function result = analyze_nl_factors(filePaths, groupLabels)
%ANALYZE_NL_FACTORS Detailed study of what drives NL_RobustP2P_Deg.
%   result = ANALYZE_NL_FACTORS(filePaths, groupLabels) parses every file
%   (via parse_nl_log.m / compute_nl_sweep_metrics.m, both already
%   cross-checked to ~1e-15 against tools/analyze_nl_stability.py), pools
%   every valid official sweep, and reports:
%
%   1. GroupSummary: mean/SD of NL_RobustP2P_Deg and ClosureErrorDeg per
%      groupLabels(fileIndex) (e.g. per method V2/A0/V3, or per mounting
%      condition) -- the between-group factor.
%   2. FactorCorrelations: within-group-centered AND within-group-detrended
%      (linear vs RunOrder, removes warm-up/thermal trend) Pearson
%      correlation of NL_RobustP2P_Deg against each candidate factor
%      (A36_Deg, RMS_AC_Deg, MeanDC_Deg, ClosureErrorDeg,
%      ApproachReturnErrorDeg, AnalysisStartRaw/sector, RunOrder itself).
%      Centering removes between-group offsets (e.g. a method or product
%      that happens to have both higher NL and higher A36 would otherwise
%      look "correlated" purely because both differ by group, not because
%      they move together within a group) -- same discipline as
%      analyze_b0b_metric_relationships.m, applied to internally-recomputed
%      metrics instead of a pre-exported CSV of unknown provenance.
%   3. PerGroupCorrelation: the same correlation computed separately inside
%      each group, so a pooled relationship can be checked for being shared
%      across groups vs driven by only one.

arguments
    filePaths (1,:) string
    groupLabels (1,:) string
end

if numel(filePaths) ~= numel(groupLabels)
    error("NLFactors:LabelCount", ...
        "groupLabels (%d) must match filePaths (%d) in count.", ...
        numel(groupLabels), numel(filePaths));
end

rows = table();
for fileIndex = 1:numel(filePaths)
    sweeps = parse_nl_log(filePaths(fileIndex));
    for sweepIndex = 1:numel(sweeps)
        sweep = sweeps(sweepIndex);
        if ~isfield(sweep, "SUMMARY") && ~isfield(sweep, "Meta")
            % ok: NL logs use Meta, not SUMMARY -- guard kept for clarity
        end
        if ~isfield(sweep, "Meta") || isempty(fieldnames(sweep.Meta))
            continue
        end
        if ~valid_official_sweep(sweep)
            continue
        end
        metric = compute_nl_sweep_metrics(sweep);
        row = struct2table(metric);
        row.Group = groupLabels(fileIndex);
        row.RunOrder = field_double(sweep.Meta, "RunOrder");
        row.AnalysisStartRaw = field_double(sweep.Meta, "AnalysisStartRaw");
        row.ApproachProtocol = string(field_or(sweep.Meta, "ApproachProtocol", "NA"));
        row.JigID = string(field_or(sweep.Meta, "JigID", "NA"));
        if isempty(rows)
            rows = row;
        else
            rows = [rows; row]; %#ok<AGROW>
        end
    end
end

if isempty(rows)
    error("NLFactors:NoRuns", "No valid official NL sweeps parsed from the given log paths.");
end

groups = unique(rows.Group, "stable");
nGroups = numel(groups);
groupName = groups;
n = zeros(nGroups, 1);
nlMean = NaN(nGroups, 1);
nlSd = NaN(nGroups, 1);
closureMean = NaN(nGroups, 1);
closureSd = NaN(nGroups, 1);
for index = 1:nGroups
    subset = rows(rows.Group == groups(index), :);
    n(index) = height(subset);
    nlMean(index) = mean(subset.NL_RobustP2P_Deg);
    nlSd(index) = std(subset.NL_RobustP2P_Deg, 0);
    closureMean(index) = mean(subset.ClosureErrorDeg);
    closureSd(index) = std(subset.ClosureErrorDeg, 0);
end
groupSummary = table(groupName, n, nlMean, nlSd, closureMean, closureSd, ...
    VariableNames=["Group","N","NL_RobustP2P_Mean","NL_RobustP2P_SD", ...
    "ClosureErrorDeg_Mean","ClosureErrorDeg_SD"]);

factorNames = ["A36_Deg","RMS_AC_Deg","MeanDC_Deg","ClosureErrorDeg", ...
    "ApproachReturnErrorDeg","AnalysisStartRaw","RunOrder"];
factorNames = factorNames(ismember(factorNames, string(rows.Properties.VariableNames)));

nRows = height(rows);
centeredNl = NaN(nRows, 1);
detrendedNl = NaN(nRows, 1);
centeredFactor = NaN(nRows, numel(factorNames));
detrendedFactor = NaN(nRows, numel(factorNames));
for index = 1:nGroups
    mask = rows.Group == groups(index);
    runOrder = rows.RunOrder(mask);
    [centeredNl(mask), detrendedNl(mask)] = center_and_detrend(rows.NL_RobustP2P_Deg(mask), runOrder);
    for factorIndex = 1:numel(factorNames)
        [centeredFactor(mask, factorIndex), detrendedFactor(mask, factorIndex)] = ...
            center_and_detrend(rows.(factorNames(factorIndex))(mask), runOrder);
    end
end

