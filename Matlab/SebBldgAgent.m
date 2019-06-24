%% SEB BLDG AGENT SCRIPT
% Transactive network configuration script from the perspective of the SEB
% Bldg.

% This script is used to initialize the SEB Building's computational
% agent from provided base classes.

%% Instantiate myTransactiveNode ******************************************
%   This states the single perspective of the computational agent that is
%   being configured. Each computational agent must complete a
%   configuration script according to its unique perspective in the
%   transactive network.
% *************************************************************************
SebBldg = myTransactiveNode; %a meaningful object name
mTN = SebBldg;
    
    mTN.description = ['SEB Building on the Pacific Northwest', ...
        'National Laboratory campus, Richland, WA'];
    mTN.name = 'SebBldg'; %a meaningful text name

%% Instantiate each MeterPoint ********************************************
% A MeterPoint object is responsible for a current measurement or
% calculated value. Any MeterPoint that is used by models or objects should
% be defined here and accessible by myTransactiveNode. Meterpoints should
% be defined early in this script because a MeterPoint may be referenced by
% InformationServiceModels and other objects and classes.
% *************************************************************************

%% SEB ELECTRICITY METER < MeterPoint
% NOTE: Many more details must be included if and when we receive real-time
% metering.
SebElectricityMeter = MeterPoint;    % Instantiate an electricity meter
MP = SebElectricityMeter;
    MP.description = 'meters the SEB electricity load';
    MP.measurementType = MeasurementType('power_real');
    MP.name = 'SebElectricityMeter';
    MP.measurementUnit = 'kWh'; 
    
%% Provide a cell array of the MeterPoint objects to myTransactiveNode.
% NOTE: Models and objects that use these meters are ALSO expected to
% possess such a list.
    mTN.meterPoints = {SebElectricityMeter};

%% Instantiate each InformationServiceModel *******************************
% An InformationServiceModel may be queried for information. It is often a
% Web information service, but is not necessarily a Web information
% service. This class is similar to MeterPoint, which should be used for
% simple metered data and calculations, but it includes model prediction
% for future time intervals.
% InformationServiceModels should be defined early in this script because
% they may be referenced by many other objects and models.
% *************************************************************************

%% RICHLAND TEMPERATURE FORECAST < InformationServiceModel
% Uses a subclass that invokes Weather Underground forecasts.
% A constructor assigns properties description, informationType,
% informationUnits, license, name, nextScheduledUpdate,
% serviceExpirationDate, and updateInterval.
RichlandTemperatureForecast = TemperatureForecastModel;
ISM = RichlandTemperatureForecast;

    ISM.address;                           % Assigned by constructor method
    ISM.description;                       % Assigned by constructor method
    ISM.file;                                                    % Not used
    ISM.informationType;                   % Assigned by constructor method
    ISM.informationUnits;                  % Assigned by constructor method
    ISM.license;                           % Assigned by constructor method
    ISM.name = 'RichlandTemperatureForecast';
%   The next scheduled information update is initialized by constructor
%   method, but it's good practice to run method update_infromation() at
%   the end of this script.
    ISM.nextScheduledUpdate;            
    ISM.predictedValues = IntervalValue.empty;       % dynamically assigned    
    ISM.serviceExpirationDate;             % Assigned by constructor method
    ISM.updateInterval; % Assigned by constructor method, may be reassigned
    
%% Provide a cell array of the InformationServiceModel objects to 
% myTransactiveNode.
    mTN.informationServiceModels = {RichlandTemperatureForecast};

%% Instantiate each LocalAsset and its LocalAssetModel

% An asset is "owned" by myTransactiveNode. Energy consumed (or generated)
% by a local asset is valued at either its production costs (for a
% resource) or blended price of electricity (for a load). A local asset
% model manages and represents its asset. There must be a one-to-one
% correspondence between an asset and asset model.

%% Unresponsive SEB Building load
BldgLoad = LocalAsset;
LA = BldgLoad;
    
    LA.description = 'SEB Building load that is not responsive';
    LA.maximumPower = 0; 
    LA.meterPoints;
    LA.minimumPower = -200; %[avg.kW]
    LA.name = 'BldgLoad';
    LA.subclass = class(LA);

