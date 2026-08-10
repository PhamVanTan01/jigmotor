function residual = simulate_lut_calibration_residual(curve, lutPoints)
%SIMULATE_LUT_CALIBRATION_RESIDUAL What a piecewise-linear N-point
%   calibration table leaves behind after "correcting" a measured error
%   curve, using the exact scheme MA600's on-chip 32-point table (CORR0-
%   31) and tools/m_ph_ng_test_non_linear_ng_c_bldc_sau_d_n_nam_ch_m.html's
%   simulator both use: sample the curve at lutPoints evenly-spaced knots,
%   subtract the linear interpolation between knots from the full-
%   resolution curve. Generalizes the ad hoc check already run against
%   the simulator's synthetic sine (docs/session-summary-2026-08-06.md,
%   the LUT-aliasing review) to any real measured curve, so it can be
%   applied to actual hardware data (e.g. checking whether a specific
%   motor's raw error curve has a feature too sharp for a 32-point table
%   to resolve, independent of whether that table is ever actually
%   loaded on real hardware).
%
%   residual = SIMULATE_LUT_CALIBRATION_RESIDUAL(curve, lutPoints)
%   curve: (n,1) double, one point per degree on a full circle.
%   lutPoints: number of calibration knots (default 32, matching MA600).
%   residual: (n,1) double, curve minus its own knot-interpolated fit --
%   near zero AT the knots by construction, largest between knots where
%   the curve's local shape can't be represented by a straight line.

arguments
    curve (:,1) double
    lutPoints (1,1) double = 32
end

n = numel(curve);
step = n / lutPoints;
% Knots sit at the nearest integer sample to each ideal (possibly
% fractional, e.g. 360/32=11.25) LUT position -- unavoidable since curve
% is already a discrete 1-point-per-degree array. Interpolation below
% uses these actual (rounded) knot positions, not the ideal fractional
% grid, so no spurious residual is introduced by the rounding itself.
knotIndex = unique(mod(round((0:lutPoints - 1) * step), n), "stable");
% knotIndex(1) is always 0 (round(0*step)=0), so appending one knot past
% 360 (wrapping to the same value as index 0) gives interp1 one
% continuous monotonic sequence covering every query point 0..n-1 with no
% separate wraparound case to handle.
knotAngle = [knotIndex(:); n];
knotValue = curve(mod(knotAngle, n) + 1);

pointIndex = (0:n - 1)';
interpolated = interp1(double(knotAngle), double(knotValue), double(pointIndex), "linear");
residual = curve - interpolated;
end
