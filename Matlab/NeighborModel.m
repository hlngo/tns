classdef NeighborModel < AbstractModel
%NeighborModel Base Class
% The NeighborModel manages the interface with a Neighbor object and
% represents it for the computational agent. There is a one-to-one
% correspondence between a Neighbor object and its NeighborModel object.
% Members of the transactive network must be indicated by setting the
% "transactive" property true.
 
%% New NeighborModel properties    
    properties
        converged = false
        convergenceFlags = IntervalValue.empty         % values are Boolean
        convergenceThreshold = 0.01                           % [0.01 = 1%]
        demandMonth = month(datetime)       % used to re-set demand charges
        demandRate = 10                                     % [$ / kW (/h)]
        demandThreshold = 1e9;      % power that causes demand charges [kW]
        effectiveImpedance = 0.0                      % Ohms for future use
        friend = false       % friendly Neighbors might get preferred rates
        mySignal = TransactiveRecord.empty  % current records ready to send 
        receivedSignal = TransactiveRecord.empty    % last records received
        % NOTE: Realized late that sentSignal is needed as part of the
        % event-driven timing of the system. This allows a comparison
        % between a recent calculation (mySignal) and the last calculation
        % that was revealed to the Neighbor (sentSignal).
        sentSignal = TransactiveRecord.empty            % last records sent
        transactive = false        
    end                                      % New NeighborModel properties
    
%% NeighborModel methods    
    methods

%% FUNCTION CALCULATE_RESERVE_MARGIN()
function calculate_reserve_margin(obj,mkt)
% CALCULATE_RESERVE_MARGIN() - Estimate the spinning reserve margin
% in each active time interval
%
% RESERVE MARGIN is defined here as additional generation or reduced
% consumption above the currently scheduled power. The intention is for
% this to represent "spinning-reserve" power that can be available on short
% notice. 
%
% For now, this quantity will be tracked. In the future, treatment of
% resource commitment may allow meaningful control of reserve margin and
% the resiliency that it supports.
%
% PRESUMPTIONS:
%   - time intervals are up-to-date
%   - scheduled power is up-to-date
%   - the active vertices are up-to-date and correct. One of the vertices
%     represents the maximum power that is available on short notice (i.e.,
%     "spinning reserve") from this neighbor.
%
%INPUTS:
%   obj - Neighbor model object
%   mkt - Market object
%
%OUTPUTS:
%   - updated obj.reserveMargins

%   Gather active time intervals ti
    time_intervals = mkt.timeIntervals;

%   Index through active time intervals ti
    for i = 1:length(time_intervals)
        
%       Find the maximum available power from among the active vertices in
%       the indexed time interval, one of which must represent maximum
%       power
        maximum_power = findobj(obj.activeVertices,'timeInterval',...
            time_intervals(i));                     % IntervalValue objects

        if isempty(maximum_power)
            
%           No active vertex was found. The hard constraint must be used.
            maximum_power = obj.object.maximumPower; 
                                                 % hard constraint [avg.kW]
            
        else
            
%           A vertex was found. Extract its power value.            
            maximum_power = [maximum_power.value];        % Vertice objects
            maximum_power = [maximum_power.power];   % real powers [avg.kW]
            maximum_power = max(maximum_power);    % maximum power [avg.kW]
 
%           Check that the operational maximum from vertices does not
%           exceed the hard physical constraint. Use the smaller of the
%           two.
            maximum_power = min(maximum_power, obj.object.maximumPower);
            
        end
        
%       Find the scheduled power for this asset in the indexed time
%       interval
        scheduled_power = findobj(obj.scheduledPowers,'timeInterval',...
            time_intervals(i));                          % an IntervalValue
        scheduled_power = scheduled_power.value; % scheduled power [avg.kW]
        
%       The available reserve margin is calculated as the difference
%       between the maximum and scheduled powers. Make sure the value is
%       not less than zero.
        value = max(0, maximum_power-scheduled_power); 
                                                  % reserve margin [avg.kW]
        
%       Check whether a reserve margin exists in the indexed time interval.
        interval_value = findobj(obj.reserveMargins,'timeInterval',...
            time_intervals(i));                          % an IntervalValue
 
        if isempty(interval_value)
            
%           No reserve margin was found for the indexed time interval.
%           Create a reserve margin interval for the calculated value 
            interval_value = IntervalValue(obj,time_intervals(i),mkt,...
                'ReserveMargin',value);                  % an IntervalValue
            
%           Append the reserve margin interval value to the list of
%           reserve margins.
            obj.reserveMargins = [obj.reserveMargins,interval_value];   
                                                    % IntervalValue objects
  
        else
            
%           The reserve margin interval value already exists, simply
%           reassign its value.
            interval_value.value = value;                        % [avg.kW]
            
        end                                    % if isempty(interval_value)
        
    end                                  % for i = 1:length(time_intervals)
    
end                                   % FUNCTION CALCULATE_RESERVE_MARGIN()
  
%% FUNCTION CHECK_FOR_CONVERGENCE()       
function check_for_convergence(mdl,mkt)
% CHECK_FOR_CONVERGENCE() - qualifies state of convergence with a
% transactive Neighor object by active time interval and globally.
%
% In respect to the coordination sub-problem, a Neighbor is not converged
% for a given time interval and a signal should be sent to the transactive
% Neighbor if
%   - The balancing and scheduling sub-problems are converged, AND
%   - No signal has been sent, OR
%   - A signal has been received from the Neighbor, and no signal has been
%     sent since the signal was received, but scheduled power and marginal
%     price in the sent and received signals (i.e., Records 0) differ, OR
%   - A timer has elapsed since the last time a signal was sent, and the
%     sent signal differs from one that would be sent again, based on 
%     current conditions.
%
% Inputs:
%   mdl - transactive NeighborModel model
%   mkt - Market object
%
% Uses property convergenceThreshold as a convergence criterion.
%
% Compares TransactiveRecord messages in mySignal, sentSignal, and
%   receivedSignal.
%
% Updates properties convergenceFlags and converged based on comparison of
%   calculated, received, and sent TransactiveRecord messages.

% NOTE: this method should not be called unless the balancing sub-problem
% and all the scheduling sub-problems have been calculated and have
% converged.

%   Gather active time intervals.
    time_intervals = mkt.timeIntervals;
   
%   Index through active time intervals to assess their convergence status.    
    for i = 1:length(time_intervals)

%       Capture the current datetime in the same format as for the
%       TransactiveRecord messages.
        dt = datetime('now','Format', 'yyMMdd:HHmmss');        
        
%       Initialize a flag true (converged) in this time interval until
%       proven otherwise.
        flag = true;
        
%       Find the TransactiveRecord objects sent from the transactive
%       Neighbor in this indexed active time interval. Create a logical
%       array ss, true if the received TransactiveRecord is in the indexed
%       active time interval. Then reassign ss as the targeted
%       TransactiveRecords themselves.
        ss = ismember({mdl.sentSignal.timeInterval},...
            time_intervals(i).name);                     % a logical vector
        ss = mdl.sentSignal(ss); % TransactiveRecord message in the indexed
                                 % TimeStamp
        
%       If a sent signal message was found in the indexed time interval,
%       its timestamp ss_ts is the last time a message was sent. Otherwise,
%       set the ss_ts to the current time dt.
        if ~isempty(ss)
            ss_ts = ss([ss.record] == 0).timeStamp;  % last time message sent
            ss_ts = datetime(ss_ts,'Format','yyMMdd:HHmmss');
        else
            ss_ts = dt;
        end                                               % if ~isempty(ss)

%       Same as above, but now for received TransactiveRecord message rs in the
%       indexed active time interval.
        rs = ismember({mdl.receivedSignal.timeInterval},...
            time_intervals(i).name);                 % an array of logicals
        rs = mdl.receivedSignal(rs); % TransactiveRecords received in the 
                                     % indexed TimeInterval
        
%       As above, if TransactiveRecords have been received, use the
%       timestamp as the last time the signal was recieved rs_ts.
%       Otherwise, use the current time instead.
        if ~isempty(rs)
            rs_ts = rs([rs.record] == 0).timeStamp; % Time message received.
            rs_ts = datetime(rs_ts,'Format','yyMMdd:HHmmss');
        else
            rs_ts = dt;
        end  
        
%       Same as above, but now for calculated, prepared TransactiveRecord
%       message ms in the indexed active time interval.
        ms = ismember({mdl.mySignal.timeInterval},...
            time_intervals(i).name);                 % an array of logicals
        ms = mdl.mySignal(ms); % TransactiveRecords prepared in the 
                                     % indexed TimeInterval 
                                     
        if ~isempty(ms)
%[180829DJH: minor bug found and corrected in this next line that had
%mistakenly referred to "rs.record" instead of "ms.record"]
            ms_ts = ms([ms.record] == 0).timeStamp; % Time message received.
            ms_ts = datetime(ms_ts,'Format','yyMMdd:HHmmss');
        else
            ms_ts = dt;
        end                                       
        
%       Now, work through the convergence criteria.        
        if isempty(ss) 
            
%           No signal has been sent in this time interval. This is the
%           first convergence requirement. Set the convergence flag false.
            flag = false;
            
        elseif ~isempty(rs) ...    % received TransactiveRecord(s) received
            && rs_ts > ss_ts ...                 % received AFTER last sent
            && are_different1(ss,rs,mdl.convergenceThreshold)   % different
            
%           One or more TransactiveRecord objects has been received in the
%           indexed time interval and it has been received AFTER the last
%           time a message was sent. These are preconditions for the second
%           convergence requirement. Function are_different1() checks
%           whether the sent and received signals differ significantly. If
%           all these conditions are true, the Neighbor is not converged.
            flag = false;

        elseif dt - ss_ts > Hours(1/12) ...   % Delay 5 min after last send
                && are_different2(ms,ss,mdl.convergenceThreshold)
            
%           More than 5 minutes have passed since the last time a signal
%           was sent. This is a precondition to the third convergence
%           criterion. Function are_different2() returns true if mySignal
%           (ms) and the sentSignal (ss) differ significantly, meaning that
%           local conditions have changed enough that a new, revised signal
%           should be sent.
            flag = false;
            
        end                                                % if isempty(ss)

%       Check whether a convergence flag exists in the indexed time
%       interval.
        iv = findobj(mdl.convergenceFlags,'timeInterval',...
            time_intervals(i));
        
        if isempty(iv)
            
%           No convergence flag was found in the indexed time interval.
%           Create one and append it to the list.
            iv = IntervalValue(mdl,time_intervals(i),mkt,...
                'ConvergenceFlag',flag);
            mdl.convergenceFlags = [mdl.convergenceFlags,iv]; 
            
        else
            
%           A convergence flag was found to exist in the indexed time
%           interval. Simply reassign it.
            iv.value = flag;
            
        end                                                % if isempty(iv)

    end                                  % for i = 1:length(time_intervals)
 
%   If any of the convergence flags in active time intervals is false, the
%   overall convergence flag should be set false, too. Otherwise, true,
%   meaning the coordination sub-problem is converged with this Neighbor.
%[180829DJH: This next code trims the length of flags to correspond with
%active time intervals. Without this line, the flags might accumulate
%indefinitely.]  
    mdl.convergenceFlags = findobj(mdl.convergenceFlags,'timeInterval',...
            time_intervals);
    
%[180829DJH: Corrected this next line that had used function "any()" 
%instead of "all()".]
    if all([mdl.convergenceFlags.value] == true)
        mdl.converged = true;
    else
        mdl.converged = false;
    end
    
end                                      % FUNCTION CHECK_FOR_CONVERGENCE()

%% FUNCTION MARGINAL_PRICE_FROM_VERTICES()
function [marginal_price] = marginal_price_from_vertices(~,power,vertices)
% FUNCTION MARGINAL_PRICE_FROM_VERTICES() - Given a power, determine the
% corresponding marginal price from a set of supply- or demand-curve
% vertices.
%
% INPUTS:
% power - scheduled power [avg.kW]
% vertices - array of supply- or demand-curve vertices
%
% OUTPUTS:
% mp - a marginal price that corresponds to p [$/kWh]

%   Sort the supplied vertices by power and marginal price.
    vertices = order_vertices(vertices);

%   number of supplied vertices len    
    len = length(vertices);

    if power < vertices(1).power
        
%       The power is below the first vertex. Marginal price is
%       indeterminate. Assign the marginal price of the first vertex,
%       create a warning, and return. (This should be an unlikely
%       condition.)
%         warning('power was lower than first vertex');
        marginal_price = vertices(1).marginalPrice;         % price [$/kWh]
        return;  
        
    elseif power >= vertices(len).power
        
%       The power is above the last vertex. Marginal price is
%       indeterminate. Assign the marginal price of the last vertex, create
%       a warning, and return. (This should be an unlikely condition.)
%         warning('power was greater than last vertex');
        marginal_price = vertices(len).marginalPrice;    % price [$/kWh]
        return;
        
    end                                      % if power < vertices(1).power

