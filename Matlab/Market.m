classdef Market < handle
% Market Base Class
% A Market object may be a formal driver of myTransactiveNode's
% responsibilities within a formal market. At least one Market must exist
% (see the firstMarket object) to drive the timing with which new
% TimeIntervals are created.

%% Market Properties
    properties
        activeVertices = IntervalValue.empty          % values are vertices
        blendedPrices1 = IntervalValue.empty                       % future
        blendedPrices2 = IntervalValue.empty                       % future
        commitment = false
        converged = false
        defaultPrice = 0.05                                       % [$/kWh]
        dualCosts = IntervalValue.empty                    % values are [$]
        dualityGapThreshold = 0.01             % [dimensionless, 0.01 = 1%]
        futureHorizon = Hours(24)                                     % [h]                                          % [h]
        initialMarketState = MarketState.Inactive             % enumeration
        intervalDuration = Hours(1)                                   % [h]
        intervalsToClear = 1                            % postitive integer
        marginalPrices = IntervalValue.empty           % values are [$/kWh]
        marketClearingInterval = Hours(1)                             % [h]
        marketClearingTime = datetime.empty            % when market clears
        marketOrder = 1     % ordering of sequential markets [pos. integer]
        method = 2   % Calculation method {1: subgradient, 2:interpolation}
        name = ''
        netPowers = IntervalValue.empty               % values are [avg.kW]
        nextMarketClearingTime = datetime.empty          % start of pattern
        productionCosts = IntervalValue.empty              % values are [$]
        timeIntervals = TimeInterval.empty            % struct TimeInterval
        totalDemand = IntervalValue.empty                        % [avg.kW]
        totalDualCost = 0.0                                           % [$]
        totalGeneration = IntervalValue.empty                    % [avg.kW]
        totalProductionCost = 0.0                                     % [$]
    end                                                 % Market Properties
    
%% Market Methods 
methods

%% FUNCTION ASSIGN_SYSTEM_VERTICES()
function assign_system_vertices(mkt,mtn)
% FUNCTION ASSIGN_SYSTEM_VERTICES() - Collect active vertices from neighbor
% and asset models and reassign them with aggregate system information for
% all active time intervals.
%
% ASSUMPTIONS:
%   - Active time intervals exist and are up-to-date
%   - Local convergence has occurred, meaning that power balance, marginal
%     price, and production costs have been adequately resolved from the
%     local agent's perspective
%   - The active vertices of local asset models exist and are up-to-date.
%     The vertices represent available power flexibility. The vertices
%     include meaningful, accurate production-cost information.
%   - There is aggrement locally and in the network concerning the format
%     and content of transactive records
%   - Calls method mkt.sum_vertices in each time interval.
%
% INPUTS:
% mkt - Market object
% mtn - myTransactiveNode object
%
% OUTPUTS:
%   - Updates mkt.activeVertices - vertices that define the net system
%     balance and flexibility. The meaning of the vertex properties are 
%       - marginalPrice: marginal price [$/kWh]
%       - cost: total production cost at the vertex [$]. (A locally
%         meaningful blended electricity price is (total production cost /
%         total production)).
%       - power: system net power at the vertex (The system "clears" where
%         system net power is zero.)

%   Gather active time intervals ti
    ti = mkt.timeIntervals;                           %active TimeIntervals
    
%   Index through active time intervals ti
    for i = 1:length(ti)
        
%       Find and delete existing aggregate active vertices in the indexed
%       time interval. These shall be recreated.
        ind = ~ismember([mkt.activeVertices.timeInterval],ti(i));
                                                             %logical array
        mkt.activeVertices = mkt.activeVertices(ind);       %IntervalValues
        
%       Call the utility method mkt.sum_vertices to recreate the
%       aggregate vertices in the indexed time interval. (This method is
%       separated out because it will be used by other methods.)
        v = mkt.sum_vertices(mtn,ti(i));

%       Create and store interval values for each new aggregate vertex v       
        for k = 1:length(v)
            iv = IntervalValue(mkt,ti(i),mkt,'SystemVertex',v(k));
                                                          %an IntervalValue
            mkt.activeVertices = [mkt.activeVertices,iv];   %IntervalValues
        end                                                 %for indexing k
    
    end                                                     %for indexing i

end   
    
%% FUNCTION BALANCE()
function balance(mkt,mtn)
% FUNCTION BALANCE()
%
%   mkt - Market object
%   mtn - my transactive node object

%   Check and update the time intervals at the begining of the process.
%   This should not need to be repeated in process iterations.
    mkt.check_intervals();

%   Clean up or initialize marginal prices. This should not be
%   repeated in process iterations.
    mkt.check_marginal_prices(); 
    
%   Set a flag to indicate an unconverged condition.
    mkt.converged = false;
    
%   Iterate to convergence. "Convergence" here refers to the status of the
%   local convergence of (1) local supply and demand and (2) dual costs.
%   This local convergence says nothing about the additional convergence
%   between transactive neighbors and their calculations.
    
%   Initialize the iteration counter k
    k = 1;
    
    while mkt.converged == false && k < 100
        
%       Invite all neighbors and local assets to schedule themselves
%       based on current marginal prices 
        mkt.schedule(mtn);
        
%       Update the primal and dual costs for each time interval and
%       altogether for the entire time horizon.
        mkt.update_costs(mtn);
        
%       Update the total supply and demand powers for each time interval.
%       These sums are needed for the sub-gradient search and for the
%       calculation of blended price.
        mkt.update_supply_demand(mtn);

%       Check duality gap for convergence.        
%       Calcualte the duality gap, defined here as the relative difference
%       between total production and dual costs
        if mkt.totalProductionCost == 0
            dg = inf;
        else
            dg = mkt.totalProductionCost - mkt.totalDualCost;         %[$]
            dg = dg / mkt.totalProductionCost; %[dimensionless. 0.01 is 1%]
        end
        
%       Display the iteration counter and duality gap. This may be
%       commented out once we have confidence in the convergence of the
%       iterations.
        fprintf('%i : %f\n',k,dg);       
        
%       Check convergence condition
        if abs(dg) <= mkt.dualityGapThreshold                    %Converged
            
            %1.3.1 System has converged to an acceptable balance.
            mkt.converged = true;
            
        else                                                 %Not converged
            

            
        end                                                             %if
        
%       System is not converged. Iterate. The next code in this
%       method revised the marginal prices in active intervals to drive
%       the system toward balance and convergence.
                
%       Gather active time intervals ti
        ti = mkt.timeIntervals;                              %TimeIntervals
        
% A parameter is used to determine how the computational agent
% searches for marginal prices.
%
% Method 1: Subgradient Search - This is the most general solution
%   technique to be used on non-differentiable solution spaces. It uses the
%   difference between primal costs (mostly production costs, in this case)
%   and dual costs (which are modified using gross profit or consumer cost)
%   to estimate the magnitude of power imbalance in each active time
%   interval. Under certain conditions, a solution is guaranteed. Many
%   iterations may be needed. The method can be fooled, so I've found, by
%   interim oscilatory solutions. This method may fail when large
%   assets have linear, not quadratic, cost functions. 
%
% Methods 2: Interpolation - If certain requirements are met, the solution
%   might be greatly accelerated by interpolatig between the inflection
%   points of the net power curve. 
%   Requirement 1: All Neighbors and LocalAssets are represented by linear
%     or quadratic cost functions, thus ensuring that the net power curve
%     is perfectly linear between its inflecion points.
%   Requirement 2: All Neighbors and Assets update their active vertices in
%     a way that represents their residual flexibility, which can be none,
%     thus ensuring a meaningful connection between balancing in time
%     intervals and scheduling of the individual Neighbors and LocalAssets.
%     This method might fail when many assets do complex scheduling of
%     their flexibilty.

        if mkt.method == 2
            mkt.assign_system_vertices(mtn);
        end                                                 % if method ==2
        
