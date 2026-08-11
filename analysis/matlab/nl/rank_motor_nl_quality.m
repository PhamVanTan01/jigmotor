function result = rank_motor_nl_quality(fileGroups)
%RANK_MOTOR_NL_QUALITY Rank motors from best to worst NL, pooling every
%   valid official sweep available per motor (across however many jig
%   groups are supplied) and reporting bootstrap 95% CI.
%
%   Because NL_RobustP2P_Deg is known to be jig-confounded (see
%   docs/nl-extreme-angle-cross-jig-test33-assessment.md and
%   docs/cross_jig_measurement_analysis.md: A36 is the stable "motor
%   signature" harmonic, largely jig-invariant, while the low-order
%   harmonics that drive NL/RMS_AC swing a lot with jig/mount/drive), this
%   ranks motors TWO ways and reports where they disagree:
%
%   1. By mean NL_RobustP2P_Deg -- what you would actually measure on
%      whatever jig each motor happened to run on. Practical, but a motor
%      tested only on a "harder" jig can look worse than it intrinsically
%      is.
%   2. By mean A36_Deg -- the harmonic tied to the motor's own electrical
%      structure, empirically stable across jigs in every cross-jig
%      comparison run so far. A better (if indirect) proxy for intrinsic
%      motor quality when motors were not all tested on the same jig.
%
%   A motor that ranks badly on BOTH is the stronger candidate for a real
%   motor-side defect; a motor that ranks badly on NL but fine on A36 is
%   more likely explained by which jig it was tested on, not the motor
%   itself -- do not treat NL rank alone as a motor quality verdict.
%
%   result = RANK_MOTOR_NL_QUALITY(fileGroups) takes the same fileGroups
%   struct array as analyze_nl_extreme_angles.m (fields Files, MotorId,
%   JigId) and returns a table sorted best-to-worst by mean NL, plus the
%   per-motor-per-jig breakdown for transparency.

arguments
    fileGroups (1,:) struct
end

perJigRows = table();
for groupIndex = 1:numel(fileGroups)
    group = fileGroups(groupIndex);
    sweeps = parse_nl_log(group.Files);
    for sweepIndex = 1:numel(sweeps)
        sweep = sweeps(sweepIndex);
        if ~isfield(sweep, "Meta") || isempty(fieldnames(sweep.Meta))
            continue
        end
        if ~valid_official_sweep_for_ranking(sweep)
            continue
        end
        metric = compute_nl_sweep_metrics(sweep);
        row = struct2table(metric);
        row.MotorId = group.MotorId;
        row.JigId = group.JigId;
        if isempty(perJigRows)
            perJigRows = row;
        else
            perJigRows = [perJigRows; row]; %#ok<AGROW>
        end
    end
end

if isempty(perJigRows)
    error("RankMotorNL:NoRuns", "No valid official NL sweeps parsed from the given file groups.");
end

motorIds = unique(perJigRows.MotorId, "stable");
nMotors = numel(motorIds);
motor = motorIds(:);
n = zeros(nMotors, 1);
nlMean = NaN(nMotors, 1);
nlCiLow = NaN(nMotors, 1);
nlCiHigh = NaN(nMotors, 1);
a36Mean = NaN(nMotors, 1);
rmsAcMean = NaN(nMotors, 1);
closureMean = NaN(nMotors, 1);
jigsUsed = strings(nMotors, 1);
for index = 1:nMotors
    subset = perJigRows(perJigRows.MotorId == motorIds(index), :);
    n(index) = height(subset);
    nlStats = bootstrap_mean_ci(subset.NL_RobustP2P_Deg);
    nlMean(index) = nlStats.Mean;
    nlCiLow(index) = nlStats.CI95(1);
    nlCiHigh(index) = nlStats.CI95(2);
    a36Mean(index) = mean(subset.A36_Deg);
    rmsAcMean(index) = mean(subset.RMS_AC_Deg);
    closureMean(index) = mean(subset.ClosureErrorDeg);
    jigsUsed(index) = strjoin(unique(subset.JigId), "+");
end

nlRank = (1:nMotors)';
[~, order] = sort(nlMean);
nlRankOf = zeros(nMotors, 1);
nlRankOf(order) = nlRank;

