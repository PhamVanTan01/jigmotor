function [runs, audit] = extract_b0b_method_runs(filePath, leg, expectedProtocol, ...
        expectedPath, expectedReversalCount)
%EXTRACT_B0B_METHOD_RUNS Gate and recompute A0/V3 metrics from a raw NL log.
%   This function deliberately starts from UART DATA/META records instead
%   of an existing CSV. Canonical closure comes from SHADOW_RESULT, while
%   post-turn residual is recomputed from DATA using the locked B0-B
%   definition:
%
%     legacyClosure = Error(360) - Error(0)
%     delta(i)       = Error(360+i) - Error(i), i=1..10
%     residual(i)    = delta(i) - legacyClosure
%
%   Mixing SHADOW_RESULT.ClosureErrorDeg into that normalization would join
%   two different sampling/reference pipelines and is therefore forbidden.

arguments
    filePath (1,1) string
    leg (1,1) string
    expectedProtocol (1,1) string
    expectedPath (1,1) string
    expectedReversalCount (1,1) double
end

if ~isfile(filePath)
    error("B0BMethod:Input", "Raw log not found: %s", filePath);
end

sweeps = parse_nl_log(filePath);
runRecords = struct([]);
auditRecords = struct([]);

for sweepIndex = 1:numel(sweeps)
    sweep = sweeps(sweepIndex);
    runRole = field_string(sweep.Meta, "RunRole");
    eligible = field_double(sweep.Meta, "EligibleForStatistics");
    officialCandidate = runRole == "OFFICIAL" || eligible == 1;

    if officialCandidate
        [gatePass, reason] = gate_official_sweep(sweep, expectedProtocol, ...
            expectedPath, expectedReversalCount);
    else
        gatePass = false;
        reason = "NOT_OFFICIAL";
    end

    auditRecord = struct( ...
        Source = filePath, Leg = leg, TestID = sweep.TestID, ...
        SweepID = sweep.SweepID, RunOrder = field_double(sweep.Meta, "RunOrder"), ...
        RunRole = runRole, OfficialCandidate = officialCandidate, ...
        GatePass = gatePass, ExclusionReason = reason);
    auditRecords = append_struct(auditRecords, auditRecord);

    if ~gatePass
        continue
    end

    metric = compute_nl_sweep_metrics(sweep);
    data = sortrows(sweep.Data, "Index");
    errors = NaN(371, 1);
    for dataIndex = 0:370
        row = data(data.Index == dataIndex, :);
        errors(dataIndex + 1) = row.ErrorDeg(1);
    end

    legacyClosure = errors(361) - errors(1);
    postTurnDelta = zeros(10, 1);
    postTurnResidual = zeros(10, 1);
    for point = 1:10
        postTurnDelta(point) = errors(361 + point) - errors(1 + point);
        postTurnResidual(point) = postTurnDelta(point) - legacyClosure;
    end

    h2Amplitude = field_double(sweep.RESULT, "A2");
    h2Phase = field_double(sweep.RESULT, "H2_PhaseSweepDeg");
    h2C = h2Amplitude * cosd(h2Phase);
    h2S = h2Amplitude * sind(h2Phase);
    canonicalClosure = metric.ClosureErrorDeg;

    record = struct( ...
        Source = filePath, Leg = leg, TestID = sweep.TestID, ...
        SweepID = sweep.SweepID, RunOrder = field_double(sweep.Meta, "RunOrder"), ...
        ApproachProtocol = field_string(sweep.Meta, "ApproachProtocol"), ...
        ApproachPath = field_string(sweep.APPROACH_RESULT, "ApproachPath"), ...
        ReversalCount = field_double(sweep.APPROACH_RESULT, "ReversalCount"), ...
        AnalysisStartRaw = field_double(sweep.Meta, "AnalysisStartRaw"), ...
        StartRaw = field_double(sweep.Meta, "StartRaw"), ...
        CanonicalClosureErrorDeg = canonicalClosure, ...
        AbsCanonicalClosureErrorDeg = abs(canonicalClosure), ...
        LegacyClosureErrorDeg = legacyClosure, ...
        LegacyMinusCanonicalClosureDeg = legacyClosure - canonicalClosure, ...
        PostTurnRepeatRMSDeg = sqrt(mean(postTurnDelta.^2)), ...
        ClosureNormalizedDeltaRMSDeg = sqrt(mean(postTurnResidual.^2)), ...
        ClosureNormalizedDeltaMaxAbsDeg = max(abs(postTurnResidual)), ...
        RMS_AC_Deg = metric.RMS_AC_Deg, ...
        NL_RobustP2P_Deg = metric.NL_RobustP2P_Deg, ...
        A36_Deg = metric.A36_Deg, ...
        H2AmplitudeDeg = h2Amplitude, H2PhaseSweepDeg = h2Phase, ...
        H2C = h2C, H2S = h2S, ...
        OriginShiftTargetErrorRaw = field_double(sweep.APPROACH_RESULT, ...
            "OriginShiftTargetErrorRaw"), ...
        FinalTargetErrorRaw = field_double(sweep.APPROACH_RESULT, ...
            "FinalTargetErrorRaw"), ...
        FinalObservedDeltaRaw = field_double(sweep.APPROACH_RESULT, ...
            "FinalObservedDeltaRaw"), ...
        LocalBackoffTargetErrorRaw = field_double(sweep.APPROACH_RESULT, ...
            "LocalBackoffTargetErrorRaw"), ...
        ApproachReadAttempts = field_double(sweep.APPROACH_RESULT, ...
            "ApproachReadAttempts"), ...
        ApproachRetries = field_double(sweep.APPROACH_RESULT, "ApproachRetries"), ...
        ApproachTransportErrors = field_double(sweep.APPROACH_RESULT, ...
            "ApproachTransportErrors"), ...
        ApproachJumpRejects = field_double(sweep.APPROACH_RESULT, ...
            "ApproachJumpRejects"), ...
        ApproachFailedSamples = field_double(sweep.APPROACH_RESULT, ...
            "ApproachFailedSamples"), ...
        AcqRetries = field_double(sweep.Meta, "AcqRetries"), ...
        AcqTransportErrors = field_double(sweep.Meta, "AcqTransportErrors"), ...
        AcqJumpRejects = field_double(sweep.Meta, "AcqJumpRejects"), ...
        AcqFailedSamples = field_double(sweep.Meta, "AcqFailedSamples"));

    for point = 1:10
        record.(sprintf("PostTurnDelta%dDeg", point)) = postTurnDelta(point);
        record.(sprintf("PostTurnResidual%dDeg", point)) = postTurnResidual(point);
    end
    runRecords = append_struct(runRecords, record);
