function group = build_nl_group_curve(files, motorId, jigId, k)
%BUILD_NL_GROUP_CURVE MATLAB counterpart to tools/analyze_nl_extreme_angles.py's
%   build_group_curve(): batch-mean error curve (point-by-point average
%   over all eligible runs), per-point SD, the top/bottom-K extreme points
%   of the BATCH-MEAN curve, and how often each point index appears in any
%   INDIVIDUAL run's own top/bottom-K (selection frequency -- this is what
%   distinguishes "these points are genuinely repeatable" from "random
%   SPI/encoder jitter", per docs/nl-extreme-angle-cross-jig-test33-
%   assessment.md).
%
%   Built as an independent cross-check of tools/analyze_nl_extreme_angles.py
%   (same purpose compute_nl_sweep_metrics.m already serves against
%   tools/analyze_nl_stability.py) -- both should keep agreeing on real
%   data; a real disagreement is a bug in one of the two, not something to
%   paper over.

arguments
    files (1,:) string
    motorId (1,1) string
    jigId (1,1) string
    k (1,1) double = 5
end

allErrors = {};
n = NaN;
for fileIndex = 1:numel(files)
    sweeps = parse_nl_log(files(fileIndex));
    for sweepIndex = 1:numel(sweeps)
        sweep = sweeps(sweepIndex);
        if ~isfield(sweep, "Meta") || isempty(fieldnames(sweep.Meta))
            continue
        end
        if ~valid_official_sweep_for_extremes(sweep)
            continue
        end
        data = sortrows(sweep.Data, "Index");
        analysisPoints = str2double(sweep.Meta.AnalysisPoints);
        data = data(data.Index < analysisPoints, :);
        if isnan(n)
            n = analysisPoints;
        elseif analysisPoints ~= n
            error("NlExtremeAngles:MixedAnalysisPoints", ...
                "%s/%s: mixed AnalysisPoints values (%d vs %d)", ...
                motorId, jigId, n, analysisPoints);
        end
        allErrors{end + 1} = data.ErrorDeg(:)'; %#ok<AGROW>
    end
end

if isempty(allErrors)
    error("NlExtremeAngles:NoEligibleSweeps", ...
        "%s/%s: no statistically eligible sweeps", motorId, jigId);
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
topIndices = orderDesc(1:k) - 1;      % 0-based point index (matches firmware DATA.Index / Python)
bottomIndices = orderAsc(1:k) - 1;

topFrequency = zeros(n, 1);
bottomFrequency = zeros(n, 1);
runTopMeans = zeros(nRuns, 1);
runBottomMeans = zeros(nRuns, 1);
for runIndex = 1:nRuns
    curve = errorMatrix(runIndex, :)';
    [~, runOrderDesc] = sort(curve, "descend");
    [~, runOrderAsc] = sort(curve, "ascend");
    runTopIdx = runOrderDesc(1:k);    % 1-based array positions into curve
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

function valid = valid_official_sweep_for_extremes(sweep)
valid = false;
% Matches analyze_motor_logs.py's officially_valid rule: reject only when
% RunRole is DECLARED and not OFFICIAL; legacy records with no RunRole
% field at all are still admitted (same allowance the Python tool makes).
if isfield(sweep.Meta, "RunRole") && string(sweep.Meta.RunRole) ~= "OFFICIAL"
    return
end
if ~isfield(sweep.Meta, "AnalysisPoints") || str2double(sweep.Meta.AnalysisPoints) <= 0
    return
end
if ~isfield(sweep.Meta, "EligibleForStatistics") || string(sweep.Meta.EligibleForStatistics) ~= "1"
    return
end
if ~isfield(sweep.Meta, "MeasurementValid") || string(sweep.Meta.MeasurementValid) ~= "1"
    return
end
if ~isfield(sweep, "END") || ~isfield(sweep.END, "Status") || string(sweep.END.Status) ~= "VALID"
    return
end
analysisPoints = str2double(sweep.Meta.AnalysisPoints);
presentCount = sum(sweep.Data.Index < analysisPoints);
if presentCount ~= analysisPoints
    return
end
valid = true;
end
