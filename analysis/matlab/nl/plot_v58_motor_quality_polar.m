function outPath = plot_v58_motor_quality_polar(files, labels, motorLabel, outPath)
%PLOT_V58_MOTOR_QUALITY_POLAR Polar "fingerprint" chart for a batch of
%   sweeps: error curve E(theta) and control-effort/difficulty curve
%   (SWEEP_CREEP_POINT InitialAbsGapRaw), theta = commanded angle 0-360deg.
%
%   Overlays every file's curve so one motor's line can be compared
%   against the envelope of the others directly. Marks three things
%   inferred from the surrounding analysis (not recomputed generically
%   here -- this is a diagnostic chart for one specific comparison):
%     - the order-2 (twice-per-revolution) peak angles of motorLabel's
%       error curve, i.e. where a real eccentricity/tilt defect that
%       rotates WITH the rotor would show up twice per turn
%     - "jig-locked" hard points: Points that rank in the hardest 15% by
%       MeanIterations in EVERY file except motorLabel's -- i.e. angles
%       that are difficult regardless of which physical motor is
%       mounted, which points at the fixture/jig rather than the motor
%     - "timeout points": Points where motorLabel's ReachedDeadbandPct
%       (from SWEEP_POINT_TIMING) is below 100%, i.e. at least one
%       official sweep never settled into the deadband within the
%       allotted time budget at that angle -- plotted at their true
%       MeanTimeToDeadbandMs radius on a third "time to deadband" panel,
%       not pinned to the rim, so the marker position is itself data
%
%   files/labels : string arrays, one file per sweep-log, motorLabel is
%                  the label (must be a member of labels) to highlight
%   outPath       : where to save the PNG (folder must exist)

arguments
    files (1,:) string
    labels (1,:) string
    motorLabel (1,1) string
    outPath (1,1) string = "C:\learn\rd\jig\analysis-out\v58_motor_quality_polar.png"
end

nFiles = numel(files);
errCurves = nan(360, nFiles);
for i = 1:nFiles
    errCurves(:, i) = mean_official_error_curve(files(i));
end

[pointMap, ~, ~] = analyze_point_difficulty_map(files, labels);
gapCurves = nan(360, nFiles);
timeCurves = nan(360, nFiles);
reachedPctCurves = nan(360, nFiles);
uLabels = unique(labels, 'stable');
for i = 1:nFiles
    sub = pointMap(pointMap.Label == labels(i), :);
    sub = sortrows(sub, 'Point');
    valid = sub.Point >= 0 & sub.Point < 360;
    pts = sub.Point(valid) + 1;
    gapCurves(pts, i) = sub.MeanInitialAbsGapRaw(valid);
    timeCurves(pts, i) = sub.MeanTimeToDeadbandMs(valid);
    reachedPctCurves(pts, i) = sub.ReachedDeadbandPct(valid);
end

% order-2 peak angles of motorLabel's error curve
motorIdx = find(labels == motorLabel, 1);
theta = (0:359)';
err0 = errCurves(:, motorIdx) - mean(errCurves(:, motorIdx), 'omitnan');
n = 360;
idx = (0:n-1)';
a = sum(err0 .* cosd(2*idx), 'omitnan');
b = sum(err0 .* sind(2*idx), 'omitnan');
phi2 = atan2d(b, a) / 2;
motorLockedAnglesDeg = mod([phi2, phi2 + 180], 360);

% jig-locked hard points: hardest 15% by MeanIterations in EVERY other label
otherLabels = uLabels(uLabels ~= motorLabel);
hardSets = cell(1, numel(otherLabels));
for k = 1:numel(otherLabels)
    sub = pointMap(pointMap.Label == otherLabels(k), :);
    sub = sortrows(sub, 'MeanIterations', 'descend');
    nTop = round(0.15 * height(sub));
    hardSets{k} = sub.Point(1:nTop);
end
jigLockedPoints = hardSets{1};
for k = 2:numel(hardSets)
    jigLockedPoints = intersect(jigLockedPoints, hardSets{k});
end

% timeout points: motorLabel's own points where at least one official
% sweep failed to reach the deadband in time (ReachedDeadbandPct < 100)
timeoutPointsIdx = find(reachedPctCurves(:, motorIdx) < 100);
timeoutPointsDeg = theta(timeoutPointsIdx);
timeoutRadius = timeCurves(timeoutPointsIdx, motorIdx);

fig = figure('Visible', 'off', 'Position', [100 100 2000 700], 'Color', 'w');
tl = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

colors = lines(nFiles);
lw = 1.2 * ones(1, nFiles);
lw(motorIdx) = 2.8;

smoothWin = 9;
errSmooth = nan(size(errCurves));
gapSmooth = nan(size(gapCurves));
timeSmooth = nan(size(timeCurves));
for i = 1:nFiles
    errSmooth(:, i) = circular_smooth(errCurves(:, i) - mean(errCurves(:, i), 'omitnan'), smoothWin);
    gapSmooth(:, i) = circular_smooth(gapCurves(:, i), smoothWin);
    timeSmooth(:, i) = circular_smooth(timeCurves(:, i), smoothWin);
