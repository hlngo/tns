classdef WeatherForecastModel < InformationServiceModel
% WeatherForecastModel - manage local hourly weather prediction
% obtained from www.wunderground.com.
% Weather Underground provides many predicted weather variables by zipcode.
% Hourly outdoor temperature is most useful, but others may be added over
% time. The predictedValues property may therefore come to include members
% having different MeasurementType (an enumeration). The user should
% therefore check the MeasurementType.
    
%% Protected WeatherForecastModel properties
    properties (GetAccess=protected)
        zipCode = '99352'
        key = '3f10e7fb5368a34a'
    end                     % Protected WeatherForecastModel properties
    
%% WeatherForecastModel methods
    methods
        
%% FUNCTION UPDATE_INFORMATION()
function update_information(obj,mkt)
% UPDATE_INFORMATION() - retrieve the local hourly weather forecast from
% www.wunderground.com and store the predicted temperatures as interval
% values.
% NOTE: there is probably no good reason to ever call this method more than
% once every 3 hours, or so. It collects 36 hourly forecasts, so it might
% be deferrable as much as 12 hours without losing its ability to assist
% with day-ahead forecasts.
    
% The format of the url inquiry
    url = ['http://api.wunderground.com/api/',obj.key,'/hourly/q/',...
        obj.zipCode,'.json'];   

%   Invoke the wunderground API
    data = webread(url);

%   pre-allocate a set of data contents
    Y = zeros(1,36);                                                 % year
    M = zeros(1,36);                                         % month number
    D = zeros(1,36);                                         % day of month
    H = zeros(1,36);                                          % hour of day 
    T = zeros(1,36);                   % predicted temperature value [degF]
    
%   Create a table of 36 hourly [Datetime, Temp] records.
    for i = 1:36
        
%       Extract an hourly forecast record
        record = data.hourly_forecast(i);
        
%       Extract information about the record hour
        record_time = record.FCTTIME;

%       Extract the components of the hourly record time
        Y(i) = string(record_time.year);                      % year [YYYY]
        M(i) = string(record_time.mon);                      % month number
        D(i) = string(record_time.mday);                     % day of month
        H(i) = string(record_time.hour_padded);                      % hour
        
%       Extract the Fahrenheit temperature for the hourly record
        T(i) = string(record.temp.english);               %Fahrenheit temp.
        
    end                                                      % for i = 1:36
    
%   Turn the hourly record time data into an array of datetimes dt
    dt = datetime(Y,M,D,H,0,0);                        % array of datetimes
        
%   Create a clean table of [Datetime, Temp] records
    Table = table(dt',T', ...
        'VariableNames',{'Datetime','Temp'});
    
%   Create a clean struct S from the table (facilitates indexing)
    S = table2struct(Table);

%   Gather the set of active market intervals ti
    ti = [mkt.timeIntervals];

%   Index through the active time intervals ti
    for i = 1:length(ti)

%       Find the indexed time interval start time and its corresponding
%       temperature from the struct table. 
        ind = [S.Datetime]==ti(i).startTime;            % an indexing array
        
        try
            value = S(ind).Temp;         % corresponsing temperature [degF]
        catch
            value = NaN;
        end
        
%       Check whether the predicted value exists.
        iv = findobj(obj.predictedValues,'timeInterval',ti(i));
        
        if isempty(iv)
            
%           The predicted value does not exist. Create and store the
%           new interval value.            
            iv = IntervalValue(obj,ti(i),mkt,'PredictedValue',value); 
                                                         % an IntervalValue
            obj.predictedValues = [obj.predictedValues,iv];
            
        elseif ~isnan(value)
            
%           The predicted value already exists. Simply reassign its value.
%           NOTE: Avoid replacing valid values with NaN, which will occur
%           occassionally for intervals that are, or are about to be, in
%           their Delivery state.
            iv.value = value;                % predicted temperature [degF]
            
        end                                                % if isempty(iv)
        
    end                                                    % for indexing i

end                                         % function update_information()

    end                                      % WeatherForecastModel methods
    
    methods (Static)

%% FUNCTION TEST_UPDATE_INFORMATION()
function pf = test_update_information()
% TEST_UPDATE_INFORMATION() - test method update_information()

pf = 'pass';
    
ti(1) = TimeInterval;
    ti(1).startTime = datetime(date) + hours(hour(datetime));
  ti(2) = TimeInterval;
    ti(2).startTime = ti(1).startTime + hours(10);
 ti(3) = TimeInterval;
    ti(3).startTime = ti(1).startTime + hours(40);
 
test_mkt = Market;
    test_mkt.timeIntervals = ti;

test_obj = WeatherForecastModel;
    test_obj.zipCode = '99352';
 
try
    test_obj.update_information(test_mkt);
catch
    pf = 'fail'
    error('- the method update_information() did not run');
end

disp('- the method update_information() ran without errors');

if isempty(test_obj.predictedValues)
    pf = 'fail';
    error('- the method failed to store any predicted values');
else
    disp('- the method successfully stored one or more predicted values');
end

if length([test_obj.predictedValues]) ~= length(ti)
    pf = 'fail';
    error('- the method stored the wrong number of predicted values');
else
    disp('- the method stored the right number of predicted values');
end

if sum(isnan([test_obj.predictedValues.value])) ~= 2
    pf = 'fail';
    error('- the method assigned an unexpected number of NaN');    
else
    disp('- the method assigned NaN where expected');
end

% Remove the NaN for next tests
test_set = [test_obj.predictedValues.value];
ind = ~isnan(test_set);
test_set = test_set(ind);

if isempty(test_set)
    pf = 'fail';
    error('- the method stored no numerical values');    
else
    disp('- the method stored at least one numerical value as expected');
end

if test_set(1) > 120 || test_set(1) < -50
    pf = 'fail';
    error('- value(s) are not reasonable Fahrenheit temperatures');
else
    disp('- a value was within a reasonable range for Fahrenheit temp');
end

disp('- the test ran to completion');

% clean up the class space
clear test_mkt test_obj

end                                         % function update_information()

    end                               % Static WeatherForecastModel methods
    
end                                         % classdef WeatherForecastModel

