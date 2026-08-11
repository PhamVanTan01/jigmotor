function result = analyze_full_curve_quality(fileGroups, toleranceDeg)
%ANALYZE_FULL_CURVE_QUALITY Evaluate motors from the FULL 360-point error
%   curve, not a handful of scalar reductions.
%
%   Every existing NL metric in this project looks at only part of the
%   curve: NL_RobustP2P_Deg uses 10/360 points (top-5+bottom-5),
%   ClosureErrorDeg uses a single point, and even the harmonic-spectrum
%   tools (compute_harmonic_spectrum.m) reduce the curve to one number per
%   frequency. RMS_AC_Deg already IS a full-curve statistic, but it is
%   still a single scalar -- it cannot tell you WHERE along the sweep a
%   motor is bad, only THAT it is, on average.
%
%   This computes, from the full per-point batch-mean curve
%   (build_nl_group_curve.m's MeanError/SdError, both already length-360
%   vectors -- this tool is the first to actually USE every point of them
%   instead of just their extremes):
%
%   1. FractionWithinToleranceDeg: what fraction of the 360 points have
%      |centered error| <= toleranceDeg -- "how much of the curve is
%      actually fine", a question no existing metric answers (NL only
%      tells you about the worst 10 points; a motor could fail NL badly
%      while being fine everywhere else, or pass NL while being mediocre
%      almost everywhere -- these look identical to NL_RobustP2P alone).
%   2. FullCurveRmsDeg: RMS over all 360 points (cross-checks RMS_AC_Deg).
%   3. MeanSdDeg: average per-point repeatability (SD across runs at each
%      point, averaged over all 360 points) -- noise/instability, distinct
%      from the mean error's own shape.
%   4. Contiguous out-of-tolerance regions (circular, wraps across the
%      360/0 boundary): angular start/length/peak of each run of adjacent
%      points exceeding toleranceDeg, sorted longest-first. A real
%      localized physical defect (a bent shaft segment, a mounting
%      eccentricity, a sticky spot) shows up as a persistent multi-point
%      REGION, not an isolated single-point spike -- this is the one
%      thing top-5/bottom-5 extraction structurally cannot distinguish
%      (an isolated 1-point spike and a genuine 20-point-wide problem
%      region can contribute the same NL_RobustP2P value).
%
%   result = ANALYZE_FULL_CURVE_QUALITY(fileGroups, toleranceDeg)
%   fileGroups: same struct array as analyze_nl_extreme_angles.m (Files,
%   MotorId, JigId); pools across every jig group given per motor, same
%   convention as rank_motor_nl_quality.m. toleranceDeg: the +/- band
%   (around the curve's own mean) a point must stay inside to count as
%   "fine"; default 0.5 deg is a round, uncalibrated starting point, not a
%   validated spec limit -- pick a value that means something for your use
%   case and pass it explicitly.

arguments
    fileGroups (1,:) struct
    toleranceDeg (1,1) double = 0.5
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
nMotors = numel(motorIds);
motor = motorIds(:);
n = zeros(nMotors, 1);
totalRuns = zeros(nMotors, 1);
fractionWithin = NaN(nMotors, 1);
fullCurveRms = NaN(nMotors, 1);
meanSd = NaN(nMotors, 1);
worstRegionLengthDeg = zeros(nMotors, 1);
worstRegionStartDeg = NaN(nMotors, 1);
worstRegionPeakDeg = NaN(nMotors, 1);
regionCount = zeros(nMotors, 1);
allRegions = cell(nMotors, 1);

for index = 1:nMotors
    motorGroups = groups([groups.MotorId] == motorIds(index));
    % Pool point-by-point across every jig group this motor has, weighted
    % by each group's own run count -- a straightforward run-weighted
    % combination, not a jig-blind average that hides which jig
    % contributed what (JigsUsed-style transparency is left to the caller
    % via `groups`/`motorGroups` in the returned struct if needed).
    npts = motorGroups(1).AnalysisPoints;
    weightedSum = zeros(npts, 1);
    weightTotal = 0;
    for gi = 1:numel(motorGroups)
        w = motorGroups(gi).EligibleRuns;
        weightedSum = weightedSum + w * motorGroups(gi).MeanError;
        weightTotal = weightTotal + w;
    end
    meanError = weightedSum / weightTotal;
    sdError = mean(horzcat(motorGroups.SdError), 2);

    n(index) = npts;
    totalRuns(index) = weightTotal;
    centered = meanError - mean(meanError);
    isWithin = abs(centered) <= toleranceDeg;
    fractionWithin(index) = sum(isWithin) / npts;
    fullCurveRms(index) = sqrt(mean(centered.^2));
    meanSd(index) = mean(sdError);

    regions = find_circular_bad_regions(centered, toleranceDeg, npts);
    allRegions{index} = regions;
    regionCount(index) = numel(regions);
    if ~isempty(regions)
        [~, worstIdx] = max([regions.LengthDeg]);
        worstRegionLengthDeg(index) = regions(worstIdx).LengthDeg;
        worstRegionStartDeg(index) = regions(worstIdx).StartDeg;
        worstRegionPeakDeg(index) = regions(worstIdx).PeakDeg;
    end
end

leaderboard = table(motor, n, totalRuns, fractionWithin, fullCurveRms, meanSd, ...
    regionCount, worstRegionLengthDeg, worstRegionStartDeg, worstRegionPeakDeg, ...
    VariableNames=["Motor", "AnalysisPoints", "TotalRuns", "FractionWithinTolerance", ...
    "FullCurveRmsDeg", "MeanSdDeg", "OutOfToleranceRegionCount", ...
    "WorstRegionLengthDeg", "WorstRegionStartDeg", "WorstRegionPeakDeg"]);
leaderboard = sortrows(leaderboard, "FractionWithinTolerance", "descend");

result = struct(Leaderboard = leaderboard, Groups = groups, Regions = allRegions, ...
    ToleranceDeg = toleranceDeg);

fprintf("=== Full-curve (360-point) motor quality: tolerance=+/-%.3f deg ===\n", toleranceDeg);
fprintf("Sorted best (most of the curve within tolerance) to worst:\n\n");
disp(leaderboard(:, ["Motor", "TotalRuns", "FractionWithinTolerance", "FullCurveRmsDeg", ...
    "MeanSdDeg", "OutOfToleranceRegionCount", "WorstRegionLengthDeg", "WorstRegionStartDeg"]));

fprintf("\n-- Out-of-tolerance regions per motor (longest first) --\n");
for rowIndex = 1:height(leaderboard)
    motorId = leaderboard.Motor(rowIndex);
    regions = allRegions{motor == motorId};
    if isempty(regions)
        fprintf("%s: none -- entire curve within tolerance\n", motorId);
        continue
    end
    [~, order] = sort([regions.LengthDeg], "descend");
    regions = regions(order);
    fprintf("%s: %d region(s)\n", motorId, numel(regions));
    for r = 1:min(3, numel(regions))
        fprintf("  #%d: start=%.1f deg  length=%.1f deg  peak=%+.3f deg (at %.1f deg)\n", ...
            r, regions(r).StartDeg, regions(r).LengthDeg, regions(r).PeakDeg, ...
            regions(r).PeakIndex * 360 / leaderboard.AnalysisPoints(rowIndex));
    end
end
end

function regions = find_circular_bad_regions(centered, toleranceDeg, n)
%FIND_CIRCULAR_BAD_REGIONS Contiguous runs of |centered|>toleranceDeg on a
%   CIRCULAR index (wraps 360->0), so a region straddling the sweep
%   boundary is reported as one region, not two.
isBad = abs(centered) > toleranceDeg;
regions = struct("StartIndex", {}, "LengthPoints", {}, "StartDeg", {}, ...
    "LengthDeg", {}, "PeakDeg", {}, "PeakIndex", {});
if ~any(isBad)
    return
end
if all(isBad)
    [peakVal, peakIdx] = max(abs(centered));
    regions(1) = struct("StartIndex", 0, "LengthPoints", n, "StartDeg", 0, ...
        "LengthDeg", 360, "PeakDeg", sign(centered(peakIdx)) * peakVal, ...
        "PeakIndex", peakIdx - 1);
    return
end
% Rotate so index 0 of the rotated view is guaranteed NOT bad -- removes
% the wrap-around case from the run-finding loop entirely.
firstGood = find(~isBad, 1, "first");
rotation = firstGood - 1;
rotatedBad = isBad(mod((0:n - 1) + rotation, n) + 1);
rotatedCentered = centered(mod((0:n - 1) + rotation, n) + 1);

index = 1;
while index <= n
    if rotatedBad(index)
        runStart = index;
        while index <= n && rotatedBad(index)
            index = index + 1;
        end
        runLength = index - runStart;
        runIndices = runStart:(index - 1);
        [peakVal, peakLocalIdx] = max(abs(rotatedCentered(runIndices)));
        peakRotatedIndex = runIndices(peakLocalIdx);
        startOriginalIndex = mod(runStart - 1 + rotation, n);
        peakOriginalIndex = mod(peakRotatedIndex - 1 + rotation, n);
        regions(end + 1) = struct( ...  %#ok<AGROW>
            "StartIndex", startOriginalIndex, "LengthPoints", runLength, ...
            "StartDeg", startOriginalIndex * 360 / n, "LengthDeg", runLength * 360 / n, ...
            "PeakDeg", sign(rotatedCentered(peakRotatedIndex)) * peakVal, ...
            "PeakIndex", peakOriginalIndex);
    else
        index = index + 1;
    end
end
end
