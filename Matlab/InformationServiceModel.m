classdef InformationServiceModel < handle
% InformationServiceModel Base Class
% An InformationServiceModel manages an InformationService and predicts or
% interpolates the information it provides.
    
%% InformationServiceModel properties    
    properties
        address                                       % web address storage
        description = ''
        file = ''                                                % filename
        informationType = MeasurementType.unknown
        informationUnits = MeasurementUnit.unknown
        license
        name = ''
        nextScheduledUpdate = datetime.empty
        predictedValues = IntervalValue.empty
        serviceExpirationDate = datetime.empty
%       NOTE: Function Hours() corrects behavior of Matlab hours().
        updateInterval = Hours(1) 
    end                                % InformationServiceModel properties
    
%% Static InformationServiceModel methods  
    methods
        
%% FUNCTION UPDATE_INFORMATION()
function update_information(ism,mkt)
% UPDATE_INFORMATION() - update the predicted information. Method may
% include Web queries or table lookup or predictor functions.

%   Gather active time intervals ti  
    ti = mkt.timeIntervals;

%   index through active time intervals ti  
    for i = 1:length(ti)
        
%       Get the start time for the indexed time interval        
        st = ti(i).startTime;
        
%       Extract the starting time hour        
        hr = hour(st);
        
%       Look up the value in a table. NOTE: tables may be used during
%       development until active information services are developed.
        T = readtable(ism.file);
        value = T(hr+1,1);

%       Check whether the information exists in the indexed time interval       
        iv = findobj(ism.values,'timeInterval',ti(i));

        if isempty(iv)
            
%           The value does not exist in the indexed time interval. Create
%           it and store it.
            iv = IntervalValue(ism,ti(i),mkt,'Temperature',value);
            ism.values = [ism.values,iv];

        else

%           The value exists in the indexed time interval. Simply reassign
%           it.
            iv.value = value;

        end                                                % if isempty(iv)

    end                                                    % for indexing i

end                                         % FUNCTION UPDATE_INFORMATION()

%% FUNCTION VIEW_INFORMATION()
function view_information(ism,mkt)
% VIEW_INFORMATION() - visualize predicted information
% ism - InformationServiceModel object
% mkt - Market object
    
    ti = mkt.timeIntervals;
    
    ind = ismember([ism.predictedValues.timeInterval],ti);
    
    pv = ism.predictedValues(ind);
    
    hold off;
    plot([ti.startTime],[pv.value],'*'); 
    hold on;
    plot([ti.startTime],[pv.value]);
    xlabel('time');
    ylabel([string(ism.informationType),' ',string(ism.informationUnits)]);
    title('Predicted Values');
    hold off;    
        
end                                           % FUNCTION VIEW_INFORMATION()
    

    end                                   % InformationServiceModel methods
    
%% Static InformationServiceModel Methods
methods (Static)
    
%% TEST_ALL()
function test_all()
% TEST_ALL() - run all the method tests
    disp('Running InformationServiceModel.test_all()');
    InformationServiceModel.test_update_information();
    InformationServiceModel.test_view_information();
end                                                            % TEST_ALL()

%% TEST_UPDATE_INFORMATION
function test_update_information()
    disp('Running InformationServiceModel.test_update_information()');
    pf = 'test is not yet completed';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up
    clear
    
end                                               % TEST_UPDATE_INFORMATION

%% TEST_VIEW_INFORMATION()                                         COMPLETE
function test_view_information()
% TEST_VIEW_INFORMATION() - test method view_information()
    disp('Running InformationServiceModel.test_view_information()');
    pf = 'pass';
    
%   Create a test Market
    test_mkt = Market;
    
%   Create and store a few TimeIntervals
%   NOTE: Function Hours() corrects behavior of Matlab hours().
    dt = datetime(date) + Hours(12);
    at = dt;
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = dt;
    ti(1) = TimeInterval(at,dur,mkt,mct,st);
    
    st = st + dur;
    ti(2) = TimeInterval(at,dur,mkt,mct,st);
    
    st = st + dur;
    ti(3) = TimeInterval(at,dur,mkt,mct,st);
    
    test_mkt.timeIntervals = ti;
    
%   Create a test InformationServiceModel
    test_ism = InformationServiceModel;
    
%   Create and store some predicted information
    iv(1) = IntervalValue(test_ism,ti(1),test_mkt,...
        'PredictedInformation',1);
    iv(2) = IntervalValue(test_ism,ti(2),test_mkt,...
        'PredictedInformation',2);
    iv(3) = IntervalValue(test_ism,ti(3),test_mkt,...
        'PredictedInformation',3);
    test_ism.predictedValues = iv;
    
    try
        test_ism.view_information(test_mkt);
        disp('- the method ran without errors');
    catch
        error('- the method encountered errors and stopped');
    end
    
% NOTE: This is pretty minimal. The next tests, if implemented, would check
% that an acceptable figure was, in fact, created.
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up
    clear test_ism test_mkt; clf; cla;

end                                               % TEST_VIEW_INFORMATION()
    
end                                % Static InformationServiceModel Methods
    
%% InformationServiceModel events    
    events
        
        UpdatedInformationReceived
        
    end                                    % InformationServiceModel events
    
end                             % classdef InformationServiceModel < handle

