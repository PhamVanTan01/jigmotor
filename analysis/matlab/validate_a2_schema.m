function validate_a2_schema(data, schemaKind)
%VALIDATE_A2_SCHEMA Fail closed when canonical CSV fields are incomplete.

arguments
    data table
    schemaKind (1,1) string
end

switch lower(schemaKind)
    case "summary"
        required = ["Run","File","Profile","Result","GatePass", ...
            "EvidenceCount","BaselineRaw","FinalRaw", ...
            "FinalTravelMilliDeg","MaxAbsTravelMilliDeg", ...
            "MaxAbsStepRaw","HoldDriftMilliDeg","SettledModuloRaw", ...
            "DeadlineMisses","Retries","TransportErrors", ...
            "JumpRejects","FailedSamples"];
    case "evidence"
        required = ["Seq","Phase","EncoderRaw","TravelRaw", ...
            "TravelMilliDeg","DeltaRaw","PowerPpm","ScheduledTick", ...
            "SampleTick","LatenessTicks","LoopCycles", ...
            "SpiLatencyCycles"];
    otherwise
        error("A2Analysis:UnknownSchema", "Unknown schema kind: %s", schemaKind);
end

missingFields = setdiff(required, string(data.Properties.VariableNames));
if ~isempty(missingFields)
    error("A2Analysis:MissingFields", "Missing %s fields: %s", ...
        schemaKind, strjoin(missingFields, ", "));
end

if schemaKind == "summary"
    if height(data) == 0
        error("A2Analysis:EmptySummary", "Summary CSV has no runs.");
    end
    return
end

if height(data) == 0
    error("A2Analysis:EmptyEvidence", "Evidence CSV has no samples.");
end

sequence = double(data.Seq);
expected = (0:height(data)-1)';
if any(~isfinite(sequence)) || any(sequence ~= expected)
    error("A2Analysis:Sequence", ...
        "Evidence Seq must be finite, continuous, and start at zero.");
end

knownPhases = ismember(string(data.Phase), ["ALIGN_RAMP","ALIGN_HOLD"]);
if any(~knownPhases)
    error("A2Analysis:Phase", "Evidence contains an unknown phase label.");
end
end