%       Index through active time intervals.
        for i = 1:length(ti)
          
%           Find the marginal price interval value for the
%           corresponding indexed time interval.
            mp = findobj(mkt.marginalPrices,'timeInterval',ti(i));
                                                         % an IntervalValue
            
%           Extract its  marginal price value.
            lamda = mp(1).value;                                  % [$/kWh]
                
            if mkt.method == 1 
                
%               Find the net power corresponding to the indexed time 
%               interval.
                np = findobj(mkt.netPowers,'timeInterval',ti(i)); 
                                                         % an IntervalValue
                                                          
                tg = findobj(mkt.totalGeneration,'timeInterval',ti(i));
                td = findobj(mkt.totalDemand,'timeInterval',ti(i));
                np = np(1).value/(tg(1).value - td(1).value);
            
%               Update the marginal price using subgradient search.
                lamda = lamda - (np * 1e-1) / (10 + k);           % [$/kWh]
                
            elseif mkt.method == 2
                
%               Get the indexed active system vertices
                av = findobj(mkt.activeVertices,'timeInterval',ti(i));
                av = [av.value];

%               Order the system vertices in the indexed time interval
                av = order_vertices(av);

%               Find the vertex that bookcases the balance point from the
%               lower side.[180705DJH: Hung observed tha the market 
%               clearing could occur precisely on a horizontal line,
%               causing the similar triangle method to fail. That
%               likelihood has been addressed by ensuring that the lower
%               and upper vertices cannot have identical power. The similar
%               triangle method may now be used, which properly assigns the
%               upper marginal price to lamda.
                lower_av = av([av.power] < 0); %condition now "<", not "<="
                lower_av = lower_av(length(lower_av));
                
%               Find the vertex that bookcases the balance point from the
%               upper side.                
                upper_av = av([av.power] >= 0);
                upper_av = upper_av(1);
                
%               Interpolate the marginal price in the interval using a
%               principle of similar triangles.
                power_range = upper_av.power - lower_av.power;
                
                mp_range = upper_av.marginalPrice - lower_av.marginalPrice;

                lamda = - mp_range  *  lower_av.power / power_range ...
                    + lower_av.marginalPrice;  
                
            end                                            % if method == 1
            
%           Regardless of the method used, variable "lamda" should now hold
%           the updated marginal price. Assign it to the marginal price
%           value for the indexed active time interval.
            mp.value = lamda;                                     % [$/kWh]            
   
        end                                          % for i = 1:length(ti)
        
%       Increment the iteration counter.
        k = k + 1;        
        
    end                           % while mkt.converged == false && k < 100
    
end                                                    % FUNCTION BALANCE()
        
%% FUNCTION CALCULATE_BLENDED_PRICES()
function calculate_blended_prices(mkt)
% FUNCTION CALCULATE_BLENDED_PRICES()
%   Calculate the blended prices for active time intervals.
%
%   The blended price is the averaged weighted price of all locally
%   generated and imported energies. A sum is made of all costs of
%   generated and imported energies, which are prices weighted by their
%   corresponding energy. This sum is divided by the total generated and
%   imported energy to get the average. 
%
%   The blended price does not include supply surplus and may therefore be
%   a preferred representation of price for local loads and friendly
%   neighbors, for which myTransactiveNode is not competitive and
%   profit-seeking.
%
%   mkt - Market object

    %Update and gather active time intervals ti. It's simpler to
    %recalculate the active time intervals than it is to check for
    %errors.
    
    mkt.check_intervals();
    ti = mkt.timeIntervals;
            
    %Gather primal production costs of the time intervals.
    
    pc = mkt.productionCosts;

    %Perform checks on interval primal production costs to ensure smooth
    %calculations. NOTE: This does not check the veracity of the
    %primal costs.
    
    %CASE 1: No primal production costs have been populated for the various
    %assets and neighbors. This results in termination of the
    %process.
    
    if isempty(pc)
        warning('Primal costs have not yet been calculated.');
        return
                
    %CASE 2: There is at least one active time interval for which primal
    %costs have not been populated. This results in termination of the 
    %process.
        
    elseif length(ti) > length(pc)
        warning('Missing primal costs for active time intervals.');
        return
                
    %CASE 3: There is at least one extra primal production cost that does
    %not refer to an active time interval. It will be removed.
    
    elseif length(ti) < length(pc)
        warning(['Removing primal costs that are not ', ...
            'among active time intervals.']);
        im_ti = [mkt.productionCosts.timeInterval];
        im = ismember(im_ti,mkt.timeIntervals);
        mkt.productionCosts = mkt.productionCosts(im);

    end %if
   
    for i = 1:length(ti)
        pc = findobj(mkt.productionCosts,'timeInterval',ti(i));
        tg = find.obj(mkt.totalGeneration,'timeInterval', ti(i));
        bp = pc / tg;

        nti = ~ismember(mkt.blendedPrices1,'timeInterval',ti(i));
        mkt.blendedPrices1 = mkt.blendedPrices1(nti);
        
        val = bp;        
        iv = IntervalValue(mkt,ti(i),mkt,'BlendedPrice',val);  
        
        %Append the blended price to the list of interval values
        
        mkt.blendedPrices1 = [mkt.blendedPrices1,iv];

    end %for indexing i

end %function calculate_blended_prices()
        
%% FUNCTION CHECK_INTERVALS()
function check_intervals(mkt)
% FUNCTION CHECK_INTERVALS()
%   Check or create the set of instantiated TimeIntervals in this Market
%
%   mkt - Market object

%   Create the array "steps" of time intervals that should be active.
%   NOTE: Function Hours() corrects the behavior of Matlab function
%   hours().
    steps = datetime(mkt.marketClearingTime): ...
        Hours(mkt.marketClearingInterval): ...
        datetime + Hours(mkt.futureHorizon);
    
    steps = steps(steps > datetime-...
        Hours(mkt.marketClearingInterval));
    
    %Index through the needed TimeIntervals based on their start times.
    
    for i = 1:length(steps)
        
        %This is a test to see whether the interval exists.
        %   Case 0: a new interval must be created
        %   Case 1: There is one match, the TimeInterval exists
        %   Otherwise: Duplicates exists and should be deleted.
        
        switch length(findobj(mkt.timeIntervals,'startTime',steps(i)))
            
            %No match was found. Create a new TimeInterval.
            case 0 

                %Create the TimeInterval
                %Modified 1/29 to use TimeInterval constructor
                at = steps(i) - Hours(mkt.futureHorizon);  % activationTime
                dur = Hours(mkt.intervalDuration);               % duration
                mct = steps(i);                        % marketClearingTime
                st = steps(i);                                  % startTime
                
                ti =  TimeInterval(at,dur,mkt,mct,st);
                                
% ELIMINATE HURKY INLINE CONSTRUCTION BELOW 
%                 ti = TimeInterval();
%                 
%                     %Populate the TimeInterval properties
% 
%                     ti.name = char(steps(i),'yyMMdd-hhmm');
%                     ti.startTime = steps(i);
%                     ti.active = true;
%                     ti.duration = Hours(mkt.intervalDuration);
%                     ti.marketClearingTime = steps(i);
%                     ti.market = mkt;
%                     ti.activationTime = steps(i)-Hours(mkt.futureHorizon);
%                     ti.timeStamp = datetime;
%                     
%                     %assign marketState property
%                     
%                     ti.assign_state(ti.market); 
% ELIMINATE HURKY INLINE CONSTRUCTOR ABOVE
                
                %Store the new TimeInterval in Market.timeIntervals
                
                mkt.timeIntervals = [mkt.timeIntervals,ti];
                
            %The TimeInterval already exists.    
            case 1 
                
                %Find the TimeInterval and check its market state
                %assignment.
                
                ti = findobj(mkt.timeIntervals,'startTime',steps(i));
                
                ti.assign_state(mkt);
                
            %Duplicate time intervals exist. Remove all but one.
            otherwise 
                
                %Get rid of duplicate TimeIntervals.
                
                mkt.timeIntervals = unique(mkt.timeIntervals);
                
                %Find the remaining TimeInterval having the startTime
                %step(i).
                
                ti = findobj(mkt.timeIntervals,'startTime',steps(i));
                
                %Finish by checking and updating the TimeInterval's
                %market state assignment.
                
                ti.assign_state(mkt);
                
        end %switch
        
    end %for
    
end %function check_intervals() 
    
%% FUNCTION CHECK_MARGINAL_PRICES()
function check_marginal_prices(mkt)
% FUNCTION CHECK_MARGINAL_PRICES()
%   Check that marginal prices exist for active time intervals. If they do
%   not exist for a time interval, choose from these alternatives that are
%   ordered from best to worst:
%       (1) initialize the marginal price from that of the preceding
%       interval.
%       (2) use the default marginal price.
%   INPUTS:
%       mkt     market object 
%   OUTPUTS:
%       populates list of active marginal prices (see class IntervalValue)
%
%   [Checked on 12/21/17]

    %Check and retrieve the list of active intervals ti
    
%    mkt.check_intervals; %This should have already been done.   
    ti = mkt.timeIntervals;
    
    %Clean up the list of active marginal prices. Remove any active
    %marginal prices that are not in active time intervals.
    ind = ismember([mkt.marginalPrices.timeInterval],ti);
    mkt.marginalPrices = mkt.marginalPrices(ind);
    
    %Index through active time intervals ti
    for i = 1:length(ti)
        
        %Check to see if a marginal price exists in the active time
        %interval
        iv = findobj(mkt.marginalPrices,'timeInterval',ti(i));
        
        if isempty(iv) 
            
            %No marginal price was found in the indexed time interval. Is
            %a marginal price defined in the preceding time interval?
            
            %Extract the starting time st of the currently indexed time
            %interval 
            
            st = ti(i).startTime;
            
            %Calculate the starting time st of the previous time interval
            
            st = st - ti(i).duration;
            
            %Find the prior active time interval pti that has this
            %calculated starting time
            
            pti = findobj(mkt.timeIntervals,'startTime',st);
            
            %Initialize previous marginal price value pmp as an empty set
            
            pmp = [];            
            
            if ~isempty(pti)
                
                %There is an active preceding time interval. Check whether
                %there is an active marginal price in the previous time
                %interval.
                
                pmp = findobj(mkt.marginalPrices,'timeInterval',pti); 
                                                          %an IntervalValue
            end

            if isempty(pmp)
                
                %No marginal price was found in the previous time interval
                %either. Assign the marginal price from a default value.
                
                value = mkt.defaultPrice;                          %[$/kWh]
                
            else
                
                %A marginal price value was found in the previous time
                %interval. Use that marginal price.
                
                value = pmp.value;                                 %[$/kWh]
                
            end %if
            
            %Create an interval value for the new marginal price in the
            %indexed time interval with either the default price or the
            %marginal price from the previous active time interval.
            
            iv = IntervalValue(mkt,ti(i),mkt,'MarginalPrice',value);
            
            %Append the marginal price value to the list of active marginal
            %prices
            
            mkt.marginalPrices = [mkt.marginalPrices,iv];
            
        end                                                             %if
  
    end                                                     %for indexing i

end %function check_marginal_prices()
        
%% FUNCTION SCHEDULE()
function schedule(mkt,mtn)
% FUNCTION SCHEDULE()
%   Process called to
%   (1) invoke all models to update the scheduling of their resources,
%   loads, or neighbor
%   (2) converge to system balance using sub-gradient search.
%
%   mkt - Market object
%   mtn - my transactive node object

    %1.2.1 Call resource models to update their schedules
    
    %Gather the list of local resource models m
    m = mtn.localAssets;                         %cell array of LocalAssets
    
    %Call each local asset model m to schedule itself. NOTE: cell array
    %elements should now be referenced by braces.
    for i = 1:length(m)
        m{i}.model.schedule(mkt);
    end                                                     %for indexing i
    
    %1.2.2 Call neighbor models to update their schedules
    
    %Gather the list of neighbors m
    m = mtn.neighbors;                             %cell array of Neighbors

    %Call each neighbor model m to schedule itself
    for i = 1:length(m)
        m{i}.model.schedule(mkt);
    end                                                     %for indexing i

end                                                   % FUNCTION SCHEDULE()

%% FUNCTION SUM_VERTICES()
function [ vertices ] = sum_vertices(~,mtn,ti,varargin)
% FUNCTION SUM_VERTICES() - Create system vertices with system information
% for a single time interval. An optional argument allows the exclusion of
% a transactive neighbor object, which is useful for transactive records
% and their corresponding demand or supply curves.
% This utility method should be used for creating transactive signals (by
% excluding the neighbor object), and for visualization tools that review
% the local system's net supply/demand curve.
%
% VERSIONING
% 0.1 2018-01 Hammerstrom
%   - Original method draft completed

%   Check if a fourth argument, an object to be excluded, was used
%   Initialize "object to exclude" ote
    ote = [];
    
    if nargin == 4
        
        %A fourth argument was used. Assign it as an object to exclude ote.
        %NOTE: Curly braces must be used with varargin{} to properly
        %reference contects.
        ote = varargin{1}; %a neighbor or asset model object
        
    end %if

%   Initialize a list of marginal prices mps at which vertices will be
%   created. 
%   It is computationally wise to pre-allocate vector memory. This is
%   accomplished here by padding with 100 zeros and using a counter.
    mps = zeros(1,100);                            %marginal prices [$/kWh]
    mps_cnt = 0;
    
%   Gather the list of active neighbor objects n    
    n = mtn.neighbors;                             %cell array of neighbors
    
%   Index through the active neighbor objects n    
    for i = 1:length(n)
        
%       Change the reference to the corresponding neighbor model        
        nm = n{i}.model;                                  %a neighbor model
        
%       Jump out of this iteration if neighbor model nm happens to be the
%       "object to exclude" ote
        if ~isempty(ote)
            if nm == ote
                continue;
            end
        end                                                             %if
        
%       Find the neighbor model's active vertices in this time interval        
        mp = findobj(nm.activeVertices,'timeInterval',ti);  %IntervalValues
        
        if ~isempty(mp)
            
%           At least one active vertex was found in the time interval
            
%           Extract the vertices from the interval values       
            mp = [mp.value];                                      %Vertices

            if length(mp) == 1
                
%               There is one vertex. This means the power is constant for
%               this neighbor. Enforce the policy of assigning infinite
%               marginal price to constant vertices.
                
                mp = inf;                           %marginal price [$/kWh]
                
            else
                
%               There are multiple vertices. Use the marginal price values
%               from the vertices themselves.
                
                mp = [mp.marginalPrice];           %marginal prices [$/kWh]
                
            end 
            
%           Increment the index counter
            mps_cnt_start = mps_cnt + 1;
            mps_cnt = mps_cnt + length(mp);                  %index counter
            
%           Warn if vector counter exceeds its original allocation            
            if mps_cnt > 100
                warning('vector length has exceeded its preallocation');
            end %if  
            
%           Append the marginal price to the list of marginal prices mps            
            mps(mps_cnt_start:mps_cnt) = mp;       %marginal prices [$/kWh]        
            
        end                                                             %if

    end                                                     %for indexing i
    
%   Gather the list of active local asset objects n      
    n = mtn.localAssets;                       %a cell array of localAssets
    
    for i = 1:length(n)
%       Change the reference to the corresponding local asset model        
        nm = n{i}.model;                               %a local asset model
        
%       Jump out of this iteration if local asset model nm happens to be
%       the "object to exclude" ote
        if ~isempty(ote)
            if nm == ote
                continue;
            end
        end                                                             %if
        
%       Find the local asset model's active vertices in this time interval        
        mp = findobj(nm.activeVertices,'timeInterval',ti);  %IntervalValues
        
        if ~isempty(mp)
            
%           At least one active vertex was found in the time interval
            
%           Extract the vertices from the interval values       
            mp = [mp.value];                                      %Vertices
             
%           Extract the marginal prices from the vertices  

            if length(mp) == 1
                
%               There is one vertex. This means the power is constant for
%               this local asset. Enforce the policy of assigning infinite
%               marginal price to constant vertices.
                
                mp = inf;                           %marginal price [$/kWh]
                
            else
                
%               There are multiple vertices. Use the marginal price values
%               from the vertices themselves.
                
                mp = [mp.marginalPrice];           %marginal prices [$/kWh]
                
            end                                                         %if
            
%           Increment the index counter
            mps_cnt_start = mps_cnt + 1;
            mps_cnt = mps_cnt + length(mp);                  %index counter
            
%           Warn if vector counter exceeds its original allocation            
            if mps_cnt > 100
                warning('vector length has exceeded its preallocation');
            end %if  
            
%           Append the marginal price to the list of marginal prices mps            
            mps(mps_cnt_start:mps_cnt) = mp;       %marginal prices [$/kWh]  
            
        end                                                             %if
            
    end                                                     %for indexing i

%   Trim mps, which was originally padded with zeros.
    mps = mps(1:mps_cnt);                          %marginal prices [$/kWh]
    
%% A list of vertex marginal prices have been created.

%   Sort the marginal prices from least to greatest
    mps = sort(mps);                               %marginal prices [$/kWh]
    
%   Ensure that no more than two vertices will be created at the same
%   marginal price. The third output of function unique() is useful here
%   because it is the index of unique entries in the original vector.
    [~,~,ind] = unique(mps);               %index of unique vector contents

%   Create a new vector of marginal prices. The first two entries are
%   accepted because they cannot violate the two-duplicates rule. The
%   vector is padded with zeros, which should be compuationally efficient.
%   A counter is used and should be incremented with new vector entries.
    if mps_cnt < 3
        mps_new = mps;
    else
        mps_new = [mps(1:2),zeros(1,98)];         % marginal prices [$/kWh]
        mps_cnt = 2;                                     % indexing counter                          
    end
    
%   Index through the indices and append the new list only when there are
%   fewer than three duplicates.
    for i = 3:length(ind)
        
%       A violation of the two-duplicate rule occurs if an entry is the
%       third duplicate. If this case, jump out of the loop to the next
%       iteration.
        if ind(i) == ind(i-1) && ind(i-1) == ind(i-2)
            
            continue;
            
        else
            
%           There are no more than two duplicates. 

%           Increment the vector indexing counter
            mps_cnt = mps_cnt + 1;
            
%           Warn if the vector's preallocation size is becoming exceeded            
            if mps_cnt > 100
                warning('vector length has exceeded its preallocation');
            end %if
            
%           Append the list of marginal prices with the indexed marginal
%           price.
            mps_new(mps_cnt) = mps(i);             %marginal prices [$/kWh]
            
        end                                                             %if
        
    end                                                     %for indexing i

%   Trim the new list of marginal prices mps_new that had been padded with
%   zeros and rename it mps 
    mps = mps_new(1:mps_cnt);                      %marginal prices [$/kWh]  
    

    if mps_cnt >= 2
        
%       There are at least two marginal prices. (This is a condition that
%       is unlikely but was found in testing of version 1.1.)
        if mps(mps_cnt) == inf && mps(mps_cnt-1) == inf

%       A duplicate infinite marginal price, which is used to indicate a
%       constant, inelastic power, is not meaningful and must be deleted
%       from the end of the list of marginal prices mps.
        mps = mps(1:(mps_cnt-1));                  %marginal prices [$/kWh]
        
        end               % if mps(mps_cnt) == inf && mps(mps_cnt-1) == inf
        
    end                                                   % if mps_cnt >= 2
   
%% A clean list of marginal prices has been created

%   Correct assignment of vertex power requires a small offset of any
%   duplicate values. Index through the new list of marginal prices again.
    for i = 2:length(mps)
        
        if mps(i) == mps(i-1)
            
%           A duplicate has been found. Offset the first of the two by a
%           very small number
            mps(i-1) = mps(i-1) - eps;             %marginal prices [$/kWh]
            
        end                                                             %if
        
    end                                                     %for indexing i
    
%% Create vertices at the marginal prices
%   Initialize the list of vertices 
    vertices = [];                                                %Vertices

%   Index through the cleaned list of marginal prices    
    for i = 1:length(mps)
        
%       Create a vertex at the indexed marginal price value (See struct
%       Vertex.)
        iv = Vertex(mps(i),0,0);
        
%       Initialize the net power pwr and total production cost pc at the
%       indexed vertex     
        pwr = 0.0;                                      %net power [avg.kW]
        pc = 0.0;                                      %production cost [$]
        
%% Include power and production costs from neighbor models        
        
%       Gather the list of active neighbors n       
        n = mtn.neighbors;                         %cell array of neighbors

%       Index through the active neighbor models n. NOTE: Now that
%       neighbors is a cell array, its elements must be referenced using
%       curly braces.
        for k = 1:length(n)
            
            nm = n{k}.model;                              %a neighbor model
                        
            if nm == ote
                
%               The indexed neighbor model is the "object to exclude" ote.
%               Continue without including its power or production costs.                 
                continue;
                
            end                                                         %if
            
%           Calculate the indexed neighbor model's power at the indexed
%           marginal price and time interval. NOTE: This must not corrupt
%           the "scheduled power" at the converged system's marginal price.
            p = production(nm,mps(i),ti);                  % power [avg.kW]
            
%           Calculate the neighbor model's production cost at the indexed
%           marginal price and time interval, and add it to the sum
%           production cost pc. NOTE: This must not corrupt the "scheduled"
%           production cost for this neighbor model.
            pc = pc + prod_cost_from_vertices(nm,ti,p); 
                                                       %production cost [$]
            
%           Add the neighbor model's power to the sum net power at this
%           vertex.
            pwr = pwr + p;                              %net power [avg.kW]
        end                                                 %for indexing k
        
%% Include power and production costs from local asset models         
        
%       Gather a list of active local assets n
        n = mtn.localAssets;                    %cell array of local assets
   
%       Index through the local asset models n. NOTE: now that local assets
%       is a cell array, its elements must be referenced using curly
%       braces.
        for k = 1:length(n)
            
            nm = n{k}.model;                           %a local asset model
            
            if nm == ote
                
%               The indexed local asset model is the "object to exclude"
%               ote. Continue without including its power or production
%               cost.
                continue;
                
            end                                                         %if
            
%           Calculate the power for the indexed local asset model at the
%           indexed marginal price and time interval.
            p = production(nm,mps(i),ti);                   %power [avg.kW]
            
%           Find the indexed local asset model's production cost and add it
%           to the sum of production cost pc for this vertex.
            pc = pc + prod_cost_from_vertices(nm,ti,p); 
                                                       %production cost [$]
                                                       
%           Add local asset power p to the sum net power pwr for this
%           vertex.
            pwr = pwr + p;                              %net power [avg.kW]
            
        end                                                 %for indexing k  
        
%       Save the sum production cost pc into the new vertex iv        
        iv.cost = pc;                              %sum production cost [$]
        
%       Save the net power pwr into the new vertex iv        
        iv.power = pwr;                                 %net power [avg.kW]

%       Append Vertex iv to the list of vertices        
        vertices = [vertices,iv];                                 %Vertices

    end                                                     %for indexing i

end %function sum_vertices()

%% FUNCTION UPDATE_COSTS()
function update_costs(mkt,mtn)
% Sum the production and dual costs from all modeled local resources, local
% loads, and neighbors, and then sum them for the entire duration of the
% time horizon being calculated.
%
% PRESUMPTIONS:
%   - Dual costs have been created and updated for all active time
%     intervals for all neighbor objects
%   - Production costs have been created and updated for all active time
%     intervals for all asset objects
%
% INTPUTS:
%   mkt - Market object
%   mtn - my Transactive Node object
%
% OUTPUTS:
%   - Updates Market.productionCosts - an array of total production cost in
%     each active time interval
%   - Updates Market.totalProductionCost - the sum of production costs for
%     the entire future time horizon of active time intervals
%   - Updates Market.dualCosts - an array of dual cost for each active time
%     interval
%   - Updates Market.totalDualCost - the sum of all the dual costs for the
%     entire future time horizon of active time intervals

%   Gather local asset models m
    m = mtn.localAssets;                         %cell array of LocalAssets
    
%   Call each LocalAssetModel to update its costs    
    for i = 1:length(m)
        m{i}.model.update_costs(mkt);
    end
    
%   Gather active neighbors m
    n = mtn.neighbors;                             %cell array of Neighbors
    
%   Call each NeighborModel to update its costs     
    for i = 1:length(n)
        n{i}.model.update_costs(mkt);
    end
    
%   Gather active time intervals ti
    ti = mkt.timeIntervals;                                  %TimeIntervals 
    
    %Index through the active time intervals ti
    for i = 1:length(ti)

        %Initialize the sum dual cost sdc in this time interval
        sdc = 0.0;                                                     %[$]
        
        %Initialize the sum production cost spc in this time interval
        spc = 0.0;                                                     %[$]

        %Index through local asset models m. NOTE: Now that localAssets is
        %a cell array, its elements must be referenced by curly braces.
        for j = 1:length(m)
            
            iv = findobj(m{j}.model.dualCosts,'timeInterval',ti(i)); 
                                                          %an IntervalValue
            sdc = sdc + iv(1).value;                     %sum dual cost [$]
            
            iv = findobj(m{j}.model.productionCosts,'timeInterval',ti(i));
                                                          %an IntervalValue
            spc = spc + iv(1).value;               %sum production cost [$]
            
        end                                                % for indexing j

        %Index through neighbors m. NOTE: now that neighbors is a cell
        %array, its elements must be referenced using curly braces.
        for j = 1:length(n)
            
            iv = findobj(n{j}.model.dualCosts,'timeInterval',ti(i));
                                                          %an IntervalValue
            sdc = sdc + iv(1).value;                     %sum dual cost [$]
            
            iv = findobj(n{j}.model.productionCosts,'timeInterval',ti(i));
                                                          %an IntervalValue
            spc = spc + iv(1).value;               %sum production cost [$]
            
        end                                                % for indexing j

        %Check to see if a sum dual cost exists in the indexed time
        %interval 
        iv = findobj(mkt.dualCosts,'timeInterval',ti(i));
        
        if isempty(iv)
            
            %No dual cost was found for the indexed time interval. Create
            %an IntervalValue and assign it the sum dual cost for the
            %indexed time interval
            iv = IntervalValue(mkt,ti(i),mkt,'DualCost',sdc); 
                                                          %an IntervalValue
        
            %Append the dual cost to the list of interval dual costs
            mkt.dualCosts = [mkt.dualCosts, iv];            %IntervalValues
            
        else
            
            %A sum dual cost value exists in the indexed time interval.
            %Simply reassign its value
            iv.value = sdc;                              %sum dual cost [$]
            
        end                                                             %if
        
        %Check to see if a sum production cost exists in the indexed time
        %interval 
        iv = findobj(mkt.productionCosts,'timeInterval',ti(i));
        
        if isempty(iv)
            
            %No sum production cost was found for the indexed time
            %interval. Create an IntervalValue and assign it the sum
            %prodution cost for the indexed time interval
            iv = IntervalValue(mkt,ti(i),mkt,'ProductionCost',spc); 
                                                          %an IntervalValue
        
            %Append the production cost to the list of interval production
            %costs 
            mkt.productionCosts = [mkt.productionCosts, iv];%IntervalValues
            
        else
            
            %A sum production cost value exists in the indexed time
            %interval. Simply reassign its value
            iv.value = spc;                        %sum production cost [$]
            
        end                                                             %if
    
    end                                                     %for indexing i
    
    %Sum total dual cost for the entire time horizon
    mkt.totalDualCost = sum([mkt.dualCosts.value]);                    %[$]
    
    %Sum total primal cost for the entire time horizon
    mkt.totalProductionCost = sum([mkt.productionCosts.value]);        %[$]
  
end                                                %function update_costs()
      
%% FUNCTION UPDATE_SUPPLY_DEMAND()
function update_supply_demand(mkt,mtn)
% FUNCTION UPDATE_SUPPLY_DEMAND()
%   For each time interval, sum the power that is generated, imported,
%   consumed, or exported for all modeled local resources, neighbors, and
%   local load.

    %Extract active time intervals
    ti = mkt.timeIntervals;                           %active TimeIntervals
    
    %Index through the active time intervals ti
    for i = 1:length(ti)
        
        %Initialize total generation tg
        tg = 0.0;                                                 %[avg.kW]
        
        %Initialize total demand td
        td = 0.0;                                                 %[avg.kW]
        
        %% Index through local asset models m.
        % NOTE: Now that localAssets is a cell array, its elements must be
        % referenced using curly braces.
        
        m = mtn.localAssets;                     %cell array of LocalAssets
        
        for k = 1:length(m)
            
            mo = findobj(m{k}.model.scheduledPowers,'timeInterval',ti(i));
                                                            %IntervalValues
            
            %Extract and include the resource's scheduled power
            p = mo(1).value;                                      %[avg.kW]
            
            if p > 0                                            %Generation
                
                %Add positive powers to total generation tg
                tg = tg + p;                                      %[avg.kW]
                
            else                                                    %Demand
                
                %Add negative powers to total demand td
                td = td + p;                                      %[avg.kW]
                
            end                                                         %if
            
        end                                              %for indexing on k
        
        %% Index through neighbors m
        m = mtn.neighbors;                         %cell array of Neighbors
        
        for k = 1:length(m)
            
            %Find scheduled power for this neighbor in the indexed time
            %interval
            mo = findobj(m{k}.model.scheduledPowers,'timeInterval',ti(i));
            
            %Extract and include the neighbor's scheduled power
            p = mo(1).value;                                      %[avg.kW]
            
            if p > 0                                            %Generation
                
                %Add positive power to total generation tg
                tg = tg + p;                                      %[avg.kW]
                
            else                                                    %Demand
                
                %Add negative power to total demand td
                td = td + p;                                      %[avg.kW]
                
            end                                                         %if
            
        end                                                 %for indexing k
        
        %At this point, total generation and importation tg, and total
        %demand and exportation td have been calculated for the indexed
        %time interval ti(i)

        %Save the total generation in the indexed time interval
        
        %Check whether total generation exists for the indexed time
        %interval
        iv = findobj(mkt.totalGeneration,'timeInterval',ti(i));
                                                          %an IntervalValue
        
        if isempty(iv)
            
            %No total generation was found in the indexed time interval.
            %Create an interval value.
            iv = IntervalValue(mkt,ti(i),mkt,'TotalGeneration',tg);
                                                          %an IntervalValue
            
            %Append the total generation to the list of total generations
            mkt.totalGeneration = [mkt.totalGeneration,iv];
            
        else
            
            %Total generation exists in the indexed time interval. Simply
            %reassign its value.
            iv(1).value = tg;                                     %[avg.kW]
            
        end

        %% Calculate and save total demand for this time interval.
        %NOTE that this formulation includes both consumption and
        %exportation among total load.
        
        %Check whether total demand exists for the indexed time
        %interval

        iv = findobj(mkt.totalDemand,'timeInterval',ti(i));
                                                          %an IntervalValue
        
        if isempty(iv)
            
            %No total demand was found in the indexed time interval. Create
            %an interval value.
            iv = IntervalValue(mkt,ti(i),mkt,'TotalDemand',td);
                                                          %an IntervalValue
            
            %Append the total demand to the list of total demands
            mkt.totalDemand = [mkt.totalDemand,iv];
            
        else
            
            %Total demand was found in the indexed time interval. Simply
            %reassign it.
            iv(1).value = td;                                     %[avg.kW]
            
        end                                                             %if
        
        %% Update net power for the interval
        %Net power is the sum of total generation and total load.
        %By convention generation power is positive and consumption
        %is negative.
        
        %Check whether net power exists for the indexed time interval
        iv = findobj(mkt.netPowers,'timeInterval',ti(i)); %an IntervalValue
        
        if isempty(iv)
            
            %Net power is not found in the indexed time interval. Create an
            %interval value.
            iv = IntervalValue(mkt,ti(i),mkt,'NetPower',tg+td); 
                                                          %an IntervalValue
            
            %Append the net power to the list of net powers
            mkt.netPowers = [mkt.netPowers,iv];                   %[avg.kW]
            
        else
            
            %A net power was found in the indexed time interval. Simply
            %reassign its value.
            iv(1).value = tg+td;                                  %[avg.kW]
            
        end                                                             %if

    end                                                     %for indexing i
    
end                                        %function update_supply_demand()

%% VIEW_MARGINAL_PRICES()
function view_marginal_prices(mkt)
% VIEW_MARGINAL_PRICES() - visualize marginal pricing in active time
% intervals.
% mkt - market object

%   Gather active time series and make sure they are in chronological order
    ti = mkt.timeIntervals;
    ti = [ti.startTime];
    ti = sort(ti);
    
if ~isa(mkt,'Market')
    warning('Object must be a NeighborModel or LocalAssetModel');
    return;   
else
    mp = mkt.marginalPrices;
end
    mp_ti = [mp.timeInterval];
    [~,ind] = sort([mp_ti.startTime]);
    mp = mp(ind);
    mp = [mp.value]; 

% This can be made prettier as time permits.
    hold off;
    plot(ti,mp,'*'); 
    hold on;
    line(ti,mp);
    title('Marginal Prices in Active Time Intervals');
    xlabel('time');
    ylabel('marginal price ($/kWh)');
    hold off;
    
end                                       % FUNCTION VIEW_MARGINAL_PRICES()

%% FUNCTION VIEW_NET_CURVE()
function view_net_curve(mkt,i)
    
%   Clear existing figure    
    clf; 
    
%   Gather the active time intervals    
    ti = mkt.timeIntervals;
    
%    Make sure the time intervals are sorted by increasing start time   
    [~,ind] = sort([ti.startTime]);
    ti = ti(ind);
    
%   Pick out the active time interval that is indexed by input i
    ti = ti(i);

%   Find the active system vertices in the indexed time interval    
    vertices = findobj(mkt.activeVertices,'timeInterval',ti);
                                                            %IntervalValues
                                                            
%   Extract the vertices. See struct Vertex.                                                        
    vertices = [vertices.value];                           %active Vertices
    
%   Eliminate any vertices that have infinite marginal price values    
    ind = ~isinf([vertices.marginalPrice]);                 %an index array
    vertices = vertices(ind);                                     %Vertices
    
%   Sort the active vertices in the indexed time interval by power and by
%   marginal price
    vertices = order_vertices(vertices);                          %Vertices

%   Calculate the extremes and range of the horizontal marginal-price axis    
    minx = min([vertices.marginalPrice]);                          %[$/kWh] 
    maxx = max([vertices.marginalPrice]);                          %[$/kWh] 
    xrange = maxx - minx;                                          %[$/kWh] 

%   Calculate the extremes and range of the vertical power axis      
    miny = min([vertices.power]);                                  %avg.kW]
    maxy = max([vertices.power]);                                  %avg.kW] 
    yrange = maxy - miny;                                          %avg.kW]
   
