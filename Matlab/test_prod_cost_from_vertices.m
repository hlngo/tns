function pf = test_prod_cost_from_vertices()
% TEST_PROD_COST_FROM_VERTICES - tests function prod_cost_from_vertices()
    disp('Running test_prod_cost_from_vertices()');
    pf = 'pass';

% Create a test object
    test_object = LocalAssetModel;

% Create a test market
    test_market = Market;

% Create several active vertices av
    av = [Vertex(0.02,5,0),...
        Vertex(0.02,7,100), ...
        Vertex(0.025,9.25,200)];

% Create a time interval
    dt = datetime;
    at = dt;
%   NOTE: Function Hours() corrects behavior of Matlab function hours().
    dur = Hours(1);
    mkt = test_market;
    mct = dt;
    st = dt;
    ti = TimeInterval(at,dur,mkt,mct,st);   
    
% Create and store the activeVertices, which are IntervalValues   
    test_object.activeVertices = [ ...
    IntervalValue(test_object,ti,test_market,'ActiveVertex',av(1)),...
    IntervalValue(test_object,ti,test_market,'ActiveVertex',av(2)),...
    IntervalValue(test_object,ti,test_market,'ActiveVertex',av(3))];

%% CASE: Various signed powers when there is more than one vertex
    test_powers = [-50,0,50,150,250];

    for i = 1:length(test_powers)
        pc(i) = prod_cost_from_vertices(test_object,ti,test_powers(i));
    end

% pc(1) = 0: value is always 0 for power < 0
% pc(2) = 5.0: assign cost from first vertex
% pc(3) = 6.0: interpolate between vertices
% pc(4) = 8.125: interpolate between vertices
% pc(5) = 9.25: use last vertex cost if power > last vertex power

    if ~all(pc == [0, 5.0, 6.0, 8.125, 9.25])
        pf = 'fail';
        error('- the production cost was incorrectly calculated');
    else
        disp('- the production cost was correctly calculated');
    end

%% CASE: One vertex (inelastic case, a constant)
    test_object.activeVertices = ...
        IntervalValue(test_object,ti,test_market,'ActiveVertex',av(1));

    for i = 1:5
        pc(i) = prod_cost_from_vertices(test_object,ti,test_powers(i));
    end

    if ~all(pc == [0.0, 5.0, 5.0, 5.0, 5.0])
        pf = 'fail';
        error('- made an incorrect assignment when there is one vertex');
    else
        disp('- made a correct assignment when there is one vertex');
    end

%% CASE: No active vertices (error case):
    test_object.activeVertices = [];

    warning('off','all');
    try
        pc = prod_cost_from_vertices(test_object,ti,test_powers(5));
        pf = 'fail';
        warning('on','all');
        error(['- the function should have warned and continued ',...
            'when there were no active vertices']);
    catch
        disp(['- the function returned gracefully when there were no ',...
            'active vertices']);
         warning('on','all');
    end
    
%   Success
    disp('- the test function ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up
    clear test_object test_market ti av

end