%   There are multiple vertices v. Index through them.  
    for i = 1:(len-1)
        
        if power >= vertices(i).power && power < vertices(i+1).power
            
%           The power lies on a segment between two defined vertices.  

            if vertices(i).power == vertices(i+1).power
                
%               The segment is horizontal. Marginal price is indefinite.
%               Assign the marginal price of the second vertex and return.
                warning('segment is horizontal');
                marginal_price = vertices(i+1).marginalPrice;
                return;
                
            else
                
%               The segment is not horizontal. Interpolate on the segment.
%               First, determine the segment's slope.
                slope = (vertices(i+1).marginalPrice ...
                    - vertices(i).marginalPrice) ...
                    / (vertices(i+1).power - vertices(i).power); 
                                                               % [$/kWh/kW]
                
%               Then interpolate to find marginal price.                
                marginal_price = vertices(i).marginalPrice ...
                    + (power - vertices(i).power) * slope;        % [$/kWh]
                return;
                
            end               % if vertices(i).power == vertices(i+1).power
            
        end  % if power >= vertices(i).power && power < vertices(i+1).power
    
    end                                                   % for i = 1:len-1
    
end                               % FUNCTION MARGINAL_PRICE_FROM_VERTICES()

%% FUNCTION PREP_TRANSACTIVE_SIGNAL()
function prep_transactive_signal(tnm,mkt,mtn)
% PREP_TRANSACTIVE_SIGNAL() - Prepare transactive records to send
% to a transactive neighbor. The prepared transactive signal should
% represent the residual flexibility offered to the transactive neighbor in
% the form of a supply or demand curve. 
% NOTE: the flexibility of the prepared transactive signals refers to LOCAL
% value. Therefore this method does not make modifications for power losses
% or demand charges, both of which are being modeled as originating with
% the RECIPIENT of power.
% FUTURE: The numbers of vertices may be restricted to emulate various
% auction mechanisms.
%
% ASSUMPTIONS:
%   - The local system has converged, meaning that all asset and neighbor
%     powers have been calculated
%   - Neighbor and asset demand and supply curves have been updated and are
%     accurate. Active vertices will be used to prepare transactive
%     records.
%
% INPUTS:
% tnm - Transactive NeighborModel object - target node to which a
%       transactive signal is to be sent
% mkt - Market object
% mtn - myTransactiveNode object
%
% OUTPUTS:
%   - Updates mySignal property, which contains transactive records that
%     are ready to send to the transactive neighbor

%   Ensure that object tnm is a transactive neighbor object.
    if ~isa(tnm,'NeighborModel') 
        warning('must be a neighbor model object');
        return;
    elseif tnm.transactive ~= true
        warning('NeighborModel must be transactive');
        return;
    end                                      % if ~isa(tnm,'NeighborModel')

%   Gather active time intervals.    
    time_intervals = mkt.timeIntervals;       % active TimeInterval objects
    
%[180830DJH: ENSURE THAT mySignal PROPERTY IS TRIMMED TO CONTAIN SIGNALS
%FROM ONLY THE ACTIVE TIME INTERVALS USING THIS NEXT LINE.]
%     tnm.mySignal = findobj(tnm.mySignal,'timeInterval',time_intervals);
    
%   Index through active time intervals.   
    for i = 1:length(time_intervals)
        
%       Keep only the transactive records that are NOT in the indexed time
%       interval. The ones in the indexed time interval shall be recreated
%       in this iteration.
        index =  ~ismember({tnm.mySignal.timeInterval},time_intervals(i).name);  
                                                           % a logical aray
        tnm.mySignal = tnm.mySignal(index);           % transactive records
        
%       Create the vertices of the net supply or demand curve, EXCLUDING
%       this transactive neighbor (i.e., "tnm"). NOTE: It is important that
%       the transactive neighbor is excluded.
        vertices = mkt.sum_vertices(mtn,time_intervals(i),tnm);  % Vertices
        
%       Find the minimum and maximum powers from the vertices. These are
%       soft constraints that represent a range of flexibility. The range
%       will usually be excessively large from the supply side; much
%       smaller from the demand side.
        vertex_powers = [vertices.power];                        % [avg.kW]
        maximum_vertex_power = max(vertex_powers);               % [avg.kW]
        minimum_vertex_power = min(vertex_powers);               % [avg.kW]

%       Find the transactive Neighbor's (i.e., "tnm") scheduled power in
%       the indexed time interval.
        scheduled_power = findobj(tnm.scheduledPowers,'timeInterval',...
            time_intervals(i));                          % an IntervalValue
        %180712DJH - Define scheduled_power as the negative of the
        %currently scheduled power, thus reflecting it about p=0.
        scheduled_power = - scheduled_power(1).value;            % [avg.kW]
        
%       Because the supply or demand curve of this transactive neighbor
%       model was excluded, an offset is created between it and the one
%       that had included the neighbor. The new balance point is mirrored
%       equal to, but of opposite sign from, the scheduled power.
% 180712DJH - omit variable "offset" and all references to it.
%        offset = -2 * scheduled_power;                          % [avg.kW]
        
%% Record #0: Balance power point    
%       Find the marginal price of the modified supply or demand curve that
%       corresponds to the balance point.
        try
            %[180712DJH - find marginal price at reflected scheduled power
            %value without using "offset."]
            %[180830DJH: NEW CONDITIONAL ENSURES THAT A LONE REMNANT VERTEX
            %HAS ITS MARGINAL PRICE SET TO INFINITY.]
            if length(vertices) == 1
                marginal_price_0 = inf;
            else
                marginal_price_0 = ...
                    tnm.marginal_price_from_vertices(scheduled_power, ...
                    vertices);
            end
        catch
            warning('erros/warnings with object %s',tnm.name);
        end
        
%       Create transactive record #0 to represent that balance point, and
%       populate its properties.
%       NOTE: A TransactiveRecord constructor is being used.
% 180712DJH - Use the reflected scheduled power in the transactive record
% without "offset."
        transactive_record = TransactiveRecord( ...
            time_intervals(i), ...
            0, ...
            marginal_price_0, ...
            scheduled_power);

%       Append the transactive signal to those that are ready to be sent.            
        tnm.mySignal = [tnm.mySignal,transactive_record];   

        if length(vertices) > 1
            
%% Transactive Record #1: Minimum neighbor power
%       Find the minimum power. For transactive neighbors, the minimum may
%       be based on the physical constraint of the line between neighbors.
%       A narrower range may be used if the full range is infeasible. For
%       example, it might not be feasible for a neighbor to change from a
%       power importer to exporter, given it limited generation resources.
%       NOTE: Power is a signed quantity. The maximum power may be 0 or
%       even negative.
% 180712DJH - use reflected value of maximumPower as minimum_power.
        minimum_power = - tnm.object.maximumPower;         % power [avg.kW]
% 180712DJH - don't offset the minimum_vertex_power using "offset."
        minimum_power = max(minimum_power,minimum_vertex_power);
        
%       Find the marginal price on the modified net supply or demand curve
%       that corresponds to the minimum power, plus its offset.
% 180712DJH - Find the marginal price at the new, reflected minimum-power
% value without using "offset."
        marginal_price_1 = ...
            tnm.marginal_price_from_vertices(minimum_power,vertices);                    % marginal price [$/kWh]

%       Create transactive record #1 to represent the minimum power, and
%       populate its properties.
%       NOTE: A TransactiveRecord constructor is being used.
% 180712DJH - Don't offset the transactive record using "offset."
        transactive_record = TransactiveRecord( ...
            time_intervals(i), ...
            1, ...
            marginal_price_1, ...
            minimum_power);
            
%       Append the transactive signal to those that are ready to be sent.
        tnm.mySignal = [tnm.mySignal,transactive_record];         
       
%% Transactive Record #2: Maximum neighbor power
%       Find the maximum power. For transactive neighbors, the maximum may
%       be based on the physical constraint of the line between neighbors.
%       NOTE: Power is a signed quantity. The maximum power may be 0 or
%       even negative.
% 180712DJH - Reflect the neighbor's minimumPower value as the new
% maximum_power value without using "offset."
        maximum_power = - tnm.object.minimumPower;         % power [avg.kW]
% 180712 - Don't offset the maximum_vertex_power using "offset."
        maximum_power = min(maximum_power,maximum_vertex_power);
        
%       Find the marginal price on the modified net supply or demand curve
%       that corresponds to the neighbor's maximum power p, plus its
%       offset.
% 180712DJH - Calculate the marginal price at the reflected maximumm_power
% value without "offset."
        marginal_price_2 = ...
            tnm.marginal_price_from_vertices(maximum_power,vertices);                             % price [$/kWh]
                                                    
%       Create Transactive Record #2 and populate its properties.
%       NOTE: A TransactiveRecord constructor is being used.
% 180712DJH - Do not offset the transactive record power using "offset."
        transactive_record = TransactiveRecord( ...
            time_intervals(i), ...
            2, ...
            marginal_price_2, ...
            maximum_power);
      
%       Append the transactive signal to the list of transactive signals
%       that are ready to be sent to the transactive neighbor.
        tnm.mySignal = [tnm.mySignal,transactive_record]; 
                                                      % transactive records
        
%% Additional Transactive Records: Search for included vertices.
% Some of the vertices of the modified net supply or demand curve may lie
% between the vertices that have been defined. These additional vertices
% should be included to correctly convey the system's flexibiltiy to its
% neighbor.
%       Create record index counter index. This must be incremented before
%       adding a transactive record.
        index = 2;
        
%       Index through the vertices of the modified net supply or demand
%       curve to see if any of their marginal prices lie within the
%       vertices that have been defined for this neighbor's miminum power
%       (at marginal_price_1) and maximum power (at marginal_price_2).
        for j = 1:(length(vertices)-1)
            
            if vertices(j).marginalPrice > marginal_price_1 ...
                    && vertices(j).marginalPrice < marginal_price_2
                
%               The vertex lies in the range defined by this neighbor's
%               minimum and maximum power range and corresponding marginal
%               prices and should be included.

%               Create a new transactive record and assign its propteries.
%               See struct TransactiveRecord. NOTE: The vertex already
%               resided on the modified net supply or demand curve and does
%               not need to be offset.
%               NOTE: A TransactiveRecord constructor is being used.
                    index = index + 1;      % new transactive record number
                transactive_record = TransactiveRecord( ...
                    time_intervals(i), ...
                    index, ...
                    vertices(j).marginalPrice, ...
                    vertices(j).power);
            
%               Append the transactive record to the list of transactive
%               records that are ready to send.
                tnm.mySignal = [tnm.mySignal,transactive_record];
                 
            end       % if vertices(j).marginalPrice > marginal_price_1 ...
            
        end                                % for j = 1:(length(vertices)-1)
        
        end                                       % if length(vertices) > 1
  
    end                                  % for i = 1:length(time_intervals)
    
end                                    % FUNCTION PREP_TRANSACTIVE_SIGNAL()
  
%% FUNCTION RECEIVE_TRANASCTIVE_SIGNAL()
function receive_transactive_signal(obj,mtn)
% FUNCTION RECEIVE_TRANASCTIVE_SIGNAL() - receive and save transactive
% records from a transactive Neighbor object. 
% (NOTE: In the Matlab implementation, the transactive signals are
% "received" via a readable csv file.)
% mtn = myTransactiveNode object
% obj - the NeighborModel object
%
% The process of receiving a transactive signal is emulated by reading an
% available text table that is presumed to have been created by the
% transactive neighbor. This process may change in field settings and using
% Python and other code environments.
  
% If trying to receive a transactive signal from a non-transactive neighbor,
% create a warning and return.
    if obj.transactive == false
        warning(['Transactive signals are not expected to be received', ...
            'from non-transactive neighbors. No signal is read.']);
        return;
    end                                       % if obj.transactive == false
    
%   Here is the format for the preferred text filename. (NOTE: The name is
%   applied by the transactive neighbor and is not under the direct control
%   of myTransactiveNode.)
%   The filename starts with a shortened name of the originating node.
    source_node = char(obj.object.name);
    if length(source_node) > 5
        source_node = source_node(1:5);
    end                                                % if length(src) > 5
    
%   Shorten the name of the target node
    target_node = char(mtn.name);
    if length(target_node) > 5
        target_node = target_node(1:5);
    end                                                % if length(tgt) > 5
    
%   Format the filename. Do not allow spaces.
    filename = strcat([source_node,'-',target_node,'.txt']);
    filename = replace(filename,' ','');
    
%   Read the signal, a set of csv records 
    try
        T = readtable(filename);
    catch
        warning(['no signal file found for ',obj.name,'.']);
        return;
    end
    
    [r,~] = size(T);
    
    T = table2struct(T);

