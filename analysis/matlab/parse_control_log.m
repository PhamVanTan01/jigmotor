function runs = parse_control_log(filePath, familyPrefix)
%PARSE_CONTROL_LOG Parse CONTROL_<family>_* UART log lines into per-run data.
%   runs = PARSE_CONTROL_LOG(filePath, familyPrefix) reads filePath (a raw
%   hardware UART dump) and returns a struct array, one element per physical
%   run. familyPrefix selects which record family to parse (e.g. "A3", "A4",
%   "A5") -- lines for other families (A5 logs also interleave CONTROL_A4_*
%   context records from the alignment they ride on top of) are ignored.
%
%   Every "<family>_ARMED" line starts a new run block. Every other scalar
%   record type (SUMMARY, SEQUENCE, HEALTH, STATE, CONFIG, IDENTITY, CLOCK,
%   TIMING, RUNTIME, ...) becomes a field struct on the run, named after the
%   record type with the family prefix stripped (e.g. run.SUMMARY.Result).
%   The repeating per-tick/per-sample "DATA" record type accumulates into a
%   table at run.DATA, one row per sample, columns named after its fields.
%
%   Field values are coerced: "0x..." hex strings to double, plain numeric
%   strings to double, everything else left as string.

arguments
    filePath (1,1) string
    familyPrefix (1,1) string
end

prefix = "CONTROL_" + familyPrefix + "_";
lines = readlines(filePath);
lines = lines(startsWith(lines, prefix));
runs = struct([]);
if isempty(lines)
    return
end

armedTag = prefix + "ARMED,";
startIndex = find(startsWith(lines, armedTag));
if isempty(startIndex)
    startIndex = 1;
end
blockEnds = [startIndex(2:end) - 1; numel(lines)];

for blockIndex = 1:numel(startIndex)
    blockLines = lines(startIndex(blockIndex):blockEnds(blockIndex));
    run = struct();
    dataRows = {};
    for lineIndex = 1:numel(blockLines)
        [recordType, fields] = parse_control_log_line(blockLines(lineIndex), prefix);
        if recordType == ""
            continue
        end
        if recordType == "DATA"
            dataRows{end + 1} = fields; %#ok<AGROW>
        else
            run.(recordType) = fields;
        end
    end
    if ~isempty(dataRows)
        run.DATA = struct2table([dataRows{:}]);
    else
        run.DATA = table();
    end
    if isempty(runs)
        runs = run;
    else
        runs(end + 1) = run; %#ok<AGROW>
    end
end
end

function [recordType, fields] = parse_control_log_line(line, prefix)
commaIndex = strfind(line, ",");
if isempty(commaIndex)
    recordType = "";
    fields = struct();
    return
end
recordType = erase(extractBefore(line, commaIndex(1)), prefix);
rest = extractAfter(line, commaIndex(1));
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
    key = strtrim(kv(1));
    value = strtrim(strjoin(kv(2:end), "="));
    fields.(key) = coerce_control_log_value(value);
end
end

function value = coerce_control_log_value(raw)
if strlength(raw) > 2 && (startsWith(raw, "0x") || startsWith(raw, "0X"))
    value = double(hex2dec(char(extractAfter(raw, 2))));
    return
end
numeric = str2double(raw);
if ~isnan(numeric)
    value = numeric;
else
    value = raw;
end
end
