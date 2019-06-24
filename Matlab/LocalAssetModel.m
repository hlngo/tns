classdef LocalAssetModel < AbstractModel
%LocalAssetModel Base Class
% A local asset model manages and represents a local asset object,
% meaning that it
%   (1) determines a power schedule across all active time intervals,
%   (2) calculates costs that are needed by system optimization, and
%   (3) models flexibility, if any, that is available from the control of
%       this asset in active time intervals. 
%
% This base class provides many of the properties and methods that will
% be needed to manage local assets--generation and demand alike. However,
% it schedules only the simplest, constant power throughout active time
% intervals. Subclassing will be required to perform dynamic power
% scheduling, expecially where scheduling is highly constrained or
% invokes optimizations. Even then, implementers might need further
% subclassing to model their unique assets.
%
% Available subclasses that inherit from this base class: (This taxonomy
% is influenced by the thesis (Kok 2013).
%   Inelastic - dynamic scheduling independent of prices
%   Shiftable - schedule a fixed utility over a time range
%   Buffering - schedule power while managing a (thermal) buffer
%   Storage - optimize revenue, less cost
%   Controllable - unconstrained scheduling based on a polynomial
%                  production or utility function 
    
%% New LocalAssetModel properties
% Many dynamic properties and a few static ones are inherited from
% AbstractModel, leaving these additional properties to be introduced here.
    properties 
        engagementCost =[0.0,0.0,0.0]% [disengagement, hold, engagement][$]
        engagementSchedule = IntervalValue.empty       % values are Boolean
        informationServiceModels = InformationServiceModel.empty
        transitionCosts = IntervalValue.empty              % values are [$]                        
    end                                    % New LocalAssetModel properties
    
%% LocalAssetModel methods    
    methods
        
%% FUNCTION ASSIGN_TRANSITION_COSTS()
function assign_transition_costs(obj,mkt)
% FUNCTION ASSIGN_TRANSITION_COSTS() - assign the cost of changeing
% engagement state from the prior to the current time interval
%
% PRESUMPTIONS:
%   - Time intervals exist and have been updated
%   - The engagement schedule exists and has been updated. Contents are
%     logical [true/false].
%   - Engagement costs have been accurately assigned for [disengagement,
%     unchanged, engagement]
%
% INPUTS:
%   obj - Local asset model object
%   mkt - Market object
%
% USES:
%   - obj.engagementCost - three costs that correspond to
%     [disengagement, unchanged, engagement) transitions
%   - obj.engagement_cost() - assigns appropriate cost from
%     obj.engagementCost property
%   - obj.engagementSchedule - engagement states (true/false) for the asset
%     in active time intervals
%
% OUTPUTS:
%   Assigns values to obj.transition_costs

%   Gather active time intervals
    ti = mkt.timeIntervals;                                  %TimeIntervals
    
%   Ensure that ti is ordered by time interval start times    
    [~,ind] = sort([ti.startTime]);                         %logical array
    ti = ti(ind);
    
%   Index through all but the first time interval ti
    for i = 2:(length(ti))
        
%       Find the current engagement schedule ces in the current indexed
%       time interval ti(i)
        ces = findobj(obj.engagementSchedule,'timeInterval',ti(i)); 
                                                             %IntervalValue
        
%       Extract its engagement state
        ces = ces(1).value;                           %logical (true/false)
        
%       Find the engagement schedule pes in the prior indexed time interval
%       ti(i-1)
        pes = findobj(obj.engagementSchedule,'timeInterval',ti(i-1));
        
%       And extract its value        
        pes = pes(1).value;                           %logical (true/false)
        
%       Calculate the state transition
%           - -1:Disengaging
%           -  0:Unchaged
%           -  1:Engaging
        dif = ces - pes;                                       %in {-1,0,1}
        
%       Assign the corresponding transition cost        
        val = obj.engagement_cost(dif);

%       Check whether a transition cost exists in the indexed time interval
        iv = findobj(obj.transitionCosts,'timeInterval',ti(i));  
                                                          %an IntervalValue
        
        if isempty(iv)
            
%           No transition cost was found in the indexed time interval.
%           Create an interval value and assign its value. 
            iv = IntervalValue(obj,ti(i),mkt,'TransitionCost',val); 
                                                          %an IntervalValue
            
%           Append the interval value to the list of active interval
%           values
            obj.transitionCosts = [obj.transitionCosts,iv]; %IntervalValues
            
        else
            
%           A transition cost was found in the indexed time interval.
%           Simpy reassign its value.
            iv.value = val;                                            %[$]            
            
        end                                                             %if
        
    end                                                     %for indexing i
    
    %Remove any extraneous transition cost values
    aes = ismember([obj.transitionCosts.timeInterval],ti);   %logical array
    obj.transitionCosts = obj.transitionCosts(aes);  %active IntervalValues
            
end                                     %function assign_transition_costs()

%% FUNCTION CALCULATE_RESERVE_MARGIN()
function calculate_reserve_margin(obj,mkt)
% FUNCTION CALCULATE_RESERVE_MARGIN() - Estimate available (spinning)
% reserve margin for this asset. 
%
% NOTES:
%     This method works with the simplest base classes that have constant
%     power and therefore provide no spinning reserve. This method may be
%     redefined by subclasses of the local asset model to add new features
%     or capabilities. 
%     This calculation will be more meaningful and useful after resource
%     commitments and uncertainty estimates become implemented. Until then,
%     reserve margins may be tracked, even if they are not used.
%
% PRESUMPTIONS:
%   - Active time intervals exist and have been updated
%   - The asset's maximum power is a meaningful and accurate estimate of
%     the maximum power level that can be achieved on short notice, i.e.,
%     spinning reserve.
%
% INPUTS:
%   obj - local asset model object
%   mkt - market object
%
% OUTPUTS:
%   Modifies obj.reserveMargins - an array of estimated (spinning) reserve
%       margins in active time intervals
    
    %Gather the active time intervals ti
    ti = mkt.timeIntervals;                           %active TimeIntervals
    
    %Index through active time intervals ti
    for i = 1:length(ti)
        
        %Calculate the reserve margin for the indexed interval. This is the
        %non-negative difference between the maximum asset power and the
        %scheduled power. In principle, generation may be increased or
        %demand decreased by this quantity to act as spinning reserve.
        
        %Find the scheduled power in the indexed time interval
        iv = findobj(obj.scheduledPowers,'timeInterval',ti(i)); 
                                                          %an IntervalValue        
        
%       Calculate the reserve margin rm in the indexed time interval. The
%       reserve margin is the differnce between the maximum operational
%       power value in the interval and the scheduled power. The
%       operational maximum should be less than the object's hard physical
%       power constraint, so a check is in order.
%       start with the hard physical constraint.
        hard_const = obj.object.maximumPower;                    % [avg.kW]

%       Calculate the operational maximum constraint, which is the highest
%       point on the supply/demand curve (i.e., the vertex) that represents
%       the residual flexibility of the asset in the time interval.
        op_const = findobj(obj.activeVertices,'timeInterval',ti(i));
                                                           % IntervalValues
        if isempty(op_const)
            op_const = hard_const;
        else
            op_const = [op_const.value];                  % active vertices
            op_const = max([op_const.power]);% operational max. power[avg.kW]
        end
        
%       Check that the upper operational power constraint is less than or
%       equal to the object's hard physical constraint.
        soft_maximum = min(hard_const, op_const);                % [avg.kW]
        
%       And finally calculate the reserve margin.
        rm = max(0, soft_maximum - iv(1).value);  %reserve margin [avg. kW]
  
        %Check whether a reserve margin already exists for the indexed
        %time interval
        iv = findobj(obj.reserveMargins,'timeInterval',ti(i));
                                                          %an IntervalValue

        if isempty(iv)
            
            %A reserve margin does not exist for the indexed time interval.
            %create it. (See IntervalValue class.) 
            iv = IntervalValue(obj,ti(i),mkt,'ReserveMargin',rm); 
                                                          %an IntervalValue
                
            %Append the new reserve margin interval value to the list of
            %reserve margins for the active time intervals
            obj.reserveMargins = [obj.reserveMargins,iv];   %IntervalValues

        else
            
            %The reserve margin already exists for the indexed time
            %interval. Simply reassign its value.
            iv(1).value = rm;                      %reserve margin [avg.kW]
            
        end                                                             %if
        
    end                                                     %for indexing i  
    
end                                    %function calculate_reserve_margin()

%% FUNCTION COST() 
function pc = cost( obj, p )
% FUNCTION COST() 
%Calculate production (consumption) cost at the given power level.
%
%   INPUTS:
%       obj - class object for which the production costs are to be
%             calculated
%       p - power production (consumption) for which production
%           (consumption) costs are to be calculated [kW]. By convention,
%           imported and generated power is positive; exported or consumed
%           power is negative.
%
%   OUTPUTS:
%       pc - calculated production (consumption) cost [$/h]
%
%   LOCAL:
%       a - array of production cost coefficients that must be ordered [a0
%       a1 a2], such that cost = a0 + a1*p + a2*p^2 [$/h].
% *************************************************************************

    %Extract the production cost coefficients for the given object
    
    a  = obj.costParameters;

    %Calculate the production (consumption) cost for the given power
    
    pc = a(1) + a(2) * p + a(3) * p^2; %[$/h]

end %function cost()  

%% FUNCTION ENGAGEMENT_COST()
function cost = engagement_cost(obj,dif)
% FUNCTION ENGAGEMENT_COST() - assigns engagement cost based on difference
% in engagement status in the current minus prior time intervals.
%
% INPUTS:
% obj - local asset model object
% dif - difference (current interval engagement - prior interval
%        engagement), which assumes integer values [-1,0,1] that should
%        correspond to the three engagement costs.
% USES:
%   obj.engagementSchedule
%   obj.engagementCost
%
% OUTPUTS:
% cost - transition cost
%   diff - cost table as a function of current and prior engagement states:
%     \ current |   false   |  true 
% prior false   |  0:ec(2)  | 1:ec(3)
%       true    | -1:ec(1)  | 0:ec(2)

%   Check that dif is a feasible difference between two logical values
    if ~ismember(dif, [-1,0,1])
        warning('Input value must be in the set {-1,0,1}.');
        cost = 0;
        return;
    end                                                                 %if
    
%   Assign engagement cost by indexing the three values of engagement cost
%   1 - transition from false to true - engagement cost
%   2 - no change in engagemment - no cost
%   3 - transition from true to false - disengagment cost
    cost = obj.engagementCost(2 + dif);                               %[$]

end                                             %function engagement_cost()

%% FUNCTION SCHEDULE_ENGAGEMENT()
function schedule_engagement(obj,mkt)
% SCHEDULE_ENGAGEMENT - method to assign engagement, or committment, which
% is relevant to some local assets (supports future capabilities). 
% NOTE: The assignment of engagement schedule, if used, may be assigned
% during the scheduling of power, not separately as demonstrated here.
% Committment and engagement are closely aligned with the optimal
% production costs of schedulable generators and utility function of
% engagements (e.g., demand responses).

% NOTE: Because this is a future capability, Implementers might choose to
% simply return from the call until LocalAsset behaviers are found to need
% committment or engagement.
%   return;

    %Gather the active time intervals ti
    ti = mkt.timeIntervals;                           %active TimeIntervals
    
%   Index through the active time intervals ti    
    for i = 1:length(ti)
        
%       Check whether an engagement schedule exists in the indexed time
%       interval
        iv = findobj(obj.engagementSchedule,'timeInterval',ti(i));  
                                                          %an IntervalValue
        
%       NOTE: this template currently assigns engagement value as true
%       (i.e., engaged).
        val = true;                          %Asset is committed or engaged
        
        if isempty(iv)
            
%           No engagement schedule was found in the indexed time interval.
%           Create an interval value and assign its value. 
            iv = IntervalValue(obj,ti(i),mkt,'EngagementSchedule',val); 
                                                          %an IntervalValue
            
%           Append the interval value to the list of active interval
%           values
            obj.engagementSchedule = [obj.engagementSchedule,iv]; 
                                                            %IntervalValues
            
        else
            
%           An engagement schedule was found in the indexed time interval.
%           Simpy reassign its value.
            iv.value = val;                                            %[$]
            
        end                                                             %if
   
    end                                                      %indexing on i        
        
%   Remove any extra engagement schedule values     
    xes = ismember([obj.engagementSchedule.timeInterval],ti);
                                                      %an array of logicals
    obj.engagementSchedule = obj.engagementSchedule(xes);   %IntervalValues
    
end                                        % function schedule_engagement()
    
%% FUNCTION SCHEDULE_POWER()
function schedule_power(obj,mkt)
% FUNCTION SCHEDULE_POWER() - determine powers of an asset in active time
% intervals. NOTE that this method may be redefined by subclasses if more
% features are needed. NOTE that this method name is common for all asset
% and neighbor models to facilitate its redefinition.
%
% PRESUMPTIONS:
%   - Active time intervals exist and have been updated
%   - Marginal prices exist and have been updated. NOTE: Marginal prices
%     are not used for inelastic assets.
%   - Transition costs, if relevant, are applied during the scheduling
%     of assets. 
%   - An engagement schedule, if used, is applied during an asset's power
%     scheduling.
%   - Scheduled power and engagement schedule must be self consistent at
%   the end of this method. That is, power should not be scheduled while
%   the asset is disengaged (uncommitted). 
%   
% INPUTS:
%   obj - local asset model object
%   mkt - market object
%
% OUTPUTS:
%   - Updates obj.scheduledPowers - the schedule of power consumed
%   - Updates obj.engagementSchedule - an array that states whether the
%     asset is engaged (committed) (true) or not (false) in the time
%     interval

    %Gather the active time intervals ti
    ti = mkt.timeIntervals;                           %active TimeIntervals
    
%   Index through the active time intervals ti
    for i = 1:length(ti)
        
        %Check whether a scheduled power already exists for the indexed
        %time interval
        iv = findobj(obj.scheduledPowers,'timeInterval',ti(i));
                                                          %an IntervalValue
 
        if isempty(iv)
            
%           A scheduled power does not exist for the indexed time
%           interval. 
            
%           Create the scheduled power from its default. NOTE this simple
%           method must be replaced if more model features are needed.
            val = obj.defaultPower;                               %[avg.kW]
            
%           Create an interval value and assign the default value
            iv = IntervalValue(obj,ti(i),mkt,'ScheduledPower',val);
                                                          %an IntervalValue

%           Append the new scheduled power to the list of scheduled
%           powers for the active time intervals
            obj.scheduledPowers = [obj.scheduledPowers,iv]; %IntervalValues

        else
            
%           The scheduled power already exists for the indexed time
%           interval. Simply reassign its value 
            iv.value = obj.defaultPower;                          %[avg.kW]
            
        end                                                             %if
        
    end                                                      %indexing on i
    
%   Remove any extra scheduled powers
    xsp = ismember([obj.scheduledPowers.timeInterval],ti);
                                                      %an array of logicals
    obj.scheduledPowers = obj.scheduledPowers(xsp);         %IntervalValues

end                                              %function schedule_power()

%% FUNCTION UPDATE_DUAL_COSTS()
function update_dual_costs(obj,mkt)
% UPDATE_DUAL_COSTS() - Update the dual cost for all active time intervals
% (NOTE: Choosing not to separate this function from the base class because
% cost might need to be handled differently and redefined in subclasses.)
    
%   Gather the active time intervals ti    
    ti = mkt.timeIntervals;                           %active TimeIntervals
    
%   Index through the time intervals ti    
    for i = 1:length(ti)
        
%       Find the marginal price mp for the indexed time interval ti(i) in
%       the given market mkt
        mp = findobj(mkt.marginalPrices,'timeInterval',ti(i));
                                                          %an IntervalValue
        mp = mp(1).value;                         %a marginal price [$/kWh] 
        
        %Find the scheduled power sp for the asset in the indexed time
        %interval ti(i)
        sp = findobj(obj.scheduledPowers,'timeInterval',ti(i));
                                                          %an IntervalValue
        sp = sp(1).value;                       %a scheduled power [avg.kW] 
        
%       Find the production cost in the indexed time interval
        pc = findobj(obj.productionCosts,'timeInterval',ti(i));
                                                          %an IntervalValue
        pc = pc(1).value;                              %production cost [$]
        
%       Dual cost in the time interval is calculated as production cost,
%       minus the product of marginal price, scheduled power, and the
%       duration of the time interval.
%       NOTE: Matlab hours() toggles duration back to numeric and is
%       correct here.
        dur = ti(i).duration;
        if isduration(dur)
            dur = hours(dur);  % Matlab hours() toggles duration to numeric
        end
        dc = pc - (mp * sp * dur);                        % a dual cost [$]
        
%       Check whether a dual cost exists in the indexed time interval
        iv = findobj(obj.dualCosts,'timeInterval',ti(i)); %an IntervalValue

        if isempty(iv)

%           No dual cost was found in the indexed time interval. Create an
%           interval value and assign it the calculated value.
            iv = IntervalValue(obj,ti(i),mkt,'DualCost',dc); 
                                                          %an IntervalValue

%           Append the new interval value to the list of active interval
%           values
            obj.dualCosts = [obj.dualCosts,iv];             %IntervalValues

        else

%           The dual cost value was found to already exist in the indexed
%           time interval. Simply reassign it the new calculated value.
            iv.value = dc;                                 %a dual cost [$]

        end                                                             %if      
        
    end                                                     %for indexing i
    
%   Ensure that only active time intervals are in the list of dual costs
%   adc
    adc = ismember([obj.dualCosts.timeInterval],ti);       %a logical array
    obj.dualCosts = obj.dualCosts(adc);                     %IntervalValues
                                           
%   Sum the total dual cost and save the value
    obj.totalDualCost = sum([obj.dualCosts.value]);    %total dual cost [$]    

end                                           %function update_dual_costs()

%% FUNCTION UPDATE_PRODUCTION_COSTS()
function update_production_costs(obj,mkt)
% UPDATE_PRODUCTION_COSTS() - Calculate the costs of generated energies.    
% (NOTE: Choosing not to separate this function from the base class because
% cost might need to be handled differently and redefined in subclasses.)    
        
%   Gather active time intervals ti
    ti = mkt.timeIntervals;                           %active TimeIntervals
    
%   Index through the active time interval ti
    for i = 1:length(ti)
        
%       Get the scheduled power sp in the indexed time interval
        sp = findobj(obj.scheduledPowers,'timeInterval',ti(i));
                                                          %an IntervalValue
        sp = sp(1).value;                          %schedule power [avg.kW]
        
%       Call on function that calculates production cost pc based on the
%       vertices of the supply or demand curve
%       NOTE that this function is now stand-alone because it might be
%       generally useful for a number of models.
        pc = prod_cost_from_vertices(obj,ti(i),sp); 
                                              %interval production cost [$]
                                              
%       Check for a transition cost in the indexed time interval.
%       (NOTE: this differs from neighbor models, which do not posses the
%       concept of commitment and engagement. This is a good reason to keep
%       this method within its base class to allow for subtle differences.)
        tc = findobj(obj.transitionCosts,'timeInterval',ti(i));
        
        if isempty(tc)
            tc = 0.0;                                                  %[$]
        else
            tc = tc(1).value;                                          %[$]
        end                                                             %if
        
%       Add the transition cost to the production cost        
        pc = pc + tc;
        
%       Check to see if the production cost value has been defined for the
%       indexed time interval
        iv = findobj(obj.productionCosts,'timeInterval',ti(i));
                                                          %an IntervalValue
            
        if isempty(iv)
            
%           The production cost value has not been defined in the indexed
%           time interval. Create it and assign its value pc.
            iv = IntervalValue(obj,ti(i),mkt,'ProductionCost',pc);
                                                          %an IntervalValue
            
%           Append the production cost to the list of active production
%           cost values
            obj.productionCosts = [obj.productionCosts,iv]; %IntervalValues
            
        else
            
%           The production cost value already exists in the indexed time
%           interval. Simply reassign its value.
            iv.value = pc;                    %interval production cost [$]
            
        end                                                             %if
        
    end                                                     %for indexing i
    
%   Ensure that only active time intervals are in the list of active
%   production costs apc
    apc = ismember([obj.productionCosts.timeInterval],ti); %a logical array
    obj.productionCosts = obj.productionCosts(apc);         %IntervalValues
    
%   Sum the total production cost
    obj.totalProductionCost = sum([obj.productionCosts.value]); 
                                                 %total production cost [$]
    
end                                     %function update_production_costs()

%% FUNCTION UPDATE_VERTICES()
function update_vertices(obj,mkt)
%% FUNCTION update_vertices()    
% Create vertices to represent the asset's flexibility
%    
% For the base local asset model, a single, inelastic power is needed.
% There is no flexibility. The constant power may be represented by a
% single (price, power) point (See struct Vertex).
    
%   Gather active time intervals    
    ti = mkt.timeIntervals;                           %active TimeIntervals
    
    %Index through active time intervals ti
    for i = 1:length(ti)
        
        %Find the scheduled power for the indexed time interval
        sp = findobj(obj.scheduledPowers,'timeInterval',ti(i));
                                                          %an IntervalValue
        
        %Extract the scheduled power value
        sp = sp.value;                                            %avg. kW]
        
        %Create the vertex that can represent this (lack of) flexibility
        value = Vertex(inf,0.0,sp,true);                     %See struct Vertex
        
        %Check to see if the active vertex already exists for this indexed
        %time interval. 
        iv = findobj(obj.activeVertices,'timeInterval',ti(i));
        
        %If the active vertex does not exist, a new interval value must be
        %created and stored.
        
        if isempty(iv)
            
            %Create the interval value and place the active vertex in it
            iv = IntervalValue(obj,ti(i),mkt,'ActiveVertex',value);
            
            %Append the interval value to the list of active vertices
            obj.activeVertices = [obj.activeVertices,iv];
 
        else
            
