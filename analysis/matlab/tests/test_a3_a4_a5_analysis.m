function test_a3_a4_a5_analysis
%TEST_A3_A4_A5_ANALYSIS Lightweight regression without hardware log dependency.
%   Covers parse_control_log.m and the A3/A4/A5 analysis modules against
%   small synthetic logs with hand-checkable expected results. These
%   modules were also validated against real hardware data (A3 test 1-5,
%   A4/A4B test 1-5 + "test 2 lần" 1-5, A5 test 1-10) reproducing the
%   published figures in docs/control-a3-result.md and
%   docs/control-a5-result.md exactly -- see conversation/commit history;
%   that validation is not re-run here since it depends on files outside
%   the repo's tracked regression set.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
addpath(fullfile(root, "a3"));
addpath(fullfile(root, "a4"));
addpath(fullfile(root, "a5"));

test_parser_ignores_other_families();
test_a3_circular_offset();
test_a4_seed_span_and_gate();
test_a4_torque_margin();
test_a5_stability_metrics();

fprintf("[ OK ] A3/A4/A5 MATLAB analysis regression test passed.\n");
end

function test_parser_ignores_other_families()
lines = [ ...
    "CONTROL_A5_ARMED,RecordVersion=1,Profile=X"; ...
    "CONTROL_A4_SUMMARY,Result=OK"; ...
    "CONTROL_A5_SUMMARY,RecordVersion=1,Result=OK,MeasurementValid=1"; ...
    "CONTROL_A5_DATA,RecordVersion=1,Index=0,Raw=100"; ...
    "CONTROL_A5_DATA,RecordVersion=1,Index=1,Raw=101"];
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>
runs = parse_control_log(file, "A5");
assert(numel(runs) == 1);
assert(~isfield(runs(1), "CONTROL_A4_SUMMARY"));
assert(runs(1).SUMMARY.Result == "OK");
assert(height(runs(1).DATA) == 2);
assert(runs(1).DATA.Raw(2) == 101);
end

function test_a3_circular_offset()
cycle = 10923;
lines = strings(0, 1);
lines(end + 1) = "CONTROL_A3_ARMED,Profile=SYNTH";
lines(end + 1) = sprintf(strcat("CONTROL_A3_SUMMARY,Profile=SYNTH,Result=OK,", ...
    "BaselineRaw=0,FinalRaw=1000,ElectricalOffsetRaw=1000,CaptureDetected=1,", ...
    "DragLagMeanRaw=10,DragLagMaxRaw=20,RampCreepRaw=5,MaxTravelMilliDeg=1000,", ...
    "MaxStepMilliDeg=100,EvidenceCount=1068"));
lines(end + 1) = "CONTROL_A3_ARMED,Profile=SYNTH";
lines(end + 1) = sprintf(strcat("CONTROL_A3_SUMMARY,Profile=SYNTH,Result=OK,", ...
    "BaselineRaw=0,FinalRaw=1100,ElectricalOffsetRaw=1100,CaptureDetected=1,", ...
    "DragLagMeanRaw=12,DragLagMaxRaw=22,RampCreepRaw=6,MaxTravelMilliDeg=1100,", ...
    "MaxStepMilliDeg=110,EvidenceCount=1068"));
lines(end + 1) = "CONTROL_A3_ARMED,Profile=SYNTH";
lines(end + 1) = strcat("CONTROL_A3_SUMMARY,Profile=SYNTH,Result=SAMPLE_STEP_LIMIT,", ...
    "BaselineRaw=0,FinalRaw=500,ElectricalOffsetRaw=500,CaptureDetected=0,", ...
    "DragLagMeanRaw=0,DragLagMaxRaw=0,RampCreepRaw=0,MaxTravelMilliDeg=9000,", ...
    "MaxStepMilliDeg=900,EvidenceCount=50");
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

