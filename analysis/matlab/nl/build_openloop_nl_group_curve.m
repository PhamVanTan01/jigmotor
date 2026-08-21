function group = build_openloop_nl_group_curve(files, motorId, jigId, k)
%BUILD_OPENLOOP_NL_GROUP_CURVE Schema-v6 counterpart to build_nl_group_curve.m.
%   Same batch-mean error curve / top-bottom-K extreme-point summary,
%   built from parse_openloop_nl_log.m's IsOpenLoopOfficial-gated sweeps
%   (RULE 0: MeasurementProfile=GREMSY_COMPAT_OPEN_LOOP_NL_V1,
%   OfficialOpenLoopNL=1, FeedbackActuationEnabled=0, RunRole=OFFICIAL,
%   EligibleForStatistics=1) instead of build_nl_group_curve.m's schema
%   v4/v5 gate. Output struct has the exact same field set, so it plugs
%   directly into compare_nl_group_curves.m unchanged.

arguments
    files (1,:) string
    motorId (1,1) string
    jigId (1,1) string
    k (1,1) double = 5
end

allErrors = {};
n = NaN;
for fileIndex = 1:numel(files)
    sweeps = parse_openloop_nl_log(files(fileIndex));
    for sweepIndex = 1:numel(sweeps)
        sweep = sweeps(sweepIndex);
        if ~sweep.IsOpenLoopOfficial
            continue
        end
        data = sortrows(sweep.Data, "Index");
        analysisPoints = sweep.Meta.AnalysisPoints;
        if isnan(analysisPoints) || analysisPoints <= 0
            continue
        end
        data = data(data.Index < analysisPoints, :);
        if height(data) ~= analysisPoints
            continue
        end
        if isnan(n)
            n = analysisPoints;
        elseif analysisPoints ~= n
            error("OpenLoopNlGroupCurve:MixedAnalysisPoints", ...
                "%s/%s: mixed AnalysisPoints values (%d vs %d)", ...
                motorId, jigId, n, analysisPoints);
        end
        allErrors{end + 1} = data.ErrorDeg(:)'; %#ok<AGROW>
    end
end

if isempty(allErrors)
    error("OpenLoopNlGroupCurve:NoEligibleSweeps", ...
        "%s/%s: no RULE-0-eligible open-loop OFFICIAL sweeps", motorId, jigId);
end

errorMatrix = vertcat(allErrors{:});
nRuns = size(errorMatrix, 1);
meanError = mean(errorMatrix, 1)';
if nRuns > 1
    sdError = std(errorMatrix, 0, 1)';
else
    sdError = zeros(n, 1);
end

k = min(max(k, 1), n);
[~, orderDesc] = sort(meanError, "descend");
[~, orderAsc] = sort(meanError, "ascend");
topIndices = orderDesc(1:k) - 1;
bottomIndices = orderAsc(1:k) - 1;

topFrequency = zeros(n, 1);
bottomFrequency = zeros(n, 1);
runTopMeans = zeros(nRuns, 1);
runBottomMeans = zeros(nRuns, 1);
for runIndex = 1:nRuns
    curve = errorMatrix(runIndex, :)';
    [~, runOrderDesc] = sort(curve, "descend");
    [~, runOrderAsc] = sort(curve, "ascend");
    runTopIdx = runOrderDesc(1:k);
    runBottomIdx = runOrderAsc(1:k);
    topFrequency(runTopIdx) = topFrequency(runTopIdx) + 1;
    bottomFrequency(runBottomIdx) = bottomFrequency(runBottomIdx) + 1;
    runTopMeans(runIndex) = mean(curve(runTopIdx));
    runBottomMeans(runIndex) = mean(curve(runBottomIdx));
end

group = struct( ...
    MotorId = motorId, JigId = jigId, AnalysisPoints = n, EligibleRuns = nRuns, ...
    MeanError = meanError, SdError = sdError, ...
    TopIndices = topIndices, BottomIndices = bottomIndices, ...
    TopFrequency = topFrequency, BottomFrequency = bottomFrequency, ...
    RunTopMeans = runTopMeans, RunBottomMeans = runBottomMeans);
end
