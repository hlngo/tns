classdef TransactiveRecord < handle
% TransactiveRecord - transactive signal record format
% This is primarily a struct, although is might include a constructor
% method.
    
%% TransactiveRecord properties    
    properties
        %Source and target are obvious from Neighbor and filenames. Omit
        timeStamp = datetime.empty     %This is assigned upon instantiation
%       NOTE: Function Hours() corrects behavior of Matlab function
%       hours().
        timeInterval = Hours(0) 
        record = 0                % positive integer =0 for scheduled state
        marginalPrice = 0.0                                       % [$/kWh]
        power = 0.0                                             % [avg. kW]
        powerUncertainty = 0.0                   % relative [dimensionless]
        cost = 0.0                                                      % ?
        reactivePower = 0.0                                    % [avg.kVAR]
        reactivePowerUncertainty = 0.0           % relative [dimensionless]
        voltage = 0.0                                              % [p.u.]
        voltageUncertainty = 0.0                 % relative [dimensionless]
    end                                      % TransactiveRecord properties 
    
%% TransactiveRecord methods     
    methods
        
%% FUNCTION TRANSACTIVERECORD()
function  obj = TransactiveRecord(ti,rn,mp,p,varargin)
% TRANSACTIVERECORD() - constructor method
% NOTE: As of Feb 2018, ti is forced to be text, the time interval name, 
%   not a TimeInterval object.
% ti - TimeInterval object (that must be converted to its name)
% rn - record number, a nonzero integer
% mp - marginal price [$/kWh]
% p  - power [avg.kW]
% varagin - Matlab variable allowing additional input arguments.

%   Warn and return if too few input arguments nargin were used.
    if nargin < 4
    	warning('too few input arguments');
        return;
    end
    
%   These are the four normal arguments of the constructor.
% NOTE: Use the time interval ti text name, not a TimeInterval object
% itself.
    if isa(ti,'TimeInterval')
        
%       A TimeInterval object argument must be represented by its text
%       name.
        obj.timeInterval = ti.name; 
        
    else
        
%       ARgument ti is most likely received as a text string name. Further
%       validation might be used to make sure that ti is a valid name of an
%       active time interval.
        obj.timeInterval = ti;
        
    end
    
    obj.record = rn;      % a record number (0 refers to the balance point)
    obj.marginalPrice = mp;                        % marginal price [$/kWh]
    obj.power = p;                                         % power [avg.kW]     
    
%   A number of cases are determined by the numbers of addtitional input
%   arguments nvarargin.
    nvarargin = length(varargin);

    if nvarargin >= 1
        obj.powerUncertainty = varargin{1}; 
                                       % FUTURE: rel. error [dimensionless]  
                                       
        if nvarargin >= 2
            obj.cost = varargin{2};             % FUTURE: a production cost  
            
            if nvarargin >= 3
                obj.reactivePower = varargin{3};
                                            % FUTURE: reactive power [kVAR]
                                            
                if nvarargin >= 4
                    obj.reactivePowerUncertainty = varargin{4};   
                                                  % FUTURE: rel uncertainty 
                                                  
                    if nvarargin >= 5
                        obj.voltage = varargin{5};        % FUTURE: voltage 
                        
                        if nvarargin >= 6
                            obj.voltageUncertainty = varargin{6};
                                                 % FUTURE: rel. uncertainty                         
                        end                             % if nvarargin >= 6
                    end                                 % if nvarargin >= 5
                end                                     % if nvarargin >= 4
            end                                         % if nvarargin >= 3
        end                                             % if nvarargin >= 2
    end                                                 % if nvarargin >= 1


%   Finally, create the timestamp that captures when the record is created.
%   Format example: "180101:000001" is one second after the new year 2018 
    obj.timeStamp = string(datetime('now','Format','yyMMdd:HHmmss')); 
    
end                                          % FUNCTION TRANSACTIVERECORD()
        
    end                                         % TransactiveRecord methods

end                                   % classdef TransactiveRecord < handle

