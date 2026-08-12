function result = analyze_sweep_creep_batch(filePaths, labels)
%ANALYZE_SWEEP_CREEP_BATCH Pool ENABLE_SWEEP_POINT_CREEP telemetry across
%   many V5.x logs to rank which sweep points actually struggle, from the
%   real per-point firmware telemetry (SWEEP_CREEP_POINT/STEP) rather than
%   the |MOTION.PositionErrorRaw| proxy analysis-out/p08-jig7-v4-creep-
%   difficulty-spatial-analysis.md had to use before this telemetry
%   existed (see docs/session-summary-2026-08-05.md sections 3-7). This is
%   the direct-evidence input V5.4 "generalized targeted fine landing"
%   needs: which points beyond the hardcoded point 66 also see crossing/
%   stick-slip/budget-exceeded, pooled across every V5.1-V5.4 run
%   captured so far (parse_sweep_creep_log.m tolerates the schema
%   differences between those firmware versions, including V5.5 dynamic
%   BASE-budget escalation fields).
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
%                       RecoveryRecrossed totals -- lets V5.1-V5.4
%                       stability be compared at a glance.
%     PhaseResponseBySweep/ByLabel -- V5.6 signed COARSE/MID/FINE,
%                       COARSE-tail and recovery response efficiency.
%     TelemetryCompleteness -- host-observed POINT/STEP counts checked
%                       against the V5.6 END contract.
%     HoldSamples/HoldResult/HoldByLabel -- V5.7 passive hard-cap hold
%                       evidence and the predeclared mechanism classification.
%     Timing/TimingEnd/TimingByLabel/TimingByPoint -- V5.8 DWT phase
%                       durations and command-to-deadband outcome. Failed
%                       points contribute stop latency, never a fabricated
%                       time-to-target.
%     TerminalByLabel -- V5.9 EXTENDED terminal correction (320-raw
%                       primary cap vs 400-raw hard cap): attempt/success/
%                       suppressed counts, entry gap, gap reduction,
%                       correction raw, iterations, response efficiency
%                       (signed, not clamped). Primary320OnlySuccessRatePct
%                       and Terminal400SuccessRatePct are kept as separate
%                       columns, never blended into one ratio.

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
response = table();
holdConfig = table();
holdSamples = table();
holdResult = table();
timing = table();
timingEnd = table();
for fileIndex = 1:numel(filePaths)
    parsed = parse_sweep_creep_log(filePaths(fileIndex));
    points = tag_and_append(points, parsed.Points, labels(fileIndex), filePaths(fileIndex));
    steps = tag_and_append(steps, parsed.Steps, labels(fileIndex), filePaths(fileIndex));
    response = tag_and_append(response, parsed.Response, labels(fileIndex), filePaths(fileIndex));
    holdConfig = tag_and_append(holdConfig, parsed.HoldConfig, labels(fileIndex), filePaths(fileIndex));
    holdSamples = tag_and_append(holdSamples, parsed.HoldSamples, labels(fileIndex), filePaths(fileIndex));
    holdResult = tag_and_append(holdResult, parsed.HoldResult, labels(fileIndex), filePaths(fileIndex));
    timing = tag_and_append(timing, parsed.Timing, labels(fileIndex), filePaths(fileIndex));
    timingEnd = tag_and_append(timingEnd, parsed.TimingEnd, labels(fileIndex), filePaths(fileIndex));
    summary = tag_and_append(summary, parsed.SweepSummary, labels(fileIndex), filePaths(fileIndex));
end

if isempty(points)
    error("SweepCreep:NoPoints", "No SWEEP_CREEP_POINT records found in the given files.");
end

byPoint = build_by_point(points);
byLabel = build_by_label(points, summary, labels);
phaseResponseBySweep = build_phase_response_by_sweep(response);
phaseResponseByLabel = build_phase_response_by_label(phaseResponseBySweep);
telemetryCompleteness = build_telemetry_completeness(points, steps, summary);
holdByLabel = build_hold_by_label(holdResult, labels);
timingByLabel = build_timing_by_label(timing, timingEnd, labels);
timingByPoint = build_timing_by_point(timing);
terminalByLabel = build_terminal_by_label(points, labels);