%% Unresponsive SEB Building Load Model    
BldgLoadModel = LocalAssetModel;
LAM = BldgLoadModel;

    LAM.activeVertices; %to be dynamically assigned
    LAM.costParameters; 	%accept defaults
    LAM.defaultPower = -100;
    LAM.defaultVertices = Vertex(inf,0,-100,true);
    LAM.dualCosts;  %to be dynamically assigned
    LAM.engagementCost; %to be dynamically assigned
    LAM.engagementSchedule; %to be dynamically assigned
    LAM.informationServiceModels = InformationServiceModel.empty;
    LAM.name = 'SebLoadModel';
    LAM.productionCosts;    %to be dynamically assigned
    LAM.reserveMargins; %to be dynamically assigned
    LAM.scheduledPowers;    %to be dynamically assigned
    LAM.totalDualCost = 0.0;    %to be dynamically assigned
    LAM.totalProductionCost = 0.0;  %to be dynamically assigned
    LAM.transitionCosts;    %to be dynamically assigned
    
%% Allow the object and model to cross reference one another
    LA.model = LAM;
    LAM.object = LA;
    
%% Intelligent Load Control (ILC) System
IlcSystem = LocalAsset;
LA = IlcSystem;

    LA.description = ['Interactive Load Control (ILCO) system in ', ... 
        'the SEB Building'];
    LA.maximumPower = 0;    %[avg.kW]
    LA.meterPoints = MeterPoint.empty;
    LA.minimumPower = -50;  %[avg.kW]
    LA.name = 'IlcSystem';
    LA.subclass = class(LA);
    
%% Intelligent Load Control Model   
IlcSystemModel = LocalAssetModel;
% IlcSystemModel = IlcModel; % Does not run yet with this model 2/5/18
LAM = IlcSystemModel;

    LAM.activeVertices; %to be dynamically assigned
    LAM.costParameters;                  %dynamically assigned
    LAM.defaultPower = -50;
    LAM.defaultVertices = [Vertex(0.055,0,-50,true), ...
        Vertex(0.06,0,-25,true)];
    LAM.dualCosts;                  %dynamically assigned
    LAM.engagementCost;                  %dynamically assigned
    LAM.engagementSchedule;                  %dynamically assigned
    LAM.informationServiceModels =InformationServiceModel.empty;
    LAM.name = 'IlcSystemModel';
    LAM.productionCosts;                  %dynamically assigned
    LAM.reserveMargins;                  %dynamically assigned
    LAM.scheduledPowers;                  %dynamically assigned
    LAM.totalDualCost = 0.0;                  %dynamically assigned
    LAM.totalProductionCost = 0.0;                  %dynamically assigned
    LAM.transitionCosts;                  %dynamically assigned
    
%% Allow the object and model to cross reference one another
    LA.model = LAM;
    LAM.object = LA;
    
%% Provide cell array of LocalLoads to myTransativeNode
% NOTE: The elements of this cell array must be indexed using curly braces.
    SebBldg.localAssets = {BldgLoad,IlcSystem};
    
%% Instantiate each Market ************************************************
% A Market is required. Markets specify TimeIntervals and when they are
% active. Additional Markets may be instantiated where (1) a complex series
% of sequential markets must be created, or (2) the durations of
% TimeIntervals change within the future horizon.

%% DAYAHEAD MARKET
dayAhead = Market;
MKT = dayAhead;
    
    MKT.blendedPrices1;                          %Dynamically assigned
    MKT.blendedPrices2;                          %Dynamically assigned
    MKT.commitment = false;
    MKT.converged = false;
    MKT.defaultPrice = 0.0428;                                %[$/kWh]
    MKT.dualCosts;                               %Dynamically assigned
    MKT.dualityGapThreshold = 0.0005;                      %[0.02 = 2%]
    MKT.futureHorizon = 24.0;    % Projects 24 hourly future intervals
    MKT.intervalDuration = 1.0;            %[h] Intervals are 1 h long
    MKT.initialMarketState = 'inactive';    %Intervals activate selves
    MKT.intervalsToClear = 1;             %Only one interval at a time
    MKT.marketClearingInterval = 1.0;                             %[h]
    MKT.marketClearingTime = datetime(date);  %Aligns with top of hour
    MKT.marketOrder = 1;                %This is first and only market
    MKT.name = 'dayAhead';
    MKT.nextMarketClearingTime = datetime('now') ...
        + 1/24 ...
        - minute(datetime('now'))/1440 ...
        - second(datetime('now'))/86400;                 % Next top of hour
    MKT.productionCosts;                         %dynamically assigned
    MKT.timeIntervals;                           %dynamically assigned
    MKT.totalDemand;                             %dynamically assigned
    MKT.totalDualCost;                           %dynamically assigned
    MKT.totalGeneration;                         %dynamically assigned
    MKT.totalProductionCost;                     %dynamically assigned
         
