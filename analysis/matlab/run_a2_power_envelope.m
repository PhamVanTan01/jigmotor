function results = run_a2_power_envelope(summaryCsv, evidenceDirectory, outputDirectory)
%RUN_A2_POWER_ENVELOPE Offline A2/A2B/A2C/A2D/A2E analysis entry point.

arguments
    summaryCsv (1,1) string
    evidenceDirectory (1,1) string
    outputDirectory (1,1) string
end

summary = load_a2_summary(summaryCsv);
if ~isfolder(evidenceDirectory)
    error("A2Analysis:EvidenceDirectory", ...
        "Evidence directory not found: %s", evidenceDirectory);
end
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
runPlotDirectory = fullfile(outputDirectory, "runs");
if ~isfolder(runPlotDirectory)
    mkdir(runPlotDirectory);
end

metrics = table();
crosscheck = table();
for index = 1:height(summary)
    row = summary(index,:);
    [evidence, evidencePath] = load_a2_evidence(string(row.Run), ...
        evidenceDirectory);
    hash = sha256_file(evidencePath);
    metric = compute_a2_metrics(row, evidence, hash);
    check = crosscheck_a2_metrics(row, metric);
    plot_a2_run(metric, evidence, runPlotDirectory);

    if isempty(metrics)
        metrics = metric;
        crosscheck = check;
    else
        metrics = [metrics; metric]; %#ok<AGROW>
        crosscheck = [crosscheck; check]; %#ok<AGROW>
    end
end

for index = 1:height(metrics)
    prior = find(metrics.EvidenceHash(1:index-1) == ...
        metrics.EvidenceHash(index), 1, "first");
    if ~isempty(prior)
        metrics.DuplicateOf(index) = metrics.Run(prior);
        metrics.Included(index) = false;
    end
end

profileSummary = build_a2_profile_summary(metrics);
plotPaths = plot_a2_power_envelope(metrics, outputDirectory);
export_a2_report(metrics, profileSummary, crosscheck, outputDirectory);

fprintf("[MATLAB] Runs=%d included=%d duplicates=%d crosscheck=%d/%d\n", ...
    height(metrics), sum(metrics.Included), sum(~metrics.Included), ...
    sum(crosscheck.MetricMatch), height(crosscheck));
disp(profileSummary(:, ["Profile","PowerPercent","TotalRuns", ...
    "HardPassRuns","MovedRuns","MaxAbsStepRaw","SettledRangeDeg", ...
    "SettledResultantR","PowerEnvelopeCandidate", ...
    "WithinOneDegCluster"]));

results = struct(Summary=summary, Metrics=metrics, ...
    ProfileSummary=profileSummary, Crosscheck=crosscheck, ...
    PlotPaths=plotPaths);
end
