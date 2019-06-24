classdef (Abstract) AbstractModel < handle
% AbstractModel- Root class for NeighborModel and LocalAssetModel classes
% - Provides handle access
% - Provides several critical methods
% - Creates a requirement that certain methods must be redefined.

%% Static AbstractModel Properties
    properties
        name = ''
        object   % Used to cross-reference the model's corresponding object
        defaultPower
        defaultVertices = Vertex(inf,0,0)
    end                                   % Static AbstractModel Properties
    
%% Dynamically-Assigned AbstractModel Properties
% These dynamic properties are used by the required methods.
    properties 
        activeVertices = IntervalValue.empty
        costParameters = [0.0,0.0,0.0]
        dualCosts = IntervalValue.empty
        meterPoints = MeterPoint.empty
        productionCosts = IntervalValue.empty
        reserveMargins = IntervalValue.empty
        scheduledPowers = IntervalValue.empty
        totalDualCost = 0.0
        totalProductionCost = 0.0
    end                     % Dynamically-Assigned AbstractModel Properties
    
%% Sealed AbstactModel Methods
% The methods schedule() and update_costs() are "sealed," meaning that they
% cannot be redefined by subclasses:
    methods (Sealed)
        
%% FUNCTION SCHEDULE()
function schedule(obj,mkt)
% SCHEDULE - Call abstract methods update_vertices(), schedule_power(),
% schedule_engagement(), and calculate_reserve_margin().

% NOTE: we can't really catch if someone tries to schedule another object
% type, but we should prevent users from creating new schedule methods
% for objects that don't inherit from either NeighborModel or
% LocalAssetModel.
if ~isa(obj,'LocalAssetModel') && ~isa(obj,'NeighborModel')
    warning(['Method works only for children of LocalAssetModel ',...
        'and NeighborModel']);
    return;
end

%   If the object is a NeighborModel give its vertices priority
    if isa(obj,'NeighborModel')
        obj.update_vertices(mkt);                
        obj.schedule_power(mkt);

%   But give power scheduling priority for a LocalAssetModel
    elseif isa(obj,'LocalAssetModel')
        obj.schedule_power(mkt);
        obj.schedule_engagement(mkt)                % only LocalAssetModels
        obj.update_vertices(mkt);  

    end

%   Have the objects estimate their available reserve margin
    calculate_reserve_margin(obj,mkt);

end                                                   % FUNCTION SCHEDULE()
        
%% FUNCTION UPDATE_COSTS()       
function update_costs(obj,mkt)
% UPDATE_COSTS() - call abstract methods to update_production_costs() and
% update_dual_costs().

%   Initialize sums of production and dual costs
    obj.totalProductionCost = 0.0;
    obj.totalDualCost = 0.0;

%   Have object update and store its production and dia; costs in
%   each active time interval
    update_production_costs(obj,mkt);
    update_dual_costs(obj,mkt);

%   Sum total production and dual costs through all time intervals
    obj.totalProductionCost = sum([obj.productionCosts.value]);
    obj.totalDualCost = sum([obj.dualCosts.value]);

end                                               % FUNCTION UPDATE_COSTS()
        
    end                                    % AbstractModel Methods (Sealed) 
    
%% Abstract AbstractModel methods
% These abstract methods must be redefined (made concrete) by NeighborModel
% and LocalAssetModel subclasses. (This requirement is met by simply doing
% so in the LocalAssetModel and NeighborModel base classes.)
    methods (Abstract)
        calculate_reserve_margin(obj,mkt)
        schedule_engagement(obj,mkt)
        schedule_power(obj,mkt)
        update_dual_costs(obj,mkt)
        update_production_costs(obj,mkt)
        update_vertices(obj,mkt)
    end                                   % AbstactModel methods (Abstract)
   
%% Static AbstractModel Methods
methods (Static)
    
%% TEST_ALL()
function test_all()
% TEST_ALL - test the sealed AbstractModel methods
    disp('Running AbstractModel.test_all()');
    AbstractModel.test_schedule();
    AbstractModel.test_update_costs();
end                                                            % TEST_ALL()        
    
%% TEST_SCHEDULE()
function pf = test_schedule()
    disp('Running AbstractModel.test_schedule()');
    pf = 'pass';

%   Create a test market test_mkt  
    test_mkt = Market;

%   Create a sample time interval ti
    dt = datetime;
    at = dt;
    % NOTE: Function Hours() corrects behavior of Matlab hours().
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    % NOTE: Function Hours() corrects behavior of Matlab hours().
    st = datetime(date) + Hours(20);
    ti = TimeInterval(at,dur,mkt,mct,st);

%   Save the time interval
    test_mkt.timeIntervals = ti;

%   Assign a marginal price in the time interval    
    test_mkt.check_marginal_prices();

%   Create a Neighbor test object and give it a default maximum power value
    test_obj = Neighbor;
    test_obj.maximumPower = 100;

%   Create a corresponding NeighborModel
    test_mdl = NeighborModel;
 
%   Make sure that the model and object cross-reference one another
    test_obj.model = test_mdl;
    test_mdl.object = test_obj;

%   Run a test with a NeighborModel object
disp('- running test with a NeighborModel:');
try
   test_mdl.schedule(test_mkt);
   disp('  - the method encountered no errors');
catch
    pf = 'fail';
    error('  - the method did not run without errors');
end

if length(test_mdl.scheduledPowers) ~= 1
    pf = 'fail';
    error('  - the method did not store a scheduled power');
else
    disp('  - the method calculated and stored a scheduled power');