%   Perform scaling if power range is large 
    if yrange > 1000
        unit = '(MW)';
        factor = 0.001;
        miny = factor * miny;
        maxy = factor * maxy;
        yrange = factor * yrange;
    else
        unit = '(kW)';
        factor = 1.0;
    end
    
    hold off;
%   Start the figure with nicely scaled axes    
    axis([minx - 0.1 * xrange, maxx + 0.1 * xrange, ...
        miny - 0.1 * yrange, maxy + 0.1 * yrange]);
    
%   Freeze the figure to maintain the axis    
    hold on;

%   Place a marker at each vertex.
    plot([vertices.marginalPrice],factor * [vertices.power],'*');

%   Create a horizontal line at zero.
    line([minx - 0.1 * xrange, maxx + 0.1 * xrange], ...
        [0.0,0.0],'LineStyle','--');

%   Draw a line from the left figure boundary to the first vertex.
    line([minx - 0.1 * xrange,vertices(1).marginalPrice], ...
        [factor * vertices(1).power,factor * vertices(1).power]);

%   Draw lines from each vertex to the next. If two successive
%   vertices are not continuous, no line should be drawn.
    for i = 1:(length(vertices)-1)
        if vertices(i).continuity == 0 && vertices(i+1).continuity ==0
            line([vertices(i:i+1).marginalPrice],...
                factor * [vertices(i:i+1).power],'LineStyle','none'); 
        else
            line([vertices(i:i+1).marginalPrice],...
                factor * [vertices(i:i+1).power],'LineStyle','-'); 
        end %if
    end %for indexing i
    
