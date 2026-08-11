function [pointMap, motionSummary, harmonics] = analyze_point_difficulty_map(files, labels)
%ANALYZE_POINT_DIFFICULTY_MAP Per-angle "how hard was this point to reach"
%   map from SWEEP_CREEP_POINT + SWEEP_POINT_TIMING telemetry, plus a
%   per-sweep MOTION_PROFILE mechanical-quality summary (backtracking).
%
%   Joins Points/Timing tables (from parse_sweep_creep_log.m) on Point
%   number within each OFFICIAL sweep, averages across sweeps sharing the
%   same label, and reports the result as a function of Point (0-359,
%   which equals the commanded angle in degrees since AnalysisPoints=360
%   spans one full turn). Then runs compute_harmonic_spectrum on each
%   difficulty signal to test whether it carries the same order-2
%   periodicity as the NL geometric-family harmonic (H2) -- if the
%   controller has to work harder twice per revolution at the SAME
%   angular locations that produce the H2 error signature, that is a
%   direct mechanistic link between the two, not just a coincidence of
%   two independently-computed numbers.
%
%   files/labels : string arrays, same size, one label per file (sweeps
%                  from files sharing a label are pooled together)
%
%   pointMap      : table, one row per (Label, Point), OFFICIAL sweeps only
%   motionSummary : table, one row per (Label, sweep), MOTION_PROFILE fields
%   harmonics     : table, one row per (Label, Signal, Order)

arguments
    files (1,:) string
    labels (1,:) string
end

pointRows = {};
motionRows = {};

for i = 1:numel(files)
    f = files(i);
    lbl = labels(i);

    creep = parse_sweep_creep_log(f);
    pts = creep.Points;
    tim = creep.Timing;

    % The Points/Timing "Official" flag is unreliable on diagnostic builds
    % that self-declare EligibleForStatistics=0 for the whole file (e.g.
    % V5.7/V5.8 DWT-timing builds) -- it reads 0 even for genuinely
    % OFFICIAL sweeps in that case. Identify PRECONDITION sweeps from the
    % sweep's own META.RunRole instead (via parse_nl_log) and drop only
    % those, keeping every other sweep regardless of the Official flag.
    nlSweeps = parse_nl_log(f);
    preconditionKeys = strings(0, 1);
    for k = 1:numel(nlSweeps)
        role = "";
        if isfield(nlSweeps(k).Meta, "RunRole")
            role = string(nlSweeps(k).Meta.RunRole);
        end
        if role == "PRECONDITION"
            preconditionKeys(end+1) = sprintf("%d_%d", nlSweeps(k).TestID, nlSweeps(k).SweepID); %#ok<AGROW>
        end
    end
    if ~isempty(pts)
        ptsKeys = compose("%d_%d", pts.TestID, pts.SweepID);
        pts = pts(~ismember(ptsKeys, preconditionKeys), :);
    end
    if ~isempty(tim)
        timKeys = compose("%d_%d", tim.TestID, tim.SweepID);
        tim = tim(~ismember(timKeys, preconditionKeys), :);
    end

    if ~isempty(pts)
        for r = 1:height(pts)
            timeToDeadbandMs = NaN;
            reached = NaN;
            clockHz = NaN;
            if ~isempty(tim)
                match = tim.TestID == pts.TestID(r) & tim.SweepID == pts.SweepID(r) & tim.Point == pts.Point(r);
                if any(match)
                    trow = tim(find(match, 1), :);
                    clockHz = trow.ClockHz;
                    if clockHz > 0
                        timeToDeadbandMs = 1000 * trow.TimeToDeadbandCycles / clockHz;
                    end
                    reached = trow.ReachedDeadband;
                end
            end
            pointRows(end+1, :) = {lbl, pts.TestID(r), pts.SweepID(r), pts.Point(r), ...
                pts.InitialAbsGapRaw(r), pts.Iterations(r), pts.TotalCorrectionRaw(r), ...
                pts.BudgetEscalated(r), timeToDeadbandMs, reached, string(pts.Result(r))}; %#ok<AGROW>
        end
    end

    motionRow = parse_motion_profile_local(f);
    for r = 1:height(motionRow)
        motionRows(end+1, :) = [{lbl}, table2cell(motionRow(r, :))]; %#ok<AGROW>
    end
end

detail = cell2table(pointRows, 'VariableNames', {'Label','TestID','SweepID','Point', ...
    'InitialAbsGapRaw','Iterations','TotalCorrectionRaw','BudgetEscalated', ...
    'TimeToDeadbandMs','ReachedDeadband','Result'});

