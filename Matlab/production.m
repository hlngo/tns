function [ p1 ] = production( obj, price, ti )
% FUNCTION PRODUCTION()
%   Find economic power production for a marginal price and time interval
%   using an object model's demand or supply curve. This is performed as a
%   linear interpolation of a discrete set of price-ordered vertices (see
%   struct Vertex).
%
%   obj - Asset or neighbor model for which the power production is to be
%       calculated. This model has a set of "active vertices" that define
%       its flexibility via a demand or supply curve.
%   price - marginal price [$/kWh]
%   ti - time interval (see class TimeInterval)
%   [p1] - economic power production in the given time interval   and at 
%          the given price (positive for generation) [avg.kW].
%
%   VERSIONING
%   0.2 2017-11 Hammerstrom
%       - Corrected for modifications to Vertex() properties. There are now
%         two prices. This one should reference property marginalPrice.
%   0.1 2017-11 Hammerstrom
%       - Original function draft
% *************************************************************************
            
%   Find the active production vertices for this time interval (see class
%   IntervalValue).
    pv = findobj(obj.activeVertices,'timeInterval',ti);     %IntervalValues
    
%   Extract the vertices (see struct Vertex) from the interval values (see
%   IntervalValue class).
    pvv = [pv.value];                                             %vertices

%   Ensure that the production vertices are ordered by increasing price.
%   Vertices having same price are ordered by power.
    pvv = order_vertices(pvv);                                    %vertices

%   Number len of vertices in the list.
    len = length(pvv);

    switch len

        case 0    %No active vertices were found in the given time interval
            
        error(['No active vertices were found for ',...
                obj.name,' in time interval ',ti.name,'.']);

        case 1   %One active vertices were found in the given time interval
            
%           Presume that using a single production vertex is shorthand for
%           constant, inelastic production.
            p1 = pvv(1).power;                                   % [avg.kW]

        otherwise %Multiple active vertices were found

            if price < pvv(1).marginalPrice 
                
%               Special case where marginal price is before first vertex.
%               The power is at its minimum.
                p1 = pvv(1).power;                                   % [kW]
                return;

            elseif price >= pvv(len).marginalPrice
                
%               Special case where marginal price is after the last
%               vertex. The power is at its maximum.
                p1 = pvv(len).power;                                 % [kW]
                return;

            else         %The marginal price lies among the active vertices
                
%               Index through the active vertices pvv in the given time
%               interval ti
                for i = 1:len-1

                    if price >= pvv(i).marginalPrice ...
                        && price < pvv(i+1).marginalPrice
                        
%                       The marginal price falls between two vertices that
%                       are sloping upward to the right. Interpolate
%                       between the vertices to find the power production.
                        p1 = pvv(i).power ...
                            + (price - pvv(i).marginalPrice) ...
                            * (pvv(i+1).power - pvv(i).power) ...
                            / (pvv(i+1).marginalPrice ...
                            - pvv(i).marginalPrice);             % [avg.kW]
                        return;

                   elseif price == pvv(i).marginalPrice ...
                        && pvv(i).marginalPrice == pvv(i+1).marginalPrice
                        
%                       The marginal price is the same as for two vertices
%                       that lie vertically at the same marginal price.
%                       Assign the power of the vertex having greater
%                       power.
                        p1 = pvv(i+1).power;                         % [kW]
                        return;

                   elseif price == pvv(i).marginalPrice
                       
%                      The marginal price is the same as the indexed
%                      active vertex. Use its power value.
                        p1 = pvv(i).power;                           % [kW]
                        return;

                    end                                                % if

                end                                      % for indexed on i

            end                                                        % if

    end                                                            % switch
            
end                                                 % function production()

