function result = match_circular_peaks(indicesA, valuesA, indicesB, valuesB, n, tolDeg)
%MATCH_CIRCULAR_PEAKS Greedy nearest-neighbor pairing of two circular
%   point sets (e.g. local maxima from find_circular_extrema.m on two
%   ALREADY-ALIGNED curves -- align first via compare_nl_group_curves.m's
%   BestShiftPoints, matching what analyze_nl_extreme_angles.m does for
%   its top-5/bottom-5 sets, generalized here to an arbitrary count of
%   peaks). Greedy-by-distance is used instead of an optimal assignment
%   (Hungarian) because false matches only happen when two candidate
%   peaks sit within tolDeg of each other on BOTH sides, which the
%   window-based extrema detector already prevents by construction (peaks
%   are separated by at least ~2*window points).
%
%   result = MATCH_CIRCULAR_PEAKS(indicesA, valuesA, indicesB, valuesB, n, tolDeg)
%   indices are 0-based point indices (as returned by
%   find_circular_extrema.m), n is the curve length in points, tolDeg is
%   the max circular distance (in points, despite the name -- pass points
%   here and convert to degrees by the caller if the grid isn't 1
%   point/degree) to consider two points "the same" peak.
%
%   Returns a struct: MatchedIndexA/MatchedIndexB/MatchedValueA/
%   MatchedValueB/Delta (B-A)/Distance (one row per matched pair, sorted
%   by MatchedIndexA), UnmatchedIndexA/UnmatchedValueA (peaks only in A),
%   UnmatchedIndexB/UnmatchedValueB (peaks only in B).

arguments
    indicesA (:,1) double
    valuesA (:,1) double
    indicesB (:,1) double
    valuesB (:,1) double
    n (1,1) double
    tolDeg (1,1) double = 15
end

nA = numel(indicesA);
nB = numel(indicesB);
candidates = zeros(0, 3); % [distance, aPos, bPos]
for a = 1:nA
    for b = 1:nB
        d = circular_distance(indicesA(a), indicesB(b), n);
        if d <= tolDeg
            candidates(end + 1, :) = [d, a, b]; %#ok<AGROW>
        end
    end
end

matchedA = false(nA, 1);
matchedB = false(nB, 1);
matches = zeros(0, 6); % [idxA, idxB, valA, valB, delta, distance]
if ~isempty(candidates)
    candidates = sortrows(candidates, 1);
    for row = 1:size(candidates, 1)
        a = candidates(row, 2);
        b = candidates(row, 3);
        if ~matchedA(a) && ~matchedB(b)
            matchedA(a) = true;
            matchedB(b) = true;
            matches(end + 1, :) = [indicesA(a), indicesB(b), valuesA(a), valuesB(b), ...
                valuesB(b) - valuesA(a), candidates(row, 1)]; %#ok<AGROW>
        end
    end
end
if ~isempty(matches)
    matches = sortrows(matches, 1);
end

result = struct( ...
    MatchedIndexA = matches(:, 1), MatchedIndexB = matches(:, 2), ...
    MatchedValueA = matches(:, 3), MatchedValueB = matches(:, 4), ...
    Delta = matches(:, 5), Distance = matches(:, 6), ...
    UnmatchedIndexA = indicesA(~matchedA), UnmatchedValueA = valuesA(~matchedA), ...
    UnmatchedIndexB = indicesB(~matchedB), UnmatchedValueB = valuesB(~matchedB), ...
    NA = nA, NB = nB, NMatched = size(matches, 1));
end

function d = circular_distance(a, b, n)
delta = mod(abs(a - b), n);
d = min(delta, n - delta);
end
