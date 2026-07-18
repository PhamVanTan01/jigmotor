function summary = load_a2_summary(summaryCsv)
%LOAD_A2_SUMMARY Load the canonical PowerShell A2-family summary CSV.

arguments
    summaryCsv (1,1) string
end

if ~isfile(summaryCsv)
    error("A2Analysis:MissingSummary", "Summary CSV not found: %s", summaryCsv);
end

summary = readtable(summaryCsv, TextType="string", ...
    VariableNamingRule="preserve");
validate_a2_schema(summary, "summary");
end
