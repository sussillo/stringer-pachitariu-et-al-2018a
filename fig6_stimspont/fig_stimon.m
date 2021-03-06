function fig_stimon(stimtpt,ip)
if nargin==1
    ip=1;
end
    
plot(stimtpt,'k','linewidth',1);
text(0.5,1,'visual stimuli','horizontalalignment','center','fontsize',8);
hold all;
if ip
plot(1 + [0 60*5*3],-.75 * [1 1],'k','linewidth',2);
text(0.06,-.1,'5 min','horizontalalignment','center','fontsize',8,'fontweight','bold','fontangle','normal');
end
axis tight;
axis off;
