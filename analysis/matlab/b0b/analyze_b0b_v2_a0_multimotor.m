function result = analyze_b0b_v2_a0_multimotor(products, v2Paths, a0Paths, ...
        outputDirectory, options)
%ANALYZE_B0B_V2_A0_MULTIMOTOR Quantify the old-sector to A0-sector change.
%   Test 29 is supporting decomposition evidence for the A0-vs-V3 choice:
%   V2 and A0 both contain a local reversal, so their main intentional
%   difference is measurement sector. It must not be described as a direct
%   no-reversal test.

arguments
    products (1,:) string
    v2Paths (1,:) string
    a0Paths (1,:) string
    outputDirectory (1,1) string
    options.ExpectedRunsPerLeg (1,1) double {mustBeInteger,mustBePositive} = 10
    options.BootstrapCount (1,1) double {mustBeInteger,mustBePositive} = 20000
    options.CreatePlots (1,1) logical = true
end

if numel(products) ~= numel(v2Paths) || numel(products) ~= numel(a0Paths)
    error("B0BMethod:InputCount", ...
        "products, v2Paths and a0Paths must have the same length.");
end
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root, "nl"));
addpath(fullfile(root, "b0b"));

v2Protocol = "SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2";
a0Protocol = "SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1";
allRuns = table();
allAudit = table();

for productIndex = 1:numel(products)
    product = products(productIndex);
    [v2Runs, v2Audit] = extract_b0b_method_runs(v2Paths(productIndex), ...
        "V2", v2Protocol, "", NaN);
    [a0Runs, a0Audit] = extract_b0b_method_runs(a0Paths(productIndex), ...
        "A0", a0Protocol, "CW_CCW_CW", 2);
    v2Runs.Product = repmat(product, height(v2Runs), 1);
    a0Runs.Product = repmat(product, height(a0Runs), 1);
    v2Audit.Product = repmat(product, height(v2Audit), 1);
    a0Audit.Product = repmat(product, height(a0Audit), 1);
    allRuns = append_table(allRuns, v2Runs);
    allRuns = append_table(allRuns, a0Runs);
    allAudit = append_table(allAudit, v2Audit);
    allAudit = append_table(allAudit, a0Audit);
end

officialAudit = allAudit(allAudit.OfficialCandidate, :);
gateRecords = struct([]);
for productIndex = 1:numel(products)
    for leg = ["V2", "A0"]
        subset = officialAudit(officialAudit.Product == products(productIndex) & ...
            officialAudit.Leg == leg, :);
        validCount = sum(subset.GatePass);
        record = struct(Product = products(productIndex), Leg = leg, ...
            OfficialCandidates = height(subset), ValidRuns = validCount, ...
            ExpectedRuns = options.ExpectedRunsPerLeg, ...
            GatePass = height(subset) == options.ExpectedRunsPerLeg && ...
                validCount == options.ExpectedRunsPerLeg);
        gateRecords = append_struct(gateRecords, record);
    end
end
gates = struct2table(gateRecords);
writetable(allAudit, fullfile(outputDirectory, "v2_a0_gate_audit.csv"));
writetable(gates, fullfile(outputDirectory, "v2_a0_gate_summary.csv"));
if ~all(gates.GatePass)
    error("B0BMethod:StructuralGate", ...
        "Test 29 V2/A0 structural gate failed; inspect v2_a0_gate_audit.csv.");
end

metrics = ["ClosureNormalizedDeltaRMSDeg", ...
    "AbsCanonicalClosureErrorDeg", "NL_RobustP2P_Deg", "RMS_AC_Deg"];
comparisonRecords = struct([]);
randomState = rng;
restoreRng = onCleanup(@() rng(randomState));
rng(20260724, "twister");

