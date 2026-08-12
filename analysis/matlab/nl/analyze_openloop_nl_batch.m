function [runs, summary] = analyze_openloop_nl_batch(files, labels)
%ANALYZE_OPENLOOP_NL_BATCH Pool schema-v6 GREMSY_COMPAT_OPEN_LOOP_NL_V1 logs.
%   RULE-0-compliant gate (AGENTS.md / docs/open-loop-nl-direction-
%   correction-handoff-2026-08-12.md): only sweeps with
%   MeasurementProfile=GREMSY_COMPAT_OPEN_LOOP_NL_V1,
%   OfficialOpenLoopNL=1, FeedbackActuationEnabled=0, RunRole=OFFICIAL,
%   EligibleForStatistics=1 are pooled. Everything else (PRECONDITION,
%   any POSITION_RESPONSE_DIAGNOSTIC_V5X sweep, any schema<6 file) is
%   reported as excluded, never silently dropped.
%
%   Primary metric is OpenLoopNL_Deg (Gremsy-compatible max(Error)-
%   min(Error)) per the schema doc; RobustP2P_Deg/RMS_AC/harmonics are
%   reported alongside as supporting metrics, never substituted as
%   primary.
%
%   Also asserts open-loop purity per sweep: End.SweepPointCreepIntegrityValid
%   must be 1 and every SweepPointCreep* counter must be 0 for an included
%   sweep -- a nonzero counter on a sweep that otherwise claims
%   OfficialOpenLoopNL=1 is a contract violation, flagged loudly rather
%   than averaged in silently.
%
%   files/labels : string arrays, same size, one label per file
%
%   runs    : table, one row per included OFFICIAL sweep
%   summary : table, one row per label (n/mean/SD/CV for OpenLoopNL_Deg,
%             RobustP2P_Deg, RMS_AC, A36/AElectrical6, ClosureErrorDeg)

arguments
    files (1,:) string
    labels (1,:) string
end

runRows = {};
excluded = {};
purityViolations = {};

for i = 1:numel(files)
    sweeps = parse_openloop_nl_log(files(i));
    for s = 1:numel(sweeps)
        sw = sweeps(s);
        role = "";
        if isfield(sw.Meta, "RunRole"); role = sw.Meta.RunRole; end
        if ~sw.IsOpenLoopOfficial
            reason = describe_exclusion(sw.Meta);
            excluded(end+1, :) = {labels(i), sw.TestID, sw.SweepID, role, reason}; %#ok<AGROW>
            continue
        end

        creepFields = ["SweepPointCreepPointsCorrected","SweepPointCreepTotalIterations", ...
            "SweepPointCreepTotalCorrectionRaw","SweepPointCreepTargetCrossed", ...
            "SweepPointCreepRecoveryAttempted","SweepPointCreepStickSlipJump"];
        dirty = false;
        for f = creepFields
            if isfield(sw.End, f) && ~isnan(sw.End.(f)) && sw.End.(f) ~= 0
                dirty = true;
            end
        end
        integrityOk = isfield(sw.End, "SweepPointCreepIntegrityValid") && sw.End.SweepPointCreepIntegrityValid == 1;
        if dirty || ~integrityOk
            purityViolations(end+1, :) = {labels(i), sw.TestID, sw.SweepID}; %#ok<AGROW>
            continue
        end

        r = sw.Result;
        runRows(end+1, :) = {labels(i), sw.TestID, sw.SweepID, ...
            get_or_nan(r, "OpenLoopNL_Deg"), get_or_nan(r, "RobustP2P_Deg"), ...
            get_or_nan(r, "MeanDC"), get_or_nan(r, "RMS_AC"), ...
            get_or_nan(r, "ClosureErrorDeg"), get_or_nan(r, "ClosureLimitDeg"), ...
            get_or_nan(r, "A1"), get_or_nan(r, "A2"), get_or_nan(r, "A36"), ...
            get_or_nan(r, "AElectrical6"), get_or_nan(r, "Motor_System_INL_Deg"), ...
            get_or_nan(r, "TrackingError_RMS_Deg")}; %#ok<AGROW>
    end
end

runs = cell2table(runRows, 'VariableNames', {'Label','TestID','SweepID', ...
    'OpenLoopNL_Deg','RobustP2P_Deg','MeanDC','RMS_AC','ClosureErrorDeg','ClosureLimitDeg', ...
    'A1','A2','A36','AElectrical6','Motor_System_INL_Deg','TrackingError_RMS_Deg'});

fprintf('Included (RULE-0-gated OFFICIAL open-loop) sweeps: %d\n', height(runs));
if ~isempty(excluded)
    excludedT = cell2table(excluded, 'VariableNames', {'Label','TestID','SweepID','RunRole','Reason'});
    fprintf('Excluded sweeps: %d\n', height(excludedT));
    disp(excludedT);
end
if ~isempty(purityViolations)
    violT = cell2table(purityViolations, 'VariableNames', {'Label','TestID','SweepID'});
    fprintf(2, 'WARNING: %d sweep(s) claim OfficialOpenLoopNL=1 but have nonzero SweepPointCreep* counters or SweepPointCreepIntegrityValid~=1 -- excluded, contract violation:\n', height(violT));
    disp(violT);
end

if isempty(runs)
    summary = table();
    return
end

[g, lbl] = findgroups(runs.Label);
n = splitapply(@numel, runs.OpenLoopNL_Deg, g);
meanNl = splitapply(@(x) mean(x, 'omitnan'), runs.OpenLoopNL_Deg, g);
sdNl = splitapply(@(x) std(x, 'omitnan'), runs.OpenLoopNL_Deg, g);
meanRobust = splitapply(@(x) mean(x, 'omitnan'), runs.RobustP2P_Deg, g);
sdRobust = splitapply(@(x) std(x, 'omitnan'), runs.RobustP2P_Deg, g);
meanRms = splitapply(@(x) mean(x, 'omitnan'), runs.RMS_AC, g);
meanA36 = splitapply(@(x) mean(x, 'omitnan'), runs.A36, g);
sdA36 = splitapply(@(x) std(x, 'omitnan'), runs.A36, g);
meanClosure = splitapply(@(x) mean(x, 'omitnan'), runs.ClosureErrorDeg, g);

summary = table(lbl, n, meanNl, sdNl, 100*sdNl./meanNl, meanRobust, sdRobust, meanRms, meanA36, sdA36, meanClosure, ...
    'VariableNames', {'Label','N','MeanOpenLoopNL_Deg','SDOpenLoopNL_Deg','CVOpenLoopNL_Pct', ...
    'MeanRobustP2P_Deg','SDRobustP2P_Deg','MeanRMS_AC','MeanA36','SDA36','MeanClosureErrorDeg'});
end

function v = get_or_nan(s, name)
if isfield(s, name)
    v = s.(name);
else
    v = NaN;
end
end

function reason = describe_exclusion(meta)
checks = {"MeasurementProfile", "GREMSY_COMPAT_OPEN_LOOP_NL_V1"; ...
          "OfficialOpenLoopNL", "1"; ...
          "FeedbackActuationEnabled", "0"; ...
          "RunRole", "OFFICIAL"; ...
          "EligibleForStatistics", "1"};
failed = strings(0, 1);
for k = 1:size(checks, 1)
    name = checks{k, 1};
    expected = checks{k, 2};
    actual = "";
    if isfield(meta, name); actual = string(meta.(name)); end
    if actual ~= expected
        failed(end+1) = sprintf("%s=%s(expected %s)", name, actual, expected); %#ok<AGROW>
    end
end
reason = strjoin(failed, "; ");
end
