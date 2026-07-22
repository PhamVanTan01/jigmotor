function stats = compute_nl_stability_stats(values)
%COMPUTE_NL_STABILITY_STATS Aggregate repeatability statistics for one leg.
%   Mirrors tools/analyze_nl_stability.py's describe(): sample SD (N-1,
%   MATLAB's default), CV%, median, MAD-based robust sigma (1.4826*MAD),
%   min/max/range, and the informal ISO-5725-style 2.77*SD repeatability
%   limit (explicitly a diagnostic band in the Python tool, not a pass/fail
%   spec).

arguments
    values (:,1) double
end

n = numel(values);
stats = struct(N = n, Mean = NaN, SampleSd = NaN, CvPct = NaN, Median = NaN, ...
    Mad = NaN, RobustSigma = NaN, Min = NaN, Max = NaN, Range = NaN, ...
    RepeatabilityLimit2_77Sd = NaN);
if n == 0
    return
end

meanValue = mean(values);
medianValue = median(values);
stats.Mean = meanValue;
stats.Median = medianValue;
stats.Min = min(values);
stats.Max = max(values);
stats.Range = stats.Max - stats.Min;

if n > 1
    sampleSd = std(values, 0); % N-1
    stats.SampleSd = sampleSd;
    stats.RepeatabilityLimit2_77Sd = 2.77 * sampleSd;
    if meanValue ~= 0
        stats.CvPct = sampleSd / meanValue * 100.0;
    end
end

mad = median(abs(values - medianValue));
stats.Mad = mad;
stats.RobustSigma = 1.4826 * mad;
end