for productIndex = 1:numel(products)
    product = products(productIndex);
    productRuns = allRuns(allRuns.Product == product, :);
    for metricIndex = 1:numel(metrics)
        metric = metrics(metricIndex);
        v2 = double(productRuns.(metric)(productRuns.Leg == "V2"));
        a0 = double(productRuns.(metric)(productRuns.Leg == "A0"));
        v2 = v2(isfinite(v2));
        a0 = a0(isfinite(a0));
        effect = mean(a0) - mean(v2);
        [low, high] = bootstrap_pair_effect(v2, a0, options.BootstrapCount);
        [pairedMean, pairedLow, pairedHigh, pairedN] = ...
            paired_effect(productRuns, metric, options.BootstrapCount);
        record = struct( ...
            Product = product, Metric = metric, ...
            V2N = numel(v2), A0N = numel(a0), ...
            V2Mean = mean(v2), V2SD = std(v2, 0), ...
            A0Mean = mean(a0), A0SD = std(a0, 0), ...
            A0MinusV2 = effect, ...
            ImprovementPct = (mean(v2) - mean(a0)) / mean(v2) * 100, ...
            Bootstrap95Low = low, Bootstrap95High = high, ...
            A0Lower = effect < 0, ...
            A0LowerWithConfidence = high < 0, ...
            PairedRunOrderN = pairedN, ...
            PairedRunOrderMean = pairedMean, ...
            PairedRunOrderBootstrap95Low = pairedLow, ...
            PairedRunOrderBootstrap95High = pairedHigh);
        comparisonRecords = append_struct(comparisonRecords, record);
    end
end
comparisons = struct2table(comparisonRecords);

summaryRecords = struct([]);
for metricIndex = 1:numel(metrics)
    metric = metrics(metricIndex);
    subset = comparisons(comparisons.Metric == metric, :);
    wins = sum(subset.A0Lower);
    confidentWins = sum(subset.A0LowerWithConfidence);
    nProducts = height(subset);
    record = struct( ...
        Metric = metric, ProductCount = nProducts, ...
        A0LowerProductCount = wins, ...
        A0LowerWithConfidenceProductCount = confidentWins, ...
        MeanProductDeltaA0MinusV2 = mean(subset.A0MinusV2), ...
        MedianProductDeltaA0MinusV2 = median(subset.A0MinusV2), ...
        OneSidedExactSignP = sign_test_probability(wins, nProducts), ...
        AllProductsSameDirection = wins == nProducts);
    summaryRecords = append_struct(summaryRecords, record);
end
summary = struct2table(summaryRecords);

writetable(allRuns, fullfile(outputDirectory, "v2_a0_runs.csv"));
writetable(comparisons, fullfile(outputDirectory, ...
    "v2_a0_product_comparisons.csv"));
writetable(summary, fullfile(outputDirectory, ...
    "v2_a0_cross_product_summary.csv"));
write_report(fullfile(outputDirectory, "v2_a0_sector_evidence.txt"), ...
    gates, comparisons, summary);
if options.CreatePlots
    create_plot(comparisons, outputDirectory);
end

residualSummary = summary(summary.Metric == ...
    "ClosureNormalizedDeltaRMSDeg", :);
closureSummary = summary(summary.Metric == ...
    "AbsCanonicalClosureErrorDeg", :);
decision = struct( ...
    SectorShiftSupportsA0 = residualSummary.AllProductsSameDirection && ...
        closureSummary.AllProductsSameDirection, ...
    ResidualA0Wins = residualSummary.A0LowerProductCount, ...
    ClosureA0Wins = closureSummary.A0LowerProductCount, ...
    ProductCount = residualSummary.ProductCount, ...
    Scope = "SECTOR_EFFECT_ONLY_NOT_REVERSAL_EFFECT");

result = struct(Runs = allRuns, Audit = allAudit, Gates = gates, ...
    ProductComparisons = comparisons, CrossProductSummary = summary, ...
    Decision = decision);
fprintf("[B0B V2-A0] residual A0 wins=%d/%d, closure A0 wins=%d/%d\n", ...
    decision.ResidualA0Wins, decision.ProductCount, ...
    decision.ClosureA0Wins, decision.ProductCount);
end

function [low, high] = bootstrap_pair_effect(v2, a0, bootstrapCount)
effects = zeros(bootstrapCount, 1);
for iteration = 1:bootstrapCount
    v2Sample = v2(randi(numel(v2), numel(v2), 1));
    a0Sample = a0(randi(numel(a0), numel(a0), 1));
    effects(iteration) = mean(a0Sample) - mean(v2Sample);
end
effects = sort(effects);
low = percentile_sorted(effects, 2.5);
high = percentile_sorted(effects, 97.5);
end

function [effectMean, low, high, n] = paired_effect(runs, metric, bootstrapCount)
v2 = sortrows(runs(runs.Leg == "V2", ["RunOrder", metric]), "RunOrder");
a0 = sortrows(runs(runs.Leg == "A0", ["RunOrder", metric]), "RunOrder");
[~, v2Index, a0Index] = intersect(v2.RunOrder, a0.RunOrder, "stable");
effects = double(a0.(metric)(a0Index)) - double(v2.(metric)(v2Index));
effects = effects(isfinite(effects));
n = numel(effects);
effectMean = mean(effects);
samples = zeros(bootstrapCount, 1);
for iteration = 1:bootstrapCount
    samples(iteration) = mean(effects(randi(n, n, 1)));