%   Extract the interval information into transactive records.
%   NOTE: A TransactiveRecord constructor is being used.
    for i = 1:r
        transative_record = TransactiveRecord( ...
            T(i).TimeInterval, ...
            T(i).Record, ...
            T(i).MarginalPrice, ...
            T(i).Power, T(i).PowerUncertainty, ...
            T(i).Cost, ...
            T(i).ReactivePower, T(i).ReactivePowerUncertainty, ...
            T(i).Voltage, T(i).VoltageUncertainty);
        
%       Save each transactive record (NOTE: We can apply more savvy to find
%       and replace the signal later.)
        obj.receivedSignal = [obj.receivedSignal,transative_record];

    end                                                       % for i = 1:r
    
end                                 % FUNCTION RECEIVE_TRANASCTIVE_SIGNAL()

%% FUNCTION SCHEDULE_POWER()
function schedule_power(obj,mkt)
%FUNCTION SCHEDULE_POWER() Calculate power for each time interval
%
%This is a basic method for calculating power generation of consumption in
%each active time interval. It infers power
%generation or consumption from the supply or demand curves that are
%represented by the neighbor's active vertices in the active time
%intervals.
%
%This strategy should is anticipated to work for most neighbor model
%objects. If additional features are needed, child neighbor models must be
%created and must redefine this method.
%
%PRESUMPTIONS: 
%   - All active vertices have been created and updated.
%   - Marginal prices have been updated and exist for all active intervals.
%
%INPUTS:
%   obj - Local asset model object
%   mkt - Market object
%
%OUTPUTS:
%   updates array obj.scheduledPowers

%   Gather the active time intervals ti
    time_intervals = mkt.timeIntervals;              % TimeInterval objects
    
%   Index through active time intervals ti
    for i = 1:length(time_intervals)
        
%       Find the marginal price for the indexed time interval
        marginal_price = findobj(mkt.marginalPrices,'timeInterval',...
            time_intervals(i));                          % an IntervalValue
        
%       Extract its marginal price value
        marginal_price = marginal_price(1).value;                                          %[$/kWh]
        
%       Find the power that corresponds to the marginal price according
%       to the set of active vertices in the indexed time interval.
%       Function Production() works for any power that is determined by
%       its supply curve or demand curve, as represented by the object's
%       active vertices.
        value = production(obj, marginal_price, time_intervals(i)); 
                                                                % [avg. kW]
        
%       Check to see if a scheduled power already exists in the indexed
%       time interval
        interval_value = findobj(obj.scheduledPowers,'timeInterval',...
            time_intervals(i));                          % an IntervalValue

        if isempty(interval_value)
            
%           No scheduled power was found in the indexed time interval.
%           Create the interval value and assign it the scheduled power
            interval_value = IntervalValue(obj,time_intervals(i),mkt,...
                'ScheduledPower',value);                 % an IntervalValue
            
%           Append the scheduled power to the list of scheduled powers
            obj.scheduledPowers = [obj.scheduledPowers,interval_value]; 
                                                    % IntervalValue objects

        else
            
%           A scheduled power already exists in the indexed time interval.
%           Simply reassign its value.
            interval_value(1).value = value;                    % [avg. kW]
            
        end                                    % if isempty(interval_value)
 
    end                                              % for i = 1:length(ti)

end                                             % FUNCTION SCHEDULE_POWER()

%% FUNCTION SCHEDULE_ENGAGEMENT()
function schedule_engagement(~,~)
% SCHEDULE_ENGAGEMENT() - required from AbstractModel, but not particularly
% useful for any NeighborModel.
    return;
end

%% FUNCTION SEND_TRANSACTIVE_SIGNAL()
function send_transactive_signal(obj,mtn)
% SEND_TRANSACTIVE_SIGNAL() - send transactive records to a transactive
% Neighbor.
% (NOTE: In the Matlab implementation, "sending" is the creation of a csv
% file that could be made available to the transactive Neighbor.)
%
% Retrieves the current transactive records, formats them into a table, and
% "sends" them to a text file for the transactive neighbor. The property
% mySignal is a storage location for the current transactive records, which
% should capture at least the active time intervals' local marginal prices
% and the power that is scheduled to be received from or sent to the
% neighbor.
% Records can also capture flex vertices for this neighbor, which are the
% supply or demand curve, less any contribution from the neighbor.
% Transactive record #0 is the scheduled power, and other record numbers
% are flex vertices. This approach anticipates that transactive signal
% might not include all time intervals or replace all records. The neighbor
% similarly prepares and sends transactive signals to this location.
% obj - NeighborModel object
% mtn - myTransactiveNode object

%   If neighbor is non-transactive, warn and return. Non-transactive
%   neighbors do not communicate transactive signals.
    if obj.transactive == false
        warning(['Non-transactive neighbors do not send transactive ',...
            'signals. No signal is sent to',obj.name,'.']);
        return
    end                                       % if obj.transactive == false
    
%   Collect current transactive records concerning myTransactiveNode.
    tr = obj.mySignal;
    
%   Number of records in mySignal len 
    len = length(tr);
    
    if isempty(tr)                     %No signal records are ready to send
        
        warning(['No transactive records were found. No transactive ', ...
            'signal can be sent to ',obj.name,'.']);
        
        return;
        
    end                                                                 %if
    
%   Gather table column contents. 
%   NOTE: Matlab became confused when similar names were being used among
%   records and table column names. Can this be completed without indexing?
%   Especially string data tends to become concatenated when it should not.
    for i = 1:len
        TS(i) = string(tr(i).timeStamp);
        TI(i) = string(tr(i).timeInterval);
        RC(i) = tr(i).record;
        MP(i) = tr(i).marginalPrice;
        PR(i) = tr(i).cost;
        PW(i) = tr(i).power;
        PWU(i) = tr(i).powerUncertainty;
        RP(i) = tr(i).reactivePower;
        RPU(i) = tr(i).reactivePowerUncertainty;
        V(i) = tr(i).voltage;
        VU(i) = tr(i).voltageUncertainty;
    end                                                     % for i = 1:len

%   Reassign column vector names as will be used in table.    
    TimeStamp = TS';
    TimeInterval = TI';
    Record = RC';
    MarginalPrice = MP';
    Cost = PR';
    Power = PW';
    PowerUncertainty = PWU';
    ReactivePower = RP';
    ReactivePowerUncertainty = RPU';
    Voltage = V';
    VoltageUncertainty = VU';   
    
%   Create the data table of transactive records that are ready to send.
%   The records are the rows of this table. NOTE: Matlab provides functions
%   to convert tables to arrays or structs.
    T = table( ... 
        TimeStamp, TimeInterval, ...
        Record, ...
        MarginalPrice,  ...
        Power, ...
        PowerUncertainty, Cost, ...
        ReactivePower, ReactivePowerUncertainty, ...
        Voltage, VoltageUncertainty);

%   Send the signal. For this Matlab version, the sending is emulated by
%   creating a table file that could be read by another active process.
    
%   Generate a meaningful filename from source node name src and target
%   node name tgt. 
    source_node = char(mtn.name);
    if length(source_node) > 5
        source_node = source_node(1:5);
    end                                                % if length(src) > 5
    
    target_node = char(obj.object.name);
    if length(target_node) > 5
        target_node = target_node(1:5);
    end                                                % if length(tgt) > 5
    
%   Format the output filename.    
    filename = strcat([source_node,'-',target_node,'.txt']);
    
%   Eliminate any spaces found in the source and target node names.    
    filename = replace(filename,' ','');
    
%   And write the table
    writetable(T,filename);
    
%   Save the sent TransactiveRecord messages (i.e., sentSignal) as a copy
%   of the calculated set that was drawn upon by this method (i.e.,
%   mySignal).
    obj.sentSignal = obj.mySignal;

end                                    % FUNCTION SEND_TRANSACTIVE_SIGNAL()

%% FUNCTION UPDATE_DC_THRESHOLD()
function update_dc_threshold(obj,mkt)
% UPDATE_DC_THRESHOLD() - keep track of the month's demand-charge threshold
% obj - BulkSupplier_dc object, which is a NeighborModel
% mkt - Market object
%
% Pseudocode:
% 1. This method should be called prior to using the demand threshold. In
%    reality, the threshold will change only during peak periods.
% 2a. (preferred) Read a meter (see MeterPoint) that keeps track of an
%     averaged power. For example, a determinant may be based on the
%     average demand in a half hour period, so the MeterPoint would ideally
%     track that average.
% 2b. (if metering unavailable) Update the demand threshold based on the
%     average power in the current time interval.
        
%   Find the MeterPoint object that is configured to measure average demand
%   for this NeighborModel. The determination is based on the meter's
%   MeasurementType.
    mtr = findobj(obj.meterPoints,'MeasturementType',...
        MeasurementType('average_demand_kW'));        % a MeterPoint object
        
    if isempty(mtr)
        
%       No appropriate MeterPoint object was found. The demand threshold
%       must be inferred.

%       Gather the active time intervals ti and find the current (soonest)
%       one.
        ti = [mkt.timeIntervals];
        [~,ind] = sort([ti.startTime]);
        ti = ti(ind);       % ordered time intervals from soonest to latest
        
%       Find current demand d that corresponds to the nearest time
%       interval.
        d = findobj(obj.scheduledPowers,'timeInterval',ti(1));   % [avg.kW]
       
%       Update the inferred demand.
        obj.demandThreshold = max([0,obj.demandThreshold,d(1).value]);
                                                                 % [avg.kW]

    else 
        
%       An appropriate MeterPoint object was found. The demand threshold
%       may be updated from the MeterPoint object.

%       Update the demand threshold.
        obj.demandThreshold = max([0,obj.demandThreshold,...
            mtr(1).currentMeasurement]);                         % [avg.kW]
        
    end                                                   % if isempty(mtr)
    
    if length(mtr) > 1

%       More than one appropriate MeterPoint object was found. This is a
%       problem. Warn, but continue.
        warning(['The BulkSupplier_dc object is associated with too ',...
            'many average-damand meters']);

    end                                                % if length(mtr) > 1
    
%   The demand threshold should be reset in a new month. First find the
%   current month number mon.
    dt = datetime; mon = month(dt);
    
    if mon ~= obj.demandMonth
        
%       This must be the start of a new month. The demand threshold must be
%       reset. For now, "resetting" means using a fraction (e.g., 80%) of
%       the final demand threshold in the prior month.
        obj.demandThreshold = 0.8 * obj.demandThreshold;
        obj.demandMonth = mon;
        
    end                                         % if mon ~= obj.demandMonth

end                                        % FUNCTION UPDATE_DC_THRESHOLD()

%% FUNCTION UPDATE_DUAL_COSTS()
function update_dual_costs(obj,mkt)
% UPDATE_DUAL_COSTS()    
    
%   Gather the active time intervals.    
    time_intervals = mkt.timeIntervals;       % active TimeInterval objects
    
%   Index through the time intervals.    
    for i = 1:length(time_intervals)
        
%       Find the marginal price mp for the indexed time interval in the
%       given market
        marginal_price = findobj(mkt.marginalPrices,'timeInterval',...
            time_intervals(i));                          % an IntervalValue
        marginal_price = marginal_price(1).value;% a marginal price [$/kWh] 
        
%       Find the scheduled power for the neighbor in the indexed time
%       interval.
        scheduled_power = findobj(obj.scheduledPowers,'timeInterval',...
            time_intervals(i));                          % an IntervalValue
        scheduled_power = scheduled_power(1).value;              % [avg.kW] 
        
%       Find the production cost in the indexed time interval.
        production_cost = findobj(obj.productionCosts,'timeInterval',...
            time_intervals(i));                          % an IntervalValue
        production_cost = production_cost(1).value;   % production cost [$]
        
%       Dual cost in the time interval is calculated as production cost,
%       minus the product of marginal price, scheduled power, and the
%       duration of the time interval.
        interval_duration = time_intervals(i).duration;
        if isduration(interval_duration)
%           NOTE: Matlab function hours() toggles duration to numeric and
%           is correct here. 
            interval_duration = hours(interval_duration); 
        end
        dual_cost = production_cost - (marginal_price * scheduled_power ...
            * interval_duration);                         % a dual cost [$]
        
%       Check whether a dual cost exists in the indexed time interval
        interval_value = findobj(obj.dualCosts,'timeInterval',...
            time_intervals(i));                          % an IntervalValue

        if isempty(interval_value)

%           No dual cost was found in the indexed time interval. Create an
%           interval value and assign it the calculated value.
            interval_value = IntervalValue(obj,time_intervals(i),mkt,...
                'DualCost',dual_cost);                   % an IntervalValue

%           Append the new interval value to the list of active interval
%           values.
            obj.dualCosts = [obj.dualCosts,interval_value];             
                                                    % IntervalValue objects

        else

%           The dual cost value was found to already exist in the indexed
%           time interval. Simply reassign it the new calculated value.
            interval_value.value = dual_cost;             % a dual cost [$]

        end                                    % if isempty(interval_value)      
        
    end                                  % for i = 1:length(time_intervals)
    
