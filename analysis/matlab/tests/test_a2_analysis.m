function test_a2_analysis
%TEST_A2_ANALYSIS Lightweight regression without hardware log dependency.

stats = compute_circular_stats([10920; 2; 5], 10923);
assert(stats.Count == 3);
assert(stats.RangeRaw == 8);
assert(stats.ResultantR > 0.999);

sequence = (0:1000)';
phase = repmat("ALIGN_RAMP", 1001, 1);
phase(sequence > 500) = "ALIGN_HOLD";
travelRaw = zeros(1001,1);
travelRaw(sequence >= 501) = 1;
deltaRaw = [travelRaw(1); diff(travelRaw)];
powerPpm = min(sequence*160, 80000);
baselineRaw = 1000;

evidence = table(sequence, phase, baselineRaw+travelRaw, travelRaw, ...
    travelRaw*360000/65536, deltaRaw, powerPpm, sequence+1000, ...
    sequence+1000, zeros(1001,1), 3000+zeros(1001,1), ...
    1336+zeros(1001,1), VariableNames=["Seq","Phase","EncoderRaw", ...
    "TravelRaw","TravelMilliDeg","DeltaRaw","PowerPpm", ...
    "ScheduledTick","SampleTick","LatenessTicks","LoopCycles", ...
    "SpiLatencyCycles"]);
validate_a2_schema(evidence, "evidence");

summary = table("synthetic-a2e", "synthetic.log", ...
    "CONTROL_A2E_FIXED_PHASE_ALIGN_P08_H500_V1", "OK", true, ...
    1001, baselineRaw, baselineRaw+1, 1000*360/65536, ...
    1000*360/65536, 1, 0, 1001, 0, 0, 0, 0, 0, ...
    VariableNames=["Run","File","Profile","Result","GatePass", ...
    "EvidenceCount","BaselineRaw","FinalRaw","FinalTravelMilliDeg", ...
    "MaxAbsTravelMilliDeg","MaxAbsStepRaw","HoldDriftMilliDeg", ...
    "SettledModuloRaw","DeadlineMisses","Retries","TransportErrors", ...
    "JumpRejects","FailedSamples"]);
validate_a2_schema(summary, "summary");

metric = compute_a2_metrics(summary, evidence, "synthetic-hash");
assert(metric.TargetPowerPercent == 8);
assert(metric.MaxAbsStepRaw == 1);
assert(abs(metric.FinalTravelDeg-360/65536) < 1e-12);
assert(metric.SettledModuloRaw == 1001);

crosscheck = crosscheck_a2_metrics(summary, metric);
assert(crosscheck.MetricMatch);

temporaryFile = string(tempname) + ".txt";
cleanup = onCleanup(@() delete_if_exists(temporaryFile));
fid = fopen(temporaryFile, "wt");
assert(fid >= 0);
fprintf(fid, "a2-analysis-regression\n");
fclose(fid);
assert(strlength(sha256_file(temporaryFile)) == 64);
clear cleanup

fprintf("[ OK ] MATLAB A2 analysis regression test passed.\n");
end

function delete_if_exists(path)
if isfile(path)
    delete(path);
end
end
