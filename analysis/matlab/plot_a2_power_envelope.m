function outputPaths = plot_a2_power_envelope(metrics, outputDirectory)
%PLOT_A2_POWER_ENVELOPE Export batch movement and convergence plots.

arguments
    metrics table
    outputDirectory (1,1) string
end

if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

included = metrics(metrics.Included,:);
safe = included.GatePass;

fig1 = figure(Visible="off", Color="white", Position=[100 100 1000 620]);
cleanup1 = onCleanup(@() close(fig1));
scatter(included.TargetPowerPercent(safe), ...
    abs(included.FinalTravelDeg(safe)), 55, [0.10 0.55 0.25], "filled");
hold on
scatter(included.TargetPowerPercent(~safe), ...
    abs(included.FinalTravelDeg(~safe)), 70, [0.85 0.15 0.12], "x", ...
    LineWidth=1.8);
grid on
xlabel("Target power (%)");
ylabel("Absolute final travel (mechanical deg)");
legend(["Hard-gate pass","Hard-gate fault"], Location="best");
title("A2-family power envelope: movement vs command power");
movementPath = fullfile(outputDirectory, "power-vs-final-travel.png");
exportgraphics(fig1, movementPath, Resolution=160);
clear cleanup1

validSettled = safe & isfinite(included.SettledModuloRaw);
fig2 = figure(Visible="off", Color="white", Position=[100 100 1000 620]);
cleanup2 = onCleanup(@() close(fig2));
scatter(included.TargetPowerPercent(validSettled), ...
    included.SettledModuloRaw(validSettled)*360.0/65536.0, ...
    60, included.StartModuloRaw(validSettled)*360.0/65536.0, "filled");
grid on
xlabel("Target power (%)");
ylabel("Settled modulo position (mechanical deg within 60 deg cycle)");
colorbar.Label.String = "Start modulo position (mechanical deg)";
title("A2-family settled modulo convergence");
settledPath = fullfile(outputDirectory, "power-vs-settled-modulo.png");
exportgraphics(fig2, settledPath, Resolution=160);
clear cleanup2

outputPaths = [movementPath; settledPath];
end
