function crosscheck = crosscheck_a4_metrics(matlabMetrics, powerShellSummaryCsv)
%CROSSCHECK_A4_METRICS Compare MATLAB's independent A4 metrics against the
%   PowerShell analyzer's -SummaryCsv output for the same runs, matched by
%   the shared "Source" column (e.g. "A4B test 1#1").

arguments
    matlabMetrics table
    powerShellSummaryCsv (1,1) string
end

psTable = readtable(powerShellSummaryCsv, TextType="string", VariableNamingRule="preserve");

n = height(matlabMetrics);
source = strings(n, 1);
finalOffsetDiffRaw = NaN(n, 1);
holdTail20DiffRaw = NaN(n, 1);
rampStepDiffRaw = NaN(n, 1);
sweepStepDiffRaw = NaN(n, 1);
matched = false(n, 1);
metricMatch = false(n, 1);

for index = 1:n
    source(index) = matlabMetrics.Source(index);
    psRow = psTable(psTable.Source == source(index),:);
    if height(psRow) ~= 1
        continue
    end
    matched(index) = true;
    finalOffsetDiffRaw(index) = circular_abs_diff( ...
        matlabMetrics.FinalOffsetRaw(index), psRow.FinalOffsetRaw(1), 10923.0);
    holdTail20DiffRaw(index) = nan_safe_diff( ...
        matlabMetrics.HoldTail20P2PRaw(index), psRow.HoldTail20P2PRaw(1));
    rampStepDiffRaw(index) = abs( ...
        matlabMetrics.RampMaxStepRawEvidence(index) - psRow.RampMaxStepRawEvidence(1));
    sweepStepDiffRaw(index) = abs( ...
        matlabMetrics.SweepMaxStepRawEvidence(index) - psRow.SweepMaxStepRawEvidence(1));
    metricMatch(index) = finalOffsetDiffRaw(index) <= 0.001 && ...
        holdTail20DiffRaw(index) <= 0.001 && rampStepDiffRaw(index) == 0 && ...
        sweepStepDiffRaw(index) == 0;
end

crosscheck = table(source, matched, finalOffsetDiffRaw, holdTail20DiffRaw, ...
    rampStepDiffRaw, sweepStepDiffRaw, metricMatch, VariableNames=["Source", ...
    "Matched","FinalOffsetDiffRaw","HoldTail20DiffRaw","RampStepDiffRaw", ...
    "SweepStepDiffRaw","MetricMatch"]);
end

function value = nan_safe_diff(left, right)
if isnan(left) && isnan(right)
    value = 0;
elseif isnan(left) || isnan(right)
    value = Inf;
else
    value = abs(left - right);
end
end

function value = circular_abs_diff(left, right, period)
value = abs(mod(left - right + period / 2.0, period) - period / 2.0);
end
