classdef Vertex
% Vertices - Struct to represent an inflection point in a supply or demand
% curve. Includes constructor method.

%% Vertex properties    
    properties
        cost  = 0.0                                                   % [$]
        marginalPrice  = 0                                        % [$/kWh]
        power  = 0.0                                             % [avg.kW]
        powerUncertainty  = 0.0         % (future) relative [dimensionless]
        continuity = true % (future) continuity between sequential vertices
    end                                                 % Vertex properties
    
%% Vertex methods    
    methods
        
%% FUNCTION VERTEX()
function s = Vertex(mPrice,prod_cost,power,varargin)
% Vertex() - a constructor method 

    s.marginalPrice = double(mPrice);                             % [$/kWh]
    s.cost = double(prod_cost);                 % i.e., production cost [$]
    s.power = double(power);                              % signed [avg.kW]

%   The remaining two properties are future capabilities that are allowed
%   to remain optional for now.
    for i = 1:nargin-3

        if islogical(varargin{i})
            s.continuity = varargin{i};

        elseif isreal(varargin{i})
            s.powerUncertainty = varargin{i};

        else
            return;

        end                                                            % if

    end                                                               % for

end                                                      %function vertex()
            
    end                                                    % Vertex methods
    
end                                                        %classdef Vertex

