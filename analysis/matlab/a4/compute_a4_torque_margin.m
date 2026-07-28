function metric = compute_a4_torque_margin(run)
%COMPUTE_A4_TORQUE_MARGIN Estimate static/kinetic friction as a fraction of
%   the motor's maximum available torque (commanded power=100%,
%   sin(pole-slip angle)=1), using only MA600 position feedback -- this
%   board has no current/voltage sensor, so absolute torque in N*m cannot
%   be derived without a separate calibration (known load + lever arm).
%
%   Physical model (synchronous open-loop PMSM torque-angle law, valid
%   while winding current tracks commanded PWM duty roughly linearly -- a
%   fair approximation for a resistive-dominated winding at these low
%   speeds):
%       T(t) / T_max@100% = Power(t) * sin(DragLagRaw(t) * 2*pi / cycle)
%   DragLagRaw is read directly from CONTROL_A4_DATA (firmware's own
%   phaseProgress - rotorProgressSinceSweepStart, control_engine.c lines
%   ~501-506) rather than re-derived here, matching this project's
%   convention of trusting an already-verified firmware-computed field over
%   an approximate MATLAB reconstruction (the same choice
%   compute_nl_sweep_metrics.m makes for ClosureErrorDeg).
%
%   Static breakaway (mu_s): while the rotor is still stuck, DragLagRaw
%   accumulates as the commanded field sweeps ahead of a stationary rotor.
%   The instant applied torque exceeds static friction the rotor starts
%   moving and DragLagRaw stops growing -- so max(DragLagRaw) over
%   PHASE_SWEEP is the peak pole-slip angle reached just before breakaway,
%   giving mu_s directly. This is used INSTEAD of the firmware's own
%   CaptureSeq/CapturePhaseProgressRaw, which is delayed by design: capture
%   is only declared after a CONTROL_A4_CAPTURE_WINDOW_TICKS (100-tick)
%   trailing window confirms sustained co-motion (control_engine.c lines
%   ~508-527), so it systematically over-reports the breakaway angle (kept
%   here as FirmwareCaptureLagRaw/FirmwareStaticFrictionFraction for
%   comparison only).
%
%   Kinetic/dynamic friction (mu_k): mean DragLagRaw over rows the firmware
%   already confirms are in steady drag (CaptureLatched==1), at the same
%   held-constant target power. Real A4/A4B hardware logs (34-run batch,
%   2026-07) show CaptureLatched==1 does NOT always mean *steady*: a
%   minority of runs oscillate over several hundred raw (up to ~900) for
%   the whole sweep instead of settling to a small (tens-of-raw) lag --
%   apparent intermittent loss-of-sync/re-capture rather than smooth
%   dragging. DragLagRangeRaw/SteadyDrag flag this so callers do not
%   silently average a physically different regime into "kinetic friction".

arguments
    run struct
end

electricalCycleRaw = 10923.0;

metric = empty_metric();
if ~isfield(run, "SUMMARY") || ~isfield(run, "DATA") || isempty(run.DATA)
    return
end

summary = run.SUMMARY;
data = run.DATA;
metric.Result = string(summary.Result);
metric.CaptureRequired = summary.CaptureRequired;
metric.CaptureDetected = summary.CaptureDetected;

if summary.CaptureRequired ~= 1
    return
end

sweep = data(string(data.Phase) == "PHASE_SWEEP", :);
if isempty(sweep)
    return
end
sweep = sortrows(sweep, "Seq");

metric.PowerConstantDuringSweep = (max(sweep.PowerPpm) - min(sweep.PowerPpm)) == 0;

[peakLagRaw, peakIndex] = max(sweep.DragLagRaw);
peakPowerPpm = sweep.PowerPpm(peakIndex);
metric.PeakLagRaw = peakLagRaw;
metric.PeakLagDeg = peakLagRaw * 360.0 / electricalCycleRaw;
metric.PeakPowerFraction = peakPowerPpm / 1.0e6;
metric.StaticFrictionFraction = metric.PeakPowerFraction ...
    * sin(peakLagRaw * 2 * pi / electricalCycleRaw);
