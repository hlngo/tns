function pf = test_prod_cost_from_formula()
    disp('Running test_prod_cost_from_formula()');
    pf = 'pass';

%   Create a test object
    test_object = LocalAssetModel;
    
%   Create a test market
    test_market = Market;

%   Create and store the object's cost parameters
    test_object.costParameters = [4, 3, 2];

%   Create and store three hourly TimeIntervals
%   Modified to use the TimeInterval constructor.
    dt = datetime;
    at = dt;
    dur = Hours(1);
    mkt = test_market;
    mct = dt;
    
    st = dt;
    ti(1) = TimeInterval(at,dur,mkt,mct,st);

    st = st + dur;
    ti(2) = TimeInterval(at,dur,mkt,mct,st);

    st = st + dur;
    ti(3) = TimeInterval(at,dur,mkt,mct,st);
    
    test_market.timeIntervals = ti;
    
% Create and store three corresponding scheduled powers
iv = [IntervalValue(test_object,ti(1),test_market,'ScheduledPower',100),...
    IntervalValue(test_object,ti(2),test_market,'ScheduledPower',200),...
    IntervalValue(test_object,ti(3),test_market,'ScheduledPower',300)];
    test_object.scheduledPowers = iv;

%   Run the test
    for i = 1:3
        pc(i) = prod_cost_from_formula(test_object,ti(i));
    end

% pc(1) = 4 + 3 * 100 + 0.5 * 2 * 100^2 = 10304
% pc(2) = 4 + 3 * 200 + 0.5 * 2 * 200^2 = 40604
% pc(3) = 4 + 3 * 300 + 0.5 * 2 * 300^2 = 90904

    if all(pc ~= [10304,40604,90904])
        pf = 'fail';
        error('- production cost was incorrectly calculated');
    else
        disp('- production cost was correctly calculated');
    end
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up class space
    clear test_object test_market ti iv

end

