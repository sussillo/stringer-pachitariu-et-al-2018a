function results = sharedVariance(dataroot, matroot, useGPU)

load(fullfile(dataroot,'dbstimspont.mat'));

clear results;
%
rng('default');

%%
for d = 1:length(dbs)
    db = dbs(d);
    dat = load(fullfile(dataroot,...
        sprintf('stimspont_%s_%s.mat',db.mouse_name,db.date)));
    
    %
    if isfield(dat.stat, 'redcell')
        redcell = logical([dat.stat.redcell]);
    else
        redcell = false(numel(dat.stat), 1);
    end
    gcell = ~redcell(:);
    
    % spontaneous activity data
    x = dat.beh.face.motionSVD;
    
    % some videos may not have captured - if so there are nan's
    tnoface = isnan(x(:,1));
    
    % spontaneous activity
    % ~dat.stimtpt
    x = x(~dat.stimtpt & ~tnoface,:);
    y = dat.Fsp(gcell, ~dat.stimtpt & ~tnoface);
    
    [NN NT] = size(y);
    fprintf('recording %d\n',d);

    % subtract mean and divide by std before binning
    ysub = mean(y,2);
    ystd = 1e-6 + std(y,1,2);
    y    = (y - ysub)./ystd;
    
    % bin spikes and behavior in 1.2 second bins
    if dbs(d).nplanes == 10
        tbin = 4;
    else
        tbin = 3;
    end

    x    = bin2d(x, tbin, 1);
    x    = x';
    y    = bin2d(y, tbin, 2);
    
    % take SVD of neural activity
    if useGPU
        [u s v] = svdecon(gpuArray(single(y)));
    else
        [u s v] = svdecon(single(y));
    end
    ncomps  = 128;
    u       = gather_try(u(:, 1:ncomps));
    v       = u' * y;
    
    NT = size(y,2);
    Lblock = round(75);
    fractrain = 0.5;
    [indtrain, indtest] = splitInterleaved(NT, Lblock, fractrain,1);
        
    %% compute face to neural vectors during spontaneous periods
    % low rank regression
    % best with a time delay of 1 frame
    [a, b] = CanonCor2(y(:,1:end-1)', x(:,2:end)', 2e3);
    % face vectors
    uFace = normc(a(:,1:32));
    
    % spont vectors
    uSpont = u(:,1:32);
    
    %% compute stimulus vectors
    istim = dat.stim.istim;
    sresp = dat.stim.resp(:, gcell);
    
    yall = dat.Fsp(gcell,:);
    
    % subtract mean and std from spont
    sresp = (sresp - ysub')./ystd';
    yall  = (yall  - ysub) ./ystd;
    
    % split stimulus responses into 3 blocks
    % nstims x neurons x 3 (nstims=33 where 33 is spont)
    A = compute_means(istim, sresp, 3, 1);
    
    % stimulus vectors
    sm = mean(A(1:end-1,:,[2 3]),3); % mean on train blocks
    
    % stimulus projection
    sproj = normc(sm')' * yall;
    
    % face projection
    tproj = uFace' * yall;

%     
%     %%
%     clf;
%     for j = 1:size(A,1)-1
%         T = sproj(j,:);
%         %         T = my_conv2(T, 1, 2);
%         plot(-j*6 + zscore(T), 'linewidth', 1)
%         hold all
%     end
%     
%     for j = 1:10
%         T = tproj(j,:);
%         %         T = my_conv2(T, 1, 2);
%         plot(-size(A,1)*6-j*6 + zscore(T), 'k', 'linewidth', 1)
%         hold all
%     end
%     
%     axis tight
%     box off
%     set(gcf,'color','w');
%     drawnow;
        
    %% compute spont/face projection and compare to stims
    
    usub{1} = uFace;
    usub{2} = uSpont;
    rbin = bin2d(dat.beh.runSpeed(~tnoface,1),tbin,1);
    fbin = bin2d(dat.beh.face.motionSVD(~tnoface,1),tbin,1);
    ybin = bin2d(yall(:,~tnoface),tbin,2);
    
    for ktype = 1:2
        ist = sum(sum(isnan(A(1:end-1,:,:)),3),2)==0;
        Astim = A(ist,:,:);
        
        % total stimulus variance
        Vtot = sum(sum(Astim(:,:,1).*Astim(:,:,2)));
        
        % shared stim-spont subspace
        C12 = Astim(:,:, 3) * usub{ktype};
        [Ua Sa Va] = svdecon(C12);
        
        Uproj1 = normc(Astim(:,:,3)' * Ua);
        % stim-spont space 
        Uproj2 = normc(usub{ktype} * Va);
        
        uproj = usub{ktype};
        % subtract off the first dimension of stim in spont
        uproj = uproj - Uproj1(:,1) * (Uproj1(:,1)'*uproj);
        
        clear p pshared pface;
        for i = 1:2
            % stim responses in shared stim-spont without 1D subspace
            p(:,:,i) = Astim(:, :, i)  * uproj;
            % stim responses in shared stim-spont (no subtraction)
            pshared(:,:,i) = Astim(:,:,i) * Uproj2;
        end
        
        Vp = sum(sum(p(:,:,1).*p(:,:,2)));
        
        % fraction of stimulus variance in shared stim-spont space
        results.Vshared(:,d,ktype) = (sum(pshared(:,:,1).*pshared(:,:,2),1)/Vtot)';
        
        % fraction of variance in stim-spont without top PC
        results.Vall(d,ktype) = Vp/Vtot;
        
        disp([results.Vall(d,ktype) sum(results.Vshared(:,d,ktype),1)])
                
        results.Sall(:,d,ktype) = diag(Sa);
        results.Ushared{d,ktype} = Uproj2(:,1);
        
        results.runcorr(d,ktype) = corr((Uproj2(:,1)' * ybin)', rbin);
        results.facecorr(d,ktype) = corr((Uproj2(:,1)' * ybin)', fbin);
    end
    %% example dataset
    if d == 1
        results.sstim = normc(sm');
        results.sprojF = normc(sm')' * yall;
        
        for ktype=1:2
            results.tprojF{ktype} = usub{ktype}' * yall;
            
            % subtract shared dimension
            ushared = results.Ushared{d,ktype};
            stimsub = results.sstim - ushared * (ushared'*results.sstim);
            spontsub = usub{ktype} - ushared * (ushared'*usub{ktype});
            
            
            results.sprojS{ktype} = stimsub' * yall;
            results.tprojS{ktype} = spontsub' * yall;
            
            results.tshared{ktype} = ushared' * yall;
        end
        results.runspeed = dat.beh.runSpeed;
    end
    
    
end

%%

save(fullfile(matroot,'stimvar.mat'),'-struct','results');















