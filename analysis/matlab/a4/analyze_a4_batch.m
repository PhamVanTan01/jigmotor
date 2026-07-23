function result = analyze_a4_batch(logPaths, expectedProfile, expectedOffsetRaw)
%ANALYZE_A4_BATCH Independent MATLAB re-analysis of an A4/A4B log batch.
%   result = ANALYZE_A4_BATCH(logPaths, expectedProfile, expectedOffsetRaw)
%   parses every file in logPaths (string array), recomputes per-run
%   metrics (compute_a4_run_metrics), and reproduces the acceptance gate
%   from docs/control-a3-result.md section 6 / scripts/analyze_control_a4.ps1:
%   >=5 runs, all runs Result=OK and internally consistent, >=4 electrical
%   quadrants covered, and circular range of FinalOffsetRaw <= 182 raw.

arguments
    logPaths (1,:) string
    expectedProfile (1,1) string
    expectedOffsetRaw (1,1) double
end

cycle = 10923.0;
metrics = table();
for fileIndex = 1:numel(logPaths)
    runs = parse_control_log(logPaths(fileIndex), "A4");
    for runIndex = 1:numel(runs)
        run = runs(runIndex);
        if ~isfield(run, "SUMMARY")
            continue
        end
        metric = compute_a4_run_metrics(run, expectedOffsetRaw);
        profileOk = string(run.SUMMARY.Profile) == expectedProfile;
        resultOk = metric.Result == "OK";
        quadrant = floor(metric.SeedPhaseRaw * 4.0 / cycle) + 1;
        row = struct2table(metric);
        row.Source = fullfile_basename(logPaths(fileIndex)) + "#" + string(runIndex);
        row.ProfileOk = profileOk;
        row.Quadrant = quadrant;
        row.Valid = profileOk && resultOk && metric.CaptureConsistent && ...
            metric.SeedMatchesExpected && metric.SpanMatchesExpected && ...
            metric.SweepTicksMatchesExpected && metric.EvidenceCountMatchesExpected;
        if isempty(metrics)
            metrics = row;
        else
            metrics = [metrics; row]; %#ok<AGROW>
        end
    end
end

if isempty(metrics)
    error("A4Analysis:NoRuns", "No CONTROL_A4_SUMMARY runs parsed from the given log paths.");
end

okRuns = metrics(metrics.Result == "OK",:);
circularStats = compute_circular_stats(okRuns.FinalOffsetRaw, cycle);

quadrantsCovered = numel(unique(metrics.Quadrant(metrics.Valid)));
allValid = all(metrics.Valid);
allOk = all(metrics.Result == "OK");
acceptance = height(metrics) >= 5 && allValid && allOk && ...
    quadrantsCovered >= 4 && circularStats.RangeRaw <= 182.0;

result = struct(Metrics = metrics, CircularStats = circularStats, ...
    QuadrantsCovered = quadrantsCovered, AllValid = allValid, ...
    AllResultsOk = allOk, Acceptance = acceptance);

fprintf("[MATLAB A4] runs=%d valid=%d/%d resultsOk=%d/%d quadrants=%d\n", ...
    height(metrics), sum(metrics.Valid), height(metrics), ...
    sum(metrics.Result == "OK"), height(metrics), quadrantsCovered);
fprintf("[MATLAB A4] FinalOffsetRaw circular mean=%.2f raw SD=%.2f raw range=%.2f raw R=%.5f (limit 182 raw)\n", ...
    circularStats.MeanRaw, circular_stddev(circularStats.ResultantR, cycle), ...
    circularStats.RangeRaw, circularStats.ResultantR);
fprintf("[MATLAB A4] acceptance: %s\n", ternary(acceptance, "PASS", "FAIL"));
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

function sd = circular_stddev(resultantR, cycle)
if resultantR > 0
    sd = sqrt(-2.0 * log(resultantR)) * cycle / (2.0 * pi);
else
    sd = NaN;
end
end
