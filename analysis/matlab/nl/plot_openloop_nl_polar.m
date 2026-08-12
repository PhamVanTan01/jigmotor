function outPath = plot_openloop_nl_polar(files, labels, outPath)
%PLOT_OPENLOOP_NL_POLAR Polar E(theta) fingerprint for schema-v6
%   GREMSY_COMPAT_OPEN_LOOP_NL_V1 logs -- independent MATLAB cross-check
%   of tools/motor_quality_polar.py's chart for the same file (separate
%   codebase, same authoritative ErrorRawQ16 source; if the two disagree
%   that is a real bug in one of them, not just style).
%
%   Only ever draws the error-curve panel. Unlike the V5.8-era diagnostic
%   chart (plot_v58_motor_quality_polar.m), there is deliberately no gap/
%   timing panel here: a genuinely open-loop log (RULE 0) has zero
%   SWEEP_CREEP_POINT/SWEEP_POINT_TIMING records by construction, so a
%   second panel would either be empty or, worse, silently pull in a
%   different file's diagnostic telemetry. Only OFFICIAL open-loop sweeps
%   (parse_openloop_nl_log.m's IsOpenLoopOfficial gate, same as
%   analyze_openloop_nl_batch.m) are averaged into each label's curve.
%
%   files/labels : string arrays, one file per log. Every file's mean
%                  curve is overlaid; the FIRST file's own order-2 peak
%                  angles (motor-locked tilt/eccentricity direction) are
%                  marked with red dashed lines, matching the convention
%                  used by tools/motor_quality_polar.py.
%   outPath       : where to save the PNG

arguments
    files (1,:) string
    labels (1,:) string
    outPath (1,1) string = "C:\learn\rd\jig\analysis-out\openloop_nl_polar.png"
end

nFiles = numel(files);
theta = (0:359)';
curves = nan(360, nFiles);

for i = 1:nFiles
    sweeps = parse_openloop_nl_log(files(i));
    acc = [];
    for s = 1:numel(sweeps)
        sw = sweeps(s);
        if ~sw.IsOpenLoopOfficial
            continue
        end
        d = sw.Data;
        d = d(d.Index >= 0 & d.Index < 360, :);
        if height(d) < 360
            continue
        end
        curve = nan(360, 1);
        curve(d.Index + 1) = d.ErrorDeg;
        if any(isnan(curve))
            continue
        end
        acc = [acc, curve]; %#ok<AGROW>
    end
    if isempty(acc)
        fprintf('WARNING: %s has no OFFICIAL open-loop sweeps with a full 360-point curve -- skipped.\n', labels(i));
        continue
    end
    fprintf('%s: %d OFFICIAL open-loop sweep(s) averaged.\n', labels(i), size(acc, 2));
    curves(:, i) = mean(acc, 2);
end

if all(isnan(curves(:)))
    error('plot_openloop_nl_polar:noData', 'No file produced a usable open-loop curve.');
end

smoothWin = 9;
curvesSmooth = nan(size(curves));
for i = 1:nFiles
    if all(isnan(curves(:, i)))
        continue
    end
    curvesSmooth(:, i) = circular_smooth(curves(:, i) - mean(curves(:, i), 'omitnan'), smoothWin);
end
floorVal = min(curvesSmooth(:), [], 'omitnan');
ceilVal = max(curvesSmooth(:), [], 'omitnan');
pad = 0.02 * (ceilVal - floorVal);

refIdx = find(~all(isnan(curves), 1), 1);
err0 = curves(:, refIdx) - mean(curves(:, refIdx), 'omitnan');
idx = (0:359)';
a = sum(err0 .* cosd(2*idx), 'omitnan');
b = sum(err0 .* sind(2*idx), 'omitnan');
phi2 = atan2d(b, a) / 2;
motorLockedAnglesDeg = mod([phi2, phi2 + 180], 360);

fig = figure('Visible', 'off', 'Position', [100 100 800 750], 'Color', 'w');
ax = polaraxes(fig);
hold(ax, 'on');
colors = lines(nFiles);
lw = 1.5 * ones(1, nFiles);
if nFiles > 1
    lw(refIdx) = 2.8;
end
for i = 1:nFiles
    if all(isnan(curvesSmooth(:, i)))
        continue
    end
    polarplot(ax, deg2rad(theta), curvesSmooth(:, i) - floorVal + pad, ...
        'LineWidth', lw(i), 'Color', colors(i, :), 'DisplayName', labels(i));
end
for a2 = motorLockedAnglesDeg
    polarplot(ax, [deg2rad(a2) deg2rad(a2)], ax.RLim, 'r--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
end
ax.ThetaZeroLocation = 'top';
ax.ThetaDir = 'clockwise';
legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal');
title(ax, sprintf('Open-loop NL fingerprint (schema v6) -- red dashed = motor-locked angles of %s (%.0f,%.0f deg)\nradius = smoothed, DC-removed, offset (ripple shape, not absolute error)', ...
    labels(refIdx), motorLockedAnglesDeg(1), motorLockedAnglesDeg(2)));

exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function y = circular_smooth(x, window)
padded = [x(end-window+1:end); x; x(1:window)];
sm = movmean(padded, window, 'omitnan');
y = sm(window+1:window+numel(x));
end
