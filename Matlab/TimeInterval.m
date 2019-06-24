classdef TimeInterval < handle
    %TimeInterval Base Class
    %   The TimeInterval is the Market time interval. It progresses through
    %   a series of MarketStates (see MarketState enumeration).
    
%% TimeInterval properties    
    properties
        active  = false                                           % Boolean
        activationTime = datetime.empty   % when negotiations become active
        converged = false
        % NOTE: function Hours() corrects behavior of Matlab's hours()
        duration = Hours(0)                     % duration of interval [hr]
        market = Market.empty
        marketClearingTime = datetime.empty            % when market clears
        marketState = MarketState.Inactive                    % enumeration
        name = ''           
        reconciled = true
        startTime = datetime.empty                   % when interval starts
        timeStamp = datetime.empty      % when interval is created/modified
    end                                           % TimeInterval properties
    
%% TimeInterval methods    
    methods
        
%% FUNCTION ASSIGN_STATE(OBJ,MARKET)      
function assign_state(obj,~)
% assign_state - assign state of the TimeInterval in its Market. 
% Enumeration MarketState has all the allowed market state names.
%   obj - a TimeInterval oject. Invoke as "obj.assign_state(market)".
%   market - Market object (see class Market).

    dt = datetime;                                   %Current date and time

%   State "Expired": The TimeInterval period is over and the interval has
%   been reconciled in its Market.
    if dt >= datetime(obj.startTime) + obj.duration ...
            && obj.reconciled == true
        obj.marketState = MarketState.Expired;
        obj.active = false;
        obj.timeStamp = dt;

%   State "Publish": The TimeInterval period has expired, but it has not
%   yet been reconciled in its Market.
    elseif dt >= datetime(obj.startTime) + obj.duration
        obj.marketState = MarketState.Publish;
        obj.active = true;
        obj.timeStamp = dt;

%   State "Delivery": Durrent datetime is within the interval period.
    elseif dt >= datetime(obj.startTime)
        obj.marketState = MarketState.Delivery;
        obj.active = true;
        obj.timeStamp = dt;

%   State "Transaction": Current datetime exceeds the market clearing time.
    elseif dt >= datetime(obj.marketClearingTime)
        obj.marketState = MarketState.Transaction;
        obj.active = true;
        obj.timeStamp = dt;

%   State "Tender": TimeInterval is both active and converged.
    elseif dt >= datetime(obj.activationTime) && obj.converged == true
        obj.marketState = MarketState.Tender;
        obj.active = true;
        obj.timeStamp = dt;

%   State "Exploring": TimeInterval is active, but it has not converged.
    elseif dt >= datetime(obj.activationTime) 
        obj.marketState = MarketState.Exploring;
        obj.active = true; 
        obj.timeStamp = dt;

%   State "Inactive": The TimeInterval has not yet become active.    
    elseif dt < datetime(obj.activationTime)
        obj.marketState = MarketState.Inactive;
        obj.active = false;
        obj.timeStamp = dt;

    else 
        error(['Invalid TimeInterval market state: ', ...
            'TimeInterval ', char(obj.name)], '\n');

    end                                                                % if

end                                               % function assign_state()

%% TimeInterval Constructor
function obj = TimeInterval(at,dur,mkt,mct,st)
%   TIMEINTERVAL - construct a TimeInterval object

%   ACTIVATION TIME - datetime that the TimeInterval becomes Active and
%   enters the Exploring market state
    obj.activationTime = datetime(at);
    
%   CONVERGED - convergence flag for possible future use
    obj.converged = false;

%   DURATION - duration of interval[hr]
%   Ensure that content is a duration [hr]
%   NOTE: Function Hours() corrects behavior of Matlab hours().
    obj.duration = Hours(dur);

%   MARKET - Market object that uses this TimeInterval
    obj.market = mkt;

%   MARKET CLEARING TIME - time that negotiations stop. Time that
%   committments, if used, are in force.
    obj.marketClearingTime = datetime(mct);

%   START TIME - time that interval period begins
    obj.startTime = datetime(st);
    
%   NAME
    obj.name = char(obj.startTime,'yyMMdd-HHmm');
    
%   RECONCILED - reconciliation flag for possible future use
    obj.reconciled = false;
    
%   MARKET STATE - an enumeration of market states, concerning the
%                  status of negotiations on this time interval.
%   ACTIVE - logical true during negotiations, delivery, and
%            reconcilliation of the time interval
%   TIME STAMP - the time the the time interval is created or modified
    obj.assign_state(); 
    
end                                              % TimeInterval Constructor

    end                                              % TimeInterval methods
    
end %Classdef TimeInterval 