factor = strings(numel(factorNames), 1);
nUsed = zeros(numel(factorNames), 1);
rCentered = NaN(numel(factorNames), 1);
pCentered = NaN(numel(factorNames), 1);
rDetrended = NaN(numel(factorNames), 1);
pDetrended = NaN(numel(factorNames), 1);
groupsSameSign = zeros(numel(factorNames), 1);
groupsValid = zeros(numel(factorNames), 1);
perGroupR = cell(numel(factorNames), 1);
for factorIndex = 1:numel(factorNames)
    factor(factorIndex) = factorNames(factorIndex);
    [rCentered(factorIndex), pCentered(factorIndex), nUsed(factorIndex)] = ...
        pearson_test(centeredNl, centeredFactor(:, factorIndex));
    [rDetrended(factorIndex), pDetrended(factorIndex)] = ...
        pearson_test(detrendedNl, detrendedFactor(:, factorIndex));

    groupR = NaN(nGroups, 1);
    for index = 1:nGroups
        mask = rows.Group == groups(index);
        groupR(index) = pearson_test(detrendedNl(mask), detrendedFactor(mask, factorIndex));
    end
    finiteGroup = isfinite(groupR);
    groupsValid(factorIndex) = sum(finiteGroup);
    if any(finiteGroup) && isfinite(rDetrended(factorIndex))
        pooledSign = sign(rDetrended(factorIndex));
        groupsSameSign(factorIndex) = sum(sign(groupR(finiteGroup)) == pooledSign);
    end
    perGroupR{factorIndex} = groupR;
end
factorCorrelations = table(factor, nUsed, rCentered, pCentered, rDetrended, ...
    pDetrended, groupsValid, groupsSameSign, VariableNames=["Factor","N", ...
    "RCentered","PCentered","RDetrended","PDetrended","GroupsValid","GroupsSameSign"]);
factorCorrelations.AbsRDetrended = abs(factorCorrelations.RDetrended);
factorCorrelations = sortrows(factorCorrelations, "AbsRDetrended", "descend");

perGroupCorrelation = array2table(horzcat(perGroupR{:}), VariableNames=cellstr(factorNames));
perGroupCorrelation = addvars(perGroupCorrelation, groups, Before=1, NewVariableNames="Group");

result = struct(Runs=rows, GroupSummary=groupSummary, ...
    FactorCorrelations=factorCorrelations, PerGroupCorrelation=perGroupCorrelation);

fprintf("=== NL factor analysis: %d sweeps, %d groups ===\n", nRows, nGroups);
disp(groupSummary);
fprintf("-- Factor correlations with NL_RobustP2P_Deg (within-group centered/detrended) --\n");
disp(factorCorrelations(:, ["Factor","N","RCentered","RDetrended","PDetrended", ...
    "GroupsSameSign","GroupsValid"]));
end

function [centeredValues, detrendedValues] = center_and_detrend(values, runOrder)
values = double(values);
runOrder = double(runOrder);
centeredValues = NaN(size(values));
detrendedValues = NaN(size(values));
finite = isfinite(values) & isfinite(runOrder);
if any(finite)
    centeredValues(finite) = values(finite) - mean(values(finite));
end
if sum(finite) >= 3 && std(runOrder(finite)) > 0
    design = [ones(sum(finite), 1), runOrder(finite)];
    detrendedValues(finite) = values(finite) - design * (design \ values(finite));
elseif any(finite)
    detrendedValues(finite) = centeredValues(finite);
end
end

function [r, p, n] = pearson_test(x, y)
finite = isfinite(x) & isfinite(y);
x = double(x(finite));
y = double(y(finite));
n = numel(x);
if n < 3
    r = NaN;
    p = NaN;
    return
end
x = x - mean(x);
y = y - mean(y);
% A column regressed against itself inside center_and_detrend (e.g. the
% "RunOrder" factor row, detrended vs RunOrder) leaves machine-epsilon
% residuals, not exact zero, so the old "std(x)==0" exact-equality guard
% missed it: dividing that noise by itself amplified into a spurious,
% sizeable r. Treat "essentially no residual variance left" (near-zero in
% absolute terms) as r=0 -- nothing left to correlate -- while a
% genuinely constant, non-near-zero column (std==0 exactly) stays NaN
% (truly undefined correlation).
noVarianceTol = 1e-9;
if max(abs(x)) < noVarianceTol || max(abs(y)) < noVarianceTol
    r = 0;
    p = 1;
    return
end
if std(x) == 0 || std(y) == 0
    r = NaN;
    p = NaN;
    return
end
r = sum(x .* y) / sqrt(sum(x.^2) * sum(y.^2));
r = min(max(r, -1), 1);
if abs(r) >= 1
    p = 0;
else
    df = n - 2;
    tSquared = r^2 * df / (1 - r^2);
    p = betainc(df / (df + tSquared), df / 2, 0.5);
end
end

function valid = valid_official_sweep(sweep)
valid = false;
if ~isfield(sweep.Meta, "AnalysisPoints") || str2double(sweep.Meta.AnalysisPoints) <= 0
    return
end
if ~isfield(sweep.Meta, "EligibleForStatistics") || string(sweep.Meta.EligibleForStatistics) ~= "1"
    return
end
if ~isfield(sweep.Meta, "MeasurementValid") || string(sweep.Meta.MeasurementValid) ~= "1"
    return
end
if ~isfield(sweep.END, "Status") || string(sweep.END.Status) ~= "VALID"
    return
end
analysisPoints = str2double(sweep.Meta.AnalysisPoints);
presentCount = sum(sweep.Data.Index < analysisPoints);
if presentCount ~= analysisPoints
    return
end
valid = true;
end

function value = field_double(fields, name)
if isfield(fields, name)
    value = str2double(fields.(name));
else
    value = NaN;
end
end

function value = field_or(fields, name, default)
if isfield(fields, name)
    value = fields.(name);
else
    value = default;
end
end