result = struct(Points = points, Steps = steps, Response = response, SweepSummary = summary, ...
    HoldConfig = holdConfig, HoldSamples = holdSamples, HoldResult = holdResult, ...
    Timing = timing, TimingEnd = timingEnd, ...
    ByPoint = byPoint, ByLabel = byLabel, ...
    PhaseResponseBySweep = phaseResponseBySweep, ...
    PhaseResponseByLabel = phaseResponseByLabel, ...
    TelemetryCompleteness = telemetryCompleteness, HoldByLabel = holdByLabel, ...
    TimingByLabel = timingByLabel, TimingByPoint = timingByPoint, ...
    TerminalByLabel = terminalByLabel);

fprintf("=== Sweep-point-creep pool: %d point-rows, %d step-rows, %d sweeps, %d labels ===\n", ...
    height(points), height(steps), height(summary), numel(unique(labels)));
fprintf("-- Top 20 trouble points (by fraction of appearances with Result~=OK) --\n");
disp(byPoint(1:min(20, height(byPoint)), ...
    ["Point","N","TroubleScore","FracRecoveryAttempted","FracStickSlipJump", ...
    "FracFineLandingAttempted","MeanAbsFinalGapRaw","MaxAbsFinalGapRaw"]));
fprintf("-- Per-label integrity summary --\n");
disp(byLabel);
if ~isempty(phaseResponseByLabel)
    fprintf("-- V5.6 phase response (signed; negative values are preserved) --\n");
    disp(phaseResponseByLabel);
end
if ~isempty(telemetryCompleteness)
    fprintf("-- V5.6 telemetry completeness --\n");
    disp(telemetryCompleteness);
end
if ~isempty(holdByLabel)
    fprintf("-- V5.7 hard-cap passive-hold classification --\n");
    disp(holdByLabel);
end
if ~isempty(timingByLabel)
    fprintf("-- V5.8 command-response timing (DWT; target time is reached-only) --\n");
    disp(timingByLabel);
    fprintf("-- V5.8 slow/not-reached points by label --\n");
    disp(timingByPoint(1:min(20, height(timingByPoint)), :));
end
if ~isempty(terminalByLabel)
    fprintf("-- V5.9 EXTENDED terminal correction (320-raw primary vs 400-raw terminal, kept separate) --\n");
    disp(terminalByLabel);
end
end

function byLabel = build_timing_by_label(timing, timingEnd, labels)
if isempty(timing)
    byLabel = table();
    return
end
labelNames = unique(labels, "stable");
rows = cell(0, 18);
for i = 1:numel(labelNames)
    subset = timing(timing.Label == labelNames(i) & timing.HasCommand == 1 ...
        & timing.TimingValid == 1, :);
    if isempty(subset)
        continue
    end
    reached = subset.ReachedDeadband == 1;
    stopMs = cycles_to_ms(subset.CommandToStopCycles, subset.ClockHz);
    targetMs = cycles_to_ms(subset.TimeToDeadbandCycles(reached), subset.ClockHz(reached));
    failedStopMs = stopMs(~reached);
    rampMs = cycles_to_ms(subset.RampCycles, subset.ClockHz);
    settleMs = cycles_to_ms(subset.InitialSettleCycles, subset.ClockHz);
    creepMs = cycles_to_ms(subset.CreepCycles, subset.ClockHz);
    legacyMs = cycles_to_ms(subset.LegacyCaptureCycles, subset.ClockHz);
    shadowMs = cycles_to_ms(subset.ShadowCaptureCycles, subset.ClockHz);
    correctionMask = subset.CreepCorrectionCommandRaw > 0;
    efficiency = 1000.0 * (abs(subset.InitialGapRaw(correctionMask)) ...
        - abs(subset.FinalGapRaw(correctionMask))) ...
        ./ subset.CreepCorrectionCommandRaw(correctionMask);
    endSubset = timingEnd(timingEnd.Label == labelNames(i), :);
    complete = ~isempty(endSubset) && all(endSubset.Complete == 1) ...
        && all(endSubset.ExpectedPoints == endSubset.EmittedPoints);
    rows(end + 1, :) = {labelNames(i), numel(unique(subset.SweepID)), ... %#ok<AGROW>
        height(subset), 100.0 * mean(reached), mean(stopMs, "omitnan"), ...
        median(stopMs, "omitnan"), safe_percentile(stopMs, 95), max(stopMs), ...
        mean(targetMs, "omitnan"), safe_percentile(targetMs, 95), ...
        mean(failedStopMs, "omitnan"), mean(rampMs, "omitnan"), ...
        mean(settleMs, "omitnan"), mean(creepMs, "omitnan"), ...
        mean(legacyMs, "omitnan"), mean(shadowMs, "omitnan"), ...
        mean(efficiency, "omitnan"), complete};
