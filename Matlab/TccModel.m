classdef TccModel < LocalAssetModel
% TCCMODEL - A LocalAssetModel specialization that interfaces integrates
% the PNNL ILC and/or TCC building systems with the transactive network.
% TCC - Transactive Control & Coordination: Manages HVAC system load using
%   auctions at the various levels of the HVAC system (e.g., VAV boxes,
%   chillers, etc.)
% ILC - Integrated Load Control: Originally designed to limit total
%   building load below a prescribed threshold. Has been recently modified
%   to make the threshold price-responsive.
% This class necessarily redefines two methods: schedule_power() and
% update_vertices(). The methods call a "single market function" that was
% developed by Sen Huang at PNNL. This function simulates (using Energy
% Plus) building performance over a 24-hour period and replies with a
% series of records for each time interval. The records represent the
% minimum and maximum inflection points and are therefore very like Vertex
% objects.

%% TccModel Properties
    properties
        buildingRecords % The records returned by the "single-market 
                        % function"
    end                                               % TccModel Properties
    
%% TCCMODEL METHODS    
    methods
        
%% SCHEDULE_POWER()
function schedule_power(obj,mkt)
% SCHEDULE_POWER() - redefines method AbstractModel.schedule_power()
% obj = TccModel object
% mkt = Market object
% Method steps:
% 1. Call single_market_function(). The function performs a building
%    simulation and returns vertices of demand curves in the active time
%    intervals. The format of the returned records are [interval datetime,
%    bottom marginal price, top marginal price, bottom quantity, top
%    quantity].
% 2. Store the returned records (see new property bldngRcrds).
% 3. Interpolate on the stored vertices to find scheduled powers in all
%    active time intervals. 

%   Call a function that simulates multiple hours (24?) of building
%   operation and returns a table of records. For the Matlab version, the
%   table is a cell array of records as follows:
%   |t1,p1-,p1+,q1-,q1+|
%   |t2,p2-,p2+,q2-,q2+|
%   |      ...         |, where
%   t = datetime representing a time interval (probably the starting time,
%       but allowed to be any time in the time interval)
%   p- and p+ = lower and upper marginal prices of the time interval
%               [$/kWh] 
%   q- and q- = lower and upper quantities of the time interval [avg. W]
%               NOTE: convert to kW for use by network template.
    brs = single_market_function();
    
%   Gather active TimeInterval objects for which scheduled powers must be
%   determined.
    time_intervals = mkt.timeIntervals;                     % TimeIntervals
    
%   Gather the marginal prices in the active time intervals.
    marginal_prices = mkt.marginalPrices;                         % [$/kWh]
    
%   Count the number of building records (the number of columns in
%   buildingRecords). 
    [record_count,~] = size(brs);
    
%   Index through the building records.    
    for i = 1:record_count
 
%       First, check that the building is following the sign convention.
%       They are presumed to consume, never supply, electricity. Therefore,
%       power values must be negative. This check applies to the 4th and
%       5th record values.
        brs{i,4} = -abs(brs{i,4});                             % signed [W]
        brs{i,5} = -abs(brs{i,5});                             % signed [W] 