%   Draw a line from the rightmost vertex to the left figure boundary.
    len = length(vertices);
    line([vertices(len).marginalPrice,maxx + 0.1 * xrange],...
        [factor * vertices(len).power,factor * vertices(len).power]);    

%   Pretty it up with labels and title
    xlabel('unit price ($/kWh)');
    ylabel('power ' + string(unit));
    title('Production Vertices (' + string(ti.name) + ')');
    
%   Unfreeze the figure    
    hold off;

end                                              %function view_net_curve()

end                                                        % Market Methods

%% Static Market Methods
methods (Static)

%% TEST_ALL()                                                     COMPLETED
function test_all()
    disp('Running Market.test_all()');
    Market.test_assign_system_vertices(); % High priority - test not complete
    Market.test_balance();              % High priorty - test not completed
    Market.test_calculate_blended_prices(); % Low priority - FUTURE
    Market.test_check_intervals();      % High priorty - test not completed
    Market.test_check_marginal_prices();% High priorty - test not completed
    Market.test_schedule();             % High priorty - test not completed
    Market.test_sum_vertices();         % High priorty - test not completed
    Market.test_update_costs();         % High priorty - test not completed
    Market.test_update_supply_demand(); % High priorty - test not completed
    Market.test_view_net_curve();       % High priorty - test not completed
    Market.test_view_marginal_prices();    % High priority - test completed
