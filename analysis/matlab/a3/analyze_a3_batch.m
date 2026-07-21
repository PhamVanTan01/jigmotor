function result = analyze_a3_batch(logPaths)
%ANALYZE_A3_BATCH MATLAB analysis of an A3 (rotating-capture) log batch.
%   No PowerShell analyzer exists for A3 yet (docs/control-a3-result.md
%   says one was planned "alongside A4 once the record layout stabilized"
%   but was never written) -- this is the first one, validated against the
%   figures already published in docs/control-a3-result.md section 3/5
%   (mean 6742.1 raw, SD 81.3 raw, range 210 raw, R~0.999 over the 8
%   Result=OK runs; 2/10 runs faulted with SAMPLE_STEP_LIMIT).
%
%   ElectricalOffsetRaw = FinalRaw mod electricalCycle (10923), exactly as
%   firmware computes it (Core/Src/control_engine.c, commit 786c657) -- a
%   single deterministic per-run value, not an averaged/circular quantity
%   at the firmware level. The cross-run mean/SD/range IS a circular
%   statistic and must be computed as one (see analysis/matlab/
%   compute_circular_stats.m) -- plain arithmetic mean/SD is only valid as
%   an approximation when the values don't approach the 0/cycle wrap
%   boundary, which this reports and checks.

arguments
    logPaths (1,:) string
end

cycle = 10923.0;
rows = table();
for fileIndex = 1:numel(logPaths)
    runs = parse_control_log(logPaths(fileIndex), "A3");
    for runIndex = 1:numel(runs)
        run = runs(runIndex);
        if ~isfield(run, "SUMMARY")
            continue
        end
        s = run.SUMMARY;
        finalOffsetRaw = mod(s.FinalRaw, cycle);
        row = table( ...
            fullfile_basename(logPaths(fileIndex)) + "#" + string(runIndex), ...
            string(s.Result), s.BaselineRaw, s.FinalRaw, finalOffsetRaw, ...
            s.ElectricalOffsetRaw, abs(finalOffsetRaw - s.ElectricalOffsetRaw) < 1e-6, ...
            s.CaptureDetected, s.DragLagMeanRaw, s.DragLagMaxRaw, s.RampCreepRaw, ...
            s.MaxTravelMilliDeg, s.MaxStepMilliDeg, s.EvidenceCount, ...
            VariableNames=["Source","Result","BaselineRaw","FinalRaw", ...
            "FinalOffsetRaw","FinalOffsetRawFromSummary","OffsetFieldMatches", ...
            "CaptureDetected","DragLagMeanRaw","DragLagMaxRaw","RampCreepRaw", ...
            "MaxTravelMilliDeg","MaxStepMilliDeg","EvidenceCount"]);
        if isempty(rows)
            rows = row;
        else
            rows = [rows; row]; %#ok<AGROW>
        end
    end
end

if isempty(rows)
    error("A3Analysis:NoRuns", "No CONTROL_A3_SUMMARY runs parsed from the given log paths.");
end

okRows = rows(rows.Result == "OK",:);
circularStats = compute_circular_stats(okRows.FinalOffsetRaw, cycle);
arithmeticMean = mean(okRows.FinalOffsetRaw);
arithmeticSdPopulation = std(okRows.FinalOffsetRaw, 1);   % divide by N
arithmeticSdSample = std(okRows.FinalOffsetRaw, 0);        % divide by N-1 (MATLAB default; matches docs/control-a3-result.md's reported 81.3)
arithmeticVsCircularDiffRaw = circular_abs_diff(arithmeticMean, circularStats.MeanRaw, cycle);

faultRows = rows(rows.Result ~= "OK",:);
captureRateAmongOk = sum(okRows.CaptureDetected == 1) / max(height(okRows), 1);
gateRangeRaw = circularStats.RangeRaw <= 182.0;
gateResultantR = circularStats.ResultantR >= 0.99;
gateZeroFaults = height(faultRows) == 0;
gateCaptureAll = captureRateAmongOk >= 1.0;
acceptance = gateRangeRaw && gateResultantR && gateZeroFaults && gateCaptureAll && height(okRows) >= 5;

result = struct(Runs = rows, OkRuns = okRows, FaultRuns = faultRows, ...
    CircularStats = circularStats, ArithmeticMeanRaw = arithmeticMean, ...
    ArithmeticSdPopulationRaw = arithmeticSdPopulation, ...
    ArithmeticSdSampleRaw = arithmeticSdSample, ...
    ArithmeticVsCircularDiffRaw = arithmeticVsCircularDiffRaw, ...
    CaptureRateAmongOk = captureRateAmongOk, ...
    GateRangeRaw = gateRangeRaw, GateResultantR = gateResultantR, ...
    GateZeroFaults = gateZeroFaults, GateCaptureAll = gateCaptureAll, ...
    Acceptance = acceptance);

fprintf("[MATLAB A3] runs=%d ok=%d faults=%d (%s)\n", height(rows), ...
    height(okRows), height(faultRows), strjoin(unique(faultRows.Result), ","));
fprintf("[MATLAB A3] ElectricalOffsetRaw circular mean=%.2f raw range=%.2f raw R=%.5f | arithmetic mean=%.2f SD(pop)=%.2f SD(sample,N-1)=%.2f raw (diff mean circular-vs-arithmetic=%.3f raw)\n", ...
    circularStats.MeanRaw, circularStats.RangeRaw, circularStats.ResultantR, ...
    arithmeticMean, arithmeticSdPopulation, arithmeticSdSample, arithmeticVsCircularDiffRaw);
fprintf("[MATLAB A3] capture rate among OK runs=%.0f%% | gates: range<=182=%d R>=0.99=%d zeroFaults=%d captureAll=%d\n", ...
    captureRateAmongOk * 100, gateRangeRaw, gateResultantR, gateZeroFaults, gateCaptureAll);
fprintf("[MATLAB A3] acceptance: %s\n", ternary(acceptance, "PASS", "FAIL"));
end

function name = fullfile_basename(path)
[~, name, ~] = fileparts(path);
name = string(name);
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end

function value = circular_abs_diff(left, right, period)
value = abs(mod(left - right + period / 2.0, period) - period / 2.0);
end