%   Ensure that only active time intervals are in the list of dual costs.
    active_dual_costs = ismember([obj.dualCosts.timeInterval],...
        time_intervals);                                  % a logical array
    obj.dualCosts = obj.dualCosts(active_dual_costs);
                                                    % IntervalValue objects
                                           
%   Sum the total dual cost and save the value
    obj.totalDualCost = sum([obj.dualCosts.value]);   % total dual cost [$]    

end                                          % FUNCTION UPDATE_DUAL_COSTS()

%% FUNCTION UPDATE_PRODUCTION_COSTS()
function update_production_costs(obj,mkt)
% UPDATE_PRODUCTION_COSTS()    
        
%   Gather active time intervals
    time_intervals = mkt.timeIntervals;       % active TimeInterval objects
    
%   Index through the active time intervals
    for i = 1:length(time_intervals)
        
%       Get the scheduled power in the indexed time interval.
        scheduled_power = findobj(obj.scheduledPowers,'timeInterval',...
            time_intervals(i));                          % an IntervalValue
        scheduled_power = scheduled_power(1).value;             %  [avg.kW]
        
%       Call on function that calculates production cost pc based on the
%       vertices of the supply or demand curve.
        production_cost = prod_cost_from_vertices(obj,time_intervals(i),...
            scheduled_power);                % interval production cost [$]
        
%       Check to see if the production cost value has been defined for the
%       indexed time interval.
        interval_value = findobj(obj.productionCosts,'timeInterval',...
            time_intervals(i));                          % an IntervalValue
            
        if isempty(interval_value)
            
%           The production cost value has not been defined in the indexed
%           time interval. Create it and assign its value pc.
            interval_value = IntervalValue(obj,time_intervals(i),mkt,...
                'ProductionCost',production_cost);       % an IntervalValue
            
%           Append the production cost to the list of active production
%           cost values.
            obj.productionCosts = [obj.productionCosts,interval_value]; 
                                                    % IntervalValue objects
            
        else
            
%           The production cost value already exists in the indexed time
%           interval. Simply reassign its value.
            interval_value.value = production_cost;   % production cost [$]
            
        end                                    % if isempty(interval_value)
        
    end                                  % for i = 1:length(time_intervals)
    
%   Ensure that only active time intervals are in the list of active
%   production costs.
    active_production_costs = ...
        ismember([obj.productionCosts.timeInterval],time_intervals); 
                                                          % a logical array
    obj.productionCosts = obj.productionCosts(active_production_costs); 
                                                    % IntervalValue objects
    
%   Sum the total production cost.
    obj.totalProductionCost = sum([obj.productionCosts.value]); 
                                                 %total production cost [$]
    
end                                    % FUNCTION UPDATE_PRODUCTION_COSTS()
  
%% FUNCTION UPDATE_VERTICES()
function update_vertices(obj,mkt)
% UPDATE_VERTICES() - Update the active vertices that define Neighbors'
% residual flexibility in the form of supply or demand curves.
%
% The active vertices of non-transactive neighbors are relatively constant.
% Active vertices must be created for new active time intervals. Vertices
% may be affected by demand charges, too, as new demand-charge thresholds
% are becoming established.
%
% The active vertices of transactive neighbors are also relatively
% constant. New vertices must be created for new active time intervals. But
% active vertices must also be checked and updated whenever a new
% transactive signal is received.
%
% PRESUMPTIONS:
%   - time intervals are up-to-date
%   - at least one default vertex has been defined, should all other
%     efforts to establish meaningful vertices fail
%
% INPUTS:
%   obj - Neighbor model object
%   mkt - Market object
%
% OUTPUTS:
%   Updates obj.activeVertices - an array of IntervalValues that contain
%       Vertex() structs 
    
%   Extract active time intervals
    time_intervals = mkt.timeIntervals;       % active TimeInterval objects
    
%   Delete any active vertices that are not in active time intervals. This
%   prevents time intervals from accumulating indefinitely.
    active_vertices = ismember([obj.activeVertices.timeInterval],...
        time_intervals);                                  % a logical array
    obj.activeVertices = obj.activeVertices(active_vertices);    
                                                    % IntervalValue objects
    
%   Index through active time intervals
    for i = 1:length(time_intervals)

%       Keep active vertices that are not in the indexed time interval, but
%       discard the one(s) in the indexed time interval. These shall be
%       recreated in this iteration. 
%       (NOTE: This creates some unnecessary recalculation that might be
%       fixed in the future.)
        active_vertices = ~ismember([obj.activeVertices.timeInterval],...
            time_intervals(i));                           % a logical array
        obj.activeVertices = obj.activeVertices(active_vertices);
                                                    % IntervalValue objects
                
%       Get the default vertices.
        default_vertices = [obj.defaultVertices];

        if isempty(default_vertices)  
            
%           No default vertices are found. Warn and return.
            warning(['At least one default vertex must be ', ...
                'defined for neighbor model object ',obj.name, ...
                '. Scheduling was not performed']);
            return
        end 

        if obj.transactive == false           % Neighbor is non-transactive           
      
%           Default vertices were found. Index through the default 
%           vertices.
            for k = 1:length(default_vertices)
                
%               Get the indexed default vertex.
                value = default_vertices(k);
                
%               Create an active vertex interval value in the indexed time
%               interval.
                interval_value = IntervalValue(obj,time_intervals(i),...
                    mkt,'ActiveVertex',value);
                
%               Append the active vertex to the list of active vertices
                obj.activeVertices = [obj.activeVertices,interval_value];
                
            end                        % for k = 1:length(default_vertices)
    
        elseif obj.transactive == true             % a transactive neighbor
            
%           Check for transactive records in the indexed time interval.       
            received_vertices = findobj([obj.receivedSignal],...
                'timeInterval',time_intervals(i).name);    
                                                % TransactiveRecord objects
            
            if isempty(received_vertices)
                
%               No received transactive records address the indexed time
%               interval. Default value(s) must be used.
                
%               Default vertices were found. Index through the default
%               vertices.
                for k = 1:length(default_vertices)

%                   Get the indexed default vertex
                    value = default_vertices(k);

%                   Create an active vertex interval value in the indexed
%                   time interval
                    interval_value = IntervalValue(obj,...
                        time_intervals(i),mkt,'ActiveVertex',value);
                                                         % an IntervalValue

%                   Append the active vertex to the list of active
%                   vertices.
                    obj.activeVertices = [obj.activeVertices,...
                        interval_value];            % IntervalValue objects

                end                    % for k = 1:length(default_vertices)
          
            else
                
%               One or more transactive records have been received
%               concerning the indexed time interval. Use these to
%               re-create active Vertices.

%               Sort the received_vertices (which happen to be
%               TransactiveRecord objects) by increasing price and power.
                [~,index] = sort([received_vertices.power]);
                received_vertices = received_vertices(index);
                [~,index] = sort([received_vertices.marginalPrice]);
                received_vertices = received_vertices(index);
                
%               Prepare for demand charge vertices.

%               This flag will be replace by its preceding ordered vertex
%               index if any of the vertices are found to exceed the
%               current demand threshold.
                demand_charge_flag = 0;                     % simply a flag
                
%               The demand-charge threshold is based on the actual measured
%               peak this month, but it may also be superseded in predicted
%               time intervales prior to the currently indexed one.
%               Start with the metered demand threshold;
                demand_charge_threshold = obj.demandThreshold;   % [avg.kW]
                
%               Calculate the peak in time intervals that come before the
%               one now indexed by i.
%               Get all the scheduled powers.
                prior_power = obj.scheduledPowers;               % [avg.kW]
                
                if length(prior_power) < i
                    
%                   Especially the first iteration can encounter missing
%                   scheduled power values. Place these out of the way by
%                   assigning then as small as possible. The current demand
%                   threshold will always trump this value.
                    prior_power = -inf;
                    
                else
                    
%                   The scheduled powers look fine. Pick out the ones that
%                   are indexed prior to the currently indexed value.
                    prior_power = [prior_power(1:i).value];      % [avg.kW]
                    
                end
                
%               Pick out the maximum power from the prior scheduled power
%               values.
                predicted_prior_peak = max(prior_power,[],'omitnan'); 
                                                                 % [avg.kW]
                                                                 
%               The demand-charge threshold for the indexed time interval
%               should be the larger of the current and predicted peaks.
                demand_charge_threshold = max([demand_charge_threshold, ...
                    predicted_prior_peak],[],'omitnan');         % [avg.kW]
                            
%               Index through the vertices in the received transactive
%               records for the indexed time interval.
                for k = 1:length(received_vertices) 
          
%                   If there are multiple transactive records in the
%                   indexed time interval, we don't need to create a vertex
%                   for Record #0. Record #0 is the balance point, which
%                   must lie on existing segements of the supply or demand
%                   curve.
                    if length(received_vertices) >= 3 ...
                            && received_vertices(k).record == 0
                        continue; % jumps out of for loop to next iteration
                    end
                    
%                   Create working values of power and marginal price from
%                   the received vertices.
                    power = received_vertices(k).power;
                    marginal_price = received_vertices(k).marginalPrice;
                    
%                   If the Neighbor power is positive (importation of
%                   electricity), then the value may be affected by losses.
%                   The available power is diminished (compared to what was
%                   sent), and the effective marginal price is increased
%                   (because myTransactiveNode is paying for electricity
%                   that it does not receive).
                    if power > 0
                        factor1 = (power / obj.object.maximumPower)^2;
                        factor2 = 1 + factor1 * obj.object.lossFactor;
                        power = power / factor2;
                        marginal_price = marginal_price * factor2;
                        
                        if power > demand_charge_threshold
                            
%                           The power is greater than the anticipated
%                           demand threshold. Demand charges are in play.
%                           Set a flag.
                            demand_charge_flag = k;

                        end                % if power > obj.demandThreshold
                        
                    end                                      % if power > 0

