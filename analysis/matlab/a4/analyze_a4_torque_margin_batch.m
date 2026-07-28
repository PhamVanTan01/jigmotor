function result = analyze_a4_torque_margin_batch(logPaths)
%ANALYZE_A4_TORQUE_MARGIN_BATCH Aggregate static/kinetic friction-fraction
%   estimates (see compute_a4_torque_margin.m) across an A4/A4B log batch.
%   Reports mean/SD/95% bootstrap CI, matching this project's established
%   statistical-rigor pattern (compute_nl_stability_stats.m). Values are a
%   FRACTION of the motor's torque at 100% commanded power, not N*m -- see
%   compute_a4_torque_margin.m for why absolute torque needs a separate
%   calibration this jig does not currently have.

arguments
    logPaths (1,:) string
end

rows = table();
for fileIndex = 1:numel(logPaths)
    runs = parse_control_log(logPaths(fileIndex), "A4");
    for runIndex = 1:numel(runs)
        metric = compute_a4_torque_margin(runs(runIndex));
        if metric.Result ~= "OK" || metric.CaptureRequired ~= 1 ...
                || isnan(metric.StaticFrictionFraction)
            continue
        end
        row = struct2table(metric);
        row.Source = fullfile_basename(logPaths(fileIndex)) + "#" + string(runIndex);
        if isempty(rows)
            rows = row;
        else
            rows = [rows; row]; %#ok<AGROW>
        end
    end
end

if isempty(rows)
    error("A4Torque:NoRuns", ...
        "No CaptureRequired=1, Result=OK A4 runs with a valid static-friction estimate found.");
end

staticStats = bootstrap_stats(rows.StaticFrictionFraction);
firmwareStaticStats = bootstrap_stats(rows.FirmwareStaticFrictionFraction(~isnan(rows.FirmwareStaticFrictionFraction)));
kineticStats = bootstrap_stats(rows.KineticFrictionFraction(~isnan(rows.KineticFrictionFraction)));

result = struct(Runs = rows, StaticFrictionStats = staticStats, ...
    KineticFrictionStats = kineticStats, ...
    FirmwareCaptureStaticFrictionStats = firmwareStaticStats);

fprintf("=== A4 torque margin (fraction of T_max @ 100%% power): %d runs ===\n", height(rows));
fprintf("Static friction, peak-lag method (mu_s):  mean=%.4f  SD=%.4f  95%%CI=[%.4f, %.4f]  n=%d\n", ...
    staticStats.Mean, staticStats.SD, staticStats.CI95(1), staticStats.CI95(2), staticStats.N);
fprintf("Static friction, firmware-capture method:  mean=%.4f  SD=%.4f  95%%CI=[%.4f, %.4f]  n=%d  (expected higher -- delayed by design)\n", ...
    firmwareStaticStats.Mean, firmwareStaticStats.SD, firmwareStaticStats.CI95(1), firmwareStaticStats.CI95(2), firmwareStaticStats.N);
fprintf("Kinetic friction (mu_k), mean over drag:   mean=%.4f  SD=%.4f  95%%CI=[%.4f, %.4f]  n=%d\n", ...
    kineticStats.Mean, kineticStats.SD, kineticStats.CI95(1), kineticStats.CI95(2), kineticStats.N);
fprintf("(cross-check vs docs/control-a3-result.md + control-a2f-p09-result.md: mu_s ~0.09-0.10, mu_k ~0.04)\n");
fprintf("(median Runs.DragLagRangeRaw=%.0f raw -- DragLagRaw oscillates substantially during drag in this dataset; mu_k above is a mean over that oscillation, not a steady value)\n", ...
    median(rows.DragLagRangeRaw, "omitnan"));

notRising = sum(~rows.LagRisingTrendToPeak);
if notRising > 0
    fprintf("WARNING: %d/%d runs did not show a significant rising lag trend before the peak -- inspect Runs.LagRisingTrendToPeak/LagTrendR before trusting their mu_s.\n", ...
        notRising, height(rows));
end
notConstantPower = sum(~rows.PowerConstantDuringSweep);
if notConstantPower > 0
    fprintf("WARNING: %d/%d runs did not hold PowerPpm constant across PHASE_SWEEP -- the fixed-power assumption is violated for those runs.\n", ...
        notConstantPower, height(rows));
end
end

function stats = bootstrap_stats(values)
values = values(:);
n = numel(values);
stats = struct(N = n, Mean = NaN, SD = NaN, CI95 = [NaN, NaN]);
if n == 0
    return
end
stats.Mean = mean(values);
if n > 1
    stats.SD = std(values, 0);
end
if n < 3
    stats.CI95 = [stats.Mean, stats.Mean];
    return
end
rng(12345, "twister"); % deterministic across runs, for reproducible reports
numBoot = 5000;
bootMeans = zeros(numBoot, 1);
for bootIndex = 1:numBoot
    sampleIndex = randi(n, n, 1);
    bootMeans(bootIndex) = mean(values(sampleIndex));
end
stats.CI95 = prctile_manual(bootMeans, [2.5, 97.5]);
end

function p = prctile_manual(values, percentiles)
sortedValues = sort(values);
n = numel(sortedValues);
p = zeros(size(percentiles));
for index = 1:numel(percentiles)
    rank = percentiles(index) / 100 * (n - 1) + 1;
    lowIndex = floor(rank);
    highIndex = ceil(rank);
    frac = rank - lowIndex;
    p(index) = sortedValues(lowIndex) * (1 - frac) + sortedValues(highIndex) * frac;
end
end

function name = fullfile_basename(path)
[~, name, ~] = fileparts(path);
name = string(name);
end
