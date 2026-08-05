function test_nl_stability_analysis
%TEST_NL_STABILITY_ANALYSIS Lightweight regression without hardware log
%   dependency. analyze_nl_stability_batch.m was also validated against
%   real hardware data (B0-B p03 jig 1 test 21A/21B/21A2.txt, test 22.txt):
%   every per-sweep metric field matches tools/analyze_nl_stability.py's
%   nl_runs.csv/nl_stability.csv to floating-point epsilon (max abs diff
%   1.4e-15 across 10 sweeps x 8 fields). That is not re-run here since it
%   depends on large files outside this repo's tracked regression set.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, "nl"));

% A synthetic sweep with a pure, known 36th-order ripple plus a DC offset:
% error(i) = dc + amp*sin(2*pi*36*i/360). RobustP2P/RawP2P/RMS_AC/A36 must
% all recover known closed-form values.
n = 360;
dc = 0.05;
amp = 0.8;
index = (0:n - 1)';
errors = dc + amp * sin(2 * pi * 36 * index / n);

lines = strings(0, 1);
lines(end + 1) = strcat("META,SchemaVersion=5,TestID=1,SweepID=1,", ...
    "AnalysisPoints=360,MeasurementValid=1,RunOrder=1,RunRole=OFFICIAL,", ...
    "EligibleForStatistics=1");
% Positional DATA fields (1-indexed here): (1)DATA (2)_ (3)TestID (4)SweepID
% (5)_ (6)_ (7)_ (8)Index (9)TargetRaw (10)AngleRaw (11)AngleDeg-unused (12)ErrorDeg.
for i = 1:n
    lines(end + 1) = sprintf("DATA,,1,1,,,,%d,0,0,0,%.10f", index(i), errors(i)); %#ok<AGROW>
end
lines(end + 1) = "SHADOW_RESULT,P2P=1.6,ClosureErrorDeg=0.05,RMS_AC=0.5657,A36=0.8";
lines(end + 1) = "APPROACH_RESULT,ApproachReturnErrorRaw=-13";
lines(end + 1) = "END,Status=VALID";
lines(end + 1) = "Nonlinear 1 Angle: 1.6 degree";
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

result = analyze_nl_stability_batch(file, "SYNTH");
assert(height(result.Runs) == 1);
row = result.Runs(1,:);
assert(abs(row.MeanDC_Deg - dc) < 1e-9);
% A pure sinusoid's RMS about its own mean is amp/sqrt(2).
assert(abs(row.RMS_AC_Deg - amp/sqrt(2)) < 1e-6);
% 360 points / 36 cycles = 10 samples/cycle, i.e. 36 degrees apart -- the
% discrete grid never lands exactly on the true +/-90 degree peak (nearest
% samples are at 72/108 degrees), so both RawP2P and RobustP2P converge to
% 2*amp*sin(2*pi*2/10), not 2*amp. This is expected discrete-sampling
% behavior, not an error in the metric.
expectedP2P = 2 * amp * sin(2 * pi * 2 / 10);
assert(abs(row.RawP2P_Deg - expectedP2P) < 1e-6);
assert(abs(row.NL_RobustP2P_Deg - expectedP2P) < 1e-6);
% The signal IS the 36th harmonic, so A36 must recover the amplitude
% almost exactly.
assert(abs(row.A36_Deg - amp) < 1e-6);
assert(abs(row.ClosureErrorDeg - 0.05) < 1e-12);
assert(abs(row.ApproachReturnErrorDeg - (-13*360/65536)) < 1e-12);

stability = compute_nl_stability_stats([1.0; 1.0; 1.0]);
assert(stability.SampleSd == 0);
assert(isnan(stability.CvPct) == false); % 0/1*100 = 0, not NaN, since mean~=0
assert(abs(stability.RepeatabilityLimit2_77Sd - 0) < 1e-12);

test_nl_factors();
test_jig_delta();
test_sector_response();
test_sector_match_gate();
test_sector_calibration_parsing();
test_nl_extreme_angles();
test_rank_motor_nl_quality();
test_harmonic_spectrum();
test_deadtime_harmonic_signature();
test_full_curve_quality();
test_cross_jig_point_delta();
test_find_outlier_mount_sessions();
test_session_feature_table();
test_compare_features_across_jigs();
test_mount_precheck();
test_peak_signature_tools();
test_sweep_creep_analysis();

fprintf("[ OK ] NL stability MATLAB analysis regression test passed.\n");
end

