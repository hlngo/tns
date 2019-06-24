function [ verts ] = prod_cost_2_verts( obj, ti )
%PROD_COST_2_VERTS() Convert production-cost formula to vertices (See
%struct Vertex)
%   obj - neighbor model or asset model object. This object is expected to
%         have a set of cost coefficients from which a pair of vertices can
%         be created.
%   ti - active time interval

if ~isa(obj,NeighborModel) && ~isa(obj,LocalAssetModel)
    disp([obj.name, ' is neither a NeighborModel nor a LocalAssetModel.']);
    return;
end

[~,a1,a2] = findobj(obj.costParameters,'timeInterval',ti);
lf = obj.object.lossFactor; %NOT YET AN ASSET PROPERTY!
lf = lf.value; 

pmin = obj.object.minimumPower;
pmax = obj.object.maximumPower;

cmin = a1 + 0.5 * (a2 + lf) * pmin;
cmax = a1 + 0.5 * (a2 + lf) * pmax;

verts = [Vertex(cmin,cmin,pmin),Vertex(cmax,cmax,pmax)];

end

