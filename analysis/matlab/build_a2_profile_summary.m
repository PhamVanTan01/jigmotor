function profileSummary = build_a2_profile_summary(metrics)
%BUILD_A2_PROFILE_SUMMARY Aggregate safety, movement and circular convergence.

arguments
    metrics table
end

rawToDeg = 360.0/65536.0;
included = metrics(metrics.Included,:);
profiles = unique(included.Profile, "stable");
n = numel(profiles);

profile = strings(n,1);
powerPercent = NaN(n,1);
totalRuns = zeros(n,1);
hardPassRuns = zeros(n,1);
faultRuns = zeros(n,1);
movedRuns = zeros(n,1);
allSafe = false(n,1);
allMoved = false(n,1);
maxAbsStepRaw = NaN(n,1);
maxAbsTravelDeg = NaN(n,1);
finalTravelMeanDeg = NaN(n,1);
finalTravelStdDeg = NaN(n,1);
settledCircularMeanRaw = NaN(n,1);
settledRangeRaw = NaN(n,1);
settledRangeDeg = NaN(n,1);
settledMaxDistanceDeg = NaN(n,1);
settledResultantR = NaN(n,1);
settledRunCount = zeros(n,1);
powerEnvelopeCandidate = false(n,1);
withinOneDegCluster = false(n,1);

for index = 1:n
    profile(index) = profiles(index);
    rows = included(included.Profile == profiles(index),:);
    powerPercent(index) = max(rows.TargetPowerPercent);
    totalRuns(index) = height(rows);
    hardPassRuns(index) = sum(rows.GatePass);
    faultRuns(index) = totalRuns(index)-hardPassRuns(index);
    movedRuns(index) = sum(rows.MovedOverPoint1Deg);
    allSafe(index) = all(rows.GatePass);
    allMoved(index) = all(rows.MovedOverPoint1Deg);
    maxAbsStepRaw(index) = max(rows.MaxAbsStepRaw);
    maxAbsTravelDeg(index) = max(rows.MaxAbsTravelDeg);
    finalTravelMeanDeg(index) = mean(rows.FinalTravelDeg);
    finalTravelStdDeg(index) = std(rows.FinalTravelDeg,1);

    settled = rows.SettledModuloRaw(rows.GatePass & ...
        isfinite(rows.SettledModuloRaw));
    circular = compute_circular_stats(settled, 10923.0);
    settledCircularMeanRaw(index) = circular.MeanRaw;
    settledRangeRaw(index) = circular.RangeRaw;
    settledRangeDeg(index) = circular.RangeRaw*rawToDeg;
    settledMaxDistanceDeg(index) = circular.MaxDistanceRaw*rawToDeg;
    settledResultantR(index) = circular.ResultantR;
    settledRunCount(index) = circular.Count;

    powerEnvelopeCandidate(index) = totalRuns(index) >= 3 && ...
        allSafe(index) && allMoved(index);
    withinOneDegCluster(index) = powerEnvelopeCandidate(index) && ...
        settledRangeDeg(index) <= 1.0;
end

profileSummary = table(profile,powerPercent,totalRuns,hardPassRuns, ...
    faultRuns,movedRuns,allSafe,allMoved,maxAbsStepRaw,maxAbsTravelDeg, ...
    finalTravelMeanDeg,finalTravelStdDeg,settledCircularMeanRaw, ...
    settledRangeRaw,settledRangeDeg,settledMaxDistanceDeg, ...
    settledResultantR,settledRunCount,powerEnvelopeCandidate, ...
    withinOneDegCluster, VariableNames=["Profile","PowerPercent", ...
    "TotalRuns","HardPassRuns","FaultRuns","MovedRuns","AllSafe", ...
    "AllMoved","MaxAbsStepRaw","MaxAbsTravelDeg", ...
    "FinalTravelMeanDeg","FinalTravelStdDeg", ...
    "SettledCircularMeanRaw","SettledRangeRaw","SettledRangeDeg", ...
    "SettledMaxDistanceDeg","SettledResultantR","SettledRunCount", ...
    "PowerEnvelopeCandidate","WithinOneDegCluster"]);

profileSummary = sortrows(profileSummary, ["PowerPercent","Profile"]);
end
