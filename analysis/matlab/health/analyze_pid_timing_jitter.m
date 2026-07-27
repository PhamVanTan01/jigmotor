function result = analyze_pid_timing_jitter(files, nominalPeriodMs)
%ANALYZE_PID_TIMING_JITTER Quantify how much real loop-timing jitter exists
%   relative to the fixed-dt assumption baked into PositionController_Update
%   (position_controller.c): "controller->integral += config.ki * errorDeg"
%   and the derivative term "kd * (errorDeg - lastError)" have NO explicit
%   dt factor -- both assume PositionController_Update is called at a
%   perfectly uniform nominalPeriodMs cadence. If the actual call-to-call
%   interval varies, the effective integral/derivative gain PER UNIT TIME
%   silently varies by the same fraction, with no compensation anywhere in
%   the controller. This does not simulate the controller; it measures how
%   large the real timing jitter is (from CONTROL_A4_DATA's own
%   LatenessTicks/LoopCycles health fields, already logged by the firmware
%   for this exact purpose) so the theoretical gap can be judged material
%   or negligible against real hardware behavior, not just asserted.

arguments
    files (1,:) string
    nominalPeriodMs (1,1) double = 1.0
end

latenessTicks = [];
loopCycles = [];
fileCol = strings(0, 1);
for index = 1:numel(files)
    runs = parse_control_log(files(index), "A4");
    for runIndex = 1:numel(runs)
        run = runs(runIndex);
        if ~isfield(run, "DATA") || isempty(run.DATA)
            continue
        end
        data = run.DATA;
        if ~ismember("LatenessTicks", string(data.Properties.VariableNames))
            continue
        end
        n = height(data);
        latenessTicks = [latenessTicks; double(data.LatenessTicks)]; %#ok<AGROW>
        if ismember("LoopCycles", string(data.Properties.VariableNames))
            loopCycles = [loopCycles; double(data.LoopCycles)]; %#ok<AGROW>
        end
        fileCol = [fileCol; repmat(files(index), n, 1)]; %#ok<AGROW>
    end
end

if isempty(latenessTicks)
    error("PidJitter:NoData", "No CONTROL_A4_DATA rows with LatenessTicks found in the given files.");
end

n = numel(latenessTicks);
lateFraction = sum(latenessTicks > 0) / n;
meanLatenessTicks = mean(latenessTicks);
maxLatenessTicks = max(latenessTicks);
% A tick that starts L ticks late ran with an actual inter-call interval of
% (1+L) nominal periods instead of 1 -- the fractional dt error for THAT
% sample versus the fixed-dt assumption baked into ki*error/kd*delta.
dtErrorFraction = latenessTicks / 1.0; % LatenessTicks is already in the same tick units as nominalPeriodMs
meanDtErrorPct = 100 * mean(dtErrorFraction);
maxDtErrorPct = 100 * max(dtErrorFraction);

result = struct(N = n, NominalPeriodMs = nominalPeriodMs, ...
    MeanLatenessTicks = meanLatenessTicks, MaxLatenessTicks = maxLatenessTicks, ...
    LateFraction = lateFraction, MeanDtErrorPct = meanDtErrorPct, MaxDtErrorPct = maxDtErrorPct, ...
    LatenessTicks = latenessTicks, LoopCycles = loopCycles);

fprintf("=== PID loop timing jitter: %d ticks across %d files ===\n", n, numel(unique(fileCol)));
fprintf("LatenessTicks: mean=%.4f  max=%d  fraction late (>0 ticks)=%.4f%%\n", ...
    meanLatenessTicks, maxLatenessTicks, 100 * lateFraction);
fprintf("Implied dt error vs the fixed-dt assumption in ki/kd: mean=%.4f%%  max=%.2f%%\n", ...
    meanDtErrorPct, maxDtErrorPct);
if ~isempty(loopCycles)
    fprintf("LoopCycles (compute time per tick): mean=%.0f  max=%.0f cycles\n", ...
        mean(loopCycles), max(loopCycles));
end
end
