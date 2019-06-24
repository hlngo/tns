classdef BulkSupplier_dc < NeighborModel
% BulkSupplier NeighborModel subclass - Represents non-transactive
% neighbor, including demand charges
%
% Created to represent large, non-transactive electricity supplier BPA in
% its relationship to a municipality. 
%   - Introduces new properties to keep track of peak demand.
%   - Calls on a new function to determine hour type (HLH or LLH).
%   - Mines tables to determine monthly electricity and demand rates in HLH
%     and LLH hour types.
    
%% BulkSupplier_dc properties
    properties
    end                                        % BuldSupplier_dc properties 
    
%% BulkSupplier_dc methods    
    methods

%% FUNCTION BULKSUPPLIER_DC()
function obj = BulkSupplier_dc()
% A constructor method that simply sets transactive = false.    

    obj.transactive = false;
    
end                                            % function BulkSupplier_dc()
 
%% FUNCTION UPDATE_DC_THRESHOLD()
function update_dc_threshold(obj,mkt)
% UPDATE_DC_THRESHOLD() - keep track of the month's demand-charge threshold
% obj - BulkSupplier_dc object, which is a NeighborModel
% mkt - Market object
%
% Pseudocode:
% 1. This method should be called prior to using the demand threshold. In
%    reality, the threshold will change only during peak periods.
% 2a. (preferred) Read a meter (see MeterPoint) that keeps track of an
%     averaged power. For example, a determinant may be based on the
%     average demand in a half hour period, so the MeterPoint would ideally
%     track that average.
% 2b. (if metering unavailable) Update the demand threshold based on the
%     average power in the current time interval.
        
%   Find the MeterPoint object that is configured to measure average demand
%   for this NeighborModel. The determination is based on the meter's
%   MeasurementType.
    mtr = findobj(obj.meterPoints,'MeasturementType',...
        MeasurementType('average_demand_kW'));        % a MeterPoint object
        
    if isempty(mtr)
        
%       No appropriate MeterPoint object was found. The demand threshold
%       must be inferred.

%       Gather the active time intervals ti and find the current (soonest)
%       one.
        ti = [mkt.timeIntervals];
        [~,ind] = sort([ti.startTime]);
        ti = ti(ind);       % ordered time intervals from soonest to latest
        
%       Find current demand d that corresponds to the nearest time
%       interval.
        d = findobj(obj.scheduledPowers,'timeInterval',ti(1));   % [avg.kW]
       
%       Update the inferred demand.
        obj.demandThreshold = max([0,obj.demandThreshold,d(1).value]);
                                                                 % [avg.kW]

    else 
        
%       An appropriate MeterPoint object was found. The demand threshold
%       may be updated from the MeterPoint object.

%       Update the demand threshold.
        obj.demandThreshold = max([0,obj.demandThreshold,...
            mtr(1).currentMeasurement]);                         % [avg.kW]
        
    end                                                   % if isempty(mtr)
    
    if length(mtr) > 1

%       More than one appropriate MeterPoint object was found. This is a
%       problem. Warn, but continue.
        warning(['The BulkSupplier_dc object is associated with too ',...
            'many average-damand meters']);

    end                                                % if length(mtr) > 1
    
%   The demand threshold should be reset in a new month. First find the
%   current month number mon.
    dt = datetime; mon = month(dt);
    
    if mon ~= obj.demandMonth
        
%       This must be the start of a new month. The demand threshold must be
%       reset. For now, "resetting" means using a fraction (e.g., 80%) of
%       the final demand threshold in the prior month.
        obj.demandThreshold = 0.8 * obj.demandThreshold;
        obj.demandMonth = mon;
        
    end                                         % if mon ~= obj.demandMonth

end                                        % FUNCTION UPDATE_DC_THRESHOLD()

%% FUNCTION UPDATE_VERTICES()
function update_vertices(obj,mkt)
% Creates active vertices for a non-transactive neighbor, including demand
% charges.
%
% INPUTS:
% obj - Bulk supplier non-transactive neighbor model object
% mkt - Market object
%
% OUTPUTS:
%   - Updates obj.activeVertices for active time intervals.
    
%   Gather active time intervals
    time_intervals = mkt.timeIntervals;              % TimeInterval objects
    
