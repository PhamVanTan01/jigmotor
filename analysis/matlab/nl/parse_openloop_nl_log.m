function sweeps = parse_openloop_nl_log(filePath)
%PARSE_OPENLOOP_NL_LOG Parse a schema-v6 GREMSY_COMPAT_OPEN_LOOP_NL_V1 log.
%   Deliberately a SEPARATE parser from parse_nl_log.m (schema v4/v5), per
%   docs/nonlinear-log-schema-v6.md's own rule: "A parser must never infer
%   v6 semantics from a v5 record." Schema v6 changed both the DATA record
%   (12 legacy positional fields + 3 appended canonical Q16 key=value
%   fields: CommandRawQ16/MeanUnwrappedRawQ16/ErrorRawQ16) and RESULT (a
%   much richer harmonic/model/tracking field set, with OpenLoopNL_Deg =
%   max(Error)-min(Error) as the Gremsy-compatible PRIMARY metric --
%   RobustP2P_Deg is supporting only, never a substitute).
%
%   For schema>=6, ErrorDeg is RECOMPUTED from the authoritative
%   ErrorRawQ16 (matching tools/analyze_motor_logs.py's parse_data_line
%   exactly: error_deg = ErrorRawQ16 * 360 / (65536 * 65536)) rather than
%   trusting the legacy positional ErrorDeg field, which is presentation
%   only per the schema doc.
%
%   Returns a struct array, one per (TestID,SweepID) sweep:
%     TestID, SweepID, Meta (struct), Result (struct), End (struct),
%     Data (table: Index/ErrorDeg/CommandRawQ16/MeanUnwrappedRawQ16/
%     ErrorRawQ16), IsOpenLoopOfficial (logical convenience flag --
%     Meta.MeasurementProfile=="GREMSY_COMPAT_OPEN_LOOP_NL_V1" AND
%     Meta.OfficialOpenLoopNL=="1" AND Meta.FeedbackActuationEnabled=="0"
%     AND Meta.RunRole=="OFFICIAL" AND Meta.EligibleForStatistics=="1" --
%     the RULE-0-compliant gate; callers should still check it explicitly
%     rather than assume every sweep in a "v6" file passes it).

arguments
    filePath (1,1) string
end

FULL_TURN_RAW = 65536.0;
Q16_SCALE = 65536.0;

metaFields = ["SchemaVersion","TestID","SweepID","JigID","MotorID","Direction", ...
    "MeasurementPolicy","MeasurementProfile","MeasurementDefinition", ...
    "MeasurementContractVersion","OfficialOpenLoopNL","FeedbackActuationEnabled", ...
    "RampEncoderObservationEnabled","RampFeedbackActuationEnabled", ...
    "OfficialResultSource","OfficialMeasurementValid","OfficialInvalidReasonMask", ...
    "Quality","SettleContract","SettleTargetRequired","SettleStabilityValid", ...
    "SettleTargetProximityValid","SettleValid","TrackingValid","ClosureValid", ...
    "AnalysisPoints","CapturedPoints","StepRaw","MotorPoleCount","MotorPolePairs", ...
    "ElectricalRippleOrder","RunRole","EligibleForStatistics","BatchID","RunOrder", ...
    "BatchRunCount","AcquisitionResult"];
metaNumeric = ~ismember(metaFields, ["JigID","MotorID","Direction","MeasurementPolicy", ...
    "MeasurementProfile","MeasurementDefinition","MeasurementContractVersion", ...
    "OfficialOpenLoopNL","FeedbackActuationEnabled","RampEncoderObservationEnabled", ...
    "RampFeedbackActuationEnabled","OfficialResultSource","OfficialMeasurementValid", ...
    "OfficialInvalidReasonMask","Quality","SettleContract","SettleTargetRequired", ...
    "SettleStabilityValid","SettleTargetProximityValid","SettleValid","TrackingValid", ...
    "ClosureValid","RunRole","EligibleForStatistics","AcquisitionResult"]);

