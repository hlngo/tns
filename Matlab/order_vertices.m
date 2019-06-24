function [ ov ] = order_vertices( uv )
%ORDER_VERTICES Order an array of production vertices by price and power
% uv  - input list of unordered ProdVertices (see struct Vertex)
% ov  - output list of ordered ProdVertices (see struct Vertex)
% ind - sorting index

%   Sort first based on power value
    [~,ind] = sort([uv.power]);
    ov = uv(ind);
    
%   Sort next based on price value
    [~,ind] = sort([ov.marginalPrice]);
    ov = ov(ind);  
    
end                                             % function order_vertices()

