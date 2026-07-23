function crosscheck = crosscheck_a5_metrics(matlabRuns, powerShellSummaryCsv)
%CROSSCHECK_A5_METRICS Compare MATLAB's independent A5 metrics against the
%   PowerShell analyzer's -SummaryCsv output for the same runs, matched by
%   the shared "Source" column. NOTE: read the PowerShell A5 summary CSV
%   with an explicit Delimiter="," -- MATLAB's readtable auto-detection
%   mis-guesses ";" as the delimiter because the (unused here) DeltaHistogram
%   column embeds many semicolons.

arguments
    matlabRuns table
    powerShellSummaryCsv (1,1) string
end

psTable = readtable(powerShellSummaryCsv, TextType="string", ...
    VariableNamingRule="preserve", Delimiter=",");

compareFields = ["P2PRaw","DriftRaw","PopulationSdRaw","RmsRelRaw","MedianRelRaw", ...
    "MadRaw","RobustSigmaRaw","SlopeRawPerSecond","DetrendedSdRaw","MaxAbsStepRaw", ...
    "RawCRC32","Autocorr1ms","Autocorr128ms","Allan1msRaw","Allan128msRaw"];

n = height(matlabRuns);
source = strings(n, 1);
matched = false(n, 1);
metricMatch = false(n, 1);
maxAbsDiff = NaN(n, 1);

for index = 1:n
    source(index) = matlabRuns.Source(index);
    psRow = psTable(psTable.Source == source(index),:);
    if height(psRow) ~= 1
        continue
    end
    matched(index) = true;
    diffs = zeros(1, numel(compareFields));
    for fieldIndex = 1:numel(compareFields)
        name = compareFields(fieldIndex);
        diffs(fieldIndex) = abs(double(matlabRuns.(name)(index)) - double(psRow.(name)(1)));
    end
    maxAbsDiff(index) = max(diffs);
    metricMatch(index) = maxAbsDiff(index) <= 1e-6;
end

crosscheck = table(source, matched, maxAbsDiff, metricMatch, ...
    VariableNames=["Source","Matched","MaxAbsDiff","MetricMatch"]);
end
