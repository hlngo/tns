classdef BulkLoadModel < LocalAssetModel
%BULKLOADMODEL subclass of LocalAssetModel
% A parametric model to represent the dynamics of non-transactive bulk
% load. This model is suitable for aggregated loads (e.g., utility load,
% distribution feeder circuits, commercial or residential loads). The model
% is responsive to many parameters, but it is price-inelastic, so it offers
% a constant, inelastic demand curve.
%   - Introduces properties that are suitable model inputs
%   - Schedules power based on paramters other than price
    
    properties
        
    end
    
    methods
        
%% FUNCTION SCHEDULE_POWER()
function schedule_power(obj,mkt)
end %function schedule_power()
        
    end
    
end

