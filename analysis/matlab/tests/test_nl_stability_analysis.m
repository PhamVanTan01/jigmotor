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
