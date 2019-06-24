classdef TemperatureForecastModel < InformationServiceModel
% TemperatureForecastModel - manage local hourly temperature prediction
% obtained from www.wunderground.com.

%% Protected TemperatureForecastModel Properties
    properties (GetAccess=protected)
        zipCode = '99352'
        key = '3f10e7fb5368a34a'
    end                     % Protected TemperatureForecastModel properties
    
%% Static TemperatureForecastModel methods
methods (Static)
    
%% TemperatureForecastModel() Constructor    
function obj = TemperatureForecastModel()
% TEMPERATUREFORECASTMODEL() - Constructs TemperatureForecastModel object
% Forecasts local hourly temperature (DEGf) using Weather Underground
% (wunderground.com).
    obj.address = 'http://api.wunderground.com/api/';
    obj.description = ['Weather Underground local one-day hourly ', ...
        'temperature forecast'];
    obj.informationType = MeasurementType.temperature;
    obj.informationUnits = MeasurementUnit.degF;
    obj.license = 'non-commercial Cumulus level';
    obj.name = 'temperature_forecast';                   % may be redefined
%   NOTE: Function Hours() corrects behavior of Matlab's function hours().
    obj.nextScheduledUpdate = datetime(date) + Hours(hour(datetime)) ...
        + Hours(1);
    obj.serviceExpirationDate = 'indeterminate';
    obj.updateInterval = Hours(3);            % recommended, may be changed
end                                % TemperatureForecastModel() Constructor 
    
end                               % Static TemperatureForecastModel methods
    
%% TemperatureForecastModel methods
    methods
        
%% FUNCTION UPDATE_INFORMATION()
function update_information(obj,mkt)
% UPDATE_INFORMATION() - retrieve the local hourly temperature forecast
% from www.wunderground.com and store the predicted temperatures as
% interval values.
% NOTE: there is probably no good reason to ever call this method more than
% once every 3 hours, or so. It collects 36 hourly forecasts, so it might
% be deferrable as much as 12 hours without losing its ability to assist
% with day-ahead forecasts.
    
% The format of the url inquiry
    url = [obj.address,obj.key,'/hourly/q/',...
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

    end                                  % TemperatureForecastModel Methods
    
    methods (Static)

%% TEST_ALL()
function test_all()
% TEST_ALL() - test all TemperatureForecastModel methods
    TemperatureForecastModel.test_update_information();
    TemperatureForecastModel.test_view_information();
end                                                            % TEST_ALL()
        
        
%% FUNCTION TEST_UPDATE_INFORMATION()
function pf = test_update_information()
% TEST_UPDATE_INFORMATION() - test method update_information()
disp('Running TemperatureForecastModel.test_update_information()');
pf = 'pass';

test_mkt = Market;

test_obj = TemperatureForecastModel;
    test_obj.zipCode = '99352';
 
% The following changes were made 1/29/18 in light of creating TimeInterval
% constructor.     
% TimeInterval(at,dur,mkt,mct,st)

dt = datetime; 
    at = dt;
%   NOTE: Function Hours() corrects behavior of Matlab's function hours().    
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = datetime(date) + Hours(hour(datetime));
    
ti(1) = TimeInterval(at,dur,mkt,mct,st);

st = ti(1).startTime + Hours(10);
ti(2) = TimeInterval(at,dur,mkt,mct,st);

st = ti(1).startTime + Hours(40);
ti(3) = TimeInterval(at,dur,mkt,mct,st);

test_mkt.timeIntervals = ti;

try
    test_obj.update_information(test_mkt);
    disp('- the method update_information() ran without errors');
catch
    pf = 'fail';
    warning('- the method update_information() did not run');
end

if isempty(test_obj.predictedValues)
    pf = 'fail';
    warning('- the method failed to store any predicted values');
else
    disp('- the method successfully stored one or more predicted values');
end

if length([test_obj.predictedValues]) ~= length(ti)
    pf = 'fail';
    warning('- the method stored the wrong number of predicted values');
else
    disp('- the method stored the right number of predicted values');
end

if sum(isnan([test_obj.predictedValues.value])) ~= 2
    pf = 'fail';
    warning('- the method assigned an unexpected number of NaN');    
else
    disp('- the method assigned NaN where expected');
end

% Remove the NaN for next tests
test_set = [test_obj.predictedValues.value];
ind = ~isnan(test_set);
test_set = test_set(ind);

if isempty(test_set)
    pf = 'fail';
    warning('- the method stored no numerical values');    
else
    disp('- the method stored at least one numerical value as expected');
end

if test_set(1) > 120 || test_set(1) < -50
    pf = 'fail';
    warning('- value(s) are not reasonable Fahrenheit temperatures');
else
    disp('- a value was within a reasonable range for Fahrenheit temp');
end

% Success
disp('- the test ran to completion');
fprintf('Result: %s\n\n',pf);

% clean up the class space
clear test_mkt test_obj

end                                         % function update_information()

    end                           % Static TemperatureForecastModel Methods
    
end                                     % classdef TemperatureForecastModel

