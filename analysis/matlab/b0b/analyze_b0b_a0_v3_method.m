function result = analyze_b0b_a0_v3_method(a0BeforePath, v3Path, ...
        a0AfterPath, outputDirectory, options)
%ANALYZE_B0B_A0_V3_METHOD Recompute and decide the A0-vs-V3 experiment.
%   Produces auditable CSVs, a text decision report, and diagnostic plots.
%   A0 is shifted-sector local reversal control; V3 is the same shifted
%   sector without reversal. The required experiment order is A0-V3-A0.

arguments
    a0BeforePath (1,1) string
    v3Path (1,1) string
    a0AfterPath (1,1) string
    outputDirectory (1,1) string
    options.ExpectedRunsPerLeg (1,1) double {mustBeInteger,mustBePositive} = 10
    options.SectorToleranceRaw (1,1) double {mustBeNonnegative} = 91
    options.BootstrapCount (1,1) double {mustBeInteger,mustBePositive} = 20000
    options.CreatePlots (1,1) logical = true
end

root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root, "nl"));
addpath(fullfile(root, "b0b"));

if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

a0Protocol = "SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1";
v3Protocol = "SCURVE_CW_PREROLL_NO_REVERSAL_V1";
[a0Before, auditBefore] = extract_b0b_method_runs(a0BeforePath, ...
    "A0_BEFORE", a0Protocol, "CW_CCW_CW", 2);
[v3, auditV3] = extract_b0b_method_runs(v3Path, ...
    "V3", v3Protocol, "CW_ONLY", 0);
[a0After, auditAfter] = extract_b0b_method_runs(a0AfterPath, ...
    "A0_AFTER", a0Protocol, "CW_CCW_CW", 2);

runs = [a0Before; v3; a0After];
audit = [auditBefore; auditV3; auditAfter];
officialAudit = audit(audit.OfficialCandidate, :);

gateRecords = struct([]);
legs = ["A0_BEFORE", "V3", "A0_AFTER"];
for legIndex = 1:numel(legs)
    leg = legs(legIndex);
    legAudit = officialAudit(officialAudit.Leg == leg, :);
    validCount = sum(legAudit.GatePass);
    record = struct( ...
        Leg = leg, OfficialCandidates = height(legAudit), ...
        ValidRuns = validCount, ExpectedRuns = options.ExpectedRunsPerLeg, ...
        GatePass = height(legAudit) == options.ExpectedRunsPerLeg && ...
            validCount == options.ExpectedRunsPerLeg, ...
        ExcludedOfficialRuns = height(legAudit) - validCount);
    gateRecords = append_struct(gateRecords, record);
end
gates = struct2table(gateRecords);

if ~all(gates.GatePass)
    writetable(audit, fullfile(outputDirectory, "a0_v3_gate_audit.csv"));
    writetable(gates, fullfile(outputDirectory, "a0_v3_gate_summary.csv"));
    error("B0BMethod:StructuralGate", ...
        "A0-V3-A0 structural gate failed. Inspect %s.", ...
        fullfile(outputDirectory, "a0_v3_gate_audit.csv"));
end

comparison = compare_b0b_a0_v3(runs, options.SectorToleranceRaw, ...
    options.BootstrapCount);

writetable(runs, fullfile(outputDirectory, "a0_v3_runs.csv"));
writetable(audit, fullfile(outputDirectory, "a0_v3_gate_audit.csv"));
writetable(gates, fullfile(outputDirectory, "a0_v3_gate_summary.csv"));
writetable(comparison.LegSummary, ...
    fullfile(outputDirectory, "a0_v3_leg_summary.csv"));
writetable(comparison.Contrasts, ...
    fullfile(outputDirectory, "a0_v3_contrasts.csv"));
writetable(comparison.Sector.PerRun, ...
    fullfile(outputDirectory, "a0_v3_sector_per_run.csv"));

write_decision_report(fullfile(outputDirectory, "a0_v3_decision.txt"), ...
    a0BeforePath, v3Path, a0AfterPath, gates, comparison);
if options.CreatePlots
    create_plots(runs, comparison, outputDirectory);
end

result = struct(Runs = runs, Audit = audit, Gates = gates, ...
    LegSummary = comparison.LegSummary, Contrasts = comparison.Contrasts, ...
    Sector = comparison.Sector, Decision = comparison.Decision);

