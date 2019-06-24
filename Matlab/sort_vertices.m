function [ spv ] = sort_vertices( pv )
%FUNCTION SORT_VERTICES Sort a list of production vertices
%Accepts a list of production vertices (see struct Vertex) and sorts them
%by increasing price and power.
%
%   INPUTS:
%       pv - an array of production vertices (see struct Vertex)
%   OUTPUTS:
%       spv - the sorted vertion of array pv by increasing price and power

    if ~isa(pv,'Vertex')
        error('Function sort_vertices must act on struct Vertex.');
    end

    %Extract the power property from the Vertex struct.
    pv_pwr = [pv.power];

    %Order the array of production vertices based on power first.
    [~,ind] = sort(pv_pwr);
    pv = pv(ind);

    %Extract the price from the Vertex struct.
    pv_prc = [pv.marginalPrice];

    %Then sort the ProdVertices pv now on price.
    [~,ind] = sort(pv_prc);
    spv = pv(ind);

end

