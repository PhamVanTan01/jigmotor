function result = analyze_deadtime_harmonic_signature(fileGroups, maxMultiple)
%ANALYZE_DEADTIME_HARMONIC_SIGNATURE Tests whether cross-jig differences
%   concentrate at ODD multiples of the electrical fundamental (order 6
%   for this 6-pole-pair motor: 6, 18, 30, ...) as classic 3-phase PWM
%   dead-time distortion predicts, versus EVEN multiples (12, 24, 36, ...)
%   which come from motor/back-EMF structure -- A36 = 6x6 is the
%   established "motor signature" harmonic, stable across jigs in every
%   cross-jig comparison run so far (cross_jig_measurement_analysis.md,
%   docs/nl-extreme-angle-cross-jig-test33-assessment.md).
%
%   This is meant as a validation step BEFORE trusting or extending
%   ENABLE_DEADTIME_COMPENSATION_FEEDFORWARD (motor_pwm.c): if cross-jig
%   deltas are NOT concentrated at odd multiples of 6, the dead-time
%   hypothesis is not well supported by this dataset and that compensation
%   should not be tuned or deployed on the strength of the hypothesis
%   alone -- "control the driver" is only the right lever if the data
%   actually shows the driver-specific signature, not just "NL differs
%   and dead-time is a plausible-sounding story".
%
%   result = ANALYZE_DEADTIME_HARMONIC_SIGNATURE(fileGroups, maxMultiple)
%   fileGroups: same struct array as analyze_nl_extreme_angles.m (Files,
%   MotorId, JigId), exactly two jig groups per motor. Computes the
%   harmonic spectrum on each group's BATCH-MEAN error curve
%   (build_nl_group_curve.m) at multiples of 6 from 1x to maxMultiple x,
%   splits into odd/even multiple, and reports the cross-jig |delta| in
%   each class per motor and pooled.

arguments
    fileGroups (1,:) struct
    maxMultiple (1,1) double = 10
end

electricalFundamental = 6; % order 6 = 1 electrical cycle per 60 mech deg, 6 pole pairs
multiples = 1:maxMultiple;
orders = multiples * electricalFundamental;
isOdd = mod(multiples, 2) == 1;

groups = struct([]);
for index = 1:numel(fileGroups)
    g = build_nl_group_curve(fileGroups(index).Files, fileGroups(index).MotorId, ...
        fileGroups(index).JigId, 5);
    g.Spectrum = compute_harmonic_spectrum(g.MeanError, orders);
    if isempty(groups)
        groups = g;
    else
        groups(end + 1) = g; %#ok<AGROW>
    end
end

motorIds = unique([groups.MotorId], "stable");
motor = strings(0, 1);
order = [];
multipleOf6 = [];
parity = strings(0, 1);
jigA = strings(0, 1);
jigB = strings(0, 1);
ampA = [];
ampB = [];
absDelta = [];

for m = 1:numel(motorIds)
    motorGroups = groups([groups.MotorId] == motorIds(m));
    if numel(motorGroups) < 2
        continue
    end
    jigIds = [motorGroups.JigId];
    [~, sortOrder] = sort(jigIds);
    motorGroups = motorGroups(sortOrder);
    a = motorGroups(1);
    b = motorGroups(2);
    for k = 1:numel(orders)
        motor(end + 1, 1) = motorIds(m); %#ok<AGROW>
        order(end + 1, 1) = orders(k); %#ok<AGROW>
        multipleOf6(end + 1, 1) = multiples(k); %#ok<AGROW>
        parity(end + 1, 1) = parity_label(isOdd(k)); %#ok<AGROW>
        jigA(end + 1, 1) = a.JigId; %#ok<AGROW>
        jigB(end + 1, 1) = b.JigId; %#ok<AGROW>
        ampA(end + 1, 1) = a.Spectrum(k); %#ok<AGROW>
        ampB(end + 1, 1) = b.Spectrum(k); %#ok<AGROW>
        absDelta(end + 1, 1) = abs(b.Spectrum(k) - a.Spectrum(k)); %#ok<AGROW>
    end
end

detail = table(motor, order, multipleOf6, parity, jigA, jigB, ampA, ampB, absDelta, ...
    VariableNames=["Motor", "Order", "MultipleOf6", "Parity", "JigA", "JigB", ...
    "AmpA_Deg", "AmpB_Deg", "AbsDelta_Deg"]);

byParity = groupsummary(detail, "Parity", ["mean", "std"], "AbsDelta_Deg");

result = struct(Detail = detail, ByParity = byParity);

fprintf("=== Dead-time harmonic-signature test: |cross-jig delta| by parity of (order/6) ===\n");
fprintf("Prediction if dead-time distortion is real: ODD multiples of 6 (%s) show LARGER\n", ...
    strjoin(string(orders(isOdd)), ","));
fprintf("cross-jig delta than EVEN multiples (%s), which reflect motor/back-EMF structure.\n\n", ...
    strjoin(string(orders(~isOdd)), ","));
disp(byParity);
oddMean = byParity.mean_AbsDelta_Deg(byParity.Parity == "ODD");
evenMean = byParity.mean_AbsDelta_Deg(byParity.Parity == "EVEN");
if ~isempty(oddMean) && ~isempty(evenMean) && evenMean > 0
    fprintf("Odd/Even mean |delta| ratio: %.2f (>1 supports dead-time signature, <=1 does not)\n", ...
        oddMean / evenMean);
end
end

function s = parity_label(isOddValue)
if isOddValue
    s = "ODD";
else
    s = "EVEN";
end
end