end
byLabel = cell2table(rows, 'VariableNames', ["Label","NSweeps","NCommandPoints", ...
    "ReachedDeadbandRatePct","MeanCommandToStopMs","MedianCommandToStopMs", ...
    "P95CommandToStopMs","MaxCommandToStopMs","MeanTimeToDeadbandMs", ...
    "P95TimeToDeadbandMs","MeanFailedStopLatencyMs","MeanRampMs", ...
    "MeanInitialSettleMs","MeanCreepMs","MeanLegacyCaptureMs", ...
    "MeanShadowCaptureMs","MeanCreepEfficiencyPermille","TelemetryComplete"]);
end

function byPoint = build_timing_by_point(timing)
if isempty(timing)
    byPoint = table();
    return
end
timing = timing(timing.HasCommand == 1 & timing.TimingValid == 1, :);
labels = unique(timing.Label, "stable");
rows = cell(0, 8);
for labelIndex = 1:numel(labels)
    labelRows = timing(timing.Label == labels(labelIndex), :);
    pointIds = unique(labelRows.Point);
    for pointIndex = 1:numel(pointIds)
        subset = labelRows(labelRows.Point == pointIds(pointIndex), :);
        stopMs = cycles_to_ms(subset.CommandToStopCycles, subset.ClockHz);
        rows(end + 1, :) = {labels(labelIndex), pointIds(pointIndex), height(subset), ... %#ok<AGROW>
            sum(subset.ReachedDeadband == 0), 100.0 * mean(subset.ReachedDeadband == 1), ...
            mean(stopMs, "omitnan"), safe_percentile(stopMs, 95), max(stopMs)};
    end
end
byPoint = cell2table(rows, 'VariableNames', ["Label","Point","N", ...
    "NNotReached","ReachedRatePct","MeanCommandToStopMs", ...
    "P95CommandToStopMs","MaxCommandToStopMs"]);
byPoint = sortrows(byPoint, ["NNotReached","P95CommandToStopMs"], "descend");
end

function ms = cycles_to_ms(cycles, clockHz)
ms = 1000.0 .* cycles ./ clockHz;
ms(clockHz <= 0) = NaN;
end

function value = safe_percentile(values, percentile)
values = sort(values(~isnan(values)));
if isempty(values)
    value = NaN;
    return
end
if numel(values) == 1
    value = values(1);
    return
end
position = 1 + (numel(values) - 1) * percentile / 100.0;
lower = floor(position);
upper = ceil(position);
if lower == upper
    value = values(lower);
else
    weight = position - lower;
    value = values(lower) * (1 - weight) + values(upper) * weight;
end
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
FracMidLandingAttempted = zeros(n, 1);
MeanMidCorrectionRaw = NaN(n, 1);
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
    FracMidLandingAttempted(i) = safe_frac(subset.MidLandingAttempted);
    MeanMidCorrectionRaw(i) = mean(subset.MidCorrectionRaw, "omitnan");
    MeanAbsFinalGapRaw(i) = mean(abs(subset.FinalGapRaw), "omitnan");
    MaxAbsFinalGapRaw(i) = max(abs(subset.FinalGapRaw));
    MeanIterations(i) = mean(subset.Iterations, "omitnan");
end

byPoint = table(Point, N, TroubleScore, FracRecoveryAttempted, FracStickSlipJump, ...
    FracFineLandingAttempted, FracMidLandingAttempted, MeanMidCorrectionRaw, ...
    MeanAbsFinalGapRaw, MaxAbsFinalGapRaw, MeanIterations);
byPoint = sortrows(byPoint, "TroubleScore", "descend");
end

