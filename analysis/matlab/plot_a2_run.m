function outputPath = plot_a2_run(metric, evidence, outputDirectory)
%PLOT_A2_RUN Export travel and command power trace for one run.

arguments
    metric table
    evidence table
    outputDirectory (1,1) string
end

if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

safeName = regexprep(metric.Run, "[^A-Za-z0-9_.-]", "_");
outputPath = fullfile(outputDirectory, safeName + ".png");

fig = figure(Visible="off", Color="white", Position=[100 100 1100 560]);
cleanup = onCleanup(@() close(fig));
sequence = double(evidence.Seq);
travelDeg = double(evidence.TravelRaw)*360.0/65536.0;
powerPercent = double(evidence.PowerPpm)/10000.0;

yyaxis left
plot(sequence, travelDeg, LineWidth=1.2, Color=[0.10 0.35 0.75]);
ylabel("Travel (mechanical deg)");
grid on

yyaxis right
plot(sequence, powerPercent, LineWidth=1.1, Color=[0.85 0.30 0.12]);
ylabel("Command power (%)");
xlabel("Sequence (1 kHz)");
title(metric.Run + " | " + metric.Profile + " | " + metric.Result, ...
    Interpreter="none");
exportgraphics(fig, outputPath, Resolution=140);
end
