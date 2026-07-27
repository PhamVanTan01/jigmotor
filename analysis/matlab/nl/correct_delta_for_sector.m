function result = correct_delta_for_sector(rawDelta, sectorRawA, sectorRawB, fit)
%CORRECT_DELTA_FOR_SECTOR Remove the fit_sector_response.m-predicted
%   sector-driven contribution from a jig/session NL delta (e.g. from
%   analyze_jig_delta.m's Summary.*_Delta columns), leaving a residual
%   delta that should be free of the sector confound this fit's R^2
%   quantifies (~22% of within-product variance for NL_RobustP2P_Deg on
%   the 14-session validation set -- see fit_sector_response.m). This
%   DOES NOT explain the remaining residual; it isolates the
%   sector-explainable PART of a delta so the rest can be discussed as
%   genuine jig/board/motor difference without sector noise mixed in.
%   Do not report ResidualDelta as "the true jig effect" without also
%   reporting fit.RSquared -- a low R^2 means most of RawDelta survives
%   into ResidualDelta essentially unchanged.

arguments
    rawDelta (1,:) double
    sectorRawA (1,:) double
    sectorRawB (1,:) double
    fit struct
end

predictedDelta = fit.PredictFn(sectorRawB) - fit.PredictFn(sectorRawA);
result = struct(RawDelta = rawDelta, PredictedSectorContribution = predictedDelta, ...
    ResidualDelta = rawDelta - predictedDelta);
end
