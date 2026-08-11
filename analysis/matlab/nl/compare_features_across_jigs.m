function result = compare_features_across_jigs(fileGroups, jigA, jigB)
%COMPARE_FEATURES_ACROSS_JIGS Rank EVERY numeric log field by how
%   consistently it differs between two jigs across multiple motors --
%   a data-driven scan instead of testing one hand-picked hypothesis
%   (dead-time harmonics, PID gain, mounting rotation, ...) at a time.
%
%   For each motor with both a jigA and a jigB session, this builds the
%   full session feature table (build_session_feature_table.m) for each
%   side, averages every numeric field across that side's eligible
%   sweeps, and takes DeltaFeature(motor) = mean(jigB) - mean(jigA). A
%   feature that reflects a genuine, motor-independent JIG effect
%   (hardware, mounting fixture, cabling...) should show the SAME SIGN
%   and a SIMILAR MAGNITUDE of delta across every motor -- exactly how
%   A36 was established as jig-invariant and low-order harmonics as
%   jig-variant in docs/cross_jig_measurement_analysis.md, generalized
%   here to every field the firmware logs instead of just harmonics.
%
%   ConsistencyScore = |mean(delta across motors)| / (std(delta across
%   motors) + eps) -- a simple signal/noise ratio, NOT a formal
%   statistical test (too few motors, typically <=5, for that). Treat it
%   as a triage ranking: high score + AllSameSign = worth investigating
%   further with a targeted tool; low score = probably just per-motor/
%   per-mount noise.
%
%   result = COMPARE_FEATURES_ACROSS_JIGS(fileGroups, jigA, jigB)
%   fileGroups: struct array (Files, MotorId, JigId), same format as
%   analyze_nl_extreme_angles.m -- JigId must equal jigA or jigB.
%   Motors missing either side are skipped (reported in
%   result.SkippedMotors).

arguments
    fileGroups (1,:) struct
    jigA (1,1) string = "JIG1"
    jigB (1,1) string = "JIG4"
end

motorIds = unique([fileGroups.MotorId], "stable");
meanTablesA = struct([]);
meanTablesB = struct([]);
skippedMotors = strings(0, 1);
usedMotors = strings(0, 1);

for m = 1:numel(motorIds)
    motorId = motorIds(m);
    groupA = fileGroups([fileGroups.MotorId] == motorId & [fileGroups.JigId] == jigA);
    groupB = fileGroups([fileGroups.MotorId] == motorId & [fileGroups.JigId] == jigB);
    if isempty(groupA) || isempty(groupB)
        skippedMotors(end + 1) = motorId; %#ok<AGROW>
        continue
    end

    filesA = [groupA.Files];
    filesB = [groupB.Files];
    tableA = build_session_feature_table(filesA, motorId, jigA);
    tableB = build_session_feature_table(filesB, motorId, jigB);

    usedMotors(end + 1) = motorId; %#ok<AGROW>
    entry = struct("MotorId", motorId, "Means", mean_numeric_columns(tableA));
    if isempty(meanTablesA); meanTablesA = entry; else; meanTablesA(end + 1) = entry; end %#ok<AGROW>
    entry = struct("MotorId", motorId, "Means", mean_numeric_columns(tableB));
    if isempty(meanTablesB); meanTablesB = entry; else; meanTablesB(end + 1) = entry; end %#ok<AGROW>
end

if numel(usedMotors) < 2
    error("CompareFeaturesAcrossJigs:TooFewMotors", ...
        "Need >=2 motors with both %s and %s sessions to rank consistency (found %d)", ...
        jigA, jigB, numel(usedMotors));
end

% Feature must be present (non-NaN on both sides) for every used motor to
% be fairly ranked -- partial-coverage fields are reported separately,
% not silently averaged over fewer motors than the rest.
allFeatureNames = fieldnames(meanTablesA(1).Means);
nMotors = numel(usedMotors);
featureName = strings(0, 1);
meanDelta = [];
stdDelta = [];
consistencyScore = [];
allSameSign = false(0, 1);
motorDeltas = zeros(0, nMotors);
coverage = [];

for f = 1:numel(allFeatureNames)
    name = allFeatureNames{f};
    if ismember(name, ["MotorId", "JigId", "TestID", "SweepID"])
        continue
    end
    deltas = NaN(1, nMotors);
    for m = 1:nMotors
        a = meanTablesA(m).Means.(name);
        b = NaN;
        if isfield(meanTablesB(m).Means, name)
            b = meanTablesB(m).Means.(name);
        end
        if ~isnan(a) && ~isnan(b)
            deltas(m) = b - a;
        end
    end
    validCount = sum(~isnan(deltas));
    if validCount < nMotors
        continue % require full coverage across motors for the main ranking
    end

    featureName(end + 1, 1) = string(name); %#ok<AGROW>
    meanDelta(end + 1, 1) = mean(deltas); %#ok<AGROW>
    stdDelta(end + 1, 1) = std(deltas); %#ok<AGROW>
    consistencyScore(end + 1, 1) = abs(mean(deltas)) / (std(deltas) + eps); %#ok<AGROW>
    allSameSign(end + 1, 1) = all(sign(deltas) == sign(deltas(1))) && sign(deltas(1)) ~= 0; %#ok<AGROW>
    motorDeltas(end + 1, :) = deltas; %#ok<AGROW>
    coverage(end + 1, 1) = validCount; %#ok<AGROW>
end

ranking = table(featureName, meanDelta, stdDelta, consistencyScore, allSameSign, coverage, ...
    VariableNames = ["Feature", "MeanDelta_BMinusA", "StdDelta", "ConsistencyScore", ...
    "AllSameSign", "MotorCoverage"]);
ranking = sortrows(ranking, "ConsistencyScore", "descend");

motorDeltaTable = array2table(motorDeltas, "VariableNames", cellstr("Motor_" + usedMotors));
motorDeltaTable = [table(featureName, VariableNames = "Feature"), motorDeltaTable];
[~, order] = sort(consistencyScore, "descend");
motorDeltaTable = motorDeltaTable(order, :);

result = struct(JigA = jigA, JigB = jigB, UsedMotors = usedMotors, ...
    SkippedMotors = skippedMotors, Ranking = ranking, MotorDeltas = motorDeltaTable);

fprintf("=== Feature scan: %s vs %s, %d motor(s), %d feature(s) with full coverage ===\n", ...
    jigA, jigB, nMotors, height(ranking));
if ~isempty(skippedMotors)
    fprintf("Skipped (missing %s or %s session): %s\n", jigA, jigB, strjoin(skippedMotors, ", "));
end
topN = min(15, height(ranking));
disp(ranking(1:topN, :));
end

function means = mean_numeric_columns(t)
means = struct();
names = t.Properties.VariableNames;
for i = 1:numel(names)
    name = names{i};
    if ismember(string(name), ["MotorId", "JigId", "TestID", "SweepID"])
        continue
    end
    column = t.(name);
    if ~isnumeric(column)
        continue
    end
    means.(name) = mean(column, "omitnan");
end
end
