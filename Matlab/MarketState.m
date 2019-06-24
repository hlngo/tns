classdef MarketState
%MarketState Enumeration
% MarketState is an enumeration os states of TimeIntervals as defined by
% the Market(s) in which myTransactiveNode transacts.
    
%% MarketState enumeration
    enumeration
        Inactive                                       % Unneeded, inactive
        Exploring                    % Actively negotiating. Not converged.
        Tender  %A converged electricity allocation solution has been found
        Transaction        % The market has cleared. Contractuals may exist
        Delivery            %The systen is currently in the interval period
        Publish     % The interval is over. Reconciliation may be under way
        Expired     % Reconciliation is concluded. The interval is inactive
    end                                           % MarketState enumeration
    
end                                                  % classdef MarketState

