function result = analyze_cross_jig_point_delta(fileGroups, deltaThresholdDeg, useShift)
%ANALYZE_CROSS_JIG_POINT_DELTA Point-by-point (all 360 points, not just
%   the 10 extremes NL_RobustP2P uses, and not reduced to a handful of
%   harmonic orders) comparison of two jigs' batch-mean error curve for
%   the SAME motor -- answers "at which specific angles does the NL
%   difference between JIG A and JIG B actually come from", by finding
%   CONTIGUOUS regions where the two jigs' curves diverge, the same way
%   analyze_full_curve_quality.m finds contiguous out-of-tolerance regions
%   within a single curve, applied here to the cross-jig DELTA curve
%   instead.
%
%   A broad, contiguous diverging region across many adjacent points
%   points at a real physical difference (mounting/alignment offset,
%   sector-dependent effect, a jig-specific mechanical asymmetry); narrow,
%   scattered single-point divergences are more consistent with ordinary
%   run-to-run noise riding on an otherwise well-matched curve shape.
%
%   result = ANALYZE_CROSS_JIG_POINT_DELTA(fileGroups, deltaThresholdDeg,
%   useShift) fileGroups: same struct array as analyze_nl_extreme_angles.m
%   (Files, MotorId, JigId), exactly two jig groups per motor.
%   deltaThresholdDeg: |delta| a point must exceed to count as
%   "diverging" for region detection (default 0.3 deg, an uncalibrated
%   round number -- pick one that means something for your use case).
%   useShift: "zero" (default -- per docs/nl-extreme-angle-cross-jig-
%   test33-assessment.md, 0-degree sweep-relative shift is already the
%   best or near-best alignment for most products, so differencing
%   without shifting is usually the right comparison) or "best" (align
%   using compare_nl_group_curves.m's own best-fit circular shift first --
%   use for a motor like P07 that is flagged sector/orientation-confounded
%   at zero shift).

arguments
    fileGroups (1,:) struct
    deltaThresholdDeg (1,1) double = 0.3
    useShift (1,1) string {mustBeMember(useShift, ["zero", "best"])} = "zero"
end

groups = struct([]);
for index = 1:numel(fileGroups)
    g = build_nl_group_curve(fileGroups(index).Files, fileGroups(index).MotorId, ...
        fileGroups(index).JigId, 5);
    if isempty(groups)
        groups = g;
    else
        groups(end + 1) = g; %#ok<AGROW>
    end
end

motorIds = unique([groups.MotorId], "stable");
nMotors = 0;
motor = strings(0, 1);
jigA = strings(0, 1);
jigB = strings(0, 1);
shiftUsedDeg = [];
meanAbsDelta = [];
rmsDelta = [];
maxAbsDelta = [];
maxAbsDeltaAtDeg = [];
regionCount = [];
worstRegionLengthDeg = [];
worstRegionStartDeg = [];
allRegions = {};
allDeltaCurves = {};

for m = 1:numel(motorIds)
    motorGroups = groups([groups.MotorId] == motorIds(m));
    if numel(motorGroups) ~= 2
        continue
    end
    jigIds = [motorGroups.JigId];
    [~, sortOrder] = sort(jigIds);
    motorGroups = motorGroups(sortOrder);
    a = motorGroups(1);
    b = motorGroups(2);
    n = a.AnalysisPoints;

    shiftPoints = 0;
    if useShift == "best"
        comparison = compare_nl_group_curves(a, b);
        shiftPoints = comparison.BestShiftPoints;
    end
    shiftedB = b.MeanError(mod((0:n - 1) + shiftPoints, n) + 1);
    delta = shiftedB - a.MeanError;

    nMotors = nMotors + 1;
    motor(end + 1, 1) = motorIds(m); %#ok<AGROW>
    jigA(end + 1, 1) = a.JigId; %#ok<AGROW>
    jigB(end + 1, 1) = b.JigId; %#ok<AGROW>
    shiftUsedDeg(end + 1, 1) = shiftPoints * 360 / n; %#ok<AGROW>
    meanAbsDelta(end + 1, 1) = mean(abs(delta)); %#ok<AGROW>
    rmsDelta(end + 1, 1) = sqrt(mean(delta.^2)); %#ok<AGROW>
    [~, worstIdx] = max(abs(delta));
    maxAbsDelta(end + 1, 1) = delta(worstIdx); %#ok<AGROW>
    maxAbsDeltaAtDeg(end + 1, 1) = (worstIdx - 1) * 360 / n; %#ok<AGROW>

    regions = find_circular_threshold_regions(delta, deltaThresholdDeg, n);
    allRegions{end + 1} = regions; %#ok<AGROW>
    allDeltaCurves{end + 1} = delta; %#ok<AGROW>
    regionCount(end + 1, 1) = numel(regions); %#ok<AGROW>
    if isempty(regions)
        worstRegionLengthDeg(end + 1, 1) = 0; %#ok<AGROW>
        worstRegionStartDeg(end + 1, 1) = NaN; %#ok<AGROW>
    else
        [~, worstRegionIdx] = max([regions.LengthDeg]);
        worstRegionLengthDeg(end + 1, 1) = regions(worstRegionIdx).LengthDeg; %#ok<AGROW>
        worstRegionStartDeg(end + 1, 1) = regions(worstRegionIdx).StartDeg; %#ok<AGROW>
    end
