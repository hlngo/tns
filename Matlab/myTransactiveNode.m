classdef myTransactiveNode < handle
%% myTransactiveNode object
% myTransactiveNode is the local persepctive of the computational agent
% among a network of TransactiveNodes.

%% myTransactiveNode Basic Properties
    properties
        description = ''
        mechanism = 'consensus'
        name = ''
        status = 'unknown'                    % future: will be enumeration
    end                                % myTransactiveNode Basic Properties
    
%% myTransactiveNode List Properties
% The agent must keep track of various devices and their models that are
% listed among these properties.
    properties
        informationServiceModels = InformationServiceModel.empty
        localAssets = LocalAsset.empty
        markets = Market.empty
        meterPoints = MeterPoint.empty
        neighbors = Neighbor.empty
    end                                 % myTransactiveNode List Properties

end                                            % Classdef myTransactiveNode