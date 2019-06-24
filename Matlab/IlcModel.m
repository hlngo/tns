classdef IlcModel < LocalAssetModel
% ILCMODEL - "glue" to a building Intelligent Load Control (ILC) system
% ILC is an existing building control system. This class is used to ensure
% that it provides the necessary information and behaviors to a
% computational agent in a transactive network.
% The ILC is able to curtail a specified amount of power below a baseline
% consumption. That is, the building operator can state, for example, that
% the building must reduce its load by, say, 10 kW, and the reduction is
% obtained from flexible loads, which are queued to do so.
% This method automates this process, making the curtailment amounts
% respond to predicted price signals in a series of active future time
% intervals.
% Because the ILC design preceded the design of the transactive network,
% this class must interact with the existing ILC code.
    
%% New IlcModel Properties
% NOTE: Numerous properties are inherited from the LocalAssetModel class.
    properties
%       NOTE: By sign convention, electric load is negative, curtailment is
%       a positive increase in load.
        reductions = IntervalValue.empty % targetted curtailment reductions [avg.kW]
        currentReduction  % reduction in the current time interval [avg.kW]
        maximumReduction               % maximum allowed reduction [avg.kW]
        responseGain = 1 % positive factor. Increase to REDUCE price sensitivity
    end                                           % New IlcModel Properties
    
%% IlcModel Methods    
methods
        
%% FUNCTION SCHEDULE_POWER()
function schedule_power(obj,mkt)
% SCHEDULE_POWER() - predict power consumption of the ILC system
% NOTE: If the predicted load is not the entire building load, additional
% LocalAssets and LocalAssetModel objects must be instantiated until the
% entire building load is being predicted for the building transactive
% node.
% obj - IlcModel object
% mkt - Market object

%   Get the list of active time intervals, and make sure they are sorted by
%   their starting times.
    time_intervals = mkt.timeIntervals;  % a series of TimeInterval objects
    [~,ind] = sort([time_intervals.startTime]);
    time_intervals = time_intervals(ind);
   
%   Get the list of active marginal prices (at the building node).
    marginal_prices = mkt.marginalPrices;                         % [$/kWh]
 
%   Calculate the average of the active marginal prices. This will be used
%   to calibrate the response to a "typical" price.
    average_marginal_price = mean([marginal_prices.value]); %       [$/kWh]
  
%   Calculate the standard deviation of the active marginal prices. This
%   will be used to scale the response in light of price variability.
    standard_deviation_of_marginal_prices = std([marginal_prices.value]);
                                                                  % [$/kWh]
    
%   Calculate the number of active time intervervals, to which average
%   power consumption values must be assigned.
    number_of_time_intervals = length(time_intervals);          % [integer]
 
%   Index through the active time intervals.
    for i = 1:number_of_time_intervals
       
%       Pick out the indexed time interval.
        time_interval = time_intervals(i);          % a TimeInterval object
        
%       Pick out the marginal price in the indexed time interval.
        marginal_price = findobj(marginal_prices,'timeInterval',...
            time_interval);                       % an IntervalValue object
        marginal_price = marginal_price.value;   % a marginal price [$/kWh]
        
%       Calculate a relative marginal price, meaning a location relative to the
%       interval [-k*std, k*std], where k is the gain factor and std is the
%       standard deviation of marginal prices. The calculation defines a
%       new range [-1,1] that corresponds to [-k*std,k*std].
        relative_marginal_price = ...
            (marginal_price - average_marginal_price) ...
            / (obj.responseGain * standard_deviation_of_marginal_prices);
                                                          % [dimensionless]
        
%       The relative marginal price should be constrained to the range
%       [-1,1]. An additional design decision is made to eliminate negative
%       values, which means that ILC will not respond to prices that are
%       BELOW the average marginal price.
        if relative_marginal_price < 0
            relative_marginal_price = 0;
        elseif relative_marginal_price > 1
            relative_marginal_price = 1;
        end                                % if relative_marginal_price < 0
        
%       Finally, the relative marginal price is used to scale the
%       curtailment reduction in the indexed time interval.
        reduction = relative_marginal_price * obj.maximumReduction;
        
%       Assign the current reduction level if we are in the Delivery market
%       state.
        if i==1
            obj.currentReduction = reduction;
        end
       
%       Try to find the reduction interval value in the indexed time
%       interval.
        interval_value = findobj(obj.reductions,'timeInterval',...
            time_interval);                       % an IntervalValue object
        
        if isempty(interval_value)
            
%           No such interval value was found. Create one.            
            interval_value = IntervalValue(obj,time_interval,mkt,...
                'Reduction',reduction);           % an IntervalValue object
            
