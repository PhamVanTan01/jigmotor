function export_a2_report(metrics, profileSummary, crosscheck, outputDirectory)
%EXPORT_A2_REPORT Write machine-readable tables and concise decision text.

arguments
    metrics table
    profileSummary table
    crosscheck table
    outputDirectory (1,1) string
end

if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

writetable(metrics, fullfile(outputDirectory, "matlab-run-metrics.csv"));
writetable(profileSummary, ...
    fullfile(outputDirectory, "matlab-profile-summary.csv"));
writetable(crosscheck, ...
    fullfile(outputDirectory, "matlab-crosscheck.csv"));
save(fullfile(outputDirectory, "matlab-analysis.mat"), ...
    "metrics", "profileSummary", "crosscheck");

reportPath = fullfile(outputDirectory, "matlab-decision.txt");
fid = fopen(reportPath, "wt", "n", "UTF-8");
if fid < 0
    error("A2Analysis:ReportOpen", "Cannot create report: %s", reportPath);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, "MATLAB A2-family offline analysis\n");
fprintf(fid, "Generated: %s\n", string(datetime("now", ...
    TimeZone="Asia/Ho_Chi_Minh", Format="yyyy-MM-dd HH:mm:ss Z")));
fprintf(fid, "Cross-check: %d/%d metrics match PowerShell\n\n", ...
    sum(crosscheck.MetricMatch), height(crosscheck));

for index = 1:height(profileSummary)
    row = profileSummary(index,:);
    format = ['%s\n  power=%.1f%% runs=%d pass=%d fault=%d moved=%d\n' ...
        '  maxStep=%g raw maxTravel=%.4f deg\n' ...
        '  settledRange=%.4f deg R=%.4f candidate=%d cluster1deg=%d\n\n'];
    fprintf(fid, format, char(row.Profile), row.PowerPercent, ...
        row.TotalRuns, row.HardPassRuns, ...
        row.FaultRuns, row.MovedRuns, row.MaxAbsStepRaw, ...
        row.MaxAbsTravelDeg, row.SettledRangeDeg, row.SettledResultantR, ...
        row.PowerEnvelopeCandidate, row.WithinOneDegCluster);
end

fprintf(fid, ['Interpretation rules:\n' ...
    '- PowerEnvelopeCandidate means all included runs were safe and moved >0.1 deg.\n' ...
    '- WithinOneDegCluster is diagnostic only, not an official acceptance gate.\n' ...
    '- MATLAB never authorizes a higher hardware power after a hard-gate fault.\n']);
end
