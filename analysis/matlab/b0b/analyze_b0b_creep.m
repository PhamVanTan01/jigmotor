function result = analyze_b0b_creep(filePaths)
%ANALYZE_B0B_CREEP Compare B0BCreepProtocol=NONE vs ENCODER_CREEP_V1 legs.
%   Unlike soft-start (a cadence change to the open-loop quintic move),
%   creep is a closed-loop corrective nudge applied AFTER the quintic move
%   settles, iterating (up to NL_B0B_CREEP_MAX_ITERATIONS=30, deadband
%   NL_B0B_CREEP_DEADBAND_RAW=16, safety cap NL_B0B_CREEP_MAX_TOTAL_RAW=150)
%   until within deadband of the -182/+182 raw target. BackoffObservedDeltaRaw
%   / ApproachObservedDeltaRaw in APPROACH_RESULT already reflect the
%   post-creep position (Core/Src/nonlinear_test.c: CreepToUnwrappedTarget
%   runs, then backoffAnchorUnwrapped/backoffObservedDeltaRaw are computed
%   from the corrected finalSample), so "% of target" here is directly the
%   metric creep is meant to improve.

arguments
    filePaths (1,:) string
end

targetRaw = 182.0;
rows = table();
for fileIndex = 1:numel(filePaths)
    [~, results] = parse_b0b_log(filePaths(fileIndex));
    sweepIds = cell2mat(keys(results));
    for sweepId = sweepIds
        r = results(sweepId);
        if ~isfield(r, "B0BCreepProtocol") || ~isfield(r, "Status")
            continue
        end
        if string(r.Status) ~= "OK" || ~isfield(r, "ApproachStructuralValid") || ...
                string(r.ApproachStructuralValid) ~= "1"
            continue
        end
        backoffDelta = field_double(r, "BackoffObservedDeltaRaw");
        approachDelta = field_double(r, "ApproachObservedDeltaRaw");
        row = table(fullfile_basename(filePaths(fileIndex)) + "#" + string(sweepId), ...
            string(r.B0BCreepProtocol), string(field_or(r, "BackoffCreepResult", "NA")), ...
            field_double(r, "BackoffCreepIterations"), field_double(r, "BackoffCreepTotalRaw"), ...
            backoffDelta, abs(backoffDelta) / targetRaw * 100.0, ...
            string(field_or(r, "ForwardCreepResult", "NA")), ...
            field_double(r, "ForwardCreepIterations"), field_double(r, "ForwardCreepTotalRaw"), ...
            approachDelta, abs(approachDelta) / targetRaw * 100.0, ...
            VariableNames=["Source","Protocol","BackoffCreepResult", ...
            "BackoffCreepIterations","BackoffCreepTotalRaw","BackoffObservedDeltaRaw", ...
            "BackoffPctOfTarget","ForwardCreepResult","ForwardCreepIterations", ...
            "ForwardCreepTotalRaw","ApproachObservedDeltaRaw","ForwardPctOfTarget"]);
        if isempty(rows)
            rows = row;
        else
            rows = [rows; row]; %#ok<AGROW>
        end
    end
end

if isempty(rows)
    error("B0BAnalysis:NoRuns", "No B0BCreepProtocol-tagged APPROACH_RESULT rows found.");
end

protocols = unique(rows.Protocol);
result = struct(Runs = rows);
fprintf("=== B0-B creep comparison (target %.0f raw each leg) ===\n", targetRaw);
for protocolIndex = 1:numel(protocols)
    protocolName = protocols(protocolIndex);
    subset = rows(rows.Protocol == protocolName,:);
    fprintf("-- Protocol=%s (n=%d) --\n", protocolName, height(subset));
    fprintf("  BACKOFF: pct-of-target mean=%.1f%% [%.1f,%.1f] | iterations mean=%.1f max=%.0f | creepTotalRaw mean=%.1f\n", ...
        mean(subset.BackoffPctOfTarget), min(subset.BackoffPctOfTarget), ...
        max(subset.BackoffPctOfTarget), mean(subset.BackoffCreepIterations), ...
        max(subset.BackoffCreepIterations), mean(subset.BackoffCreepTotalRaw));
    fprintf("  FORWARD: pct-of-target mean=%.1f%% [%.1f,%.1f] | iterations mean=%.1f max=%.0f | creepTotalRaw mean=%.1f\n", ...
        mean(subset.ForwardPctOfTarget), min(subset.ForwardPctOfTarget), ...
        max(subset.ForwardPctOfTarget), mean(subset.ForwardCreepIterations), ...
        max(subset.ForwardCreepIterations), mean(subset.ForwardCreepTotalRaw));
    result.(matlab.lang.makeValidName(char(protocolName))) = subset;
end
end

function value = field_double(record, name)
if isfield(record, name)
    value = str2double(record.(name));
else
    value = NaN;
end
end

function value = field_or(record, name, default)
if isfield(record, name)
    value = record.(name);
else
    value = default;
end
end

function name = fullfile_basename(path)
[~, name, ~] = fileparts(path);
name = string(name);
end
