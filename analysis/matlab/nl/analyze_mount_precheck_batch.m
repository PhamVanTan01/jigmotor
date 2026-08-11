function result = analyze_mount_precheck_batch(filePaths, labels)
%ANALYZE_MOUNT_PRECHECK_BATCH Pool MOUNT_PRECHECK_RESULT records across
%   files/sessions and summarize H1/H2 amplitude by group, as a first
%   step toward the H1/H2 mounting-quality threshold flagged as
%   uncalibrated in Core/Src/nonlinear_test.c (MOUNT_PRECHECK_V1 M0
%   comment block): "H1 shrinks and sometimes H2 grows under bad
%   mounting... not yet calibrated from enough pilot data (one clean vs.
%   one confounded sample per product so far)". This tool does not itself
%   decide a threshold -- it only pools what has been captured so far so
%   that decision can be made from a growing pilot dataset instead of by
%   eye on one file at a time.
%
%   result = ANALYZE_MOUNT_PRECHECK_BATCH(filePaths, labels) parses every
%   MOUNT_PRECHECK_RESULT record from each file (one file may contain
%   several, one per batch/precondition), tags each row with its file's
%   label (free text, e.g. an assembly name -- MUST be the physical
%   sensor+fixture assembly identity per docs/session-summary-2026-08-03-
%   mount-precheck-and-assembly-swap.md section 4, not the board/JigID
%   text logged by firmware, since that pairing is exactly what was found
%   to drift), and returns:
%     Records  -- one row per MOUNT_PRECHECK_RESULT found, all fields
%                 plus Label and SourceFile.
%     ByLabel  -- one row per label: N, MountValidRate, and
%                 mean/SD/min/max for H1AmplitudeDeg, H2AmplitudeDeg,
%                 H2OverH1, RobustP2PDeg, ClosureErrorDeg.
%     RejectReasonCounts -- cross-tab of Label x RejectReason counts.
%
%   labels defaults to each file's own basename if omitted (one label per
%   file, matching analyze_nl_stability_batch.m's convention -- pass the
%   same label to multiple files to pool them into one group).

arguments
    filePaths (1,:) string
    labels (1,:) string = strings(1, 0)
end

if isempty(labels)
    labels = fullfile_basenames(filePaths);
elseif numel(labels) ~= numel(filePaths)
    error("MountPrecheck:LabelCount", ...
        "labels (%d) must match filePaths (%d) in count.", numel(labels), numel(filePaths));
end

records = table();
for fileIndex = 1:numel(filePaths)
    fileRecords = parse_mount_precheck_log(filePaths(fileIndex));
    if isempty(fileRecords)
        continue
    end
    fileRecords.Label = repmat(labels(fileIndex), height(fileRecords), 1);
    fileRecords.SourceFile = repmat(filePaths(fileIndex), height(fileRecords), 1);
    if isempty(records)
        records = fileRecords;
    else
        records = [records; fileRecords]; %#ok<AGROW>
    end
end

if isempty(records)
    error("MountPrecheck:NoRecords", "No MOUNT_PRECHECK_RESULT lines found in the given files.");
end
records.H2OverH1 = records.H2AmplitudeDeg ./ records.H1AmplitudeDeg;

labelNames = unique(records.Label, "stable");
byLabel = table();
for index = 1:numel(labelNames)
    subset = records(records.Label == labelNames(index), :);
    row = table(labelNames(index), height(subset), mean(subset.MountValid == 1) * 100.0, ...
        VariableNames = ["Label", "N", "MountValidRatePct"]);
    row = [row, describe_column(subset.H1AmplitudeDeg, "H1AmplitudeDeg")]; %#ok<AGROW>
    row = [row, describe_column(subset.H2AmplitudeDeg, "H2AmplitudeDeg")]; %#ok<AGROW>
    row = [row, describe_column(subset.H2OverH1, "H2OverH1")]; %#ok<AGROW>
    row = [row, describe_column(subset.RobustP2PDeg, "RobustP2PDeg")]; %#ok<AGROW>
    row = [row, describe_column(subset.ClosureErrorDeg, "ClosureErrorDeg")]; %#ok<AGROW>
    if isempty(byLabel)
        byLabel = row;
    else
        byLabel = [byLabel; row]; %#ok<AGROW>
    end
end
byLabel = sortrows(byLabel, "Mean_H1AmplitudeDeg");

rejectReasonCounts = groupcounts(records, ["Label", "RejectReason"]);

result = struct(Records = records, ByLabel = byLabel, RejectReasonCounts = rejectReasonCounts);

fprintf("=== MOUNT_PRECHECK_RESULT pilot pool: %d records, %d labels ===\n", ...
    height(records), numel(labelNames));
disp(byLabel(:, ["Label","N","MountValidRatePct","Mean_H1AmplitudeDeg","SD_H1AmplitudeDeg", ...
    "Mean_H2AmplitudeDeg","Mean_H2OverH1"]));
fprintf("-- RejectReason breakdown (why MountValid=0, where applicable) --\n");
disp(rejectReasonCounts);
fprintf(strcat("Note: H1/H2 columns are logged for calibration only -- ", ...
    "no validated threshold exists yet (see Core/Src/nonlinear_test.c, ", ...
    "MOUNT_PRECHECK_V1 M0 comment). Do not gate on these numbers alone.\n"));
end

function names = fullfile_basenames(paths)
names = strings(size(paths));
for index = 1:numel(paths)
    [~, name, ~] = fileparts(paths(index));
    names(index) = string(name);
end
end

function row = describe_column(values, prefix)
values = values(~isnan(values));
if isempty(values)
    m = NaN; s = NaN; lo = NaN; hi = NaN;
else
    m = mean(values);
    if numel(values) > 1
        s = std(values, 0);
    else
        s = 0;
    end
    lo = min(values);
    hi = max(values);
end
row = table(m, s, lo, hi, VariableNames = ...
    ["Mean_" + prefix, "SD_" + prefix, "Min_" + prefix, "Max_" + prefix]);
end
