function [indices, values] = find_circular_extrema(curve, window, promThresh, isMax)
%FIND_CIRCULAR_EXTREMA Local maxima/minima of a periodic (wraparound) curve.
%   A point is a local extremum if it is the max (or min) within a
%   +/-window circular neighborhood AND its prominence (extremum value
%   minus the opposite-sign extreme of that same neighborhood) is at
%   least promThresh -- this rejects sub-noise-floor wiggles from being
%   counted as real peaks. Default window=4 matches one lobe of the
%   order-36 dominant NL ripple on a 360-point sweep (360/36=10 points/
%   cycle, so +/-4 spans most of one lobe without bleeding into the next).
%
%   Ties (two or more adjacent points at the exact same window-max value)
%   are real, not a bug: a discrete grid landing exactly on a lobe's
%   symmetric shoulder produces an exact tie by construction (e.g. a
%   period-10 sine sampled at integer points has sin(72deg)==sin(108deg)
%   to floating-point precision). Only the LEADING edge of a tied
%   plateau (curve(i-1) < curve(i)) is reported, so a real peak is never
%   silently dropped just because it happens to sit on a tie, and a tied
%   plateau is never double-counted as two separate peaks.
%
%   [indices, values] = FIND_CIRCULAR_EXTREMA(curve, window, promThresh, isMax)
%   curve: (n,1) or (1,n) double, one point per degree (or any uniform
%   circular grid). indices: 0-based point indices of each extremum
%   found, ascending order. values: curve value at each returned index.

arguments
    curve (:,1) double
    window (1,1) double = 4
    promThresh (1,1) double = 0.03
    isMax (1,1) logical = true
end

n = numel(curve);
work = curve;
if ~isMax
    work = -work;
end
indices = [];
values = [];
for i = 0:n - 1
    win = mod((i - window):(i + window), n) + 1;
    windowVals = work(win);
    center = work(i + 1);
    prevVal = work(mod(i - 1, n) + 1);
    if center == max(windowVals) && prevVal < center
        prom = center - min(windowVals);
        if prom >= promThresh
            indices(end + 1) = i; %#ok<AGROW>
            values(end + 1) = center; %#ok<AGROW>
        end
    end
end
indices = indices(:);
values = values(:);
if ~isMax
    values = -values;
end
end