end

if isempty(runRecords)
    runs = table();
else
    runs = struct2table(runRecords);
    runs = sortrows(runs, "RunOrder");
end
if isempty(auditRecords)
    audit = table();
else
    audit = struct2table(auditRecords);
end
end

function [pass, reason] = gate_official_sweep(sweep, expectedProtocol, ...
        expectedPath, expectedReversalCount)
failures = strings(0, 1);

if field_double(sweep.Meta, "EligibleForStatistics") ~= 1
    failures(end + 1) = "EligibleForStatistics";
end
if field_double(sweep.Meta, "MeasurementValid") ~= 1
    failures(end + 1) = "MeasurementValid";
end
if field_double(sweep.Meta, "AnalysisPoints") ~= 360
    failures(end + 1) = "AnalysisPoints";
end
if field_double(sweep.Meta, "CapturedPoints") < 371
    failures(end + 1) = "CapturedPoints";
end
if field_string(sweep.Meta, "AcquisitionResult") ~= "OK"
    failures(end + 1) = "AcquisitionResult";
end
if field_string(sweep.END, "Status") ~= "VALID"
    failures(end + 1) = "EndStatus";
end
if field_double(sweep.Meta, "ApproachStructuralValid") ~= 1 || ...
        field_double(sweep.APPROACH_RESULT, "ApproachStructuralValid") ~= 1
    failures(end + 1) = "ApproachStructuralValid";
end
if field_string(sweep.APPROACH_RESULT, "Status") ~= "OK" || ...
        field_double(sweep.APPROACH_RESULT, "Complete") ~= 1
    failures(end + 1) = "ApproachComplete";
end
if field_double(sweep.APPROACH_RESULT, "ApproachAcquisitionClean") ~= 1
    failures(end + 1) = "ApproachAcquisitionClean";
end
if field_string(sweep.Meta, "ApproachProtocol") ~= expectedProtocol || ...
        field_string(sweep.APPROACH_RESULT, "Protocol") ~= expectedProtocol
    failures(end + 1) = "ApproachProtocol";
end
if expectedPath ~= "" && ...
        field_string(sweep.APPROACH_RESULT, "ApproachPath") ~= expectedPath
    failures(end + 1) = "ApproachPath";
end
if isfinite(expectedReversalCount) && ...
        field_double(sweep.APPROACH_RESULT, "ReversalCount") ~= expectedReversalCount
    failures(end + 1) = "ReversalCount";
end
if field_double(sweep.SHADOW_RESULT, "Valid") ~= 1 || ...
        ~isfinite(field_double(sweep.SHADOW_RESULT, "ClosureErrorDeg"))
    failures(end + 1) = "CanonicalClosure";
end

dataIndices = sweep.Data.Index;
requiredIndices = (0:370)';
if numel(dataIndices) < 371 || numel(unique(dataIndices)) ~= numel(dataIndices) || ...
        ~all(ismember(requiredIndices, dataIndices))
    failures(end + 1) = "Data0To370";
end

pass = isempty(failures);
if pass
    reason = "";
else
    reason = strjoin(failures, "|");
end
end

function value = field_double(record, name)
if isstruct(record) && isfield(record, name)
    value = str2double(string(record.(name)));
else
    value = NaN;
end
end

function value = field_string(record, name)
if isstruct(record) && isfield(record, name)
    value = string(record.(name));
else
    value = "";
end
end

function records = append_struct(records, record)
if isempty(records)
    records = record;
else
    records(end + 1) = record;
end
end