end                                                            % TEST_ALL()

%% TEST_ASSIGN_SYSTEM_VERTICES()
function pf = test_assign_system_vertices()
    disp('Running Market.test_assign_system_vertices()');
    pf = 'test is not complete';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
end                                         % TEST_ASSIGN_SYSTEM_VERTICES()

%% TEST_BALANCE
function pf = test_balance()
    disp('Running Market.test_balance()');
    pf = 'test is not complete';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
end                                                          % TEST_BALANCE

%% TEST_CALCULATE_BLENDED_PRICES()                              LOW PRIOITY
function pf = test_calculate_blended_prices()
    disp('Running Market.test_calculate_blended_prices()');
    pf = 'test is not complete';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
end                                       % TEST_CALCULATE_BLENDED_PRICES()

%% TEST_CHECK_INTERVALS()
function pf = test_check_intervals()
    disp('Running Market.test_check_intervals()');
    pf = 'test is not complete';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
end                                                % TEST_CHECK_INTERVALS()

%% TEST_CHECK_MARGINAL_PRICES()
function pf = test_check_marginal_prices()
    disp('Running Market.test_check_marginal_prices()');
    pf = 'test is not complete';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
end                                          % TEST_CHECK_MARGINAL_PRICES()

%% TEST SCHEDULE()                                                COMPLETED
function pf = test_schedule()
    disp('Running Market.test_schedule()');
    disp('WARNING: This test may be affected by NeighborModel.schedule()');
    disp('WARNING: This test may be affected by NeighborModel.schedule()');   
    pf = 'pass';
    
