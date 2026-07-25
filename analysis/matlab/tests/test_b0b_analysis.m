function test_b0b_analysis
%TEST_B0B_ANALYSIS Lightweight regression without hardware log dependency.
%   analyze_b0b_transient.m was also validated against the real historical
%   logs docs/b0b-soft-start-phase-a-result.md mined (p03 jig 1 test 14/14
%   lần 2/15/16.txt, p03 jig 3 test 17/17 lần 2.txt): it reproduces every
%   published checkpoint (tick 15/25/30/35/40, both legs) exactly. That is
%   not re-run here since it depends on large files outside this repo's
%   tracked regression set; this test only checks the formulas on a small
%   synthetic case.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, "b0b"));
addpath(fullfile(root, "nl"));

% A leg that tracks the commanded quintic perfectly must read back ~100%
% tracked at every checkpoint (up to integer-rounding of the synthesized
% raw samples).
ticks = 40;
targetRaw = 182;
raw0 = 10000;
rawPerfect = zeros(1, ticks);
for index = 1:ticks
    u = index / ticks;
    blend = u^3 * (10.0 - 15.0 * u + 6.0 * u * u);
    rawPerfect(index) = round(raw0 + targetRaw * blend);
end

lines = strings(0, 1);
lines(end + 1) = sprintf(strcat("APPROACH_STEPS,SchemaVersion=5,TestID=1,", ...
    "SweepID=1,JigID=JIG1,MotorID=synth,Official=0,Leg=FORWARD,StepCount=40,", ...
    "UnwrappedRaw=%s"), strjoin(string(rawPerfect), "|"));
lines(end + 1) = strcat("APPROACH_RESULT,SweepID=1,Status=OK,", ...
    "ApproachStructuralValid=1,ApproachObservedDeltaRaw=182");
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

summary = analyze_b0b_transient(file);
assert(isfield(summary, "FORWARD"));
assert(~isfield(summary, "BACKOFF"));
assert(summary.FORWARD.N == 1);
% Rounding to integer raw counts introduces a few tenths of a percent of
% noise near tick 1 (tiny expected displacement, so any 1-raw rounding is a
% large relative error there) -- check the checkpoints where the commanded
% displacement is large enough for that rounding noise to be negligible.
lateCheckpointIndex = find(summary.FORWARD.Checkpoints == 40, 1);
assert(abs(summary.FORWARD.PctTrackedMean(lateCheckpointIndex) - 100.0) < 1.0);

% A leg that never moves must read back ~0% tracked from the first nonzero
% checkpoint onward, and its own APPROACH_RESULT gate must be respected --
% an orphan SweepID (no matching APPROACH_RESULT) must be skipped entirely.
rawStuck = repmat(raw0, 1, ticks);
lines2 = strings(0, 1);
lines2(end + 1) = sprintf(strcat("APPROACH_STEPS,SchemaVersion=5,TestID=1,", ...
    "SweepID=2,JigID=JIG1,MotorID=synth,Official=0,Leg=BACKOFF,StepCount=40,", ...
    "UnwrappedRaw=%s"), strjoin(string(rawStuck), "|"));
lines2(end + 1) = strcat("APPROACH_RESULT,SweepID=2,Status=OK,", ...
    "ApproachStructuralValid=1,BackoffObservedDeltaRaw=0");
lines2(end + 1) = sprintf(strcat("APPROACH_STEPS,SchemaVersion=5,TestID=1,", ...
    "SweepID=3,JigID=JIG1,MotorID=synth,Official=0,Leg=BACKOFF,StepCount=40,", ...
    "UnwrappedRaw=%s"), strjoin(string(rawPerfect), "|"));
% No APPROACH_RESULT for SweepID=3 -- must be skipped as an orphan.
file2 = write_temp_log(lines2);
cleanup2 = onCleanup(@() delete_if_exists(file2)); %#ok<NASGU>

summary2 = analyze_b0b_transient(file2);
assert(summary2.BACKOFF.N == 1);
assert(abs(summary2.BACKOFF.PctTrackedMean(lateCheckpointIndex) - 0.0) < 1e-9);

test_creep();
test_precondition();
test_method_extraction();
test_method_comparison();

fprintf("[ OK ] B0-B MATLAB analysis regression test passed.\n");
end

