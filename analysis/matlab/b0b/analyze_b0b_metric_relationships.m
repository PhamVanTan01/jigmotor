function relationships = analyze_b0b_metric_relationships(inputCsv, outputDirectory)
%ANALYZE_B0B_METRIC_RELATIONSHIPS Find repeatable within-product co-movement.
%   Batch-centering removes between-motor/between-session offsets. Linear
%   detrending against RunOrder then removes a common warm-up/time trend.
%   Per-batch correlation signs show whether a pooled relationship is shared
%   by the products or is driven by only one batch.

arguments
    inputCsv (1,1) string
    outputDirectory (1,1) string
end

if ~isfile(inputCsv)
    error("B0BRelationships:Input", "Input CSV not found: %s", inputCsv);
end
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

data = readtable(inputCsv, TextType="string", VariableNamingRule="preserve");
required = ["Batch","RunOrder"];
if ~all(ismember(required, string(data.Properties.VariableNames)))
    error("B0BRelationships:Schema", "Input requires Batch and RunOrder.");
end

requestedMetrics = [ ...
    "NL_RobustP2P","MeanDC","RMS_AC","A1","A2","A3","A6","A9", ...
    "A12","A18","A27","A36","A45","A72","A108", ...
    "Residual_RMS_H6","Residual_RMS_H36","Residual_RMS_Full", ...
    "Residual_RMS_Extended","Fitted_P2P","Fitted_P2P_Extended", ...
    "FitExplainedRatio","FitExplainedRatio_Extended", ...
    "Motor_Error_P2P_Deg","Motor_System_INL_Deg","CrestFactor", ...
    "P99_AbsDeviation","TrackingError_RMS_Deg", ...
    "TrackingError_MaxAbs_Deg","ClosureErrorDeg","AbsClosureErrorDeg", ...
    "ShadowP2P","BackoffFeedforwardTargetErrorRaw", ...
    "ForwardFeedforwardTargetErrorRaw","BackoffTargetErrorRaw", ...
    "ApproachTargetErrorRaw","ApproachReturnErrorRaw", ...
    "AbsApproachReturnErrorRaw","BackoffObservedDeltaRaw", ...
    "ApproachObservedDeltaRaw","AnalysisStartRaw", ...
    "MaxAbsSettlePositionErrorDeg","MotorActiveDurationMs", ...
    "TimeSincePreviousRunMs"];
metricNames = requestedMetrics(ismember(requestedMetrics, ...
    string(data.Properties.VariableNames)));

nRows = height(data);
nMetrics = numel(metricNames);
centered = NaN(nRows, nMetrics);
detrended = NaN(nRows, nMetrics);
batches = unique(data.Batch, "stable");

for batchIndex = 1:numel(batches)
    rowMask = data.Batch == batches(batchIndex);
    runOrder = double(data.RunOrder(rowMask));
    for metricIndex = 1:nMetrics
        values = double(data.(metricNames(metricIndex))(rowMask));
        finite = isfinite(values) & isfinite(runOrder);
        centeredValues = NaN(size(values));
        detrendedValues = NaN(size(values));
        if any(finite)
            centeredValues(finite) = values(finite) - mean(values(finite));
        end
        if sum(finite) >= 3
            design = [ones(sum(finite),1), runOrder(finite)];
            detrendedValues(finite) = values(finite) - design*(design\values(finite));
        end
        centered(rowMask, metricIndex) = centeredValues;
        detrended(rowMask, metricIndex) = detrendedValues;
    end
end

pairCount = nMetrics*(nMetrics-1)/2;
metricX = strings(pairCount,1);
metricY = strings(pairCount,1);
n = zeros(pairCount,1);
rCentered = NaN(pairCount,1);
pCentered = NaN(pairCount,1);
rDetrended = NaN(pairCount,1);
pDetrended = NaN(pairCount,1);
batchValid = zeros(pairCount,1);
batchSameDirection = zeros(pairCount,1);
batchOppositeDirection = zeros(pairCount,1);
medianBatchR = NaN(pairCount,1);

pairIndex = 0;
for xIndex = 1:nMetrics-1
    for yIndex = xIndex+1:nMetrics
        pairIndex = pairIndex + 1;
        metricX(pairIndex) = metricNames(xIndex);
        metricY(pairIndex) = metricNames(yIndex);
        [rCentered(pairIndex), pCentered(pairIndex), n(pairIndex)] = ...
            pearson_test(centered(:,xIndex), centered(:,yIndex));
        [rDetrended(pairIndex), pDetrended(pairIndex)] = ...
            pearson_test(detrended(:,xIndex), detrended(:,yIndex));

        batchR = NaN(numel(batches),1);
        for batchIndex = 1:numel(batches)
            rowMask = data.Batch == batches(batchIndex);
            batchR(batchIndex) = pearson_test( ...
                detrended(rowMask,xIndex), detrended(rowMask,yIndex));
        end
        finiteBatch = isfinite(batchR);
        batchValid(pairIndex) = sum(finiteBatch);
        if any(finiteBatch) && isfinite(rDetrended(pairIndex))
            pooledSign = sign(rDetrended(pairIndex));
            batchSameDirection(pairIndex) = sum(sign(batchR(finiteBatch)) == pooledSign);
            batchOppositeDirection(pairIndex) = sum(sign(batchR(finiteBatch)) == -pooledSign);
            medianBatchR(pairIndex) = median(batchR(finiteBatch));
        end
    end
end

relationships = table(metricX, metricY, n, rCentered, pCentered, ...
    rDetrended, pDetrended, batchValid, batchSameDirection, ...
    batchOppositeDirection, medianBatchR, ...
    VariableNames=["MetricX","MetricY","N","RCentered","PCentered", ...
    "RDetrended","PDetrended","BatchValid","BatchSameDirection", ...
    "BatchOppositeDirection","MedianBatchR"]);
relationships.AbsRDetrended = abs(relationships.RDetrended);
relationships = sortrows(relationships, "AbsRDetrended", "descend");
writetable(relationships, fullfile(outputDirectory, ...
    "b0b_metric_relationships.csv"));

common = relationships(relationships.AbsRDetrended >= 0.45 & ...
    relationships.PDetrended <= 0.01 & relationships.BatchSameDirection >= 6,:);
writetable(common, fullfile(outputDirectory, ...
    "b0b_common_relationships.csv"));

fprintf("[B0B] rows=%d batches=%d metrics=%d pairs=%d common=%d\n", ...
    nRows, numel(batches), nMetrics, height(relationships), height(common));
disp(common(:,["MetricX","MetricY","RDetrended","PDetrended", ...
    "BatchSameDirection","BatchValid","MedianBatchR"]));
end

function [r, p, n] = pearson_test(x, y)
finite = isfinite(x) & isfinite(y);
x = double(x(finite));
y = double(y(finite));
n = numel(x);
if n < 3 || std(x) == 0 || std(y) == 0
    r = NaN;
    p = NaN;
    return
end
x = x - mean(x);
y = y - mean(y);
r = sum(x.*y)/sqrt(sum(x.^2)*sum(y.^2));
r = min(max(r,-1),1);
if abs(r) >= 1
    p = 0;
else
    df = n - 2;
    tSquared = r^2*df/(1-r^2);
    p = betainc(df/(df+tSquared), df/2, 0.5);
end
end