end
samples = sort(samples);
low = percentile_sorted(samples, 2.5);
high = percentile_sorted(samples, 97.5);
end

function probability = sign_test_probability(wins, n)
% One-sided P(X>=wins) for X~Binomial(n,0.5), no toolbox dependency.
probability = 0;
for count = wins:n
    probability = probability + nchoosek(n, count) * 0.5^n;
end
end

function value = percentile_sorted(sortedValues, percentile)
position = 1 + (numel(sortedValues) - 1) * percentile / 100;
lowerIndex = floor(position);
upperIndex = ceil(position);
if lowerIndex == upperIndex
    value = sortedValues(lowerIndex);
else
    fraction = position - lowerIndex;
    value = sortedValues(lowerIndex) * (1 - fraction) + ...
        sortedValues(upperIndex) * fraction;
end
end

function write_report(path, gates, comparisons, summary)
fid = fopen(path, "wt", "n", "UTF-8");
if fid < 0
    error("B0BMethod:Output", "Cannot write report: %s", path);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, "B0-B Test 29: V2 old sector vs A0 shifted sector\n");
fprintf(fid, "================================================\n");
fprintf(fid, "Scope: sector-effect support only. Both methods contain reversal;\n");
fprintf(fid, "this dataset does not test reversal removal.\n\n");
fprintf(fid, "Structural gates: %d/%d product-leg batches pass.\n\n", ...
    sum(gates.GatePass), height(gates));

for metric = ["ClosureNormalizedDeltaRMSDeg", ...
        "AbsCanonicalClosureErrorDeg", "NL_RobustP2P_Deg", "RMS_AC_Deg"]
    fprintf(fid, "%s\n", metric);
    subset = comparisons(comparisons.Metric == metric, :);
    for row = 1:height(subset)
        fprintf(fid, "  %s V2=%.8f A0=%.8f delta=%+.8f CI95=[%+.8f,%+.8f]\n", ...
            subset.Product(row), subset.V2Mean(row), subset.A0Mean(row), ...
            subset.A0MinusV2(row), subset.Bootstrap95Low(row), ...
            subset.Bootstrap95High(row));
    end
    aggregate = summary(summary.Metric == metric, :);
    fprintf(fid, "  A0 lower: %d/%d products; confident: %d/%d; sign-test p=%.5f\n\n", ...
        aggregate.A0LowerProductCount, aggregate.ProductCount, ...
        aggregate.A0LowerWithConfidenceProductCount, aggregate.ProductCount, ...
        aggregate.OneSidedExactSignP);
end
end

function create_plot(comparisons, outputDirectory)
metrics = ["ClosureNormalizedDeltaRMSDeg", ...
    "AbsCanonicalClosureErrorDeg"];
figureHandle = figure(Visible="off", Color="white", ...
    Position=[100 100 1100 480]);
cleanup = onCleanup(@() close(figureHandle));
tiledlayout(1, 2, TileSpacing="compact", Padding="compact");
for metricIndex = 1:2
    axisHandle = nexttile;
    subset = comparisons(comparisons.Metric == metrics(metricIndex), :);
    bar(axisHandle, subset.A0MinusV2, FaceColor=[0.25 0.55 0.75]);
    hold(axisHandle, "on");
    lowError = subset.A0MinusV2 - subset.Bootstrap95Low;
    highError = subset.Bootstrap95High - subset.A0MinusV2;
    errorbar(axisHandle, 1:height(subset), subset.A0MinusV2, ...
        lowError, highError, "k.", LineWidth=1.2);
    yline(axisHandle, 0, "--k");
    xticks(axisHandle, 1:height(subset));
    xticklabels(axisHandle, subset.Product);
    ylabel(axisHandle, "A0 - V2 (deg)");
    title(axisHandle, metrics(metricIndex), Interpreter="none");
    grid(axisHandle, "on");
end
exportgraphics(figureHandle, fullfile(outputDirectory, ...
    "v2_a0_sector_effect.png"), Resolution=160);
end

function output = append_table(output, input)
if isempty(output)
    output = input;
else
    output = [output; input];
end
end

function records = append_struct(records, record)
if isempty(records)
    records = record;
else
    records(end + 1) = record;
end
end
