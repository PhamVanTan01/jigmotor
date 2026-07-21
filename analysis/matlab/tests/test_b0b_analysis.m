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

fprintf("[ OK ] B0-B MATLAB analysis regression test passed.\n");
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
