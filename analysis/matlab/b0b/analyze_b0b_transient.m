function summary = analyze_b0b_transient(filePaths)
%ANALYZE_B0B_TRANSIENT Per-tick tracking-lag shape for B0-B backoff/forward.
%   MATLAB port of scripts/analyze_b0b_transient.py's --b0b mode (see that
%   file's module docstring for the full rationale). B0-B's backoff/forward
%   legs (nonlinear_test.c, SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2) command a
%   182-raw quintic move over 40 ticks at 1 ms/tick, full power.
%   APPROACH_RESULT reports only the *final* observed displacement; this
%   reconstructs the tick-by-tick shape from APPROACH_STEPS, comparing the
%   analytically re-derived commanded quintic curve to the logged position,
%   both referenced to the leg's own first sample (tick 1) -- a *relative*
%   shape comparison, not the official displacement metric.
%
%   As of 2026-07 no new B0-B hardware A/B log data exists yet (only the
%   firmware builds in builds/b0b-soft-start-*); this has been validated by
%   reproducing docs/b0b-soft-start-phase-a-result.md's published Phase-A
%   table exactly (tick 15: BACKOFF 35.4%/32.4 raw, FORWARD 18.5%/40.8 raw;
%   tick 40: BACKOFF 57.4%/77.4 raw, FORWARD 38.5%/111.9 raw) by mining the
%   same historical NL logs (p03 jig ... test 14-17). Point this at the new
%   A/B/A batch's logs once it exists.

arguments
    filePaths (1,:) string
end

targetRaw = 182.0;
ticks = 40;
checkpoints = [1 5 10 15 20 25 30 35 40];

legRuns = struct('BACKOFF', {{}}, 'FORWARD', {{}});
for fileIndex = 1:numel(filePaths)
    [legs, results] = parse_b0b_log(filePaths(fileIndex));
    for legIndex = 1:numel(legs)
        leg = legs(legIndex);
        if numel(leg.Raw) ~= ticks
            continue
        end
        if ~isKey(results, leg.SweepID)
            continue
        end
        r = results(leg.SweepID);
        if ~isfield(r, "Status") || string(r.Status) ~= "OK" || ...
                ~isfield(r, "ApproachStructuralValid") || ...
                string(r.ApproachStructuralValid) ~= "1"
            continue
        end
        if leg.Leg == "BACKOFF"
            targetSigned = -targetRaw;
        else
            targetSigned = targetRaw;
        end
        raw0 = leg.Raw(1);
        actualCum = leg.Raw - raw0;
        expected = arrayfun(@(commandIndex) expected_cum(commandIndex, ...
            targetSigned, ticks), 1:ticks);
        lag = expected - actualCum;
        pctTracked = zeros(1, ticks);
        nonzero = expected ~= 0;
        pctTracked(nonzero) = actualCum(nonzero) ./ expected(nonzero) * 100.0;

        entry = struct('Path', filePaths(fileIndex), 'SweepID', leg.SweepID, ...
            'ActualCum', actualCum, 'Expected', expected, 'Lag', lag, ...
            'PctTracked', pctTracked);
        legName = char(leg.Leg);
        legRuns.(legName){end + 1} = entry; %#ok<AGROW>
    end
end

summary = struct();
legNames = ["BACKOFF", "FORWARD"];
for legIndex = 1:numel(legNames)
    legName = char(legNames(legIndex));
    runs = legRuns.(legName);
    n = numel(runs);
    if n == 0
        continue
    end

    nCheckpoints = numel(checkpoints);
    pctMean = zeros(1, nCheckpoints);
    pctMin = zeros(1, nCheckpoints);
    pctMax = zeros(1, nCheckpoints);
    lagMean = zeros(1, nCheckpoints);
    lagMax = zeros(1, nCheckpoints);
    for cpIndex = 1:nCheckpoints
        tickIndex = checkpoints(cpIndex);
        pcts = cellfun(@(r) r.PctTracked(tickIndex), runs);
        lags = cellfun(@(r) abs(r.Lag(tickIndex)), runs);
        pctMean(cpIndex) = mean(pcts);
        pctMin(cpIndex) = min(pcts);
        pctMax(cpIndex) = max(pcts);
        lagMean(cpIndex) = mean(lags);
        lagMax(cpIndex) = max(lags);
    end
    finalPcts = cellfun(@(r) r.PctTracked(end), runs);

    summary.(legName) = struct('N', n, 'Checkpoints', checkpoints, ...
        'PctTrackedMean', pctMean, 'PctTrackedMin', pctMin, 'PctTrackedMax', pctMax, ...
        'LagMeanRaw', lagMean, 'LagMaxRaw', lagMax, ...
        'FinalPctTrackedMean', mean(finalPcts), 'FinalPctTrackedMin', min(finalPcts), ...
        'FinalPctTrackedMax', max(finalPcts));

    fprintf("=== B0-B %s leg -- %d run(s), target %d ticks / %d raw ===\n", ...
        legName, n, ticks, targetRaw);
    fprintf("%4s %14s %13s %13s %14s %13s\n", "tick", "%tracked mean", ...
        "%tracked min", "%tracked max", "lag mean(raw)", "lag max(raw)");
    for cpIndex = 1:nCheckpoints
        fprintf("%4d %14.1f %13.1f %13.1f %14.1f %13.1f\n", checkpoints(cpIndex), ...
            pctMean(cpIndex), pctMin(cpIndex), pctMax(cpIndex), lagMean(cpIndex), ...
            lagMax(cpIndex));
    end
    fprintf("  final tick-%d %%tracked: mean=%.1f min=%.1f max=%.1f\n\n", ticks, ...
        mean(finalPcts), min(finalPcts), max(finalPcts));
end
end

function value = expected_cum(commandIndex, targetSigned, ticks)
if commandIndex >= ticks
    value = targetSigned;
    return
end
u = commandIndex / ticks;
blend = u^3 * (10.0 - 15.0 * u + 6.0 * u * u);
value = targetSigned * blend;
end
