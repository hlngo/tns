function AgentTest(mTN)
% A test may be written to summarize the configuration that exists
% after running a configuration script. This test script simply lists the
% configuration to screen.

fprintf(['Configuration of ',mTN.name, ':\n']);

fprintf('\nLocalAssets:\n');
n = mTN.localAssets;
for i = 1:length(n)
 fprintf(['  ',n{i}.name,': ',n{i}.description,'\n']);   
end

fprintf('\nNeighbors:\n');
n = mTN.neighbors;
for i = 1:length(n)
 fprintf(['  ',n{i}.name,': ',n{i}.description,'\n']);   
end

fprintf('\nMarkets:\n');
n = mTN.markets;
for i = 1:length(n)
 disp([string(n{i}.marketOrder)+': '+n{i}.name]);   
end

end

