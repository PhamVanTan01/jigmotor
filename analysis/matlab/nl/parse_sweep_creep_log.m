function result = parse_sweep_creep_log(filePath)
%PARSE_SWEEP_CREEP_LOG Extract ENABLE_SWEEP_POINT_CREEP telemetry from a log.
%   Covers the V5.1/V5.2/V5.3/V5.4/V5.5 field evolution documented in
%   docs/session-summary-2026-08-05.md: SWEEP_CREEP_CONFIG (once/sweep),
%   SWEEP_CREEP_POINT (one row per point that got creep-corrected --
%   V5.1 has only the base fields; V5.2 adds PreCrossGapRaw/CrossingGapRaw/
%   Recovery*; V5.3 adds FineLanding*/StickSlipJumpDetected/
%   MaxObservedStepDeltaRaw/TraceCount; V5.4 adds universal live-gap
%   selection and first-integrity-failure trace metadata; V5.5 adds dynamic
%   BASE-to-EXTENDED budget-escalation telemetry),
%   SWEEP_CREEP_STEP (V5.3+ only,
%   detailed per-iteration trace for points selected for a full trace,
%   e.g. FineTargetPoint), and the SweepPointCreep*-prefixed fields on the
%   END record (one per-sweep rollup already computed by firmware).
%
%   Fields absent for an older schema version are filled with NaN
%   (numeric) or "" (string) rather than erroring, so V5.1-V5.5 logs
%   can be pooled in one analyze_sweep_creep_batch.m call.
%
%   result = PARSE_SWEEP_CREEP_LOG(filePath) returns a struct with 4
%   tables: Config, Points, Steps, SweepSummary (from END). Any table is
%   0 rows (all columns present) if the log has none of that record type.

arguments
    filePath (1,1) string
end

configFields = ["SchemaVersion","TestID","SweepID","JigID","MotorID","Direction","Official", ...
    "Enabled","Protocol","SelectionRule","TriggerRaw","BudgetEscalationProtocol", ...
    "BaseBudgetRaw","BasePrimaryBudgetRaw","BaseHardBudgetRaw","BaseMaxIterations", ...
    "BaseEscalatedMaxIterations", ...
    "ExtendedBudgetRaw","ExtendedMaxIterations","StepRaw","DeadbandRaw","Power", ...
    "TargetCrossingGuard","RecoveryProtocol","RecoveryBudgetRaw","RecoveryMaxIterations", ...
    "FineLandingProtocol","FineSelectionRule","FineTargetPoint","FineEntryRaw","FineStepRaw", ...
    "FineMaxIterations","FineBaseMaxIterations","FineExtendedMaxIterations", ...
    "JumpThresholdRaw","FineRecoveryBudgetRaw","FineRecoveryMaxIterations", ...
    "TracePolicy","TraceCapacity"];
configNumeric = ~ismember(configFields, ["JigID","MotorID","Direction","Protocol", ...
    "SelectionRule","BudgetEscalationProtocol","TargetCrossingGuard","RecoveryProtocol","FineLandingProtocol", ...
    "FineSelectionRule","TracePolicy"]);

pointFields = ["SchemaVersion","TestID","SweepID","JigID","MotorID","Direction","Point", ...
    "Official","InitialGapRaw","InitialAbsGapRaw","BudgetClass","SelectedBudgetRaw", ...
    "PrimaryBudgetRaw","HardBudgetRaw","BudgetEscalated","EscalationCorrectionRaw", ...
    "SelectedMaxIterations","Iterations","TotalCorrectionRaw","PreCrossGapRaw","CrossingGapRaw", ...
    "RecoveryAttempted","RecoverySucceeded","RecoveryIterations","RecoveryCorrectionRaw", ...
    "FineLandingAttempted","FineLandingSucceeded","FineIterations","FineCorrectionRaw", ...
    "StickSlipJumpDetected","MaxObservedStepDeltaRaw","TraceCaptured","TraceCount", ...
    "FinalGapRaw","Result"];
pointNumeric = ~ismember(pointFields, ["JigID","MotorID","Direction","BudgetClass","Result"]);

stepFields = ["SchemaVersion","TestID","SweepID","JigID","MotorID","Direction","Point", ...
    "Official","StepOrder","Iteration","Phase","CommandStepRaw","GapBeforeRaw", ...
    "ObservedDeltaRaw","GapAfterRaw","StickSlipJumpDetected"];
stepNumeric = ~ismember(stepFields, ["JigID","MotorID","Direction","Phase"]);

