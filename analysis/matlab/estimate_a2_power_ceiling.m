function ceilingEstimate = estimate_a2_power_ceiling(safetyEnvelope)
%ESTIMATE_A2_POWER_CEILING Linear extrapolation of step/travel budget vs power.
%   Diagnostic only: a straight-line fit through the tested power levels,
%   not a physical model of the motor. It exists to flag "you are trending
%   toward the limit" earlier than discovering it by hard-gate fault at the
%   next hardware run. Never treat the crossing power as a validated safe
%   ceiling -- always confirm empirically one power step at a time, per the
%   power-envelope plan in docs/control-a2-alignment-hardware-test.md.

arguments
    safetyEnvelope table
end

stepLimitRaw = 45.0;
travelLimitDeg = 910.0*360.0/65536.0;

power = safetyEnvelope.PowerPercent;
if numel(power) < 2 || numel(unique(power)) < 2
    ceilingEstimate = struct(StepSlopeRawPerPercent=NaN, ...
        StepInterceptRaw=NaN, StepCeilingPercent=NaN, ...
        TravelSlopeDegPerPercent=NaN, TravelInterceptDeg=NaN, ...
        TravelCeilingPercent=NaN);
    return
end

stepFit = polyfit(power, safetyEnvelope.MaxStepRawAny, 1);
travelFit = polyfit(power, safetyEnvelope.MaxTravelDegAny, 1);

ceilingEstimate = struct( ...
    StepSlopeRawPerPercent=stepFit(1), StepInterceptRaw=stepFit(2), ...
    StepCeilingPercent=solve_linear_crossing(stepFit, stepLimitRaw), ...
    TravelSlopeDegPerPercent=travelFit(1), TravelInterceptDeg=travelFit(2), ...
    TravelCeilingPercent=solve_linear_crossing(travelFit, travelLimitDeg));
end

function ceiling = solve_linear_crossing(fit, limit)
slope = fit(1);
intercept = fit(2);
if slope <= 0
    ceiling = Inf;
else
    ceiling = (limit - intercept)/slope;
end
end
