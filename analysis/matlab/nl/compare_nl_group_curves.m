function result = compare_nl_group_curves(a, b)
%COMPARE_NL_GROUP_CURVES MATLAB counterpart to tools/analyze_nl_extreme_angles.py's
%   compare_groups(): circular cross-correlation to find the best sweep-
%   relative alignment between two group curves (e.g. same motor on two
%   different jigs), best-matching circular distance between their extreme
%   points after alignment, and the top-5/bottom-5/robust-NL deltas
%   computed as batch-averages of each run's OWN top-5/bottom-5 mean --
%   this preserves RobustNLDelta = Top5Delta - Bottom5Delta exactly,
%   matching the per-run firmware metric identity even when which points
%   fall in the tail changes.
%
%   MA600 raw zero is local to each sensor/jig -- BestShiftDeg is the
%   sweep-relative circular alignment that best matches the two curves'
%   SHAPE, not a claim that equal raw codes on two jigs are the same
%   physical angle.

arguments
    a struct
    b struct
end

if a.AnalysisPoints ~= b.AnalysisPoints
    error("NlExtremeAngles:MismatchedAnalysisPoints", ...
        "%s: cannot compare N=%d and N=%d", a.MotorId, a.AnalysisPoints, b.AnalysisPoints);
end
n = a.AnalysisPoints;

corr = NaN(n, 1);
for shift = 0:n - 1
    shiftedB = b.MeanError(mod((0:n - 1) + shift, n) + 1);
    corr(shift + 1) = pearson_corr(a.MeanError, shiftedB);
end
[sortedCorr, sortedShift] = sort(corr, "descend");
bestShift = sortedShift(1) - 1;
bestCorr = sortedCorr(1);
secondShift = sortedShift(2) - 1;
secondCorr = sortedCorr(2);
alignedB = b.MeanError(mod((0:n - 1) + bestShift, n) + 1);

mappedTopB = mod(b.TopIndices - bestShift, n);
mappedBottomB = mod(b.BottomIndices - bestShift, n);
[topMeanDist, topMaxDist] = best_set_matching(a.TopIndices, mappedTopB, n);
[bottomMeanDist, bottomMaxDist] = best_set_matching(a.BottomIndices, mappedBottomB, n);

top5MeanA = mean(a.RunTopMeans);
top5MeanB = mean(b.RunTopMeans);
bottom5MeanA = mean(a.RunBottomMeans);
bottom5MeanB = mean(b.RunBottomMeans);
robustA = top5MeanA - bottom5MeanA;
robustB = top5MeanB - bottom5MeanB;

result = struct( ...
    MotorId = a.MotorId, JigA = a.JigId, JigB = b.JigId, AnalysisPoints = n, ...
    RunsA = a.EligibleRuns, RunsB = b.EligibleRuns, ...
    ZeroShiftCorrelation = pearson_corr(a.MeanError, b.MeanError), ...
    BestShiftDeg = bestShift * 360.0 / n, BestShiftPoints = bestShift, BestShiftCorrelation = bestCorr, ...
    SecondShiftDeg = secondShift * 360.0 / n, SecondShiftCorrelation = secondCorr, ...
    CorrelationMargin = bestCorr - secondCorr, ...
    ShiftsWithin0_001OfBest = sum(bestCorr - corr <= 0.001), ...
    CenteredRmseZeroShiftDeg = centered_rmse(a.MeanError, b.MeanError), ...
    CenteredRmseAlignedDeg = centered_rmse(a.MeanError, alignedB), ...
    Top5MeanADeg = top5MeanA, Top5MeanBDeg = top5MeanB, Top5DeltaBMinusADeg = top5MeanB - top5MeanA, ...
    Bottom5MeanADeg = bottom5MeanA, Bottom5MeanBDeg = bottom5MeanB, ...
    Bottom5DeltaBMinusADeg = bottom5MeanB - bottom5MeanA, ...
    RobustNLADeg = robustA, RobustNLBDeg = robustB, RobustNLDeltaBMinusADeg = robustB - robustA, ...
    Top5MeanDistanceAlignedDeg = topMeanDist * 360.0 / n, ...
    Top5MaxDistanceAlignedDeg = topMaxDist * 360.0 / n, ...
    Bottom5MeanDistanceAlignedDeg = bottomMeanDist * 360.0 / n, ...
    Bottom5MaxDistanceAlignedDeg = bottomMaxDist * 360.0 / n);
end

function r = pearson_corr(x, y)
x = x(:);
y = y(:);
mx = mean(x);
my = mean(y);
dx = x - mx;
dy = y - my;
denom = sqrt(sum(dx.^2) * sum(dy.^2));
if denom == 0
    r = NaN;
else
    r = sum(dx .* dy) / denom;
end
end

function rmse = centered_rmse(a, b)
a = a(:);
b = b(:);
ma = mean(a);
mb = mean(b);
rmse = sqrt(mean(((a - ma) - (b - mb)).^2));
end

function [meanDist, maxDist] = best_set_matching(aIndices, bIndices, n)
% Brute-force minimum (sum, then max) circular distance over all
% permutations of bIndices matched to aIndices -- matches Python's
% itertools.permutations approach exactly (k is always small, e.g. 5 ->
% 120 permutations, tractable).
aIndices = aIndices(:)';
bIndices = bIndices(:)';
k = numel(aIndices);
if k ~= numel(bIndices) || k == 0
    meanDist = NaN;
    maxDist = NaN;
    return
end
permList = perms(bIndices);
bestSum = Inf;
bestMax = Inf;
for permIndex = 1:size(permList, 1)
    permRow = permList(permIndex, :);
    d = circular_distance(aIndices, permRow, n);
    s = sum(d);
    m = max(d);
    if s < bestSum || (s == bestSum && m < bestMax)
        bestSum = s;
        bestMax = m;
    end
end
meanDist = bestSum / k;
maxDist = bestMax;
end

function d = circular_distance(a, b, n)
delta = mod(abs(a - b), n);
d = min(delta, n - delta);
end