function bySweep = build_phase_response_by_sweep(response)
if isempty(response) || all(isnan(response.MidIterations))
    bySweep = table();
    return
end
phaseNames = ["COARSE","MID","FINE","COARSE_TAIL","RECOVERY"];
rows = cell(0, 12);
for r = 1:height(response)
    for phaseIndex = 1:numel(phaseNames)
        phase = phaseNames(phaseIndex);
        [iterations, commandRaw, directedRaw, zeroSteps, oppositeSteps, largeSteps] = ...
            phase_values(response(r, :), phase);
        efficiency = NaN;
        if ~isnan(commandRaw) && commandRaw ~= 0
            efficiency = 1000.0 * directedRaw / commandRaw;
        end
        rows(end + 1, :) = {response.Label(r), response.SourceFile(r), ... %#ok<AGROW>
            response.TestID(r), response.SweepID(r), phase, iterations, commandRaw, ...
            directedRaw, efficiency, zeroSteps, oppositeSteps, largeSteps};
    end
end
bySweep = cell2table(rows, 'VariableNames', ["Label","SourceFile","TestID", ...
    "SweepID","Phase","Iterations","CommandRaw","DirectedResponseRaw", ...
    "EfficiencyPermille","ZeroResponseSteps","OppositeResponseSteps", ...
    "LargeResponseSteps"]);
end

function [iterations, commandRaw, directedRaw, zeroSteps, oppositeSteps, largeSteps] = ...
        phase_values(row, phase)
switch phase
    case "COARSE"
        prefix = "Coarse";
    case "MID"
        prefix = "Mid";
    case "FINE"
        prefix = "Fine";
    case "RECOVERY"
        iterations = row.RecoveryIterations;
        commandRaw = row.RecoveryCommandRaw;
        directedRaw = row.RecoveryDirectedResponseRaw;
        zeroSteps = row.RecoveryZeroResponseSteps;
        oppositeSteps = row.RecoveryOppositeResponseSteps;
        largeSteps = row.RecoveryLargeResponseSteps;
        return
    otherwise % COARSE_TAIL
        iterations = row.CoarseTailIterations;
        commandRaw = row.CoarseTailCommandRaw;
        directedRaw = row.CoarseTailDirectedResponseRaw;
        zeroSteps = NaN;
        oppositeSteps = row.CoarseTailOppositeResponseSteps;
        largeSteps = NaN;
        return
end
iterations = row.(prefix + "Iterations");
commandRaw = row.(prefix + "CommandRaw");
directedRaw = row.(prefix + "DirectedResponseRaw");
zeroSteps = row.(prefix + "ZeroResponseSteps");
oppositeSteps = row.(prefix + "OppositeResponseSteps");
largeSteps = row.(prefix + "LargeResponseSteps");
end

function byLabel = build_phase_response_by_label(bySweep)
if isempty(bySweep)
    byLabel = table();
    return
end
labels = unique(bySweep.Label, "stable");
phases = unique(bySweep.Phase, "stable");
rows = cell(0, 10);
for labelIndex = 1:numel(labels)
    for phaseIndex = 1:numel(phases)
        subset = bySweep(bySweep.Label == labels(labelIndex) ...
            & bySweep.Phase == phases(phaseIndex), :);
        commandRaw = sum(subset.CommandRaw, "omitnan");
        directedRaw = sum(subset.DirectedResponseRaw, "omitnan");
        efficiency = NaN;
        if commandRaw ~= 0
            efficiency = 1000.0 * directedRaw / commandRaw;
        end
        rows(end + 1, :) = {labels(labelIndex), phases(phaseIndex), ... %#ok<AGROW>
            height(subset), sum(subset.Iterations, "omitnan"), commandRaw, directedRaw, ...
            efficiency, sum(subset.ZeroResponseSteps, "omitnan"), ...
            sum(subset.OppositeResponseSteps, "omitnan"), ...
            sum(subset.LargeResponseSteps, "omitnan")};
    end
end
byLabel = cell2table(rows, 'VariableNames', ["Label","Phase","NSweeps", ...
    "Iterations","CommandRaw","DirectedResponseRaw","EfficiencyPermille", ...
    "ZeroResponseSteps","OppositeResponseSteps","LargeResponseSteps"]);