% Establish a myTransactiveNode object
    mtn = myTransactiveNode;
    
% Establish a test market
    test_mkt = Market;

% Create and store one TimeInterval
    dt = datetime(2018,01,01,12,0,0); % Noon Jan 1, 2018
    at = dt;
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = dt;
    ti = TimeInterval(at,dur,mkt,mct,st);

    test_mkt.timeIntervals = ti(1);
    
% Create and store a marginal price in the active interval.    
    test_mkt.marginalPrices = IntervalValue(test_mkt,ti(1),test_mkt,...
        'MarginalPrice',0.01);
    
    disp('- configuring a test Neighbor and its NeighborModel');
% Create a test object that is a Neighbor
    test_obj1 = Neighbor;
    test_obj1.maximumPower = 100;

% Create the corresponding model that is a NeighborModel
    test_mdl1 = NeighborModel;
    test_mdl1.defaultPower = 10;
    
    test_obj1.model = test_mdl1;
    test_mdl1.object = test_obj1;
    
    mtn.neighbors = {test_obj1};
    
     disp('- configuring a test LocalAsset and its LocalAssetModel');
% Create a test object that is a Local Asset
    test_obj2 = LocalAsset;
    test_obj2.maximumPower = 100;

% Create the corresponding model that is a LocalAssetModel
    test_mdl2 = LocalAssetModel;
    test_mdl2.defaultPower = 10;
    
    test_obj2.model = test_mdl2;
    test_mdl2.object = test_obj2;
    
    mtn.localAssets = {test_obj2};   
 
    try
    test_mkt.schedule(mtn);
        disp('- method ran without errors');
    catch
        error('- method did not run due to errors');
    end
    
    if length(test_mdl1.scheduledPowers) ~= 1
        error(['- the wrong numbers of scheduled powers were stored ',...
            'for the Neighbor']);
    else
        disp(['- the right number of scheduled powers were stored ',...
            'for the Neighbor']);
    end
    
    if length(test_mdl2.scheduledPowers) ~= 1
        error(['- the wrong numbers of scheduled powers were stored ',...
            'for the LocalAsset']);        
    else
        disp(['- the right number of scheduled powers were stored ',...
            'for the LocalAsset']);        
    end

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up
    clear mtn test_mkt test_obj1 test_obj2 test_mdl1 test_mdl2
    
