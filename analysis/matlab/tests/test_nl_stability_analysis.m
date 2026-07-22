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

fprintf("[ OK ] NL stability MATLAB analysis regression test passed.\n");
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