%                   Create a corresponding (price,power) pair (aka "active
%                   vertex") using the received power and marginal price.
%                   See struct Vertex(). 
                    value = Vertex(marginal_price,...
                        received_vertices(k).cost, ...
                        power, ...
                        received_vertices(k).powerUncertainty);  % a Vertex
                
%                   Create an active vertex interval value for the vertex
%                   in the indexed time interval.
                    interval_value = IntervalValue(obj,...
                        time_intervals(i),mkt,'ActiveVertex',value);
                                                          %an IntervalValue
                
%                   Append the active vertex to the list of active
%                   vertices.
                    obj.activeVertices = [obj.activeVertices,...
                        interval_value];            % IntervalValue objects
  
                end                   % for k = 1:length(received_vertices)

%               DEMAND CHARGES
%               Check whether the power of any of the vertices was found to
%               be larger than the current demand-charge threshold, as
%               would be indicated by this flag being a value other than 0.
                if demand_charge_flag ~= 0
                    
%                   Demand charges are in play.
%                   Get the newly updated active vertices for this
%                   transactive Neighbor again in the indexed time
%                   interval.
                    vertices = findobj(obj.activeVertices,...
                        'timeInterval',time_intervals(i));  
                                                    % IntervalValue objects
                    vertices = [vertices.value];           % Vertex objects
                    
%                   Find the marginal price that would correspond to the
%                   demand-charge threshold, based on the newly updated
%                   (but excluding the effects of demand charges) active
%                   vertices in the indexed time interval.
                    marginal_price = ...
                        obj.marginal_price_from_vertices(...
                        demand_charge_threshold,vertices);        % [$/kWh]

%                   Create the first of two vertices at the intersection of
%                   the demand-charge threshold and the supply or demand
%                   curve from prior to the application of demand charges.
                    vertex = Vertex(marginal_price,0,...
                        demand_charge_threshold);         % a Vertex object
                    
%                   Create an IntervalValue for the active vertex.
                    interval_value = IntervalValue(obj,...
                        time_intervals(i),mkt,'ActiveVertex',vertex);
                                                  % an IntervalValue object
                    
%                   Store the new active vertex interval value.
                    obj.activeVertices = ...
                        [obj.activeVertices,interval_value]; 
                                                    % IntervalValue objects
                    
%                   Create the marginal price of the second of the two new
%                   vertices, augmented by the demand rate.
                    marginal_price = marginal_price + obj.demandRate; 
                                                                  % [$/kWh]
                    
%                   Create the second vertex.
                    vertex = Vertex(marginal_price,0,...
                        demand_charge_threshold);         % a vertex object
                    
%                   ... and the interval value for the second vertex,
                    interval_value = IntervalValue(obj,...
                        time_intervals(i),mkt,'ActiveVertex',vertex); 
                                                  % an IntervalValue object
                    
%                   ... and finally store the active vertex.
                    obj.activeVertices = [obj.activeVertices,...
                        interval_value];            % IntervalValue objects
                    
%                   Check that vertices having power greater than the
%                   demand threshold have their marginal prices reflect the
%                   demand charges. Start by picking out those in the
%                   currently indexed time interval.
                    interval_values = findobj(obj.activeVertices,...
                        'timeInterval',time_intervals(i)); 
                                                    % IntervalValue objects
                    
%                   Index through the current active vertices in the
%                   indexed time interval. At this point, these include
%                   vertices from both prior to and after the introduction
%                   of demand-charge vertices.
                    for k = 1:length(interval_values)
                        
%                       Extract the indexed vertex.
                        vertex = interval_values(k).value;
                        
%                       Extract the power of the indexed vertex.
                        vertex_power = vertex.power;             % [avg.kW]
                        
                        if vertex_power > demand_charge_threshold
                            
%                           The indexed vertex's power exceeds the
%                           demand-charge threshold. Increment the vertex's
%                           marginal price with the demand rate.
                            vertex.marginalPrice = vertex.marginalPrice ...
                                + obj.demandRate;
                            
%                           ... and re-store the vertex in its
%                           IntervalValue
                            interval_values(k).value = vertex;
                                                  % an IntervalValue object
                                                  
                        end     % if vertex_power > demand_charge_threshold
                        
                    end                 % for k = 1:length(interval_values)
 
                end                             % if demand_charge_flag > 1

            end                               % if isempty(received_vertex)
       
        else
            
%           Logic should not arrive here. Error. 
            error(['Neighbor ',obj.name,...
                ' must be either transactive or not.']);
            
        end                                   % if obj.transactive == false
        
    end                                  % for i = 1:length(time_intervals)

end                                            % FUNCTION UPDATE_VERTICES()

    end                                             % NeighborModel methods
    
%% Static NeighborModel methods (mostly tests)   
    methods (Static)
     
%% TEST_ALL()                                                     COMPLETED
function test_all()
% TEST_ALL - run all test functions
    disp('Running NeighborModel.test_all()');

    NeighborModel.test_calculate_reserve_margin();
    NeighborModel.test_check_for_convergence();
    NeighborModel.test_marginal_price_from_vertices();
    NeighborModel.test_prep_transactive_signal();
    NeighborModel.test_receive_transactive_signal();
    NeighborModel.test_schedule_engagement();
    NeighborModel.test_schedule_power();
    NeighborModel.test_send_transactive_signal;
    NeighborModel.test_update_dc_threshold;
    NeighborModel.test_update_dual_costs();
    NeighborModel.test_update_production_costs();
    NeighborModel.test_update_vertices();   
    
end                                                            % TEST_ALL()

%% TEST_CALCULATE_RESERVE_MARGIN()                                COMPLETED
function test_calculate_reserve_margin()
% TEST_LAM_CALCULATE_RESERVE_MARGIN() - a LocalAssetModel ("LAM") class
% method NOTE: Reserve margins are introduced but not fully integrated into
% code in early template versions.
% CASES:
% 1. uses hard maximum if no active vertices exist
% 2. vertices exist
%   2.1 uses maximum vertex power if it is less than hard power constraint
%   2.2 uses hard constraint if it is less than maximum vertex power 
%   2.3 upper flex power is greater than scheduled power assigns correct
%       positive reserve margin 
%   2.4 upperflex power less than scheduled power assigns zero value to
%       reserve margin.
    disp('Running NeighborModel.test_calculate_reserve_margin()');
    pf = 'pass';
    
%   Establish a test market
    test_mkt = Market;  
    
%   Establish test market with an active time interval
%   Modified 1/29/18 due to new TimeInterval constructor
    dt = datetime;
    at = dt;
%   NOTE: Function Hours() corrects behavior of Matlab hours().    
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
%   NOTE: Function Hours() corrects behavior of Matlab hours().    
    st = datetime(date) + Hours(12);                        % today at noon

    ti = TimeInterval(at,dur,mkt,mct,st);

    test_mkt.timeIntervals = ti;

%   Establish a test object that is a LocalAsset with assigned maximum power
    test_object = Neighbor;
        test_object.maximumPower = 100;

%   Establish test object that is a NeighborModel
    test_model = NeighborModel;
        test_model.scheduledPowers = ...
            IntervalValue(test_model,ti(1),test_mkt,'ScheduledPower',0.0);

%   Allow object and model to cross-reference one another.
    test_object.model = test_model;
    test_model.object = test_object;

%   Run the first test case.
    try
        test_model.calculate_reserve_margin(test_mkt);
        disp('- method ran without errors');
    catch
        warning('- errors occurred while running the method');
    end
    
    if length(test_model.reserveMargins) ~= 1
        warning('- an unexpected number of results were stored');
    else
        disp('- one reserve margin was stored, as expected');
    end
    
    if test_model.reserveMargins(1).value ~= 100
        pf = 'fail';
        warning('- the method did not use the available maximum power');
    else
        disp('- the method used maximum power value, as expected');
    end
    
%   create some vertices and store them
    interval_value(1) = IntervalValue(test_model,ti,test_mkt,'Vertex',...
        Vertex(0,0,-10));
    interval_value(2) = IntervalValue(test_model,ti,test_mkt,'Vertex',...
        Vertex(0,0,10));
    test_model.activeVertices = interval_value;
    
%   run test with maximum power greater than maximum vertex
    test_object.maximumPower = 100;
    test_model.calculate_reserve_margin(test_mkt);   
    
    if test_model.reserveMargins.value ~= 10
        pf = 'fail';
        warning('- the method should have used vertex for comparison');
    else
        disp('- the method correctly chose to use the vertex power');
    end
    
%   run test with maximum power less than maximum vertex
    test_object.maximumPower = 5;
    test_model.calculate_reserve_margin(test_mkt);   
    
    if test_model.reserveMargins.value ~= 5
        pf = 'fail';
        warning('- method should have used maximum power for comparison');        
    else
        disp('- the method properly chose to use the maximum power');        
    end   
    
%   run test with scheduled power greater than maximum vertex
    test_model.scheduledPowers(1).value = 20;
    test_object.maximumPower = 500;    
    test_model.calculate_reserve_margin(test_mkt);   
    
    if test_model.reserveMargins.value ~= 0
        pf = 'fail';
        warning('- method should have assigned zero for a neg. result');        
    else
        disp('- the method properly assigned 0 for a negative result');         
    end

%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
%   Clean up class space
    clear test_object test_model ti test_mkt

end                                       % TEST_CALCULATE_RESERVE_MARGIN()
 
%% TEST_CHECK_FOR_CONVERGENCE()                                   COMPLETED
function test_check_for_convergence()
% TEST_CHECK_FOR_CONVERGENCE() - test method
% NeighborModel.check_for_convergence().
disp('Running NeighborModel.test_check_for_convergence()');
pf = 'pass';

% Create a test NeighborModel object.
    test_model = NeighborModel;
    test_model.convergenceThreshold = 0.01;
    test_model.converged = true; 
    
% Create a test Market object.
    test_market = Market;
    
% Create and store an active TimeInterval object.
    dt = datetime;
    time_intervals = TimeInterval(dt,Hours(1),test_market,dt,dt);
    test_market.timeIntervals = time_intervals;

%% TEST 1: No TransactiveRecord messages have been sent.
    disp('- Test 1: Property sentSignal is empty');
    
    try
        test_model.check_for_convergence(test_market);
        disp('  - the method ran to completion');
    catch
        warning('  - the method encountered errors and stopped');
    end
    
    if length(test_model.convergenceFlags) ~= 1
        pf = 'fail';
        warning('  - an unexpected number of convergence flags occurred');
    else
        disp('  - the expected number of convergence flags occurred');
    end
    
    if test_model.convergenceFlags(1).value ~= false
        tf = 'fail';
        warning('  - the interval convergence flag should have been false');
    else
        disp('  - the interval convergence flag was false, as expected');
    end
    
    if test_model.converged ~= false
        tf = 'fail';
        warning('  - the overall convergence should have been false');
    else
        disp('  - the overall convergence was false, as expected');
    end   
    
%% TEST 2: Compare sent and received signals with identical records
disp('- Test 2: Comparing identical sent and received transactive records');

    test_model.converged = false; % Preset to  ensure test changes status.

% Create a couple TransactiveRecord objects. NOTE: sent and received
% records have opposite signs for their powers. These should therefore
% match and show convergence. The timestamp of the the record for
% receivedSignal should be made LATER than that for the sent as this is a
% precondition that must be met.
    tr(1) = TransactiveRecord(time_intervals,0,0.05,100);
    tr(2) = TransactiveRecord(time_intervals,0,0.05,-100);
    tr(2).timeStamp = datetime('now','Format','yyMMdd:HHmmss') + Hours(1);
 
% NOTE: The latter-defined record must be placed in receivedSignal to
% satisfy a precondition.
    test_model.sentSignal = tr(1);
    test_model.receivedSignal = tr(2);
    
    try
        test_model.check_for_convergence(test_market);
        disp('  - the method ran to completion');
    catch
        warning('  - the method encountered errors and stopped');
    end
    
    if length(test_model.convergenceFlags) ~= 1
        pf = 'fail';
        warning('  - an unexpected number of interval convergence flags occurred');
    else
        disp('  - the expected number of interval convergence flags occurred');
    end
    
    if test_model.convergenceFlags(1).value ~= true
        tf = 'fail';
        warning('  - the interval convergence flag should have been true');
    else
        disp('  - the interval convergence flag was true, as expected');
    end
    
    if test_model.converged ~= true
        tf = 'fail';
        warning('  - the overall convergence should have been true');
    else
        disp('  - the overall convergence was true, as expected');
    end   
    
%% TEST 3: Revise records' scheduled powers to show lack of convergence 
disp(['- Test 3: Revise powers to destroy convergence between sent', ...
    'and received messages']);
    test_model.receivedSignal(1).power = ...
        1.02 * test_model.receivedSignal(1).power;
    
    try
        test_model.check_for_convergence(test_market);
        disp('  - the method ran to completion');
    catch
        warning('  - the method encountered errors and stopped');
    end
    
    if length(test_model.convergenceFlags) ~= 1
        pf = 'fail';
        warning('  - an unexpected number of interval convergence flags occurred');
    else
        disp('  - the expected number of interval convergence flags occurred');
    end
    
    if test_model.convergenceFlags(1).value ~= false
        tf = 'fail';
        warning('  - the interval convergence flag should have been false');
    else
        disp('  - the interval convergence flag was false, as expected');
    end
    
    if test_model.converged ~= false
        tf = 'fail';
        warning('  - the overall convergence should have been false');
    else
        disp('  - the overall convergence was false, as expected');
    end   
    
%% TEST 4: Sent and received signals differ, no signal received since last send
disp('- Test 4: No received signal since last send');
    dt = datetime('now','Format','yyMMdd:HHmmss');
    test_model.sentSignal(1).timeStamp = dt;
    test_model.receivedSignal(1).timeStamp = dt;
    
    try
        test_model.check_for_convergence(test_market);
        disp('  - the method ran to completion');
    catch
        warning('  - the method encountered errors and stopped');
    end
    
    if length(test_model.convergenceFlags) ~= 1
        pf = 'fail';
        warning('  - an unexpected number of interval convergence flags occurred');
    else
        disp('  - the expected number of interval convergence flags occurred');
    end
    
    if test_model.convergenceFlags(1).value ~= true
        tf = 'fail';
        warning('  - the interval convergence flag should have been true');
    else
        disp('  - the interval convergence flag was true, as expected');
    end
    
    if test_model.converged ~= true
        tf = 'fail';
        warning('  - the overall convergence should have been true');
    else
        disp('  - the overall convergence was true, as expected');
    end   
    
%% TEST 5: Compare identical mySignal and sentSignal records  
disp('- Test 5: Identical mySignal and sentSignal contents');

%   Create prepared mySignal message that is exactly the same as the sent
%   message.     
    test_model.mySignal = tr(1);
    test_model.sentSignal = tr(1); 

%   Ensure that the sent signal was sent much more than 5 minutes ago
    test_model.sentSignal(1).timeStamp = dt - Hours(1);
    
%   Ensure that a signal has NOT been received since the last one was sent.
%   This intentionally violates a precondition so that the method under
%   test will not compare the sent and received messages.
    test_model.receivedSignal(1).timeStamp = ...
        test_model.sentSignal(1).timeStamp - Hours(1);

    try
        test_model.check_for_convergence(test_market);
        disp('  - the method ran to completion');
    catch
        warning('  - the method encountered errors and stopped');
    end
    
    if length(test_model.convergenceFlags) ~= 1
        pf = 'fail';
        warning('  - an unexpected number of interval convergence flags occurred');
    else
        disp('  - the expected number of interval convergence flags occurred');
    end
    
    if test_model.convergenceFlags(1).value ~= true
        tf = 'fail';
        warning('  - the interval convergence flag should have been true');
    else
        disp('  - the interval convergence flag was true, as expected');
    end
    
    if test_model.converged ~= true
        tf = 'fail';
        warning('  - the overall convergence should have been true');
    else
        disp('  - the overall convergence was true, as expected');
    end  
    
%% TEST 6: Compare multiple matched mySignal and testSignal records  
disp('- Test 6: Compare multiple matched mySignal and testSignal records');

% Create a couple new TransactiveRecord objects.
    tr(3) = TransactiveRecord(time_intervals,1,0.049,90);
    tr(3).timeStamp = test_model.sentSignal(1).timeStamp;
    
    tr(4) = TransactiveRecord(time_intervals,2,0.051,110);
    tr(4).timeStamp = test_model.sentSignal(1).timeStamp;    
    
% Append the mySignal and sentSignal records. The sets should still remain
% identical, meaning that the system has not changed and remains converged.
    test_model.mySignal = tr([1,3,4]);
    test_model.sentSignal = tr([1,3,4]);

   try
        test_model.check_for_convergence(test_market);
        disp('  - the method ran to completion');
    catch
        warning('  - the method encountered errors and stopped');
    end
    
    if length(test_model.convergenceFlags) ~= 1
        pf = 'fail';
        warning('  - an unexpected number of interval convergence flags occurred');
    else
        disp('  - the expected number of interval convergence flags occurred');
    end
    
    if test_model.convergenceFlags(1).value ~= true
        tf = 'fail';
        warning('  - the interval convergence flag should have been true');
    else
        disp('  - the interval convergence flag was true, as expected');
    end
    
    if test_model.converged ~= true
        tf = 'fail';
        warning('  - the overall convergence should have been true');
    else
        disp('  - the overall convergence was true, as expected');
    end  
    
%% TEST 7: A Vertex differs significantly between mySignal and sentSignal
disp(['- Test 7: mySignal and sentSignal differ significantly, ',...
    'multiple points.']);

% Change mySignal to be significantly different from sentSignal.
 %   test_model.mySignal(1).
 
 tr(5) = TransactiveRecord(time_intervals,1,0.049,85);
  test_model.mySignal = tr([1,5,4]);

   try
        test_model.check_for_convergence(test_market);
        disp('  - the method ran to completion');
    catch
        warning('  - the method encountered errors and stopped');
    end
    
    if length(test_model.convergenceFlags) ~= 1
        pf = 'fail';
        warning('  - an unexpected number of interval convergence flags occurred');
    else
        disp('  - the expected number of interval convergence flags occurred');
    end
    
    if test_model.convergenceFlags(1).value ~= false
        tf = 'fail';
        warning('  - the interval convergence flag should have been false');
    else
        disp('  - the interval convergence flag was false, as expected');
    end
    
    if test_model.converged ~= false
        tf = 'fail';
        warning('  - the overall convergence should have been false');
    else
        disp('  - the overall convergence was false, as expected');
    end  
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);

