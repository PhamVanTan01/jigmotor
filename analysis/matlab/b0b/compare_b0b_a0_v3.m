function comparison = compare_b0b_a0_v3(runs, sectorToleranceRaw, bootstrapCount)
%COMPARE_B0B_A0_V3 Deep A0-before/V3/A0-after bracket comparison.
%   The 2.77*pooled-SD residual gate is the pre-locked experiment gate.
%   Bootstrap confidence intervals and run-order pairing are sensitivity
%   analyses; they add uncertainty information but do not replace that gate.

arguments
    runs table
    sectorToleranceRaw (1,1) double {mustBeNonnegative} = 91
    bootstrapCount (1,1) double {mustBeInteger,mustBePositive} = 20000
end

requiredLegs = ["A0_BEFORE", "V3", "A0_AFTER"];
if ~ismember("Leg", string(runs.Properties.VariableNames)) || ...
        ~all(ismember(requiredLegs, unique(runs.Leg)))
    error("B0BMethod:Legs", "Runs must contain A0_BEFORE, V3 and A0_AFTER.");
end

metricNames = [ ...
    "ClosureNormalizedDeltaRMSDeg", ...
    "ClosureNormalizedDeltaMaxAbsDeg", ...
    "CanonicalClosureErrorDeg", ...
    "AbsCanonicalClosureErrorDeg", ...
    "LegacyClosureErrorDeg", ...
    "RMS_AC_Deg", ...
    "NL_RobustP2P_Deg", ...
    "A36_Deg", ...
    "AnalysisStartRaw", ...
    "OriginShiftTargetErrorRaw", ...
    "FinalTargetErrorRaw", ...
    "H2AmplitudeDeg", ...
    "H2PhaseSweepDeg", ...
    "H2C", ...
    "H2S"];
metricNames = metricNames(ismember(metricNames, ...
    string(runs.Properties.VariableNames)));

summaryRecords = struct([]);
contrastRecords = struct([]);
randomState = rng;
restoreRng = onCleanup(@() rng(randomState));
rng(20260724, "twister");

for metricIndex = 1:numel(metricNames)
    metric = metricNames(metricIndex);
    legValues = cell(1, 3);
    for legIndex = 1:3
        values = double(runs.(metric)(runs.Leg == requiredLegs(legIndex)));
        values = values(isfinite(values));
        legValues{legIndex} = values;
        summaryRecord = describe_values(requiredLegs(legIndex), metric, values);
        summaryRecords = append_struct(summaryRecords, summaryRecord);
    end

    before = legValues{1};
    v3 = legValues{2};
    after = legValues{3};
    bracketMean = (mean(before) + mean(after)) / 2;
    effect = mean(v3) - bracketMean;
    pooledSd = pooled_sd(before, v3, after);
    standardError = sqrt(var(before, 0) / numel(before) / 4 + ...
        var(v3, 0) / numel(v3) + var(after, 0) / numel(after) / 4);
    [bootstrapLow, bootstrapHigh] = bootstrap_effect(before, v3, after, ...
        bootstrapCount);
    [pairedMean, pairedSd, pairedLow, pairedHigh, pairedN] = ...
        paired_run_order_effect(runs, metric, bootstrapCount);
    a0Drift = mean(after) - mean(before);
    a0DriftSe = sqrt(var(before, 0) / numel(before) + ...
        var(after, 0) / numel(after));

    contrastRecord = struct( ...
        Metric = metric, ...
        A0BeforeMean = mean(before), V3Mean = mean(v3), ...
        A0AfterMean = mean(after), BracketMean = bracketMean, ...
        V3MinusBracket = effect, PooledSD = pooledSd, ...
        EffectInPooledSD = effect / pooledSd, ...
        StandardError = standardError, EffectInSE = effect / standardError, ...
        Bootstrap95Low = bootstrapLow, Bootstrap95High = bootstrapHigh, ...
        A0DriftAfterMinusBefore = a0Drift, ...
        A0DriftStandardError = a0DriftSe, ...
        A0DriftInSE = a0Drift / a0DriftSe, ...
        V3OutsideA0MeanBracket = mean(v3) < min(mean(before), mean(after)) || ...
            mean(v3) > max(mean(before), mean(after)), ...
        PairedRunOrderN = pairedN, ...
        PairedRunOrderMean = pairedMean, ...
        PairedRunOrderSD = pairedSd, ...
        PairedRunOrderBootstrap95Low = pairedLow, ...
        PairedRunOrderBootstrap95High = pairedHigh);
    contrastRecords = append_struct(contrastRecords, contrastRecord);
