classdef TemperatureTables
% TEMPERATURETABLES - static hourly temperature tables for development
% Hourly temperature forecasts will be needed frequently. This file
% provides simple static tables that may be used by developers until a
% suite of InformationServices can be developed.
% The provided method simply creates a text file from the temperature data.
%
% Example: TemperatureTables.temp(1,2) returns the temperature between
%          midnight and 1a on a moderate day.
    properties
        filename = 'temperatures.txt'
    end
    
%% Constant TemperatureTables properties
    properties (Constant)
        temp = [ ...
%           cold    moderate hot        hour-starting
            19,     49,      89; ...   %00
            19,     49,      89; ...   %01
            20,     50,      90; ...   %02
            20,     50,      90; ...   %03
            20,     51,      91; ...   %04
            21,     51,      91; ...   %05
            21,     51,      91; ...   %06
            21,     51,      91; ...   %07
            21,     51,      91; ...   %08
            23,     53,      93; ...   %09
            25,     55,      95; ...   %10
            28,     58,      98; ...   %11
            30,     60,     100; ...   %12
            32,     62,     102; ...   %13
            32,     62,     102; ...   %14
            30,     60,     100; ...   %15
            25,     55,      95; ...   %16
            20,     50,      90; ...   %17
            18,     48,      88; ...   %18
            18,     48,      88; ...   %19
            18,     48,      88; ...   %20
            19,     49,      89; ...   %21
            19,     49,      89; ...   %22
            19,     49,      89];      %23
    end                             % Constant TemperatureTables properties
    
    methods
        function make_table(obj)
            cold = TemperatureTables.temp(:,1);
            moderate = TemperatureTables.temp(:,2);
            hot = TemperatureTables.temp(:,3);
            T = table(cold,moderate,hot);
            writetable(T,obj.filename);
        end
    end
    
end                                            % classdef TemperatureTables

