%% Test function test_isHLH
function  pf  = test_isHLH()
    disp('Running test_isHLH()');
    pf = 'pass';

%% Test exception days (at noon)
exception_days = [ ...
    datetime(2018,01,01,12,0,0); ...                       % New Year's Day
    datetime(2018,05,28,12,0,0); ...                         % Memorial Day
    datetime(2018,07,04,12,0,0); ...                     % Independence Day
    datetime(2018,09,03,12,0,0); ...                            % Labor Day
    datetime(2018,11,22,12,0,0); ...                     % Thanksgiving Day
    datetime(2018,12,25,12,0,0)];                           % Christmas Day

    for i = 1:length(exception_days)
        test(i) = ~isHLH(exception_days(i));
    end

    if all(test) == false
        pf = 'fail';
        error('- NERC holidays are not HLH');
    else
        disp('- NERC holidays were handled correctly');
    end

    d = datetime(2018,12,2,12,0,0) + days(0:6);
    for i = 1:7
        if isHLH(d(i)) ~= logical(weekday(d(i))-1)
            pf = 'fail';
            error('- only Sunday should be excluded from HLH');        
        end
    end

    hrs = 0:23;

    test_day = datetime(2018,1,2,0,0,0);

    for i = 1:24
%      NOTE: Function Hours() corrects behavior of Matlab function hours().
       test(i) = isHLH(test_day + Hours(hrs(i)));
    end

    if ~all(~test(1:6))
        pf = 'fail';
        error('- hours starting [0-5] are not HLH');
    elseif ~all(test(7:22))
        pf = 'fail';
        error('- hours starting [6-23] are HLH');   
    elseif ~all(~test(23:24))
        pf = 'fail';
        error('- hours starting [22,23] are not HLH');    
    end
    disp('- correct assignments were made');

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up the class space
    clear test_object test_day

end