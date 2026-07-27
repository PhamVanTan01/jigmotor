function result = analyze_sensor_noise_floor(files)
%ANALYZE_SENSOR_NOISE_FLOOR Aggregate "MA600 noise (last 5s)" diagnostic
%   lines (format: "MA600 noise (last 5s): P2P=Xdeg StdDev=Xdeg Drift=Xdeg
%   MaxStep=Xdeg N=25 valid=1", emitted between BATCH cooldown windows)
%   across many raw hardware logs to characterize the sensor's stationary
%   (motor-off) noise floor and compare it against the encoder's native
%   LSB resolution (360/65536 deg = 0.00549 deg). This is the read-path
%   noise the PID feedback loop's raw, unaveraged single-sample reads are
%   directly exposed to (see position_controller.c / Motor_MoveToAngle*
%   in motor.c -- unlike the NL sweep's MA600_ReadAveragedPointWithIo,
%   the real-time control loop does not average or MAD-filter its
%   feedback samples).

arguments
    files (1,:) string
end

pattern = "MA600 noise \(last 5s\): P2P=([\-0-9.]+)deg StdDev=([\-0-9.]+)deg " + ...
    "Drift=([\-0-9.]+)deg MaxStep=([\-0-9.]+)deg N=(\d+) valid=(\d)";

file = strings(0, 1);
p2pDeg = [];
stdDevDeg = [];
driftDeg = [];
maxStepDeg = [];
sampleCount = [];
valid = [];

for index = 1:numel(files)
    lines = readlines(files(index));
    tokens = regexp(lines, pattern, "tokens");
    for lineIndex = 1:numel(tokens)
        matchList = tokens{lineIndex};
        if isempty(matchList)
            continue
        end
        t = matchList{1};
        file(end + 1, 1) = files(index); %#ok<AGROW>
        p2pDeg(end + 1, 1) = str2double(t(1)); %#ok<AGROW>
        stdDevDeg(end + 1, 1) = str2double(t(2)); %#ok<AGROW>
        driftDeg(end + 1, 1) = str2double(t(3)); %#ok<AGROW>
        maxStepDeg(end + 1, 1) = str2double(t(4)); %#ok<AGROW>
        sampleCount(end + 1, 1) = str2double(t(5)); %#ok<AGROW>
        valid(end + 1, 1) = str2double(t(6)); %#ok<AGROW>
    end
end

if isempty(file)
    error("SensorNoise:NoSamples", "No 'MA600 noise' diagnostic lines found in the given files.");
end

runs = table(file, p2pDeg, stdDevDeg, driftDeg, maxStepDeg, sampleCount, valid, ...
    VariableNames=["File", "P2PDeg", "StdDevDeg", "DriftDeg", "MaxStepDeg", "N", "Valid"]);

lsbDeg = 360.0 / 65536.0;
n = height(runs);
% The firmware itself flags some noise-check windows invalid (Valid=0 --
% e.g. captured during/after a motor error, not a stationary steady
% state). Pooling those with genuine stationary readings hugely inflates
% the apparent noise floor with numbers that were never meant to be
% representative -- report All vs Valid-only separately rather than
% silently mixing them (a first pass at this tool did exactly that and
% got a mean 100x too high because of it).
validMask = runs.Valid == 1;
p2pOverLsbAll = runs.P2PDeg / lsbDeg;
validRuns = runs(validMask, :);
p2pOverLsbValid = validRuns.P2PDeg / lsbDeg;

result = struct(Runs = runs, LsbDeg = lsbDeg, N = n, NValid = height(validRuns), ...
    P2PMeanDeg = mean(runs.P2PDeg), P2PMedianDeg = median(runs.P2PDeg), ...
    P2PMaxDeg = max(runs.P2PDeg), StdDevMeanDeg = mean(runs.StdDevDeg), ...
    P2POverLsbMean = mean(p2pOverLsbAll), P2POverLsbMax = max(p2pOverLsbAll), ...
    StdOverLsbMean = mean(runs.StdDevDeg) / lsbDeg, ...
    P2PMeanDegValid = mean(validRuns.P2PDeg), P2PMedianDegValid = median(validRuns.P2PDeg), ...
    P2PMaxDegValid = max(validRuns.P2PDeg), StdDevMeanDegValid = mean(validRuns.StdDevDeg), ...
    P2POverLsbMeanValid = mean(p2pOverLsbValid), P2POverLsbMaxValid = max(p2pOverLsbValid), ...
    StdOverLsbMeanValid = mean(validRuns.StdDevDeg) / lsbDeg);

fprintf("=== MA600 stationary noise floor: %d readings (%d Valid=1) across %d files ===\n", ...
    n, height(validRuns), numel(unique(runs.File)));
fprintf("ALL (incl. Valid=0, e.g. captured during/after a motor error):\n");
fprintf("  P2P: mean=%.4f deg (%.1fx LSB)  median=%.4f deg  max=%.4f deg (%.1fx LSB)\n", ...
    result.P2PMeanDeg, result.P2POverLsbMean, result.P2PMedianDeg, result.P2PMaxDeg, result.P2POverLsbMax);
fprintf("VALID ONLY (Valid=1, genuine stationary reads):\n");
fprintf("  P2P: mean=%.4f deg (%.1fx LSB)  median=%.4f deg  max=%.4f deg (%.1fx LSB)\n", ...
    result.P2PMeanDegValid, result.P2POverLsbMeanValid, result.P2PMedianDegValid, ...
    result.P2PMaxDegValid, result.P2POverLsbMaxValid);
fprintf("  StdDev: mean=%.4f deg (%.1fx LSB)\n", result.StdDevMeanDegValid, result.StdOverLsbMeanValid);
if any(validMask)
    [worstP2PValid, worstIdxLocal] = max(validRuns.P2PDeg);
    fprintf("  Worst VALID reading: %s, P2P=%.3f deg (%.0fx LSB)\n", ...
        validRuns.File(worstIdxLocal), worstP2PValid, worstP2PValid / lsbDeg);
end
end
