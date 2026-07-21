function [legs, results] = parse_b0b_log(filePath)
%PARSE_B0B_LOG Parse APPROACH_STEPS / APPROACH_RESULT lines from an NL log.
%   Mirrors scripts/analyze_b0b_transient.py's parse_b0b_log(): these are
%   nonlinear_test.c measurement-image records (SCURVE_LOCK_PLUS_CW_LOCAL_
%   APPROACH_V2 backoff/forward legs), NOT the CONTROL_<family>_* records
%   parse_control_log.m handles -- a different log family entirely.
%
%   legs: struct array with SweepID (double), Leg ("BACKOFF"/"FORWARD"),
%   Raw (1x40 double, one raw encoder count per tick).
%   results: containers.Map, SweepID -> struct of APPROACH_RESULT fields
%   (all values kept as strings; caller converts as needed).

arguments
    filePath (1,1) string
end

lines = readlines(filePath);
legs = struct('SweepID', {}, 'Leg', {}, 'Raw', {});
results = containers.Map('KeyType', 'double', 'ValueType', 'any');

for index = 1:numel(lines)
    line = lines(index);
    if startsWith(line, "APPROACH_STEPS,")
        fields = parse_kv_fields(line, "APPROACH_STEPS,");
        if ~isfield(fields, "UnwrappedRaw") || ~isfield(fields, "SweepID") || ...
                ~isfield(fields, "Leg")
            continue
        end
        raw = str2double(split(fields.UnwrappedRaw, "|"));
        if any(isnan(raw))
            continue
        end
        legs(end + 1) = struct('SweepID', str2double(fields.SweepID), ...
            'Leg', string(fields.Leg), 'Raw', raw(:)'); %#ok<AGROW>
    elseif startsWith(line, "APPROACH_RESULT,")
        fields = parse_kv_fields(line, "APPROACH_RESULT,");
        if ~isfield(fields, "SweepID")
            continue
        end
        results(str2double(fields.SweepID)) = fields;
    end
end
end

function fields = parse_kv_fields(line, prefix)
rest = extractAfter(line, strlength(prefix));
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
