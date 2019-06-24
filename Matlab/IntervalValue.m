classdef IntervalValue < handle
    %IntervalValue Base Class
    %   An IntervalValue instance is used to keep track of a value
    %   (measurement, quality, etc.) with its corresponding TimeInterval
    %   instance.
    
%% IntervalValue properties
    properties
        version = 0;
        scheduled =  true;
        associatedClass                         % class of associatedObject
        associatedObject             % object that created or updated value
        id
        timeInterval = TimeInterval.empty
        market = Market.empty
        measurementType = 'unknown'
        name = ''
        value
    end                                          % IntervalValue properties
    
%% IntervalValue methods   
    methods

        %Subdivide an IntervalValue into mutiple idential IntervalValues.
        function subdivide(obj)
            fprintf('made it to IntervalValue.subdivide()');
        end
        
%% FUNCTION INTERVALVALUE()
% A constructor method
        function iv = IntervalValue(calling_object,time_interval, ...
                market,type,value,~)
            iv.value = value;
            iv.associatedClass = class(calling_object);
            iv.associatedObject = calling_object;
            iv.timeInterval = time_interval;
            iv.market = market;
            iv.measurementType = type;
            iv.name = strcat(iv.measurementType,'-',iv.timeInterval.name);
        end                                      % function IntervalValue()
        
    end                                             % IntervalValue methods
    
end                                       % classdef IntervalValue < handle

