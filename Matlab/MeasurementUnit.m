classdef MeasurementUnit
% MeasurementUnit enumeration - allowed units of measure
% This formulation currently allows only a small set of measurement units
% and expecting precisely one unit of measure for each measurement type.
%
% NOTE: perhaps this approach should be revised to ensure the proper
% pairing of measurment types and their unit of measure.
 
%% MeasurementUnit enumeration
    enumeration
        degF
        kVAR
        kVARh
        kW
        kWh
        unknown                            % useful as a default assignment
    end                                       % MeasurementUnit enumeration
    
end                                               %classdef MeasurementUnit