%           Append the interval value to the list of reduction interval
%           values.
            obj.reductions = [obj.reductions,interval_value]; 
                                                    % IntervalValue objects
            
        else
            
%           The interval value already exists. Simply reassign its value.
            interval_value(1).value = reduction;                 % [avg.kW]
            
        end
        
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% At this point, the ILC system must be queried to learn the predicted
% BASELINE consumptin in the indexed time interval, meaning the predicted
% load if no curtailment were to occur. NOTE: If the response of the ILC
% system does not include the entire building load, additional LocalAsset
% and LocalAssetModel objects must be instantiated until the entire
% building load is being predicted.
%       baseline_load = query(ilc_object,time_interval);         % [avg.kW]
        baseline_load = -50;       % assigned for testing purposes [avg.kW]
% NOTE: baseline load should be a NEGATIVE number.
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%       Calculate the scheduled power, which might be changed by the
%       curtailment reduction.
        scheduled_power = baseline_load + reduction;             % [avg.kW]
        
%       Try to find the scheduled power interval value in this time
%       interval.
        interval_value = findobj(obj.scheduledPowers,'timeInterval',...
            time_interval);
        
        if isempty(interval_value)
            
%           The scheduled power interval value was not found. Create it.
            interval_value = IntervalValue(obj,time_interval,mkt,...
                'ScheduledPower',scheduled_power);% an IntervalValue object
            
%           Append the interval value to the scheduled powers.
            obj.scheduledPowers = [obj.scheduledPowers,interval_value];
                                                    % IntervalValue objects
            
        else
            
%           The sheduled power interval value already exists. Simply
%           reassign its value.
            interval_value.value = scheduled_power;              % [avg.kW]
            
        end                                    % if isempty(interval_value)
 
    end                                              % for i = 1:length(ti)

end                                             % FUNCTION SCHEDULE_POWER()

    end                                                  % IlcModel Methods 
    
%% Static IlcModel Methods
methods (Static)
    
%% TEST_ALL()                                                     COMPLETED
function test_all()
% TEST_ALL() - test all the IlcModel methods
    disp('Running IlcModel.test_all()');
    IlcModel.test_schedule_power()
end                                                            % TEST_ALL()

%% TEST_SCHEDULE_POWER()                                          COMPLETED
function test_schedule_power()
% TEST_SCHEDULE_POWER() - test method shedule_power()
    disp('Running IlcModel.test_schedule_power()');
    pf = 'pass';
 
%   Create a test market
    test_mkt = Market;
    
%   Create and store time intervals
    dt = datetime;
    at = datetime;
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = dt;
    time_intervals(1) = TimeInterval(at,dur,mkt,mct,st);
    st = st + dur;
    time_intervals(2) = TimeInterval(at,dur,mkt,mct,st);
    st = st + dur;
    time_intervals(3) = TimeInterval(at,dur,mkt,mct,st);
    test_mkt.timeIntervals = time_intervals;
    
%   Create and store marginal prices
    interval_values(1) = IntervalValue(test_mkt,time_intervals(1),...
        test_mkt,'MarginalPrice',0.1);
    interval_values(2) = IntervalValue(test_mkt,time_intervals(2),...
        test_mkt,'MarginalPrice',0.2);
    interval_values(3) = IntervalValue(test_mkt,time_intervals(3),...
        test_mkt,'MarginalPrice',0.3);  
    test_mkt.marginalPrices = interval_values;
    
%   Create a test object
    test_obj = IlcModel;
    test_obj.maximumReduction = 10;
    test_obj.responseGain = 1;    
    
%   Run the test
    try
        test_obj.schedule_power(test_mkt);
        disp('- the method ran without errors');
    catch
        pf = 'fail';
        warning('- the method encountered errors');
    end
    
    if any(abs([test_obj.reductions.value] - [0, 0, 10.0]) > 0.001)
        pf = 'fail';
        warning('- incorrect reduction values were assigned');
    else
        disp('- the correct reduction values were assigned');
    end

    if length(test_obj.scheduledPowers) ~= 3
        pf = 'fail';
        warning(['- the method created the wrong number of scheduled ',...
            'power values']);
    else
        disp(['- the method created the right number of scheduled ',...
            'power values']);
    end   

%   Success
    disp('- the test ran to completion');
    fprintf('Results %s\n\n',pf);
    
%   Clean up the variable space
    clear test_mkt test_obj time_intervals interval_values

end                                                 % TEST_SCHEDULE_POWER()

end                                               % Static IlcModel Methods
    
end

