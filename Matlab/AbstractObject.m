classdef (Abstract) AbstractObject  < handle
% AbstractObject - Abstract root class for Neighbor and LocalAsset classes
% - Provides handle access
% - Ensures that critical properties will be uniformly redefined

%% AbstractObject properties
    properties
        description = ''
        maximumPower = 0.0    % object's physical "hard" constraint[avg.kW]
        meterPoints = MeterPoint.empty               % see class MeterPoint
        minimumPower = 0.0    % object's physical "hard" constraint[avg.kW]                                         % [avg. kW]
        model             % cross reference to object's corresponding model
        name = ''
        subclass
        status
    end                                         % AbstractObject properties

end                                      % classdef AbstractObject < handle

