function result = parse_sector_calibration_log(filePath)
%PARSE_SECTOR_CALIBRATION_LOG Parse SECTOR_CALIBRATION diagnostic lines
%   (format: "SECTOR_CALIBRATION,BatchID=%lu,TargetIndex=%lu,TargetRaw=%ld")
%   emitted once per batch when ENABLE_NL_SECTOR_CALIBRATION_SWEEP=1
%   (Core/Src/nonlinear_test.c), and cross-checks each batch's COMMANDED
%   target against the ACHIEVED AnalysisStartRaw of that batch's sweeps
%   (from the normal META records, via parse_nl_log.m) -- quantifies how
%   precisely the new active pre-positioning step actually lands where
%   commanded, which is exactly what the calibration sweep experiment
%   needs to trust before fitting a sector-response curve to it.

arguments
    filePath (1,1) string
end

lines = readlines(filePath);
calibLines = lines(startsWith(lines, "SECTOR_CALIBRATION,"));

batchId = [];
targetIndex = [];
targetRaw = [];
for index = 1:numel(calibLines)
    line = calibLines(index);
    batchId(end + 1, 1) = extract_field(line, "BatchID"); %#ok<AGROW>
    targetIndex(end + 1, 1) = extract_field(line, "TargetIndex"); %#ok<AGROW>
    targetRaw(end + 1, 1) = extract_field(line, "TargetRaw"); %#ok<AGROW>
end

commanded = table(batchId, targetIndex, targetRaw, ...
    VariableNames=["BatchID", "TargetIndex", "CommandedTargetRaw"]);

if isempty(commanded)
    error("SectorCalibration:NoCommandedTargets", ...
        "No SECTOR_CALIBRATION lines found in %s -- was ENABLE_NL_SECTOR_CALIBRATION_SWEEP=1 for this build?", filePath);
end

sweeps = parse_nl_log(filePath);
achievedBatchId = [];
achievedSectorRaw = [];
for index = 1:numel(sweeps)
    sweep = sweeps(index);
    if ~isfield(sweep, "Meta") || isempty(fieldnames(sweep.Meta))
        continue
    end
    if ~isfield(sweep.Meta, "BatchID") || ~isfield(sweep.Meta, "AnalysisStartRaw")
        continue
    end
    achievedBatchId(end + 1, 1) = str2double(sweep.Meta.BatchID); %#ok<AGROW>
    achievedSectorRaw(end + 1, 1) = str2double(sweep.Meta.AnalysisStartRaw); %#ok<AGROW>
end

achievedMeanByBatch = table();
uniqueBatches = unique(achievedBatchId);
for index = 1:numel(uniqueBatches)
    mask = achievedBatchId == uniqueBatches(index);
    row = table(uniqueBatches(index), mean(achievedSectorRaw(mask)), sum(mask), ...
        VariableNames=["BatchID", "AchievedSectorRawMean", "SweepCount"]);
    achievedMeanByBatch = [achievedMeanByBatch; row]; %#ok<AGROW>
end

comparison = innerjoin(commanded, achievedMeanByBatch, Keys="BatchID");
comparison.ErrorRaw = comparison.AchievedSectorRawMean - comparison.CommandedTargetRaw;

result = struct(Commanded = commanded, Achieved = achievedMeanByBatch, Comparison = comparison);

fprintf("=== Sector calibration commanded-vs-achieved: %d batches ===\n", height(comparison));
disp(comparison(:, ["BatchID", "TargetIndex", "CommandedTargetRaw", "AchievedSectorRawMean", "SweepCount", "ErrorRaw"]));
if ~isempty(comparison)
    fprintf("Pre-position error: mean=%.1f raw  max abs=%.1f raw\n", ...
        mean(comparison.ErrorRaw), max(abs(comparison.ErrorRaw)));
end
end

function value = extract_field(line, name)
tokens = regexp(line, name + "=(-?\d+)", "tokens");
if isempty(tokens)
    value = NaN;
else
    value = str2double(tokens{1}{1});
end
end