%% Provide a cell array of Markets to myTransactiveNode.
    mTN.markets = {dayAhead};

%% Instantiate each Neighbor and Neighbor Model ***************************
% Neighbors are remote locations with which myTransactiveNode exchanges
% electricity. myTransactiveNode has limited ownership or control over
% their electricty usage or generation. There are transactive neighbors and
% non-transactive neighbors, as may be specified by the property
% Neighbor.transactive.
%
% Transactive neighbors (transactive = true) are members of the transactive
% system network. Transactive signals are sent to and received from
% transactive neighbors.
%
% Non-Transactive neighbors (transactive = false) are not members of the
% transactive network. They do  not exchange TransactiveSignals with
% myTransactiveNode.
%
% The neighbor model manages an interface to and represents its neighbor.
% There is a one-to-one correspondence between a Neighbor and its model.

%% PNNL Campus
PnnlCampus = Neighbor;
NB = PnnlCampus;

    NB.lossFactor = 0.01;
    NB.maximumPower = 200;
    NB.minimumPower = 0;
    NB.description = ['Pacific Northwest National Laboratory', ...
        '(PNNL) Campus in Richland, WA'];
    NB.mechanism = 'consensus';
    NB.name = 'PNNLCampus';
    NB.status;

%% PNNL Campus Model    
PnnlCampusModel = NeighborModel;
NBM = PnnlCampusModel;

    NBM.activeVertices;                  %dynamically assigned
    NBM.converged = false;                  %dynamically assigned
    NBM.convergenceFlags;                  %dynamically assigned
    NBM.convergenceThreshold = 0.02;
    NBM.costParameters;         %accept default values
    NBM.defaultVertices = [Vertex(0.045,25,0,1),Vertex(0.048,0,200,true)];
    NBM.demandThreshold = 0.8 * NB.maximumPower;
    NBM.dualCosts;                  %dynamically assigned
    NBM.effectiveImpedance = 0.0;
    NBM.friend = false;
    NBM.meterPoints = MeterPoint.empty;
    NBM.mySignal;                  %dynamically assigned
    NBM.name = 'PnnlCampusModel';
    NBM.productionCosts;                  %dynamically assigned
    NBM.receivedSignal;                  %dynamically assigned
    NBM.reserveMargins;                  %dynamically assigned
    NBM.scheduledPowers;                  %dynamically assigned
    NBM.totalDualCost = 0.0;                  %dynamically assigned
    NBM.totalProductionCost = 0.0;                  %dynamically assigned
    NBM.transactive = true;
    
%% Allow the object and model to cross reference one another.
    NBM.object = NB; %Cross reference to object
    NB.model = NBM; %Cross reference to model

%% Provide a cell array of Neighbors to myTransactiveNode.
% NOTE: A cell array must be indexed using curly braces.
    mTN.neighbors = {PnnlCampus};
    
%% Clean up    
clear LA LAM mTN NB NBM MKT ISM MP

%% Additional setup script ************************************************
% The following methods would normally be called soon after the above
% script to launch the system.

% Receive any transactive signals sent to myTransactiveNode from its
% TransactiveNeighbors. For this matlab version, this is simply the process
% of reading a file that the neighbor might have prepared and made
% available to myTransactiveNode.
PnnlCampusModel.receive_transactive_signal(SebBldg);

% Balance supply and demand at myTransactiveNode. This is iterative. A
% succession of iterationcounters and duality gap (the convergence metric)
% will be generated until the system converges. All scheduled powers and
% marginal prices should be meaningful for all active time intervals at the
% conclusion of this method.
dayAhead.balance(SebBldg);

% myTransactiveNode must prepare a set of TransactiveRecords for each of
% its TransactiveNeighbors. The records are updated and stored into the
% property "mySignal" of the TransactiveNeighbor.
PnnlCampusModel.prep_transactive_signal(dayAhead,SebBldg);

% Finally, the prepared TransactiveRecords are sent to their corresponding
% TransactiveNeighbor. In the matlab version, this is the creation (or
% updating) of a text file having TransactiveRecords as its rows.
PnnlCampusModel.send_transactive_signal(SebBldg);

% This method invokes the Market object to sum all the powers as will be
% needed by the net supply/demand curve.
dayAhead.assign_system_vertices(SebBldg);

% The condition of the total system supply/demand curve may be viewed at
% any time. This methods creates a net supply/demand curve figure for the
% active time integer interval indicated by the argument.
dayAhead.view_net_curve(1);