function metric = compute_a5_run_metrics(run)
%COMPUTE_A5_RUN_METRICS Independent recompute of A5 static-capture stability
%   metrics from one parsed run's DATA table (2048 samples/run). Mirrors
%   scripts/analyze_control_a5.ps1's formulas exactly (verified by
%   crosscheck_a5_metrics.m against its real -SummaryCsv output) so MATLAB's
%   signal-processing strengths (autocorrelation, Allan deviation) can be
%   used with the same confidence as the PowerShell reference.

arguments
    run struct
end

data = run.DATA;
raw = double(data.Raw);
n = numel(raw);

relative = unwrap_relative(raw);

p2pRaw = max(relative) - min(relative);
driftRaw = relative(end) - relative(1);
meanRelRaw = mean(relative);
populationSdRaw = sqrt(sum((relative - meanRelRaw).^2) / n);
rmsRelRaw = sqrt(sum(relative.^2) / n);
medianRelRaw = median(relative);
absoluteDeviations = abs(relative - medianRelRaw);
madRaw = median(absoluteDeviations);
robustSigmaRaw = 1.4826 * madRaw;

sampleRateHz = 1000.0;
if isfield(run, "ARMED") && isfield(run.ARMED, "SampleRateHz")
    sampleRateHz = run.ARMED.SampleRateHz;
end
[slopeRawPerSample, detrendedSdRaw] = linear_drift(relative);
slopeRawPerSecond = slopeRawPerSample * sampleRateHz;

deltaRaw = diff(relative);
maxAbsStepRaw = max(abs(deltaRaw));

tauSamples = [1 2 4 8 16 32 64 128];
autocorr = zeros(1, numel(tauSamples));
allanDev = zeros(1, numel(tauSamples));
for index = 1:numel(tauSamples)
    autocorr(index) = autocorrelation_at_lag(relative, tauSamples(index));
    allanDev(index) = overlapping_allan_deviation(relative, tauSamples(index));
end

rawCrc32 = crc32_raw_words(uint16(raw));

metric = struct( ...
    Accepted = n, ...
    FirstRaw = raw(1), ...
    LastRaw = raw(end), ...
    MinRelRaw = min(relative), ...
    MaxRelRaw = max(relative), ...
    P2PRaw = p2pRaw, ...
    DriftRaw = driftRaw, ...
    MeanRelRaw = meanRelRaw, ...
    PopulationSdRaw = populationSdRaw, ...
    RmsRelRaw = rmsRelRaw, ...
    MedianRelRaw = medianRelRaw, ...
    MadRaw = madRaw, ...
    RobustSigmaRaw = robustSigmaRaw, ...
    SlopeRawPerSecond = slopeRawPerSecond, ...
    DetrendedSdRaw = detrendedSdRaw, ...
    MaxAbsStepRaw = maxAbsStepRaw, ...
    RawCRC32 = rawCrc32, ...
    TauSamples = tauSamples, ...
    Autocorrelation = autocorr, ...
    AllanDeviationRaw = allanDev);
end

function relative = unwrap_relative(raw)
n = numel(raw);
relative = zeros(n, 1);
for index = 2:n
    delta = raw(index) - raw(index - 1);
    if delta > 32767
        delta = delta - 65536;
    elseif delta < -32768
        delta = delta + 65536;
    end
    relative(index) = relative(index - 1) + delta;
end
end

function [slope, detrendedSd] = linear_drift(relative)
n = numel(relative);
index = (0:n-1)';
meanX = (n - 1) / 2.0;
meanY = mean(relative);
numerator = sum((index - meanX) .* (relative - meanY));
denominator = sum((index - meanX).^2);
if denominator == 0
    slope = 0;
else
    slope = numerator / denominator;
end
intercept = meanY - slope * meanX;
residual = relative - (intercept + slope * index);
detrendedSd = sqrt(sum(residual.^2) / n);
end

function value = autocorrelation_at_lag(relative, lag)
n = numel(relative);
if lag >= n
    value = NaN;
    return
end
meanValue = mean(relative);
centered = relative - meanValue;
denominator = sum(centered.^2);
if denominator == 0
    value = 0;
    return
end
numerator = sum(centered(1:n - lag) .* centered(1 + lag:n));
value = numerator / denominator;
end

function allanDev = overlapping_allan_deviation(relative, tau)
n = numel(relative);
if n < 2 * tau
    allanDev = NaN;
    return
end
prefix = [0; cumsum(relative)];
sumSquares = 0.0;
pairs = 0;
for start = 0:(n - 2 * tau)
    meanA = (prefix(start + tau + 1) - prefix(start + 1)) / tau;
    meanB = (prefix(start + 2 * tau + 1) - prefix(start + tau + 1)) / tau;
    sumSquares = sumSquares + (meanB - meanA)^2;
    pairs = pairs + 1;
end
allanDev = sqrt(0.5 * sumSquares / pairs);
end

function crc = crc32_raw_words(rawWords)
% Standard bit-reversed CRC-32 (poly 0xEDB88320, init/final 0xFFFFFFFF),
% processed byte-by-byte (low byte then high byte of each 16-bit word) --
% matches firmware's ControlA5_RawWordsCrc32 exactly.
persistent table
if isempty(table)
    table = zeros(1, 256, 'uint32');
    poly = uint32(3988292384); % 0xEDB88320
    for byteValue = 0:255
        crcEntry = uint32(byteValue);
        for bit = 1:8
            if bitand(crcEntry, uint32(1)) ~= 0
                crcEntry = bitxor(bitshift(crcEntry, -1), poly);
            else
                crcEntry = bitshift(crcEntry, -1);
            end
        end
        table(byteValue + 1) = crcEntry;
    end
end

crcState = uint32(4294967295); % 0xFFFFFFFF
for index = 1:numel(rawWords)
    word = uint32(rawWords(index));
    lowByte = uint8(bitand(word, uint32(255)));
    highByte = uint8(bitand(bitshift(word, -8), uint32(255)));
    crcState = bitxor(bitshift(crcState, -8), ...
        table(bitand(bitxor(crcState, uint32(lowByte)), uint32(255)) + 1));
    crcState = bitxor(bitshift(crcState, -8), ...
        table(bitand(bitxor(crcState, uint32(highByte)), uint32(255)) + 1));
end
crc = double(bitxor(crcState, uint32(4294967295)));
end