resultFields = ["OpenLoopNL_Deg","RobustP2P_Deg","MeanDC","RMS_AC", ...
    "Point0MeanRawQ16","ClosureErrorRawQ16","ClosureErrorDeg","ClosureLimitDeg","ClosureValid", ...
    "A1","A2","A3","A4","A6","A8","A9","A12","A18","A27","A36","A45","A72","A108", ...
    "H1_PhaseSweepDeg","H2_PhaseSweepDeg","H3_PhaseSweepDeg","H4_PhaseSweepDeg", ...
    "H6_PhaseSweepDeg","H8_PhaseSweepDeg","H9_PhaseSweepDeg","H12_PhaseSweepDeg", ...
    "H18_PhaseSweepDeg","H27_PhaseSweepDeg","H36_PhaseSweepDeg","H45_PhaseSweepDeg", ...
    "H72_PhaseSweepDeg","H108_PhaseSweepDeg", ...
    "AElectrical6","Electrical6_PhaseSweepDeg","ElectricalRippleValid", ...
    "DominantSelectedOrder","DominantSelectedAmplitude","DominantSelectedEnergyRatio", ...
    "Fitted_P2P","FitExplainedRatio","Fitted_P2P_Extended","FitExplainedRatio_Extended", ...
    "Motor_Error_P2P_Deg","Motor_System_INL_Deg","CrestFactor","P99_AbsDeviation", ...
    "TrackingError_RMS_Deg","TrackingError_MaxAbs_Deg"];
resultNumeric = ~ismember(resultFields, ["ClosureValid","ElectricalRippleValid"]);

endFields = ["OfficialMeasurementValid","OfficialInvalidReasonMask","Status", ...
    "AcquisitionResult","SweepPointCreepPointsCorrected","SweepPointCreepTotalIterations", ...
    "SweepPointCreepTotalCorrectionRaw","SweepPointCreepBudgetExceeded", ...
    "SweepPointCreepTargetCrossed","SweepPointCreepRecoveryAttempted", ...
    "SweepPointCreepRecoverySucceeded","SweepPointCreepRecoveryFailed", ...
    "SweepPointCreepStickSlipJump","SweepPointCreepIntegrityValid"];
endNumeric = ~ismember(endFields, ["OfficialMeasurementValid","OfficialInvalidReasonMask","Status","AcquisitionResult"]);