[~, a36Order] = sort(a36Mean);
a36RankOf = zeros(nMotors, 1);
a36RankOf(a36Order) = (1:nMotors)';

rankShift = a36RankOf - nlRankOf;

leaderboard = table(motor, n, nlMean, nlCiLow, nlCiHigh, nlRankOf, a36Mean, a36RankOf, ...
    rankShift, rmsAcMean, closureMean, jigsUsed, VariableNames=...
    ["Motor", "N", "NL_Mean_Deg", "NL_CI95_Low", "NL_CI95_High", "NL_Rank", ...
    "A36_Mean_Deg", "A36_Rank", "RankShift_A36MinusNL", "RMS_AC_Mean_Deg", ...
    "Closure_Mean_Deg", "JigsUsed"]);
leaderboard = sortrows(leaderboard, "NL_Rank");

result = struct(Leaderboard = leaderboard, PerJigRuns = perJigRows);

fprintf("=== Motor NL quality leaderboard: %d motors, %d sweeps ===\n", nMotors, height(perJigRows));
fprintf("Sorted best (lowest NL) to worst (highest NL). RankShift = A36 rank - NL rank:\n");
fprintf("  0 or small  -> NL and A36 agree, ranking trustworthy\n");
fprintf("  large       -> NL rank likely distorted by which jig this motor happened to run on\n\n");
disp(leaderboard(:, ["Motor", "N", "NL_Mean_Deg", "NL_CI95_Low", "NL_CI95_High", ...
    "NL_Rank", "A36_Rank", "RankShift_A36MinusNL", "JigsUsed"]));

suspectMask = abs(leaderboard.RankShift_A36MinusNL) >= 2;
if any(suspectMask)
    fprintf("WARNING: %d/%d motors show NL rank vs A36 rank disagreement >=2 positions -- their NL\n", ...
        sum(suspectMask), nMotors);
    fprintf("  rank is likely jig-confounded, not purely a motor-quality signal: %s\n", ...
        strjoin(cellstr(leaderboard.Motor(suspectMask)), ", "));
end
end

function stats = bootstrap_mean_ci(values)
values = values(:);
n = numel(values);
stats = struct(Mean = NaN, CI95 = [NaN, NaN]);
if n == 0
    return
end
stats.Mean = mean(values);
if n < 3
    stats.CI95 = [stats.Mean, stats.Mean];
    return
end
rng(12345, "twister");
numBoot = 5000;
bootMeans = zeros(numBoot, 1);
for bootIndex = 1:numBoot
    sampleIndex = randi(n, n, 1);
    bootMeans(bootIndex) = mean(values(sampleIndex));
end
sortedBoot = sort(bootMeans);
stats.CI95 = [prctile_manual(sortedBoot, 2.5), prctile_manual(sortedBoot, 97.5)];
end

function p = prctile_manual(sortedValues, percentile)
n = numel(sortedValues);
rank = percentile / 100 * (n - 1) + 1;
lowIndex = floor(rank);
highIndex = ceil(rank);
frac = rank - lowIndex;
p = sortedValues(lowIndex) * (1 - frac) + sortedValues(highIndex) * frac;
end

function valid = valid_official_sweep_for_ranking(sweep)
valid = false;
if isfield(sweep.Meta, "RunRole") && string(sweep.Meta.RunRole) ~= "OFFICIAL"
    return
end
if ~isfield(sweep.Meta, "AnalysisPoints") || str2double(sweep.Meta.AnalysisPoints) <= 0
    return
end
if ~isfield(sweep.Meta, "EligibleForStatistics") || string(sweep.Meta.EligibleForStatistics) ~= "1"
    return
end
if ~isfield(sweep.Meta, "MeasurementValid") || string(sweep.Meta.MeasurementValid) ~= "1"
    return
end
if ~isfield(sweep, "END") || ~isfield(sweep.END, "Status") || string(sweep.END.Status) ~= "VALID"
    return
end
analysisPoints = str2double(sweep.Meta.AnalysisPoints);
presentCount = sum(sweep.Data.Index < analysisPoints);
if presentCount ~= analysisPoints
    return
end
valid = true;
end
