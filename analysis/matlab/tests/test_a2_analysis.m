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

metric.Included = true;
significance = compute_circular_significance([100; 105; 95; 110; 90], 10923.0, ...
    BootstrapSamples=200);
assert(significance.N == 5);
assert(significance.RayleighP < 0.01);
assert(significance.BootstrapCILow <= significance.R && ...
    significance.R <= significance.BootstrapCIHigh + 1e-9);

uniformValues = [0; 2184.5; 4369; 6553.6; 8738.1];
uniformStats = compute_circular_significance(uniformValues, 10923.0, ...
    BootstrapSamples=200);
assert(uniformStats.R < 0.05);
assert(uniformStats.RayleighP > 0.9);

metrics = [metric; metric];
metrics.Run(2) = "synthetic-a2e-2";
metrics.EvidenceHash(2) = "synthetic-hash-2";
safety = build_a2_safety_envelope(metrics);
assert(height(safety) == 1);
assert(safety.TotalRuns(1) == 2);
assert(safety.FaultRuns(1) == 0);
assert(abs(safety.MaxStepRawAny(1) - metric.MaxAbsStepRaw) < 1e-9);

ceiling = estimate_a2_power_ceiling(safety);
assert(isstruct(ceiling));

electricalPeriodRaw = 10923.0;
trueAmplitudeRaw = 200.0;
truePhaseRaw = 1500.0;
thetaKnown = linspace(0, 2*pi*11/12, 12)';
startModuloKnown = mod(thetaKnown*electricalPeriodRaw/(2*pi), electricalPeriodRaw);
travelRawKnown = trueAmplitudeRaw*sin(thetaKnown - 2*pi*truePhaseRaw/electricalPeriodRaw);
harmonicMetrics = table(repmat("SYNTH_HARMONIC", 12, 1), repmat(true, 12, 1), ...
    repmat(true, 12, 1), repmat(8.0, 12, 1), startModuloKnown, ...
    travelRawKnown*360.0/65536.0, VariableNames=["Profile","Included", ...
    "GatePass","TargetPowerPercent","StartModuloRaw","FinalTravelDeg"]);
harmonicFit = fit_a2_restoring_torque(harmonicMetrics);
assert(height(harmonicFit.PerLevel) == 1);
assert(abs(harmonicFit.PerLevel.AmplitudeRaw(1) - trueAmplitudeRaw) < 1e-6);
assert(abs(mod(harmonicFit.PerLevel.PhaseRaw(1) - truePhaseRaw + ...
    electricalPeriodRaw/2, electricalPeriodRaw) - electricalPeriodRaw/2) < 1e-6);
assert(harmonicFit.PerLevel.RSquared(1) > 0.999);
assert(harmonicFit.PerLevel.PValue(1) < 1e-6);
assert(harmonicFit.Pooled.N == 12);

nullTravelDeg = [12;-9;5;-14;8;-3;11;-7;2;-10;6;-4];
nullMetrics = table(repmat("SYNTH_NULL", 12, 1), repmat(true, 12, 1), ...
    repmat(true, 12, 1), repmat(8.0, 12, 1), startModuloKnown, ...
    double(nullTravelDeg), VariableNames=["Profile","Included", ...
    "GatePass","TargetPowerPercent","StartModuloRaw","FinalTravelDeg"]);
nullFit = fit_a2_restoring_torque(nullMetrics);
assert(nullFit.PerLevel.PValue(1) > 0.05);

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
