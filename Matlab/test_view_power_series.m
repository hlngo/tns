function test_view_power_series()
% TEST_VIEW_POWER_SERIES() - test function view_power_series()
    disp('Running test_view_power_series()');
    pf = 'pass';

% establish a test market
    test_mkt = Market;

% create and store three TimeIntervals
    dt = datetime;
    at = dt;
%   NOTE: Function Hours() corrects the behavior of Matlab function
%   hours().
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

%% Test using a NeighborModel object
    disp('- using a NeighborModel object');
    test_obj = NeighborModel;
    
%   Create and store three scheduled power values
    iv(1) = IntervalValue(test_obj,ti(3),test_mkt,'ScheduledPower',3);
    iv(2) = IntervalValue(test_obj,ti(1),test_mkt,'ScheduledPower',1);
    iv(3) = IntervalValue(test_obj,ti(2),test_mkt,'ScheduledPower',2);
    test_obj.scheduledPowers = iv;
    
    try
        view_power_series(test_obj,test_mkt);
        disp('  - function ran without errors');
    catch
        error('  - function encountered errors and stopped');        
    end
    
%   Check for a figure
    fig = gca;
    title = get(fig,'Title');
    title = title.Text.String;

    if title ~= 'Total Generation in Active Time Intervals'
        error('  - the figure title is unexpected');
    else
        disp('  - the figure title is as expected');
    end 
    
    cla; clf;
    
%% Test using a LocalAssetModel object
    disp('- using a LocalAssetModel object');
    test_obj = LocalAssetModel;
    test_obj.scheduledPowers = iv;
    
    try
        view_power_series(test_obj,test_mkt);
        disp('  - function ran without errors');
    catch
        error('  - function encountered errors and stopped');        
    end

%   Check for a figure    
    fig = gca;
    title = get(fig,'Title');
    title = title.Text.String;

    if title ~= 'Total Generation in Active Time Intervals'
        error('  - the figure title is unexpected');
    else
        disp('  - the figure title is as expected');
    end 

%% Test using a Market object
    disp('- using a Market object');
    test_obj = test_mkt;
    
%   Create and store three scheduled power values
    test_obj.totalGeneration = iv;
    
    try
        view_power_series(test_obj,test_mkt);
        disp('  - function ran without errors');
    catch
        error('  - function encountered errors and stopped');        
    end
    
%   Check for a figure
    fig = gca;
    title = get(fig,'Title');
    title = title.Text.String;

    if title ~= 'Total Generation in Active Time Intervals'
        error('  - the figure title is unexpected');
    else
        disp('  - the figure title is as expected');
    end 
    
    cla; clf;  
    
%% Test using a disallowed object
    disp('- using a disallowed object');
    test_obj = MeterPoint;
    
    warning('off','all');
    try
        view_power_series(test_obj,test_mkt);
        warning('on','all');        
        error('  - function ran when it should not have');
    catch
        disp('  - encountered warnings and returned gracefully'); 
        warning('on','all');        
    end
    
    cla; clf;  
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);

clear test_obj test_mkt
    
end                                          % FUNCTION VIEW_POWER_SERIES()

