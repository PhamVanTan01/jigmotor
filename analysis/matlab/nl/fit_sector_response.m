function fit = fit_sector_response(files, products, metricName, periodRaw)
%FIT_SECTOR_RESPONSE Within-product-centered single-harmonic regression of
%   a NL metric against AnalysisStartRaw (sector), pooling many A0-protocol
%   sessions across different products/jigs/dates.
%
%   IMPORTANT -- read before using this for anything. Validated on 14 real
%   A0 sessions (JIG1 test29 + JIG4/JIG5 test31, products p02/p03/p05/p06/
%   p07, 2026-07): this single-harmonic model explains R^2~=0.22 of
%   within-product NL_RobustP2P_Deg variance (electrical-cycle period,
%   10923 raw) -- REAL but PARTIAL. A naive pooled fit that does NOT
%   center by product first gets R^2~=0.01 (products/motors have their own
%   nonlinearity baseline that swamps the shared sector shape unless
%   removed first) -- do not skip the centering step. Even centered,
%   ~78% of the within-product variance stays unexplained by sector alone:
%   MotorIDValid=0 on every run in this dataset (see analyze_jig_delta.m),
%   so genuine motor-to-motor variation is a live, unruled-out contributor.
%   Use this to isolate the sector-explainable PART of a delta
%   (correct_delta_for_sector.m), not to claim a full fix -- see
%   docs/hardware-validation-checklist.md and the JIG1-vs-JIG4/JIG4-vs-
%   JIG5 analyses this was built from for the fuller picture. A software
%   correction is a partial patch; the durable fix is controlling A0's
%   sector at the protocol/firmware level so future comparisons are not
%   confounded by it at all.
%
%   fit = FIT_SECTOR_RESPONSE(files, products, metricName, periodRaw) pools
%   one point per file (session mean of metricName over valid official
%   sweeps), subtracts each product's own mean (removes the between-
%   product/motor baseline so only the within-product sector shape is
%   fit), then regresses centeredMetric ~ a*cos(2*pi*sector/periodRaw) +
%   b*sin(2*pi*sector/periodRaw) (no intercept -- centered data already
%   averages to ~0 per product).

arguments
    files (1,:) string
    products (1,:) string
    metricName (1,1) string
    periodRaw (1,1) double = 10923.0
end

if numel(files) ~= numel(products)
    error("SectorResponse:LabelCount", "files (%d) must match products (%d) in count.", ...
        numel(files), numel(products));
end

n = numel(files);
sector = NaN(n, 1);
metricValue = NaN(n, 1);
for index = 1:n
    [sector(index), metricValue(index)] = session_mean(files(index), metricName);
end

uniqueProducts = unique(products, "stable");
centered = metricValue;
for p = 1:numel(uniqueProducts)
    mask = products == uniqueProducts(p);
    centered(mask) = metricValue(mask) - mean(metricValue(mask));
end

theta = 2 * pi * sector / periodRaw;
design = [cos(theta), sin(theta)];
coeffs = design \ centered;
predicted = design * coeffs;
resid = centered - predicted;
ssrFull = sum(resid.^2);
ssrNull = sum(centered.^2);
if ssrNull > 0
    rSquared = 1 - ssrFull / ssrNull;
else
    rSquared = NaN;
end

fit = struct(Files = files(:), Products = products(:), Sector = sector, ...
    MetricValue = metricValue, Centered = centered, PeriodRaw = periodRaw, ...
    Coeffs = coeffs, RSquared = rSquared, N = n, ...
    PredictFn = @(s) coeffs(1) * cos(2 * pi * s / periodRaw) + coeffs(2) * sin(2 * pi * s / periodRaw));

fprintf("=== Sector-response fit: %s, n=%d sessions, %d products, period=%.0f raw ===\n", ...
    metricName, n, numel(uniqueProducts), periodRaw);
fprintf("R^2=%.4f (within-product-centered) -- partial explanation only, see docstring caveat\n", rSquared);
end

function [sectorMean, metricMean] = session_mean(filePath, metricName)
sweeps = parse_nl_log(filePath);
sectorValues = [];
metricValues = [];
for index = 1:numel(sweeps)
    sweep = sweeps(index);
    if ~isfield(sweep, "Meta") || isempty(fieldnames(sweep.Meta))
        continue
    end
    if ~isfield(sweep.Meta, "EligibleForStatistics") || string(sweep.Meta.EligibleForStatistics) ~= "1"
        continue
    end
    if ~isfield(sweep.Meta, "MeasurementValid") || string(sweep.Meta.MeasurementValid) ~= "1"
        continue
    end
    if ~isfield(sweep, "END") || ~isfield(sweep.END, "Status") || string(sweep.END.Status) ~= "VALID"
        continue
    end
    metric = compute_nl_sweep_metrics(sweep);
    sectorValues(end + 1) = str2double(sweep.Meta.AnalysisStartRaw); %#ok<AGROW>
    metricValues(end + 1) = metric.(metricName); %#ok<AGROW>
end
sectorMean = mean(sectorValues);
metricMean = mean(metricValues);
end
