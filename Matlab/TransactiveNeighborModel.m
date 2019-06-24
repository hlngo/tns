classdef TransactiveNeighborModel < handle
    %TransactiveNeighborModel Base Class
    
    %I'M EXPERIMENTING WITH THE DISTINCTION BETWEEN TRANSACTIVE AND
    %NONTRANSACTIVE NEIGHBOR MODELS. THIS CLASS WILL PROBABLY BE ELIMINATED
    %UPON INTRODUCTION OF A NEIBHBORMODEL CLASS THAT COMBINES THE TWO.
    
    %   The TransactiveNeighborModel manages the interface with a
    %   TransactiveNeighbor and represents it for the computational agent.
    %   There is a one-to-one correspondence between a TransactiveNeighbor
    %   object and its TransactiveNeighborModel object.
    
    %   VERION  DATE    AUTHOR          CHANGE
    %   0.1     2017-11 DJ Hammerstrom  Original draft
    
    properties
        activeVertices %IntervalValues; MeasurementType = 'ProdVertex'
        convergenceThreshold
        defaultVertices = [Vertex(0.0,0.0,1),Vertex(0.0,0.0,1)]
        effectiveImpedance
        meterPoints
        name
        numVertices = 1 %number of ProdVertices needed
        object %cross reference to corresponding Neighbor object
        transactive = TRUE
    end
    
    methods
        
%% FUNCTION CONSTRAIN ******************************************************
%   Assign vertices consistent with the constrained scheduling of this
%   TransactiveNeighbor. Default vertices are provided from the
%   TransactiveNeighborModel base class and suffice for an unconstrained 
%   import. If scheduling is dynamic (e.g., demand charges, ramp rates,
%   etc.), then alternative scheduling functions must be invoked to handle
%   those changes.
%       numVertices - number of production vertices needed by the 
%                     TransactiveNeighborModel object.
%       obj - the TransactiveNeighborModel object.
%       vt - array of constrained production vertices (See struct Vertex).
%       ti - the time interval to be constrained (see TimeInterval class).
% *************************************************************************
        function vt = constrain(obj,ti)
            v = [1:obj.numVertices];
            [vt] = [obj.defaultVertices(v)]; %default assignment
        end % function constrain()
        
%% FUNCTION COST() 
%Calculate production (consumption) cost for given object at the given
%power level.
%   INPUTS:
%       obj - class object for which the production costs are to be
%             calculated
%       p - power production (consumption) for which production
%           (consumption) costs are to be calculated [kW]. By convention,
%           imported and generated power is positive; exported or consumed
%           power is negative.
%   OUTPUTS:
%       pc - calculated production (consumption) cost [$/h]
%   LOCAL:
%       a - array of production cost coefficients that must be ordered [a0
%       a1 a2], such that cost = a0 + a1*p + a2*p^2 [$/h].
% *************************************************************************
    function [ c ] = cost( obj, p )
        
        c = 0.0;
        
        [a] = findobj(obj.activeVertices,'timeInterval',ti);
                
        switch length([a])
            
            case 0
                
            case 1

                    c = a(1).price * a(1).power; %[$/h]
       
            case 2
                
                c = a(1).price * a(1).power; %[$/h]
                
                if p > a(1).power && p < a(2).power;
                    m = (a(2).price-a(1).price)/(a(2).power-a(2).power);
                    c = c + (p-a(1).power)^2 * m;
                    
                elseif p = a(1).power && a(1).power == a(2).power
                    c = c + (p-a(1).power) * a(1).price;
                    
                elseif p >= a(2).power
                    m = (a(2).price-a(1).price)/(a(2).power-a(2).power);
                    c = c + (a(2).power-a(1).power)^2 * m;
                    
                end %if
                
        end %switch

    end %function cost() 
        
%%        
        function check_for_convergence()
            fprintf('made it to TransactiveNeighborModel.check_for_convergence()');
        end

%%        
        function create_transactive_signal(target, market)
            fprintf('made it to TransactiveNeighborModel.create_transactive_signal()');
            %1. Gather the center power values for each active interval for
            %   this TN
            %2. pair interval incremental prices with TN power
            %3. If power is positive (import from TN) and TN is NOT the
            %   marginal resource, then allocate the interval's marginal 
            %   flexibility to TN
            %4. If the TN is a "friend," also supply the coefficient that
            %   conveys impacts of blended pricing, which distributes any
            %   supply excess in the interval
            %5. Format the signal.
            %6. Store the signal
        end; %This belongs with TransactiveSignalClass
        
%%        
        function receive_transactive_signal(transactive_signal)
            fprintf('made it to TransactiveNeighborModel.receive_transactive_signal()');
            %1. Accept the signal
            %2. Save the signal
            %3. Extract the interval information
            %3. Extract the incremental price for each interval
            %4. If provided, extract the additional price coefficient that
            %   is made available to "friends" that are eligible to use the
            %   blended price
            %5. Extract the power for each interval. Anticipate in the
            %   signal future usage of an uncertainty range.
            %6. If provided, extract the marginal flexibility in each
            %   interval
            %7. Interpret the price, power, and flexibility in each
            %   interval as one or more production vertices.
            %   a. If an import, a single production vertex is created. Demand
            %      must be supplied. There is really no flexibility.
            %   b. If an export and myTransactiveNode is the marginal
            %      resource to this neighbor, a single vertex is created.
            %      There is virtually no flexibility available from this
            %      neighbor that is relying on myTransactiveNode as its
            %      marginal resource.
            %   c. If an export, but myTransactiveNode is NOT the
            %      neighbor's marginal resource, as indicated by the
            %      offering of such flexibility, the flexibility should be
            %      offered into the local resource selection by providing
            %      vertices around the offered price and power quantities.
            %8. Populate the production cost coefficients so that the
            %   correct price will be calculated--either incremental or 
            %   blended.
            %9. Document that the information has been received and 
            %   updated.
        end

%%        
        function send_transactive_signal(transactive_signal)
            fprintf('made it to TransactiveNeighborModel.send_transactive_signal()');
            %This should be simply the mechanics of communicating the
            %signal.
        end
                
    end %methods
    
end %Classdef TransactiveNeigborModel