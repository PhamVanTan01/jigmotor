function [groups, pairs] = analyze_nl_extreme_angles(fileGroups, k)
%ANALYZE_NL_EXTREME_ANGLES MATLAB counterpart to
%   tools/analyze_nl_extreme_angles.py -- locates the angles that determine
%   robust NL for each (motor,jig) group and compares same-motor curves
%   across jigs via circular cross-correlation. Built as an INDEPENDENT
%   cross-check of the Python tool's own conclusions
%   (docs/nl-extreme-angle-cross-jig-test33-assessment.md), not a
%   replacement for it -- both must keep agreeing on real data (see
%   scripts/tests for the validation against analysis-out/test33-nl-
%   extreme-angles/cross_jig_curve_comparison.csv, the Python tool's own
%   output on the same Test-33 logs).
%
%   [groups, pairs] = ANALYZE_NL_EXTREME_ANGLES(fileGroups, k)
%   fileGroups: struct array, each element has fields Files (string
%   array, all belonging to one motor+jig group), MotorId, JigId. Returns
%   `groups` (struct array of build_nl_group_curve.m results) and `pairs`
%   (struct array of compare_nl_group_curves.m results, one per same-motor
%   jig-pair combination -- matches Python's itertools.combinations over
%   jigs sorted by JigId, so pair direction/order is deterministic).

arguments
    fileGroups (1,:) struct
    k (1,1) double = 5
end

groups = struct([]);
for index = 1:numel(fileGroups)
    g = build_nl_group_curve(fileGroups(index).Files, fileGroups(index).MotorId, ...
        fileGroups(index).JigId, k);
    if isempty(groups)
        groups = g;
    else
        groups(end + 1) = g; %#ok<AGROW>
    end
end

motorIds = unique([groups.MotorId], "stable");
pairs = struct([]);
for m = 1:numel(motorIds)
    motorGroups = groups([groups.MotorId] == motorIds(m));
    jigIds = [motorGroups.JigId];
    [~, order] = sort(jigIds);
    motorGroups = motorGroups(order);
    for i = 1:numel(motorGroups)
        for j = i + 1:numel(motorGroups)
            p = compare_nl_group_curves(motorGroups(i), motorGroups(j));
            if isempty(pairs)
                pairs = p;
            else
                pairs(end + 1) = p; %#ok<AGROW>
            end
        end
    end
end

fprintf("=== NL extreme-angle cross-jig comparison: %d groups, %d pairs ===\n", ...
    numel(groups), numel(pairs));
for index = 1:numel(pairs)
    p = pairs(index);
    fprintf("%s %s->%s: r0=%.4f bestShift=%.0fdeg(r=%.4f) dNL=%+.4f dTop5=%+.4f dBottom5=%+.4f\n", ...
        p.MotorId, p.JigA, p.JigB, p.ZeroShiftCorrelation, p.BestShiftDeg, p.BestShiftCorrelation, ...
        p.RobustNLDeltaBMinusADeg, p.Top5DeltaBMinusADeg, p.Bottom5DeltaBMinusADeg);
end
end