%           Otherwise, simply reassign the active vertex value to the
%           existing listed interval value. (NOTE that this base local
%           asset model unnecessarily reassigns constant values, but the
%           reassignment is allowed because it teaches how a more dynamic
%           assignment may be maintained.
            iv.value = value;
                
        end                                                             %if
        
    end                                                     %for indexing i 
    
end                                             %function update_vertices()

    end                                           % LocalAssetModel methods
    
%% Static LocalAssetModel methods    
    methods (Static)
 
%% TEST_ALL()                                                     COMPLETED
function test_all()
    disp('Running LocalAssetModel.test_all()');
    LocalAssetModel.test_assign_transition_costs();
    LocalAssetModel.test_calculate_reserve_margin(); % Done
    LocalAssetModel.test_cost(); % Missing - low priority
    LocalAssetModel.test_engagement_cost(); % Missing - low priority
    LocalAssetModel.test_schedule_engagement(); % Done - low priority
    LocalAssetModel.test_schedule_power(); % Done - high priority  
    LocalAssetModel.test_update_dual_costs(); % Missing - high priority
    LocalAssetModel.test_update_production_costs(); % Missing - high priority
    LocalAssetModel.test_update_vertices(); % Missing - high priority
end                                                            % TEST_ALL()

%% TEST_ASSIGN_TRANSITION_COSTS()                                 COMPLETED
function test_assign_transition_costs()
% TEST_ASSIGN_TRANSITION_COSTS() - tests method assign_transition_costs()
    disp('Running LocalAssetModel.test_assign_transition_costs()');
    pf = 'pass';
    
%   Create a test Market object.
    test_market = Market;
    
%   Create and store five active TimeInterval objects.
    dt = datetime; % datetime arguments of the TimeInterval constructor.
    start_time = dt;
    interval = Hours(1);
    time_intervals(1) = TimeInterval(dt,interval,test_market,dt,...
        start_time);
    start_time = start_time + interval;
    time_intervals(2) = TimeInterval(dt,interval,test_market,dt,...
        start_time);
    start_time = start_time + interval;
    time_intervals(3) = TimeInterval(dt,interval,test_market,dt,...
        start_time);
    start_time = start_time + interval;
    time_intervals(4) = TimeInterval(dt,interval,test_market,dt,...
        start_time);  
    start_time = start_time + interval;
    time_intervals(5) = TimeInterval(dt,interval,test_market,dt,...
        start_time);    
    
    test_market.timeIntervals = time_intervals;

%   Create a test LocalAsstModel object.
    test_model = LocalAssetModel;  
    
%   Assign engagement cost. This is a triplet of dollar costs for
%   transitioning on, holding, and transitioning off.
    test_model.engagementCost = [1,2,3];
    
%   Create and store five engagement states in the three active time
%   intervals. The test engagment series should be {F,F,T,T,F}
    interval_values(1) = IntervalValue(test_model,time_intervals(1),...
        test_market,'Engagement',false);
    interval_values(2) = IntervalValue(test_model,time_intervals(2),...
        test_market,'Engagement',false);    
    interval_values(3) = IntervalValue(test_model,time_intervals(3),...
        test_market,'Engagement',true);
    interval_values(4) = IntervalValue(test_model,time_intervals(4),...
        test_market,'Engagement',true);
    interval_values(5) = IntervalValue(test_model,time_intervals(5),...
        test_market,'Engagement',false);
    test_model.engagementSchedule = interval_values;
    
%% TEST 1
    disp(['- Test 1: Does model assign engagement and disengagement ',...
        'transition costs?']);
    
    try
        test_model.assign_transition_costs(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors and stopped when called');
    end
    
    transition_costs = [test_model.transitionCosts.value];
    
    if length(transition_costs) ~= 4
        pf = 'fail';
        warning(['  - an unexpected number of transition costs ',...
            'was created']);
    else
        disp(['  - the expected number of transition costs ',...
            'was created']);
    end

% This test presumes an ordering of transition costs. If there is any
% chance that order may have been corrupted, the results must be ensured to
% correspond with chronological time intervals (2:5).
    if any(single(transition_costs) ~= single([2 3 2 1]))
        pf = 'fail';
        warning('  - the transition costs were not as expected');
    else
        disp('  - the transition costs were as expected')
    end
    
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
end                                        % TEST_ASSIGN_TRANSITION_COSTS()

%% TEST_CALCULATE_RESERVE_MARGIN()                                COMPLETED
function test_calculate_reserve_margin()
% TEST_LAM_CALCULATE_RESERVE_MARGIN() - a LocalAssetModel ("LAM") class
% method NOTE: Reserve margins are introduced but not fully integrated into
% code in early template versions.
% CASES:
% 1. uses hard maximum if no active vertices exist
% 2. vertices exist
%   2.1 uses maximum vertex power if it is less than hard power constraint
%   2.2 uses hard constraint if it is less than maximum vertex power 
%   2.3 upper flex power is greater than scheduled power assigns correct
%       positive reserve margin 
%   2.4 upperflex power less than scheduled power assigns zero value to
%       reserve margin.

    disp('Running LocalAssetModel.test_calculate_reserve_margin()');

    pf = 'pass';
    
%   Establish test market
    test_mkt = Market;
    
%   Establish test market with an active time interval
% Note: modified 1/29/18 due to new TimeInterval constructor
    dt = datetime;
    at = dt;
%   NOTE: Function Hours() corrects behavior of Matlab hours().   
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = datetime(date);

    ti = TimeInterval(at,dur,mkt,mct,st);

%   Store time interval
    test_mkt.timeIntervals = ti;

%   Establish a test object that is a LocalAsset with assigned maximum power
    test_object = LocalAsset;
        test_object.maximumPower = 100;

%   Establish test object that is a LocalAssetModel
    test_model = LocalAssetModel;
        test_model.scheduledPowers = ...
            IntervalValue(test_model,ti(1),test_mkt,'ScheduledPower',0.0);

%   Allow object and model to cross-reference one another.
    test_object.model = test_model;
    test_model.object = test_object;

%   Run the first test case.
    try
        test_model.calculate_reserve_margin(test_mkt);
        disp('- method ran without errors');
    catch
        error('- errors occurred while running the method');
    end
    
    if length(test_model.reserveMargins) ~= 1
        error('- an unexpected number of results were stored');
    else
        disp('- one reserve margin was stored, as expected');
    end
    
    if test_model.reserveMargins.value ~= test_object.maximumPower
        pf = 'fail';
        error('- the method did not use the available maximum power');
    else
        disp('- the method used maximum power value, as expected');
    end
    
%   create some vertices and store them
    iv(1) = IntervalValue(test_model,ti,test_mkt,'Vertex',Vertex(0,0,-10));
    iv(2) = IntervalValue(test_model,ti,test_mkt,'Vertex',Vertex(0,0,10));
    test_model.activeVertices = iv;
    
%   run test with maximum power greater than maximum vertex
    test_object.maximumPower = 100;
    test_model.calculate_reserve_margin(test_mkt);   
    
    if test_model.reserveMargins.value ~= 10
        pf = 'fail';
        error('- the method should have used vertex for comparison');
    else
        disp('- the method correctly chose to use the vertex power');
    end
    
%   run test with maximum power less than maximum vertex
    test_object.maximumPower = 5;
    test_model.calculate_reserve_margin(test_mkt);   
    
    if test_model.reserveMargins.value ~= 5
        pf = 'fail';
        error('- method should have used maximum power for comparison');        
    else
        disp('- the method properly chose to use the maximum power');        
    end   
    
%   run test with scheduled power greater than maximum vertex
    test_model.scheduledPowers(1).value = 20;
    test_object.maximumPower = 500;    
    test_model.calculate_reserve_margin(test_mkt);   
    
    if test_model.reserveMargins.value ~= 0
        pf = 'fail';
        error('- method should have assigned zero for a neg. result');        
    else
        disp('- the method properly assigned 0 for a negative result');         
    end

%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
%   Clean up class space
    clear test_object test_model ti test_mkt

end                                       % TEST_CALCULATE_RESERVE_MARGIN()
   
%% TEST_COST()                                                    COMPLETED
function test_cost()
% TEST_COST - test method cost() that calculates production cost from a
% production-cost formula and a power level.
    disp('Running LocalAssetModel.test_cost()');
    pf = 'pass';
    
%   Create a test LocalAssetModel object.
    test_model = LocalAssetModel;
    
%   Create and store a set of production-cost coefficients.
    test_model.costParameters = [1,2,3];
    
    power = 3.14159;
    
    try
        production_cost = test_model.cost(power);
        disp('- the method ran without errors');
    catch
        pf = 'fail';
        warning('- the method had errors and stopeed when called');
    end
    
    if single(production_cost) ~= single(1 + 2*power + 3*power^2)
        pf = 'fail';
        warning('- the method returned an unexpected value');
    else
        disp('- the method returned the expected production-cost value');
    end
   
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
end                                                           % TEST_COST()

%% TEST_ENGAGEMENT_COST()                                         COMPLETED
function test_engagement_cost()
    disp('Running LocalAssetModel.test_engagement_cost()');
    pf = 'pass';
    
%   Create a test LocalAssetModel object.
    test_model = LocalAssetModel;
    
%   Assign engagement costs for [dissengagement, hold, engagement];
    test_model.engagementCost = [1 2 3];
    
%% TEST 1
    disp('- Test 1: Normal transition input arguments [-1,0,1]');

    transition = false - false; % a hold transition, unchanged
    
    try
       cost = test_model.engagement_cost(transition); 
       disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors and stopped');
    end
    
    if cost ~= 2
        pf = 'fail';
        warning('  - the method miscalculated the cost of a hold');
    else
        disp('  - the method correctly calculated the cost of a hold');
    end
    
    transition = false - true; % an disengagement transition
    
    try
       cost = test_model.engagement_cost(transition); 
    end  
    
    if cost ~= 1
        pf = 'fail';
        warning('  - the method miscalculated the cost of a disengagement');
    else
        disp(['  - the method correctly calculated the cost of a ',...
            'disengagement']);
    end    
    
    transition = true - false; % an disengagement transition
    
    try
       cost = test_model.engagement_cost(transition); 
    end  
    
    if cost ~= 3
        pf = 'fail';
        warning('  - the method miscalculated the cost of an engagement');
    else
        disp(['  - the method correctly calculated the cost of an ',...
            'engagement']);
    end    
    
%% TEST 2
    disp('- Test 2: Unexpected, dissallowed input argument');
    
    transition = 7; % a disallowed transition
    
    warning('off','all');
    try
       cost = test_model.engagement_cost(transition); 
       disp('  - method warned and returned gracefully');
       warning('on','all');
    catch
        warning('on','all');
        warning('  - method encountered errors and stopped');
    end  
    
    if cost ~= 0
        pf = 'fail';
        warning('  - the method assigned a cost value other than zero');
    else
        disp(['  - the method correctly assigned zero to the cost']);
    end        
   
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
end                                                % TEST_ENGAGEMENT_COST()

%% TEST_SCHEDULE_ENGAGEMENT()                                     COMPLETED    
function test_schedule_engagement()
% TEST_SCHEDULE_ENGAGEMENT() - tests a LocalAssetModel method called
% schedule_engagment()

    disp('Running LocalAssetModel.test_schedule_engagement()');

    pf = 'pass';
    
%   Establish test market
    test_mkt = Market;
    
%   Establish test market with two distinct active time intervals
% Note: This changed 1/29/18 due to new TimeInterval constructor
    dt = datetime;
    at = dt;
%   NOTE: Function Hours() corrects behavior of Matlab hours().    
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = datetime(date);

    ti(1) = TimeInterval(at,dur,mkt,mct,st);
    
    st = ti(1).startTime + dur;
    ti(2) = TimeInterval(at,dur,mkt,mct,st); 

%   store time intervals
    test_mkt.timeIntervals = ti;

%   Establish test object that is a LocalAssetModel
    test_object = LocalAssetModel;

%   Run the first test case.
    test_object.schedule_engagement(test_mkt);

%   Were the right number of engagement schedule values created?
    if length(test_object.engagementSchedule) ~= 2
        pf = 'fail';
        error('- the method did not store the engagement schedule');
    else
        disp('- the method stored the right number of results');
    end

%   Where the correct scheduled engagement values stored?
    if any([test_object.engagementSchedule.value] ~= [true,true])
        pf = 'fail';
        error('- the stored engagement schedule was not as expected');
    else
        disp('- the result values were as expected');
    end

%   Create and store another active time interval.
    st = ti(2).startTime + dur;
    ti(3) = TimeInterval(at,dur,mkt,mct,st);

%   Re-store time intervals
    test_mkt.timeIntervals = ti;    

%   Run next test case.
    test_object.schedule_engagement(test_mkt);    

%   Was the new time interval used?
    if length(test_object.engagementSchedule) ~= 3
        pf = 'fail';
        error('- the method apparently failed to create a new engagement');
    else
        disp('- the method created and stored new values');
    end

%   Were the existing time interval values reassigned properly?
    if any([test_object.engagementSchedule.value] ~= true * ones(1,3))
        pf = 'fail';
        error('- the existing list was not augmented as expected');
    else
        disp('- the existing list was augmented as expected');
    end

%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);   

%   clean up class space    
    clear ti test_mkt test_object

end                                            % TEST_SCHEDULE_ENGAGEMENT()      

%% TEST_SCHEDULE_POWER()                                          COMPLETED
function test_schedule_power()
% TEST_SCHEDULE_POWER() - tests a LocalAssetModel method called
% schedule_power().

    disp('Running LocalAssetModel.test_schedule_power()');

    pf = 'pass';
    
%   Establish test market
    test_mkt = Market;
    
%   Establish test market with two distinct active time intervals
% Note: This changed 1/29/19 due to new TimeInterval constructor
    dt = datetime;
    at = dt;
%   NOTE: Function Hours() corrects behavior of Matlab hours().    
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = datetime(date);

    ti(1) = TimeInterval(at,dur,mkt,mct,st);

    st = ti(1).startTime + dur;
    ti(2) = TimeInterval(at,dur,mkt,mct,st);

%   Store time intervals
    test_mkt.timeIntervals = ti;

%   Establish test object that is a LocalAssetModel with a default power
%   property.
    test_object = LocalAssetModel;
        test_object.defaultPower = 3.14159;

%   Run the first test case.
    test_object.schedule_power(test_mkt);

%   Were the right number of schduled power values created?
    if length(test_object.scheduledPowers) ~= 2
        pf = 'fail';
        error('- the method did not store the right number of results');
    else
        disp('- the method stored the right number of results');
    end

%   Where the correct scheduled power valules stored?
    if any([test_object.scheduledPowers.value] ~= ...
            test_object.defaultPower * ones(1,2))
        pf = 'fail';
        error('- the stored scheduled powers were not as expected');
    else
        disp('- the result value was as expected');
    end

%   Change the default power.
    test_object.defaultPower = 6;

%   Create and store another active time interval.
    st = ti(2).startTime + dur;
    ti(3) = TimeInterval(at,dur,mkt,mct,st);

%   Re-store time intervals   
    test_mkt.timeIntervals = ti;    

%   Run next test case.
    test_object.schedule_power(test_mkt);    

%   Was the new time interval used?
    if length(test_object.scheduledPowers) ~= 3
        pf = 'fail';
        error('- the method failed to create a new scheduled power');
    else
        disp('- the method created and stored a new scheduled power');
    end

%   Were the existing time intervals reassigned properly?
    if any([test_object.scheduledPowers.value] ~= ...
            test_object.defaultPower * ones(1,3))
        pf = 'fail';
        error('- existing scheduled powers were not reassigned properly');
    else
        disp('- existing stored results were reassigned properly');
    end

%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
%   clean up class space    
    clear ti test_mkt test_object    

end                                                 % TEST_SCHEDULE_POWER()

%% TEST_UPDATE_DUAL_COSTS()                                       COMPLETED
function test_update_dual_costs()
% TEST_UPDATE_DUAL_COSTS() - test method update_dual_costs() that creates
% or revises the dual costs in active time intervals using active vertices,
% scheduled powers, and marginal prices.
% NOTE: This test is virtually identical to the NeighborModel test of the
% same name.
    disp('Running LocalAssetModel.test_update_dual_costs()');
    pf = 'pass';

%   Create a test Market object.
    test_market = Market;
    
%   Create and store a TimeInterval object.
    dt = datetime; % datetime that may be used for most datetime arguments
    time_interval = TimeInterval(dt,Hours(1),test_market,dt,dt);
    test_market.timeIntervals = time_interval;

%   Create and store a marginal price IntervalValue object.
    test_market.marginalPrices = IntervalValue(test_market,...
        time_interval,test_market,'MarginalPrice',0.1);
    
%   Create a test LocalAssetModel object.
    test_model = LocalAssetModel; 
    
%   Create and store a scheduled power IntervalValue in the active time
%   interval. 
    test_model.scheduledPowers = IntervalValue(test_model,...
        time_interval,test_market,'ScheduledPower',100);
    
%   Create and store a production cost IntervalValue object in the active
%   time interval.
    test_model.productionCosts = IntervalValue(test_model,...
        time_interval,test_market,'ProductionCost',1000);

% TEST 1
    disp('- Test 1: First calculation of a dual cost');
    
    try
        test_model.update_dual_costs(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - there were errors when the method was called');
    end
    
    if length(test_model.dualCosts) ~= 1
        pf = 'fail';
        warning('  - the wrong number of dual cost values was created');
    else
        disp('  - the right number of dual cost values was created');
    end
    
    dual_cost = test_model.dualCosts(1).value;
    
    if dual_cost ~= (1000 - 100 * 0.1)
        pf = 'fail';
        warning('  - an unexpected dual cost value was found');
    else
        disp('  - the expected dual cost value was found');
    end
    
% TEST 2
    disp('- Test 2: Reassignment of an existing dual cost');
    
%   Configure the test by modifying the marginal price value.    
   test_market.marginalPrices(1).value = 0.2;
   
     try
        test_model.update_dual_costs(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - there were errors when the method was called');
    end
    
    if length(test_model.dualCosts) ~= 1
        pf = 'fail';
        warning('  - the wrong number of dual cost values was created');
    else
        disp('  - the right number of dual cost values was created');
    end
    
    dual_cost = test_model.dualCosts(1).value;
    
    if dual_cost ~= (1000 - 100 * 0.2)
        pf = 'fail';
        warning('  - an unexpected dual cost value was found');
    else
        disp('  - the expected dual cost value was found');
    end       
   
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
end                                        % TEST_UPDATE_DUAL_COSTS()

%% TEST_UPDATE_PRODUCTION_COSTS()                                 COMPLETED
function test_update_production_costs()
% TEST_UPDATE_PRODUCTION_COSTS() - test method update_production_costs()
% that calculates production costs from active vertices and scheduled
% powers. 
% NOTE: This test is virtually identical to the NeighborModel test of the
% same name.
    disp('Running LocalAssetModel.test_update_production_costs()');
    pf = 'pass';
    
%   Create a test Market object.
    test_market = Market;
    
%   Create and store a TimeInterval object.
    dt = datetime; % datetime that may be used for most datetime arguments
    time_interval = TimeInterval(dt,Hours(1),test_market,dt,dt);
    test_market.timeIntervals = time_interval;

%   Create a test LocalAssetModel object.
    test_model = LocalAssetModel; 
    
%   Create and store a scheduled power IntervalValue in the active time
%   interval. 
    test_model.scheduledPowers = IntervalValue(test_model,...
        time_interval,test_market,'ScheduledPower',50); 
    
%   Create and store some active vertices IntervalValue objects in the
%   active time interval.
    vertices(1) = Vertex(0.1,1000,0);
    interval_values(1) = IntervalValue(test_model,time_interval,...
        test_market,'ActiveVertex',vertices(1));
    vertices(2) = Vertex(0.2,1015,100);
    interval_values(2) = IntervalValue(test_model,time_interval,...
        test_market,'ActiveVertex',vertices(2));    
    test_model.activeVertices = interval_values;
    
% TEST 1
    disp('- Test 1: First calculation of a production cost');
    
    try
        test_model.update_production_costs(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - there were errors when the method was called');
    end
    
    if length(test_model.productionCosts) ~= 1
        pf = 'fail';
        warning('  - the wrong number of production costs was created');
    else
        disp('  - the right number of production cost values was created');
    end
    
    production_cost = test_model.productionCosts(1).value;
    
    if single(production_cost) ~= single(1007.5)
        pf = 'fail';
        warning('  - an unexpected production cost value was found');
    else
        disp('  - the expected production cost value was found');
    end
    
% TEST 2
    disp('- Test 2: Reassignment of an existing production cost');
    
%   Configure the test by modifying the scheduled power value.    
   test_model.scheduledPowers(1).value = 150;
   
     try
        test_model.update_production_costs(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - there were errors when the method was called');
    end
    
    if length(test_model.productionCosts) ~= 1
        pf = 'fail';
        warning('  - the wrong number of productions was created');
    else
        disp('  - the right number of production cost values was created');
    end
    
    production_cost = test_model.productionCosts(1).value;
    
    if single(production_cost) ~= single(1015)
        pf = 'fail';
        warning('  - an unexpected dual cost value was found');
    else
        disp('  - the expected dual cost value was found');
    end       
   
%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
end                                        % TEST_UPDATE_PRODUCTION_COSTS()

%% TEST_UPDATE_VERTICES()                                         COMPLETED
function test_update_vertices()
% TEST_UPDATE_VERTICES() - test method update_vertices(), which for this
% base class of LocalAssetModel does practically nothing and must be
% redefined by child classes that represent flesible assets.
    disp('Running LocalAssetModel.test_update_vertices()');
    pf = 'pass';
    
%   Create a test Market object.
    test_market = Market;
    
%   Create and store a TimeInterval object.
    dt = datetime; % datetime that may be used for most datetime arguments
    time_interval = TimeInterval(dt,Hours(1),test_market,dt,dt);
    test_market.timeIntervals = time_interval;

%   Create a test LocalAssetModel object.
    test_model = LocalAssetModel; 
    
%   Create and store a scheduled power IntervalValue in the active time
%   interval. 
    test_model.scheduledPowers = IntervalValue(test_model,...
        time_interval,test_market,'ScheduledPower',50);   
    
%   Create a LocalAsset object and its maximum and minimum powers.
    test_object = LocalAsset;
    test_object.maximumPower = 200;
    test_object.minimumPower = 0;
    
%   Have the LocalAsset model and object cross reference one another.
    test_object.model = test_model;
    test_model.object = test_object;
    
%% TEST 1
    disp('- Test 1: Basic operation');
     
    try
        test_model.update_vertices(test_market);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors and stopped');
    end   
    
    if length(test_model.activeVertices) ~= 1
        pf = 'fail';
        warning('  - there is an unexpected number of active vertices');
    else
        disp('  - the expected number of active vertices was found');
    end

%   Success.
    fprintf('- the test ran to completion');
    fprintf('\nResult: %s\n\n',pf);
    
end                                                % TEST_UPDATE_VERTICES()

    end                                    % Static LocalAssetModel methods 
 
end                               %classdef LocalAssetModel < AbstractModel