result = analyze_a3_batch(file);
assert(height(result.Runs) == 3);
assert(height(result.OkRuns) == 2);
assert(height(result.FaultRuns) == 1);
assert(abs(result.ArithmeticMeanRaw - 1050) < 1e-9);
assert(abs(result.CircularStats.RangeRaw - 100) < 1e-6);
assert(all(result.Runs.OffsetFieldMatches));
assert(result.CaptureRateAmongOk == 1.0);
assert(result.GateZeroFaults == false);
assert(mod(cycle, 1) == 0); % sanity: cycle constant used consistently above
end

function test_a4_seed_span_and_gate()
cycle = 10923;
offset = 100;
baseline = 5000;
expectedSeed = mod(mod(baseline, cycle) - offset + cycle, cycle);
expectedSpan = mod(cycle - expectedSeed, cycle);
proportional = floor((2400 * expectedSpan + floor(cycle / 2)) / cycle);
expectedSweepTicks = max(proportional, 240);

lines = strings(0, 1);
lines(end + 1) = "CONTROL_A4_ARMED,Profile=SYNTH";
lines(end + 1) = sprintf(strcat("CONTROL_A4_SUMMARY,Profile=SYNTH,Result=OK,", ...
    "SeedPhaseRaw=%d,SeedOffsetRaw=%d,SweepSpanRaw=%d,SweepTicks=%d,", ...
    "AlreadyAligned=0,CaptureRequired=1,CaptureDetected=1,BaselineRaw=%d,FinalRaw=%d,", ...
    "ElectricalOffsetRaw=%d,DragLagMeanRaw=0,DragLagMaxRaw=0,", ...
    "EvidenceCount=%d"), expectedSeed, offset, expectedSpan, expectedSweepTicks, ...
    baseline, baseline + 20, mod(baseline + 20, cycle), ...
    floor((300 + expectedSweepTicks + 500) / 3) + 1 + double(mod(300 + expectedSweepTicks + 500, 3) ~= 0));
lines(end + 1) = strcat("CONTROL_A4_DATA,Seq=0,Phase=POWER_RAMP,EncoderRaw=", ...
    string(mod(baseline, 65536)), ",DeltaRaw=0,DragLagRaw=0,CaptureLatched=0");
lines(end + 1) = strcat("CONTROL_A4_DATA,Seq=1,Phase=ALIGN_HOLD,EncoderRaw=", ...
    string(mod(baseline + 20, 65536)), ",DeltaRaw=1,DragLagRaw=0,CaptureLatched=1");
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

result = analyze_a4_batch(file, "SYNTH", offset);
assert(height(result.Metrics) == 1);
assert(result.Metrics.SeedMatchesExpected(1));
assert(result.Metrics.SpanMatchesExpected(1));
assert(result.Metrics.SweepTicksMatchesExpected(1));
assert(result.Metrics.EvidenceCountMatchesExpected(1));
assert(result.Metrics.CaptureConsistent(1));
% Single run can never satisfy the >=5-run acceptance gate.
assert(result.Acceptance == false);
end

function test_a4_torque_margin()
% Synthetic PHASE_SWEEP: DragLagRaw rises while the rotor is stuck (rows
% 1-5, peak=200 raw at constant PowerPpm=350000), then settles into a
% lower steady drag (rows 6-10, CaptureLatched=1) -- exactly the
% stuck-then-break shape compute_a4_torque_margin.m's peak-lag method
% assumes. SUMMARY's own CapturePhaseProgressRaw is deliberately set
% higher (250) than the true peak (200) to reproduce the documented
% over-report from the firmware's delayed capture-confirmation window.
cycle = 10923.0;
lagValues = [40, 80, 120, 160, 200, 150, 130, 125, 122, 120];
captureLatched = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1];

lines = strings(0, 1);
lines(end + 1) = "CONTROL_A4_ARMED,Profile=SYNTH_TORQUE";
lines(end + 1) = strcat("CONTROL_A4_SUMMARY,Profile=SYNTH_TORQUE,Result=OK,", ...
    "CaptureRequired=1,CaptureDetected=1,CapturePhaseProgressRaw=250");
