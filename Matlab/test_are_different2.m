% test_are_different2 - tests operation of stand-alone method
% are_different2(), which should return F if sent and prepared transactive
% signals are virtually the same at a Transactive Node System agent.

% The following cases are not yet coded for (would fail) but may be useful.
%% FUTURE CASE - Mismatched numbers of signals (should return T because the 
% signals clearly disagree on flexibility).
%% FUTURE CASE - No flexibility - One or both of the signals is missing 
% Record 0 (should use single signal, but warn).

disp('Running test_are_different2()');
pf = 'pass';

% Create a test Market object:
test_market = Market;

% Create a test TimeInterval object:
dt = datetime();
dur = Hours(1);
time_interval = TimeInterval(dt,dur,test_market,dt,dt);

% Create some TransactiveRecord objects:
transactive_records(1) = TransactiveRecord(time_interval,0,0.5,100);
transactive_records(2) = TransactiveRecord(time_interval,0,0.5,105);
transactive_records(3) = TransactiveRecord(time_interval,1,0.022,-0.0);
transactive_records(4) = TransactiveRecord(time_interval,2,0.022,16400);
transactive_records(5) = TransactiveRecord(time_interval,2,0.023,16400);

%%CASE 0: SIGNAL SETS DIFFER IN NUMBERS OF RECORDS
disp('Case 0: Signals have different record counts.');
prepped_records = transactive_records(1);
sent_records = transactive_records(1,2);
threshold = 0.02;

try
    response = are_different2(prepped_records,sent_records,threshold);
    disp('  The method ran without errors');
catch
    pf = 'fail';
    warning('  The method encountered errors and stopped');
end

if response ~= true
    pf = 'fail';
    warning('  The method said the signals are the same which is wrong');
else
    disp('  The method correctly said the signals differ');
end

%%CASE 1: No flexibility. One signal each. Powers of Records 0 match.
disp('Case 1: No flexibility. One signal each. Powers of Records 0 match.');
prepped_records = transactive_records(1);
sent_records = transactive_records(1);
threshold = 0.02;

try
    response = are_different2(prepped_records,sent_records,threshold);
    disp('  The method ran without errors');
catch
    pf = 'fail';
    warning('  The method encountered errors and stopped');
end

if response ~= false
    pf = 'fail';
    warning('  The method said the signals were different which is wrong');
else
    disp('  The method correctly said the signals were the same');
end

%%CASE 2 - No flexibiltiy. One signal each. Powers of Records 0 do not
%%match.
disp('Case 2: No flexibility. One signal each. Powers of Records 0 do NOT match.');
prepped_records = transactive_records(1);
sent_records = transactive_records(2);
threshold = 0.02;

try
    response = are_different2(prepped_records,sent_records,threshold);
    disp('  The method ran without errors');
catch
    pf = 'fail';
    warning('  The method encountered errors and stopped');
end

if response ~= true
    pf = 'fail';
    warning('  The method said the signals were the same which is wrong');
else
    disp('  The method correctly said the signals differ');
end

%%CASE 3 - (Hung's case) Flexibility, but identical signals. 
%NOTE: Hung had found a case where powers had become zero, causing logic
%problems. Code has been revised to avoid this possiblity.
disp('Case 3: Flexibility. Signals are identical');
prepped_records = transactive_records(3:4);
sent_records = transactive_records(3:4);
threshold = 0.02;

try
    response = are_different2(prepped_records,sent_records,threshold);
    disp('  The method ran without errors');
catch
    pf = 'fail';
    warning('  The method encountered errors and stopped');
end

if response ~= false
    pf = 'fail';
    warning('  The method said the signals differ which is wrong');
else
    disp('  The method correctly said the signals are the same');
end

%%CASE 4 - Flexibility, but different signals.
disp('Case 4: Flexibility. Signals are different');
prepped_records = transactive_records(3:4);
sent_records = transactive_records(3:5);
threshold = 0.02;

try
    response = are_different2(prepped_records,sent_records,threshold);
    disp('  The method ran without errors');
catch
    pf = 'fail';
    warning('  The method encountered errors and stopped');
end

if response ~= true
    pf = 'fail';
    warning('  The method said the signals are the same which is wrong');
else
    disp('  The method correctly said the signals differ');
end

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up the class space
    clear dt pf test_market time_interval transactive_records
    clear dur prepped_records response sent_records threshold