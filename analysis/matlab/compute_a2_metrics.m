function metric = compute_a2_metrics(summaryRow, evidence, evidenceHash)
%COMPUTE_A2_METRICS Recompute motion/settle metrics from evidence.

arguments
    summaryRow table
    evidence table
    evidenceHash (1,1) string
end

if height(summaryRow) ~= 1
    error("A2Analysis:SummaryRow", "Exactly one summary row is required.");
end

mechanicalCounts = 65536.0;
electricalPeriodRaw = 10923.0;
rawToDeg = 360.0/mechanicalCounts;

travelRaw = double(evidence.TravelRaw);
deltaRaw = double(evidence.DeltaRaw);
powerPpm = double(evidence.PowerPpm);
baselineRaw = scalar_number(summaryRow.BaselineRaw);
holdMask = string(evidence.Phase) == "ALIGN_HOLD";
tailMask = find(holdMask);
tailMask = tailMask(max(1, numel(tailMask)-19):end);

if any(holdMask)
    holdRaw = travelRaw(holdMask);
    holdDriftDeg = (holdRaw(end)-holdRaw(1))*rawToDeg;
    holdMeanRaw = mean(holdRaw);
    holdStdDeg = std(holdRaw*rawToDeg, 1);
    holdP2PDeg = (max(holdRaw)-min(holdRaw))*rawToDeg;
    settledModuloRaw = mod(baselineRaw+holdMeanRaw, electricalPeriodRaw);
    tailRaw = travelRaw(tailMask);
    tailStdDeg = std(tailRaw*rawToDeg, 1);
    tailP2PDeg = (max(tailRaw)-min(tailRaw))*rawToDeg;
else
    holdDriftDeg = NaN;
    holdStdDeg = NaN;
    holdP2PDeg = NaN;
    settledModuloRaw = NaN;
    tailStdDeg = NaN;
    tailP2PDeg = NaN;
end

gatePass = scalar_logical(summaryRow.GatePass);
maxAbsTravelDeg = max(abs(travelRaw))*rawToDeg;
finalTravelDeg = travelRaw(end)*rawToDeg;
maxAbsStepRaw = max(abs(deltaRaw));
targetPowerPercent = max(powerPpm)/10000.0;
startModuloRaw = mod(baselineRaw, electricalPeriodRaw);
finalModuloRaw = mod(baselineRaw+travelRaw(end), electricalPeriodRaw);

metric = table(string(summaryRow.Run), string(summaryRow.File), ...
    string(summaryRow.Profile), string(summaryRow.Result), gatePass, ...
    targetPowerPercent, height(evidence), baselineRaw, startModuloRaw, ...
    finalTravelDeg, maxAbsTravelDeg, maxAbsStepRaw, holdDriftDeg, ...
    holdStdDeg, holdP2PDeg, tailStdDeg, tailP2PDeg, ...
    settledModuloRaw, finalModuloRaw, maxAbsTravelDeg >= 0.1, ...
    evidenceHash, strings(1,1), true, ...
    VariableNames=["Run","File","Profile","Result","GatePass", ...
    "TargetPowerPercent","EvidenceCount","BaselineRaw", ...
    "StartModuloRaw","FinalTravelDeg","MaxAbsTravelDeg", ...
    "MaxAbsStepRaw","HoldDriftDeg","HoldStdDeg","HoldP2PDeg", ...
    "Tail20StdDeg","Tail20P2PDeg","SettledModuloRaw", ...
    "FinalModuloRaw","MovedOverPoint1Deg","EvidenceHash", ...
    "DuplicateOf","Included"]);
end

function value = scalar_number(input)
if isnumeric(input) || islogical(input)
    value = double(input(1));
else
    value = str2double(string(input(1)));
end
if ~isfinite(value)
    error("A2Analysis:Numeric", "Expected a finite scalar number.");
end
end

function value = scalar_logical(input)
if islogical(input)
    value = input(1);
elseif isnumeric(input)
    value = input(1) ~= 0;
else
    text = lower(strtrim(string(input(1))));
    if ismember(text, ["true","1"])
        value = true;
    elseif ismember(text, ["false","0"])
        value = false;
    else
        error("A2Analysis:Logical", "Invalid logical value: %s", text);
    end
end
end
