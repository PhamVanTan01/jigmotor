function result = analyze_offaxis_calibration_risk(fileGroups, opts)
%ANALYZE_OFFAXIS_CALIBRATION_RISK Screen NL sweep curves for the "sharp,
%   localized field distortion" signature that would explain a motor
%   passing the jig's closed-loop NL sweep cleanly while its separate
%   MA600 32-point offset-calibration table (the Gremsy gimbal QA/QC
%   tool's ENCODER_MA600 routine, NOT jigmotor-nl2 -- see
%   docs/session-summary-2026-08-06.md section 10, the P09 finding) fails
%   to converge. That tool's raw log/source aren't in this repo, so this
%   works from what IS available: the jig's own NL sweep curve for the
%   same motor, using two assumption-light diagnostics plus one direct
%   simulation of the failing mechanism:
%
%   1. MaxAbsJumpDeg -- the largest point-to-point step anywhere on the
%      measured curve. A real magnetic-field gradient hot spot (e.g. from
%      an off-axis-mounted sensor die reading a non-uniform local field,
%      per the confirmed P09 root cause) shows up here as an isolated
%      spike, independent of any harmonic-order assumption. The jig's
%      closed-loop creep correction (analysis/matlab/nl/*sweep_creep*)
%      tracks through a hot spot fine -- it always corrects toward
%      whatever the live gap actually is -- so this signature can be
%      completely invisible in NL_RobustP2P_Deg while still being fatal
%      for a table that assumes local smoothness between knots.
%   2. OtherHighOrderRmsDeg -- RMS energy at harmonic orders above
%      HighOrderCutoff (default 16, the Nyquist limit a 32-point table
%      can resolve at all) EXCLUDING multiples of MotorHarmonicMultiple
%      (default 6 -- the project's established "motor" harmonic family,
%      6x-pole-pairs cogging-torque-like ripple, real and expected to be
%      large regardless of mounting; see docs/session-summary-2026-08-04-
%      board-effect-and-sensor-fixture-separation.md section 5). What's
%      left after excluding that family is orders a clean, well-centered
%      mount has no reason to populate -- elevated energy there is a
%      second, independent line of evidence for a non-periodic local
%      distortion.
%   3. MaxAbsResidualDeg -- simulate_lut_calibration_residual.m applied
%      to this exact curve: what a LutPoints-knot table (default 32,
%      matching MA600's real CORR0-31 and the earlier LUT-aliasing
%      review of tools/*non_linear*.html) would leave uncorrected. Directly
%      answers "would THIS curve's shape defeat a 32-point table," using
%      the same simulated mechanism, on real data instead of a synthetic
%      sine.
%
%   IMPORTANT: the Gremsy tool's own angle reference frame is NOT the
%   same as the jig's (different raw scale, different zero -- see the
%   session-summary's own caution against matching index numbers across
%   the two tools). Do not report an angle from this analysis as "the
%   same physical position" as the Gremsy tool's flagged index without
%   independent confirmation -- only the MAGNITUDE of these diagnostics
%   is comparable across motors, not literal angle-to-angle correspondence.
%
%   result = ANALYZE_OFFAXIS_CALIBRATION_RISK(fileGroups, opts)
%   fileGroups: struct array with Files/MotorId/JigId (same shape as
%   analyze_nl_extreme_angles.m). Returns a struct:
%     Summary -- one row per group, sorted by MaxAbsJumpDeg descending.
%     Detail  -- struct array (one per group) with the full MeanError
%                curve, harmonic Spectrum, and LUT Residual curve, for
%                follow-up plotting.

arguments
    fileGroups (1,:) struct
    opts.LutPoints (1,1) double = 32
    opts.HighOrderCutoff (1,1) double = 16
    opts.MotorHarmonicMultiple (1,1) double = 6
end

rows = table();
detail = struct([]);
for index = 1:numel(fileGroups)
    g = build_nl_group_curve(fileGroups(index).Files, fileGroups(index).MotorId, ...
        fileGroups(index).JigId, 5);
    n = g.AnalysisPoints;
    curve = g.MeanError;

    orders = 1:floor(n / 2);
    spectrum = compute_harmonic_spectrum(curve, orders);
    isMotorFamily = mod(orders, opts.MotorHarmonicMultiple) == 0;
    isOtherHigh = (orders > opts.HighOrderCutoff) & ~isMotorFamily;
    otherHighOrderRmsDeg = sqrt(sum(spectrum(isOtherHigh) .^ 2) / 2);

    jumps = curve(mod((0:n - 1)' + 1, n) + 1) - curve; % circular forward difference
    [maxAbsJump, jumpAt] = max(abs(jumps));
    jumpAtAngleDeg = (jumpAt - 1) * 360.0 / n;

    residual = simulate_lut_calibration_residual(curve, opts.LutPoints);
    [maxAbsResidual, residualAt] = max(abs(residual));
    residualAtAngleDeg = (residualAt - 1) * 360.0 / n;

    row = table(g.MotorId, g.JigId, g.EligibleRuns, maxAbsJump, jumpAtAngleDeg, ...
        otherHighOrderRmsDeg, maxAbsResidual, residualAtAngleDeg, VariableNames = ...
        ["MotorId","JigId","EligibleRuns","MaxAbsJumpDeg","JumpAtAngleDeg", ...
        "OtherHighOrderRmsDeg","MaxAbsResidualDeg","ResidualAtAngleDeg"]);
    if isempty(rows)
        rows = row;
    else
        rows = [rows; row]; %#ok<AGROW>
    end

    d = struct(MotorId = g.MotorId, JigId = g.JigId, MeanError = curve, ...
        Orders = orders, Spectrum = spectrum, Residual = residual);
    if isempty(detail)
        detail = d;
    else
        detail(end + 1) = d; %#ok<AGROW>
    end
end

rows = sortrows(rows, "MaxAbsJumpDeg", "descend");
result = struct(Summary = rows, Detail = detail);

fprintf("=== Off-axis / local-distortion calibration-risk screen: %d groups ===\n", height(rows));
disp(rows);
fprintf(strcat("Note: JumpAtAngleDeg/ResidualAtAngleDeg are in the JIG's own angle frame -- ", ...
    "NOT comparable to any index/angle reported by a different calibration tool ", ...
    "(e.g. the Gremsy gimbal QA/QC console) without independent confirmation.\n"));
end
