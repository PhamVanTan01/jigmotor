function safetyEnvelope = build_a2_safety_envelope(metrics)
%BUILD_A2_SAFETY_ENVELOPE Track step/travel budget usage across ALL runs.
%   Unlike build_a2_profile_summary (which reports only what a candidate
%   power level looked like), this deliberately includes hard-gate FAULT
%   runs -- a SAMPLE_STEP_LIMIT or TRAVEL_LIMIT fault is exactly the
%   boundary evidence needed to see how close to the ceiling each power
%   level came, and must not be silently dropped from the trend.

arguments
    metrics table
end

stepLimitRaw = 45.0;
travelLimitDeg = 910.0*360.0/65536.0;

included = metrics(metrics.Included,:);
profiles = unique(included.Profile, "stable");
n = numel(profiles);

profile = strings(n,1);
powerPercent = NaN(n,1);
totalRuns = zeros(n,1);
faultRuns = zeros(n,1);
faultKinds = strings(n,1);
maxStepRawAny = NaN(n,1);
maxTravelDegAny = NaN(n,1);
stepBudgetFraction = NaN(n,1);
travelBudgetFraction = NaN(n,1);

for index = 1:n
    profile(index) = profiles(index);
    rows = included(included.Profile == profiles(index),:);
    powerPercent(index) = max(rows.TargetPowerPercent);
    totalRuns(index) = height(rows);
    faultMask = rows.Result ~= "OK";
    faultRuns(index) = sum(faultMask);
    if any(faultMask)
        faultKinds(index) = strjoin(unique(rows.Result(faultMask)), ",");
    end
    maxStepRawAny(index) = max(rows.MaxAbsStepRaw);
    maxTravelDegAny(index) = max(rows.MaxAbsTravelDeg);
    stepBudgetFraction(index) = maxStepRawAny(index)/stepLimitRaw;
    travelBudgetFraction(index) = maxTravelDegAny(index)/travelLimitDeg;
end

safetyEnvelope = table(profile, powerPercent, totalRuns, faultRuns, ...
    faultKinds, maxStepRawAny, maxTravelDegAny, stepBudgetFraction, ...
    travelBudgetFraction, VariableNames=["Profile","PowerPercent", ...
    "TotalRuns","FaultRuns","FaultKinds","MaxStepRawAny", ...
    "MaxTravelDegAny","StepBudgetFraction","TravelBudgetFraction"]);

safetyEnvelope = sortrows(safetyEnvelope, "PowerPercent");
end
