function timeline = build_s4_sensor_timeline(files)
%BUILD_S4_SENSOR_TIMELINE Chronological per-file fingerprint table across
%   the whole S4 open-loop log set, built to support inferring how many
%   distinct physical MA600 units were in play over time.
%
%   MA600 exposes no per-unit serial number over SPI (Core/Inc/ma600.h's
%   register map: ZERO/DIR/FILT/STATUS/PRT/RMAPID/CORR0-31, none of them a
%   unique ID -- RMAPID is a register-map/part revision ID shared by every
%   unit of that part). So sensor identity can only be inferred indirectly
%   from the measured curve, using the signature established on
%   2026-08-19 (see docs/session-summary-2026-08-19.md, "Sensor swap"
%   section): a sensor-chip swap changes RawP2P amplitude modestly WITHOUT
%   requiring an angular realignment shift when compared against a
%   same-mount reference, whereas a geometry/mount change requires a real
%   shift. This function only builds the per-file fingerprint table;
%   pairwise shift/RMSE comparison against a same-mount reference (the
%   actual transition detection) is the caller's job, since it requires
%   picking which pairs are legitimately "same mount, different time".
%
%   Per file: JigId (from META, authoritative -- not filename), BuildID
%   (firmware build timestamp, used as a chronological proxy since these
%   logs have no capture wall-clock timestamp field), MCU_UID, confirmed
%   MotorId is NOT attempted here (firmware's own MotorID is always
%   UNKNOWN; use A36 against a known reference table separately if needed
%   -- out of scope for this function), RawP2P/OpenLoopNL_Deg, A36
%   (motor-family fingerprint), H2 amplitude+phase (mount/sensor-family
%   fingerprint), N eligible OFFICIAL open-loop sweeps.

arguments
    files (1,:) string
end

rows = {};
for i = 1:numel(files)
    try
        sweeps = parse_openloop_nl_log(files(i));
    catch
        continue
    end
    if isempty(sweeps)
        continue
    end
    metaSweep = sweeps(find(arrayfun(@(s) isfield(s.Meta,"JigID") && s.Meta.JigID ~= "", sweeps), 1));
    if isempty(metaSweep)
        continue
    end
    jigId = "";
    buildId = "";
    mcuUid = "";
    for s = 1:numel(sweeps)
        if isfield(sweeps(s).Meta, "JigID") && sweeps(s).Meta.JigID ~= ""
            jigId = sweeps(s).Meta.JigID;
            break
        end
    end

    acc = [];
    for s = 1:numel(sweeps)
        sw = sweeps(s);
        if ~sw.IsOpenLoopOfficial
            continue
        end
        d = sw.Data;
        d = d(d.Index >= 0 & d.Index < 360, :);
        if height(d) < 360
            continue
        end
        curve = nan(360, 1);
        curve(d.Index + 1) = d.ErrorDeg;
        if any(isnan(curve))
            continue
        end
        acc = [acc, curve]; %#ok<AGROW>
    end
    if isempty(acc)
        continue
    end
    meanCurve = mean(acc, 2);
    n = 360; idx = (0:n-1)';
    amp = compute_harmonic_spectrum(meanCurve, [1 2 36]);
    c = meanCurve - mean(meanCurve);
    a2 = sum(c .* cosd(2*idx)); b2 = sum(c .* sind(2*idx));
    h2Phase = atan2d(b2, a2);
    rawP2p = max(meanCurve) - min(meanCurve);

    buildIdRaw = "";
    lines = readlines(files(i), "EmptyLineRule", "skip");
    for L = 1:min(numel(lines), 200)
        if startsWith(lines(L), "META,") && contains(lines(L), "BuildID=")
            tok = regexp(lines(L), "BuildID=([^,]*)", "tokens", "once");
            if ~isempty(tok)
                buildIdRaw = tok{1};
            end
            mcuTok = regexp(lines(L), "MCU_UID=([^,]*)", "tokens", "once");
            if ~isempty(mcuTok)
                mcuUid = mcuTok{1};
            end
            break
        end
    end
    buildDate = NaT;
    try
        buildDate = datetime(buildIdRaw, "InputFormat", "MMM d yyyy HH:mm:ss", "Locale", "en_US");
    catch
        try
            buildDate = datetime(buildIdRaw, "InputFormat", "MMM  d yyyy HH:mm:ss", "Locale", "en_US");
        catch
            buildDate = NaT;
        end
    end

    rows(end+1, :) = {files(i), jigId, mcuUid, buildDate, size(acc,2), ...
        rawP2p, amp(3), amp(2), h2Phase}; %#ok<AGROW>
end

timeline = cell2table(rows, 'VariableNames', {'File','JigId','McuUid','BuildDate', ...
    'NOfficialSweeps','RawP2P_Deg','A36_Deg','H2_Deg','H2PhaseDeg'});
timeline = sortrows(timeline, {'JigId','BuildDate'});
end