end
errFloor = min(errSmooth(:)) - 0.02 * (max(errSmooth(:)) - min(errSmooth(:)));

ax1 = polaraxes(tl); ax1.Layout.Tile = 1;
hold(ax1, 'on');
for i = 1:nFiles
    polarplot(ax1, deg2rad(theta), errSmooth(:, i) - errFloor, ...
        'LineWidth', lw(i), 'Color', colors(i, :), 'DisplayName', labels(i));
end
for a2 = motorLockedAnglesDeg
    polarplot(ax1, [deg2rad(a2) deg2rad(a2)], ax1.RLim, 'r--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
end
if ~isempty(timeoutPointsDeg)
    polarplot(ax1, deg2rad(timeoutPointsDeg), ax1.RLim(2) * ones(size(timeoutPointsDeg)), ...
        'o', 'Color', [0.85 0 0], 'MarkerSize', 5, 'LineWidth', 1.1, ...
        'DisplayName', 'timeout points (rim-pinned, see time panel for true value)');
end
ax1.ThetaZeroLocation = 'top';
ax1.ThetaDir = 'clockwise';
title(ax1, sprintf('Error curve E(theta), smoothed+offset (radius = ripple, not absolute error) -- thick line = %s', motorLabel));
legend(ax1, 'Location', 'southoutside', 'Orientation', 'horizontal');

ax2 = polaraxes(tl); ax2.Layout.Tile = 2;
hold(ax2, 'on');
for i = 1:nFiles
    polarplot(ax2, deg2rad(theta), gapSmooth(:, i), ...
        'LineWidth', lw(i), 'Color', colors(i, :), 'DisplayName', labels(i));
end
for a2 = motorLockedAnglesDeg
    polarplot(ax2, [deg2rad(a2) deg2rad(a2)], ax2.RLim, 'r--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
end
if ~isempty(jigLockedPoints)
    rOuter = ax2.RLim(2);
    polarplot(ax2, deg2rad(jigLockedPoints), rOuter * ones(size(jigLockedPoints)), 'kx', ...
        'MarkerSize', 6, 'LineWidth', 1.2, 'DisplayName', 'jig-locked hard points (common)');
end
ax2.ThetaZeroLocation = 'top';
ax2.ThetaDir = 'clockwise';
title(ax2, 'Initial gap per point (raw ticks) -- control effort needed to correct');
legend(ax2, 'Location', 'southoutside', 'Orientation', 'horizontal');

ax3 = polaraxes(tl); ax3.Layout.Tile = 3;
hold(ax3, 'on');
for i = 1:nFiles
    polarplot(ax3, deg2rad(theta), timeSmooth(:, i), ...
        'LineWidth', lw(i), 'Color', colors(i, :), 'DisplayName', labels(i));
end
for a2 = motorLockedAnglesDeg
    polarplot(ax3, [deg2rad(a2) deg2rad(a2)], ax3.RLim, 'r--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
end
if ~isempty(timeoutPointsDeg)
    polarplot(ax3, deg2rad(timeoutPointsDeg), timeoutRadius, 'o', ...
        'MarkerSize', 7, 'MarkerFaceColor', [0.85 0 0], 'MarkerEdgeColor', 'k', 'LineStyle', 'none', ...
        'DisplayName', sprintf('%s: ReachedDeadband<100%% (exceeded time budget)', motorLabel));
end
ax3.ThetaZeroLocation = 'top';
ax3.ThetaDir = 'clockwise';
title(ax3, 'Time to deadband per point (ms) -- filled red = exceeded time budget at that angle');
legend(ax3, 'Location', 'southoutside', 'Orientation', 'horizontal');

title(tl, sprintf('Motor quality fingerprint (V5.8) -- red dashed = 2 motor-locked angles of %s (theta=%.0fdeg, %.0fdeg); black x = jig-locked hard points; red dots (right panel) = points that exceeded the response-time budget', ...
    motorLabel, motorLockedAnglesDeg(1), motorLockedAnglesDeg(2)), 'FontWeight', 'bold');

exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function y = circular_smooth(x, window)
padded = [x(end-window+1:end); x; x(1:window)];
sm = movmean(padded, window, 'omitnan');
y = sm(window+1:window+numel(x));
end

function curve = mean_official_error_curve(file)
sweeps = parse_nl_log(file);
acc = [];
for k = 1:numel(sweeps)
    sw = sweeps(k);
    role = "";
    if isfield(sw.Meta, "RunRole")
        role = string(sw.Meta.RunRole);
    end
    if role == "PRECONDITION"
        continue
    end
    if height(sw.Data) < 360
        continue
    end
    e = sw.Data.ErrorDeg(1:360);
    if any(isnan(e))
        continue
    end
    acc = [acc, e]; %#ok<AGROW>
end
if isempty(acc)
    curve = nan(360, 1);
else
    curve = mean(acc, 2);
end
end
