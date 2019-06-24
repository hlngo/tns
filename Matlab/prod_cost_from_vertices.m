function [ cost ] = prod_cost_from_vertices( obj, ti, pwr )
% PROD_COST_FROM_VERTICES - Infer production cost for a power from the
% vertices that define an object's supply curve
%
% If the neighbor is not a "friend" (an insider that is owned by the same
% business entity), it is probably represented by a production cost that
% includes both production costs and profits. If, however, the neighbor is
% a friend, it may offer a blended price that eliminates some, if not all,
% local profit.
%
% PRESUMPTIONS:
%   - This method applies to NeighborModel and LocalAssetModel objects.
%     Method properties must be named identically in these object classes.
%   - A supply curve exists for the object, as defined by a set of active
%     vertices. The vertices are up-to-date. See struct Vertex().
%   - Vertex property "cost" defines the total, accurate production cost
%     for the object at the vertex's power. The marginal price and slope of
%     segment between successive vertices must be used to infer production
%     cost between vertices.
%   - Production costs must be accurate and meaningful. An ideal is that
%     the production costs estimate or displace the dynamic delivered cost
%     of electricity. If production costs are well-tracked, production
%     costs should be equivalent to electricity costs over time.
%
% INPUTS:
% obj - the neighbor model 3object
% ti - the active time interval
% pwr - the average power at which the production cost is to be
%       calculated. This will be the scheduled power during scheduling.
%       It may be power at other active vertices for the calculation of
%       flexibility.
%
% OUTPUTS:
% cost - production cost in the time interval ti [$]
%
% VERSIONING
% 0.1 2018-01 Hammerstrom
%   - Generalized function from a method of NeighborModel. Should be usable
%     by either neighbor or asset models, I think.

%   We presume only generation and importation of electricity (i.e., p>0)
%   contribute to production costs
    if pwr < 0.0
        cost = 0.0;
        return;
    end

%   Find the active vertices for the object in the given time
%   interval
    v = findobj(obj.activeVertices,'timeInterval',ti);      %IntervalValues

%   number of active vertices len in the indexed time interval    
    len = length(v);
    
    switch len
        
    case 0               %No vertices were found in the given time interval

        warning(['No active vertices are found for ', ...
            obj.name,'. Returning without finding ', ...
            'production cost.']);

        return;

    case 1                 %One vertex was found in the given time interval

%       Extract the vertex from the interval value
        v = v(1).value;                                %a production vertex

%       There is no flexibility. Assign the production value from the
%       constant production as indicated by the lone vertex.
        cost = v.cost;                                % production cost [$]

        otherwise                            %There is more than one vertex

        %Extract the production vertices from the interval values
        v = [v.value];                                            %vertices

%       Sort the vertices in order of increasing marginal price and
%       power
        v = sort_vertices(v);                   %sorted production vertices

%       Special case when neighbor is at its minimum power. 
        if pwr <= v(1).power
            
%           Production cost is known from the vertex cost.
            cost = v(1).cost;                          %production cost [$]

%       Special case when neighbor is at its maximum power. 
        elseif pwr >= v(len).power
%             
%           Production cost may be inferred from the blended price at the
%           maximum production vertex.
            cost = v(len).cost;                        %production cost [$]

%       Remaining case is that neighbor power is between defined
%       production indices.
        
        else

%           Index through the production vertices v in this time interval
            for k = 1:(len-1)

                if pwr >= v(k).power && pwr < v(k+1).power
                    
%                   The power is found to lie between two of the vertices.

%                   Constant term (an integration constant from lower
%                   vertex
                    a0 = v(k).cost;                                    %[$]
                    
%                   First-order term for the segment is based on the
%                   marginal price of the lower vertex and the power
%                   exceeding that of the lower vertex
%                   NOTE: Matlab function hours() toggles duration back to
%                   a numeric value, which is correct here.
                    dur = ti.duration;
                    if isduration(dur)
                        dur = hours(dur);      % toggle duration to numeric
                    end
                    a1 = v(k).marginalPrice;                      % [$/kWh]
                    a1 = a1 * (pwr - v(k).power);                   % [$/h]
                    a1 = a1 * dur;                                    % [$]
                    
%                   Second-order term is derived from the slope of the
%                   current segment of the supply curve and the square of
%                   the power in excess of the lower vertex
                    if v(k+1).power == v(k).power
                        
%                       An exception is needed for infinite slope to avoid
%                       division by zero
                        a2 = 0.0;                                      %[$]
                        
                    else
%                       NOTE: Matlab function hours() toggles a duration
%                       back to a numeric, which is correct here.
                        dur = ti.duration;
                        if isduration(dur)
                            dur = hours(dur);  % toggle duration to numeric
                        end
                        a2 = v(k+1).marginalPrice - v(k).marginalPrice;
                                                                  % [$/kWh]
                        a2 = a2 / (v(k+1).power - v(k).power); % [$/kWh/kW]
                        a2 = a2 * (pwr - v(k).power)^2;             % [$/h]
                        a2 = a2 * dur;                                % [$]
                    end                                                 %if

%                   Finally, calculate the production cost for the time
%                   interval by summing the terms
                    cost = a0 + a1 + a2;               %production cost [$]
                    
%                   Return. Production cost has been calculated.                    
                    return;

                end                                                     %if

            end                                             %for indexing k

        end                                                             %if   

    end                                                             %switch
    
end                                    % function prod_cost_from_vertices()