%   Get the maximum power maxp for this neighbor.
    maximum_power = obj.object.maximumPower;                     % [avg.kW]
    
%   The maximum power property is meaningful for both imported (p>0) and
%   exported (p<0) electricity, but this formulation is intended for
%   importation (power>0) from an electricity supplier. Warn the user and
%   return if the maximum power is negative.
    if maximum_power < 0
        warning(['Maximum power must be positive in ', ...
            '"BulkSupplier_dc.m".']);
        warning(['Returning without creating active vertices for ', ...
            obj.name]);
        return;
    end                                              % if maximum_power < 0
    
%   Get the minimum power for this neighbor.
    minimum_power = obj.object.minimumPower;                     % [avg.kW]
    
%   Only importation is supported from this non-transactive neighbor.
    if minimum_power < 0
        warning(['Minimum power must be positive in ', ...
            '"BulkSupplier_dc.m".']);
        warning(['Returning without creating active vertices for ', ...
            obj.name]);        
        return;
    end                                              % if minimum_power < 0

%   Cost coefficient a0. This is unavailable from a supply curve, so it
%   must be determined directly from the first, constant cost parameter.
%   It does NOT affect marginal pricing.
    a0 = obj.costParameters(1);                                     % [$/h]

%   Full-power loss at is defined by the loss factor property and the
%   maximum power.
    full_power_loss = maximum_power * obj.object.lossFactor;     % [avg.kW] 

%   Minimum-power loss at Vertex 1 is a fraction of the full-power loss.
%   (Power losses are modeled proportional to the square of power
%   transfer.)
    minimum_power_loss = (minimum_power/maximum_power)^2 * full_power_loss; 
                                                                  %[avg.kW]
    
%   Index through active time intervals
    for i = 1:length(time_intervals)
        
%       Find and delete active vertices in the indexed time interval.
%       These vertices shall be recreated.
        indices = ~ismember([obj.activeVertices.timeInterval],...
            time_intervals(i));                         % array of logicals
        obj.activeVertices = obj.activeVertices(indices);
        
%       Find the month number for the indexed time interval start time.
%       The month is needed for rate lookup tables.
        month_number = month(time_intervals(i).startTime);  

        if isHLH(time_intervals(i).startTime) 
            
%           The indexed time interval is an HLH hour. The electricity rate
%           is a little higher during HLH hours, and demand-charges may
%           apply.
%           Look up the BPA energy rate for month_number. The second
%           parameter is HLH = 1 (i.e., column 1 of the table).
            energy_rate = bpa_rate.energy(month_number,1);  
                                                   %HLH energy rate [$/kWh]
            
%           Four active vertices are initialized:
%           #1 at minimum power
%           #2 at the demand-charge power threshold
%           #3 at the new demand rate and power threshold
%           #4 at maximum power and demand rate
            vertices = [Vertex(0,0,0),Vertex(0,0,0),Vertex(0,0,0),...
                Vertex(0,0,0)]; 

%% Evaluate the first of the four vertices
%           Segment 1: First-order parameter a1. 
%           This could be stated directly from cost parameters, but this
%           model allows for dynamic rates, accounts for losses, and models
%           demand-charges, which would require defining multiple
%           cost-parameter models. The first-order parameter is the
%           electricity rate. In this model, the rate is meaningful at a
%           neighbor node location at zero power transfer.
            a1 = energy_rate;                                     % [$/kWh]
  
%           Vertex 1: Full available power transfer at Vertex 1 is thus the
%           physical transfer limit, minus losses.
            vertices(1).power = (minimum_power-minimum_power_loss);

%           Vertex 1: Marginal price of Vertex 1 is augmented by the value
%           of energy from the neighbor that is lost. (This model assigns
%           the cost of losses to the recipient (importer) of electricity.)
            vertices(1).marginalPrice = a1 ...
                * (1 + obj.object.lossFactor*minimum_power/maximum_power);         
                                                                  % [$/kWh]
            
%% Evalauate the second of four vertices            
%           Vertex 2: Available power at Vertex 2 is determined by the
%           current peak demand charge threshold pdt and possibly scheduled
%           powers prior to the indexed time interval. The demand threshold
%           in the indexed time interval is at least equal to the
%           parameter. NOTE this process will work only if the demand
%           threshold is is updated based on actual, accurate measurements.
            peak_demand_threshold = obj.demandThreshold;             % [kW]
            
