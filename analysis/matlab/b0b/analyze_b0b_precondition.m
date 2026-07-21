function result = analyze_b0b_precondition(filePath)
%ANALYZE_B0B_PRECONDITION Summarize an adaptive-precondition batch log.
%   Reads BATCH,... lines (Core/Src/nonlinear_test.c ENABLE_AUTO_BATCH_TEST
%   path): batch-level PreconditionProtocol/PreconditionCount at START, the
%   per-cycle COOLDOWN_START lines (CycleOrder/RunOrder/RunRole -- the
%   cheapest reliable way to see how many PRECONDITION cycles actually ran,
%   since the adaptive protocol can repeat cycle 1 as RunOrder=0 multiple
%   times before the first OFFICIAL RunOrder=1), and the final
%   Status=COMPLETE line (PreconditionRunsUsed, PreconditionValid,
%   PreconditionStabilityDeltaDeg).
%
%   This reports precondition-protocol behavior only (how many precondition
%   sweeps ran, whether/how fast it stabilized). It does NOT recompute
%   RMS_AC/A36/closure measurement quality for the official runs that follow
%   -- that is scripts/analyze_nonlinear_logs.ps1's job (the official,
%   mature NL metric pipeline); join its -OutCsv output on CycleOrder/
%   RunOrder if you need to correlate precondition behavior with official
%   measurement repeatability.

arguments
    filePath (1,1) string
end

lines = readlines(filePath);
lines = lines(startsWith(lines, "BATCH,"));

startLine = lines(startsWith(lines, "BATCH,BatchID=") & contains(lines, "Status=START,"));
completeLine = lines(contains(lines, "Status=COMPLETE,"));
cooldownLines = lines(contains(lines, "Status=COOLDOWN_START,"));
unstableLine = lines(contains(lines, "Status=PRECONDITION_UNSTABLE,"));

if isempty(startLine)
    error("B0BAnalysis:NoBatchStart", "No BATCH Status=START line found in %s.", filePath);
end
startFields = parse_kv_fields(startLine(1), "BATCH,");

cycles = table();
for index = 1:numel(cooldownLines)
    fields = parse_kv_fields(cooldownLines(index), "BATCH,");
    if ~isfield(fields, "CycleOrder") || ~isfield(fields, "RunOrder") || ...
            ~isfield(fields, "RunRole")
        continue
    end
    row = table(str2double(fields.CycleOrder), str2double(fields.RunOrder), ...
        string(fields.RunRole), VariableNames=["CycleOrder","RunOrder","RunRole"]);
    if isempty(cycles)
        cycles = row;
    else
        cycles = [cycles; row]; %#ok<AGROW>
    end
end
cycles = sortrows(cycles, "CycleOrder");

preconditionCyclesObserved = sum(cycles.RunRole == "PRECONDITION");
officialCyclesObserved = sum(cycles.RunRole == "OFFICIAL");

result = struct( ...
    Path = filePath, ...
    PreconditionProtocol = string(startFields.PreconditionProtocol), ...
    DeclaredPreconditionCount = str2double(startFields.PreconditionCount), ...
    DeclaredRunCount = str2double(startFields.RunCount), ...
    Cycles = cycles, ...
    PreconditionCyclesObserved = preconditionCyclesObserved, ...
    OfficialCyclesObserved = officialCyclesObserved, ...
    Completed = ~isempty(completeLine), ...
    Unstable = ~isempty(unstableLine));

if ~isempty(completeLine)
    completeFields = parse_kv_fields(completeLine(1), "BATCH,");
    result.PreconditionRunsUsed = field_double(completeFields, "PreconditionRunsUsed");
    result.PreconditionValid = field_double(completeFields, "PreconditionValid");
    result.PreconditionStabilityDeltaDeg = field_double(completeFields, "PreconditionStabilityDeltaDeg");
end
if ~isempty(unstableLine)
    unstableFields = parse_kv_fields(unstableLine(1), "BATCH,");
    result.PreconditionMaxCount = field_double(unstableFields, "PreconditionMaxCount");
    result.PreconditionRunsUsedAtAbort = field_double(unstableFields, "PreconditionRunsUsed");
end

fprintf("=== B0-B precondition summary: %s ===\n", filePath);
fprintf("  Protocol=%s declaredPreconditionCount=%g declaredRunCount=%g\n", ...
    result.PreconditionProtocol, result.DeclaredPreconditionCount, result.DeclaredRunCount);
fprintf("  Observed cycles: precondition=%d official=%d (from COOLDOWN_START lines)\n", ...
    preconditionCyclesObserved, officialCyclesObserved);
if result.Completed
    fprintf("  COMPLETE: PreconditionRunsUsed=%g PreconditionValid=%g StabilityDeltaDeg=%g\n", ...
        result.PreconditionRunsUsed, result.PreconditionValid, result.PreconditionStabilityDeltaDeg);
end
if result.Unstable
    fprintf("  UNSTABLE: aborted after PreconditionRunsUsed=%g (max=%g)\n", ...
        result.PreconditionRunsUsedAtAbort, result.PreconditionMaxCount);
end
end

function fields = parse_kv_fields(line, prefix)
rest = extractAfter(line, strlength(prefix));
parts = split(rest, ",");
fields = struct();
for index = 1:numel(parts)
    part = parts(index);
    if strlength(part) == 0
        continue
    end
    kv = split(part, "=");
    if numel(kv) < 2
        continue
    end
    key = matlab.lang.makeValidName(strtrim(kv(1)));
    value = strtrim(strjoin(kv(2:end), "="));
    fields.(key) = value;
end
end

function value = field_double(fields, name)
if isfield(fields, name)
    value = str2double(fields.(name));
else
    value = NaN;
end
end
