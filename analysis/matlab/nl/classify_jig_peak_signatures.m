function result = classify_jig_peak_signatures(fileGroups, opts)
%CLASSIFY_JIG_PEAK_SIGNATURES Pairwise jig classification by full-curve
%   peak signature (all local maxima/minima, not just top-5/bottom-5).
%   Generalizes the by-hand method that found the sensor+fixture-assembly
%   swap in docs/session-summary-2026-08-03-mount-precheck-and-assembly-
%   swap.md section 3.5 (bottom-tail signature match, r=0.9984) to any
%   number of jigs/products at once: for each motor, every jig-pair's
%   mean curve is aligned (compare_nl_group_curves.m's own best circular
%   shift), then EVERY local peak/trough (find_circular_extrema.m) is
%   matched one-to-one across the pair (match_circular_peaks.m) and the
%   per-peak amplitude delta is reported -- both a summary verdict
%   (SAME_CLASS/DIFFERENT_CLASS) and the full per-peak angle+delta table,
%   so a disagreement can be traced to WHICH angles it lives at, not just
%   a single scalar.
%
%   IMPORTANT: JigId here is whatever the log's own JigID field says, NOT
%   a verified physical sensor+fixture assembly identity -- per the
%   session-summary above, that pairing has been observed to drift
%   (assemblies swapped between boards mid-session). Treat "DIFFERENT_
%   CLASS" between two same-named jigs, or "SAME_CLASS" between two
%   different-named jigs, as a lead to verify physically, not a final
%   verdict on which board is at fault.
%
%   result = CLASSIFY_JIG_PEAK_SIGNATURES(fileGroups, opts) fileGroups:
%   struct array with Files/MotorId/JigId (same shape as
%   analyze_nl_extreme_angles.m's input; multiple Files per element are
%   pooled into one mean curve, e.g. several remounts of the same jig).
%   opts (name-value): Window (default 4), PromThresholdDeg (default
%   0.03), MatchTolPoints (default 15), ClassifyThresholdDeg (default
%   0.10 -- NOT a validated spec, see note below) all pass straight
%   through to find_circular_extrema.m / match_circular_peaks.m.
%
%   ClassifyThresholdDeg is a diagnostic default, not a calibrated spec:
%   pick it the same way NL_PRECONDITION_STABILITY_THRESHOLD_DEG and
%   sector_match_gate.m's default were picked (a round number comfortably
%   above known within-jig remount noise and comfortably below known
%   cross-assembly gaps), pending real pilot data the same way
%   MOUNT_PRECHECK_V1's H1/H2 threshold is pending (see
%   analyze_mount_precheck_batch.m).

arguments
    fileGroups (1,:) struct
    opts.Window (1,1) double = 4
    opts.PromThresholdDeg (1,1) double = 0.03
    opts.MatchTolPoints (1,1) double = 15
    opts.ClassifyThresholdDeg (1,1) double = 0.10
end

groups = struct([]);
for index = 1:numel(fileGroups)
    g = build_nl_group_curve(fileGroups(index).Files, fileGroups(index).MotorId, ...
        fileGroups(index).JigId, 5);
    if isempty(groups)
        groups = g;
    else
        groups(end + 1) = g; %#ok<AGROW>
    end
end

