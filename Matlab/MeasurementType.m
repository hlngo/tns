classdef MeasurementType
% MeasurementType Enumeration
% This enumeration is used by IntervalValue class to consistently specify
% types of measurements being made, including their units of measure. (Some
% further work may be needed to parse this enumeration into still smaller
% parts.)
    
%% MeasurementType enumeration
    enumeration
        average_demand_kW              % used for demand threshold metering
        voltage
        power_real
        power_reactive
        price_incremental
        price_blended
        energy_real
        energy_reactive
        power_minimum_real
        power_maximum_real
        power_minimum_reactive
        power_maximum_reactive
        ProdVertex                      % Used by LocalResource
        temperature                     % used by WeatherForecastModel
        insolation_density
        relative_humidity
        unknown
    end                                       % MeasurementType enumeration
    
end                                              % classdef MeasurementType

