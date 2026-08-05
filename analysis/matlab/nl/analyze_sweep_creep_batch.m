function result = analyze_sweep_creep_batch(filePaths, labels)
%ANALYZE_SWEEP_CREEP_BATCH Pool ENABLE_SWEEP_POINT_CREEP telemetry across
%   many V5.x logs to rank which sweep points actually struggle, from the
%   real per-point firmware telemetry (SWEEP_CREEP_POINT/STEP) rather than
%   the |MOTION.PositionErrorRaw| proxy analysis-out/p08-jig7-v4-creep-
%   difficulty-spatial-analysis.md had to use before this telemetry
%   existed (see docs/session-summary-2026-08-05.md sections 3-7). This is
%   the direct-evidence input V5.4 "generalized targeted fine landing"
%   needs: which points beyond the hardcoded point 66 also see crossing/
%   stick-slip/budget-exceeded, pooled across every V5.1/V5.2/V5.3 run
%   captured so far (parse_sweep_creep_log.m tolerates the schema
%   differences between those firmware versions).
%
%   result = ANALYZE_SWEEP_CREEP_BATCH(filePaths, labels) labels defaults
%   to each file's own basename (one label per file; pass the same label
%   to pool multiple files into one group, matching
%   analyze_nl_stability_batch.m's convention). Returns a struct:
%     Points        -- every SWEEP_CREEP_POINT row across all files,
%                       tagged with Label/SourceFile.
%     Steps         -- every SWEEP_CREEP_STEP row (only present for
%                       traced points, e.g. FineTargetPoint), tagged the
%                       same way.
%     SweepSummary  -- every END-record per-sweep rollup, tagged the
%                       same way.
%     ByPoint       -- one row per distinct Point index (0-359) seen
%                       anywhere in the pool, sorted by TroubleScore
%                       descending: N (times corrected), fraction with
%                       Result~=OK, RecoveryAttempted rate, StickSlipJump
%                       rate, FineLandingAttempted rate, mean/max
%                       |FinalGapRaw|, mean Iterations, TroubleScore
%                       (fraction not OK -- the single ranking metric).
%     ByLabel       -- one row per label/file: N points, IntegrityValid
%                       rate (from SweepSummary), TargetCrossed/
%                       RecoveryRecrossed totals -- lets V5.1/V5.2/V5.3
%                       stability be compared at a glance.

arguments
    filePaths (1,:) string
    labels (1,:) string = strings(1, 0)
end

if isempty(labels)
    labels = fullfile_basenames(filePaths);
elseif numel(labels) ~= numel(filePaths)
    error("SweepCreep:LabelCount", ...
        "labels (%d) must match filePaths (%d) in count.", numel(labels), numel(filePaths));
end

points = table();
steps = table();
summary = table();
for fileIndex = 1:numel(filePaths)
    parsed = parse_sweep_creep_log(filePaths(fileIndex));
    points = tag_and_append(points, parsed.Points, labels(fileIndex), filePaths(fileIndex));
    steps = tag_and_append(steps, parsed.Steps, labels(fileIndex), filePaths(fileIndex));
    summary = tag_and_append(summary, parsed.SweepSummary, labels(fileIndex), filePaths(fileIndex));
end

if isempty(points)
    error("SweepCreep:NoPoints", "No SWEEP_CREEP_POINT records found in the given files.");
end

byPoint = build_by_point(points);
byLabel = build_by_label(points, summary, labels);

result = struct(Points = points, Steps = steps, SweepSummary = summary, ...
    ByPoint = byPoint, ByLabel = byLabel);

fprintf("=== Sweep-point-creep pool: %d point-rows, %d step-rows, %d sweeps, %d labels ===\n", ...
    height(points), height(steps), height(summary), numel(unique(labels)));
fprintf("-- Top 20 trouble points (by fraction of appearances with Result~=OK) --\n");
disp(byPoint(1:min(20, height(byPoint)), ...
    ["Point","N","TroubleScore","FracRecoveryAttempted","FracStickSlipJump", ...
    "FracFineLandingAttempted","MeanAbsFinalGapRaw","MaxAbsFinalGapRaw"]));
