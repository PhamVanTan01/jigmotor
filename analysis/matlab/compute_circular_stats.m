function stats = compute_circular_stats(valuesRaw, periodRaw)
%COMPUTE_CIRCULAR_STATS Mean, resultant and minimal covering arc.

arguments
    valuesRaw (:,1) double
    periodRaw (1,1) double {mustBePositive}
end

values = mod(valuesRaw(isfinite(valuesRaw)), periodRaw);
if isempty(values)
    stats = struct(MeanRaw=NaN, ResultantR=NaN, RangeRaw=NaN, ...
        MaxDistanceRaw=NaN, Count=0);
    return
end

angles = 2*pi*values/periodRaw;
resultant = mean(exp(1i*angles));
meanAngle = mod(angle(resultant), 2*pi);
meanRaw = meanAngle*periodRaw/(2*pi);

sorted = sort(values);
wrapGaps = diff([sorted; sorted(1)+periodRaw]);
rangeRaw = periodRaw - max(wrapGaps);
delta = abs(mod(values-meanRaw+periodRaw/2, periodRaw)-periodRaw/2);

stats = struct(MeanRaw=meanRaw, ResultantR=abs(resultant), ...
    RangeRaw=rangeRaw, MaxDistanceRaw=max(delta), Count=numel(values));
end
