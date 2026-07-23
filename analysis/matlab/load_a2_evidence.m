function [evidence, evidencePath] = load_a2_evidence(runName, evidenceDirectory)
%LOAD_A2_EVIDENCE Load evidence CSV corresponding to one summary run.

arguments
    runName (1,1) string
    evidenceDirectory (1,1) string
end

safeName = regexprep(runName, "[^A-Za-z0-9_.-]", "_");
evidencePath = fullfile(evidenceDirectory, safeName + ".csv");
if ~isfile(evidencePath)
    error("A2Analysis:MissingEvidence", ...
        "Evidence CSV for run '%s' not found: %s", runName, evidencePath);
end

evidence = readtable(evidencePath, TextType="string", ...
    VariableNamingRule="preserve");
validate_a2_schema(evidence, "evidence");
end