lines = readlines(filePath);
sweepOrder = strings(0, 1);
sweepByKey = containers.Map('KeyType', 'char', 'ValueType', 'any');
activeKey = "";

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

    if recordType == "DATA"
        parts = split(line, ",");
        if numel(parts) < 12
            continue
        end
        schema = str2double(parts(2));
        testId = str2double(parts(3));
        sweepId = str2double(parts(4));
        idx = str2double(parts(8));
        errorDegPositional = str2double(parts(12));

        commandRawQ16 = NaN; meanUnwrappedRawQ16 = NaN; errorRawQ16 = NaN;
        errorDeg = errorDegPositional;
        if numel(parts) > 12
            extra = parse_kv_parts(parts(13:end));
            if isfield(extra, "CommandRawQ16")
                commandRawQ16 = str2double(extra.CommandRawQ16);
            end
            if isfield(extra, "MeanUnwrappedRawQ16")
                meanUnwrappedRawQ16 = str2double(extra.MeanUnwrappedRawQ16);
            end
            if isfield(extra, "ErrorRawQ16")
                errorRawQ16 = str2double(extra.ErrorRawQ16);
                if schema >= 6
                    errorDeg = errorRawQ16 * 360.0 / (FULL_TURN_RAW * Q16_SCALE);
                end
            end
        end

        key = sprintf("%d_%d", testId, sweepId);
        if ~isKey(sweepByKey, key)
            sweepByKey(key) = new_sweep(testId, sweepId);
            sweepOrder(end + 1) = string(key); %#ok<AGROW>
        end
        sweep = sweepByKey(key);
        rowIndex = height(sweep.Data) + 1;
        sweep.Data(rowIndex, :) = {idx, errorDeg, commandRawQ16, meanUnwrappedRawQ16, errorRawQ16};
        sweepByKey(key) = sweep;
        activeKey = string(key);
        continue
    end

    switch recordType
        case "META"
            fields = parse_kv_fields_local(line, recordType);
            if ~isfield(fields, "TestID") || ~isfield(fields, "SweepID")
                continue
            end
            testId = str2double(fields.TestID);
            sweepId = str2double(fields.SweepID);
            key = sprintf("%d_%d", testId, sweepId);
            if ~isKey(sweepByKey, key)
                sweepByKey(key) = new_sweep(testId, sweepId);
                sweepOrder(end + 1) = string(key); %#ok<AGROW>
            end
            sweep = sweepByKey(key);
            sweep.Meta = build_row_struct(fields, metaFields, metaNumeric);
            sweepByKey(key) = sweep;
            activeKey = string(key);
        case "RESULT"
            if activeKey == "" || ~isKey(sweepByKey, char(activeKey))
                continue
            end
            fields = parse_kv_fields_local(line, recordType);
            sweep = sweepByKey(char(activeKey));
            sweep.Result = build_row_struct(fields, resultFields, resultNumeric);
            sweepByKey(char(activeKey)) = sweep;
        case "END"
            if activeKey == "" || ~isKey(sweepByKey, char(activeKey))
                continue
            end
            fields = parse_kv_fields_local(line, recordType);
            sweep = sweepByKey(char(activeKey));
            sweep.End = build_row_struct(fields, endFields, endNumeric);
            sweepByKey(char(activeKey)) = sweep;
        otherwise
            % CONFIG/ACQ/MOTION/GRID/BATCH/... not needed for the NL scalar
            % and harmonic report; ignored here.
    end
end

sweeps = struct([]);
for index = 1:numel(sweepOrder)
    sweep = sweepByKey(char(sweepOrder(index)));
    sweep.IsOpenLoopOfficial = is_openloop_official(sweep.Meta);
    if isempty(sweeps)
        sweeps = sweep;
    else
        sweeps(end + 1) = sweep; %#ok<AGROW>
    end
end
end

function tf = is_openloop_official(meta)
tf = isfield(meta, "MeasurementProfile") && meta.MeasurementProfile == "GREMSY_COMPAT_OPEN_LOOP_NL_V1" ...
    && isfield(meta, "OfficialOpenLoopNL") && meta.OfficialOpenLoopNL == "1" ...
    && isfield(meta, "FeedbackActuationEnabled") && meta.FeedbackActuationEnabled == "0" ...
    && isfield(meta, "RunRole") && meta.RunRole == "OFFICIAL" ...
    && isfield(meta, "EligibleForStatistics") && meta.EligibleForStatistics == "1";
end

function sweep = new_sweep(testId, sweepId)
sweep = struct('TestID', testId, 'SweepID', sweepId, 'Meta', struct(), ...
    'Result', struct(), 'End', struct(), ...
    'Data', table('Size', [0 5], 'VariableTypes', repmat("double", 1, 5), ...
    'VariableNames', ["Index","ErrorDeg","CommandRawQ16","MeanUnwrappedRawQ16","ErrorRawQ16"]));
end

function s = build_row_struct(fields, names, isNumeric)
s = struct();
for k = 1:numel(names)
    name = names(k);
    if isfield(fields, name)
        value = fields.(name);
        if isNumeric(k)
            s.(name) = str2double(value);
        else
            s.(name) = string(value);
        end
    else
        if isNumeric(k)
            s.(name) = NaN;
        else
            s.(name) = "";
        end
    end
end
end

function fields = parse_kv_fields_local(line, prefix)
rest = extractAfter(line, strlength(prefix) + 1);
parts = split(rest, ",");
fields = parse_kv_parts(parts);
end

function fields = parse_kv_parts(parts)
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