function test_method_extraction()
% Verify the locked post-turn formula independently of the production log.
lines = strings(0, 1);
lines(end + 1) = strcat("META,SchemaVersion=5,TestID=1,SweepID=1,", ...
    "RunOrder=1,RunRole=OFFICIAL,EligibleForStatistics=1,", ...
    "MeasurementValid=1,AnalysisPoints=360,CapturedPoints=371,", ...
    "AcquisitionResult=OK,ApproachStructuralValid=1,AnalysisStartRaw=7930,", ...
    "StartRaw=7929,AcqRetries=0,AcqTransportErrors=0,AcqJumpRejects=0,", ...
    "AcqFailedSamples=0,ApproachProtocol=", ...
    "SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1");

analysisErrors = 0.2 * sin(2*pi*(0:359)'/36);
allErrors = [analysisErrors; analysisErrors(1) + 0.1; zeros(10,1)];
expectedResidual = (1:10)' * 0.01;
for point = 1:10
    allErrors(361 + point) = analysisErrors(1 + point) + 0.1 + ...
        expectedResidual(point);
end
for dataIndex = 0:370
    lines(end + 1) = sprintf("DATA,,1,1,,,,%d,0,0,0,%.10f", ...
        dataIndex, allErrors(dataIndex + 1)); %#ok<AGROW>
end
lines(end + 1) = strcat("RESULT,A2=0.16,H2_PhaseSweepDeg=-90");
lines(end + 1) = strcat("SHADOW_RESULT,Valid=1,ClosureErrorDeg=0.12,", ...
    "P2P=0.4,RMS_AC=0.14,A36=0.0");
lines(end + 1) = strcat("APPROACH_RESULT,Protocol=", ...
    "SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1,", ...
    "ApproachPath=CW_CCW_CW,ReversalCount=2,Status=OK,Complete=1,", ...
    "ApproachAcquisitionClean=1,ApproachStructuralValid=1,", ...
    "OriginShiftTargetErrorRaw=180,FinalTargetErrorRaw=-100,", ...
    "FinalObservedDeltaRaw=82,LocalBackoffTargetErrorRaw=100,", ...
    "ApproachReadAttempts=100,ApproachRetries=0,ApproachTransportErrors=0,", ...
    "ApproachJumpRejects=0,ApproachFailedSamples=0");
lines(end + 1) = "END,Status=VALID";
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

[runs, audit] = extract_b0b_method_runs(file, "A0_BEFORE", ...
    "SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1", "CW_CCW_CW", 2);
assert(height(runs) == 1);
assert(sum(audit.OfficialCandidate & audit.GatePass) == 1);
assert(abs(runs.LegacyClosureErrorDeg - 0.1) < 1e-9);
assert(abs(runs.CanonicalClosureErrorDeg - 0.12) < 1e-12);
assert(abs(runs.LegacyMinusCanonicalClosureDeg + 0.02) < 1e-9);
assert(abs(runs.ClosureNormalizedDeltaRMSDeg - ...
    sqrt(mean(expectedResidual.^2))) < 1e-9);
assert(abs(runs.ClosureNormalizedDeltaMaxAbsDeg - 0.10) < 1e-9);
end

function test_method_comparison()
runOrder = repmat((1:10)', 3, 1);
leg = [repmat("A0_BEFORE",10,1); repmat("V3",10,1); ...
    repmat("A0_AFTER",10,1)];
noise = repmat(linspace(-0.004,0.004,10)', 3, 1);
residual = [repmat(0.080,10,1); repmat(0.120,10,1); ...
    repmat(0.090,10,1)] + noise;
residualMax = residual * 1.8;
absoluteClosure = [repmat(0.012,10,1); repmat(0.030,10,1); ...
    repmat(0.016,10,1)] + abs(noise);
nl = [repmat(2.75,10,1); repmat(2.73,10,1); ...
    repmat(2.71,10,1)] + noise;
rmsAc = [repmat(0.711,10,1); repmat(0.707,10,1); ...
    repmat(0.704,10,1)] + noise/10;
analysisStart = [repmat(7930,10,1); linspace(7927.25,7922.75,10)'; ...
    repmat(7920,10,1)];
runs = table(leg, runOrder, residual, residualMax, absoluteClosure, nl, ...
    rmsAc, analysisStart, VariableNames=["Leg","RunOrder", ...
    "ClosureNormalizedDeltaRMSDeg", ...
    "ClosureNormalizedDeltaMaxAbsDeg", ...
    "AbsCanonicalClosureErrorDeg","NL_RobustP2P_Deg","RMS_AC_Deg", ...
    "AnalysisStartRaw"]);

comparison = compare_b0b_a0_v3(runs, 91, 1000);
assert(comparison.Decision.SelectedMethod == "A0");
assert(~comparison.Decision.ResidualGatePass);
assert(comparison.Decision.V3ResidualWorseWithConfidence);
assert(comparison.Sector.DescriptiveGatePass);
assert(comparison.Sector.PassCount == 10);
residualContrast = comparison.Contrasts( ...
    comparison.Contrasts.Metric == "ClosureNormalizedDeltaRMSDeg", :);
assert(abs(residualContrast.V3MinusBracket - 0.035) < 1e-12);
assert(residualContrast.Bootstrap95Low > 0);
end

function test_creep()
lines = strings(0, 1);
lines(end + 1) = strcat("APPROACH_RESULT,SweepID=1,Status=OK,ApproachStructuralValid=1,", ...
    "B0BCreepProtocol=NONE,BackoffCreepResult=NOT_RUN,BackoffCreepIterations=0,", ...
    "BackoffCreepTotalRaw=0,ForwardCreepResult=NOT_RUN,ForwardCreepIterations=0,", ...
    "ForwardCreepTotalRaw=0,BackoffObservedDeltaRaw=-85,ApproachObservedDeltaRaw=56");
lines(end + 1) = strcat("APPROACH_RESULT,SweepID=2,Status=OK,ApproachStructuralValid=1,", ...
    "B0BCreepProtocol=ENCODER_CREEP_V1,BackoffCreepResult=OK,BackoffCreepIterations=12,", ...
    "BackoffCreepTotalRaw=96,ForwardCreepResult=OK,ForwardCreepIterations=18,", ...
    "ForwardCreepTotalRaw=144,BackoffObservedDeltaRaw=-167,ApproachObservedDeltaRaw=168");
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

result = analyze_b0b_creep(file);
assert(height(result.Runs) == 2);
noneRow = result.Runs(result.Runs.Protocol == "NONE",:);
creepRow = result.Runs(result.Runs.Protocol == "ENCODER_CREEP_V1",:);
assert(abs(noneRow.BackoffPctOfTarget - 85/182*100) < 1e-6);
assert(abs(creepRow.BackoffPctOfTarget - 167/182*100) < 1e-6);
assert(creepRow.BackoffCreepIterations == 12);
% Creep must move the tracked percentage closer to target than no-creep.
assert(creepRow.BackoffPctOfTarget > noneRow.BackoffPctOfTarget);
assert(creepRow.ForwardPctOfTarget > noneRow.ForwardPctOfTarget);
end

function test_precondition()
lines = strings(0, 1);
lines(end + 1) = strcat("BATCH,BatchID=1,Status=START,", ...
    "PreconditionProtocol=ADAPTIVE_2CONSECUTIVE_STABLE_V1,PreconditionCount=1,", ...
    "RunCount=10,TotalCycleCount=11,CooldownTargetMs=120000");
lines(end + 1) = "BATCH,BatchID=1,Status=COOLDOWN_START,CycleOrder=1,RunOrder=0,RunRole=PRECONDITION,TargetMs=120000,Protocol=COOLDOWN_120S_V1";
lines(end + 1) = "BATCH,BatchID=1,Status=COOLDOWN_START,CycleOrder=2,RunOrder=0,RunRole=PRECONDITION,TargetMs=120000,Protocol=COOLDOWN_120S_V1";
lines(end + 1) = "BATCH,BatchID=1,Status=COOLDOWN_START,CycleOrder=3,RunOrder=1,RunRole=OFFICIAL,TargetMs=120000,Protocol=COOLDOWN_120S_V1";
lines(end + 1) = strcat("BATCH,BatchID=1,Status=COMPLETE,PreconditionCount=1,RunCount=10,", ...
    "TotalCycleCount=11,PreconditionValid=1,PreconditionRunsUsed=2,", ...
    "PreconditionStabilityDeltaDeg=0.01");
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

result = analyze_b0b_precondition(file);
assert(result.PreconditionProtocol == "ADAPTIVE_2CONSECUTIVE_STABLE_V1");
assert(result.PreconditionCyclesObserved == 2);
assert(result.OfficialCyclesObserved == 1);
assert(result.Completed);
assert(result.PreconditionRunsUsed == 2);
assert(abs(result.PreconditionStabilityDeltaDeg - 0.01) < 1e-9);
end

function file = write_temp_log(lines)
file = string(tempname) + ".txt";
fid = fopen(file, "wt");
assert(fid >= 0);
for index = 1:numel(lines)
    fprintf(fid, "%s\n", lines(index));
end
fclose(fid);
end

function delete_if_exists(path)
if isfile(path)
    delete(path);
end
end