end                                          % TEST_CHECK_FOR_CONVERGENCE()

%% TEST_MARGINAL_PRICE_FROM_VERTICES()                            COMPLETED
function test_marginal_price_from_vertices()
% TEST_MARGINAL_PRICE_FROM_VERTICES() - test method
% marginal_price_from_vertices().
    disp('Running NeighborModel.test_marginal_price_from_vertices()');
    pf = 'pass';
    
% CASES:
%   - power less than leftmost vertex
%   - power greater than rightmost vertex
%   - power between two vertices

%   Create a test NeighborModel object.
    test_obj = NeighborModel;
    
%   Create and store two test Vertex objects. Misorder to test ordering.
    test_vertices(1) = Vertex(0.2,0,100);
    test_vertices(2) = Vertex(0.1,0,-100); 
    
%   Test 1: Power less than leftmost vertex.
    disp('- Test 1: power less than leftmost Vertex');
    power = -150;
    
    try
        marginal_price = test_obj.marginal_price_from_vertices(power,...
            test_vertices);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors when called');
    end
    
    if marginal_price ~= test_vertices(2).marginalPrice
        pf = 'fail';
        warning('  - the method returned an unexpected marginal price');
    else
        disp('  - the method returned the expected marginal price');
    end

%   Test 2: Power greater than the rightmost Vertex.
    disp('- Test 2: power greater than the rightmost Vertex');
    power = 150;
    
    try
        marginal_price = test_obj.marginal_price_from_vertices(power,...
            test_vertices);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors when called');
    end
    
    if marginal_price ~= test_vertices(1).marginalPrice
        pf = 'fail';
        warning('  - the method returned an unexpected marginal price');
    else
        disp('  - the method returned the expected marginal price');
    end

%   Test 3: Power between vertices.
    disp('- Test 3: power is between vertices');
    power = 0;
    
    try
        marginal_price = test_obj.marginal_price_from_vertices(power,...
            test_vertices);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors when called');
    end
    
    if abs(marginal_price - 0.15) > 0.0001
        pf = 'fail';
        warning('  - the method returned an unexpected marginal price');
    else
        disp('  - the method returned the expected marginal price');
    end
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
%   Clean up the variable space
    clear test_obj test_vertices
    
end                                   % TEST_MARGINAL_PRICE_FROM_VERTICES()

%% TEST_PREP_TRANSACTIVE_SIGNAL()                                 COMPLETED
function test_prep_transactive_signal()
    disp('Running NeighborModel.test_prep_transactive_signal()');
    pf = 'pass';
    
%   Create a test model.
    test_model = NeighborModel;
    
%   Create a test object.
    test_object = Neighbor;
    
%   Let the test object and model cross reference one another.
    test_object.model = test_model;
    test_model.object = test_object;
    
%   Create a test market object.
    test_market = Market;
    
%   Create a test LocalAssetModel object.
    test_asset_model = LocalAssetModel;
    
%   Create a test LocalAsset object.
    test_local_asset = LocalAsset;
    
%   Let the asset and its model cross-reference one another.
    test_local_asset.model = test_asset_model;
    test_asset_model.object = test_local_asset;
    
%   Create a test myTransactiveNode object and its references to its
%   objects and models.
    test_myTransactiveNode = myTransactiveNode; 
    test_myTransactiveNode.neighbors = {test_object};
    test_myTransactiveNode.localAssets = {test_local_asset};
    test_myTransactiveNode.markets = test_market;
    
%   Create and store a TimeInterval object;
    dt = datetime;
    at = dt;
    dur = Hours(1);
    mkt = test_market;
    mct = dt;
    st = dt;    
    time_interval = TimeInterval(at,dur,mkt,mct,st);
    test_market.timeIntervals = time_interval;
    
%   Create some active vertices and their IntervalValue objects ready to
%   choose from for the various tests. 
    vertices(1) = Vertex(0.1,0,-100);
    interval_values(1) = IntervalValue(test_model,time_interval,...
        test_market,'TestVertex',vertices(1));
    vertices(2) = Vertex(0.2,0,-37.5);
    interval_values(2) = IntervalValue(test_model,time_interval,...
        test_market,'TestVertex',vertices(2));    
    vertices(3) = Vertex(0.3,0,0);
    interval_values(3) = IntervalValue(test_model,time_interval,...
        test_market,'TestVertex',vertices(3));    
    vertices(4) = Vertex(0.4,0,25);
    interval_values(4) = IntervalValue(test_model,time_interval,...
        test_market,'TestVertex',vertices(4));    
    vertices(5) = Vertex(0.5,0,100);
    interval_values(5) = IntervalValue(test_model,time_interval,...
        test_market,'TestVertex',vertices(5));    

%% TEST 1
    disp('- Test 1: Neighbor is NOT transactive');
    test_model.transactive = false;
    
    warning('off','all'); % A warning is expected. Turn off warnings.
    try
        test_model.prep_transactive_signal(test_market,...
            test_myTransactiveNode);
        disp('  - The method warned and returned, as expected');
    catch
        warning('on','all'); % turn the warnings back on.
        pf = 'fail';
        warning('  - The method failed with errors when called');      
    end
    
%% TEST 2 
    disp('- Test 2: The trans. Neighbor is offered no flexibility');

%   Configure the test.
    test_model.transactive = true; 
    test_model.scheduledPowers = IntervalValue(test_model,time_interval,...
        test_market,'ScheduledPower',200);
    test_asset_model.activeVertices = interval_values(3);
    warning('on','all'); % Turn on warnings.
    
    try
        test_model.prep_transactive_signal(test_market,...
            test_myTransactiveNode);
        disp('  - the method ran to completion without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors when called');
    end
    
    if length(test_model.mySignal) ~= 1
        pf = 'fail';
        warning('  - the wrong number of transactive records were stored');
    else
        disp('  - a transactive record was stored as expected');
    end
    
    if test_model.mySignal.power ~= -200 ...
            && test_model.mySignal.marginalPrice ~= inf
        pf = 'fail';
        warning('  - the transactive record values were not as expected');
    else
        disp('  - the values in the transactive record were as expected');        
    end
    
    
%% TEST 3
    disp('- Test 3: The trans. Neigbor imports from myTransactiveNode');
    
%   Configure the test.
    test_model.transactive = true;
    test_model.scheduledPowers = IntervalValue(test_model,time_interval,...
        test_market,'ScheduledPower',-50);
    test_object.maximumPower = -10;
    test_object.minimumPower = -75;
    test_asset_model.activeVertices = [interval_values(3),...
        interval_values(5)];  
    
    try
        test_model.prep_transactive_signal(test_market,...
            test_myTransactiveNode);
        disp('  - the method ran to completion without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors when called');
    end
    
    if length(test_model.mySignal) ~= 3
        pf = 'fail';
        warning('  - the wrong number of transactive records were stored');
    else
        disp('  - three transactive records ware stored as expected');
    end    
    
    if any(~ismember([test_model.mySignal(:).power],[10,50,75]))
        pf = 'fail';
        warning('  - the record power values were not as expected');
    else
        disp('  - the power values in the records were as expected');        
    end
        
    if any(abs([test_model.mySignal(:).marginalPrice]-0.3200)...
                < 0.0001) ...
            && any(abs([test_model.mySignal(:).marginalPrice]-0.4000)...
                < 0.0001)...
            && any(abs([test_model.mySignal(:).marginalPrice]-0.4500)...
                < 0.0001)
        disp('  - the marginal price values were as expected'); 
    else
        pf = 'fail';
        warning('  - the marginal price values were not as expected');       
    end    
    
%% TEST 4
    disp('- Test 4: The trans. Neighbor exports to myTransactiveNode');
    
%   Configure the test.
    test_model.transactive = true;
    test_model.scheduledPowers = IntervalValue(test_model,time_interval,...
        test_market,'ScheduledPower',50);
    test_object.maximumPower = 75;
    test_object.minimumPower = 10;
    test_asset_model.activeVertices = [interval_values(1),...
        interval_values(3)]; 
    
    try
        test_model.prep_transactive_signal(test_market,...
            test_myTransactiveNode);
        disp('  - the method ran to completion without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors when called');
    end
    
    if length(test_model.mySignal) ~= 3
        pf = 'fail';
        warning('  - the wrong number of transactive records were stored');
    else
        disp('  - three transactive records ware stored as expected');
    end    
    
    if any(~ismember([test_model.mySignal(:).power],[-10,-50,-75]))
        pf = 'fail';
        warning('  - the record power values were not as expected');
    else
        disp('  - the power values in the records were as expected');        
    end
        
    if any(abs([test_model.mySignal(:).marginalPrice]-0.1500)...
                < 0.0001) ...
            && any(abs([test_model.mySignal(:).marginalPrice]-0.2000)...
                < 0.0001)...
            && any(abs([test_model.mySignal(:).marginalPrice]-0.2800)...
                < 0.0001)
        disp('  - the marginal price values were as expected'); 
    else
        pf = 'fail';
        warning('  - the marginal price values were not as expected');       
    end      
    
%% TEST 5
    disp('- Test 5: There is an extra Vertex in the range');
    
%   Configure the test.
    test_model.transactive = true;
    test_model.scheduledPowers = IntervalValue(test_model,time_interval,...
        test_market,'ScheduledPower',50);
    test_object.maximumPower = 75;
    test_object.minimumPower = 25;
    test_asset_model.activeVertices = [interval_values(1),...
        interval_values(2), ... % an extra vertex in active flex range
        interval_values(3)]; 
    
     try
        test_model.prep_transactive_signal(test_market,...
            test_myTransactiveNode);
        disp('  - the method ran to completion without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors when called');
    end
    
    if length(test_model.mySignal) ~= 4
        pf = 'fail';
        warning('  - the wrong number of transactive records were stored');
    else
        disp('  - four transactive records ware stored as expected');
    end    
    
    if any(~ismember([test_model.mySignal(:).power],[-25,-50,-75, -37.5]))
        pf = 'fail';
        warning('  - the record power values were not as expected');
    else
        disp('  - the power values in the records were as expected');        
    end
        
    if any(abs([test_model.mySignal(:).marginalPrice]-0.1800)...
                < 0.0001) ...
            && any(abs([test_model.mySignal(:).marginalPrice]-0.1400)...
                < 0.0001) ...
            && any(abs([test_model.mySignal(:).marginalPrice]-0.2333)...
                < 0.0001) ...
            && any(abs([test_model.mySignal(:).marginalPrice]-0.2000)...
                < 0.0001)            
        disp('  - the marginal price values were as expected'); 
    else
        pf = 'fail';
        warning('  - the marginal price values were not as expected');       
    end    
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
%   Clean up the variable space
    clear test_obj
    
