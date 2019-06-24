function [ b ] = isHLH( time )
% isHLH - True if time is within a HLH hour; false otherwise
% INPUT:
% - time: a datetime

%Ensure that time is represented as a datetime
time = datetime(time);

%% NERC Holidays
% NERC holidays are always LLH.
holidays = [ ...
    datetime(2018,01,01); ...                               %New Year's Day
    datetime(2018,05,28); ...                                 %Memorial Day
    datetime(2018,07,04); ...                             %Independence Day
    datetime(2018,09,03); ...                                    %Labor Day
    datetime(2018,11,22); ...                             %Thanksgiving Day
    datetime(2018,12,25)];                                   %Christmas Day

%The basic definition of HLH is based on hour h and weekday d memberships.
h = hour(time);
d = weekday(time);

%% HLH hours starting
% HLH hours are defined by the time they end. Here, we shall address hours
% by their starting times.
HLH = 6:21;                                  %Daily HLH hour starting block

[Y,M,D] = ymd(time);                                  %Year, month, and day

if ismember(h,HLH) && d ~= 1 && ~ismember(datetime(Y,M,D),holidays)
    b = true;                                                  %an HLH hour
else
    b = false;                                                 %an LLH hour
end

end                                                       %function isHLH()