%           Also consider, however, scheduled powers prior to the indexed
%           interval that might have already set a new demand threshold.
%           For simplicity, presume that new demand thresholds would occur
%           only during HLH hour types. More complex code will be needed
%           if only HLH hours must be considered. NOTE this process will
%           work only if the load forcasts are meaningful and accurate.
            
%           Gather scheduled powers sp
            scheduled_powers = obj.scheduledPowers;

            if ~isempty(scheduled_powers)
                
%               Powers have been scheduled, order the scheduled powers by
%               their start time 
                interval_start_times = [obj.scheduledPowers.timeInterval];   
                                                    % IntervalValue objects
                interval_start_times = [interval_start_times.startTime]; 
                                                                % datetimes
                [~,index] = sort(interval_start_times);     % logical array
                ordered_scheduled_powers = obj.scheduledPowers(index); 
                              %IntervalValue objects ordered by start times
                              
                ordered_scheduled_powers = ordered_scheduled_powers(1:i);
                                     
%               The peak demand determinant is the greater of the monthly
%               peak threshold or the prior scheduled powers.
                peak_demand_threshold = max([peak_demand_threshold,...
                    ordered_scheduled_powers.value]);                % [kW]
                
            end                             % if ~isempty(scheduled_powers)
            
%           Vertex 2: The power at which demand charges will begin accruing
%           and therefore marks the start of Vertex 2. It is not affected
%           by losses because it is based on local metering.
            vertices(2).power = peak_demand_threshold;           % [avg.kW]
            
%           Vertex 2: Marginal price of Vertex 2 is augmented by the value
%           of energy from the neighbor that is lost.
            vertices(2).marginalPrice = a1 ...
                * (1 + obj.object.lossFactor ...
                * vertices(2).power/maximum_power);               % [$/kWh]
            
%% Evaluate the third of four vertices
%           Look up the demand rate dr for the month_number. The second
%           parameter is HLH = 1 (i.e., the first column of the table).
            demand_rate = bpa_rate.demand(month_number,1);
                                                         % [$/kW (per kWh)]
            
%           Vertex 3: The power of Vertex 3 is the same as that of Vertex 2            
            vertices(3).power = peak_demand_threshold;           % [avg.kW]
            
%           Vertex 3: The marginal price at Vertex 3 is shifted strongly by
%           the demand response rate. The logic here is that cost is
%           determined by rate * (power-threshold). Therefore, the
%           effective marginal rate is augmented by the demand rate itself.
%           NOTE: Some hand-waving is always needed to compare demand and
%           energy rates. This approach assigns a meaningful production
%           cost, but it is not correct to say it describes an energy
%           price. The cost is assigned to the entire hour. Shorter time
%           intervals should not be further incremented. Evenso, a huge
%           discontinuity appears in the marginal price.
            vertices(3).marginalPrice = vertices(3).marginalPrice ...
                + demand_rate;                                    % [$/kWh]
                     
%% Evaluate the fourth of four vertices            
%           Vertex 4: The power at Vertex 4 is the maximum power, minus
%           losses
            vertices(4).power = maximum_power - full_power_loss; % [avg.kW]
            
%           The marginal price at Vertex 4 is affected by both losses and
%           demand charges.

%           Marginal price at Vertex 3 from loss component
            vertices(4).marginalPrice = a1 * (1 + obj.object.lossFactor); 
                                                                  % [$/kWh]
            
%           Augment marginal price at Vertex 4 with demand-charge impact
            vertices(4).marginalPrice = vertices(4).marginalPrice ...
                + demand_rate;                          % [$/kW (per hour)]
 
%% Assign production costs for the four vertices
%           Segment 1: The second-order cost coefficient a2 on the first
%           line segment is determined from the change in marginal price
%           divided by change in power.
            a2 = (vertices(2).marginalPrice - vertices(1).marginalPrice);
                                                                  % [$/kWh]
            a2 = a2 / (vertices(2).power - vertices(1).power);  % [$/kW^2h]
            
%           Vertex 1: The cost at Vertex 1 can be inferred by integrating
%           from p=0 to Vertex 1.
            vertices(1).cost = a0 + a1 * vertices(1).power ...
                + 0.5 * a2 * (vertices(1).power)^2; % production cost [$/h]
            
