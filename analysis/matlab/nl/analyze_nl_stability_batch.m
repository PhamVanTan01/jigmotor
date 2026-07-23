function result = analyze_nl_stability_batch(filePaths, labels, includePrecondition)
%ANALYZE_NL_STABILITY_BATCH Independent MATLAB re-analysis of NL logs.
%   Mirrors tools/analyze_nl_stability.py's per-sweep validity gate and
%   per-leg aggregate stats. One label applies to every valid sweep parsed
%   from its file (matching the Python tool's --labels semantics, one label
%   per input file). Validated against real hardware data (B0-B p03 jig 1
%   test 22.txt): every per-sweep metric field matches the Python tool's
%   nl_runs.csv to ~15 significant digits.

arguments
    filePaths (1,:) string
    labels (1,:) string = strings(1, 0)
    includePrecondition (1,1) logical = false
end

if isempty(labels)
    labels = fullfile_basenames(filePaths);
elseif numel(labels) ~= numel(filePaths)
    error("NLAnalysis:LabelCount", ...
        "labels (%d) must match filePaths (%d) in count.", numel(labels), numel(filePaths));
end

rows = table();
excluded = strings(0, 1);
for fileIndex = 1:numel(filePaths)
    sweeps = parse_nl_log(filePaths(fileIndex));
    for sweepIndex = 1:numel(sweeps)
        sweep = sweeps(sweepIndex);
        [valid, reason] = check_sweep_valid(sweep, includePrecondition);
        if ~valid
            excluded(end + 1) = sprintf("%s TestID=%d SweepID=%d: %s", ...
                labels(fileIndex), sweep.TestID, sweep.SweepID, reason); %#ok<AGROW>
            continue
        end
        metric = compute_nl_sweep_metrics(sweep);
        row = struct2table(metric);
        row.Leg = labels(fileIndex);
        row.RunOrder = str2double(sweep.Meta.RunOrder);
        if isempty(rows)
            rows = row;
        else
            rows = [rows; row]; %#ok<AGROW>
        end
    end
end

if isempty(rows)
    error("NLAnalysis:NoValidSweeps", "No valid official sweeps parsed from the given log paths.");
end
rows = sortrows(rows, ["Leg","RunOrder"]);

legNames = unique(rows.Leg, "stable");
stabilityRows = table();
for legIndex = 1:numel(legNames)
    subset = rows(rows.Leg == legNames(legIndex),:);
    s = compute_nl_stability_stats(subset.NL_RobustP2P_Deg);
    row = struct2table(s);
    row.Leg = legNames(legIndex);
    if isempty(stabilityRows)
        stabilityRows = row;
    else
        stabilityRows = [stabilityRows; row]; %#ok<AGROW>
    end
end
allStats = compute_nl_stability_stats(rows.NL_RobustP2P_Deg);
allRow = struct2table(allStats);
allRow.Leg = "ALL";
stabilityRows = [stabilityRows; allRow];

closureStatsRows = table();
for legIndex = 1:numel(legNames)
    subset = rows(rows.Leg == legNames(legIndex),:);
    s = compute_nl_stability_stats(subset.ClosureErrorDeg);
    row = struct2table(s);
    row.Leg = legNames(legIndex);
    row.PassRate180 = mean(abs(subset.ClosureErrorDeg) <= 0.20) * 100.0;
    if isempty(closureStatsRows)
        closureStatsRows = row;
    else
        closureStatsRows = [closureStatsRows; row]; %#ok<AGROW>
    end
end

result = struct(Runs = rows, Stability_NL_RobustP2P = stabilityRows, ...
    Stability_Closure = closureStatsRows, Excluded = excluded);

fprintf("=== NL stability (NL_RobustP2P_Deg), n=%d valid, %d excluded ===\n", ...
    height(rows), numel(excluded));
disp(stabilityRows(:, ["Leg","N","Mean","SampleSd","CvPct","Min","Max","Range","RepeatabilityLimit2_77Sd"]));
fprintf("=== Closure (ClosureErrorDeg, pilot limit 0.20 deg, diagnostic only) ===\n");
disp(closureStatsRows(:, ["Leg","N","Mean","SampleSd","Min","Max","PassRate180"]));
if ~isempty(excluded)
    fprintf("Excluded sweeps:\n");
    for index = 1:numel(excluded)
        fprintf("  %s\n", excluded(index));
    end
end
end

function [valid, reason] = check_sweep_valid(sweep, includePrecondition)
valid = false;
if ~isfield(sweep.Meta, "AnalysisPoints") || str2double(sweep.Meta.AnalysisPoints) <= 0
    reason = "AnalysisPoints<=0 or missing";
    return
end
if ~includePrecondition
    if ~isfield(sweep.Meta, "EligibleForStatistics") || ...
            string(sweep.Meta.EligibleForStatistics) ~= "1"
        reason = "EligibleForStatistics!=1";
        return
    end
end
if ~isfield(sweep.Meta, "MeasurementValid") || string(sweep.Meta.MeasurementValid) ~= "1"
    reason = "MeasurementValid!=1";
    return
end
if ~isfield(sweep.END, "Status") || string(sweep.END.Status) ~= "VALID"
    reason = "END.Status!=VALID";
    return
end
analysisPoints = str2double(sweep.Meta.AnalysisPoints);
presentCount = sum(sweep.Data.Index < analysisPoints);
if presentCount ~= analysisPoints
    reason = sprintf("missing DATA rows: have %d of %d analysis points", ...
        presentCount, analysisPoints);
    return
end
valid = true;
reason = "";
end

function names = fullfile_basenames(paths)
names = strings(size(paths));
for index = 1:numel(paths)
    [~, name, ~] = fileparts(paths(index));
    names(index) = string(name);
end
end