fprintf("[B0B A0-V3] selected=%s code=%s\n", ...
    result.Decision.SelectedMethod, result.Decision.DecisionCode);
fprintf("[B0B A0-V3] report=%s\n", ...
    fullfile(outputDirectory, "a0_v3_decision.txt"));
end

function write_decision_report(path, beforePath, v3Path, afterPath, gates, comparison)
fid = fopen(path, "wt", "n", "UTF-8");
if fid < 0
    error("B0BMethod:Output", "Cannot write report: %s", path);
end
cleanup = onCleanup(@() fclose(fid));

residual = comparison.Contrasts( ...
    comparison.Contrasts.Metric == "ClosureNormalizedDeltaRMSDeg", :);
closure = comparison.Contrasts( ...
    comparison.Contrasts.Metric == "AbsCanonicalClosureErrorDeg", :);
nl = comparison.Contrasts( ...
    comparison.Contrasts.Metric == "NL_RobustP2P_Deg", :);
rms = comparison.Contrasts(comparison.Contrasts.Metric == "RMS_AC_Deg", :);

fprintf(fid, "B0-B A0 vs V3 measurement-method decision\n");
fprintf(fid, "========================================\n");
fprintf(fid, "A0 before: %s\nV3: %s\nA0 after: %s\n\n", ...
    beforePath, v3Path, afterPath);

fprintf(fid, "1. HARD DATA/PROTOCOL GATES\n");
for row = 1:height(gates)
    fprintf(fid, "  %-10s valid=%d/%d candidates=%d pass=%d\n", ...
        gates.Leg(row), gates.ValidRuns(row), gates.ExpectedRuns(row), ...
        gates.OfficialCandidates(row), gates.GatePass(row));
end
fprintf(fid, "\n");

fprintf(fid, "2. PRIMARY POST-TURN RESIDUAL (lower is better)\n");
print_contrast(fid, residual);
fprintf(fid, "  Locked gate: V3 < bracket - 2.77*pooledSD = %.8f deg\n", ...
    comparison.Decision.LockedResidualThresholdDeg);
fprintf(fid, "  Gate pass: %d\n", comparison.Decision.ResidualGatePass);
fprintf(fid, "  V3 worse, bootstrap 95%% excludes zero: %d\n\n", ...
    comparison.Decision.V3ResidualWorseWithConfidence);

fprintf(fid, "3. SECONDARY MEASUREMENT METRICS\n");
fprintf(fid, "  Absolute canonical closure:\n");
print_contrast(fid, closure);
fprintf(fid, "  NL robust P2P:\n");
print_contrast(fid, nl);
fprintf(fid, "  RMS_AC:\n");
print_contrast(fid, rms);
fprintf(fid, "\n");

fprintf(fid, "4. SAME-SECTOR DIAGNOSTIC\n");
fprintf(fid, "  time axis=%s (approximate, no shared cross-file wall clock)\n", ...
    comparison.Sector.TimingEvidence);
fprintf(fid, "  within +/-%g raw: %d/%d; max abs error=%.3f raw\n", ...
    comparison.Sector.ToleranceRaw, comparison.Sector.PassCount, ...
    comparison.Sector.RunCount, comparison.Sector.MaxAbsErrorRaw);
fprintf(fid, "  descriptive pass=%d; formal causal sector gate available=%d\n\n", ...
    comparison.Sector.DescriptiveGatePass, ...
    comparison.Decision.FormalCausalSectorGateAvailable);

fprintf(fid, "5. DECISION\n");
fprintf(fid, "  Selected method: %s\n", comparison.Decision.SelectedMethod);
fprintf(fid, "  Code: %s\n", comparison.Decision.DecisionCode);
fprintf(fid, "  %s\n", comparison.Decision.Rationale);
fprintf(fid, "  Interpretation: Test 28 can reject a V3 benefit and keep A0 as the\n");
fprintf(fid, "  production method. It cannot claim a fully timestamp-controlled causal\n");
fprintf(fid, "  proof because the three firmware legs do not share an absolute clock.\n");
end

function print_contrast(fid, row)
fprintf(fid, "    A0-before=%.8f  V3=%.8f  A0-after=%.8f\n", ...
    row.A0BeforeMean, row.V3Mean, row.A0AfterMean);