%           Vertex 2: The cost at Vertex 2 is on the same trajectory
            vertices(2).cost = a0 + a1 * vertices(2).power ...
                + 0.5 * a2 * (vertices(2).power)^2; % production cost [$/h]
            
%           Vertex 3: Both the power and production cost should be the same
%           at Vertex 3 as for Vertex 2.
            vertices(3).cost = vertices(2).cost;    % production cost [$/h]
                           
%           Vertex 4: The cost on the third line segment has a new
%           trajectory that begins with the cost at Vertex 3 (an
%           integration constant).
            vertices(4).cost = vertices(3).cost;  
                                            % partial production cost [%/h]
            
%           Segment 3: The new first-order term for the third line segment
%           is the marginal price at Vertex 3. This applies only to power
%           imports that exceed Vertex 3.
            a1 = vertices(3).marginalPrice; 
                                          % first-order coefficient [$/kWh]
            
%           Vertex 4: Add the first-order term to the Vertex-4 cost
            vertices(4).cost = vertices(4).cost ...
                + a1 * (vertices(4).power - vertices(3).power);  
                                            % partial production cost [$/h]

%           Segment 3: NOTE: The second-order coeffiecient a2 on the second
%           line segment is unchanged from the first segment

%           Vertex 4: Add the second-order term to the Vertex-4 cost.
            vertices(4).cost = vertices(4).cost ...
                + 0.5 * a2 * (vertices(4).power - vertices(3).power)^2;
                                                    % production cost [$/h]
            
%           Convert the costs to raw dollars
%           NOTE: This usage of Matlab hours() toggles a duration back
%           into a numerical representation, which is correct here.
            interval_duration = time_intervals(i).duration;
            if isduration(interval_duration)
%               NOTE: Matlab hours() toggles back to numeric and is fine
%               here
                interval_duration = hours(interval_duration);  
            end
            vertices(1).cost = vertices(1).cost * interval_duration;  % [$]                            % [$]
            vertices(2).cost = vertices(2).cost * interval_duration;  % [$]                              % [$]
            vertices(3).cost = vertices(3).cost * interval_duration;  % [$]                              % [$]
            vertices(4).cost = vertices(4).cost * interval_duration;  % [$]                              % [$]            

%           Create interval values for the active vertices
            interval_values(1) = IntervalValue(obj,time_intervals(i),...
                mkt,'ActiveVertex',vertices(1));
            interval_values(2) = IntervalValue(obj,time_intervals(i),...
                mkt,'ActiveVertex',vertices(2));
            interval_values(3) = IntervalValue(obj,time_intervals(i),...
                mkt,'ActiveVertex',vertices(3));
            interval_values(4) = IntervalValue(obj,time_intervals(i),...
                mkt,'ActiveVertex',vertices(4));
            
%           Append the active vertices to the list of active vertices
            %in the indexed time interval
            obj.activeVertices = [obj.activeVertices,interval_values];
 
        else                           %indexed time interval is a LLH hour
            
%% LLH hours          
%           The indexed time interval is a LLH hour. The electricity rate
%           is a little lower, and demand charges are not applicable.
%             
%           Look up the BPA energy rate for month m. The second parameter
%           is LLH = 2 (i.e., column 2 of the table).
            energy_rate = bpa_rate.energy(month_number,2);
            
%           Two active vertices are created
%             #1 at minimum power
%             #2 at maximum power
            vertices = [Vertex(0,0,0),Vertex(0,0,0)];             
   
%% Evaluate the first of two vertices            
%           First-order parameter a1.
            a1 = energy_rate;                                     % [$/kWh]
  
%           Vertex 1: Full available power transfer at Vertex 1 is thus the
%           physical transfer limit, minus losses.
            vertices(1).power = (minimum_power-minimum_power_loss); 
                                                                 % [avg.kW]

%           Vertex 1: Marginal price of Vertex 1 is augmented by the value
%           of energy from the neighbor that is lost. (This model assigns
%           the cost of losses to the recipient (importer) of electricity.)
            vertices(1).marginalPrice = a1 ...
                * (1 + obj.object.lossFactor*minimum_power/maximum_power);         
                                                                  % [$/kWh]
            
