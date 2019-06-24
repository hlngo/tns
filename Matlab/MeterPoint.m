classdef MeterPoint < handle
% MeterPoint Base Class
% A MeterPoint may correlate directly with a meter. It necessarily
% corresponds to one measurement type (see MeasurementType enumeration) and
% measurement location within the circuit. Therefore, a single physical
% meter might be the source of more than one MeterPoint.
     
%% MeterPoint Properties
    properties
        description = ''
        currentMeasurement = 0.0          % storage for last measured value
        currentMeasurementTime = datetime.empty
        lastStoreTime = datetime.empty
        % NOTE: Function Hours() corrects behavior of Matlab hours().
        measurementInterval = Hours(1)                               % [hr]
        measurementType = MeasurementType.unknown            %  enumeration
        measurementUnit = MeasurementUnit.unknown            %  enumeration
        name = ''
        nextStoreTime = datetime.empty
        status
        storeInterval = Hours(1)        
        writeFile = 'MP'+string(datetime('now','Format','yyMMdd'))
    end                                             % MeterPoint Properties
    
%% MeterPoint methods    
    methods

%% FUNCTION READ_METER()
function read_meter(obj)
% FUNCTION READ_METER() - Read a meter point at scheduled intervals
%
% This method will likely differ by application and meter type. 
% Pseudocode:
% 1. This method should be called when the measurementInterval has passed
%    since the currentMeasurementTime.
% 2. Read the meter (practices, protocols, and standards may differ).
% 3. Calculate and store the currentMeasurement.
% 4. Update currentMeasurementTime by adding the measurementInterval to the
%    currentMeasurementTime.
% 5. Update the nextMeasurementTime by adding the measurementInterval to
%    the nextMeasurmentTime.
%

    disp(['Made it to MeterPoint.read_meter() for ', obj.name]);
    
end                                                 % FUNCTION READ_METER()

%% FUNCTION STORE()
function store( obj )
% FUNCTION STORE() - Store the last measurement into a file
%   obj - MeterPoint object
% Pseudocode:
% 1. This method should be called when we are time storeInterval past the
%    lastStoreTime.
% 2. The currentMeasurement and its corresponding currentMeasurementTime
%    are appended to a file.
% 3. The lastStoreTime is updated by adding store interval.
    
%   Open a simple text file for appending    
    fid = fopen(obj.writeFile,'w');
    
%   Append the formatted, paired last measurement time and its datum
    fprintf(fid, ...
        string(datetime(obj.currentMeasurementTime,'Format', ...
        'yyMMdd:hhmmss'))+','+string(obj.currentMeasurement)+'\n');
    
%   Re-close the file
    fclose(fid);
    
%   Update the last storage time
%   NOTE: Function Hours() corrects the behavior of Matlab hours().
    obj.lastStoreTime = obj.lastStoreTime + Hours(obj.storeInterval);
    
%   Update the next storage time
    obj.nextStoreTime = obj.nextStoreTime + Hours(obj.storeInterval);

end                                                       %function store()
        
    end                                                % MeterPoint Methods
    
% Static MeterPoint Methods
    methods (Static)
        
%% TEST_ALL()                                                      COMPLETE
function test_all()
% TEST_ALL() - test all MeterPoint methods
    disp('Running MeterPoint.test_all()');
    MeterPoint.test_read_meter();
    MeterPoint.test_store();
end                                                              % TEST_ALL

%% TEST_READ_METER()
function pf = test_read_meter()
    disp('Running MeterPoint.test_read_meter()');
    pf = 'the test is not completed yet';
    disp(['WARNING: This test will be unique to the meter being read ',...
        'or the value being computed.']);

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
% Clean up
%     clear test_mtr

end                                                     % TEST_READ_METER()

%% TEST_STORE()                                                    COMPLETE
function pf = test_store()
    disp('Running MeterPoint.test_store()');
    pf = 'pass';
    
    filename = 'MeterFileTest.txt';
    
%   Create a test meter and its writeFile
    test_mtr = MeterPoint;
        test_mtr.writeFile = filename;
        test_mtr.currentMeasurement = 3.1416;
        test_mtr.currentMeasurementTime = datetime(2018,1,1,12,0,0);
        test_mtr.lastStoreTime = datetime(2018,7,4,0,0,0);
%       NOTE: Function Hours() corrects behavior of Matlab hours().
        test_mtr.storeInterval = Hours(1);
        
    try
        test_mtr.store();
        disp('- the method ran without errors');
    catch
        pf = 'fail';
        error('- the method encountered errors and would not run');
    end
    
    if exist(filename,'file') ~= 2
        pf = 'fail';
        error('- the storage file does not exist');
    else
        disp('- the storage file was found to exist');
    end
    
    fid = fopen(filename);
    data = textread(filename, '%s', 'whitespace',',');
    fclose(fid);
    
    if str2num(data{2}) ~= 3.1416
        pf = 'fail';
        warning('- did not retreive the expected value');
    else
        disp('- retrieved the expected value');
    end

%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
% Clean up
    clear test_mtr
    fclose all;
%     oldstate = recycle('on');
%     delete 'MeterFileTest.txt'; %NOTE: This is not working for some reason.
%     recycle(oldstate);

end                                                          % TEST_STORE()


    end                                         % Static MeterPoint Methods
    
end                                                    %classdef MeterPoint

