function stats = compute_circular_significance(valuesRaw, periodRaw, options)
%COMPUTE_CIRCULAR_SIGNIFICANCE Rayleigh test and bootstrap CI for circular R.
%   A point estimate of R (from compute_circular_stats) cannot say whether
%   apparent clustering is distinguishable from a uniform (no phase-lock)
%   distribution at n=5. Rayleigh's test gives a p-value for that null
%   hypothesis; the bootstrap CI shows how much a single added/removed run
%   could move R, which matters when decisions are made on n=5 per level.

arguments
    valuesRaw (:,1) double
    periodRaw (1,1) double {mustBePositive}
    options.BootstrapSamples (1,1) double {mustBePositive, mustBeInteger} = 2000
    options.Alpha (1,1) double {mustBePositive} = 0.05
    options.Seed (1,1) double = 42
end

values = valuesRaw(isfinite(valuesRaw));
n = numel(values);
base = compute_circular_stats(values, periodRaw);

if n < 2
    stats = struct(N=n, R=base.ResultantR, RayleighZ=NaN, RayleighP=NaN, ...
        BootstrapCILow=NaN, BootstrapCIHigh=NaN, BootstrapSamples=0);
    return
end

z = n * base.ResultantR^2;
% Zar (1999) small-sample-corrected Rayleigh p-value approximation. Valid
% down to small n (it is the standard correction used precisely because the
% asymptotic exp(-z) formula is unreliable there).
p = exp(-z) * (1 + (2*z - z^2)/(4*n) - ...
    (24*z - 132*z^2 + 76*z^3 - 9*z^4)/(288*n^2));
p = min(max(p, 0), 1);

rngState = rng();
cleanupRng = onCleanup(@() rng(rngState));
rng(options.Seed);
bootR = zeros(options.BootstrapSamples, 1);
for index = 1:options.BootstrapSamples
    sampleIndex = randi(n, n, 1);
    bootStats = compute_circular_stats(values(sampleIndex), periodRaw);
    bootR(index) = bootStats.ResultantR;
end
clear cleanupRng
sortedBootR = sort(bootR);
loIndex = max(1, round(options.Alpha/2 * options.BootstrapSamples));
hiIndex = min(options.BootstrapSamples, round((1 - options.Alpha/2) * options.BootstrapSamples));

stats = struct(N=n, R=base.ResultantR, RayleighZ=z, RayleighP=p, ...
    BootstrapCILow=sortedBootR(loIndex), BootstrapCIHigh=sortedBootR(hiIndex), ...
    BootstrapSamples=options.BootstrapSamples);
end
