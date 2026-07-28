function gate = sector_match_gate(sectorRawA, sectorRawB, toleranceRaw)
%SECTOR_MATCH_GATE Flags whether two sessions' AnalysisStartRaw (sector)
%   values are close enough for a direct NL/A36/RMS_AC comparison to be
%   considered free of the sector confound found in analyze_jig_delta.m.
%
%   Why a gate and not a correction formula: fit_sector_response.m's own
%   validation (14 real A0 sessions, JIG1/JIG4/JIG5, products p02-p07)
%   found sector explains only ~22% of within-product NL_RobustP2P_Deg
%   variance (R^2=0.22, within-product-centered single-harmonic fit) --
%   real, but far from a complete explanation. Silently "subtracting the
%   fitted sector effect" would leave ~78% of any disagreement unaddressed
%   while implying it was fixed. The defensible move at this evidence
%   level is a VALIDITY GATE: flag comparisons with a large sector
%   mismatch as confounded (interpret with caution, or use
%   correct_delta_for_sector.m to see how much of the delta sector alone
%   can account for) rather than pretend to remove the confound outright.
%
%   gate = SECTOR_MATCH_GATE(sectorRawA, sectorRawB, toleranceRaw) wraps
%   the raw delta to the nearest point in one electrical cycle (10923 raw)
%   and flags SectorMatched=true when the wrapped delta's magnitude is
%   within toleranceRaw. Default toleranceRaw=200 raw (~6.6 deg electrical)
%   is a generous multiple of the ~10-20 raw session-to-session spread
%   observed within a single jig's own repeated boot-ups in these logs
%   (see analyze_nl_factors.m's real-data runs) -- not a validated safety
%   limit, just a round number well above normal noise and well below the
%   ~120-172 deg swings that coincided with the largest NL disagreements.

arguments
    sectorRawA (1,1) double
    sectorRawB (1,1) double
    toleranceRaw (1,1) double = 200.0
end

electricalCycleRaw = 10923.0;
rawDelta = sectorRawB - sectorRawA;
wrapped = mod(rawDelta + electricalCycleRaw / 2, electricalCycleRaw) - electricalCycleRaw / 2;
gate = struct( ...
    SectorDeltaRaw = wrapped, ...
    SectorDeltaDeg = wrapped * 360.0 / electricalCycleRaw, ...
    ToleranceRaw = toleranceRaw, ...
    SectorMatched = abs(wrapped) <= toleranceRaw);
end
