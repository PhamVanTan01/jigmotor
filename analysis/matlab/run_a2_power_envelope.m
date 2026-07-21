function results = run_a2_power_envelope(summaryCsv, evidenceDirectory, outputDirectory)
%RUN_A2_POWER_ENVELOPE Offline A2-family analysis entry point.
%   summaryCsv and evidenceDirectory are paired string arrays (one entry per
%   profile/batch, e.g. P06/P07/P08/P10) so cross-power-level trend analysis
%   (circular significance, safety-envelope regression) can see every tested
%   level in one report instead of one profile at a time.

arguments
    summaryCsv (1,:) string
    evidenceDirectory (1,:) string
    outputDirectory (1,1) string
end

if numel(summaryCsv) ~= numel(evidenceDirectory)
    error("A2Analysis:BatchMismatch", ...
        "summaryCsv (%d) and evidenceDirectory (%d) must have equal length.", ...
        numel(summaryCsv), numel(evidenceDirectory));
end

if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
runPlotDirectory = fullfile(outputDirectory, "runs");
if ~isfolder(runPlotDirectory)
    mkdir(runPlotDirectory);
end

summary = table();
metrics = table();
crosscheck = table();
for batchIndex = 1:numel(summaryCsv)
    batchSummary = load_a2_summary(summaryCsv(batchIndex));
    if ~isfolder(evidenceDirectory(batchIndex))
        error("A2Analysis:EvidenceDirectory", ...
            "Evidence directory not found: %s", evidenceDirectory(batchIndex));
    end

    for index = 1:height(batchSummary)
        row = batchSummary(index,:);
        [evidence, evidencePath] = load_a2_evidence(string(row.Run), ...
            evidenceDirectory(batchIndex));
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

    if isempty(summary)
        summary = batchSummary;
    else
        summary = [summary; batchSummary]; %#ok<AGROW>
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
circularSignificance = build_a2_circular_significance(metrics);
safetyEnvelope = build_a2_safety_envelope(metrics);
ceilingEstimate = estimate_a2_power_ceiling(safetyEnvelope);
harmonicFit = fit_a2_restoring_torque(metrics);
plotPaths = plot_a2_power_envelope(metrics, outputDirectory);
export_a2_report(metrics, profileSummary, crosscheck, ...
    circularSignificance, safetyEnvelope, ceilingEstimate, harmonicFit, ...
    outputDirectory);

fprintf("[MATLAB] Runs=%d included=%d duplicates=%d crosscheck=%d/%d\n", ...
    height(metrics), sum(metrics.Included), sum(~metrics.Included), ...
    sum(crosscheck.MetricMatch), height(crosscheck));
disp(profileSummary(:, ["Profile","PowerPercent","TotalRuns", ...
    "HardPassRuns","MovedRuns","MaxAbsStepRaw","SettledRangeDeg", ...
    "SettledResultantR","PowerEnvelopeCandidate", ...
    "WithinOneDegCluster"]));
disp(circularSignificance);
disp(safetyEnvelope(:, ["Profile","PowerPercent","FaultRuns", ...
    "FaultKinds","StepBudgetFraction","TravelBudgetFraction"]));
fprintf("[MATLAB] Linear-extrapolated ceiling (diagnostic only): step=%.2f%% travel=%.2f%%\n", ...
    ceilingEstimate.StepCeilingPercent, ceilingEstimate.TravelCeilingPercent);
disp(harmonicFit.PerLevel);
fprintf("[MATLAB] Pooled harmonic fit (all safe runs, all power levels): N=%d amplitude=%.2f raw phase=%.1f raw (%.2f deg) R2=%.4f p=%.6f\n", ...
    harmonicFit.Pooled.N, harmonicFit.Pooled.AmplitudeRaw, ...
    harmonicFit.Pooled.PhaseRaw, harmonicFit.Pooled.PhaseDeg, ...
    harmonicFit.Pooled.RSquared, harmonicFit.Pooled.PValue);

results = struct(Summary=summary, Metrics=metrics, ...
    ProfileSummary=profileSummary, Crosscheck=crosscheck, ...
    CircularSignificance=circularSignificance, ...
    SafetyEnvelope=safetyEnvelope, CeilingEstimate=ceilingEstimate, ...
    HarmonicFit=harmonicFit, PlotPaths=plotPaths);
end