function test_nl_factors()
% Two synthetic groups. Within each group, NL is built as a known linear
% function of A36 (slope 2, matching r=1 exactly by construction) plus
% independent noise on a decoy factor (MeanDC) that must NOT correlate.
% RunOrder carries a group-specific linear drift that detrending must
% remove (checked by RunOrder's own detrended correlation collapsing to
% ~0, same sanity check as the real-data run showing 0.0009).
groupSize = 12;
index = (0:groupSize - 1)';
files = strings(1, 2);
labels = ["G1", "G2"];
for groupIndex = 1:2
    % Sawtooth-in-RunOrder, NOT a linear function of it -- if this were
    % linear in RunOrder, within-group linear detrending would (correctly)
    % remove nearly all of its variance before correlation, which is a
    % property of the analysis (RunOrder/warm-up trends must not be
    % mistaken for a real factor), not something this test should fight.
    a36 = 0.5 + 0.3 * mod(index, 4) / 3 + 0.01 * groupIndex;
    decoy = mod(index * 7, 5); % deliberately uncorrelated with the errors' shape

    lines = strings(0, 1);
    for k = 1:groupSize
        lines(end + 1) = sprintf(strcat("META,SchemaVersion=5,TestID=%d,SweepID=%d,", ...
            "RunOrder=%d,RunRole=OFFICIAL,EligibleForStatistics=1,MeasurementValid=1,", ...
            "AnalysisPoints=360,AnalysisStartRaw=1000,ApproachProtocol=SYNTH"), ...
            groupIndex, k, k); %#ok<AGROW>
        n = 360;
        errors = zeros(1, n);
        % Build a pure-36th-harmonic curve with the target amplitude a36(k)
        % and a DC offset chosen so MeanDC is a decoy unrelated to nl.
        theta = 2 * pi * 36 * (0:n - 1) / n;
        errors = decoy(k) + a36(k) * sin(theta);
        % RMS_AC of a pure sinusoid is amplitude/sqrt(2); NL_RobustP2P of a
        % clean 10-samples/cycle sinusoid is a fixed fraction of 2*amplitude
        % (see test_nl_stability_analysis's own discrete-sampling note) --
        % neither is independently steered to equal nl(k) exactly, so this
        % case checks the STRUCTURE (a real factor recovered, a decoy
        % rejected, RunOrder trend removed), not an exact target value.
        for dataIndex = 0:n - 1
            lines(end + 1) = sprintf("DATA,,%d,%d,,,,%d,0,0,0,%.10f", ...
                groupIndex, k, dataIndex, errors(dataIndex + 1)); %#ok<AGROW>
        end
        lines(end + 1) = sprintf("SHADOW_RESULT,ClosureErrorDeg=%.6f", 0.01 * k); %#ok<AGROW>
        lines(end + 1) = "END,Status=VALID"; %#ok<AGROW>
    end
    files(groupIndex) = write_temp_log(lines);
end
cleanup = onCleanup(@() cellfun(@delete_if_exists, cellstr(files))); %#ok<NASGU>

result = analyze_nl_factors(files, labels);
assert(height(result.GroupSummary) == 2);
assert(height(result.Runs) == 24);

a36Row = result.FactorCorrelations(result.FactorCorrelations.Factor == "A36_Deg", :);
% A36 truly drives the synthetic errors' shape; detrended correlation with
% NL_RobustP2P must be strong, positive, and consistent across both groups.
assert(a36Row.RDetrended > 0.9);
assert(a36Row.GroupsSameSign == 2);

runOrderRow = result.FactorCorrelations(result.FactorCorrelations.Factor == "RunOrder", :);
% Within-group linear detrending against RunOrder must remove RunOrder's
% own detrended correlation with itself down to ~0 (by construction).
assert(abs(runOrderRow.RDetrended) < 1e-9);
end

function test_jig_delta()
% Three synthetic products. Each product gets one JIG4 sweep and one JIG5
% sweep with a KNOWN AnalysisStartRaw (sector) difference and a pure-36th-
% harmonic error curve whose amplitude is a known linear function of that
% sector difference -- by construction, |sector delta| vs |A36 delta| must
% correlate almost perfectly (r > 0.99) across the 3 products, and the
% Summary table's own computed deltas must match the hand-calculated
% values exactly (catches wiring bugs in the aggregation/labeling, not
% just the underlying formula, which analyze_nl_factors's tests already
% cover).
cycle = 10923.0;
products = ["P1", "P2", "P3"];
jig4Sector = [1000, 2000, 3000];
sectorDeltaRaw = [300, 600, 900]; % JIG5 - JIG4, well inside the cycle, no wrap needed
jig5Sector = jig4Sector + sectorDeltaRaw;
baseA36 = 0.5;
slopeDegToAmp = 0.01;

jig4Files = strings(1, 3);
jig5Files = strings(1, 3);
expectedA36Delta = NaN(1, 3);
for index = 1:3
    sectorDeltaDeg = sectorDeltaRaw(index) * 360.0 / cycle;
    a36Jig5 = baseA36 + slopeDegToAmp * sectorDeltaDeg;
    expectedA36Delta(index) = a36Jig5 - baseA36;
    jig4Files(index) = write_synthetic_sweep(jig4Sector(index), baseA36);
    jig5Files(index) = write_synthetic_sweep(jig5Sector(index), a36Jig5);
end
cleanup = onCleanup(@() cellfun(@delete_if_exists, cellstr([jig4Files, jig5Files]))); %#ok<NASGU>

result = analyze_jig_delta(jig4Files, jig5Files, products);
assert(height(result.Summary) == 3);

for index = 1:3
    assert(abs(result.Summary.SectorDeltaRaw(index) - sectorDeltaRaw(index)) < 1e-9);
    assert(abs(result.Summary.A36_Deg_Delta(index) - expectedA36Delta(index)) < 1e-6);
end

a36Row = result.SectorCorrelation(result.SectorCorrelation.Metric == "A36_Deg", :);
assert(a36Row.R > 0.99);

% Wrap-around case: a raw difference just past the cycle boundary must
% fold back to a small delta, not report a near-full-cycle jump.
wrapFile4 = write_synthetic_sweep(200, baseA36);
wrapFile5 = write_synthetic_sweep(mod(200 - 150, cycle), baseA36); % true delta -150, encoded via wraparound
cleanup2 = onCleanup(@() cellfun(@delete_if_exists, {wrapFile4, wrapFile5})); %#ok<NASGU>
wrapResult = analyze_jig_delta(wrapFile4, wrapFile5, "PWRAP");
assert(abs(wrapResult.Summary.SectorDeltaRaw(1) - (-150)) < 1e-9);
end

function file = write_synthetic_sweep(analysisStartRaw, a36Amplitude)
n = 360;
theta = 2 * pi * 36 * (0:n - 1) / n;
errors = a36Amplitude * sin(theta);
lines = strings(0, 1);
lines(end + 1) = sprintf(strcat("META,SchemaVersion=5,TestID=1,SweepID=1,RunRole=OFFICIAL,", ...
    "EligibleForStatistics=1,MeasurementValid=1,AnalysisPoints=360,", ...
    "AnalysisStartRaw=%d,ApproachProtocol=SYNTH"), analysisStartRaw);
for dataIndex = 0:n - 1
    lines(end + 1) = sprintf("DATA,,1,1,,,,%d,0,0,0,%.10f", dataIndex, errors(dataIndex + 1)); %#ok<AGROW>
end
lines(end + 1) = "SHADOW_RESULT,ClosureErrorDeg=0.05";
lines(end + 1) = "END,Status=VALID";
file = write_temp_log(lines);
end

function test_sector_response()
% Three products, three sessions each, MeanDC_Deg built EXACTLY as
% productBaseline + trueA*cos(theta) + trueB*sin(theta) (no noise) so the
% within-product-centered harmonic fit must recover trueA/trueB and
% R^2=1 to tight tolerance -- MeanDC_Deg is used because it is the one
% metric a constant-error sweep controls exactly (mean of a constant
% array), unlike NL_RobustP2P_Deg which needs real curve shape.
cycle = 10923.0;
trueA = 0.05;
trueB = -0.03;
baseline = struct("Q1", 1.0, "Q2", 2.0, "Q3", 3.0);
sectors = [0, cycle / 3, 2 * cycle / 3];
products = ["Q1", "Q2", "Q3"];

files = strings(1, 9);
productList = strings(1, 9);
idx = 0;
for p = 1:3
    for s = 1:3
        idx = idx + 1;
        sector = sectors(s);
        theta = 2 * pi * sector / cycle;
        value = baseline.(products(p)) + trueA * cos(theta) + trueB * sin(theta);
        files(idx) = write_constant_sweep(sector, value);
        productList(idx) = products(p);
    end
end
cleanup = onCleanup(@() cellfun(@delete_if_exists, cellstr(files))); %#ok<NASGU>

fit = fit_sector_response(files, productList, "MeanDC_Deg", cycle);
assert(fit.N == 9);
assert(abs(fit.RSquared - 1) < 1e-9);
assert(abs(fit.Coeffs(1) - trueA) < 1e-9);
assert(abs(fit.Coeffs(2) - trueB) < 1e-9);

% correct_delta_for_sector: a delta built as PURELY the sector-driven
% component (same product, two sectors) must residualize to ~0; adding a
% known extra on top must survive into ResidualDelta unchanged.
sectorX = 1500;
sectorY = 6000;
pureHarmonicDelta = fit.PredictFn(sectorY) - fit.PredictFn(sectorX);
result1 = correct_delta_for_sector(pureHarmonicDelta, sectorX, sectorY, fit);
assert(abs(result1.ResidualDelta) < 1e-9);

extra = 0.4;
result2 = correct_delta_for_sector(pureHarmonicDelta + extra, sectorX, sectorY, fit);
assert(abs(result2.ResidualDelta - extra) < 1e-9);
end

function file = write_constant_sweep(analysisStartRaw, constantValue)
n = 360;
lines = strings(0, 1);
lines(end + 1) = sprintf(strcat("META,SchemaVersion=5,TestID=1,SweepID=1,RunRole=OFFICIAL,", ...
    "EligibleForStatistics=1,MeasurementValid=1,AnalysisPoints=360,", ...
    "AnalysisStartRaw=%.10f,ApproachProtocol=SYNTH"), analysisStartRaw);
for dataIndex = 0:n - 1
    lines(end + 1) = sprintf("DATA,,1,1,,,,%d,0,0,0,%.10f", dataIndex, constantValue); %#ok<AGROW>
end
lines(end + 1) = "SHADOW_RESULT,ClosureErrorDeg=0.0";
lines(end + 1) = "END,Status=VALID";
file = write_temp_log(lines);
end

function test_sector_match_gate()
% Within tolerance, no wrap.
gate1 = sector_match_gate(1000, 1150, 200);
assert(abs(gate1.SectorDeltaRaw - 150) < 1e-9);
assert(gate1.SectorMatched == true);

% Outside tolerance, no wrap.
gate2 = sector_match_gate(1000, 1500, 200);
assert(abs(gate2.SectorDeltaRaw - 500) < 1e-9);
assert(gate2.SectorMatched == false);

% Wrap-around: raw difference near a full cycle must fold to a small
% signed delta, same discipline as analyze_jig_delta.m's own wrap test.
cycle = 10923.0;
gate3 = sector_match_gate(100, mod(100 - 80, cycle), 200);
assert(abs(gate3.SectorDeltaRaw - (-80)) < 1e-9);
assert(gate3.SectorMatched == true);
end

function test_sector_calibration_parsing()
% 3 synthetic batches: commanded targets [0, 1365, 2731], each achieved
% with a small, known pre-position error ([+5, -5, +9] raw) and 2 sweeps
% per batch (both sweeps land at the same achieved sector, since the
% pre-position happens once per batch, before both sweeps in it).
commandedTargets = [0, 1365, 2731];
achievedErrors = [5, -5, 9];
lines = strings(0, 1);
for batchIndex = 1:3
    lines(end + 1) = sprintf("SECTOR_CALIBRATION,BatchID=%d,TargetIndex=%d,TargetRaw=%d", ...
        batchIndex, batchIndex - 1, commandedTargets(batchIndex)); %#ok<AGROW>
    achievedSector = commandedTargets(batchIndex) + achievedErrors(batchIndex);
    for sweepIndex = 1:2
        lines(end + 1) = sprintf(strcat("META,SchemaVersion=5,TestID=%d,SweepID=%d,BatchID=%d,", ...
            "RunRole=OFFICIAL,EligibleForStatistics=1,MeasurementValid=1,AnalysisPoints=360,", ...
            "AnalysisStartRaw=%d,ApproachProtocol=SYNTH"), ...
            batchIndex, sweepIndex, batchIndex, achievedSector); %#ok<AGROW>
        for dataIndex = 0:359
            lines(end + 1) = sprintf("DATA,,%d,%d,,,,%d,0,0,0,0.0", ...
                batchIndex, sweepIndex, dataIndex); %#ok<AGROW>
        end
        lines(end + 1) = "SHADOW_RESULT,ClosureErrorDeg=0.0"; %#ok<AGROW>
        lines(end + 1) = "END,Status=VALID"; %#ok<AGROW>
    end
end
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

result = parse_sector_calibration_log(file);
assert(height(result.Commanded) == 3);
assert(height(result.Comparison) == 3);
for batchIndex = 1:3
    row = result.Comparison(result.Comparison.BatchID == batchIndex, :);
    assert(abs(row.CommandedTargetRaw - commandedTargets(batchIndex)) < 1e-9);
    assert(abs(row.AchievedSectorRawMean - (commandedTargets(batchIndex) + achievedErrors(batchIndex))) < 1e-9);
    assert(abs(row.ErrorRaw - achievedErrors(batchIndex)) < 1e-9);
    assert(row.SweepCount == 2);
end
end

function test_nl_extreme_angles()
% Two groups (motor M1, jig JA/JB), 2 identical runs each, n=8, k=3.
% Group B's mean curve is EXACTLY group A's curve rotated by 2 points, so
% every quantity is hand-computable: best shift must recover exactly 2,
% best correlation exactly 1, post-alignment tail distances exactly 0,
% and (since B is a pure rotation of A, not an amplitude change) every
% top5/bottom5/robust-NL delta must be exactly 0.
curveA = [5, 1, 2, 3, -5, -1, -2, -3];
n = numel(curveA);
curveB = zeros(1, n);
for j = 0:n - 1
    curveB(j + 1) = curveA(mod(j - 2, n) + 1);
end

fileA = write_extreme_angle_log(curveA, "M1", "JA");
fileB = write_extreme_angle_log(curveB, "M1", "JB");
cleanup = onCleanup(@() cellfun(@delete_if_exists, {fileA, fileB})); %#ok<NASGU>

fileGroups = struct("Files", {fileA, fileB}, "MotorId", {"M1", "M1"}, "JigId", {"JA", "JB"});
[groups, pairs] = analyze_nl_extreme_angles(fileGroups, 3);

assert(numel(groups) == 2);
assert(numel(pairs) == 1);
p = pairs(1);

assert(p.BestShiftPoints == 2);
assert(abs(p.BestShiftCorrelation - 1) < 1e-9);
assert(abs(p.Top5MeanDistanceAlignedDeg) < 1e-9);
assert(abs(p.Bottom5MeanDistanceAlignedDeg) < 1e-9);
assert(abs(p.Top5MaxDistanceAlignedDeg) < 1e-9);
assert(abs(p.Bottom5MaxDistanceAlignedDeg) < 1e-9);
assert(abs(p.Top5DeltaBMinusADeg) < 1e-9);
assert(abs(p.Bottom5DeltaBMinusADeg) < 1e-9);
assert(abs(p.RobustNLDeltaBMinusADeg) < 1e-9);

expectedRobust = mean([5, 3, 2]) - mean([-5, -3, -2]);
assert(abs(p.RobustNLADeg - expectedRobust) < 1e-9);
assert(abs(p.RobustNLBDeg - expectedRobust) < 1e-9);

% Zero-shift correlation must be strictly worse than the best-shift one --
% curveA and curveB are NOT aligned at shift 0 by construction.
assert(p.ZeroShiftCorrelation < p.BestShiftCorrelation - 1e-6);
end

function file = write_extreme_angle_log(curve, motorId, jigId) %#ok<INUSD>
n = numel(curve);
lines = strings(0, 1);
for runIndex = 1:2
    lines(end + 1) = sprintf(strcat("META,SchemaVersion=5,TestID=%d,SweepID=%d,", ...
        "RunRole=OFFICIAL,EligibleForStatistics=1,MeasurementValid=1,AnalysisPoints=%d,", ...
        "AnalysisStartRaw=0,ApproachProtocol=SYNTH"), ...
        runIndex, runIndex, n); %#ok<AGROW>
    for dataIndex = 0:n - 1
        lines(end + 1) = sprintf("DATA,,%d,%d,,,,%d,0,0,0,%.10f", ...
            runIndex, runIndex, dataIndex, curve(dataIndex + 1)); %#ok<AGROW>
    end
    lines(end + 1) = "SHADOW_RESULT,ClosureErrorDeg=0.0"; %#ok<AGROW>
    lines(end + 1) = "END,Status=VALID"; %#ok<AGROW>
end
file = write_temp_log(lines);
end

function test_rank_motor_nl_quality()
% Three motors, single jig "JX" each, n=360, 3 runs/motor. M1: small pure
% 36th-harmonic amplitude (low NL, low A36) -- "good". M2: large pure
% 36th-harmonic amplitude (high NL, high A36) -- consistently bad on both
% metrics. M3: the SAME small amplitude as M1 (so A36 must match M1)
% plus a single-point spike added at one index -- a single point can
% dominate a top-5-of-360 mean, inflating NL_RobustP2P, while barely
% moving the 36th-order DFT amplitude. This is the textbook "NL rank
% distorted, A36 rank not" case the RankShift warning exists to catch.
n = 360;
index = (0:n - 1)';
theta = 2 * pi * 36 * index / n;

files = strings(1, 3);
amps = [0.3, 1.0, 0.3];
% Index 7 (angle 252 deg) puts the spike's DFT contribution roughly
% opposite the base sine's own phase, so it slightly REDUCES M3's
% resultant A36 amplitude below M1's (0.2737 vs 0.3) while still
% dominating M3's top-5/bottom-5 mean (NL_RobustP2P only depends on error
% VALUES, not their DFT phase, so the spike inflates NL regardless of
% which index it sits at) -- this is what makes M3 rank BETTER than M1 on
% A36 but WORSE on NL, the exact case the RankShift warning targets.
spikeAt = [-1, -1, 7]; % 0-based DATA index to spike, -1 = none
for m = 1:3
    lines = strings(0, 1);
    for run = 1:3
        errors = amps(m) * sin(theta);
        if spikeAt(m) >= 0
            errors(spikeAt(m) + 1) = errors(spikeAt(m) + 1) + 5.0;
        end
        lines(end + 1) = sprintf(strcat("META,SchemaVersion=5,TestID=%d,SweepID=%d,", ...
            "RunRole=OFFICIAL,EligibleForStatistics=1,MeasurementValid=1,AnalysisPoints=360,", ...
            "AnalysisStartRaw=0,ApproachProtocol=SYNTH"), run, run); %#ok<AGROW>
        for dataIndex = 0:n - 1
            lines(end + 1) = sprintf("DATA,,%d,%d,,,,%d,0,0,0,%.10f", ...
                run, run, dataIndex, errors(dataIndex + 1)); %#ok<AGROW>
        end
        lines(end + 1) = "SHADOW_RESULT,ClosureErrorDeg=0.0"; %#ok<AGROW>
        lines(end + 1) = "END,Status=VALID"; %#ok<AGROW>
    end
    files(m) = write_temp_log(lines);