fprintf("-- Per-label integrity summary --\n");
disp(byLabel);
end

function t = tag_and_append(accum, rows, label, sourceFile)
if isempty(rows)
    t = accum;
    return
end
rows.Label = repmat(label, height(rows), 1);
rows.SourceFile = repmat(sourceFile, height(rows), 1);
if isempty(accum)
    t = rows;
else
    t = [accum; rows];
end
end

function byPoint = build_by_point(points)
pointIds = unique(points.Point);
pointIds = pointIds(~isnan(pointIds));
n = numel(pointIds);
Point = pointIds;
N = zeros(n, 1);
TroubleScore = zeros(n, 1);
FracRecoveryAttempted = zeros(n, 1);
FracStickSlipJump = zeros(n, 1);
FracFineLandingAttempted = zeros(n, 1);
MeanAbsFinalGapRaw = zeros(n, 1);
MaxAbsFinalGapRaw = zeros(n, 1);
MeanIterations = zeros(n, 1);

for i = 1:n
    subset = points(points.Point == pointIds(i), :);
    N(i) = height(subset);
    TroubleScore(i) = mean(subset.Result ~= "OK");
    FracRecoveryAttempted(i) = safe_frac(subset.RecoveryAttempted);
    FracStickSlipJump(i) = safe_frac(subset.StickSlipJumpDetected);
    FracFineLandingAttempted(i) = safe_frac(subset.FineLandingAttempted);
    MeanAbsFinalGapRaw(i) = mean(abs(subset.FinalGapRaw), "omitnan");
    MaxAbsFinalGapRaw(i) = max(abs(subset.FinalGapRaw));
    MeanIterations(i) = mean(subset.Iterations, "omitnan");
end

byPoint = table(Point, N, TroubleScore, FracRecoveryAttempted, FracStickSlipJump, ...
    FracFineLandingAttempted, MeanAbsFinalGapRaw, MaxAbsFinalGapRaw, MeanIterations);
byPoint = sortrows(byPoint, "TroubleScore", "descend");
end

function frac = safe_frac(values)
values = values(~isnan(values));
if isempty(values)
    frac = NaN;
else
    frac = mean(values == 1);
end
end

function byLabel = build_by_label(points, summary, labels)
labelNames = unique(labels, "stable");
Label = labelNames(:);
NPointRows = zeros(numel(labelNames), 1);
NSweeps = zeros(numel(labelNames), 1);
IntegrityValidRatePct = NaN(numel(labelNames), 1);
TotalTargetCrossed = NaN(numel(labelNames), 1);
TotalRecoveryRecrossed = NaN(numel(labelNames), 1);
TotalStickSlipJump = NaN(numel(labelNames), 1);

for i = 1:numel(labelNames)
    NPointRows(i) = sum(points.Label == labelNames(i));
    if ~isempty(summary)
        subset = summary(summary.Label == labelNames(i), :);
        NSweeps(i) = height(subset);
        if height(subset) > 0
            IntegrityValidRatePct(i) = mean(subset.SweepPointCreepIntegrityValid == 1) * 100.0;
            TotalTargetCrossed(i) = sum(subset.SweepPointCreepTargetCrossed, "omitnan");
            TotalRecoveryRecrossed(i) = sum(subset.SweepPointCreepRecoveryRecrossed, "omitnan");
            TotalStickSlipJump(i) = sum(subset.SweepPointCreepStickSlipJump, "omitnan");
        end
    end
end

byLabel = table(Label, NPointRows, NSweeps, IntegrityValidRatePct, TotalTargetCrossed, ...
    TotalRecoveryRecrossed, TotalStickSlipJump);
end

function names = fullfile_basenames(paths)
names = strings(size(paths));
for index = 1:numel(paths)
    [~, name, ~] = fileparts(paths(index));
    names(index) = string(name);
end
end
