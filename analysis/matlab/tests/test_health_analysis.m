function test_health_analysis
%TEST_HEALTH_ANALYSIS Lightweight regression for the health/algorithm-
%   weakness analysis tools (analyze_sensor_noise_floor.m,
%   analyze_acquisition_health.m, analyze_pid_timing_jitter.m), all
%   without hardware log dependency -- synthetic logs with hand-checkable
%   expected results.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
addpath(fullfile(root, "health"));

test_sensor_noise_floor();
test_acquisition_health();
test_pid_timing_jitter();

fprintf("[ OK ] Health/algorithm-weakness MATLAB analysis regression test passed.\n");
end

function test_sensor_noise_floor()
lines = strings(0, 1);
lines(end + 1) = "MA600 noise (last 5s): P2P=0.10deg StdDev=0.02deg Drift=0.01deg MaxStep=0.05deg N=25 valid=1";
lines(end + 1) = "MA600 noise (last 5s): P2P=0.30deg StdDev=0.06deg Drift=-0.02deg MaxStep=0.15deg N=25 valid=1";
% A Valid=0 row (e.g. captured during/after a motor error) with a huge
% P2P must inflate the ALL stats but be excluded from the Valid-only
% stats -- this is the exact bug the tool's first real-data run exposed
% (a Valid=0 read after E502 gave P2P=164.95 deg, ~30000x LSB, silently
% pooled with genuine stationary readings before this fix).
lines(end + 1) = "MA600 noise (last 5s): P2P=99.0deg StdDev=40.0deg Drift=90.0deg MaxStep=95.0deg N=25 valid=0";
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

result = analyze_sensor_noise_floor(file);
assert(result.N == 3);
assert(result.NValid == 2);
assert(abs(result.P2PMeanDeg - mean([0.10, 0.30, 99.0])) < 1e-9); % ALL includes the invalid outlier
assert(abs(result.P2PMeanDegValid - 0.20) < 1e-9);                % Valid-only excludes it
assert(abs(result.P2PMaxDegValid - 0.30) < 1e-9);
assert(abs(result.StdDevMeanDegValid - 0.04) < 1e-9);
lsbDeg = 360.0 / 65536.0;
assert(abs(result.LsbDeg - lsbDeg) < 1e-12);
assert(abs(result.P2POverLsbMeanValid - (0.20 / lsbDeg)) < 1e-6);
end

function test_acquisition_health()
lines = strings(0, 1);
lines(end + 1) = "META,SchemaVersion=5,AcqReadAttempts=1000,AcqRetries=10,AcqTransportErrors=2,AcqJumpRejects=1,AcqFailedSamples=0";
lines(end + 1) = "META,SchemaVersion=5,AcqReadAttempts=2000,AcqRetries=0,AcqTransportErrors=0,AcqJumpRejects=0,AcqFailedSamples=0";
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

result = analyze_acquisition_health(file);
assert(height(result.Runs) == 2);
assert(result.TotalReadAttempts == 3000);
assert(result.TotalRetries == 10);
assert(result.TotalTransportErrors == 2);
assert(result.TotalJumpRejects == 1);
assert(abs(result.Runs.RetryRate(1) - 10 / 1000) < 1e-12);
assert(height(result.ByFile) == 1);
assert(result.ByFile.sum_ReadAttempts(1) == 3000);
end

function test_pid_timing_jitter()
lines = strings(0, 1);
lines(end + 1) = "CONTROL_A4_ARMED,Profile=SYNTH";
lines(end + 1) = "CONTROL_A4_SUMMARY,Profile=SYNTH,Result=OK";
% 5 ticks: 3 on time (LatenessTicks=0), 1 late by 2, 1 late by 4.
latenessValues = [0, 0, 2, 0, 4];
for i = 1:numel(latenessValues)
    lines(end + 1) = sprintf(strcat("CONTROL_A4_DATA,Seq=%d,Phase=PHASE_SWEEP,", ...
        "LatenessTicks=%d,LoopCycles=3000"), i, latenessValues(i)); %#ok<AGROW>
end
file = write_temp_log(lines);
cleanup = onCleanup(@() delete_if_exists(file)); %#ok<NASGU>

result = analyze_pid_timing_jitter(file, 1.0);
assert(result.N == 5);
assert(abs(result.MeanLatenessTicks - mean(latenessValues)) < 1e-9);
assert(result.MaxLatenessTicks == 4);
assert(abs(result.LateFraction - 2 / 5) < 1e-9);
assert(abs(result.MeanDtErrorPct - 100 * mean(latenessValues)) < 1e-9);
assert(abs(result.MaxDtErrorPct - 400) < 1e-9);
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
