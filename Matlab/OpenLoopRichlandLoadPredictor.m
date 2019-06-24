classdef OpenLoopRichlandLoadPredictor < LocalAssetModel
% OPENLOOPRICHLANDLOADPREDICTOR - predicted electrical load of the City of
% Richland using hour-of-day, season, heating/cooling regime, and
% forecasted Fahrenheit temperature.

% Uses Excel file "Richland_Load_Model_Coefficients.xlsx."
% Predictor formula
% LOAD = DOW_Intercept(DOW) 
%           + HOUR_SEASON_REGIME_Intercept(HOUR,SEASON,REGIME) 
%           + Factor(HOUR,SEASON,REGIME) * TEMP
%   DOW_Intercept - average kW - Addend that is a function of categorical
%       day-of-week.
%   HOUR - Categorical hour of day in the range [1, 24]
%   HOUR_SEASON_REGIME_Factor - avg.kW / deg.F - Factor of TEMP. A function
%       of categoricals HOUR, SEASON, and REGIME.
%   HOUR_SEASON_REGIME_Intercept - average kW - Addend that is a function
%       of categoricals HOUR, SEASON, and REGIME.
%   LOAD - average kW - Predicted hourly Richland, WA electric load 
%   REGIME - Categorical {"Cool", "Heat", or "NA"}. Applies only in seasons
%       Spring and Fall. Not to be used for Summer or Winter seasons.
%   SEASON - Categorical season
%       "Spring" - [Mar, May]
%       "Summer" - [Jun, Aug]
%       "Fall"   - [Sep, Nov]
%       "Winter" - [Dec, Feb]
%   TEMP - degrees Fahrenheit - a predicted hourly temperature forecast.

%% Constant OpenLoopRichlandLoadPredictor properties
properties (Constant)
%   DOW_INTERCEPT - addend as function of day-of-weak [avg.kW]
    dowIntercept = [    138118, ... % Sunday
                        144786, ... % Monday
                        146281, ... % Tuesday
                        146119, ... % Wednesday
                        145577, ... % Thursday
                        143896, ... % Friday
                        139432]     % Saturday
%   SEASON - Maps categorical SEASON to the lookup table as a function of
%       MONTH.                  
    season = [  6, ...  % January   Winter
                6, ...  % February  Winter
                1, ...  % March     Spring
                1, ...  % April     Spring
                1, ...  % May       Spring
                3, ...  % June      Summer
                3, ...  % July      Summer
                3, ...  % August    Summer
                4, ...  % September Fall
                4, ...  % October   Fall
                4, ...  % November  Fall
                6]      % December  Winter
end                     % Constant OpenLoopRichlandLoadPredictor properties
    
%% OpenLoopRichlandLoadPredictor Methods    
methods
    
%% FUNCTION SCHEDULE_POWER()
function schedule_power(obj,mkt)
% SCHEDULE_POWER() - predict municipal load
% This is a model of non-price-responsive load using an open-loop
% regression model.

%   Get the active time intervals.
    time_intervals = mkt.timeIntervals;              % TimeInterval objects
    
%   Look for an information service that provides temperature.
    temperature_forecaster = findobj(obj.informationServiceModels{:},...
        'informationType','temperature');    
 
%   Index through the active time intervals.    
    for i = 1:length(time_intervals)
        
%       Pick out the indexed time interval.
        time_interval = time_intervals(i);

%       Extract the start time from the indexed time interval.        
        interval_start_time = time_interval.startTime;
 
        if isempty(temperature_forecaster)
            
            % No appropriate information service was found, must use a
            % default temperature value.
            TEMP = 56.6;                                          % [deg.F]
            
        else
            
%           An appropriate information service was found. Get the
%           temperature that corresponds to the indexed time interval.
            interval_value = ...
                findobj(temperature_forecaster(1).predictedValues,...
                'timeInterval',time_interval);           % an IntervalValue
            
            
            if isempty(interval_value)
                
%               No stored temperature was found. Assign a default value.
                TEMP = 56.6;                                      % [def.F]
                
            else
                
%               A stored temperature value was found. Use it.
                TEMP = interval_value(1).value;                   % [def.F] 
                
            end                                % if isempty(interval_value)
   
            if isnan(TEMP)
                
%               The temperature value is not a number. Use a default value.
                TEMP = 56.6;                                      % [def.F] 
                
            end                                            % if isnan(TEMP)
            
        end                            % if isempty(temperature_forecaster)

%       Determine the DOW_Intercept.
%       The DOW_Intercept is a function of categorical day-of-week number
%       DOWN. Calculate the weekday number DOWN.
        DOWN = weekday(interval_start_time);
        
%       Look up the DOW_intercept from the short table that is among the
%       class's constant properties.
        DOW_Intercept = obj.dowIntercept(DOWN);   
        
%       Determine categorical HOUR of the indexed time interval. This will
%       be needed to mine the HOUR_SEASON_REGIME_Intercept lookup table.
%       The hour is incremented by 1 because the lookup table uses hours
%       [1,24], not [0,23].
        HOUR = hour(interval_start_time) + 1;
        
%       Determine the categorical SEASON of the indexed time interval.
%       SEASON is a function of MONTH, so start by determining the MONTH of
%       the indexed time interval.      
        MONTH = month(interval_start_time);
        
%       Property season provides an index for use with the 
%       HOUR_SEASON_REGIME_Intercept lookup table.
        SEASON = obj.season(MONTH);
        