end                                        % TEST_PREP_TRANSACTIVE_SIGNAL()

%% TEST_RECEIVE_TRANSACTIVE_SIGNAL()                              COMPLETED
function test_receive_transactive_signal()
    disp('Running NeighborModel.test_receive_transactive_signal()');
    pf = 'pass';
    
%   Create a test NeighborModel object.
    test_model = NeighborModel;
    
%   Create a test Neighbor object.
    test_object = Neighbor;
    test_object.name = 'TN_abcdefghijklmn';
    
%   Get the test object and model to cross-reference one another.
    test_object.model = test_model;
    test_model.object = test_object;
    
%   Create a test market object.
    test_market = Market;
    
%   Create a test myTransactiveNode object.
    test_myTransactiveNode = myTransactiveNode;
    test_myTransactiveNode.name = 'mTN_abcd';
    
%% TEST 1
    disp('- Test 1: Neighbor is NOT transactive');
    test_model.transactive = false;
    
    warning('off','all');
    try
        test_model.receive_transactive_signal(test_myTransactiveNode);
        disp('  - The method warned and returned, as expected');
        warning('on','all');
    catch
        pf = 'fail';
        warning('on','all');
        warning('  - The method failed with errors when called');      
    end

% Test 2
    disp('- Test 2: Read a csv file into received transactive records');
    
%   Configure for the test.
    test_model.transactive = true;

%   Create a test time interval
    dt = datetime;
    at = dt;
    dur = Hours(1);
    mkt = test_market;
    mct = dt;
    st = dt;
    time_interval = TimeInterval(at,dur,mkt,mct,st);
    
%   Create a couple test transactive records.
    test_records(1) = TransactiveRecord(time_interval,0,0.1,0);
    test_records(2) = TransactiveRecord(time_interval,1,0.2,100);
    
    test_model.mySignal = test_records;
    
    try 
        test_model.send_transactive_signal(test_myTransactiveNode);
        disp(['  - this test depends on method ',...
            'send_transactive_signal() to create a file']);
    catch
        pf = 'fail';
        warning(['  - method send_transactive_signal() ',...
            'failed to create a file']);
    end
 
%   Clear the mySignal property that will be used to receive the records.    
    test_model.receivedSignal = [];
    
%   A trick is needed because the filenames rely on source and target node
%   names, which are swapped in the reading and sending methods. Exchange
%   the names of the test object and test myTransactiveNode.
    name_holder = test_myTransactiveNode.name;
    test_myTransactiveNode.name = test_object.name;
    test_object.name = name_holder;
    
    try
        test_model.receive_transactive_signal(test_myTransactiveNode);
        disp('  - the receive method ran without errors');
    catch
        pf = 'fail';
        warning('  - problems occurred when calling the receive method');
    end
    
    if length(test_model.receivedSignal) ~= 2
        pf = 'fail';
        warning('  - an unexpected, or no, record count was stored');
    else
        disp('  - the expected number of records was stored');
    end
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
%   Close and delete the test csv file
    expected_filename = 'mTN_a-TN_ab.txt';
    fclose('all');
    delete(expected_filename);
    
end                                     % TEST_RECEIVE_TRANSACTIVE_SIGNAL()

%% TEST_SCHEDULE_ENGAGMENT()                                      COMPLETED
function test_schedule_engagement()
    disp('Running NeighborModel.test_schedule_engagement()');
    pf = 'pass';
    
    test_obj = NeighborModel;

    test_mkt = Market;

    try
        test_obj.schedule_engagement(test_mkt);
        disp('- method ran to completion');
    catch
        pf = 'fail';
        error('- method encountered error and did not run to completion');
    end

    if test_obj == test_obj
        disp('- the NeighborModel was unchanged, which is correct');
    else
        error('- the NeighborModel was unexpected altered');
    end

%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
    clear test_obj test_mkt

end                                             % TEST_SCHEDULE_ENGAGMENT()
  
%% TEST_SCHEDULE_POWER()                                          COMPLETED         
function test_schedule_power()
% TEST_SCHEDULE_POWER() - tests a NeighborModel method called
% schedule_power().
    disp('Running NeighborModel.test_schedule_power()');
    pf = 'pass';
    
%   Create a test NeighborModel object.
    test_model = NeighborModel;
%     test_model.defaultPower = 99;
    
%   Create a test Market object.
    test_market = Market;
    
%   Create and store an active TimeInterval object.
    dt = datetime; % datetime that may be used for all datetime arguments
    time_interval = TimeInterval(dt,Hours(1),test_market,dt,dt);
    test_market.timeIntervals = time_interval;  
    
%   Create and store a marginal price IntervalValue object.
    test_market.marginalPrices = IntervalValue(test_market,...
        time_interval,test_market,'MarginalPrice',0.1);
 
%   Create a store a simple active Vertex for the test model.
    test_vertex = Vertex(0.1,0,100);
    test_interval_value = IntervalValue(test_model,time_interval, ...
        test_market,'ActiveVertex',test_vertex);
    test_model.activeVertices = test_interval_value;
    
