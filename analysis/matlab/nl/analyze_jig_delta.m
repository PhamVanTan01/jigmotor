function result = analyze_jig_delta(filesA, filesB, products, labelA, labelB)
%ANALYZE_JIG_DELTA Paired cross-jig comparison on the same motor product.
%   result = ANALYZE_JIG_DELTA(filesA, filesB, products, labelA, labelB)
%   parses one log per (jig, product) pair and quantifies, per product:
%     - the mean NL_RobustP2P_Deg/ClosureErrorDeg/RMS_AC_Deg/A36_Deg/
%       MeanDC_Deg difference (labelB - labelA);
%     - the AnalysisStartRaw (sector) difference, wrapped to the nearest
%       point in one ELECTRICAL cycle (10923 raw -- the period the 36th-
%       harmonic ripple that dominates these metrics actually repeats on,
%       not the 65536-raw mechanical revolution) since a different locked
%       MA600 Zero shifts which absolute electrical angle a given raw
%       encoder reading corresponds to, which shifts which portion of the
%       motor's own electrical nonlinearity curve gets sampled -- exactly
%       the "sector" effect already found to move NL in
%       analyze_nl_factors.m;
%   then correlates |sector delta| against |metric delta| across products
%   to test whether a sector shift explains the two jigs' disagreement.
%   Small n (as many products as given) -- report this correlation as
%   suggestive, not conclusive, unless n is large.
%
%   Built for JIG4-vs-JIG5 (test31, 2026-07-27), then reused for JIG1-vs-
%   JIG4 -- per docs/hardware-validation-checklist.md, JIG1 and JIG4 are
%   the pair that actually shares one mechanical fixture across a control-
%   board swap (JIG4's own locked MA600 Zero converged to 0x0000, matching
%   JIG1, after three corrections -- see that doc's JIG4 audit-state row);
%   JIG5 is a separate later board swap, not a fixture-mate of JIG4 in that
%   sense. labelA/labelB are free text so the same tool serves either
%   comparison (default "JIG_A"/"JIG_B" if omitted).

arguments
    filesA (1,:) string
    filesB (1,:) string
    products (1,:) string
    labelA (1,1) string = "JIG_A"
    labelB (1,1) string = "JIG_B"
end

if numel(filesA) ~= numel(products) || numel(filesB) ~= numel(products)
    error("JigDelta:LabelCount", ...
        "filesA/filesB (%d/%d) must match products (%d) in count.", ...
        numel(filesA), numel(filesB), numel(products));
end

electricalCycleRaw = 10923.0;
metricNames = ["NL_RobustP2P_Deg", "ClosureErrorDeg", "RMS_AC_Deg", "A36_Deg", "MeanDC_Deg"];

rows = table();
for index = 1:numel(products)
    rowsA = collect_sweeps(filesA(index), labelA, products(index));
    rowsB = collect_sweeps(filesB(index), labelB, products(index));
    rows = vertcat_rows(rows, rowsA);
    rows = vertcat_rows(rows, rowsB);
end

if isempty(rows)
    error("JigDelta:NoRuns", "No valid official NL sweeps parsed from the given log paths.");
end

nProducts = numel(products);
product = products(:);
meanA = struct();
meanB = struct();
delta = struct();
sectorDeltaRaw = NaN(nProducts, 1);
sectorDeltaDeg = NaN(nProducts, 1);
nA = zeros(nProducts, 1);
nB = zeros(nProducts, 1);

for m = 1:numel(metricNames)
    meanA.(metricNames(m)) = NaN(nProducts, 1);
    meanB.(metricNames(m)) = NaN(nProducts, 1);
    delta.(metricNames(m)) = NaN(nProducts, 1);
end

for index = 1:nProducts
    subsetA = rows(rows.Jig == labelA & rows.Product == products(index), :);
    subsetB = rows(rows.Jig == labelB & rows.Product == products(index), :);
    nA(index) = height(subsetA);
    nB(index) = height(subsetB);
    for m = 1:numel(metricNames)
        vA = mean(subsetA.(metricNames(m)));
        vB = mean(subsetB.(metricNames(m)));
        meanA.(metricNames(m))(index) = vA;
        meanB.(metricNames(m))(index) = vB;
        delta.(metricNames(m))(index) = vB - vA;
    end
    rawDelta = mean(subsetB.AnalysisStartRaw) - mean(subsetA.AnalysisStartRaw);
    wrapped = mod(rawDelta + electricalCycleRaw / 2, electricalCycleRaw) - electricalCycleRaw / 2;
    sectorDeltaRaw(index) = wrapped;
    sectorDeltaDeg(index) = wrapped * 360.0 / electricalCycleRaw;
end

nColName = "N_" + labelA;
nColName2 = "N_" + labelB;
summary = table(product, nA, nB, sectorDeltaRaw, sectorDeltaDeg, VariableNames=...
    ["Product", nColName, nColName2, "SectorDeltaRaw", "SectorDeltaDeg"]);
for m = 1:numel(metricNames)
    summary.(metricNames(m) + "_" + labelA) = meanA.(metricNames(m));
    summary.(metricNames(m) + "_" + labelB) = meanB.(metricNames(m));
    summary.(metricNames(m) + "_Delta") = delta.(metricNames(m));
end

factor = strings(numel(metricNames), 1);
n = zeros(numel(metricNames), 1);
r = NaN(numel(metricNames), 1);
p = NaN(numel(metricNames), 1);
for m = 1:numel(metricNames)
    factor(m) = metricNames(m);
    [rVal, pVal, nVal] = pearson_test(abs(sectorDeltaDeg), abs(delta.(metricNames(m))));
    n(m) = nVal;
    r(m) = rVal;
    p(m) = pVal;
end
sectorCorrelation = table(factor, n, r, p, VariableNames=["Metric", "N", "R", "P"]);

result = struct(Runs = rows, Summary = summary, SectorCorrelation = sectorCorrelation);

fprintf("=== %s vs %s paired delta (same product) ===\n", labelA, labelB);
disp(summary(:, ["Product", nColName, nColName2, "SectorDeltaDeg", ...
    "NL_RobustP2P_Deg_" + labelA, "NL_RobustP2P_Deg_" + labelB, "NL_RobustP2P_Deg_Delta", ...
    "ClosureErrorDeg_" + labelA, "ClosureErrorDeg_" + labelB, "ClosureErrorDeg_Delta"]));
fprintf("-- |sector delta (deg electrical)| vs |metric delta| correlation across %d products (suggestive only, small n) --\n", nProducts);
disp(sectorCorrelation);
end

function rows = collect_sweeps(filePath, jigLabel, productLabel)
sweeps = parse_nl_log(filePath);
rows = table();
for sweepIndex = 1:numel(sweeps)
    sweep = sweeps(sweepIndex);
    if ~isfield(sweep, "Meta") || isempty(fieldnames(sweep.Meta))
        continue
    end
    if ~valid_official_sweep(sweep)
        continue
    end
    metric = compute_nl_sweep_metrics(sweep);
    row = struct2table(metric);
    row.Jig = jigLabel;
    row.Product = productLabel;
    row.AnalysisStartRaw = field_double(sweep.Meta, "AnalysisStartRaw");
    if isempty(rows)
        rows = row;
    else
        rows = [rows; row]; %#ok<AGROW>
    end
end
end

function rows = vertcat_rows(rows, newRows)
if isempty(newRows)
    return
end
if isempty(rows)
    rows = newRows;
else
    rows = [rows; newRows];
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