end
cleanup = onCleanup(@() cellfun(@delete_if_exists, cellstr(files))); %#ok<NASGU>

fileGroups = struct("Files", {files(1), files(2), files(3)}, ...
    "MotorId", {"M1", "M2", "M3"}, "JigId", {"JX", "JX", "JX"});
result = rank_motor_nl_quality(fileGroups);
lb = result.Leaderboard;

m1 = lb(lb.Motor == "M1", :);
m2 = lb(lb.Motor == "M2", :);
m3 = lb(lb.Motor == "M3", :);

assert(m1.NL_Rank == 1);          % smallest amplitude, no spike -- clearly best
assert(m2.NL_Rank == 3);          % largest amplitude -- clearly worst on NL
assert(m2.A36_Rank == 3);         % ...and on A36 too (consistently bad)
assert(m3.NL_Mean_Deg > m1.NL_Mean_Deg);
assert(abs(m3.A36_Mean_Deg - m1.A36_Mean_Deg) < 0.05); % spike barely moves A36
assert(m3.NL_Rank > m1.NL_Rank);
% The rank-shift flag must catch M3: A36 rank much better than its NL rank.
assert(m3.RankShift_A36MinusNL <= -1);
end

function test_harmonic_spectrum()
% Pure sinusoid at order 36, amplitude 0.8, plus a DC offset -- must
% recover 0.8 at order 36 (cross-checked against compute_nl_sweep_metrics'
% own A36 formula, same input) and near-zero at unrelated orders (1, 12).
n = 360;
index = (0:n - 1)';
amp = 0.8;
errors = 0.05 + amp * sin(2 * pi * 36 * index / n);