end

if length(test_mdl.reserveMargins) ~= 1
    pf = 'fail';
    error('  - the method did not store a reserve margin');
else
    disp('  - the method stored a reserve margin');
end

if length(test_mdl.activeVertices) ~= 1
    pf = 'fail';
    error('  - the method did not store an active vertex');    
else
    disp('  - the method stored an active vertex');    
end

%   Run a test again with a LocalAssetModel object
    test_obj = LocalAsset;
    test_obj.maximumPower = 100;
    test_mdl = LocalAssetModel;
    test_obj.model = test_mdl;
    test_mdl.object = test_obj;
    
disp('- running test with a LocalAssetModel:');

try
   test_mdl.schedule(test_mkt);
   disp('  - the method encountered no errors');
catch
    pf = 'fail';
    error('  - the method did not run without errors');
end

if length(test_mdl.scheduledPowers) ~= 1
    pf = 'fail';
    error('  - the method did not store a scheduled power');
else
    disp('  - the method calculated and stored a scheduled power');
end

if length(test_mdl.reserveMargins) ~= 1
    pf = 'fail';
    error('  - the method did not store a reserve margin');
else
    disp('  - the method stored a reserve margin');
end

if length(test_mdl.activeVertices) ~= 1
    pf = 'fail';
    error('  - the method did not store an active vertex');    
else
    disp('  - the method stored an active vertex');    
end

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
    clear test_obj test_mkt
    
end                                                       % TEST_SCHEDULE()

%% TEST_UPDATE_COSTS()
function pf = test_update_costs()
    disp('Running AbstractModel.test_update_costs()'); 
    
    pf = 'pass';
    
%   Create a test market test_mkt  
    test_mkt = Market;

%   Create a sample time interval ti
    dt = datetime;
    at = dt;
%   NOTE: Function Hours() corrects behavior of Matlab hours().    
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = datetime(date) + Hours(20);
    ti = TimeInterval(at,dur,mkt,mct,st);

%   Save the time interval
    test_mkt.timeIntervals = ti;

%   Assign a marginal price in the time interval    
    test_mkt.check_marginal_prices();

%   Create a Neighbor test object and give it a default maximum power value
    test_obj = Neighbor;
%     test_obj.maximumPower = 100;

%   Create a corresponding NeighborModel
    test_mdl = NeighborModel;
 
%   Make sure that the model and object cross-reference one another
    test_obj.model = test_mdl;
    test_mdl.object = test_obj;
    
    test_mdl.scheduledPowers = ...
        IntervalValue(test_mdl,ti,test_mkt,'ScheduledPower',100);
    test_mdl.activeVertices = ...
        IntervalValue(test_mdl,ti,test_mkt,'ActiveVertex',...
        Vertex(0.05,0,100));

%   Run a test with a NeighborModel object
disp('- running test with a NeighborModel:');
try
   test_mdl.update_costs(test_mkt);
   disp('  - the method encountered no errors');
catch
    pf = 'fail';
    error('  - the method did not run without errors');
end

if length(test_mdl.productionCosts) ~= 1
    pf = 'fail';
    error('  - the method did not store a production cost');
else
    disp('  - the method calculated and stored a production cost');
end

if length(test_mdl.dualCosts) ~= 1
    pf = 'fail';
    error('  - the method did not store a dual cost');
else
    disp('  - the method stored a dual cost');
end

if (test_mdl.totalProductionCost) ~= sum(test_mdl.productionCosts.value)
    pf = 'fail';
    error('  - the method did not store a total production cost');    
else
    disp('  - the method stored an total production cost');    
end

if (test_mdl.totalDualCost) ~= sum(test_mdl.dualCosts.value)
    pf = 'fail';
    error('  - the method did not store a total dual cost');    
else
    disp('  - the method stored an total dual cost');    
end

%   Run a test again with a LocalAssetModel object
    test_obj = LocalAsset;
%     test_obj.maximumPower = 100;
    test_mdl = LocalAssetModel;
    test_obj.model = test_mdl;
    test_mdl.object = test_obj;
    
    test_mdl.scheduledPowers = ...
        IntervalValue(test_mdl,ti,test_mkt,'ScheduledPower',100);
    test_mdl.activeVertices = ...
        IntervalValue(test_mdl,ti,test_mkt,'ActiveVertex',...
        Vertex(0.05,0,100));   
    
disp('- running test with a LocalAssetModel:');

try
   test_mdl.update_costs(test_mkt);
   disp('  - the method encountered no errors');
catch
    pf = 'fail';
    error('  - the method did not run without errors');
end

if length(test_mdl.productionCosts) ~= 1
    pf = 'fail';
    error('  - the method did not store a production cost');
else
    disp('  - the method calculated and stored a production cost');
end

if length(test_mdl.dualCosts) ~= 1
    pf = 'fail';
    error('  - the method did not store a dual cost');
else
    disp('  - the method stored a dual cost');
end

if (test_mdl.totalProductionCost) ~= sum(test_mdl.productionCosts.value)
    pf = 'fail';
    error('  - the method did not store a total production cost');    
else
    disp('  - the method stored a total production cost');    
end

if (test_mdl.totalDualCost) ~= sum(test_mdl.dualCosts.value)
    pf = 'fail';
    error('  - the method did not store a total dual cost');    
else
    disp('  - the method stored a total dual cost');    
end

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
end                                                   % TEST_UPDATE_COSTS()

end                                          % Static AbstractModel Methods

end                                        % classdef AbstactModel < handle

