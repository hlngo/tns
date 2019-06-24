function [ cost ] = prod_cost_from_formula( obj,ti )
% PROD_COST_FROM_FORMULA() -  Calculate production cost from a quadratic
% production-cost formula
%
% This formulation allows for a quadratic cost function. Objects have cost
% parameters that allow the calculation of production cost from the power
% and these cost coefficients
%             production cost = a0 + a1*p + 0.5*a2*p^2
%
% INPUTS:
% obj - Either a NeighborModel or LocalAssetModel object
% ti - time interval (See TimeInterval class)
%
% OUTPUTS:
% cost - production cost in absolute dollars for time interval ti [$]

%   Get the object's quadratic cost coefficients
    a = obj.costParameters;

%   Find the scheduled power sp in time interval ti    
    sp = findobj(obj.scheduledPowers,'timeInterval',ti);  %An IntervalValue
    
%   Extract the scheduled-power value    
    sp = sp.value;                                                %[avg.kW]

%   Calculate the production cost from the quadratic cost formula
%   Constant term
    cost = a(1);                                                       %[$/h]
    
%   Add the first-order term    
    cost = cost + a(2) * sp;                                           %[$/h]
    
%   Add the second order term    
    cost = cost + 0.5 * a(3) * sp^2;                                   %[$/h]
    
%   Convert to absolute dollars 
%   NOTE: Matlab function hours() toggles from duration to numeric, which
%   is correct here.
    dur = ti.duration;
    if isduration(dur)
        dur = hours(dur);                % toggle from duration to numberic
    end
    cost = cost * dur;                       % interval production cost [$]

end                                      %function prod_cost_from_formula()