fprintf(fid, "    V3-bracket=%+.8f  pooledSD=%.8f  effect=%.3f SD / %.3f SE\n", ...
    row.V3MinusBracket, row.PooledSD, row.EffectInPooledSD, row.EffectInSE);
fprintf(fid, "    bootstrap95=[%+.8f, %+.8f]\n", ...
    row.Bootstrap95Low, row.Bootstrap95High);
fprintf(fid, "    paired-run-order sensitivity=%+.8f, bootstrap95=[%+.8f, %+.8f]\n", ...
    row.PairedRunOrderMean, row.PairedRunOrderBootstrap95Low, ...
    row.PairedRunOrderBootstrap95High);
end

function create_plots(runs, comparison, outputDirectory)
legOrder = ["A0_BEFORE", "V3", "A0_AFTER"];
colors = [0.20 0.45 0.75; 0.85 0.33 0.10; 0.30 0.65 0.35];

figureHandle = figure(Visible="off", Color="white", ...
    Position=[100 100 1200 800]);
cleanup = onCleanup(@() close(figureHandle));
tiledlayout(2, 2, TileSpacing="compact", Padding="compact");
plot_metric(nexttile, runs, legOrder, colors, ...
    "ClosureNormalizedDeltaRMSDeg", "Post-turn residual RMS (deg)");
plot_metric(nexttile, runs, legOrder, colors, ...
    "AbsCanonicalClosureErrorDeg", "|Canonical closure| (deg)");
plot_metric(nexttile, runs, legOrder, colors, ...
    "NL_RobustP2P_Deg", "NL robust P2P (deg)");
plot_metric(nexttile, runs, legOrder, colors, ...
    "RMS_AC_Deg", "RMS AC (deg)");
exportgraphics(figureHandle, fullfile(outputDirectory, ...
    "a0_v3_primary_metrics.png"), Resolution=160);

figureHandle2 = figure(Visible="off", Color="white", ...
    Position=[100 100 1200 520]);
cleanup2 = onCleanup(@() close(figureHandle2));
tiledlayout(1, 2, TileSpacing="compact", Padding="compact");
axisHandle = nexttile;
sector = comparison.Sector.PerRun;
plot(axisHandle, sector.RunOrder, sector.SectorErrorRaw, "o-", ...
    LineWidth=1.4, Color=colors(2,:));
yline(axisHandle, comparison.Sector.ToleranceRaw, "--k");
yline(axisHandle, -comparison.Sector.ToleranceRaw, "--k");
xlabel(axisHandle, "V3 run order");
ylabel(axisHandle, "Sector error (raw)");
title(axisHandle, "Same-sector check (approximate time axis)");
grid(axisHandle, "on");

axisHandle = nexttile;
hold(axisHandle, "on");
for legIndex = 1:3
    subset = runs(runs.Leg == legOrder(legIndex), :);
    scatter(axisHandle, subset.H2C, subset.H2S, 42, colors(legIndex,:), ...
        "filled", DisplayName=legOrder(legIndex));
end
axis(axisHandle, "equal");
xlabel(axisHandle, "H2 C");
ylabel(axisHandle, "H2 S");
title(axisHandle, "H2 setup-consistency vector");
legend(axisHandle, Location="best");
grid(axisHandle, "on");
exportgraphics(figureHandle2, fullfile(outputDirectory, ...
    "a0_v3_sector_h2.png"), Resolution=160);
end

function plot_metric(axisHandle, runs, legOrder, colors, metric, titleText)
hold(axisHandle, "on");
for legIndex = 1:3
    subset = sortrows(runs(runs.Leg == legOrder(legIndex), :), "RunOrder");
    x = (legIndex - 1) * 11 + subset.RunOrder;
    plot(axisHandle, x, subset.(metric), "o-", LineWidth=1.2, ...
        Color=colors(legIndex,:), DisplayName=legOrder(legIndex));
    ylineValue = mean(subset.(metric));
    plot(axisHandle, [min(x), max(x)], [ylineValue, ylineValue], "--", ...
        Color=colors(legIndex,:), HandleVisibility="off");
end
xlabel(axisHandle, "Cumulative run index");
ylabel(axisHandle, titleText);
title(axisHandle, titleText);
legend(axisHandle, Location="best");
grid(axisHandle, "on");
end

function records = append_struct(records, record)
if isempty(records)
    records = record;
else
    records(end + 1) = record;
end
end