end

summaries = struct2table(summaryRecords);
contrasts = struct2table(contrastRecords);

sector = compute_sector_gate(runs, sectorToleranceRaw);
residual = contrast_row(contrasts, "ClosureNormalizedDeltaRMSDeg");
nl = contrast_row(contrasts, "NL_RobustP2P_Deg");
absoluteClosure = contrast_row(contrasts, "AbsCanonicalClosureErrorDeg");

lockedResidualThreshold = residual.BracketMean - 2.77 * residual.PooledSD;
residualGatePass = residual.V3Mean < lockedResidualThreshold;
nlWithinRepeatability = abs(nl.V3MinusBracket) <= 2.77 * nl.PooledSD;
v3ResidualWorseWithConfidence = residual.V3MinusBracket > 0 && ...
    residual.Bootstrap95Low > 0;
closureImprovedWithConfidence = absoluteClosure.V3MinusBracket < 0 && ...
    absoluteClosure.Bootstrap95High < 0;

if residualGatePass && sector.DescriptiveGatePass
    decisionCode = "V3_CANDIDATE_REQUIRES_TRUE_TIMESTAMP_CONFIRMATION";
    selectedMethod = "UNRESOLVED";
    rationale = "V3 clears the locked residual gate, but the current sector timestamp axis is approximate.";
elseif v3ResidualWorseWithConfidence
    decisionCode = "KEEP_A0_REJECT_V3";
    selectedMethod = "A0";
    rationale = "V3 post-turn residual is higher than the A0 bracket and its bootstrap 95% interval excludes zero.";
else
    decisionCode = "KEEP_A0_NO_V3_BENEFIT";
    selectedMethod = "A0";
    rationale = "V3 does not clear the pre-locked residual-improvement gate.";
end

decision = struct( ...
    SelectedMethod = selectedMethod, ...
    DecisionCode = decisionCode, ...
    Rationale = rationale, ...
    ResidualGatePass = residualGatePass, ...
    LockedResidualThresholdDeg = lockedResidualThreshold, ...
    V3ResidualWorseWithConfidence = v3ResidualWorseWithConfidence, ...
    NLWithinRepeatabilityEnvelope = nlWithinRepeatability, ...
    ClosureImprovedWithConfidence = closureImprovedWithConfidence, ...
    SectorGateDescriptivePass = sector.DescriptiveGatePass, ...
    SectorTimingEvidence = "APPROXIMATE_CUMULATIVE_RUN_INDEX", ...
    FormalCausalSectorGateAvailable = false);

comparison = struct(LegSummary = summaries, Contrasts = contrasts, ...
    Sector = sector, Decision = decision);
end

function record = describe_values(leg, metric, values)
medianValue = median(values);
record = struct( ...
    Leg = leg, Metric = metric, N = numel(values), ...
    Mean = mean(values), SampleSD = std(values, 0), ...
    Median = medianValue, MAD = median(abs(values - medianValue)), ...
    Min = min(values), Max = max(values), ...
    Range = max(values) - min(values), ...
    RepeatabilityLimit2_77SD = 2.77 * std(values, 0));
end

function value = pooled_sd(before, v3, after)
degreesFreedom = numel(before) + numel(v3) + numel(after) - 3;
value = sqrt(((numel(before) - 1) * var(before, 0) + ...
    (numel(v3) - 1) * var(v3, 0) + ...
    (numel(after) - 1) * var(after, 0)) / degreesFreedom);
end

function [low, high] = bootstrap_effect(before, v3, after, bootstrapCount)
effects = zeros(bootstrapCount, 1);
for iteration = 1:bootstrapCount
    beforeSample = before(randi(numel(before), numel(before), 1));
    v3Sample = v3(randi(numel(v3), numel(v3), 1));
    afterSample = after(randi(numel(after), numel(after), 1));
    effects(iteration) = mean(v3Sample) - ...
        (mean(beforeSample) + mean(afterSample)) / 2;
end
sorted = sort(effects);
low = percentile_sorted(sorted, 2.5);
high = percentile_sorted(sorted, 97.5);
end