%% TEST 1
    disp('- Test 1: scheduled power does not exist yet');
    
    try
        test_model.schedule_power(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors when called');
    end
    
    if length(test_model.scheduledPowers) ~= 1
        pf = 'fail';
        warning('  - an unexpected number of scheduled powers is created');
    else
        disp('  - the expected number of scheduled powers is created');
    end
    
    scheduled_power = test_model.scheduledPowers(1).value;
    if scheduled_power ~= 100
        pf = 'fail';
        warning('  - the scheduled power value was not that expected');
    else
        disp('  - the scheduled power value was as expected');
    end

%% TEST 2
    disp('- Test 2: scheduled power value exists to be reassigned');
    
%   Configure for test by using a different active vertex.
    test_vertex.power = 50;
    test_model.activeVertices(1).value = test_vertex;
    
   try
        test_model.schedule_power(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors when called');
    end
    
    if length(test_model.scheduledPowers) ~= 1
        pf = 'fail';
        warning('  - an unexpected number of scheduled powers is found');
    else
        disp('  - the expected number of scheduled powers is found');
    end
    
    scheduled_power = test_model.scheduledPowers(1).value;
    if scheduled_power ~= 50
        pf = 'fail';
        warning('  - the scheduled power value was not that expected');
    else
        disp('  - the scheduled power value was as expected');
    end  

%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf); 
   
end                                                 % TEST_SCHEDULE_POWER()

%% TEST_SEND_TRANSACTIVE_SIGNAL()                                 COMPLETED
function test_send_transactive_signal()
    disp('Running NeighborModel.test_send_transactive_signal()');
    pf = 'pass';
    
%   Create a test NeighborModel object.
    test_model = NeighborModel;
%     test_model.name = 'NM_abcdefghijkl';
    
%   Create a test Neighbor object.
    test_object = Neighbor;
    test_object.name = 'TN_abcdefghijklmn';
    
%   Get the test object and model to cross-reference one another.
    test_object.model = test_model;
    test_model.object = test_object;
    
%   Create a test market object.
    test_market = Market;
    
%   Create a test myTransactiveNode object.
    test_myTransactiveNode = myTransactiveNode;
    test_myTransactiveNode.name = 'mTN_abcd';
    
%% TEST 1
    disp('- Test 1: Neighbor is NOT transactive');
    test_model.transactive = false;
    
    warning('off','all');
    try
        test_model.send_transactive_signal(test_myTransactiveNode);
        disp('  - The method warned and returned, as expected');
        warning('on','all');        
    catch
        warning('on','all');
        pf = 'fail';
        warning('  - The method failed with errors when called');      
    end    

% Test 2
    disp('- Test 2: Write transactive records into a csv file');
    
%   Configure for the test.
    test_model.transactive = true;

%   Create a test time interval
    dt = datetime;
    at = dt;
    dur = Hours(1);
    mkt = test_market;
    mct = dt;
    st = dt;
    time_interval = TimeInterval(at,dur,mkt,mct,st);
    
%   Create a couple test transactive records.
    test_records(1) = TransactiveRecord(time_interval,0,0.1,0);
    test_records(2) = TransactiveRecord(time_interval,1,0.2,100);
    
    test_model.mySignal = test_records;
    
    try 
        test_model.send_transactive_signal(test_myTransactiveNode);
        disp('  - the method ran to completion without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors when called');
    end
    
    expected_filename = 'mTN_a-TN_ab.txt';
    
    if exist(expected_filename,'file') ~= 2 
        pf = 'fail';
        warning('  - the expected output file does not exist');
    else
        disp('  - the expected output file exists');
    end
    
    expected_data = csvread(expected_filename,1,3,[1,3,2,4]);
    
    if expected_data ~= [0.1000, 0; 0.2000, 100]
        pf = 'fail';
        warning('  - the csv file contents were not as expected');
    else
        disp('  - the csv file contents were as expected');
    end
    
%% TEST 3: Check that the saved sent signal is the same as that calculated.
disp('- Test 3: Was the sent signal saved properly?');

    if test_model.mySignal ~= test_model.sentSignal
        pf = 'fail';
        warning('  - the sent signal does not match the calculated one');
    else
        disp('  - the sent signal matches the calculated one');
    end
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
% Close and delete the file.
    fclose('all');
    delete(expected_filename);
    
end                                        % TEST_SEND_TRANSACTIVE_SIGNAL()

%% TEST_UPDATE_DC_THRESHOLD()                                     COMPLETED
function test_update_dc_threshold()
    disp('Running NeighborModel.test_update_dc_threshold()');
    pf = 'pass';

%% Basic configuration for tests:
%   Create a test object and initialize demand-realted properties
    test_obj = BulkSupplier_dc;
        test_obj.demandMonth = month(datetime);
        test_obj.demandThreshold = 1000;
        
%   Create a test market   
    test_mkt = Market;
    
%   Create and store two time intervals
    dt = datetime;
    at = dt;
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = dt;
    ti(1) = TimeInterval(at,dur,mkt,mct,st);
    
    st = st + dur;
    ti(2) = TimeInterval(at,dur,mkt,mct,st);
    test_mkt.timeIntervals = ti;
    

    
%%  Test case when there is no MeterPoint object  
    test_obj.demandThreshold = 1000;
    test_obj.demandMonth = month(datetime);
    test_obj.meterPoints = MeterPoint.empty;
    
%   Create and store a couple scheduled powers
    iv(1) = IntervalValue(test_obj,ti(1),test_mkt,'SheduledPower',900);
    iv(2) = IntervalValue(test_obj,ti(2),test_mkt,'SheduledPower',900);
    test_obj.scheduledPowers = iv;
    
    try
        test_obj.update_dc_threshold(test_mkt);
        disp('- the method ran without errors');
    catch
        pf = 'fail';
        warning('- the method encountered errors when called');
    end
    
    if test_obj.demandThreshold ~= 1000
        pf = 'fail';
        warning('- the method inferred the wrong demand threshold value');
    else
        disp(['- the method properly kept the old demand threshold ',...
            'value with no meter']);        
    end
    
    iv(1) = IntervalValue(test_obj,ti(1),test_mkt,'SheduledPower',1100);
    iv(2) = IntervalValue(test_obj,ti(2),test_mkt,'SheduledPower',900);
    test_obj.scheduledPowers = iv; 
    
    try
        test_obj.update_dc_threshold(test_mkt);
        disp('- the method ran without errors when there is no meter');
    catch
        pf = 'fail';
        warning('- the method encountered errors when there is no meter');
    end    

    if test_obj.demandThreshold ~= 1100
        pf = 'fail';
        warning(['- the method did not update the inferred demand ',...
            'threshold value']);
    else
        disp(['- the method properly updated the demand threshold ',...
            'value with no meter']);        
    end    
    
%% Test with an appropriate MeterPoint meter
%   Create and store a MeterPoint test object
    test_mtr = MeterPoint;
        test_mtr.measurementType = 'average_demand_kW';
        test_mtr.currentMeasurement = 900;
    test_obj.meterPoints = test_mtr;

%   Reconfigure the test object for this test:
    iv(1) = IntervalValue(test_obj,ti(1),test_mkt,'SheduledPower',900);
    iv(2) = IntervalValue(test_obj,ti(2),test_mkt,'SheduledPower',900);
    test_obj.scheduledPowers = iv;
    
    test_obj.demandThreshold = 1000;
    test_obj.demandMonth = month(datetime);
    
%   Run the test. Confirm it runs.
    try
        test_obj.update_dc_threshold(test_mkt);
        disp('- the method ran without errors when there is a meter');
    catch
        pf = 'fail';
        warning('- the method encountered errors when there is a meter');
    end
 
%   Check that the old threshold is correctly retained.
    if test_obj.demandThreshold ~= 1000
        pf = 'fail';
        warning(['- the method failed to keep the correct demand ',...
            'threshold value when there is a meter']);
    else
        disp(['- the method properly kept the old demand threshold ',...
            'value when there is a meter']);        
    end    

%   Reconfigure the test object with a lower current threshold
    iv(1) = IntervalValue(test_obj,ti(1),test_mkt,'SheduledPower',900);
    iv(2) = IntervalValue(test_obj,ti(2),test_mkt,'SheduledPower',900);
    test_obj.scheduledPowers = iv;
    test_obj.demandThreshold = 800;

%   Run the test.
    test_obj.update_dc_threshold(test_mkt);

%   Check that a new, higher demand threshold was set.
    if test_obj.demandThreshold ~= 900
        pf = 'fail';
        warning(['- the method failed to update the demand ',...
            'threshold value when there is a meter']);
    else
        disp(['- the method properly updated the demand threshold ',...
            'value when there is a meter']);        
    end   

%% Test rollover to new month
%   Configure the test object
    test_obj.demandMonth = month(datetime - days(31));        % prior month
    test_obj.demandThreshold = 1000;
    test_obj.scheduledPowers(1).value = 900;
    test_obj.scheduledPowers(2).value = 900; 
    test_obj.meterPoints = MeterPoint.empty;
    
%   Run the test
    test_obj.update_dc_threshold(test_mkt);    

%   See if the demand threshold was reset at the new month.
    if test_obj.demandThreshold ~= 0.8 * 1000
        pf = 'fail';
        warning(['- the method did not reduce the threshold ',...
            'properly in a new month']);
    else
        disp('- the method reduced the threshold properly in a new month');
    end  
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up the variable space
    clear test_mtr test_mkt test_obj iv ti
        
end                                            % TEST_UPDATE_DC_THRESHOLD()

%% TEST_UPDATE_DUAL_COSTS()                                       COMPLETED
function test_update_dual_costs()
    disp('Running NeighborModel.test_update_dual_costs()');
    pf = 'pass';

%   Create a test Market object.
    test_market = Market;
    
%   Create and store a TimeInterval object.
    dt = datetime; % datetime that may be used for most datetime arguments
    time_interval = TimeInterval(dt,Hours(1),test_market,dt,dt);
    test_market.timeIntervals = time_interval;

%   Create and store a marginal price IntervalValue object.
    test_market.marginalPrices = IntervalValue(test_market,...
        time_interval,test_market,'MarginalPrice',0.1);
    
%   Create a test NeighborModel object.
    test_model = NeighborModel; 
    
%   Create and store a scheduled power IntervalValue in the active time
%   interval. 
    test_model.scheduledPowers = IntervalValue(test_model,...
        time_interval,test_market,'ScheduledPower',100);
    
%   Create and store a production cost IntervalValue object in the active
%   time interval.
    test_model.productionCosts = IntervalValue(test_model,...
        time_interval,test_market,'ProductionCost',1000);

% TEST 1
    disp('- Test 1: First calculation of a dual cost');
    
    try
        test_model.update_dual_costs(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - there were errors when the method was called');
    end
    
    if length(test_model.dualCosts) ~= 1
        pf = 'fail';
        warning('  - the wrong number of dual cost values was created');
    else
        disp('  - the right number of dual cost values was created');
    end
    
    dual_cost = test_model.dualCosts(1).value;
    
    if dual_cost ~= (1000 - 100 * 0.1)
        pf = 'fail';
        warning('  - an unexpected dual cost value was found');
    else
        disp('  - the expected dual cost value was found');
    end
    
% TEST 2
    disp('- Test 2: Reassignment of an existing dual cost');
    
%   Configure the test by modifying the marginal price value.    
   test_market.marginalPrices(1).value = 0.2;
   
     try
        test_model.update_dual_costs(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - there were errors when the method was called');
    end
    
    if length(test_model.dualCosts) ~= 1
        pf = 'fail';
        warning('  - the wrong number of dual cost values was created');
    else
        disp('  - the right number of dual cost values was created');
    end
    
    dual_cost = test_model.dualCosts(1).value;
    
    if dual_cost ~= (1000 - 100 * 0.2)
        pf = 'fail';
        warning('  - an unexpected dual cost value was found');
    else
        disp('  - the expected dual cost value was found');
    end   
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
end                                              % TEST_UPDATE_DUAL_COSTS()

%% TEST_UPDATE_PRODUCTION_COSTS()                                 COMPLETED
function test_update_production_costs()
    disp('Running NeighborModel.test_update_production_costs()');
    pf = 'pass';
    
%   Create a test Market object.
    test_market = Market;
    
%   Create and store a TimeInterval object.
    dt = datetime; % datetime that may be used for most datetime arguments
    time_interval = TimeInterval(dt,Hours(1),test_market,dt,dt);
    test_market.timeIntervals = time_interval;

%   Create a test NeighborModel object.
    test_model = NeighborModel; 
    
%   Create and store a scheduled power IntervalValue in the active time
%   interval. 
    test_model.scheduledPowers = IntervalValue(test_model,...
        time_interval,test_market,'ScheduledPower',50); 
    
%   Create and store some active vertices IntervalValue objects in the
%   active time interval.
    vertices(1) = Vertex(0.1,1000,0);
    interval_values(1) = IntervalValue(test_model,time_interval,...
        test_market,'ActiveVertex',vertices(1));
    vertices(2) = Vertex(0.2,1015,100);
    interval_values(2) = IntervalValue(test_model,time_interval,...
        test_market,'ActiveVertex',vertices(2));    
    test_model.activeVertices = interval_values;
    
% TEST 1
    disp('- Test 1: First calculation of a production cost');
    
    try
        test_model.update_production_costs(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - there were errors when the method was called');
    end
    
    if length(test_model.productionCosts) ~= 1
        pf = 'fail';
        warning('  - the wrong number of production costs was created');
    else
        disp('  - the right number of production cost values was created');
    end
    
    production_cost = test_model.productionCosts(1).value;
    
    if production_cost ~= 1007.5
        pf = 'fail';
        warning('  - an unexpected production cost value was found');
    else
        disp('  - the expected production cost value was found');
    end
    
% TEST 2
    disp('- Test 2: Reassignment of an existing production cost');
    
%   Configure the test by modifying the scheduled power value.    
   test_model.scheduledPowers(1).value = 150;
   
     try
        test_model.update_production_costs(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - there were errors when the method was called');
    end
    
    if length(test_model.productionCosts) ~= 1
        pf = 'fail';
        warning('  - the wrong number of productions was created');
    else
        disp('  - the right number of production cost values was created');
    end
    
    production_cost = test_model.productionCosts(1).value;
    
    if production_cost ~= 1015
        pf = 'fail';
        warning('  - an unexpected dual cost value was found');
    else
        disp('  - the expected dual cost value was found');
    end       

%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf); 
    
end                                        % TEST_UPDATE_PRODUCTION_COSTS()

%% TEST_UPDATE_VERTICES()                                         COMPLETED
function test_update_vertices()
    disp('Running NeighborModel.test_update_vertices()');
    pf = 'pass';
    
%   Create a test Market object.
    test_market = Market;
    
%   Create and store a TimeInterval object.
    dt = datetime; % datetime that may be used for most datetime arguments
    time_interval = TimeInterval(dt,Hours(1),test_market,dt,dt);
    test_market.timeIntervals = time_interval;

%   Create a test NeighborModel object.
    test_model = NeighborModel; 
    
%   Create and store a scheduled power IntervalValue in the active time
%   interval. 
    test_model.scheduledPowers = IntervalValue(test_model,...
        time_interval,test_market,'ScheduledPower',50);   
    
%   Create a Neighbor object and its maximum and minimum powers.
    test_object = Neighbor;
    test_object.maximumPower = 200;
    test_object.minimumPower = 0;
    test_object.lossFactor = 0; % eliminate losses from the calcs for now.
    
%   Have the Neighbor model and object cross reference one another.
    test_object.model = test_model;
    test_model.object = test_object;
    
%% TEST 1
    disp('- Test 1: No default vertex has been defined for the Neighbor');
    
    test_model.defaultVertices = [];
    
    warning('off','all');
    try
        test_model.update_vertices(test_market);
        disp('  - the method warned and returned, as designed.');
        warning('on','all');        
    catch
        pf = 'fail';
        warning('on','all');
        warning('  - the method encountered errors and stopped');
    end
    
%% TEST 2
    disp('- Test 2: The Neighbor is not transactive');
    
%   Create the default Vertex object.
     test_model.defaultVertices = Vertex(.1,0,100); 
     test_model.transactive = false;
     
    try
        test_model.update_vertices(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors and stopped');
    end   
    
    if length(test_model.activeVertices) ~= 1
        pf = 'fail';
        warning('  - there is an unexpected number of active vertices');
    else
        disp('  - the expected number of active vertices was found');
    end
    
    vertex = test_model.activeVertices(1).value;
    
    if vertex.power ~= 100 || vertex.marginalPrice ~= 0.1
        pf = 'fail';
        warning('  - the vertex values are not as expected');
    else
        disp(['  - the vertex values were derived from the default ',...
            'vertex as expected']);
    end   

    
%% TEST 3
    disp(['- Test 3: The Neighbor is transactive,',...
        'but transactive records are not available']);
    test_model.transactive = true;
    test_model.defaultVertices = Vertex(.2,0,200); % Changed 

    try
        test_model.update_vertices(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors and stopped');
    end   
    
    if length(test_model.activeVertices) ~= 1
        pf = 'fail';
        warning('  - there is an unexpected number of active vertices');
    else
        disp('  - the expected number of active vertices was found');
    end
    
    vertex = test_model.activeVertices(1).value;
    
    if vertex.power ~= 200 || vertex.marginalPrice ~= 0.2
        pf = 'fail';
        warning('  - the vertex values are not as expected');
    else
        disp(['  - the vertex values were derived from the default ',...
            'vertex as expected']);
    end       
    
%% TEST 4
    disp(['- Test 4: The Neighbor is transactive,',...
        'and a transactive records are available to use']); 
    test_model.transactive = true;
    
%   Create and store some received transactive records
    transactive_records(1) = TransactiveRecord(time_interval,1,0.15,0);
    transactive_records(2) = TransactiveRecord(time_interval,2,0.25,100);
    transactive_records(3) = TransactiveRecord(time_interval,0,0.2,50);
    test_model.receivedSignal = transactive_records;
    
    test_model.demandThreshold = 500;

    try
        test_model.update_vertices(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors and stopped');
    end   
    
    if length(test_model.activeVertices) ~= 2
        pf = 'fail';
        warning('  - there is an unexpected number of active vertices');
    else
        disp('  - the expected number of active vertices was found');
    end
    
    vertex = [test_model.activeVertices(:).value];
    vertex_power = [vertex.power];
    vertex_marginal_price = [vertex.marginalPrice];
    
    if any(~ismember([vertex_power],[0,100])) ...
            || any(~ismember([vertex_marginal_price],[0.1500, 0.2500]))
        pf = 'fail';
        warning('  - the vertex values are not as expected');
    else
        disp(['  - the vertex values were derived from the received ',...
            'transactive records as expected']);
    end   
    
%% TEST 5
    disp(['- Test 5: The Neighbor is transactive ',...
        'with transactive records, ', ...
        'and demand charges are in play']); 
    test_model.transactive = true;
    
%   Create and store some received transactive records
    transactive_records(1) = TransactiveRecord(time_interval,1,0.15,0);
    transactive_records(2) = TransactiveRecord(time_interval,2,0.25,100);
    transactive_records(3) = TransactiveRecord(time_interval,0,0.2,50);
    test_model.receivedSignal = transactive_records;
    
%   The demand threshold is being moved into active vertex range.
    test_model.demandThreshold = 80; % 

    try
        test_model.update_vertices(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors and stopped');
    end   
    
    if length(test_model.activeVertices) ~= 4
        pf = 'fail';
        warning('  - there is an unexpected number of active vertices');
    else
        disp('  - the expected number of active vertices was found');
    end
    
    vertex = [test_model.activeVertices(:).value];
    vertex_power = [vertex.power];
    vertex_marginal_price = [vertex.marginalPrice];
    
    if any(~ismember([vertex_power],[0,80,100])) ...
            || any(~ismember(single(vertex_marginal_price),...
            single([0.1500, 0.2300, 10.2500, 10.2300])))
        pf = 'fail';
        warning('  - the vertex values are not as expected');
    else
        disp(['  - the vertex values were derived from the received ',...
            'transactive records and demand threshold as expected']);
    end     
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
end                                                % TEST_UPDATE_VERTICES()

    end                                      % Static NeighborModel methods 

end                                                  %Classdef NeigborModel







