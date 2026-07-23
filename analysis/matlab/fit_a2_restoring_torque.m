function fit = fit_a2_restoring_torque(metrics)
%FIT_A2_RESTORING_TORQUE First-harmonic regression of settle travel vs
%starting electrical phase, per power level and pooled across all levels.
%
%   Model: FinalTravelRaw ~ a*sin(theta) + b*cos(theta) + c, where
%   theta = 2*pi*StartModuloRaw/electricalCycle is the baseline position's
%   phase within one electrical cycle. amplitude = sqrt(a^2+b^2) is a proxy
%   for restoring-torque strength at that power; the implied phase is a
%   candidate A3 phase offset. An F-test against the intercept-only null
%   (no phase dependence) gives a p-value -- the statistically honest
%   replacement for eyeballing whether SettledModuloRaw values "look"
%   clustered. Pooling every safe run across P06-P09 gives this test far
%   more power than any single power level's n=5.
%
%   Only GatePass runs are used: a hard-gate FAULT run's FinalTravelRaw is a
%   safety cutoff point, not a settled equilibrium, and would bias the fit.

arguments
    metrics table
end

electricalPeriodRaw = 10923.0;
rawToDeg = 360.0/65536.0;

included = metrics(metrics.Included & metrics.GatePass,:);
profiles = unique(included.Profile, "stable");
n = numel(profiles);

profile = strings(n,1);
powerPercent = NaN(n,1);
sampleCount = zeros(n,1);
amplitudeRaw = NaN(n,1);
phaseRaw = NaN(n,1);
phaseDeg = NaN(n,1);
rSquared = NaN(n,1);
pValue = NaN(n,1);

for index = 1:n
    profile(index) = profiles(index);
    rows = included(included.Profile == profiles(index),:);
    powerPercent(index) = max(rows.TargetPowerPercent);
    result = fit_harmonic(rows, electricalPeriodRaw);
    sampleCount(index) = result.N;
    amplitudeRaw(index) = result.AmplitudeRaw;
    phaseRaw(index) = result.PhaseRaw;
    phaseDeg(index) = result.PhaseRaw*rawToDeg;
    rSquared(index) = result.RSquared;
    pValue(index) = result.PValue;
end

perLevel = table(profile, powerPercent, sampleCount, amplitudeRaw, ...
    phaseRaw, phaseDeg, rSquared, pValue, VariableNames=["Profile", ...
    "PowerPercent","N","AmplitudeRaw","PhaseRaw","PhaseDeg","RSquared","PValue"]);
perLevel = sortrows(perLevel, "PowerPercent");

pooledResult = fit_harmonic(included, electricalPeriodRaw);
pooled = struct(N=pooledResult.N, AmplitudeRaw=pooledResult.AmplitudeRaw, ...
    PhaseRaw=pooledResult.PhaseRaw, PhaseDeg=pooledResult.PhaseRaw*rawToDeg, ...
    RSquared=pooledResult.RSquared, PValue=pooledResult.PValue);

fit = struct(PerLevel=perLevel, Pooled=pooled);
end

function result = fit_harmonic(rows, electricalPeriodRaw)
n = height(rows);
theta = 2*pi*double(rows.StartModuloRaw)/electricalPeriodRaw;
travelRaw = double(rows.FinalTravelDeg)*65536.0/360.0;

if n < 4
    result = struct(N=n, AmplitudeRaw=NaN, PhaseRaw=NaN, RSquared=NaN, PValue=NaN);
    return
end

designMatrix = [sin(theta), cos(theta), ones(n,1)];
coeffs = designMatrix \ travelRaw;
residualFull = travelRaw - designMatrix*coeffs;
ssrFull = sum(residualFull.^2);
ssrReduced = sum((travelRaw - mean(travelRaw)).^2);

a = coeffs(1);
b = coeffs(2);
amplitudeRaw = sqrt(a^2 + b^2);
phaseRaw = mod(atan2(-b, a)*electricalPeriodRaw/(2*pi), electricalPeriodRaw);

dfFull = n - 3;
if dfFull <= 0 || ssrFull <= 0 || ssrReduced <= 0
    rSquared = NaN;
    pValue = NaN;
else
    rSquared = 1 - ssrFull/ssrReduced;
    fStatistic = ((ssrReduced - ssrFull)/2) / (ssrFull/dfFull);
    if fStatistic <= 0
        pValue = 1;
    else
        % F(2,dfFull) upper-tail p-value via the regularized incomplete
        % beta function (core MATLAB, no toolbox needed).
        x = 2*fStatistic/(2*fStatistic + dfFull);
        pValue = 1 - betainc(x, 1, dfFull/2);
    end
end

result = struct(N=n, AmplitudeRaw=amplitudeRaw, PhaseRaw=phaseRaw, ...
    RSquared=rSquared, PValue=pValue);
end
