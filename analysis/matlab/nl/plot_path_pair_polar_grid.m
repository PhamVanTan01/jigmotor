function outPath = plot_path_pair_polar_grid(motorIds, path1Files, path2Files, outPath)
%PLOT_PATH_PAIR_POLAR_GRID Overlay path1 vs path2 polar E(theta) per motor.
%   One polar subplot per motor (tiled grid), each showing that motor's
%   path1 (blue) and path2 (orange) mean open-loop error curves overlaid,
%   using build_openloop_nl_group_curve.m + compare_nl_group_curves.m for
%   the r0/best-shift/RMSE annotation in each subplot's title -- same
%   numbers as analyze_openloop_nl_batch.m's table, just visual.
%
%   motorIds            : string array, one per motor
%   path1Files/path2Files : cell array, one element per motor, each a
%                          string array of that motor's path1/path2 files
%   outPath              : where to save the PNG

arguments
    motorIds (1,:) string
    path1Files (1,:) cell
    path2Files (1,:) cell
    outPath (1,1) string = "C:\learn\rd\jig\analysis-out\path1_vs_path2_polar_grid.png"
end

nMotors = numel(motorIds);
nCols = ceil(sqrt(nMotors));
nRows = ceil(nMotors / nCols);

fig = figure('Visible', 'off', 'Position', [100 100 420*nCols 420*nRows], 'Color', 'w');
tl = tiledlayout(fig, nRows, nCols, 'TileSpacing', 'compact', 'Padding', 'compact');

theta = deg2rad((0:359)');
smoothWin = 9;

for i = 1:nMotors
    g1 = build_openloop_nl_group_curve(path1Files{i}, motorIds(i), "path1");
    g2 = build_openloop_nl_group_curve(path2Files{i}, motorIds(i), "path2");
    cmp = compare_nl_group_curves(g1, g2);

    c1 = circular_smooth(g1.MeanError - mean(g1.MeanError), smoothWin);
    c2 = circular_smooth(g2.MeanError - mean(g2.MeanError), smoothWin);
    floorVal = min([c1; c2]);
    pad = 0.02 * (max([c1; c2]) - floorVal);

    ax = polaraxes(tl); ax.Layout.Tile = i;
    hold(ax, 'on');
    polarplot(ax, theta, c1 - floorVal + pad, 'LineWidth', 2.2, 'Color', [0 0.4470 0.7410], 'DisplayName', 'path1');
    polarplot(ax, theta, c2 - floorVal + pad, 'LineWidth', 2.2, 'Color', [0.8500 0.3250 0.0980], 'DisplayName', 'path2');
    ax.ThetaZeroLocation = 'top';
    ax.ThetaDir = 'clockwise';
    title(ax, sprintf('%s -- r0=%.3f shift=%.0f%s RMSE=%.3f%s', ...
        motorIds(i), cmp.ZeroShiftCorrelation, cmp.BestShiftDeg, char(176), cmp.CenteredRmseAlignedDeg, char(176)));
    legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal', 'FontSize', 7);
end

title(tl, 'path1 vs path2 today, per motor -- radius = smoothed, DC-removed, offset (ripple shape, not absolute error)', ...
    'FontWeight', 'bold');

exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function y = circular_smooth(x, window)
padded = [x(end-window+1:end); x; x(1:window)];
sm = movmean(padded, window, 'omitnan');
y = sm(window+1:window+numel(x));
end
