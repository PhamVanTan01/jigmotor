function sweeps = parse_nl_log(filePath)
%PARSE_NL_LOG Parse an NL (nonlinear measurement) hardware log into sweeps.
%   Mirrors tools/analyze_nl_stability.py's load_sweeps(): groups records by
%   (TestID, SweepID). META/RESULT/SHADOW_RESULT/APPROACH_RESULT/END are
%   Key=Value comma records; DATA is POSITIONAL (12 comma fields, not
%   Key=Value): field 3=TestID, 4=SweepID, 8=Index, 9=TargetRaw,
%   10=AngleRaw, 11=AngleDeg, 12=ErrorDeg (1-indexed here; 0-indexed in the
%   Python source as parts[2],[3],[7],[8],[9],[10],[11]). Records without
%   their own TestID/SweepID (RESULT/SHADOW_RESULT/APPROACH_RESULT/END)
%   attach to the most recently seen (TestID,SweepID) key, exactly like the
%   Python tool's `active_key`.
%
%   Returns a struct array, one element per sweep, with fields:
%   TestID, SweepID, Meta (struct), Result/Shadow/Approach/End (struct,
%   possibly missing), Data (table: Index/TargetRaw/AngleRaw/AngleDeg/
%   ErrorDeg), FirmwareNLDeg (double, NaN if not found).

arguments
    filePath (1,1) string
end

lines = readlines(filePath);
sweepOrder = strings(0, 1);
sweepByKey = containers.Map('KeyType', 'char', 'ValueType', 'any');
activeKey = "";

firmwareNlPattern = "Nonlinear\s+\d+\s+Angle:\s*(-?\d+(?:\.\d+)?)\s+degree";

for index = 1:numel(lines)
    line = lines(index);
    if strlength(line) == 0
        continue
    end

    firmwareMatch = regexp(line, firmwareNlPattern, "tokens", "once");
    if ~isempty(firmwareMatch) && activeKey ~= ""
        sweep = sweepByKey(activeKey);
        sweep.FirmwareNLDeg = str2double(firmwareMatch{1});
        sweepByKey(activeKey) = sweep;
        continue
    end

    commaIndex = strfind(line, ",");
    if isempty(commaIndex)
        continue
    end
    recordType = extractBefore(line, commaIndex(1));

    if recordType == "DATA"
        parts = split(line, ",");
        if numel(parts) ~= 12
            continue
        end
        testId = str2double(parts(3));
        sweepId = str2double(parts(4));
        key = sprintf("%d_%d", testId, sweepId);
        if ~isKey(sweepByKey, key)
            sweepByKey(key) = new_sweep(testId, sweepId);
            sweepOrder(end + 1) = string(key); %#ok<AGROW>
        end
        sweep = sweepByKey(key);
        rowIndex = height(sweep.Data) + 1;
        % parts(8)=Index, parts(9)=TargetRaw, parts(10)=AngleRaw,
        % parts(11)=AngleDeg (unused, skipped), parts(12)=ErrorDeg.
        sweep.Data(rowIndex, :) = {str2double(parts(8)), str2double(parts(9)), ...
            str2double(parts(10)), str2double(parts(12))};
        sweepByKey(key) = sweep;
        activeKey = string(key);
        continue
    end

    fields = parse_kv_fields(line, recordType);

    switch recordType
        case "META"
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
            sweep.Meta = fields;
            sweepByKey(key) = sweep;
            activeKey = string(key);
        case {"RESULT", "SHADOW_RESULT", "APPROACH_RESULT", "END"}
            if activeKey == "" || ~isKey(sweepByKey, char(activeKey))
                continue
            end
            sweep = sweepByKey(char(activeKey));
            sweep.(char(recordType)) = fields;
            sweepByKey(char(activeKey)) = sweep;
        otherwise
            % Other record types (GRID, BATCH, RUNTIME, ...) are not part
            % of the NL stability metric set; ignored here exactly as the
            % Python tool ignores them.
    end
end

sweeps = struct([]);
for index = 1:numel(sweepOrder)
    sweep = sweepByKey(char(sweepOrder(index)));
    if isempty(sweeps)
        sweeps = sweep;
    else
        sweeps(end + 1) = sweep; %#ok<AGROW>
    end
end
end

function sweep = new_sweep(testId, sweepId)
sweep = struct('TestID', testId, 'SweepID', sweepId, 'Meta', struct(), ...
    'RESULT', struct(), 'SHADOW_RESULT', struct(), 'APPROACH_RESULT', struct(), ...
    'END', struct(), 'FirmwareNLDeg', NaN, ...
    'Data', table('Size', [0 4], 'VariableTypes', repmat("double", 1, 4), ...
    'VariableNames', ["Index","TargetRaw","AngleRaw","ErrorDeg"]));
% NOTE: AngleDeg (parts[10]) is intentionally not stored separately -- it
% is not used by any metric in analyze_nl_stability.py, only ErrorDeg is.
end

function fields = parse_kv_fields(line, prefix)
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
