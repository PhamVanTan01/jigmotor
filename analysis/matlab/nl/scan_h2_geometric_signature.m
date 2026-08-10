function [summary, detail] = scan_h2_geometric_signature(files, eraLabels)
%SCAN_H2_GEOMETRIC_SIGNATURE Pool H1/H2/H36 harmonic amplitudes across a
%   large batch of raw NL logs, grouped by ProductId (parsed from the file
%   name, pattern P0[2-9] case-insensitive) and JigId (from META.JigID,
%   falling back to a JIG[0-9] filename pattern if META lacks it).
%
%   H36 (motor/cogging family) shrank across firmware generations along
%   with H2 (settle-creep contaminated most harmonics broadly, not just
%   the geometric family), so raw H2 amplitude is NOT comparable across
%   eras. RatioH2H36 = H2/H36 is used as the primary cross-era ranking
%   metric; raw H2/H1/H36 are kept for within-era comparison.
%
%   Bypasses EligibleForStatistics deliberately -- this is an exploratory
%   population scan to characterize the H2 threshold, not an official NL
%   statistic. Every sweep with >=300 captured points and no NaN in the
%   first 360 ErrorDeg samples is included, regardless of RunRole.
%
%   files      : string array of file paths
%   eraLabels  : string array, same size as files, an era/source tag
%                (e.g. "legacy-root", "assembly-swap-era", "v5.x-latest")
%
%   summary : table grouped by ProductId x Era: N, MeanH1/H2/H36,
%             MeanRatioH2H36, SDRatioH2H36, CVRatioH2H36Pct
%   detail  : table, one row per qualifying sweep

arguments
    files (1,:) string
    eraLabels (1,:) string
end

orders = [1 2 36];
rows = cell(0, 10);

for i = 1:numel(files)
    f = files(i);
    productId = extract_product_id(f);
    try
        sweeps = parse_nl_log(f);
    catch err
        fprintf('  skip (parse error) %s: %s\n', f, err.message);
        continue
    end
    for s = 1:numel(sweeps)
        sw = sweeps(s);
        if height(sw.Data) < 300
            continue
        end
        err = sw.Data.ErrorDeg(1:min(360, height(sw.Data)));
        if any(isnan(err)) || numel(err) < 300
            continue
        end
        amp = compute_harmonic_spectrum(err, orders);
        h1 = amp(1); h2 = amp(2); h36 = amp(3);
        if h36 <= 0
            continue
        end
        jigId = extract_jig_id(sw, f);
        role = "";
        if isfield(sw.Meta, "RunRole")
            role = string(sw.Meta.RunRole);
        end
        rows(end+1, :) = {f, eraLabels(i), productId, jigId, sw.TestID, sw.SweepID, role, h1, h2, h36}; %#ok<AGROW>
    end
end

detail = cell2table(rows, 'VariableNames', ...
    {'File','Era','ProductId','JigId','TestID','SweepID','RunRole','H1_Deg','H2_Deg','H36_Deg'});
detail.RatioH2H36 = detail.H2_Deg ./ detail.H36_Deg;
detail.RatioH1H36 = detail.H1_Deg ./ detail.H36_Deg;

if isempty(detail)
    summary = table();
    return
end

[groups, productId, era] = findgroups(detail.ProductId, detail.Era);
n = splitapply(@numel, detail.H2_Deg, groups);
meanH1 = splitapply(@mean, detail.H1_Deg, groups);
meanH2 = splitapply(@mean, detail.H2_Deg, groups);
meanH36 = splitapply(@mean, detail.H36_Deg, groups);
meanRatio = splitapply(@mean, detail.RatioH2H36, groups);
sdRatio = splitapply(@(x) std(x), detail.RatioH2H36, groups);
cvRatioPct = 100 * sdRatio ./ meanRatio;

summary = table(productId, era, n, meanH1, meanH2, meanH36, meanRatio, sdRatio, cvRatioPct, ...
    'VariableNames', {'ProductId','Era','N','MeanH1_Deg','MeanH2_Deg','MeanH36_Deg', ...
    'MeanRatioH2H36','SDRatioH2H36','CVRatioH2H36Pct'});
summary = sortrows(summary, {'Era','MeanRatioH2H36'}, {'ascend','descend'});
end

function productId = extract_product_id(filePath)
tok = regexp(filePath, '[Pp]0([2-9])', 'tokens', 'once');
if isempty(tok)
    productId = "UNKNOWN";
else
    productId = "P0" + tok{1};
end
end

function jigId = extract_jig_id(sweep, filePath)
if isfield(sweep.Meta, "JigID") && string(sweep.Meta.JigID) ~= "" && string(sweep.Meta.JigID) ~= "UNKNOWN"
    jigId = string(sweep.Meta.JigID);
    return
end
tok = regexp(filePath, '[Jj][Ii][Gg] ?([0-9])', 'tokens', 'once');
if isempty(tok)
    jigId = "UNKNOWN";
else
    jigId = "JIG" + tok{1};
end
end