%% Evaluate the second of two vertices                          
%           Vertex 2: The power at Vertex 2 is the maximum power, minus
%           losses
            vertices(2).power = maximum_power - full_power_loss; % [avg.kW]                          %[avg.kW]
            
%           Vertex 2: The marginal price at Vertex 2 is affected only by
%           losses. Demand charges do not apply during LLH hours.
% 
%           Vertex 2: Marginal price at Vertex 2 from loss component
            vertices(2).marginalPrice = a1 * (1 ...
                + obj.object.lossFactor);                         % [$/kWh]
 
%% Assign production costs for the two vertices
%           The second-order cost coefficient a2 on the lone line segment
%           is determined from the change in marginal price divided by
%           change in power.
            a2 = (vertices(2).marginalPrice - vertices(1).marginalPrice);
                                                                  % [$/kWh]
            a2 = a2 / (vertices(2).power - vertices(1).power);  % [$/kW^2h]
            
%           The cost at Vertex 1 can be inferred by integrating from
%           p=0 to Vertex 1.
            vertices(1).cost = a0 + a1 * vertices(1).power ...
                + 0.5 * a2 * (vertices(1).power)^2; % production cost [$/h]
            
%           The cost at Vertex 2 is on the same trajectory
            vertices(2).cost = a0 + a1 * vertices(2).power ...
                + 0.5 * a2 * (vertices(2).power)^2; % production cost [$/h]

%           Convert the costs to raw dollars
            interval_duration = time_intervals(i).duration;
            if isduration(interval_duration)
%               Matlab function hours() toggles a duration back to numeric.
                interval_duration = hours(interval_duration); 
            end
            vertices(1).cost = vertices(1).cost * interval_duration;  % [$]                           % [$]
            vertices(2).cost = vertices(2).cost * interval_duration;  % [$]                             % [$]
            
%           Create interval values for the active vertices
            interval_values(1) = IntervalValue(obj,time_intervals(i),...
                mkt,'ActiveVertex',vertices(1));
            interval_values(2) = IntervalValue(obj,time_intervals(i),...
                mkt,'ActiveVertex',vertices(2));
            
%           Append the active vertices to the list of active vertices
%           in the indexed time interval
            obj.activeVertices = [obj.activeVertices,interval_values];            
  
        end                         % if isHLH(time_intervals(i).startTime)
    
    end                                  % for i = 1:length(time_intervals)

end                                            % FUNCTION UPDATE_VERTICES()
       
    end                                           % BulkSupplier_dc Methods
    
%% Static BulkSupplier_dc Methods
methods (Static)
    
%% TEST_ALL()                                                     COMPLETED
function test_all()
    disp('Running BulkSupplier_dc.test_all()');
    BulkSupplier_dc.test_update_dc_threshold();
    BulkSupplier_dc.test_update_vertices();
end                                                            % TEST_ALL()

%% TEST_UPDATE_DC_THRESHOLD()                                     COMPLETED
function test_update_dc_threshold()
    disp('Running BulkSupplier_dc.test_update_dc_threshold()');
    pf = 'pass';

%% Basic configuration for tests:
%   Create a test object and initialize demand-realted properties
    test_obj = BulkSupplier_dc;
        test_obj.demandMonth = month(datetime);
        test_obj.demandThreshold = 1000;
        
%   Create a test market   
    test_mkt = Market;
    
%   Create and store two time intervals
    dt = datetime;
    at = dt;
    dur = Hours(1);
    mkt = test_mkt;
    mct = dt;
    st = dt;
    ti(1) = TimeInterval(at,dur,mkt,mct,st);
    
    st = st + dur;
    ti(2) = TimeInterval(at,dur,mkt,mct,st);
    test_mkt.timeIntervals = ti;
    

    
%%  Test case when there is no MeterPoint object  
    test_obj.demandThreshold = 1000;
    test_obj.demandMonth = month(datetime);
    test_obj.meterPoints = MeterPoint.empty;
    