%       Determine categorical REGIME, which is also an index for use with
%       the HOUR_SEASON_REGIME_Intercept lookup table.
        REGIME = 0;             % The default assignment
        if (SEASON == 1 ...     % (Spring season index
            || SEASON == 4) ... % OR Fall season index)
            && TEMP <= 56.6     % AND Heating regime
                REGIME = 1; 
        end
        
%       Calcualte the table row. Add final 1 because of header row.
        row = 6*(HOUR - 1) + SEASON + REGIME;
        
%       Increment the row number by 1 due to the header row.
        row = row + 1;

%       State the Excel filename, sheet, and cells where the indexed data
%       will be found.
        filename = 'Richland_Load_Model_Coefficients.xlsx';
        sheet = "Hourly";                % Double quotes ensure string type
        range = string(compose('E%i:F%i',row,row));

%       Read the Intercept and Factor from the Excel file.
        [num] = xlsread(filename,sheet,range);

%       Assign the Intercept and Factor values that were found.
        HOUR_SEASON_REGIME_Intercept = num(1);
        HOUR_SEASON_REGIME_Factor = num(2);
        
%       Finally, predict the Richland load.
        LOAD = DOW_Intercept ...
            + HOUR_SEASON_REGIME_Intercept ...
            + HOUR_SEASON_REGIME_Factor * TEMP;                  % [avg.kW]
        
%       The table defined electric load as a positive value. The network
%       model defines load as a negative value.
        LOAD = -LOAD;                                            % [avg.kW]
        
%       Look for the scheduled power in the indexed time interval.
        interval_value = findobj(obj.scheduledPowers,'timeInterval',...
            time_interval);
        
        if isempty(interval_value)
            
%           No scheduled power was found in the indexed time interval.
%           Create one and store it.
            interval_value = IntervalValue(obj,time_interval,mkt,...
                'ScheduledPower',LOAD);
            
            obj.scheduledPowers = [obj.scheduledPowers, interval_value];
            
        else
            
%           The interval value already exist. Simply reassign its value.
            interval_value.value = LOAD;
            
        end                                    % if isempty(interval_value)
  
    end                                  % for i = 1:length(time_intervals)

end                                             % FUNCTION SCHEDULE_POWER()

end                                 % OpenLoopRichlandLoadPredictor Methods
    
%% Static OpenLoopRichlandLoadPredictor Methods    
methods (Static)
        
%% TEST_ALL()  
function test_all()
% TEST_ALL() - test all the class methods
    disp('Running OpenLoopRichlandLoadPredictor.test_all()');
    OpenLoopRichlandLoadPredictor.test_schedule_power();
end                                                            % TEST_ALL()

%% TEST_SCHEDULE_POWER()
function test_schedule_power()
    disp('Running OpenLoopRichlandLoadPredictor.test_schedule_power()');
    pf = 'pass';
    
%   Create a OpenLoopRichlandLoadPredictor test object.
    test_obj = OpenLoopRichlandLoadPredictor;

%   Create a test Market object.
    test_mkt = Market;

%   Create and store a couple TimeInterval objects at a known date and
%   time.
    dt = datetime(2017,11,01,12,0,0); %Wednesday Nov. 1, 2017 at noon
    at = dt;
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = dt;
    test_intervals(1) = TimeInterval(at,dur,mkt,mct,st);
    
    st = st + dur; % 1p on the same day
    test_intervals(2) = TimeInterval(at,dur,mkt,mct,st);
    
    test_mkt.timeIntervals = test_intervals;
    
%   Create a test TemperatureForecastModel object and give it some
%   temperature values in the test TimeIntervals.
    test_forecast = TemperatureForecastModel;
%       The information type should be specified so the test object will
%       correctly identivy it.
        test_forecast.informationType = 'temperature';
%     test_forecast.update_information(test_mkt);
        test_forecast.predictedValues(1) = ...
          IntervalValue(test_forecast,test_intervals(1),test_mkt,...
          'Temperature',20); % Heating regime
      test_forecast.predictedValues(2) = ...
          IntervalValue(test_forecast,test_intervals(2),test_mkt,...
          'Temperature',100); % Cooling regime
%     Matlab has some quirks concerning lists versus cell arrays. The
%     method
      test_obj.informationServiceModels = {test_forecast};

% Manually evaluate from the lookup table and the above categorical inputs
% DOW = Wed. ==> 
    Intercept1 = 146119;
    Intercept2 = 18836;
    Intercept3 = -124095;
    Factor1 = -1375;
    Factor2 = 1048;
    Temperature1 = 20;
    Temperature2 = 100;
    
    LOAD(1) = -(Intercept1 + Intercept2 + Factor1 * Temperature1);
    LOAD(2) = -(Intercept1 + Intercept3 + Factor2 * Temperature2);      
      
      try
          test_obj.schedule_power(test_mkt);
          disp('- the method ran without errors');
      catch
          pf = 'fail';
          warning('- the method had errors when called');
      end
      
      if any(abs([test_obj.scheduledPowers(1:2).value] - [LOAD])) > 5
          pf = 'fail';
          warning('- the calculated powers were not as expected');
      else
          disp('- the calculated powers were as expected');
      end

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up variable space
    clear test_obj test_mkt test_intervals test_forecast
    
end                                                 % TEST_SCHEDULE_POWER()

end                          % Static OpenLoopRichlandLoadPredictor Methods    
    
end


