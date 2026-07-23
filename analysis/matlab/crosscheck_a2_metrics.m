function result = crosscheck_a2_metrics(summaryRow, metric)
%CROSSCHECK_A2_METRICS Compare independent MATLAB metrics with PowerShell.

arguments
    summaryRow table
    metric table
end

finalDiffMilliDeg = abs(metric.FinalTravelDeg*1000 - ...
    scalar_number(summaryRow.FinalTravelMilliDeg));
maxTravelDiffMilliDeg = abs(metric.MaxAbsTravelDeg*1000 - ...
    scalar_number(summaryRow.MaxAbsTravelMilliDeg));
stepDiffRaw = abs(metric.MaxAbsStepRaw - scalar_number(summaryRow.MaxAbsStepRaw));
holdDiffMilliDeg = nan_difference(metric.HoldDriftDeg*1000, ...
    scalar_number_allow_nan(summaryRow.HoldDriftMilliDeg));
settledDiffRaw = circular_difference(metric.SettledModuloRaw, ...
    scalar_number_allow_nan(summaryRow.SettledModuloRaw), 10923.0);

metricMatch = finalDiffMilliDeg <= 0.6 && maxTravelDiffMilliDeg <= 0.6 && ...
    stepDiffRaw == 0 && holdDiffMilliDeg <= 0.6 && settledDiffRaw <= 0.001;
result = table(metric.Run, finalDiffMilliDeg, maxTravelDiffMilliDeg, ...
    stepDiffRaw, holdDiffMilliDeg, settledDiffRaw, metricMatch, ...
    VariableNames=["Run","FinalDiffMilliDeg","MaxTravelDiffMilliDeg", ...
    "StepDiffRaw","HoldDiffMilliDeg","SettledDiffRaw","MetricMatch"]);
end

function value = scalar_number(input)
value = scalar_number_allow_nan(input);
if ~isfinite(value)
    error("A2Analysis:CrosscheckNumeric", "Expected a finite scalar number.");
end
end

function value = scalar_number_allow_nan(input)
if isnumeric(input) || islogical(input)
    value = double(input(1));
else
    text = string(input(1));
    value = str2double(text);
end
end

function difference = nan_difference(left, right)
if isnan(left) && isnan(right)
    difference = 0;
elseif isnan(left) || isnan(right)
    difference = Inf;
else
    difference = abs(left-right);
end
end

function difference = circular_difference(left, right, period)
if isnan(left) && isnan(right)
    difference = 0;
elseif isnan(left) || isnan(right)
    difference = Inf;
else
    difference = abs(mod(left-right+period/2, period)-period/2);
end
end
