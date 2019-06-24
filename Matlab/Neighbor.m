classdef Neighbor < AbstractObject
%Neighbor base class
% A Neighbor is a remote entity with which myTransactiveNode
% intertransacts. Neighbors that are also members of the transactive
% network are obligated to negotiate via transactive signals, and such
% Neighbors are indicated by setting the corresponding NeighborModel
% "transactive" parameter to TRUE.
    
%% Required Neighbor properties
% These properties are required by abstract superclass AbstractObject.
    properties
%         description = ''
%         maximumPower = 0.0        % "hard" power constraint [signed avg.kW]
%         meterPoints = MeterPoint.empty               % see class MeterPoint
%         minimumPower = 0.0      % a "hard" power constraint [signed avg.kW]
%         model = NeighborModel.empty % a cross-reference to associated model
%         name = ''
%         subclass = ''                       % the object's class membership
%         status = 'unknown'       
    end                                      % Required Neighbor properties
    
%% New Neighbor properties
    properties
        lossFactor = 0.01                 % [dimensionless, 0.01 = 1% loss]
%       NOTE: This next property may be moved to a TransactiveNeighbor
%       subclass.
        mechanism = 'consensus'     % Only applies to a TransactiveNeighbor       
    end                                           % New Neighbor properties
    
end                                    % classdef Neighbor < AbstractObject

