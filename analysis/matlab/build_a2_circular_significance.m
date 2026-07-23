function significance = build_a2_circular_significance(metrics)
%BUILD_A2_CIRCULAR_SIGNIFICANCE Rayleigh test + bootstrap CI per profile.
%   Companion to build_a2_profile_summary's point-estimate R: answers
%   "is this R distinguishable from uniform" and "how wide is the
%   uncertainty on R given only ~5 runs per power level".

arguments
    metrics table
end

included = metrics(metrics.Included,:);
profiles = unique(included.Profile, "stable");
n = numel(profiles);

profile = strings(n,1);
powerPercent = NaN(n,1);
sampleCount = zeros(n,1);
resultantR = NaN(n,1);
rayleighZ = NaN(n,1);
rayleighP = NaN(n,1);
bootstrapCILow = NaN(n,1);
bootstrapCIHigh = NaN(n,1);

for index = 1:n
    profile(index) = profiles(index);
    rows = included(included.Profile == profiles(index),:);
    powerPercent(index) = max(rows.TargetPowerPercent);
    settled = rows.SettledModuloRaw(rows.GatePass & isfinite(rows.SettledModuloRaw));
    stats = compute_circular_significance(settled, 10923.0);
    sampleCount(index) = stats.N;
    resultantR(index) = stats.R;
    rayleighZ(index) = stats.RayleighZ;
    rayleighP(index) = stats.RayleighP;
    bootstrapCILow(index) = stats.BootstrapCILow;
    bootstrapCIHigh(index) = stats.BootstrapCIHigh;
end

significance = table(profile, powerPercent, sampleCount, resultantR, ...
    rayleighZ, rayleighP, bootstrapCILow, bootstrapCIHigh, ...
    VariableNames=["Profile","PowerPercent","SampleCount","ResultantR", ...
    "RayleighZ","RayleighP","BootstrapCILow","BootstrapCIHigh"]);

significance = sortrows(significance, "PowerPercent");
end