for index = 1:numel(lagValues)
    lines(end + 1) = sprintf(strcat("CONTROL_A4_DATA,Seq=%d,Phase=PHASE_SWEEP,", ...
        "DragLagRaw=%d,PowerPpm=350000,CaptureLatched=%d"), ...
        index, lagValues(index), captureLatched(index)); %#ok<AGROW>
end
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

runs = parse_control_log(file, "A4");
metric = compute_a4_torque_margin(runs(1));

expectedStatic = 0.35 * sin(200 * 2 * pi / cycle);
assert(metric.PeakLagRaw == 200);
assert(metric.LagRisingTrendToPeak == true);
assert(metric.PowerConstantDuringSweep == true);
assert(metric.DragLagRangeRaw == 30); % post-capture range = 150-120 raw
assert(abs(metric.StaticFrictionFraction - expectedStatic) < 1e-9);

expectedKineticLagMean = mean([150, 130, 125, 122, 120]);
expectedKinetic = 0.35 * sin(expectedKineticLagMean * 2 * pi / cycle);
assert(abs(metric.KineticFrictionFraction - expectedKinetic) < 1e-9);

expectedFirmware = 0.35 * sin(250 * 2 * pi / cycle);
assert(abs(metric.FirmwareStaticFrictionFraction - expectedFirmware) < 1e-9);
% The firmware's delayed capture-confirmation window must over-report
% relative to the true peak-lag breakaway angle -- that is the whole
% reason the peak-lag method exists instead of trusting CaptureSeq alone.
assert(metric.FirmwareStaticFrictionFraction > metric.StaticFrictionFraction);

batch = analyze_a4_torque_margin_batch(file);
assert(height(batch.Runs) == 1);
assert(batch.StaticFrictionStats.N == 1);
assert(abs(batch.StaticFrictionStats.Mean - expectedStatic) < 1e-9);
end

function test_a5_stability_metrics()
n = 64;
rawSequence = 51650 + round(3 * sin((0:n-1)' * 2 * pi / 16));
lines = strings(0, 1);
lines(end + 1) = "CONTROL_A5_ARMED,RecordVersion=1,Profile=SYNTH,SampleRateHz=1000";
lines(end + 1) = "CONTROL_A5_SUMMARY,RecordVersion=1,Profile=SYNTH,Result=OK,MeasurementValid=1";
for index = 1:n
    lines(end + 1) = sprintf("CONTROL_A5_DATA,RecordVersion=1,Profile=SYNTH,Index=%d,Raw=%d", ...
        index - 1, rawSequence(index)); %#ok<AGROW>
end
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

runs = parse_control_log(file, "A5");
assert(numel(runs) == 1);
assert(height(runs(1).DATA) == n);
metric = compute_a5_run_metrics(runs(1));

relative = rawSequence - rawSequence(1);
expectedP2P = max(relative) - min(relative);
assert(abs(metric.P2PRaw - expectedP2P) < 1e-9);
assert(abs(metric.DriftRaw - (relative(end) - relative(1))) < 1e-9);
expectedPopSd = sqrt(sum((relative - mean(relative)).^2) / n);
assert(abs(metric.PopulationSdRaw - expectedPopSd) < 1e-9);
assert(metric.RawCRC32 >= 0 && metric.RawCRC32 < 4294967296);
assert(numel(metric.Autocorrelation) == 8);
assert(numel(metric.AllanDeviationRaw) == 8);
% A clean period-16 sinusoid must autocorrelate strongly (positively) at
% lag 16 (one full period) and strongly negatively at lag 8 (half period).
assert(metric.Autocorrelation(find(metric.TauSamples == 16, 1)) > 0.6);
assert(metric.Autocorrelation(find(metric.TauSamples == 8, 1)) < -0.6);
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
