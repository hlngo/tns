function [ tf ] = are_different1( s, r, threshold )
% ARE_DIFFERENT1() - Returns true is two sets of TransactiveRecord objects,
% representing sent and received messages in a time interval, are
% significantly different.
% 
% INPUTS:
%   s - sent TransactiveRecord object(s) (see struct TransactiveRecord)
%   r - received TransactiveRecord object(s) 
%   threshold - relative error used as convergence criterion. Two messages
%               differ significantly if the relative distance between the
%               scheduled points (i.e., Record 0) differ by more than this
%               threshold.
%
% OUTPUS:
%   tf - Boolean: true if relative distance between scheduled (i.e., Record
%        0) (price,quantity) pairs in the two messages exceeds the
%        threshold.

%   Pick out the scheduled sent and received records (i.e., the one where
%   record = 0).
    s0 = s([s.record] == 0);                            % a TransactiveRecord
    r0 = r([r.record] == 0);                            % a TransactiveRecord

%   Calculate the difference dmp in scheduled marginal prices.
    dmp = abs(s0.marginalPrice - r0.marginalPrice);               % [$/kWh]

%   Calculate the average mp_avg of the two scheduled marginal prices. 
    mp_avg = 0.5*abs(s0.marginalPrice + r0.marginalPrice);        % [$/kWh]
    
%   Calculate the difference dq betweent the scheduled powers.   
    dq = abs(-s0.power - r0.power);                             % [avg. kW]

%   Calculate the average q_avg of the two scheduled average powers.    
    q_avg = 0.5 * abs(r0.power + -s0.power);                    % [avg. kW]

%   Calculate the relative Euclidian distance d (a relative error
%   criterion) between the two scheduled (price,quantity) points.
    if length(s) == 1 || length(r) == 1
        d = dq / q_avg;                                     % dimensionless
    else
        d = sqrt((dq / q_avg)^2 + (dmp / mp_avg)^2);        % dimensionless
    end

    if d > threshold
        
%       The distance, or relative error, between the two scheduled points
%       exceeds the threshold criterion. Return true to indicate that the
%       two messages are significantly different.
        tf = true;
        
    else
        
%       The distance, or relative error, between the two scheduled points
%       is less than the threshold criterion. Return false, meaning that
%       the two messages are not significantly different.
        tf = false;
        
    end                                                  % if d > threshold

end% FUNCTION ARE_DIFFERENT1()