end                                                       % TEST SCHEDULE()

%% TEST_SUM_VERTICES()                                            COMPLETED
function test_sum_vertices()
    disp('Running Market.test_sum_vertices()');
    pf = 'pass';
    
%   Create a test myTransactiveNode object.
    test_node = myTransactiveNode;
    
%   Create a test Market object. 
    test_market = Market;
    
%   List the test market with the test_node.
    test_node.markets = test_market;
    
%   Create and store a time interval to work with.
    dt = datetime;
    at = dt;
    dur = Hours(1);
    mkt = test_market;
    mct = dt;
    st = dt;
    time_interval = TimeInterval(at,dur,mkt,mct,st);
    test_market.timeIntervals = time_interval;    
    
%   Create test LocalAsset and LocalAssetModel objects
    test_asset = LocalAsset;
    test_asset_model = LocalAssetModel;
    
%   Add the test_asset to the test node list.
    test_node.localAssets = {test_asset};
    
% Have the test asset and its model cross reference one another.    
    test_asset.model = test_asset_model;
    test_asset_model.object = test_asset;
    
%   Create and store an active Vertex or two for the test asset;
    test_vertex(1) = Vertex(0.2,0,-110);
    interval_value(1) = IntervalValue(test_node,time_interval,...
        test_market,'ActiveVertex',test_vertex(1));
    test_vertex(2) = Vertex(0.2,0,-90);
    interval_value(2) = IntervalValue(test_node,time_interval,...
        test_market,'ActiveVertex',test_vertex(2));    
    test_asset_model.activeVertices = interval_value(1:2);

%   Create test Neighbor and NeighborModel objects.
    test_neighbor = Neighbor;
    test_neighbor_model = NeighborModel;
    
%   Add the test neighbor to the test node list.
    test_node.neighbors = {test_neighbor};
   
%   Have the test neighbor and its model cross reference one another.    
    test_neighbor.model = test_neighbor_model;
    test_neighbor.model.object = test_neighbor;
    
%   Create and store an active Vertex or two for the test neighbor;
    test_vertex(3) = Vertex(0.1,0,0); 
    interval_value(3) = IntervalValue(test_node,time_interval,...
        test_market,'ActiveVertex',test_vertex(3));    
    test_vertex(4) = Vertex(0.3,0,200);
    interval_value(4) = IntervalValue(test_node,time_interval,...
        test_market,'ActiveVertex',test_vertex(4));      
    test_neighbor_model.activeVertices = interval_value(3:4);

%% Case 1
   disp('- Case 1: Basic case with interleaved vertices')

%   Run the test.
    try
        [ vertices ] = test_market.sum_vertices(test_node,time_interval);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method had errors when called and stopped');
    end
    
    if length(vertices) ~= 4
        pf = 'fail';
        warning('  - an unexpected number of vertices was returned');
    else
        disp('  - the expected number of vertices was returned');
    end
    
    powers = [vertices.power];
    
    if any(~ismember(single(powers),...
            single([-110.0000,-10.0000,10.0000,110.0000])))
        pf = 'fail';
        warning('  - the vertex powers were not as expected');
    else
        disp('  - the vertex powers were as expected');
    end
    
    marginal_prices = [vertices.marginalPrice];
    
    if any(~ismember(single(marginal_prices),...
            single([0.1000,0.2000,0.3000])))
        pf = 'fail';
        warning('  - the vertex powers were not as expected');
    else
        disp('  - the vertex marginal prices were as expected');
    end  
    
%% CASE 2: NEIGHBOR MODEL TO BE EXCLUDED
% This case is needed when a demand or supply curve must be created for a
% transactive Neighbor object. The active vertices of the target Neighbor
% must be excluded, leaving a residual supply or demand curve against which
% the Neighbor may plan.
    disp('- Case 2: Exclude test Neighbor model');
    
