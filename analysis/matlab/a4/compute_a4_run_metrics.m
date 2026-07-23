function metric = compute_a4_run_metrics(run, expectedOffsetRaw)
%COMPUTE_A4_RUN_METRICS Independently recompute A4/A4B per-run metrics.
%   Mirrors scripts/analyze_control_a4.ps1's derived-metric formulas so the
%   two independent implementations can be cross-checked against each
%   other. Evidence (run.DATA) is decimated 3x from the firmware's 1kHz
%   loop, so fields computed only from DATA (Ramp/SweepMaxStepRawEvidence,
%   HoldTail20P2PRaw, decimated drag-lag mean/max) are bounded
%   approximations of the true 1kHz values SUMMARY reports directly -- same
%   distinction the PowerShell analyzer itself keeps (MaxStepMilliDeg vs
%   *Evidence columns). CaptureSeq/CaptureDetected are NOT re-derived here:
%   the firmware's capture-latch ring-buffer runs on every 1kHz tick, and a
%   3x-decimated log cannot reproduce that window exactly -- they are
%   trusted from SUMMARY and only checked for internal consistency.

arguments
    run struct
    expectedOffsetRaw (1,1) double
end

cycle = 10923.0;
summary = run.SUMMARY;
data = run.DATA;

baselineRaw = summary.BaselineRaw;
expectedSeed = normalize_cycle(mod(baselineRaw, cycle) - expectedOffsetRaw, cycle);
expectedSpan = normalize_cycle(cycle - expectedSeed, cycle);
proportional = floor((2400.0 * expectedSpan + floor(cycle / 2.0)) / cycle);
expectedSweepTicks = max(proportional, 240.0);
expectedTotalTicks = 300.0 + expectedSweepTicks + 500.0;
expectedEvidenceCount = floor(expectedTotalTicks / 3.0) + 1.0;
if mod(expectedTotalTicks, 3.0) ~= 0.0
    expectedEvidenceCount = expectedEvidenceCount + 1.0;
end

finalOffsetRaw = mod(summary.FinalRaw, cycle);

phase = string(data.Phase);
deltaRaw = double(data.DeltaRaw);
rampMaxStepRawEvidence = max_abs_or_zero(deltaRaw(phase == "POWER_RAMP"));
sweepMaxStepRawEvidence = max_abs_or_zero(deltaRaw(phase == "PHASE_SWEEP"));

holdTail20P2PRaw = tail20_p2p_raw(data, phase == "ALIGN_HOLD");

dragLagRaw = double(data.DragLagRaw);
captureLatched = logical(data.CaptureLatched);
postCapture = dragLagRaw(captureLatched);
if isempty(postCapture)
    dragLagMeanRawEvidence = NaN;
    dragLagMaxRawEvidence = NaN;
else
    dragLagMeanRawEvidence = fix(sum(postCapture) / numel(postCapture));
    dragLagMaxRawEvidence = max(postCapture);
end

metric = struct( ...
    Run = string(summary.Profile) + "#" + string(summary.Result), ...
    Result = string(summary.Result), ...
    BaselineRaw = baselineRaw, ...
    SeedPhaseRaw = summary.SeedPhaseRaw, ...
    ExpectedSeedPhaseRaw = expectedSeed, ...
    SeedMatchesExpected = abs(summary.SeedPhaseRaw - expectedSeed) < 1e-6, ...
    SweepSpanRaw = summary.SweepSpanRaw, ...
    ExpectedSweepSpanRaw = expectedSpan, ...
    SpanMatchesExpected = abs(summary.SweepSpanRaw - expectedSpan) < 1e-6, ...
    SweepTicks = summary.SweepTicks, ...
    ExpectedSweepTicks = expectedSweepTicks, ...
    SweepTicksMatchesExpected = abs(summary.SweepTicks - expectedSweepTicks) < 1e-6, ...
    EvidenceCount = summary.EvidenceCount, ...
    ExpectedEvidenceCount = expectedEvidenceCount, ...
    EvidenceCountMatchesExpected = abs(summary.EvidenceCount - expectedEvidenceCount) < 1e-6, ...
    CaptureRequired = summary.CaptureRequired, ...
    CaptureDetected = summary.CaptureDetected, ...
    CaptureConsistent = ~(summary.CaptureRequired == 1 && summary.CaptureDetected ~= 1), ...
    FinalOffsetRaw = finalOffsetRaw, ...
    FinalOffsetRawFromSummaryField = summary.ElectricalOffsetRaw, ...
    RampMaxStepRawEvidence = rampMaxStepRawEvidence, ...
    SweepMaxStepRawEvidence = sweepMaxStepRawEvidence, ...
    HoldTail20P2PRaw = holdTail20P2PRaw, ...
    DragLagMeanRawSummary = summary.DragLagMeanRaw, ...
    DragLagMaxRawSummary = summary.DragLagMaxRaw, ...
    DragLagMeanRawEvidence = dragLagMeanRawEvidence, ...
    DragLagMaxRawEvidence = dragLagMaxRawEvidence);
end

function value = normalize_cycle(value, cycle)
value = mod(value, cycle);
if value < 0
    value = value + cycle;
end
end

function value = max_abs_or_zero(values)
if isempty(values)
    value = 0;
else
    value = max(abs(values));
end
end

function p2p = tail20_p2p_raw(data, mask)
holdRows = find(mask);
if isempty(holdRows)
    p2p = NaN;
    return
end
tailRows = holdRows(max(1, numel(holdRows) - 19):end);
encoderRaw = double(data.EncoderRaw(tailRows));
unwrapped = zeros(size(encoderRaw));
for index = 2:numel(encoderRaw)
    delta = encoderRaw(index) - encoderRaw(index - 1);
    if delta > 32767
        delta = delta - 65536;
    elseif delta < -32768
        delta = delta + 65536;
    end
    unwrapped(index) = unwrapped(index - 1) + delta;
end
p2p = max(unwrapped) - min(unwrapped);
end