end

summary = table(motor, jigA, jigB, shiftUsedDeg, meanAbsDelta, rmsDelta, ...
    maxAbsDelta, maxAbsDeltaAtDeg, regionCount, worstRegionLengthDeg, worstRegionStartDeg, ...
    VariableNames=["Motor", "JigA", "JigB", "ShiftUsedDeg", "MeanAbsDeltaDeg", "RmsDeltaDeg", ...
    "MaxDeltaDeg", "MaxDeltaAtDeg", "RegionCount", "WorstRegionLengthDeg", "WorstRegionStartDeg"]);
summary = sortrows(summary, "RmsDeltaDeg", "descend");

result = struct(Summary = summary, Regions = allRegions, DeltaCurves = allDeltaCurves, ...
    DeltaThresholdDeg = deltaThresholdDeg, UseShift = useShift);

fprintf("=== Cross-jig point-by-point delta (all 360 points, threshold=+/-%.2f deg, shift=%s) ===\n", ...
    deltaThresholdDeg, useShift);
disp(summary);

fprintf("\n-- Diverging regions per motor (longest first) --\n");
for rowIndex = 1:height(summary)
    motorId = summary.Motor(rowIndex);
    regions = allRegions{motor == motorId};
    if isempty(regions)
        fprintf("%s: none -- curves match within threshold everywhere\n", motorId);
        continue
    end
    [~, order] = sort([regions.LengthDeg], "descend");
    regions = regions(order);
    fprintf("%s: %d region(s)\n", motorId, numel(regions));
    for r = 1:min(3, numel(regions))
        fprintf("  #%d: start=%.1f deg  length=%.1f deg  peak delta=%+.3f deg (at %.1f deg)\n", ...
            r, regions(r).StartDeg, regions(r).LengthDeg, regions(r).PeakDeg, regions(r).PeakAtDeg);
    end
end
end

function regions = find_circular_threshold_regions(delta, thresholdDeg, n)
%FIND_CIRCULAR_THRESHOLD_REGIONS Same circular contiguous-run logic as
%   analyze_full_curve_quality.m's find_circular_bad_regions, duplicated
%   locally (this project's convention: small self-contained per-file
%   helpers rather than a shared utility module) -- operates directly on
%   a delta curve instead of a mean-centered single curve.
isOver = abs(delta) > thresholdDeg;
regions = struct("StartIndex", {}, "LengthPoints", {}, "StartDeg", {}, ...
    "LengthDeg", {}, "PeakDeg", {}, "PeakIndex", {}, "PeakAtDeg", {});
if ~any(isOver)
    return
end
if all(isOver)
    [peakVal, peakIdx] = max(abs(delta));
    regions(1) = struct("StartIndex", 0, "LengthPoints", n, "StartDeg", 0, ...
        "LengthDeg", 360, "PeakDeg", sign(delta(peakIdx)) * peakVal, "PeakIndex", peakIdx - 1, ...
        "PeakAtDeg", (peakIdx - 1) * 360 / n);
    return
end
firstGood = find(~isOver, 1, "first");
rotation = firstGood - 1;
rotatedOver = isOver(mod((0:n - 1) + rotation, n) + 1);
rotatedDelta = delta(mod((0:n - 1) + rotation, n) + 1);

index = 1;
while index <= n
    if rotatedOver(index)
        runStart = index;
        while index <= n && rotatedOver(index)
            index = index + 1;
        end
        runLength = index - runStart;
        runIndices = runStart:(index - 1);
        [peakVal, peakLocalIdx] = max(abs(rotatedDelta(runIndices)));
        peakRotatedIndex = runIndices(peakLocalIdx);
        startOriginalIndex = mod(runStart - 1 + rotation, n);
        peakOriginalIndex = mod(peakRotatedIndex - 1 + rotation, n);
        regions(end + 1) = struct( ...  %#ok<AGROW>
            "StartIndex", startOriginalIndex, "LengthPoints", runLength, ...
            "StartDeg", startOriginalIndex * 360 / n, "LengthDeg", runLength * 360 / n, ...
            "PeakDeg", sign(rotatedDelta(peakRotatedIndex)) * peakVal, ...
            "PeakIndex", peakOriginalIndex, "PeakAtDeg", peakOriginalIndex * 360 / n);
    else
        index = index + 1;
    end
end
end