%   Run the test.
    try
        [ vertices ] = test_market.sum_vertices(test_node,...
            time_interval,test_neighbor_model);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors and stopped');
    end 
    
    if length(vertices) ~= 2
        pf = 'fail';
        warning('  - an unexpected number of vertices was returned');
    else
        disp('  - the expected number of vertices was returned');
    end   
    
    powers = [vertices.power];
    
    if any(~ismember(single(powers),...
            single([-110.0000,-90.0000])))
        pf = 'fail';
        warning('  - the vertex powers were not as expected');
    else
        disp('  - the vertex powers were as expected');
    end
    
    marginal_prices = [vertices.marginalPrice];
    
    if any(~ismember(single(marginal_prices),...
            single([0.2000])))
        pf = 'fail';
        warning('  - the vertex powers were not as expected');
    else
        disp('  - the vertex marginal prices were as expected');
    end   
    
%% CASE 3: CONSTANT SHOULD NOT CREATE NEW NET VERTEX
    disp(['- Case 3: Include a constant vertex. ',...
        'No net vertex should be added']);
    
%   Change the test asset to NOT have any flexibility. A constant should
%   not introduce a net vertex at a constant's marginal price. Marginal
%   price is NOT meaningful for an inelastic device.
    test_asset_model.activeVertices = interval_value(1); 
    
%   Run the test.
    try
        [ vertices ] = test_market.sum_vertices(test_node,...
            time_interval);
        disp('  - the method ran without errors');

    catch
        pf = 'fail';
        warning('  - the method encountered errors and stopped');
    end  
    
    if length(vertices) ~= 3
        pf = 'fail';
        warning('  - an unexpected number of vertices was returned');
    else
        disp('  - the expected number of vertices was returned');
    end     
    
    powers = [vertices.power];
    
    if any(~ismember(single(powers),...
            single([-110.0000, 90])))
        pf = 'fail';
        warning('  - the vertex powers were not as expected');
    else
        disp('  - the vertex powers were as expected');
    end
    
    marginal_prices = [vertices.marginalPrice];
    
    if any(~ismember(single(marginal_prices),single([0.1000,0.3000, Inf])))
        pf = 'fail';
        warning('  - the vertex powers were not as expected');
    else
        disp('  - the vertex marginal prices were as expected');
    end  
    
% CASE 4: More than two vertices at any marginal price
    disp('- Case 4: More than two vertices at same marginal price');

%   Move the two active vertices of the test asset to be at the same
%   marginal price as one of the neighbor active vertices.
    test_vertex(1) = Vertex(0.1,0,-110);
    interval_value(1) = IntervalValue(test_node,time_interval,...
        test_market,'ActiveVertex',test_vertex(1));
    test_vertex(2) = Vertex(0.1,0,-90);
    interval_value(2) = IntervalValue(test_node,time_interval,...
        test_market,'ActiveVertex',test_vertex(2));    
    test_asset_model.activeVertices = interval_value(1:2); 
    
%   Run the test.
    try
        [ vertices ] = test_market.sum_vertices(test_node,...
            time_interval);
        disp('  - the method ran without errors');
    catch
        pf = 'fail';
        warning('  - the method encountered errors and stopped');
    end  
    
    if length(vertices) ~= 3
        pf = 'fail';
        warning('  - an unexpected number of vertices was returned');
    else
        disp('  - the expected number of vertices was returned');
    end     
    
    powers = [vertices.power];
    
    if any(~ismember(single(powers),...
            single([-110.0000, -90.0000, 110.0000])))
        pf = 'fail';
        warning('  - the vertex powers were not as expected');
    else
        disp('  - the vertex powers were as expected');
    end
    
    marginal_prices = [vertices.marginalPrice];
    
    if any(~ismember(single(marginal_prices),single([0.1000,0.3000])))
        pf = 'fail';
        warning('  - the vertex powers were not as expected');
    else
        disp('  - the vertex marginal prices were as expected');
    end      
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
end                                                   % TEST_SUM_VERTICES()

%% TEST_UPDATE_COSTS()
function pf = test_update_costs()
    disp('Running Market.test_update_costs()');
    pf = 'test is not complete';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
end                                                   % TEST_UPDATE_COSTS()

%% TEST_UPDATE_SUPPLY_DEMAND()
function pf = test_update_supply_demand()
    disp('Running Market.test_update_supply_demand()');
    pf = 'test is not complete';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
end                                           % TEST_UPDATE_SUPPLY_DEMAND()

%% TEST_VIEW_NET_CURVE()                                          COMPLETED
function pf = test_view_net_curve()
    disp('Running Market.test_view_net_curve()');
    pf = 'pass';
    
% Establish a test market
    test_mkt = Market;

% Create and store one TimeInterval
    dt = datetime(2018,01,01,12,0,0);
    at = dt;
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = dt;
    ti(1) = TimeInterval(at,dur,mkt,mct,st);

    test_mkt.timeIntervals = ti;

%% Test using a Market object
    disp('- using a Market object');
    
%   Create and store three active vertices
    v(1) = Vertex(0.01,0,-1);
    v(2) = Vertex(0.02,0,1);
    v(3) = Vertex(0.03,0,1);
    iv(1) = IntervalValue(test_mkt,ti(1),test_mkt,'ActiveVertex',v(3));
    iv(2) = IntervalValue(test_mkt,ti(1),test_mkt,'ActiveVertex',v(1));
    iv(3) = IntervalValue(test_mkt,ti(1),test_mkt,'ActiveVertex',v(2));
    test_mkt.activeVertices = iv;
    
    try
        test_mkt.view_net_curve(1);
        disp('  - function ran without errors');
    catch
        error('  - function encountered errors and stopped');        
    end
    
%   Check for a figure
    fig = gca;
    title = get(fig,'Title');
    title = title.Text.String;

    if title ~= 'Production Vertices (180101-1200)'
        error('  - the figure title is unexpected');
    else
        disp('  - the figure title is as expected');
    end 

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up
    clear test_mkt; cla; clf; 
    
end                                                 % TEST_VIEW_NET_CURVE()

%% TEST_VIEW_MARGINAL_PRICES()                                    COMPLETED
function pf = test_view_marginal_prices()
    disp('Running Market.test_view_marginal_prices()');
    pf = 'pass';

% Establish a test market
    test_mkt = Market;

% Create and store three TimeIntervals
    dt = datetime;
    at = dt;
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    
    ti = TimeInterval.empty;

    st = dt;
    ti(1) = TimeInterval(at,dur,mkt,mct,st);

    st = st + dur;
    ti(2) = TimeInterval(at,dur,mkt,mct,st);

    st = st + dur;
    ti(3) = TimeInterval(at,dur,mkt,mct,st);

    test_mkt.timeIntervals = ti;

%% Test using a Market object
    disp('- using a Market object');
    
    iv = IntervalValue.empty;
%   Create and store three marginal price values
    iv(1) = IntervalValue(test_mkt,ti(3),test_mkt,'MarginalPrice',3);
    iv(2) = IntervalValue(test_mkt,ti(1),test_mkt,'MarginalPrice',1);
    iv(3) = IntervalValue(test_mkt,ti(2),test_mkt,'MarginalPrice',2);
    test_mkt.marginalPrices = iv;
    
    try
        test_mkt.view_marginal_prices();
        disp('  - function ran without errors');
    catch
        error('  - function encountered errors and stopped');        
    end
    
%   Check for a figure
    fig = gca;
    title = get(fig,'Title');
    title = title.Text.String;

    if title ~= 'Marginal Prices in Active Time Intervals'
        error('  - the figure title is unexpected');
    else
        disp('  - the figure title is as expected');
    end 

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up
    clear test_mkt; cla; clf;   

end                                           % TEST_VIEW_MARGINAL_PRICES()

end                                                 % Static Market Methods
    
end                                                        %Classdef Market