end

function completeness = build_telemetry_completeness(points, steps, summary)
if isempty(summary) || all(isnan(summary.SweepPointCreepExpectedPointTelemetry))
    completeness = table();
    return
end
% Only sweeps that actually logged the V5.6+ Expected/EmittedPointTelemetry
% fields belong in this report -- earlier-schema sweeps (V5.1-V5.5) leave
% these NaN (parse_sweep_creep_log.m's documented fill for absent fields)
% and must be excluded here, not just at the all-NaN short-circuit above,
% or every pre-V5.6 sweep gets a spurious MechanismTelemetryComplete=false row.
summary = summary(~isnan(summary.SweepPointCreepExpectedPointTelemetry), :);
rows = cell(height(summary), 11);
for r = 1:height(summary)
    samePointSweep = points.Label == summary.Label(r) ...
        & points.TestID == summary.TestID(r) & points.SweepID == summary.SweepID(r);
    observedPoint = sum(samePointSweep);
    if isempty(steps)
        observedStep = 0;
    else
        sameStepSweep = steps.Label == summary.Label(r) ...
            & steps.TestID == summary.TestID(r) & steps.SweepID == summary.SweepID(r);
        observedStep = sum(sameStepSweep);
    end
    expectedPoint = summary.SweepPointCreepExpectedPointTelemetry(r);
    emittedPoint = summary.SweepPointCreepEmittedPointTelemetry(r);
    expectedStep = summary.SweepPointCreepExpectedStepTelemetry(r);
    emittedStep = summary.SweepPointCreepEmittedStepTelemetry(r);
    pointComplete = observedPoint == expectedPoint && emittedPoint == expectedPoint;
    stepComplete = observedStep == expectedStep && emittedStep == expectedStep;
    rows(r, :) = {summary.Label(r), summary.SourceFile(r), summary.TestID(r), ...
        summary.SweepID(r), expectedPoint, emittedPoint, observedPoint, expectedStep, ...
        emittedStep, observedStep, pointComplete && stepComplete};
end
completeness = cell2table(rows, 'VariableNames', ["Label","SourceFile","TestID", ...
    "SweepID","ExpectedPoint","EmittedPoint","ObservedPoint","ExpectedStep", ...
    "EmittedStep","ObservedStep","MechanismTelemetryComplete"]);
end

function frac = safe_frac(values)
values = values(~isnan(values));
if isempty(values)
    frac = NaN;
else
    frac = mean(values == 1);
end
end

function byLabel = build_hold_by_label(holdResult, labels)
if isempty(holdResult)
    byLabel = table();
    return
end
labelNames = unique(labels, "stable");
rows = cell(numel(labelNames), 12);
for i = 1:numel(labelNames)
    subset = holdResult(holdResult.Label == labelNames(i), :);
    complete = subset.Complete == 1;
    candidates = subset.CandidateLatched == 1;
    static = subset.Classification == "STATIC_WITHIN_SETTLE_BAND";
    relaxes = subset.Classification == "RELAXES_TOWARD_TARGET";
    drifts = subset.Classification == "DRIFTS_AWAY_FROM_TARGET";
    rows(i, :) = {labelNames(i), height(subset), sum(candidates), sum(complete), ...
        sum(static), sum(relaxes), sum(drifts), ...
        mean(subset.PreHoldGapReductionRaw(complete), "omitnan"), ...
        mean(subset.GapReductionRaw(complete), "omitnan"), ...
        mean(subset.TotalGapReductionRaw(complete), "omitnan"), ...
        mean(abs(subset.ObservedDriftRaw(complete)), "omitnan"), ...
        mean(subset.ValidSamples == subset.ExpectedSamples) * 100.0};
end
byLabel = cell2table(rows, 'VariableNames', ["Label","NSweeps","NCandidates", ...
    "NComplete","NStatic","NRelaxesTowardTarget","NDriftsAway", ...
    "MeanPreHoldGapReductionRaw","MeanHoldGapReductionRaw", ...
    "MeanTotalGapReductionRaw","MeanAbsHoldObservedDriftRaw","CompleteRatePct"]);
end

function byLabel = build_terminal_by_label(points, labels)
%BUILD_TERMINAL_BY_LABEL V5.9 EXTENDED terminal correction (320-raw
%   primary cap vs 400-raw hard cap). Deliberately reports the 320-only
%   success rate and the 400-terminal success rate as two SEPARATE
%   columns (never blended into one ratio, per the V5.9 plan section
%   11.4) and preserves negative TerminalResponseEfficiencyPermille
%   values (a point that ended up farther from target after terminal
%   correction, not clamped to zero).
if ~any(strcmp("TerminalEligible", points.Properties.VariableNames))
    byLabel = table();
    return
end
labelNames = unique(labels, "stable");
rows = cell(0, 15);
for i = 1:numel(labelNames)
    subset = points(points.Label == labelNames(i) & points.BudgetClass == "EXTENDED", :);
    if isempty(subset)
        continue
    end
    eligible = subset.TerminalEligible == 1;
    attempted = subset.TerminalAttempted == 1;
    succeeded = attempted & subset.TerminalSucceeded == 1;
    failed = attempted & subset.TerminalSucceeded ~= 1;
    suppressed = subset.TerminalSuppressedBySweepGuard == 1;
    primaryOnlyOk = ~attempted & subset.Result == "OK";
    gapReduction = abs(subset.TerminalEntryGapRaw(attempted)) - abs(subset.FinalGapRaw(attempted));
    rows(end + 1, :) = {labelNames(i), height(subset), sum(eligible), sum(attempted), ... %#ok<AGROW>
        sum(succeeded), sum(failed), sum(suppressed), sum(primaryOnlyOk), ...
        100.0 * sum(primaryOnlyOk) / height(subset), ...
        100.0 * sum(succeeded) / max(sum(attempted), 1), ...
        mean(subset.TerminalEntryGapRaw(attempted), "omitnan"), ...
        mean(gapReduction, "omitnan"), ...
        mean(subset.TerminalCorrectionRaw(attempted), "omitnan"), ...
        mean(subset.TerminalIterations(attempted), "omitnan"), ...
        mean(subset.TerminalResponseEfficiencyPermille(attempted), "omitnan")};
end
if isempty(rows)
    byLabel = table();
    return
end
byLabel = cell2table(rows, 'VariableNames', ["Label","NExtendedPoints","NEligible", ...
    "NAttempted","NSucceeded","NFailed","NSuppressedByGuard","NPrimary320OnlyOk", ...
    "Primary320OnlySuccessRatePct","Terminal400SuccessRatePct", ...
    "MeanTerminalEntryGapRaw","MeanTerminalGapReductionRaw","MeanTerminalCorrectionRaw", ...
    "MeanTerminalIterations","MeanTerminalEfficiencyPermille"]);
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
TotalBaseEscalationAttempted = NaN(numel(labelNames), 1);
TotalBaseEscalationSucceeded = NaN(numel(labelNames), 1);
TotalBaseEscalationFailed = NaN(numel(labelNames), 1);
BaseEscalationSuccessRatePct = NaN(numel(labelNames), 1);

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
            TotalBaseEscalationAttempted(i) = sum( ...
                subset.SweepPointCreepBaseEscalationAttempted, "omitnan");
            TotalBaseEscalationSucceeded(i) = sum( ...
                subset.SweepPointCreepBaseEscalationSucceeded, "omitnan");
            TotalBaseEscalationFailed(i) = sum( ...
                subset.SweepPointCreepBaseEscalationFailed, "omitnan");
            if TotalBaseEscalationAttempted(i) > 0
                BaseEscalationSuccessRatePct(i) = 100.0 ...
                    * TotalBaseEscalationSucceeded(i) / TotalBaseEscalationAttempted(i);
            end
        end
    end
end

byLabel = table(Label, NPointRows, NSweeps, IntegrityValidRatePct, TotalTargetCrossed, ...
    TotalRecoveryRecrossed, TotalStickSlipJump, TotalBaseEscalationAttempted, ...
    TotalBaseEscalationSucceeded, TotalBaseEscalationFailed, BaseEscalationSuccessRatePct);
end

function names = fullfile_basenames(paths)
names = strings(size(paths));
for index = 1:numel(paths)
    [~, name, ~] = fileparts(paths(index));
    names(index) = string(name);
end
end
