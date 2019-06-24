function view_power_series(obj,mkt)
% VIEW_POWER_SERIES() - visualize power in active time intervals
% obj - object owning the scheduled power time series 
% mkt - market object in which the series of active time intervals is
%       defined.

%   Gather active time series and make sure they are in chronological order
    ti = mkt.timeIntervals;
    ti = [ti.startTime];
    ti = sort(ti);
    
if isa(obj,'Market')
    tg = obj.totalGeneration;
elseif isa(obj,'NeighborModel') || isa(obj,'LocalAssetModel')
    tg = obj.scheduledPowers;
else
    warning('Object must be a NeighborModel or LocalAssetModel');
    return;
end
    tg_ti = [tg.timeInterval];
    [~,ind] = sort([tg_ti.startTime]);
    tg = tg(ind);
    tg = [tg.value]; 
    
%Add representation of total reserve in future    
%     tr = mkt.totalReserveMargin; 
    hold off;
    plot(ti,tg,'*');    
    hold on; 
    plot(ti,tg);
    title('Total Generation in Active Time Intervals');
    xlabel('time');
    ylabel('power (kW)');
    hold off;
    
end                                          % FUNCTION VIEW_POWER_SERIES()