%       Find the active TimeInterval object that the indexed building
%       record is in (i.e., the building record's datetime is within the
%       active TimeInterval's period). A logical index is true if the
%       building record's datetime is both greater than an active
%       TimeInterval's start time and less than the following TimeInterval
%       start time.
        index = (brs{i,1} >= [time_intervals.startTime]) ...
            .* (brs{i,1} < [time_intervals.startTime] ...
            + mkt.intervalDuration);          % an array of logical indices
        
%       Pick out the matched time_interval.        
        ti = time_intervals(logical(index));        % A TimeInterval object
        
        if isempty(ti)
            
%           No time interval was found to match the time of the building
%           record. Continue to the next building record.
            continue;
            
        end                                                % if isempty(ti)

%       Find the marginal price in the matched active TimeInterval ti.     
        mp = findobj(marginal_prices,'timeInterval',ti(1));       % [$/kWh]
        
        if isempty(mp)
            
%           There is no marginal price defined in the time interval. The
%           default average power value must be assigned as the scheduled
%           power in this active TimeInterval ti.
            sp = obj.defaultPower;                               % [avg.kW]
            
        else
            
%           A marginal price was found in the matched TimeInterval. The
%           scheduled power may be interpolated from the building record's
%           prices and power values. NOTE: This code presumes that a
%           building record contains exactly two (price, quantity) pairs.
            if mp(1).value < min(brs{i,2:3})             % mp below minimum
                sp = min(brs{i,4:5});                             % [avg.W]
                
            elseif mp(1).value < max(brs{i,2:3})   % mp between min and max
                sp = min(brs{i,4:5}) ...
                    + (mp(1).value - min(brs{i,2:3})) ...
                    * (max(brs{i,4:5}) - min(brs{i,4:5})) ...
                    / (max(brs{i,2:3}) - min(brs{i,2:3}));        % [avg.W]
            else                                      % mp greater than max
                sp = max(brs{i,4:5});                      % [avg.W]
                
            end                            % if mp < min(bldngRcrds{i,2:3})

%           Convert scheduled power that was found from the building record
%           from Watts into killoWatts.
            sp = sp / 1000;                                      % [avg.kW]
        
        end                                                % if isempty(mp)

%       Check to see if a scheduled power exists yet in the matched time
%       interval.         
        iv = findobj(obj.scheduledPowers,'timeInterval',ti); 
                                                         % an IntervalValue

        if isempty(iv)
            
%           No scheduled power was found in the matched TimeInterval.
%           Create, assign its value, and store it.
            iv = IntervalValue(obj,ti,mkt,'ScheduledPower',sp); 
                                                         % an IntervalValue
                                                         
%           Append the scheduled power to the list of scheduled powers.
            obj.scheduledPowers = [obj.scheduledPowers,iv];
                                                         
        else
            
%           A scheduled power already exists in the matched TimeInterval.
%           Simply reassign its value.
            iv.value = sp;                                       % [avg.kW]
            
        end
   
    end                                            % for i = 1:record_count

%   Code must still check that scheduled powers are assigned for all active
%   TimeInterval objects.

%   Find active TimeIntervals for which there is no scheduled power value.
    ind = ~ismember(mkt.timeIntervals,[obj.scheduledPowers.timeInterval]);
                                                     % an array of logicals

%   Identify TimeInterval objects ti for which there is no scheduled power
%   value.
    ti = time_intervals(ind);                        % TimeInterval objects

%   For each missing scheduled power, create an IntervalValue and assign it
%   with the default average power.
    for i = 1:length(ti)
        iv = IntervalValue(obj,ti(i),mkt,'ScheduledPower',...
            obj.defaultPower);

%       Append the new IntervalValue objects to the list of scheduled
%       powers.
        obj.scheduledPowers = [obj.scheduledPowers,iv];
    
    end                                                % for i = length(ti)
   
%   Save the building records in new property buildingRecords.    
    obj.buildingRecords = brs;

end                                                      % SCHEDULE_POWER()

%% UPDATE_VERTICES()
function update_vertices(obj,mkt)
% UPDATE_VERTICES() - redefines method AbstractModel.update_vertices()
% 1. Index through the stored returned values from the single market
%    function (see property buildingRecords).
% 2. Convert the contents of property buildingRecords into active vertices
%    (see struct Vertex) and store them(see property activeVertices).

%   Gather the building records, from which vertices will be
%   created/updated. These building records were stored by method
%   schedule_powers(). 
    brs = obj.buildingRecords;
    [nr,~] = size(brs);                          % number of records (rows)
    
%   Gather active TimeInterval objects for which scheduled powers must be
%   determined.
    time_intervals = mkt.timeIntervals;                     % TimeIntervals      
    
%   Index through the building records that were received from ILC.    
    for i = 1:nr
        
%       Find the active TimeInterval object that the indexed building
%       record is in (i.e., the building record's datetime is within the
%       active TimeInterval's period). A logical index is true if the
%       building record's datetime is both greater than an active
%       TimeInterval's start time and less than the following TimeInterval
%       start time.
        index = (brs{i,1} >= [time_intervals.startTime]) ...
            .* (brs{i,1} < [time_intervals.startTime] ...
            + mkt.intervalDuration);          % an array of logical indices
        
%       Pick out the matched time_interval.        
        ti = time_intervals(logical(index));        % A TimeInterval object
 
%       Recast the building record as a pair of Vertex objects. Note: this
%       code presumes that exactly two points are created by the ILC
%       function. Note: This code forces points to be properly paired with
%       monotonically increasing prices and quanties. That is, the lowest
%       price is always paired with the lowest signed average power.
        v1 = Vertex(min(brs(i,2:3)),0,min(brs(i,4:5)));
        v2 = Vertex(max(brs(i,2:3)),0,max(brs(i,4:5)));
 
%       Create the two interval values iv for the two Vertex objects v.        
        iv(1) = IntervalValue(obj,ti,mkt,'ActiveVertex',v1);
        iv(2) = IntervalValue(obj,ti,mkt,'ActiveVertex',v2);
 
%       Discard existing active vertices in the record's time interval and
%       replace them this the newly created ones.
        iav = ~ismember([obj.activeVertices.timeInterval],ti);
        obj.activeVertices = [obj.activeVertices(iav),iv];     
   
    end                                                      % for i = 1:nr
    
%   Now that active vertices have been created for all building records, we
%   must check that an active vertex exists for every active time interval.
%   If not, one must be created using the default active vertex.
%   Find active TimeIntervals for which there is no scheduled power value.
    ind = ~ismember(mkt.timeIntervals,[obj.activeVertices.timeInterval]);
                                                     % an array of logicals

%   Identify TimeInterval objects ti for which there are no active
%   vertices. 
    ti = time_intervals(ind);                        % TimeInterval objects

%   For each missing active vertex, create an IntervalValue iv and assign
%   it with the default active vertices. Note: there may be more than one
%   default active vertex defined.
%   Index throught the time intervals ti for which no active vertices
%   exist. 
    for i = length(ti)
        
%       Index through the default vertices to be assigned where active
%       vertices are missing.
        for j = length(obj.defaultVertices)

%           Create an interval value iv for each default vertex.
            iv = IntervalValue(obj,ti(i),mkt,'ActiveVertex',...
                obj.defaulVertices(j));
            
%           Append the new IntervalValue to the list of active vertices.
            obj.activeVertices = [obj.activeVertices,iv];  
                
        end                           % for j = length(obj.defaultVertices)
        
    end                                                % for i = length(ti)

end                                                     % UPDATE_VERTICES()

    end                                                  % TCCMODEL METHODS
    
%% STATIC TCCMODEL METHODS
    methods (Static)
        
%% TEST_ALL()
function test_all()
% TEST_ALL() - Test all the TccModel methods.
    disp('Running TccModel.test_all()');
    TccModel.test_schedule_power();
    TccModel.test_update_vertices();
end % % TEST_ALL()

%% TEST_SCHEDULE_POWER()
function test_schedule_power()
% TEST_SCHEDULE_POWER() - test the method TccModel.schedule_power().
    disp('Running TccModel.test_schedule_power()');
    pf = 'pass';
 
% NOTE: Function single_market_function() has been appended to this class
% definition. It simply assigns a small table using the format I understand
% to be received from the ILC/TCC building functions.

% Create a test IlcModel model.
    test_model = TccModel;
    
% Configure a default power that will be used in test.
    test_model.defaultPower = -75;                               % [avg.kW]
    
% Create a test market
    test_market = Market;
    
% Create some active time intervals. Create more than the three building
% records so we can excercise the assignment of default power.
    dt = datetime;
    ti(1) = TimeInterval(dt,Hours(1),test_market,dt,dt);
    ti(2) = TimeInterval(dt,Hours(1),test_market,dt,dt+Hours(1));    
    ti(3) = TimeInterval(dt,Hours(1),test_market,dt,dt+Hours(2));
    ti(4) = TimeInterval(dt,Hours(1),test_market,dt,dt+Hours(3)); 
    ti(5) = TimeInterval(dt,Hours(1),test_market,dt,dt+Hours(4));  
    
    test_market.timeIntervals = ti;
    
% Create marginal prices in these active time intervals to challenge the
% assignments of scheduled powers using the buidling records.
    mp = [0.045, 0.05, 0.055, 0.06, 0.065];
    for i = 1:5;
        iv(i) = IntervalValue(test_model,ti(i),test_market,...
            'MarginalPrice',mp(i));
    end
    test_market.marginalPrices = iv;
    
    try 
        test_model.schedule_power(test_market);
        disp('- the method ran without errors');
    catch
        pf = 'fail';
        warning('- the method encountered errors and stopped');
    end
    
    if length(test_model.scheduledPowers) ~= 5
        pf = 'fail';
        warning('- an unexpected number of scheduled powers was created');
    else
        disp('- the expected number of scheduled powers were created');
    end
            
    if any(~ismember([test_model.scheduledPowers.value],...
            [-90,-95,-100, -75]))
        pf = 'fail';
        warning('- the scheduled power values were not as expected');
    else
        disp('- the scheduled power values were as expected');
    end
    
% NOTE: the ACTUAL one_market_function method should probably be tested to
% ensure that (1) it may be called soon after it was initially called to
% support iterations.
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);    
    
end                                                 % TEST_SCHEDULE_POWER()

%% TEST_UPDATE_VERTICES()
function test_update_vertices()
% TEST_UPDATE_VERTICES() - test the method TccModel.update_vertices().
    disp('Running TccModel.test_update_vertices()');
    pf = 'test not yet completed';
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);    
    
end                                                % TEST_UPDATE_VERTICES()
    
    end                                           % STATIC TCCMODEL METHODS

end                                   % classdef TccModel < LocalAssetModel

function [ csv_table ] = single_market_function()
% SINGLE_MARKET_FUNCTION - Emulates the returns records from a building
% simulation as a cell array of records having format [datetime, bottom
% marginal price, top marginal price, bottom quantity, top quantity].
% NOTE: The network template uses signed power. Demand is negative.
dt = datetime + Hours(1);
p1 = 0.05;                                                        % [$/kWh]
p2 = 0.06;                                                        % [$/kWh]
q1 = -90e3;                                                       % [avg.W]
q2 = -100e3;                                                      % [avg.W]

% Here's a small table that should suffice for testing.
csv_table =    {dt,p1,p1,q1,q1;
                dt + Hours(1),p1,p2,q1,q2;
                dt + Hours(2),p2,p2,q2,q2 };

end