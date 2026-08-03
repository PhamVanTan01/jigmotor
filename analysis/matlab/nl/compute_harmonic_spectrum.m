function amplitudes = compute_harmonic_spectrum(errors, orders)
%COMPUTE_HARMONIC_SPECTRUM DFT amplitude at each order in `orders`, for an
%   arbitrary error curve. Same formula compute_nl_sweep_metrics.m uses
%   for A36_Deg (hardcoded order=36), generalized to any order list so
%   multiple harmonics can be compared on the same curve in one call.
%
%   amp(k) = hypot(2*sum(centered.*cos(2*pi*order(k)*i/n))/n, ...
%                   2*sum(centered.*sin(2*pi*order(k)*i/n))/n)
%
%   Cross-checked against compute_nl_sweep_metrics.m's A36_Deg by the
%   regression test (same input, order=36, must match to float epsilon).

arguments
    errors (:, 1) double
    orders (1, :) double
end

n = numel(errors);
centered = errors - mean(errors);
index = (0:n - 1)';
amplitudes = zeros(1, numel(orders));
for k = 1:numel(orders)
    order = orders(k);
    a = sum(centered .* cos(2 * pi * order * index / n));
    b = sum(centered .* sin(2 * pi * order * index / n));
    amplitudes(k) = hypot(2 * a / n, 2 * b / n);
end
end
