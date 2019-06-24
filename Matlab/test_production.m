function pf = test_production()
    disp('Running test_production()');
    pf = 'pass';

%   Create a test object
    test_object = LocalAssetModel;

%   Create a test market
    test_market = Market;

%   Create several active vertices av
av = [Vertex(0.0200,5.00,0.0),...
    Vertex(0.0200,7.00,100.0), ...
    Vertex(0.0250,9.25,200.0)];

% Create a time interval ti
    dt = datetime;
    at = dt;
%   NOTE: Function Hours() corrects the behavior of Matlab hours().
    dur = Hours(1);
    mkt = test_market;
    mct = dt;
    st = dt;
    ti = TimeInterval(at,dur,mkt,mct,st);

% Assign activeVertices, which are IntervalValues   
    test_object.activeVertices = [ ...
    IntervalValue(test_object,ti,test_market,'ActiveVertex',av(1)),...
    IntervalValue(test_object,ti,test_market,'ActiveVertex',av(2)),...
    IntervalValue(test_object,ti,test_market,'ActiveVertex',av(3))];

%% CASE: Various marginal prices when there is more than one vertex
    test_prices = [-0.010,0.000,0.020,0.0225,0.030];

    p= zeros(1,length(test_prices));
    for i = 1:length(test_prices)
        try
            p(i) = production(test_object,test_prices(i),ti);
        catch
            pf = 'fail';
            error('- the function had errors and stopped');
        end
    end
    disp('- the function ran without errors');

% p(1) = 0: below first vertex
% p(2) = 0: below first vertex
% p(3) = 100: at first vertex, which has identical marginal price as second
% p(4) = 150: interpolate between vertices
% p(5) = 200: exceeds last vertex


if ~all(abs(p - [0, 0, 100, 150, 200]) < 0.001)
    pf = 'fail';
    error('- the production cost was incorrectly calculated');
else
    disp('- the production cost was correctly calculated');
end

%% CASE: One vertex (inelastic case, a constant)
    test_object.activeVertices = ...
    IntervalValue(test_object,ti,test_market,'ActiveVertex',av(3));

    for i = 1:5
        p(i) = production(test_object,test_prices(i),ti);
    end

    if ~all(p == 200 * ones(1,length(p)))
        pf = 'fail';
        error('the vertex power should be assigned when there is one vertex');
    else
        disp('- the correct power was assigned when there is one vertex');
    end

%% CASE: No active vertices (error case):
    test_object.activeVertices = [];

    try
        p = production(test_object,test_prices(5),ti);
        pf = 'fail';
        error('- an error should have occurred with no active vertices');
    catch
        disp(['- with no vertices, system returned with warnings, ',...
            'as expected']);
    end
    
%   Success
    disp('- the test function ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up class spacc
    clear test_object test_market ti av

end



