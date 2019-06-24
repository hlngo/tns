classdef TransactiveNode < handle
    %TransactiveNode Base Class
    %   A TransactiveNode is the building block of a transactive network,
    %   but the base class is not used much. One necessarily adopts a
    %   perspective in which the computational agent instantiates 
    %   myTransactiveNode that interacts with subclass
    %   TransactiveNeighbor(s).
    
    %   VERSIONING
    %   0.1 2017-10 Hammerstrom     
    %       - Initial version
    
    properties
        
        description {ischar(description)}
        
        mechanism = 'consensus'
        
        name {ischar(name)}
        
        status
        
    end
    
end

