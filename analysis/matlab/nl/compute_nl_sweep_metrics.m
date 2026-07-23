function metric = compute_nl_sweep_metrics(sweep)
%COMPUTE_NL_SWEEP_METRICS Independent recompute of one sweep's NL metrics.
%   Mirrors tools/analyze_nl_stability.py's validate_and_compute() core
%   arithmetic. ClosureErrorDeg is NOT recomputed here -- neither the
%   Python tool nor firmware derives it from the DATA array in this path;
%   it is read straight from the SHADOW_RESULT record (the canonical
%   closure result), exactly like the reference tool.

arguments
    sweep struct
end

% Metrics use only the AnalysisPoints window (0..AnalysisPoints-1) -- DATA
% also logs closure (point AnalysisPoints) and margin points beyond it
% (e.g. 360 analysis points out of 371 logged samples on the 1deg grid),
% which must NOT be folded into MeanDC/RMS_AC/RobustP2P/A36.
data = sortrows(sweep.Data, "Index");
analysisPoints = str2double(sweep.Meta.AnalysisPoints);
data = data(data.Index < analysisPoints, :);
errors = data.ErrorDeg;
n = height(data);

meanDc = mean(errors);
centered = errors - meanDc;
rmsAc = sqrt(mean(centered.^2));

sortedErrors = sort(errors);
robustCount = min(5, floor(n / 2));
topMean = mean(sortedErrors(end - robustCount + 1:end));
bottomMean = mean(sortedErrors(1:robustCount));
robustP2P = topMean - bottomMean;

rawP2P = max(errors) - min(errors);
systemInl = rawP2P / 2.0;

order = 36;
angleIndex = data.Index; % firmware-native 0-based sample index
a = sum(centered .* cos(2 * pi * order * angleIndex / n));
b = sum(centered .* sin(2 * pi * order * angleIndex / n));
aCoeff = 2.0 * a / n;
bCoeff = 2.0 * b / n;
a36 = hypot(aCoeff, bCoeff);

closureErrorDeg = shadow_field(sweep, "ClosureErrorDeg");
shadowP2P = shadow_field(sweep, "P2P");
firmwareShadowRmsAc = shadow_field(sweep, "RMS_AC");
firmwareShadowA36 = shadow_field(sweep, "A36");

approachReturnErrorRaw = approach_field(sweep, "ApproachReturnErrorRaw");
approachReturnErrorDeg = approachReturnErrorRaw * 360.0 / 65536.0;

metric = struct( ...
    TestID = sweep.TestID, SweepID = sweep.SweepID, N = n, ...
    MeanDC_Deg = meanDc, RMS_AC_Deg = rmsAc, NL_RobustP2P_Deg = robustP2P, ...
    RawP2P_Deg = rawP2P, SystemINL_Deg = systemInl, A36_Deg = a36, ...
    ClosureErrorDeg = closureErrorDeg, ShadowP2P_Deg = shadowP2P, ...
    FirmwareShadowRMS_AC_Deg = firmwareShadowRmsAc, ...
    FirmwareShadowA36_Deg = firmwareShadowA36, ...
    FirmwareNL_Deg = sweep.FirmwareNLDeg, ...
    ApproachReturnErrorRaw = approachReturnErrorRaw, ...
    ApproachReturnErrorDeg = approachReturnErrorDeg, ...
    RMS_RecomputeDelta_Deg = rmsAc - firmwareShadowRmsAc, ...
    A36_RecomputeDelta_Deg = a36 - firmwareShadowA36, ...
    NL_MinusFirmwareRounded_Deg = robustP2P - sweep.FirmwareNLDeg);
end

function value = shadow_field(sweep, name)
if isfield(sweep, "SHADOW_RESULT") && isfield(sweep.SHADOW_RESULT, name)
    value = str2double(sweep.SHADOW_RESULT.(name));
else
    value = NaN;
end
end

function value = approach_field(sweep, name)
if isfield(sweep, "APPROACH_RESULT") && isfield(sweep.APPROACH_RESULT, name)
    value = str2double(sweep.APPROACH_RESULT.(name));
else
    value = NaN;
end
end
