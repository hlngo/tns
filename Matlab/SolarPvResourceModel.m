classdef SolarPvResourceModel < LocalAssetModel
% SolarPvResourceModel Subclass for renewable solar PV generation The Solar
% PV resource is treated here as a must-take resource. This is unlike
% dispatchable resources in this regard. Production may be predicted.
% The main features of this model are (1) the introduction of property
% cloudFactor, an IntervalValue, that allows us to reduce the expected
% solar generation according to cloud cover, and (2) method
% solar_generation() that creates the envelope, best-case, power production
% for the resource as a function of time-of-day.

%% New SolarPvResourceModel properties
    properties
        cloudFactor = 1.0
    end                               % New SolarPvResourceModel properties
    
%% SolarPvResourceModel methods    
    methods
        
%% FUNCTION schedule_power()
function schedule_power(obj, mkt)
% Function schedule_power() - estimate stochastic generation from a solar
% PV array as a function of time-of-day and a cloud-cover factor.
%   INPUTS:
%       obj - SolarPvResourceModel class object
%       tod - time of day
%   OUTPUTS:
%       p - calcalated maximum power production at this time of day
%   LOCAL:
%       h - hour (presumes 24-hour clock, local time)
% *************************************************************************

%   Gather active time intervals
    ti = mkt.timeIntervals;
    
%   Index through the active time intervals ti
    for i = 1:length(ti)
        
%       Production will be estimated from the time-of-day at the center of
%       the time interval.
%       NOTE: Function Hours() corrects behavior of Matlab's hours().
        tod = datetime(ti(i).startTime) ...
            + 0.5 * Hours(ti(i).duration);                     % a datetime
        
%       extract a fractional representation of the hour-of-day
        h = hour(tod);
        m = minute(tod);
        h = h + m/60;                       %TOD stated as fractional hours   
        
%       Estimate solar generation as a sinusoidal function of daylight
%       hours.
        if h < 5.5 || h > 17.5
            
%           The time is outside the time of solar production. Set power to
%           zero.
            p = 0.0;                                              %[avg.kW]

        else
            
%           A sinusoidal function is used to forecast solar generation
%           during the normally sunny part of a day.            
            p = 0.5 * (1 + cos( (h - 12) * 2.0 * pi / 12)); 
            p = obj.object.maximumPower * p;
            p = obj.cloudFactor * p;                              %[avg.kW]
            
        end                                                             %if
        
%       Check whether a scheduled power exists in the indexed time
%       interval.         
        iv = findobj(obj.scheduledPowers,'timeInterval',ti(i));
        
        if isempty(iv)
            
%           No scheduled power value is found in the indexed time interval.
%           Create and store one.
            iv = IntervalValue(obj,ti(i),mkt,"ScheduledPower",p);
                                                             %IntervalValue
%           Append the scheduled power to the list of scheduled powers.            
            obj.scheduledPowers = [obj.scheduledPowers,iv]; %IntervalValues
            
        else
            
%           A scheduled power already exists in the indexed time interval.
%           Simply reassign its value.
            iv.value = p;                                         %[avg.kW]
            
        end                                                             %if
        
%% Assign engagement schedule in the indexed time interval
%       NOTE: The assignment of engagement schedule, if used, will often be
%       assigned during the scheduling of power, not separately as
%       demonstrated here.
        
%       Check whether an engagement schedule exists in the indexed time
%       interval
        iv = findobj(obj.engagementSchedule,'timeInterval',ti(i));  
                                                          %an IntervalValue
        
%       NOTE: this template assigns engagement value as true (i.e.,
%       engaged).  
        val = true;                          %Asset is committed or engaged
        
        if isempty(iv)
            
%           No engagement schedule was found in the indexed time interval.
%           Create an interval value and assign its value. 
            iv = IntervalValue(obj,ti(i),mkt,'EngagementSchedule',val); 
                                                          %an IntervalValue
            
%           Append the interval value to the list of active interval
%           values
            obj.engagementSchedule = [obj.engagementSchedule,iv]; 
                                                            %IntervalValues
            
        else
            
%           An engagement schedule was found in the indexed time interval.
%           Simpy reassign its value.
            iv.value = val;                                            %[$]
            
        end                                                             %if

    end                                                      %indexing on i
    
%   Remove any extra scheduled powers
    xsp = ismember([obj.scheduledPowers.timeInterval],ti);
                                                      %an array of logicals
    obj.scheduledPowers = obj.scheduledPowers(xsp);         %IntervalValues
    
%   Remove any extra engagement schedule values     
    xes = ismember([obj.engagementSchedule.timeInterval],ti);
                                                      %an array of logicals
    obj.engagementSchedule = obj.engagementSchedule(xes);   %IntervalValues        

end                                              %function schedule_power()
    
    end                                      % SolarPvResourceModel methods  
    
%% Static SolarPvResourceModel Methods
methods (Static)
    
%% TEST_ALL()
function test_all()
% TEST_ALL - test all class methods
    disp('Running SolarPvResourceModel.test_all()');
    SolarPvResourceModel.test_schedule_power();
end                                                            % TEST_ALL()

%% TEST_SCHEDULE_POWER()
function test_schedule_power()
    disp('Running SolarPvResourceModel.test_schedule_power()');
    pf = 'test not completed yet';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up the class space
    clear test_obj
end                                                 % TEST_SCHEDULE_POWER()
    
end                                   % Static SolarPvResourceModel Methods
    
end                        % classdef SolarPvResoureModel < LocalAssetModel

