function records = parse_mount_precheck_log(filePath)
%PARSE_MOUNT_PRECHECK_LOG Extract MOUNT_PRECHECK_RESULT records from a log.
%   Firmware emits one MOUNT_PRECHECK_RESULT,Key=Value,... line per
%   PRECONDITION sweep (Core/Src/nonlinear_test.c, MOUNT_PRECHECK_V1
%   milestone M0 -- see the ENABLE_MOUNT_PRECHECK_GATE comment block
%   there). This is a standalone per-batch "mounting fingerprint": unlike
%   the other record types parse_nl_log.m handles, it is not itself part
%   of a (TestID,SweepID) sweep and needs no DATA/META correlation, so it
%   gets its own lightweight parser rather than being folded into
%   parse_nl_log.m's sweep-keyed model.
%
%   records = PARSE_MOUNT_PRECHECK_LOG(filePath) returns a table, one row
%   per MOUNT_PRECHECK_RESULT line found, columns: JigID, MotorID,
%   BatchID, CycleOrder, TestID, RobustP2PDeg, H1AmplitudeDeg,
%   H1PhaseDeg, H2AmplitudeDeg, H2PhaseDeg, ClosureErrorDeg,
%   TrackingValid, ClosureValid, AcquisitionResult, MountValid,
%   RejectReason, GateEnabled. Empty table (0 rows, all columns present)
%   if the file has none -- lets callers concatenate results across many
%   files without a file-by-file isempty branch.

arguments
    filePath (1,1) string
end

varNames = ["JigID","MotorID","BatchID","CycleOrder","TestID","RobustP2PDeg", ...
    "H1AmplitudeDeg","H1PhaseDeg","H2AmplitudeDeg","H2PhaseDeg","ClosureErrorDeg", ...
    "TrackingValid","ClosureValid","AcquisitionResult","MountValid","RejectReason","GateEnabled"];
varTypes = ["string","string","double","double","double","double", ...
    "double","double","double","double","double", ...
    "double","double","string","double","string","double"];
records = table('Size', [0, numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);

lines = readlines(filePath);
for index = 1:numel(lines)
    line = lines(index);
    if ~startsWith(line, "MOUNT_PRECHECK_RESULT,")
        continue
    end
    fields = parse_kv_fields_local(line);
    row = { ...
        field_string(fields, "JigID"), field_string(fields, "MotorID"), ...
        field_double(fields, "BatchID"), field_double(fields, "CycleOrder"), ...
        field_double(fields, "TestID"), field_double(fields, "RobustP2PDeg"), ...
        field_double(fields, "H1AmplitudeDeg"), field_double(fields, "H1PhaseDeg"), ...
        field_double(fields, "H2AmplitudeDeg"), field_double(fields, "H2PhaseDeg"), ...
        field_double(fields, "ClosureErrorDeg"), field_double(fields, "TrackingValid"), ...
        field_double(fields, "ClosureValid"), field_string(fields, "AcquisitionResult"), ...
        field_double(fields, "MountValid"), field_string(fields, "RejectReason"), ...
        field_double(fields, "GateEnabled")};
    records(end + 1, :) = row; %#ok<AGROW>
end
end

function fields = parse_kv_fields_local(line)
rest = extractAfter(line, strlength("MOUNT_PRECHECK_RESULT") + 1);
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

function value = field_double(fields, name)
if isfield(fields, name)
    value = str2double(fields.(name));
else
    value = NaN;
end
end

function value = field_string(fields, name)
if isfield(fields, name)
    value = string(fields.(name));
else
    value = "";
end
end
