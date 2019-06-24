function [ tf ] = are_different2( m, s, threshold )
% ARE_DIFFERENT2() - Assess whether two TransactiveRecord messages,
% representing the calculated and sent messages in an active time interval
% are significantly different from one another. If the signals are
% different, this indicates that local conditions have changed, and a
% revised, updated transactive message shoudl be sent to the Neighbor.
%
% INPUTS:
% m - TransactiveRecord message representing the mySignal, the last
%     message calculated for this transactiveNeighbor.
% s - TransactiveRecord messge representing the sentSignal, the last
%     message that was sent to this transactive Neighbor.
% threshold - a dimensionless, relative error that is used as a convergence
%             criterion.
%
% OUTPUTS:
% tf - Boolean: true if the sent and recently calculated transactive
%      messages are significantly different.

%[180904DJH: THE TWO SIGNAL SETS MUST BE DIFFERENT IF THEY HAVE DIFFERENT
%NUMBERS OF RECORDS:
    if length(s) ~= length(m)
        tf = true;
        return;
    end

    if length(s) == 1 || length(m) == 1
        
%       Either the sent or calculated message is a constant, (i.e., one
%       Vertex) meaning its marginal price is probaly NOT meaningful. Use
%       only the power in this case to determine whether they differ.
%       Pick out the scheduled values (i.e., Record 0) from mySignal and
%       sentSignal records.
        m0 = m([m.record] == 0);
        s0 = s([s.record] == 0);
        
%       Calculate the difference dq between the scheduled powers in the two
%       sets of records.         
        dq = abs(m0.power - s0.power);                          % [avg.kW]
        
%       Calculate the average scheduled power avg_q of the two sets of
%       records.         
        avg_q = 0.5 * abs(m0.power + s0.power);                 % [avg.kW]
        
%       Calculate relative distance d between the two scheduled powers.
%       Avoid the unlikely condition that the average power is zero.
        if avg_q ~= 0
            d = dq / avg_q;
        else
            d = 0;
        end
        
        if d > threshold
            
%           The difference is greater than the criterion. Return true,
%           meaning that the difference is significant.
            tf = true;
            
        else
            
%           The difference is less than the criterion. Return false,
%           meaning the difference is not significant.
            tf = false;
            
        end
        
    else
        
%       There are multiple records, meaning that the Neighbor is
%       price-responsive. 

%       Pick out the records that are NOT scheduled points, i.e., are not
%       Record 0. Local convergence of the coordination sub-problem does
%       not require so much that the exact point has been determined as
%       that the flexibility is accurately conveyed to the Neighbor.        
        m0 = m([m.record] ~= 0);
        s0 = s([s.record] ~= 0); 

%       Index through the sent and calculated flexibility records. See if
%       any record cannot be matched with a corresponding member of
%       mySignal m0.
        for i = 1:length(s0)
            
            tf = true;
            
            for j = 1:length(m0)
            
%           Calculate difference dmp between marginal prices .            
            dmp = abs(s0(i).marginalPrice - m0(j).marginalPrice); % [$/kWh]
            
%           Calculate average avg_mp of marginal price pair.            
            avg_mp = 0.5*(s0(i).marginalPrice + m0(j).marginalPrice);% [$/kWh]
            
%           Calculate difference dq between power values in the two sets of
%           records.
            dq = abs(s0(i).power - m0(j).power);                   % [avg.kW]
            
%           Calculate average avg_q of power pairs in the two sets of
%           records.
            avg_q = abs(s0(i).power + m0(j).power);                   % [avg.kW]
       
%           If no pairing between the flexibility records of the two sets
%           of records can be found within the relative error criterion,
%           things must have changed locally since the transactive message
%           was last sent.
%[180904DJH-HUNG FOUND CASE WHERE AVERAGES IN DENOMINATORS BECOME ZERO. THE
%OUTCOME HAD BEEN AN UNRELIABLE CONDITIONAL WITH NAN COMPARISONS. THIS CASE
%MUST BE AVOIDED WITH THIS CODE: 
% Avoid unlikely divide-by-zero case. If the average marginal price is
% zero, it is probable they are BOTH zero:
            if avg_mp == 0
                dmp = 0;
            else
                dmp = dmp/avg_mp;
            end
% Avoid unlikely divide-by-zero case. If the average power is
% zero, it is probable they are BOTH zero:            
            if avg_q == 0
                dq = 0;
            else
                dq = dq/avg_q;
            end
            
            if sqrt(dmp^2 + dq^2) <= threshold
%[180904DJH Changed: if sqrt((dmp/avg_mp)^2 + (dq/avg_q)^2) <= threshold
                
%               No pairing was found within the relative error criterion
%               distance. Things must have changed locally since the
%               transactive message was last sent to the transactive
%               Neighbor. Set the flag true.
                tf = false;
                continue;

            end      % if sqrt((dmp/avg_mp)^2 + (dq/avg_q)^2) <= threshold)
            
            end                                      % for j = 1:length(m0)
            
            if tf == true
                return;
            end
            
        end                                          % for i = 1:length(s0)
        
    end                               % if length(s) == 1 || length(m) == 1

end                                             % FUNCTION ARE_DIFFERENT2()