%   Create and store a couple scheduled powers
    iv(1) = IntervalValue(test_obj,ti(1),test_mkt,'SheduledPower',900);
    iv(2) = IntervalValue(test_obj,ti(2),test_mkt,'SheduledPower',900);
    test_obj.scheduledPowers = iv;
    
    try
        test_obj.update_dc_threshold(test_mkt);
        disp('- the method ran without errors');
    catch
        pf = 'fail';
        warning('- the method encountered errors when called');
    end
    
    if test_obj.demandThreshold ~= 1000
        pf = 'fail';
        warning('- the method inferred the wrong demand threshold value');
    else
        disp(['- the method properly kept the old demand threshold ',...
            'value with no meter']);        
    end
    
    iv(1) = IntervalValue(test_obj,ti(1),test_mkt,'SheduledPower',1100);
    iv(2) = IntervalValue(test_obj,ti(2),test_mkt,'SheduledPower',900);
    test_obj.scheduledPowers = iv; 
    
    try
        test_obj.update_dc_threshold(test_mkt);
        disp('- the method ran without errors when there is no meter');
    catch
        pf = 'fail';
        warning('- the method encountered errors when there is no meter');
    end    

    if test_obj.demandThreshold ~= 1100
        pf = 'fail';
        warning(['- the method did not update the inferred demand ',...
            'threshold value']);
    else
        disp(['- the method properly updated the demand threshold ',...
            'value with no meter']);        
    end    
    
%% Test with an appropriate MeterPoint meter
%   Create and store a MeterPoint test object
    test_mtr = MeterPoint;
        test_mtr.measurementType = 'average_demand_kW';
        test_mtr.currentMeasurement = 900;
    test_obj.meterPoints = test_mtr;

%   Reconfigure the test object for this test:
    iv(1) = IntervalValue(test_obj,ti(1),test_mkt,'SheduledPower',900);
    iv(2) = IntervalValue(test_obj,ti(2),test_mkt,'SheduledPower',900);
    test_obj.scheduledPowers = iv;
    
    test_obj.demandThreshold = 1000;
    test_obj.demandMonth = month(datetime);
    
%   Run the test. Confirm it runs.
    try
        test_obj.update_dc_threshold(test_mkt);
        disp('- the method ran without errors when there is a meter');
    catch
        pf = 'fail';
        warning('- the method encountered errors when there is a meter');
    end
 
%   Check that the old threshold is correctly retained.
    if test_obj.demandThreshold ~= 1000
        pf = 'fail';
        warning(['- the method failed to keep the correct demand ',...
            'threshold value when there is a meter']);
    else
        disp(['- the method properly kept the old demand threshold ',...
            'value when there is a meter']);        
    end    

%   Reconfigure the test object with a lower current threshold
    iv(1) = IntervalValue(test_obj,ti(1),test_mkt,'SheduledPower',900);
    iv(2) = IntervalValue(test_obj,ti(2),test_mkt,'SheduledPower',900);
    test_obj.scheduledPowers = iv;
    test_obj.demandThreshold = 800;

%   Run the test.
    test_obj.update_dc_threshold(test_mkt);

%   Check that a new, higher demand threshold was set.
    if test_obj.demandThreshold ~= 900
        pf = 'fail';
        warning(['- the method failed to update the demand ',...
            'threshold value when there is a meter']);
    else
        disp(['- the method properly updated the demand threshold ',...
            'value when there is a meter']);        
    end   

%% Test rollover to new month
%   Configure the test object
    test_obj.demandMonth = month(datetime - days(31));        % prior month
    test_obj.demandThreshold = 1000;
    test_obj.scheduledPowers(1).value = 900;
    test_obj.scheduledPowers(2).value = 900; 
    test_obj.meterPoints = MeterPoint.empty;
    
%   Run the test
    test_obj.update_dc_threshold(test_mkt);    

%   See if the demand threshold was reset at the new month.
    if test_obj.demandThreshold ~= 0.8 * 1000
        pf = 'fail';
        warning(['- the method did not reduce the threshold ',...
            'properly in a new month']);
    else
        disp('- the method reduced the threshold properly in a new month');
    end  
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up the variable space
    clear test_mtr test_mkt test_obj iv ti
        
end                                            % TEST_UPDATE_DC_THRESHOLD()

%% TEST_UPDATE_VERTICES()
function test_update_vertices()
    disp('Running BulkSupplier_dc.test_update_vertices()');
    pf = 'test is not completed yet';
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up
    clear
    
end                                                % TEST_UPDATE_VERTICES()

end                                        % Static BulkSupplier_dc Methods
    
end

