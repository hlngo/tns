function test_order_vertices()
    disp('Running test_order_vertices()');
    pf = 'pass';

    p = [-100, 0, 100 , 0]; % power vector
    c = [0.4, 0.3, 0.3, 0,2]; % marginal price vector

    % create test vertices in v_in
    for i = 1:4
        v_in(i) = Vertex(c(i),0,p(i));
    end

    v_out = order_vertices( v_in );

% Compare output to correct order    
    if all([v_out.power] ~= [v_in([4,2,3,1]).power]) ...
           || all([v_out.marginalPrice] ~= [v_in([4,2,3,1]).marginalPrice])
        pf = 'fail';
        warning('- sorting was not successful');
    else
        disp('- sorting was successful');
    end
    
%   Success
    disp('- the test ran to completion');
    fprintf('Result: %s\n\n',pf);
    
%   Clean up the variable space
    clear v_in v_out
        
end                                            

