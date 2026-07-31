function result = find_outlier_mount_sessions(fileGroups, shiftToleranceDeg)
%FIND_OUTLIER_MOUNT_SESSIONS Screens many sessions of the SAME motor for
%   the "R4 pattern" found by hand in the p06 remount investigation: a
%   session whose curve needs a real circular shift (mechanical degrees,
%   full 360-point sweep) to align with how every OTHER session of that
%   motor lines up, rather than lining up at ~0 degrees like the
%   majority. Generalizes that one manual finding into a reusable
%   automatic screen across however many sessions/products are given.
%
%   Method: for each motor, compute the pairwise best-fit circular shift
%   (compare_nl_group_curves.m) between EVERY pair of that motor's
%   sessions, wrapped to (-180, 180]. A pair is "aligned" if
%   |wrapped shift| <= shiftToleranceDeg. For each session, AlignmentCount
%   = how many of the motor's OTHER sessions it is aligned with. The
%   session with the highest AlignmentCount is taken as the majority
%   reference orientation; every session's ShiftFromMajorityDeg is its
%   pairwise shift against that reference (0 for the reference itself).
%   IsOutlier = ShiftFromMajorityDeg exceeds the tolerance.
%
%   This is a simple pairwise-consensus heuristic, not a formal
%   clustering algorithm -- with very few sessions per motor (as few as
%   2, e.g. a single JIG1-vs-JIG4 pair) "majority" is not statistically
%   meaningful; treat AlignmentCount/SessionCount as a measure of how much
%   to trust the flag, not just IsOutlier alone.
%
%   result = FIND_OUTLIER_MOUNT_SESSIONS(fileGroups, shiftToleranceDeg)
%   fileGroups: same struct array as analyze_nl_extreme_angles.m (Files,
%   MotorId, JigId) -- JigId is used only as a free-text session label
%   here (sessions need not come from different physical jigs; the R4
%   case was 4 sessions on the SAME jig).

arguments
    fileGroups (1,:) struct
    shiftToleranceDeg (1,1) double = 15
end

groups = struct([]);
for index = 1:numel(fileGroups)
    g = build_nl_group_curve(fileGroups(index).Files, fileGroups(index).MotorId, ...
        fileGroups(index).JigId, 5);
    if isempty(groups)
        groups = g;
    else
        groups(end + 1) = g; %#ok<AGROW>
    end
end

motorIds = unique([groups.MotorId], "stable");
motor = strings(0, 1);
session = strings(0, 1);
alignmentCount = [];
sessionCount = [];
shiftFromMajorityDeg = [];
correlationVsMajority = [];
isOutlier = false(0, 1);
isMajorityReference = false(0, 1);
pairwiseDetail = table();

for m = 1:numel(motorIds)
    motorGroups = groups([groups.MotorId] == motorIds(m));
    ns = numel(motorGroups);
    if ns < 2
        continue
    end

    % Full pairwise shift matrix (wrapped to (-180,180]) and a matching
    % "aligned" boolean matrix.
    shiftMatrix = NaN(ns, ns);
    alignedMatrix = false(ns, ns);
    for i = 1:ns
        for j = 1:ns
            if i == j
                shiftMatrix(i, j) = 0;
                alignedMatrix(i, j) = true;
                continue
            end
            c = compare_nl_group_curves(motorGroups(i), motorGroups(j));
            wrapped = mod(c.BestShiftDeg + 180, 360) - 180;
            shiftMatrix(i, j) = wrapped;
            alignedMatrix(i, j) = abs(wrapped) <= shiftToleranceDeg;
            row = table(motorIds(m), motorGroups(i).JigId, motorGroups(j).JigId, ...
                c.BestShiftDeg, wrapped, c.BestShiftCorrelation, ...
                VariableNames=["Motor", "SessionA", "SessionB", "BestShiftDeg", ...
                "WrappedShiftDeg", "BestShiftCorrelation"]);
            if isempty(pairwiseDetail)
                pairwiseDetail = row;
            else
                pairwiseDetail = [pairwiseDetail; row]; %#ok<AGROW>
            end
        end
    end

    counts = sum(alignedMatrix, 2) - 1; % exclude self-alignment
    [~, referenceIdx] = max(counts);

    for i = 1:ns
        motor(end + 1, 1) = motorIds(m); %#ok<AGROW>
        session(end + 1, 1) = motorGroups(i).JigId; %#ok<AGROW>
        alignmentCount(end + 1, 1) = counts(i); %#ok<AGROW>
        sessionCount(end + 1, 1) = ns; %#ok<AGROW>
        shiftFromMajorityDeg(end + 1, 1) = shiftMatrix(referenceIdx, i); %#ok<AGROW>
        if i == referenceIdx
            correlationVsMajority(end + 1, 1) = 1; %#ok<AGROW>
        else
            c = compare_nl_group_curves(motorGroups(referenceIdx), motorGroups(i));
            correlationVsMajority(end + 1, 1) = c.BestShiftCorrelation; %#ok<AGROW>
        end
        isOutlier(end + 1, 1) = abs(shiftMatrix(referenceIdx, i)) > shiftToleranceDeg; %#ok<AGROW>
        isMajorityReference(end + 1, 1) = (i == referenceIdx); %#ok<AGROW>
    end
end

summary = table(motor, session, sessionCount, alignmentCount, shiftFromMajorityDeg, ...
    correlationVsMajority, isMajorityReference, isOutlier, VariableNames=...
    ["Motor", "Session", "SessionsForMotor", "AlignmentCount", "ShiftFromMajorityDeg", ...
    "CorrelationVsMajority", "IsMajorityReference", "IsOutlier"]);
summary = sortrows(summary, ["Motor", "IsOutlier"], ["ascend", "descend"]);

result = struct(Summary = summary, PairwiseDetail = pairwiseDetail, ...
    ShiftToleranceDeg = shiftToleranceDeg);

fprintf("=== Outlier-mount screen: shift tolerance = +/-%.0f deg ===\n", shiftToleranceDeg);
disp(summary);
outlierRows = summary(summary.IsOutlier, :);
if isempty(outlierRows)
    fprintf("No sessions flagged -- every session aligns with its motor's majority within tolerance.\n");
else
    fprintf("Flagged %d session(s) (out of %d) as ""R4-like"" outliers:\n", ...
        height(outlierRows), height(summary));
    for r = 1:height(outlierRows)
        fprintf("  %s / %s: shift=%.0f deg vs majority (aligned with %d/%d other sessions)\n", ...
            outlierRows.Motor(r), outlierRows.Session(r), outlierRows.ShiftFromMajorityDeg(r), ...
            outlierRows.AlignmentCount(r), outlierRows.SessionsForMotor(r) - 1);
    end
end
end