[g, lbl, pt] = findgroups(detail.Label, detail.Point);
n = splitapply(@numel, detail.Point, g);
meanGap = splitapply(@(x) mean(x, 'omitnan'), detail.InitialAbsGapRaw, g);
meanIter = splitapply(@(x) mean(x, 'omitnan'), detail.Iterations, g);
meanCorr = splitapply(@(x) mean(x, 'omitnan'), detail.TotalCorrectionRaw, g);
escPct = splitapply(@(x) 100*mean(x, 'omitnan'), detail.BudgetEscalated, g);
meanTimeMs = splitapply(@(x) mean(x, 'omitnan'), detail.TimeToDeadbandMs, g);
reachedPct = splitapply(@(x) 100*mean(x, 'omitnan'), detail.ReachedDeadband, g);

pointMap = table(lbl, pt, n, meanGap, meanIter, meanCorr, escPct, meanTimeMs, reachedPct, ...
    'VariableNames', {'Label','Point','N','MeanInitialAbsGapRaw','MeanIterations', ...
    'MeanTotalCorrectionRaw','BudgetEscalatedPct','MeanTimeToDeadbandMs','ReachedDeadbandPct'});
pointMap = sortrows(pointMap, {'Label','Point'});

if isempty(motionRows)
    motionSummary = table();
else
    motionSummary = cell2table(motionRows, 'VariableNames', ...
        ['Label', motion_field_names()]);
end

harmonics = compute_difficulty_harmonics(pointMap);
end

function names = motion_field_names()
names = {'TestID','SweepID','JigID','LockDurationMs','LockCommands','LockTimingOverruns', ...
    'RampSegments','RampCommands','RampTimingOverruns','MaxLatenessTicks', ...
    'ObservedBacktracks','MaxObservedBacktrackRaw','BacktrackRatePct'};
end

function t = parse_motion_profile_local(filePath)
names = motion_field_names();
lines = readlines(filePath);
rows = {};
for i = 1:numel(lines)
    line = lines(i);
    if ~startsWith(line, "MOTION_PROFILE,")
        continue
    end
    rest = extractAfter(line, "MOTION_PROFILE,");
    parts = split(rest, ",");
    fields = struct();
    for k = 1:numel(parts)
        kv = split(parts(k), "=");
        if numel(kv) < 2
            continue
        end
        fields.(matlab.lang.makeValidName(strtrim(kv(1)))) = strtrim(strjoin(kv(2:end), "="));
    end
    getf = @(name, default) ternary(isfield(fields, name), @() str2double(fields.(name)), default);
    testId = getf("TestID", NaN);
    sweepId = getf("SweepID", NaN);
    jigId = "";
    if isfield(fields, "JigID"); jigId = string(fields.JigID); end
    lockMs = getf("LockDurationMs", NaN);
    lockCmd = getf("LockCommands", NaN);
    lockOver = getf("LockTimingOverruns", NaN);
    rampSeg = getf("RampSegments", NaN);
    rampCmd = getf("RampCommands", NaN);
    rampOver = getf("RampTimingOverruns", NaN);
    maxLate = getf("MaxLatenessTicks", NaN);
    backtracks = getf("ObservedBacktracks", NaN);
    maxBacktrack = getf("MaxObservedBacktrackRaw", NaN);
    backtrackPct = NaN;
    if rampCmd > 0
        backtrackPct = 100 * backtracks / rampCmd;
    end
    rows(end+1, :) = {testId, sweepId, jigId, lockMs, lockCmd, lockOver, rampSeg, rampCmd, ...
        rampOver, maxLate, backtracks, maxBacktrack, backtrackPct}; %#ok<AGROW>
end
if isempty(rows)
    t = cell2table(cell(0, numel(names)), 'VariableNames', names);
else
    t = cell2table(rows, 'VariableNames', names);
end
end

function out = ternary(cond, trueFn, falseVal)
if cond
    out = trueFn();
else
    out = falseVal;
end
end

function harmonics = compute_difficulty_harmonics(pointMap)
orders = [1 2 3 4 6 36];
signals = ["MeanInitialAbsGapRaw","MeanIterations","MeanTimeToDeadbandMs","ReachedDeadbandPct"];
labels = unique(pointMap.Label);
rows = {};
for i = 1:numel(labels)
    sub = pointMap(pointMap.Label == labels(i), :);
    sub = sortrows(sub, "Point");
    if height(sub) < 300
        continue
    end
    for s = 1:numel(signals)
        sig = signals(s);
        v = sub.(sig);
        v = fillmissing(v, 'linear');
        amp = compute_harmonic_spectrum(v, orders);
        for k = 1:numel(orders)
            rows(end+1, :) = {labels(i), sig, orders(k), amp(k)}; %#ok<AGROW>
        end
    end
end
harmonics = cell2table(rows, 'VariableNames', {'Label','Signal','Order','Amplitude'});
end