spectrum = compute_harmonic_spectrum(errors, [1, 12, 36]);
assert(abs(spectrum(3) - amp) < 1e-6);   % order 36: recovers the amplitude
assert(spectrum(1) < 1e-6);              % order 1: no such component
assert(spectrum(2) < 1e-6);              % order 12: no such component
end

function test_deadtime_harmonic_signature()
% One motor "MX", two jigs. JigA's mean curve is a pure order-12 sine
% (EVEN multiple of the 6-pole-pair electrical fundamental, amplitude
% 0.5) -- the "motor signature" class this project has already found
% jig-invariant. JigB's curve is JigA's PLUS a pure order-18 sine (ODD
% multiple, amplitude 0.4) -- the dead-time-predicted class. By
% construction the cross-jig delta must be exactly 0.4 at order 18 and
% exactly 0 at order 12, and the pooled ODD-class mean must exceed the
% EVEN-class mean.
n = 360;
index = (0:n - 1)';
curveA = 0.5 * sin(2 * pi * 12 * index / n);
curveB = curveA + 0.4 * sin(2 * pi * 18 * index / n);

fileA = write_extreme_angle_log(curveA', "MX", "JA");
fileB = write_extreme_angle_log(curveB', "MX", "JB");
cleanup = onCleanup(@() cellfun(@delete_if_exists, {fileA, fileB})); %#ok<NASGU>

fileGroups = struct("Files", {fileA, fileB}, "MotorId", {"MX", "MX"}, "JigId", {"JA", "JB"});
result = analyze_deadtime_harmonic_signature(fileGroups, 3); % multiples 1,2,3 -> orders 6,12,18

d = result.Detail;
row12 = d(d.Order == 12, :);
row18 = d(d.Order == 18, :);
assert(abs(row12.AbsDelta_Deg) < 1e-6);          % even multiple: no delta by construction
assert(abs(row18.AbsDelta_Deg - 0.4) < 1e-6);    % odd multiple: exactly the added amplitude

oddMean = result.ByParity.mean_AbsDelta_Deg(result.ByParity.Parity == "ODD");
evenMean = result.ByParity.mean_AbsDelta_Deg(result.ByParity.Parity == "EVEN");
assert(oddMean > evenMean);
end

function test_full_curve_quality()
% Three motors, single jig "JX" each, n=360, 2 identical runs/motor
% (fully deterministic, SD=0 everywhere). MG: flat curve, no bad points --
% FractionWithinTolerance must be exactly 1, zero regions. MB: a clean
% 20-point contiguous bad region (0-based indices 100..119, value +2.0)
% against a tolerance of 0.5 -- must recover exactly 1 region, length 20
% deg, start 100 deg. MW: the SAME 20-point bad region but split across
% the 360/0 wrap boundary (0-based indices 350..359 and 0..9) -- must
% still be detected as ONE region (proves the circular wrap logic works
% end-to-end), not two.
n = 360;
tol = 0.5;

curveMG = zeros(1, n);

curveMB = zeros(1, n);
curveMB(101:120) = 2.0; % 0-based indices 100..119 -> MATLAB 101:120

curveMW = zeros(1, n);
curveMW([351:360, 1:10]) = 1.5; % 0-based indices 350..359, 0..9 (wraps)

files = strings(1, 3);
labels = ["MG", "MB", "MW"];
curves = {curveMG, curveMB, curveMW};
for m = 1:3
    files(m) = write_extreme_angle_log(curves{m}, labels(m), "JX");
end
cleanup = onCleanup(@() cellfun(@delete_if_exists, cellstr(files))); %#ok<NASGU>

fileGroups = struct("Files", {files(1), files(2), files(3)}, ...
    "MotorId", {"MG", "MB", "MW"}, "JigId", {"JX", "JX", "JX"});
result = analyze_full_curve_quality(fileGroups, tol);
lb = result.Leaderboard;

mg = lb(lb.Motor == "MG", :);
mb = lb(lb.Motor == "MB", :);
mw = lb(lb.Motor == "MW", :);

assert(abs(mg.FractionWithinTolerance - 1) < 1e-9);
assert(mg.OutOfToleranceRegionCount == 0);

assert(abs(mb.FractionWithinTolerance - (340 / 360)) < 1e-9);
assert(mb.OutOfToleranceRegionCount == 1);
assert(abs(mb.WorstRegionLengthDeg - 20) < 1e-9);
assert(abs(mb.WorstRegionStartDeg - 100) < 1e-9);
expectedPeakMB = 2.0 - 20 * 2.0 / n; % raw spike value minus the curve's own mean (centering)
assert(abs(mb.WorstRegionPeakDeg - expectedPeakMB) < 1e-6);

assert(abs(mw.FractionWithinTolerance - (340 / 360)) < 1e-9);
assert(mw.OutOfToleranceRegionCount == 1); % must NOT be split at the 360/0 boundary
assert(abs(mw.WorstRegionLengthDeg - 20) < 1e-9);
end

function test_cross_jig_point_delta()
% One motor "MX", two jigs "JA"/"JB", n=360. JigA's curve is flat zero;
% JigB's curve is flat zero EXCEPT a clean 15-point contiguous region
% (0-based indices 200..214, value +2.0) -- every quantity is hand-
% computable since curveA contributes nothing to the delta.
n = 360;
curveA = zeros(1, n);
curveB = zeros(1, n);
curveB(201:215) = 2.0; % 0-based 200..214 -> MATLAB 201:215

fileA = write_extreme_angle_log(curveA, "MX", "JA");
fileB = write_extreme_angle_log(curveB, "MX", "JB");
cleanup = onCleanup(@() cellfun(@delete_if_exists, {fileA, fileB})); %#ok<NASGU>

fileGroups = struct("Files", {fileA, fileB}, "MotorId", {"MX", "MX"}, "JigId", {"JA", "JB"});
result = analyze_cross_jig_point_delta(fileGroups, 0.3, "zero");

s = result.Summary;
assert(height(s) == 1);
assert(abs(s.MeanAbsDeltaDeg - (15 * 2.0 / n)) < 1e-9);
assert(abs(s.RmsDeltaDeg - sqrt(15 * 2.0^2 / n)) < 1e-9);
assert(abs(s.MaxDeltaDeg - 2.0) < 1e-9);
assert(abs(s.MaxDeltaAtDeg - 200) < 1e-9);
assert(s.RegionCount == 1);
assert(abs(s.WorstRegionLengthDeg - 15) < 1e-9);
assert(abs(s.WorstRegionStartDeg - 200) < 1e-9);

% useShift="best": jig B's curve is a pure rotation of jig A's own curve
% (not flat-zero-plus-spike this time) -- after best-fit alignment the
% delta must collapse to ~0 everywhere, proving the shift is actually
% applied before differencing, not just reported.
curveC = 0.5 * sin(2 * pi * 36 * (0:n - 1) / n);
curveD = zeros(1, n);
for j = 0:n - 1
    curveD(j + 1) = curveC(mod(j - 5, n) + 1);
end
fileC = write_extreme_angle_log(curveC, "MY", "JA");
fileD = write_extreme_angle_log(curveD, "MY", "JB");
cleanup2 = onCleanup(@() cellfun(@delete_if_exists, {fileC, fileD})); %#ok<NASGU>
fileGroups2 = struct("Files", {fileC, fileD}, "MotorId", {"MY", "MY"}, "JigId", {"JA", "JB"});
resultShifted = analyze_cross_jig_point_delta(fileGroups2, 0.01, "best");
s2 = resultShifted.Summary;
assert(abs(s2.ShiftUsedDeg - 5) < 1e-6);
assert(s2.RmsDeltaDeg < 1e-6);
assert(s2.RegionCount == 0);
end

function test_find_outlier_mount_sessions()
% One motor "MX", 4 sessions. S1,S2,S3 are all the SAME pure order-2 sine
% (0.5 amplitude, a mounting-eccentricity-like low-order component, NOT
% order 36 -- a pure order-36 curve is invariant under any 10-degree-
% multiple rotation since 360/36=10, which would make a 40-degree shift
% test degenerate) -- the "majority" orientation. S4 is that SAME curve
% rotated by 40 mechanical degrees -- the "R4 pattern" found by hand in
% the real p06 remount investigation: everyone else agrees at 0-degree
% shift, S4 alone needs +40.
n = 360;
index = 0:n - 1;
baseCurve = 0.5 * sin(2 * pi * 2 * index / n);
rotatedCurve = zeros(1, n);
for j = 0:n - 1
    rotatedCurve(j + 1) = baseCurve(mod(j - 40, n) + 1);
end

files = strings(1, 4);
labels = ["S1", "S2", "S3", "S4"];
curves = {baseCurve, baseCurve, baseCurve, rotatedCurve};
for k = 1:4
    files(k) = write_extreme_angle_log(curves{k}, "MX", labels(k));
end
cleanup = onCleanup(@() cellfun(@delete_if_exists, cellstr(files))); %#ok<NASGU>

fileGroups = struct("Files", {files(1), files(2), files(3), files(4)}, ...
    "MotorId", {"MX", "MX", "MX", "MX"}, "JigId", {"S1", "S2", "S3", "S4"});
result = find_outlier_mount_sessions(fileGroups, 15);

s = result.Summary;
s1 = s(s.Session == "S1", :);
s2 = s(s.Session == "S2", :);
s3 = s(s.Session == "S3", :);
s4 = s(s.Session == "S4", :);

assert(s1.AlignmentCount == 2); % aligned with S2,S3 (not S4)
assert(s2.AlignmentCount == 2);
assert(s3.AlignmentCount == 2);
assert(s4.AlignmentCount == 0); % aligned with none

assert(s4.IsOutlier == true);
assert(s1.IsOutlier == false);
assert(s2.IsOutlier == false);
assert(s3.IsOutlier == false);

assert(abs(abs(s4.ShiftFromMajorityDeg) - 40) < 1e-6);
end

function test_session_feature_table()
% One motor/jig, one OFFICIAL sweep, with CONTROL_STATE/MOTION_RESULT/
% CLOSURE_PROBE_RESULT lines added -- confirms build_session_feature_table
% flattens across all of them (not just the tags parse_nl_log already
% served to other tools), prefixes correctly, drops non-numeric fields
% (HomeResult=OK), and still recomputes NL_RobustP2P_Deg/A36 alongside.
file = write_feature_log("M1", "JA", 1, 1, 0.25, 3, 4);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

features = build_session_feature_table(file, "M1", "JA");
assert(height(features) == 1);
assert(features.MotorId(1) == "M1");
assert(features.JigId(1) == "JA");
assert(abs(features.CTRL_HomeFinalErrorDeg(1) - 0.25) < 1e-9);
assert(features.MOTION_SettleRetries(1) == 3);
assert(features.CLOSUREPROBE_ValidStages(1) == 4);
assert(abs(features.SHADOW_ClosureErrorDeg(1) - 0) < 1e-9);
assert(~ismember("CTRL_HomeResult", string(features.Properties.VariableNames)));
assert(~isnan(features.NL_RobustP2P_Deg(1)));
end

function test_compare_features_across_jigs()
% Two motors, two jigs each. CTRL_HomeFinalErrorDeg shifts by a
% consistent ~+0.3 from JA to JB for BOTH motors (a genuine jig effect);
% MOTION_SettleRetries shifts by +3 for M1 but -3 for M2 (motor-specific
% noise, no consistent jig effect). The ranked-first feature must be the
% consistent one, with a much higher ConsistencyScore and AllSameSign.
f1 = write_feature_log("M1", "JA", 1, 1, 0.10, 2, 4);
f2 = write_feature_log("M1", "JB", 1, 1, 0.40, 5, 4);
f3 = write_feature_log("M2", "JA", 1, 1, 0.12, 5, 4);
f4 = write_feature_log("M2", "JB", 1, 1, 0.44, 2, 4);
cleanup = onCleanup(@() cellfun(@delete_if_exists, {f1, f2, f3, f4})); %#ok<NASGU>

fileGroups = struct("Files", {f1, f2, f3, f4}, ...
    "MotorId", {"M1", "M1", "M2", "M2"}, "JigId", {"JA", "JB", "JA", "JB"});
result = compare_features_across_jigs(fileGroups, "JA", "JB");

assert(result.Ranking.Feature(1) == "CTRL_HomeFinalErrorDeg");
assert(result.Ranking.AllSameSign(1) == true);
assert(result.Ranking.ConsistencyScore(1) > 10);

noisyIdx = find(result.Ranking.Feature == "MOTION_SettleRetries");
assert(~isempty(noisyIdx));
assert(result.Ranking.AllSameSign(noisyIdx) == false);
assert(result.Ranking.ConsistencyScore(noisyIdx) < 1);
assert(result.Ranking.ConsistencyScore(1) > result.Ranking.ConsistencyScore(noisyIdx));
end

function file = write_feature_log(motorId, jigId, testId, sweepId, homeFinalErrorDeg, settleRetries, validStages)
n = 8;
curve = [1, 2, 3, 4, -4, -3, -2, -1];
lines = strings(0, 1);
lines(end + 1) = sprintf(strcat("META,SchemaVersion=5,TestID=%d,SweepID=%d,RunRole=OFFICIAL,", ...
    "EligibleForStatistics=1,MeasurementValid=1,AnalysisPoints=%d,JigID=%s,MotorID=%s"), ...
    testId, sweepId, n, jigId, motorId);
for i = 0:n - 1
    lines(end + 1) = sprintf("DATA,,%d,%d,,,,%d,0,0,0,%.10f", testId, sweepId, i, curve(i + 1)); %#ok<AGROW>
end
lines(end + 1) = "SHADOW_RESULT,ClosureErrorDeg=0.0";
lines(end + 1) = sprintf("CONTROL_STATE,TestID=%d,SweepID=%d,HomeFinalErrorDeg=%.6f,HomeResult=OK", ...
    testId, sweepId, homeFinalErrorDeg);
lines(end + 1) = sprintf("MOTION_RESULT,TestID=%d,SweepID=%d,SettleRetries=%d", ...
    testId, sweepId, settleRetries);
lines(end + 1) = sprintf("CLOSURE_PROBE_RESULT,TestID=%d,SweepID=%d,ValidStages=%d", ...
    testId, sweepId, validStages);
lines(end + 1) = "END,Status=VALID";
file = write_temp_log(lines);
end

function test_mount_precheck()
% Two synthetic groups mimicking the firmware comment's own description
% (Core/Src/nonlinear_test.c, MOUNT_PRECHECK_V1 M0): "GOOD" mounts have a
% larger H1 (concentricity) amplitude and small H2; "BAD" mounts have H1
% shrunk and H2 grown, per "H1 shrinks and sometimes H2 grows under bad
% mounting". One BAD record is also MountValid=0/CLOSURE_INVALID, to
% check RejectReason pooling. Two files per group so file-level pooling
% (not just record-level) is exercised.
h1Good = [0.40, 0.42];
h2Good = [0.05, 0.06];
h1Bad = [0.05, 0.06];
h2Bad = [0.30, 0.28];

fileGoodA = write_mount_precheck_log("JIG1", "p05", 2.50, h1Good(1), h2Good(1), 0.05, 1, "NONE", 1);
fileGoodB = write_mount_precheck_log("JIG1", "p05", 2.60, h1Good(2), h2Good(2), 0.04, 1, "NONE", 1);
fileBadA = write_mount_precheck_log("JIG5", "p05", 3.00, h1Bad(1), h2Bad(1), 0.25, 0, "CLOSURE_INVALID", 0);
fileBadB = write_mount_precheck_log("JIG5", "p05", 3.10, h1Bad(2), h2Bad(2), 0.03, 1, "NONE", 1);
files = [fileGoodA, fileGoodB, fileBadA, fileBadB];
cleanup = onCleanup(@() cellfun(@delete_if_exists, cellstr(files))); %#ok<NASGU>

% parse_mount_precheck_log.m on a single multi-record file: two batches
% logged back to back must both be recovered, in order.
combined = write_temp_log([ ...
    mount_precheck_line("JIG1", "p03", 1, 1, 2.10, 0.30, 0.02, 0.01, 1, "NONE", 0), ...
    mount_precheck_line("JIG1", "p03", 2, 1, 2.15, 0.31, 0.02, 0.02, 1, "NONE", 0)]);
cleanup2 = onCleanup(@() delete_if_exists(combined)); %#ok<NASGU>
singleFileRecords = parse_mount_precheck_log(combined);
assert(height(singleFileRecords) == 2);
assert(singleFileRecords.BatchID(1) == 1 && singleFileRecords.BatchID(2) == 2);
assert(abs(singleFileRecords.H1AmplitudeDeg(2) - 0.31) < 1e-9);
assert(singleFileRecords.AcquisitionResult(1) == "OK");

labels = ["GOOD", "GOOD", "BAD", "BAD"];
result = analyze_mount_precheck_batch(files, labels);
assert(height(result.Records) == 4);
assert(height(result.ByLabel) == 2);

goodRow = result.ByLabel(result.ByLabel.Label == "GOOD", :);
badRow = result.ByLabel(result.ByLabel.Label == "BAD", :);
assert(abs(goodRow.Mean_H1AmplitudeDeg - mean(h1Good)) < 1e-9);
assert(abs(goodRow.Mean_H2AmplitudeDeg - mean(h2Good)) < 1e-9);
assert(abs(goodRow.MountValidRatePct - 100) < 1e-9);
assert(abs(badRow.Mean_H1AmplitudeDeg - mean(h1Bad)) < 1e-9);
assert(abs(badRow.Mean_H2AmplitudeDeg - mean(h2Bad)) < 1e-9);
assert(abs(badRow.MountValidRatePct - 50) < 1e-9);

% The firmware-observed direction ("H1 shrinks, H2 grows under bad
% mounting") must show up as BAD's H1 lower and H2OverH1 much higher.
assert(badRow.Mean_H1AmplitudeDeg < goodRow.Mean_H1AmplitudeDeg);
assert(badRow.Mean_H2OverH1 > goodRow.Mean_H2OverH1);

% Sorted ascending by Mean_H1AmplitudeDeg -- BAD (lower H1) must come first.
assert(result.ByLabel.Label(1) == "BAD");

rrc = result.RejectReasonCounts;
badClosureRow = rrc(rrc.Label == "BAD" & rrc.RejectReason == "CLOSURE_INVALID", :);
assert(height(badClosureRow) == 1);
assert(badClosureRow.GroupCount == 1);
goodNoneRow = rrc(rrc.Label == "GOOD" & rrc.RejectReason == "NONE", :);
assert(goodNoneRow.GroupCount == 2);
end

function file = write_mount_precheck_log(jigId, motorId, robustP2P, h1Amp, h2Amp, closureErr, mountValid, rejectReason, gateEnabled)
line = mount_precheck_line(jigId, motorId, 1, 1, robustP2P, h1Amp, h2Amp, closureErr, mountValid, rejectReason, gateEnabled);
file = write_temp_log(line);
end

function line = mount_precheck_line(jigId, motorId, batchId, cycleOrder, robustP2P, h1Amp, h2Amp, closureErr, mountValid, rejectReason, gateEnabled)
line = sprintf(strcat("MOUNT_PRECHECK_RESULT,SchemaVersion=5,BatchID=%d,CycleOrder=%d,TestID=1,", ...
    "Protocol=PRECONDITION_FULL_SWEEP_MOUNT_GATE_V1,JigID=%s,MotorID=%s,RobustP2PDeg=%.5f,", ...
    "H1AmplitudeDeg=%.5f,H1PhaseDeg=-50.00,H2AmplitudeDeg=%.5f,H2PhaseDeg=10.00,", ...
    "ClosureErrorDeg=%.5f,TrackingValid=1,ClosureValid=%d,AcquisitionResult=OK,", ...
    "MountValid=%d,RejectReason=%s,GateEnabled=%d"), ...
    batchId, cycleOrder, jigId, motorId, robustP2P, h1Amp, h2Amp, closureErr, ...
    double(rejectReason == "NONE"), mountValid, rejectReason, gateEnabled);
end

function test_peak_signature_tools()
% find_circular_extrema: n=8, period-4 square-ish wave [0 1 0 -1 0 1 0 -1]
% (0-based idx 0..7). With window=1, promThresh=0.5, must recover exactly
% the two maxima (idx 1,5, value 1) and two minima (idx 3,7, value -1) --
% hand-checkable by construction.
curve = [0; 1; 0; -1; 0; 1; 0; -1];
[maxIdx, maxVal] = find_circular_extrema(curve, 1, 0.5, true);
[minIdx, minVal] = find_circular_extrema(curve, 1, 0.5, false);
assert(isequal(maxIdx, [1; 5]));
assert(isequal(maxVal, [1; 1]));
assert(isequal(minIdx, [3; 7]));
assert(isequal(minVal, [-1; -1]));

% A promThresh above the actual prominence must find nothing.
[noneIdx, ~] = find_circular_extrema(curve, 1, 1.5, true);
assert(isempty(noneIdx));

% match_circular_peaks: two points in A, two in B, each within tolerance
% of exactly one A point -- every quantity hand-computable.
mResult = match_circular_peaks([1;5], [1;1], [2;6], [1.2;0.8], 8, 2);
assert(mResult.NMatched == 2);
assert(isequal(mResult.MatchedIndexA, [1;5]));
assert(isequal(mResult.MatchedIndexB, [2;6]));
assert(all(abs(mResult.Delta - [0.2; -0.2]) < 1e-9));
assert(isempty(mResult.UnmatchedIndexA));
assert(isempty(mResult.UnmatchedIndexB));

% Outside tolerance: no candidate pairs within reach -- both unmatched.
mFar = match_circular_peaks([0], [1], [4], [1], 8, 2);
assert(mFar.NMatched == 0);
assert(isequal(mFar.UnmatchedIndexA, 0));
assert(isequal(mFar.UnmatchedIndexB, 4));

% classify_jig_peak_signatures end-to-end: 3 synthetic jigs, one motor.
% JA and JB are the IDENTICAL pure order-36 curve (0.5 amplitude) --
% MeanAbsDeltaDeg must be exactly 0, classified SAME_CLASS. JC is JA
% scaled by 1.6x everywhere -- every matched peak/trough differs by
% exactly 0.6*valueA at that point (same sign as A, since it's a pure
% scale, not a shift), comfortably above the default 0.10 deg threshold,
% classified DIFFERENT_CLASS. Peak POSITIONS must be identical across all
% three (scaling doesn't move zero-crossings/extrema locations), so all
% 36 maxima and 36 minima must match on every pair.
n = 360;
theta = 2 * pi * 36 * (0:n - 1) / n;
curveA = 0.5 * sin(theta);
curveB = curveA;
curveC = 1.6 * curveA;

fileA = write_extreme_angle_log(curveA, "MZ", "JA");
fileB = write_extreme_angle_log(curveB, "MZ", "JB");
fileC = write_extreme_angle_log(curveC, "MZ", "JC");
cleanup = onCleanup(@() cellfun(@delete_if_exists, {fileA, fileB, fileC})); %#ok<NASGU>

fileGroups = struct("Files", {fileA, fileB, fileC}, ...
    "MotorId", {"MZ", "MZ", "MZ"}, "JigId", {"JA", "JB", "JC"});
result = classify_jig_peak_signatures(fileGroups);

pairs = result.PairSummary;
assert(height(pairs) == 3);
rowAB = pairs(pairs.JigA == "JA" & pairs.JigB == "JB", :);
rowAC = pairs(pairs.JigA == "JA" & pairs.JigB == "JC", :);
rowBC = pairs(pairs.JigA == "JB" & pairs.JigB == "JC", :);

assert(rowAB.NMaxMatched == 36 && rowAB.NMinMatched == 36);
assert(rowAC.NMaxMatched == 36 && rowAC.NMinMatched == 36);
assert(abs(rowAB.MeanAbsDeltaDeg) < 1e-9);
assert(rowAB.Class == "SAME_CLASS");
assert(rowAC.MeanAbsDeltaDeg > 0.10);
assert(rowAC.Class == "DIFFERENT_CLASS");
assert(rowBC.MeanAbsDeltaDeg > 0.10);
assert(rowBC.Class == "DIFFERENT_CLASS");

expectedRows = (rowAB.NMaxMatched + rowAB.NMinMatched) + (rowAC.NMaxMatched + rowAC.NMinMatched) ...
    + (rowBC.NMaxMatched + rowBC.NMinMatched);
assert(height(result.PeakDetail) == expectedRows);

% Spot-check one PeakDetail row against the hand-derived scale relationship.
detailAC = result.PeakDetail(result.PeakDetail.JigA == "JA" & result.PeakDetail.JigB == "JC" ...
    & result.PeakDetail.Kind == "MAX", :);
assert(height(detailAC) == 36);
assert(all(abs(detailAC.ValueB_Deg - 1.6 * detailAC.ValueA_Deg) < 1e-9));
end

function test_sweep_creep_analysis()
% Two synthetic sweeps mimicking the real V5.1->V5.3 schema evolution
% (docs/session-summary-2026-08-05.md): sweep A is "V5.1-style" (POINT
% lines missing PreCrossGapRaw/Recovery*/FineLanding* -- must fill NaN/""
% rather than error); sweep B is "V5.3-style" (full fields). Point 66 is
% built as a genuine trouble point in BOTH sweeps (TARGET_CROSSED /
% RECOVERY_RECROSSED, RecoveryAttempted=1, StickSlipJumpDetected=1 in the
% V5.3 sweep) so it must rank first in ByPoint; points 10/20 are clean OK
% every time so they must rank at the bottom (TroubleScore=0).
linesA = strings(0, 1);
linesA(end + 1) = "SWEEP_CREEP_CONFIG,SchemaVersion=5,TestID=1,SweepID=1,JigID=JIG7,MotorID=p03,Direction=CW,Official=0,Enabled=1,Protocol=ADAPTIVE_GAP_BUDGET_CROSS_GUARD_V1,TriggerRaw=200,BaseBudgetRaw=220,BaseMaxIterations=15,StepRaw=16,DeadbandRaw=16,Power=1.000";
linesA(end + 1) = "SWEEP_CREEP_POINT,SchemaVersion=5,TestID=1,SweepID=1,JigID=JIG7,MotorID=p03,Direction=CW,Point=66,Official=0,InitialGapRaw=223,InitialAbsGapRaw=223,BudgetClass=EXTENDED,SelectedBudgetRaw=320,SelectedMaxIterations=21,Iterations=21,TotalCorrectionRaw=336,FinalGapRaw=-311,Result=TARGET_CROSSED";
linesA(end + 1) = "SWEEP_CREEP_POINT,SchemaVersion=5,TestID=1,SweepID=1,JigID=JIG7,MotorID=p03,Direction=CW,Point=10,Official=0,InitialGapRaw=40,InitialAbsGapRaw=40,BudgetClass=BASE,SelectedBudgetRaw=220,SelectedMaxIterations=15,Iterations=3,TotalCorrectionRaw=48,FinalGapRaw=-8,Result=OK";
linesA(end + 1) = "SWEEP_CREEP_POINT,SchemaVersion=5,TestID=1,SweepID=1,JigID=JIG7,MotorID=p03,Direction=CW,Point=20,Official=0,InitialGapRaw=30,InitialAbsGapRaw=30,BudgetClass=BASE,SelectedBudgetRaw=220,SelectedMaxIterations=15,Iterations=2,TotalCorrectionRaw=32,FinalGapRaw=-2,Result=OK";
linesA(end + 1) = "END,SchemaVersion=5,TestID=1,SweepID=1,Status=INVALID,AcquisitionResult=OK,SweepPointCreepPointsCorrected=3,SweepPointCreepTotalIterations=26,SweepPointCreepTotalCorrectionRaw=416,SweepPointCreepTimeouts=0,SweepPointCreepBudgetExceeded=0,SweepPointCreepTargetCrossed=1,SweepPointCreepRecoveryAttempted=0,SweepPointCreepRecoverySucceeded=0,SweepPointCreepRecoveryFailed=0,SweepPointCreepRecoveryRecrossed=0,SweepPointCreepRecoveryTotalIterations=0,SweepPointCreepRecoveryTotalCorrectionRaw=0,SweepPointCreepBaseBudgetExceeded=0,SweepPointCreepBaseTargetCrossed=1,SweepPointCreepExtendedPoints=1,SweepPointCreepExtendedOk=0,SweepPointCreepExtendedTotalIterations=21,SweepPointCreepExtendedTotalCorrectionRaw=336,SweepPointCreepExtendedTimeouts=0,SweepPointCreepExtendedBudgetExceeded=0,SweepPointCreepExtendedTargetCrossed=1,SweepPointCreepFineLandingAttempted=0,SweepPointCreepFineLandingSucceeded=0,SweepPointCreepFineLandingFailed=0,SweepPointCreepStickSlipJump=0,SweepPointCreepMaxObservedStepDeltaRaw=87,SweepPointCreepIntegrityValid=0";
fileA = write_temp_log(linesA);

linesB = strings(0, 1);
linesB(end + 1) = "SWEEP_CREEP_CONFIG,SchemaVersion=6,TestID=5,SweepID=5,JigID=JIG7,MotorID=p03,Direction=CW,Official=0,Enabled=1,Protocol=ADAPTIVE_GAP_BUDGET_POINT66_FINE_LANDING_V1,TriggerRaw=200,BaseBudgetRaw=220,BaseMaxIterations=15,ExtendedBudgetRaw=320,ExtendedMaxIterations=21,StepRaw=16,DeadbandRaw=16,Power=1.000,FineTargetPoint=66,FineEntryRaw=64,FineStepRaw=4,FineMaxIterations=81,JumpThresholdRaw=96,TraceCapacity=100";
linesB(end + 1) = "SWEEP_CREEP_POINT,SchemaVersion=6,TestID=5,SweepID=5,JigID=JIG7,MotorID=p03,Direction=CW,Point=66,Official=0,InitialGapRaw=-238,InitialAbsGapRaw=238,BudgetClass=EXTENDED,SelectedBudgetRaw=320,SelectedMaxIterations=21,Iterations=21,TotalCorrectionRaw=336,PreCrossGapRaw=-18,CrossingGapRaw=279,RecoveryAttempted=1,RecoverySucceeded=0,RecoveryIterations=9,RecoveryCorrectionRaw=144,FineLandingAttempted=0,FineLandingSucceeded=0,FineIterations=0,FineCorrectionRaw=0,StickSlipJumpDetected=1,MaxObservedStepDeltaRaw=211,TraceCount=23,FinalGapRaw=-100,Result=RECOVERY_RECROSSED";
linesB(end + 1) = "SWEEP_CREEP_POINT,SchemaVersion=6,TestID=5,SweepID=5,JigID=JIG7,MotorID=p03,Direction=CW,Point=10,Official=0,InitialGapRaw=38,InitialAbsGapRaw=38,BudgetClass=BASE,SelectedBudgetRaw=220,SelectedMaxIterations=15,Iterations=3,TotalCorrectionRaw=48,PreCrossGapRaw=0,CrossingGapRaw=0,RecoveryAttempted=0,RecoverySucceeded=0,RecoveryIterations=0,RecoveryCorrectionRaw=0,FineLandingAttempted=0,FineLandingSucceeded=0,FineIterations=0,FineCorrectionRaw=0,StickSlipJumpDetected=0,MaxObservedStepDeltaRaw=12,TraceCount=0,FinalGapRaw=-6,Result=OK";
linesB(end + 1) = "SWEEP_CREEP_STEP,SchemaVersion=1,TestID=5,SweepID=5,JigID=JIG7,MotorID=p03,Direction=CW,Point=66,Official=0,StepOrder=1,Iteration=1,Phase=COARSE,CommandStepRaw=-16,GapBeforeRaw=-238,ObservedDeltaRaw=-15,GapAfterRaw=-223,StickSlipJumpDetected=0";
linesB(end + 1) = "SWEEP_CREEP_STEP,SchemaVersion=1,TestID=5,SweepID=5,JigID=JIG7,MotorID=p03,Direction=CW,Point=66,Official=0,StepOrder=9,Iteration=9,Phase=COARSE,CommandStepRaw=-16,GapBeforeRaw=-18,ObservedDeltaRaw=-211,GapAfterRaw=193,StickSlipJumpDetected=1";
linesB(end + 1) = "END,SchemaVersion=6,TestID=5,SweepID=5,Status=INVALID,AcquisitionResult=OK,SweepPointCreepPointsCorrected=2,SweepPointCreepTotalIterations=24,SweepPointCreepTotalCorrectionRaw=384,SweepPointCreepTimeouts=0,SweepPointCreepBudgetExceeded=0,SweepPointCreepTargetCrossed=1,SweepPointCreepRecoveryAttempted=1,SweepPointCreepRecoverySucceeded=0,SweepPointCreepRecoveryFailed=1,SweepPointCreepRecoveryRecrossed=1,SweepPointCreepRecoveryTotalIterations=9,SweepPointCreepRecoveryTotalCorrectionRaw=144,SweepPointCreepBaseBudgetExceeded=0,SweepPointCreepBaseTargetCrossed=0,SweepPointCreepExtendedPoints=1,SweepPointCreepExtendedOk=0,SweepPointCreepExtendedTotalIterations=21,SweepPointCreepExtendedTotalCorrectionRaw=336,SweepPointCreepExtendedTimeouts=0,SweepPointCreepExtendedBudgetExceeded=0,SweepPointCreepExtendedTargetCrossed=1,SweepPointCreepFineLandingAttempted=0,SweepPointCreepFineLandingSucceeded=0,SweepPointCreepFineLandingFailed=0,SweepPointCreepStickSlipJump=1,SweepPointCreepMaxObservedStepDeltaRaw=211,SweepPointCreepIntegrityValid=0";
fileB = write_temp_log(linesB);
cleanup = onCleanup(@() cellfun(@delete_if_exists, {fileA, fileB})); %#ok<NASGU>

% parse_sweep_creep_log.m on the V5.1-style file: fields absent from that
% schema (PreCrossGapRaw, RecoveryAttempted, FineLandingAttempted, ...)
% must come back as NaN, not error, and Config/Points/Steps/SweepSummary
% must all be populated from the single file correctly.
parsedA = parse_sweep_creep_log(fileA);
assert(height(parsedA.Config) == 1);
assert(height(parsedA.Points) == 3);
assert(height(parsedA.Steps) == 0);
assert(height(parsedA.SweepSummary) == 1);
row66A = parsedA.Points(parsedA.Points.Point == 66, :);
assert(isnan(row66A.RecoveryAttempted));
assert(isnan(row66A.FineLandingAttempted));
assert(row66A.Result == "TARGET_CROSSED");

parsedB = parse_sweep_creep_log(fileB);
assert(height(parsedB.Steps) == 2);
row66B = parsedB.Points(parsedB.Points.Point == 66, :);
assert(row66B.RecoveryAttempted == 1);
assert(row66B.StickSlipJumpDetected == 1);
assert(row66B.Result == "RECOVERY_RECROSSED");

result = analyze_sweep_creep_batch([fileA, fileB], ["V5.1", "V5.3"]);
assert(height(result.Points) == 5);
assert(height(result.Steps) == 2);
assert(height(result.SweepSummary) == 2);

byPoint = result.ByPoint;
assert(byPoint.Point(1) == 66);
assert(abs(byPoint.TroubleScore(1) - 1.0) < 1e-9); % non-OK in both appearances
point10 = byPoint(byPoint.Point == 10, :);
assert(abs(point10.TroubleScore - 0.0) < 1e-9);
% Point 66's V5.3 appearance has RecoveryAttempted=1/StickSlipJumpDetected=1,
% its V5.1 appearance has both NaN (schema didn't have the field) -- the
% fraction must be computed over only the non-NaN appearance, i.e. exactly 1.
point66Row = byPoint(byPoint.Point == 66, :);
assert(abs(point66Row.FracRecoveryAttempted - 1.0) < 1e-9);
assert(abs(point66Row.FracStickSlipJump - 1.0) < 1e-9);
assert(abs(point66Row.MaxAbsFinalGapRaw - 311) < 1e-9); % max(|-311|, |-100|)

byLabel = result.ByLabel;
v51Row = byLabel(byLabel.Label == "V5.1", :);
v53Row = byLabel(byLabel.Label == "V5.3", :);
assert(v51Row.NPointRows == 3);
assert(v53Row.NPointRows == 2);
assert(abs(v51Row.IntegrityValidRatePct - 0.0) < 1e-9); % the one sweep is INVALID
assert(v53Row.TotalRecoveryRecrossed == 1);
assert(v53Row.TotalStickSlipJump == 1);
end

function file = write_temp_log(lines)
file = string(tempname) + ".txt";
fid = fopen(file, "wt");
assert(fid >= 0);
for index = 1:numel(lines)
    fprintf(fid, "%s\n", lines(index));
end
fclose(fid);
end

function delete_if_exists(path)
if isfile(path)
    delete(path);
end
end
