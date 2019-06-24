function [ ho ] = Hours( hi )
% HOURS - Correct the behavior of Matlab function hours()
% Matlab function hours() unfortunately toggles between duration and
% numerical representations. Therefore the result can be indeterminate.
% This function corrects that behavior.
    if ~isduration(hi)
        ho = hours(hi);
    else
        ho = hi;
    end
end

