function result = analyze_a5_batch(logPaths)
%ANALYZE_A5_BATCH Independent MATLAB re-analysis of an A5 static-capture
%   log batch (compute_a5_run_metrics per run: P2P, drift, population SD,
%   RMS, median, MAD/robust sigma, linear drift/detrended SD, first/last-
%   harmonic-free autocorrelation and overlapping Allan deviation at
%   tau in {1,2,4,8,16,32,64,128} samples, CRC32). PWM-phase-bin and
%   schedule-cycle diagnostics (CsAssertCycle-based) are intentionally not
%   ported here -- they are transport/timing integrity checks already
%   covered by scripts/analyze_control_a5.ps1's hard structural gate, not
%   part of the RawAngle stability question this module studies.

arguments
    logPaths (1,:) string
end

rows = table();
for fileIndex = 1:numel(logPaths)
    runs = parse_control_log(logPaths(fileIndex), "A5");
    [~, baseName, ~] = fileparts(logPaths(fileIndex));
    for runIndex = 1:numel(runs)
        run = runs(runIndex);
        if ~isfield(run, "SUMMARY") || height(run.DATA) == 0
            continue
        end
        metric = compute_a5_run_metrics(run);
        row = table(baseName + "#" + string(runIndex), string(run.SUMMARY.Result), ...
            string(run.SUMMARY.MeasurementValid) == "1", metric.Accepted, ...
            metric.P2PRaw, metric.DriftRaw, metric.PopulationSdRaw, metric.RmsRelRaw, ...
            metric.MedianRelRaw, metric.MadRaw, metric.RobustSigmaRaw, ...
            metric.SlopeRawPerSecond, metric.DetrendedSdRaw, metric.MaxAbsStepRaw, ...
            metric.RawCRC32, VariableNames=["Source","Result","MeasurementValid", ...
            "Accepted","P2PRaw","DriftRaw","PopulationSdRaw","RmsRelRaw", ...
            "MedianRelRaw","MadRaw","RobustSigmaRaw","SlopeRawPerSecond", ...
            "DetrendedSdRaw","MaxAbsStepRaw","RawCRC32"]);
        for tauIndex = 1:numel(metric.TauSamples)
            row.("Autocorr" + string(metric.TauSamples(tauIndex)) + "ms") = ...
                metric.Autocorrelation(tauIndex);
            row.("Allan" + string(metric.TauSamples(tauIndex)) + "msRaw") = ...
                metric.AllanDeviationRaw(tauIndex);
        end
        if isempty(rows)
            rows = row;
        else
            rows = [rows; row]; %#ok<AGROW>
        end
    end
end

if isempty(rows)
    error("A5Analysis:NoRuns", "No CONTROL_A5_SUMMARY runs parsed from the given log paths.");
end

result = struct(Runs = rows, ...
    P2PBandRaw = [min(rows.P2PRaw), max(rows.P2PRaw)], ...
    PopulationSdBandRaw = [min(rows.PopulationSdRaw), max(rows.PopulationSdRaw)], ...
    DriftBandRaw = [min(rows.DriftRaw), max(rows.DriftRaw)]);

fprintf("[MATLAB A5] runs=%d valid=%d/%d\n", height(rows), ...
    sum(rows.MeasurementValid), height(rows));
fprintf("[MATLAB A5] P2P band=[%g,%g] raw | population SD band=[%.3f,%.3f] raw | drift band=[%g,%g] raw\n", ...
    result.P2PBandRaw(1), result.P2PBandRaw(2), result.PopulationSdBandRaw(1), ...
    result.PopulationSdBandRaw(2), result.DriftBandRaw(1), result.DriftBandRaw(2));
end