function [effectMean, effectSd, low, high, n] = paired_run_order_effect( ...
        runs, metric, bootstrapCount)
before = runs(runs.Leg == "A0_BEFORE", ["RunOrder", metric]);
v3 = runs(runs.Leg == "V3", ["RunOrder", metric]);
after = runs(runs.Leg == "A0_AFTER", ["RunOrder", metric]);
paired = innerjoin(before, v3, Keys="RunOrder", ...
    LeftVariables=["RunOrder", metric], RightVariables=metric);
paired = innerjoin(paired, after, Keys="RunOrder", ...
    LeftVariables=string(paired.Properties.VariableNames), ...
    RightVariables=metric);

valueNames = string(paired.Properties.VariableNames);
metricColumns = valueNames(startsWith(valueNames, metric));
if numel(metricColumns) ~= 3
    effectMean = NaN;
    effectSd = NaN;
    low = NaN;
    high = NaN;
    n = 0;
    return
end

effects = double(paired.(metricColumns(2))) - ...
    (double(paired.(metricColumns(1))) + double(paired.(metricColumns(3)))) / 2;
effects = effects(isfinite(effects));
n = numel(effects);
effectMean = mean(effects);
effectSd = std(effects, 0);
samples = zeros(bootstrapCount, 1);
for iteration = 1:bootstrapCount
    samples(iteration) = mean(effects(randi(n, n, 1)));
end
samples = sort(samples);
low = percentile_sorted(samples, 2.5);
high = percentile_sorted(samples, 97.5);
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

function sector = compute_sector_gate(runs, toleranceRaw)
before = sortrows(runs(runs.Leg == "A0_BEFORE", :), "RunOrder");
v3 = sortrows(runs(runs.Leg == "V3", :), "RunOrder");
after = sortrows(runs(runs.Leg == "A0_AFTER", :), "RunOrder");

beforeReference = circular_mean_raw(before.AnalysisStartRaw);
afterReference = circular_mean_raw(after.AnalysisStartRaw);
afterUnwrapped = beforeReference + circular_delta(afterReference, beforeReference);

v3Times = reshape(height(before) + (1:height(v3)), [], 1);
beforeReferenceTime = (1 + height(before)) / 2;
afterReferenceTime = height(before) + height(v3) + ...
    (1 + height(after)) / 2;

expected = beforeReference + (afterUnwrapped - beforeReference) .* ...
    (v3Times - beforeReferenceTime) ./ ...
    (afterReferenceTime - beforeReferenceTime);
errors = arrayfun(@(actual, reference) circular_delta(actual, reference), ...
    v3.AnalysisStartRaw, expected);
passes = abs(errors) <= toleranceRaw;

perRun = table(v3.RunOrder, v3.AnalysisStartRaw, v3Times, expected, errors, ...
    passes, VariableNames=["RunOrder","AnalysisStartRaw","ApproximateTimeIndex", ...
    "ExpectedAnalysisStartRaw","SectorErrorRaw","WithinTolerance"]);
sector = struct( ...
    TimingEvidence = "APPROXIMATE_CUMULATIVE_RUN_INDEX", ...
    ToleranceRaw = toleranceRaw, BeforeCircularMeanRaw = beforeReference, ...
    AfterCircularMeanRaw = afterReference, PerRun = perRun, ...
    PassCount = sum(passes), RunCount = numel(passes), ...
    MaxAbsErrorRaw = max(abs(errors)), ...
    DescriptiveGatePass = sum(passes) >= ceil(0.9 * numel(passes)), ...
    FormalGateAvailable = false);
end

function value = circular_mean_raw(values)
angles = double(values) * 2 * pi / 65536;
value = mod(atan2(mean(sin(angles)), mean(cos(angles))) * 65536 / ...
    (2 * pi), 65536);
end

function value = circular_delta(x, reference)
value = mod(double(x) - double(reference) + 32768, 65536) - 32768;
end

function row = contrast_row(contrasts, metric)
row = contrasts(contrasts.Metric == metric, :);
if height(row) ~= 1
    error("B0BMethod:Metric", "Expected one contrast row for %s.", metric);
end
end

function records = append_struct(records, record)
if isempty(records)
    records = record;
else
    records(end + 1) = record;
end
end
