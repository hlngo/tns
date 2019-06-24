classdef BulkTempRespLoadModel < LocalAssetModel
%BULKTEMPRESPLOADMODEL subclass of LocalAssetModel
% (NOTE: An improved model has been created specifically for City of
% Richland, WA load. See the CorLoadForecast class.)
% A parametric model to represent the dynamics of non-transactive bulk
% load. This model is suitable for aggregated loads (e.g., utility load,
% distribution feeder circuits, commercial or residential loads). The model
% is responsive to many parameters, but it is price-inelastic, so it offers
% a constant, inelastic demand curve.
%   - Introduces properties that are suitable model inputs
%   - Schedules power based on paramters other than price
    
%% BulkTempRespLoadModel properties
% The first four default property values are based on the Peninsula
% Light chapter of the Pacific Northwest Smart Grid Demonstration Project
% Technology Performance Report: Volume 1: Technology Performance
% concerning temperature sensitive residential homes on Fox Island, WA.
% (Online at
% https://www.smartgrid.gov/files/TPR15PeninsulaLightCompanyTests.pdf)
% NOTE: Normally, the coolingRise should be positive; the heatingRise neg.
% The scaling factor must be reassigned to represent the magnitude of load.
    properties
        basePower = 1.311                                        % [avg.kW]
        coolingRise = 0.00137 % power increase with cooling deg. [kW/deg.F]
        heatingRise = -0.115  % power increase with heating deg. [kW/deg.F]
        inflectionTemp = 56.7        % intersection of temp. curves [deg.F]
        scalingFactor = 1                    % model multiplier [pos. int.]
    end                                  % BulkTempRespLoadModel properties
    
%% BulkTempRespLoadModel methods    
    methods
        
%% FUNCTION SCHEDULE_POWER()
function schedule_power(obj,mkt)
% SCHEDULE_POWER() - predict bulk power using a simple, pseudo-static
% temperature dependence. The model may be used to predict performance of
% bulk circuits like feeder or building populations. The model is NOT
% price-responsive.  

%   Gather the list of active time intervals
    ti = mkt.timeIntervals;
    
%   Find the information service concerning temperature forecasts (there
%   might be multiple information services).
    is = findobj(obj.informationServiceModels{:},'informationType',...
        MeasurementType.temperature);
    
%   Index through the time intervals    
    for i = 1:length(ti)
        
%       Retreive the forecasted temperature in the indexed time interval        
        temp = findobj(is.predictedValues,'timeInterval',ti(i));

        if isempty(temp) || isnan(temp)
            
%           No forecast temperature was found in the indexed time interval.
%           The default power must be used.
            p = obj.defaultPower;
            
        else
            
%           The forecast temperature was found. Extract the temperature
%           value.            
            temp = temp(1).value; 
            
%           Begin the power prediction from the base power value.
            p = obj.basePower;
    
            if temp >= obj.inflectionTemp

%               Cooling mode formula
                p = p + obj.coolingRise * (temp - obj.inflectionTemp);

            elseif temp <= obj.inflectionTemp

%               Heating mode formula
                p = p + obj.heatingRise * (temp - obj.inflectionTemp);   

            end                             % if temp >= obj.inflectionTemp

        end                                              % if isempty(temp)
        
%       Scheduled power p has been calculated. Check if the scheduled power
%       exists in the indexed time interval.
        iv = findobj(obj.scheduledPowers,'timeInterval',ti(i));
        
        if isempty(iv)
            
%           The scheduled power value does not exist in indexed time
%           interval. Create and store one.
            iv = IntervalValue(obj,ti(i),mkt,'ScheduledPower',p);
            obj.scheduledPowers = [obj.scheduledPowers,iv];
            
        else
            
%           The scheduled power already exists in the indexed time
%           interval. Simply reassign its value.
            iv(1).value = p;

        end                                                % if isempty(iv)
        
    end                                                    % for indexing i

end                                             % FUNCTION SCHEDULE_POWER()

    end                                     % BulkTempRespLoadModel Methods
    
%% Static BulkTempRespLoadModel Methods
    methods (Static)

%% TEST_SCHEDULE_POWER()
function test_schedule_power()
    disp('Running BulkTempRespLoadModel.test_schedule_power()');
    pf = 'test not completed';
    
% NOTE: A regression model is being prepared to replace the current one.
% The test should be written to that capability.

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
end                                                 % TEST_SCHEDULE_POWER()
        
    end
    
end

