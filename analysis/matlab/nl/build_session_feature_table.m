function features = build_session_feature_table(files, motorId, jigId)
%BUILD_SESSION_FEATURE_TABLE Flatten every numeric field the firmware logs
%   per sweep into ONE wide table, one row per OFFICIAL/eligible sweep.
%
%   Purpose: prior tools each look at ONE hand-picked signal at a time
%   (NL curve shape, A36, ClosureErrorDeg, PID gain, dead-time harmonics,
%   mounting rotation...). This is the generic substrate underneath all of
%   them -- every Key=Value numeric field parse_nl_log.m captures from
%   META/RESULT/SHADOW_RESULT/APPROACH_RESULT/END/CONTROL_STATE/
%   MOTION_RESULT/CLOSURE_PROBE_RESULT, prefixed by source record so
%   compare_features_across_jigs.m can rank ALL of them at once instead of
%   testing hypotheses one at a time.
%
%   Non-numeric fields (status strings, protocol names, hex IDs) are
%   dropped silently -- this table is for numeric cross-jig comparison
%   only; use parse_nl_log.m directly for anything that needs the raw
%   strings.
%
%   features = BUILD_SESSION_FEATURE_TABLE(files, motorId, jigId)
%   files: string array of log file paths (same motor+jig group).
%   Returns a table with columns MotorId, JigId, TestID, SweepID plus one
%   column per numeric field found (prefixed META_/RESULT_/SHADOW_/
%   APPROACH_/END_/CTRL_/MOTION_/CLOSUREPROBE_), plus NL_RobustP2P_Deg and
%   A36_Deg recomputed via compute_nl_sweep_metrics.m for cross-reference.
%   Columns absent on a given sweep are NaN for that row.

arguments
    files (1,:) string
    motorId (1,1) string
    jigId (1,1) string
end

sources = struct( ...
    "Meta", "META_", "RESULT", "RESULT_", "SHADOW_RESULT", "SHADOW_", ...
    "APPROACH_RESULT", "APPROACH_", "END", "END_", "CONTROL_STATE", "CTRL_", ...
    "MOTION_RESULT", "MOTION_", "CLOSURE_PROBE_RESULT", "CLOSUREPROBE_");
sourceNames = fieldnames(sources);

rows = {};
for fileIndex = 1:numel(files)
    sweeps = parse_nl_log(files(fileIndex));
    for sweepIndex = 1:numel(sweeps)
        sweep = sweeps(sweepIndex);
        if ~isfield(sweep, "Meta") || isempty(fieldnames(sweep.Meta))
            continue
        end
        if ~valid_official_sweep(sweep)
            continue
        end

        row = struct("MotorId", motorId, "JigId", jigId, ...
            "TestID", sweep.TestID, "SweepID", sweep.SweepID);
        for s = 1:numel(sourceNames)
            fieldName = sourceNames{s};
            prefix = sources.(fieldName);
            if ~isfield(sweep, fieldName) || isempty(fieldnames(sweep.(fieldName)))
                continue
            end
            subFields = fieldnames(sweep.(fieldName));
            for f = 1:numel(subFields)
                value = numeric_or_nan(sweep.(fieldName).(subFields{f}));
                if isnan(value)
                    continue
                end
                row.(prefix + string(subFields{f})) = value;
            end
        end

        metric = compute_nl_sweep_metrics(sweep);
        row.NL_RobustP2P_Deg = metric.NL_RobustP2P_Deg;
        row.A36_Deg_Recomputed = metric.A36_Deg;
        row.RMS_AC_Deg_Recomputed = metric.RMS_AC_Deg;

        rows{end + 1} = row; %#ok<AGROW>
    end
end

if isempty(rows)
    error("SessionFeatureTable:NoEligibleSweeps", ...
        "%s/%s: no statistically eligible sweeps in %d file(s)", ...
        motorId, jigId, numel(files));
end

features = rows_to_table(rows);
end

function value = numeric_or_nan(text)
text = string(text);
if strlength(text) == 0
    value = NaN;
    return
end
if startsWith(text, "0x") || startsWith(text, "0X")
    value = double(hex2dec(extractAfter(text, 2)));
    if isnan(value)
        value = NaN;
    end
    return
end
value = str2double(text);
end

function t = rows_to_table(rows)
% Union of all field names across rows (rows may have different fields
% present depending which log tags fired for that sweep), preserving
% first-seen order so MotorId/JigId/TestID/SweepID stay leftmost.
allNames = strings(0, 1);
seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
for r = 1:numel(rows)
    names = string(fieldnames(rows{r}));
    for n = 1:numel(names)
        key = char(names(n));
        if ~isKey(seen, key)
            seen(key) = true;
            allNames(end + 1) = names(n); %#ok<AGROW>
        end
    end
end

nRows = numel(rows);
nCols = numel(allNames);
data = cell(nRows, nCols);
for r = 1:numel(rows)
    for c = 1:nCols
        name = char(allNames(c));
        if isfield(rows{r}, name)
            data{r, c} = rows{r}.(name);
        else
            data{r, c} = NaN;
        end
    end
end

t = cell2table(data, "VariableNames", cellstr(allNames));
% MotorId/JigId were stored as scalar strings inside each row struct but
% cell2table keeps them as a cell-of-strings column; convert the two
% identifier columns to proper string columns for easy filtering upstream.
t.MotorId = string(t.MotorId);
t.JigId = string(t.JigId);
end

function valid = valid_official_sweep(sweep)
valid = false;
if isfield(sweep.Meta, "RunRole") && string(sweep.Meta.RunRole) ~= "OFFICIAL"
    return
end
if ~isfield(sweep.Meta, "AnalysisPoints") || str2double(sweep.Meta.AnalysisPoints) <= 0
    return
end
if ~isfield(sweep.Meta, "EligibleForStatistics") || string(sweep.Meta.EligibleForStatistics) ~= "1"
    return
end
if ~isfield(sweep.Meta, "MeasurementValid") || string(sweep.Meta.MeasurementValid) ~= "1"
    return
end
if ~isfield(sweep, "END") || ~isfield(sweep.END, "Status") || string(sweep.END.Status) ~= "VALID"
    return
end
analysisPoints = str2double(sweep.Meta.AnalysisPoints);
presentCount = sum(sweep.Data.Index < analysisPoints);
if presentCount ~= analysisPoints
    return
end
valid = true;
end
