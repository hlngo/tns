classdef TransactiveNeighbor < TransactiveNode
    
    %I'M EXPERIMENTING WITH THE DISTINCTION BETWEEN TRANSACTIVE AND
    %NONTRANSACTIVE NEIGHBORS. THIS CLASS IS TO BE ELIMINATED IN FAVOR OF
    %THE NEIGHBOR CLASS THAT COMBINED THEM. - DON
    
    %Neighbor Subclass
    %   A Neighbor is a TransactiveNode object with which
    %   myTransactiveNode intertransacts. 
    %   Those Neighbors that are also members of the transactive network
    %   are obligated to negotiate via transactive signals, and these
    %   Neighbors are indicated by setting the corresponding NeighborModel
    %   "transactive" parameter to TRUE.
    
    %   VERSION DATE    AUTHOR          CHANGE
    %   0.1     2017-11 DJ Hammerstrom  Original draft
    
    properties
        model %cross reference to the corresponding NeighborModel object
    end
    
    methods
    end
    
end