summaryFields = ["TestID","SweepID","Status","AcquisitionResult", ...
    "SweepPointCreepPointsCorrected","SweepPointCreepTotalIterations", ...
    "SweepPointCreepTotalCorrectionRaw","SweepPointCreepTimeouts", ...
    "SweepPointCreepBudgetExceeded","SweepPointCreepTargetCrossed", ...
    "SweepPointCreepRecoveryAttempted","SweepPointCreepRecoverySucceeded", ...
    "SweepPointCreepRecoveryFailed","SweepPointCreepRecoveryRecrossed", ...
    "SweepPointCreepRecoveryTotalIterations","SweepPointCreepRecoveryTotalCorrectionRaw", ...
    "SweepPointCreepBaseBudgetExceeded","SweepPointCreepBaseTargetCrossed", ...
    "SweepPointCreepBaseEscalationAttempted","SweepPointCreepBaseEscalationSucceeded", ...
    "SweepPointCreepBaseEscalationFailed","SweepPointCreepBaseEscalationCorrectionRaw", ...
    "SweepPointCreepExtendedPoints","SweepPointCreepExtendedOk", ...
    "SweepPointCreepExtendedTotalIterations","SweepPointCreepExtendedTotalCorrectionRaw", ...
    "SweepPointCreepExtendedTimeouts","SweepPointCreepExtendedBudgetExceeded", ...
    "SweepPointCreepExtendedTargetCrossed","SweepPointCreepFineLandingAttempted", ...
    "SweepPointCreepFineLandingSucceeded","SweepPointCreepFineLandingFailed", ...
    "SweepPointCreepFineBaseAttempted","SweepPointCreepFineExtendedAttempted", ...
    "SweepPointCreepTracePoint", ...
    "SweepPointCreepStickSlipJump","SweepPointCreepMaxObservedStepDeltaRaw", ...
    "SweepPointCreepIntegrityValid"];
summaryNumeric = ~ismember(summaryFields, ["Status","AcquisitionResult"]);

configRows = {};
pointRows = {};
stepRows = {};
summaryRows = {};

lines = readlines(filePath);
for index = 1:numel(lines)
    line = lines(index);
    if strlength(line) == 0
        continue
    end
    commaIndex = strfind(line, ",");
    if isempty(commaIndex)
        continue
    end
    recordType = extractBefore(line, commaIndex(1));
    switch recordType
        case "SWEEP_CREEP_CONFIG"
            fields = parse_kv_fields_local(line, recordType);
            configRows{end + 1} = build_row(fields, configFields, configNumeric); %#ok<AGROW>
        case "SWEEP_CREEP_POINT"
            fields = parse_kv_fields_local(line, recordType);
            pointRows{end + 1} = build_row(fields, pointFields, pointNumeric); %#ok<AGROW>
        case "SWEEP_CREEP_STEP"
            fields = parse_kv_fields_local(line, recordType);
            stepRows{end + 1} = build_row(fields, stepFields, stepNumeric); %#ok<AGROW>
        case "END"
            fields = parse_kv_fields_local(line, recordType);
            if isfield(fields, "SweepPointCreepIntegrityValid")
                summaryRows{end + 1} = build_row(fields, summaryFields, summaryNumeric); %#ok<AGROW>
            end
        otherwise
            % Not a sweep-point-creep record; ignored.
    end
end

result = struct( ...
    Config = rows_to_table(configRows, configFields, configNumeric), ...
    Points = rows_to_table(pointRows, pointFields, pointNumeric), ...
    Steps = rows_to_table(stepRows, stepFields, stepNumeric), ...
    SweepSummary = rows_to_table(summaryRows, summaryFields, summaryNumeric));
end

function row = build_row(fields, names, isNumeric)
row = cell(1, numel(names));
for k = 1:numel(names)
    name = names(k);
    if isfield(fields, name)
        value = fields.(name);
        if isNumeric(k)
            row{k} = str2double(value);
        else
            row{k} = string(value);
        end
    else
        if isNumeric(k)
            row{k} = NaN;
        else
            row{k} = "";
        end
    end
end
end

function t = rows_to_table(rows, names, isNumeric)
varTypes = repmat("string", 1, numel(names));
varTypes(isNumeric) = "double";
t = table('Size', [numel(rows), numel(names)], 'VariableTypes', varTypes, 'VariableNames', names);
for r = 1:numel(rows)
    t(r, :) = rows{r};
end
end

function fields = parse_kv_fields_local(line, prefix)
rest = extractAfter(line, strlength(prefix) + 1);
parts = split(rest, ",");
fields = struct();
for index = 1:numel(parts)
    part = parts(index);
    if strlength(part) == 0
        continue
    end
    kv = split(part, "=");
    if numel(kv) < 2
        continue
    end
    key = matlab.lang.makeValidName(strtrim(kv(1)));
    value = strtrim(strjoin(kv(2:end), "="));
    fields.(key) = value;
end
end