motorIds = unique([groups.MotorId], "stable");
pairRows = table();
peakRows = table();
for m = 1:numel(motorIds)
    motorGroups = groups([groups.MotorId] == motorIds(m));
    jigIds = [motorGroups.JigId];
    [~, order] = sort(jigIds);
    motorGroups = motorGroups(order);
    for i = 1:numel(motorGroups)
        for j = i + 1:numel(motorGroups)
            a = motorGroups(i);
            b = motorGroups(j);
            if a.AnalysisPoints ~= b.AnalysisPoints
                error("ClassifyJigPeaks:MismatchedAnalysisPoints", ...
                    "%s: cannot compare N=%d (%s) and N=%d (%s)", ...
                    a.MotorId, a.AnalysisPoints, a.JigId, b.AnalysisPoints, b.JigId);
            end
            n = a.AnalysisPoints;
            cmp = compare_nl_group_curves(a, b);
            shift = cmp.BestShiftPoints;
            alignedB = b.MeanError(mod((0:n - 1) + shift, n) + 1);

            [maxA, maxValA] = find_circular_extrema(a.MeanError, opts.Window, opts.PromThresholdDeg, true);
            [minA, minValA] = find_circular_extrema(a.MeanError, opts.Window, opts.PromThresholdDeg, false);
            [maxB, maxValB] = find_circular_extrema(alignedB, opts.Window, opts.PromThresholdDeg, true);
            [minB, minValB] = find_circular_extrema(alignedB, opts.Window, opts.PromThresholdDeg, false);

            mMax = match_circular_peaks(maxA, maxValA, maxB, maxValB, n, opts.MatchTolPoints);
            mMin = match_circular_peaks(minA, minValA, minB, minValB, n, opts.MatchTolPoints);

            allDelta = [mMax.Delta; mMin.Delta];
            meanAbsDelta = mean(abs(allDelta));
            maxAbsDelta = max(abs(allDelta));
            nMatched = mMax.NMatched + mMin.NMatched;
            nTotal = mMax.NA + mMax.NB + mMin.NA + mMin.NB; % both sides' counts
            matchFrac = 2 * nMatched / nTotal;

            if meanAbsDelta <= opts.ClassifyThresholdDeg
                cls = "SAME_CLASS";
            else
                cls = "DIFFERENT_CLASS";
            end

            row = table(a.MotorId, a.JigId, b.JigId, cmp.BestShiftDeg, cmp.ZeroShiftCorrelation, ...
                cmp.BestShiftCorrelation, mMax.NMatched, mMax.NA, mMax.NB, mMin.NMatched, mMin.NA, mMin.NB, ...
                matchFrac, meanAbsDelta, maxAbsDelta, cls, VariableNames = ...
                ["MotorId","JigA","JigB","BestShiftDeg","ZeroShiftCorrelation","BestShiftCorrelation", ...
                "NMaxMatched","NMaxA","NMaxB","NMinMatched","NMinA","NMinB", ...
                "MatchFraction","MeanAbsDeltaDeg","MaxAbsDeltaDeg","Class"]);
            if isempty(pairRows)
                pairRows = row;
            else
                pairRows = [pairRows; row]; %#ok<AGROW>
            end

            peakRows = [peakRows; peak_detail_rows(a.MotorId, a.JigId, b.JigId, "MAX", mMax, n)]; %#ok<AGROW>
            peakRows = [peakRows; peak_detail_rows(a.MotorId, a.JigId, b.JigId, "MIN", mMin, n)]; %#ok<AGROW>
        end
    end
end

result = struct(Groups = groups, PairSummary = pairRows, PeakDetail = peakRows);

fprintf("=== Jig peak-signature classification: %d groups, %d pairs ===\n", ...
    numel(groups), height(pairRows));
if ~isempty(pairRows)
    disp(pairRows(:, ["MotorId","JigA","JigB","BestShiftDeg","BestShiftCorrelation", ...
        "MatchFraction","MeanAbsDeltaDeg","MaxAbsDeltaDeg","Class"]));
end
fprintf(strcat("Note: JigId is the log's own label, not a verified physical assembly ", ...
    "identity (see docs/session-summary-2026-08-03-mount-precheck-and-assembly-swap.md). ", ...
    "ClassifyThresholdDeg=%.3f deg is a diagnostic default, not a calibrated spec.\n"), ...
    opts.ClassifyThresholdDeg);
end

function rows = peak_detail_rows(motorId, jigA, jigB, kind, m, n)
nRows = m.NMatched;
if nRows == 0
    rows = table();
    return
end
angleDegA = m.MatchedIndexA * 360.0 / n;
rows = table(repmat(motorId, nRows, 1), repmat(jigA, nRows, 1), repmat(jigB, nRows, 1), ...
    repmat(string(kind), nRows, 1), m.MatchedIndexA, angleDegA, m.MatchedValueA, m.MatchedValueB, ...
    m.Delta, m.Distance * 360.0 / n, VariableNames = ...
    ["MotorId","JigA","JigB","Kind","IndexA","AngleDegA","ValueA_Deg","ValueB_Deg","DeltaDeg","AlignDistanceDeg"]);
end