% Shape sanity check the model relies on: lag should trend upward while
% the rotor is still stuck, not just hit a noise spike. Real hardware
% DragLagRaw carries several-raw tick-to-tick jitter (encoder quantization
% + loop timing), so a strict non-decreasing check flags every real run --
% test the OVERALL trend instead (Pearson r of DragLagRaw vs Seq over the
% pre-peak segment, positive and significant). A real violation means the
% peak likely picked up noise rather than genuine stuck-then-break
% behavior, and StaticFrictionFraction for that run should not be trusted
% blindly.
if peakIndex >= 4
    [trendR, trendP] = pearson_corr_test(double(sweep.Seq(1:peakIndex)), ...
        double(sweep.DragLagRaw(1:peakIndex)));
    metric.LagTrendR = trendR;
    metric.LagRisingTrendToPeak = trendR > 0 && trendP < 0.05;
else
    metric.LagTrendR = NaN;
    metric.LagRisingTrendToPeak = true; % too few points before the peak to test
end

dragging = sweep(logical(sweep.CaptureLatched), :);
if ~isempty(dragging)
    metric.DragLagMeanRaw = mean(dragging.DragLagRaw);
    % Informational only: real A4/A4B hardware logs (34-run batch, 2026-07)
    % show DragLagRaw swings several hundred raw around its own mean for
    % essentially every run during drag, not just a visually "unsteady"
    % minority as first suspected from a 2-run spot check -- there is no
    % evidence of a clean steady-vs-oscillating split in this population,
    % so this is reported as a continuous diagnostic, not thresholded into
    % a pass/fail flag.
    metric.DragLagRangeRaw = max(dragging.DragLagRaw) - min(dragging.DragLagRaw);
    metric.DragPowerMeanFraction = mean(dragging.PowerPpm) / 1.0e6;
    metric.KineticFrictionFraction = metric.DragPowerMeanFraction ...
        * sin(metric.DragLagMeanRaw * 2 * pi / electricalCycleRaw);
end

if summary.CaptureDetected == 1
    metric.FirmwareCaptureLagRaw = summary.CapturePhaseProgressRaw;
    metric.FirmwareStaticFrictionFraction = metric.PeakPowerFraction ...
        * sin(summary.CapturePhaseProgressRaw * 2 * pi / electricalCycleRaw);
end
end

function metric = empty_metric()
metric = struct(Result = "", CaptureRequired = NaN, CaptureDetected = NaN, ...
    PowerConstantDuringSweep = NaN, PeakLagRaw = NaN, PeakLagDeg = NaN, ...
    PeakPowerFraction = NaN, StaticFrictionFraction = NaN, ...
    LagTrendR = NaN, LagRisingTrendToPeak = NaN, DragLagMeanRaw = NaN, ...
    DragLagRangeRaw = NaN, ...
    DragPowerMeanFraction = NaN, KineticFrictionFraction = NaN, ...
    FirmwareCaptureLagRaw = NaN, FirmwareStaticFrictionFraction = NaN);
end

function [r, p] = pearson_corr_test(x, y)
% Standalone reimplementation (same formula as analyze_nl_factors.m's
% pearson_test) -- kept local per this project's per-file convention.
finite = isfinite(x) & isfinite(y);
x = x(finite);
y = y(finite);
n = numel(x);
if n < 3 || std(x) == 0 || std(y) == 0
    r = NaN;
    p = NaN;
    return
end
x = x - mean(x);
y = y - mean(y);
r = sum(x .* y) / sqrt(sum(x.^2) * sum(y.^2));
r = min(max(r, -1), 1);
if abs(r) >= 1
    p = 0;
else
    df = n - 2;
    tSquared = r^2 * df / (1 - r^2);
    p = betainc(df / (df + tSquared), df / 2, 0.5);
end
end
