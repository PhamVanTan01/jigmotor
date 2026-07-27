function result = analyze_acquisition_health(files)
%ANALYZE_ACQUISITION_HEALTH Aggregate MA600 acquisition health counters
%   (AcqReadAttempts/AcqRetries/AcqTransportErrors/AcqJumpRejects/
%   AcqFailedSamples, logged once per sweep in the NL-family META record)
%   across many raw hardware logs, to quantify how often the sensor
%   acquisition algorithm's retry/robustness machinery is actually needed
%   in practice and flag any file/session with an abnormal failure rate.

arguments
    files (1,:) string
end

file = strings(0, 1);
readAttempts = [];
retries = [];
transportErrors = [];
jumpRejects = [];
failedSamples = [];

for index = 1:numel(files)
    lines = readlines(files(index));
    metaLines = lines(startsWith(lines, "META,"));
    for lineIndex = 1:numel(metaLines)
        line = metaLines(lineIndex);
        ra = extract_field(line, "AcqReadAttempts");
        rt = extract_field(line, "AcqRetries");
        te = extract_field(line, "AcqTransportErrors");
        jr = extract_field(line, "AcqJumpRejects");
        fs = extract_field(line, "AcqFailedSamples");
        if isnan(ra)
            continue
        end
        file(end + 1, 1) = files(index); %#ok<AGROW>
        readAttempts(end + 1, 1) = ra; %#ok<AGROW>
        retries(end + 1, 1) = rt; %#ok<AGROW>
        transportErrors(end + 1, 1) = te; %#ok<AGROW>
        jumpRejects(end + 1, 1) = jr; %#ok<AGROW>
        failedSamples(end + 1, 1) = fs; %#ok<AGROW>
    end
end

if isempty(file)
    error("AcqHealth:NoSamples", "No META AcqReadAttempts fields found in the given files.");
end

runs = table(file, readAttempts, retries, transportErrors, jumpRejects, failedSamples, ...
    VariableNames=["File", "ReadAttempts", "Retries", "TransportErrors", "JumpRejects", "FailedSamples"]);
runs.RetryRate = runs.Retries ./ max(runs.ReadAttempts, 1);
runs.TransportErrorRate = runs.TransportErrors ./ max(runs.ReadAttempts, 1);
runs.JumpRejectRate = runs.JumpRejects ./ max(runs.ReadAttempts, 1);

byFile = groupsummary(runs, "File", "sum", ...
    ["ReadAttempts", "Retries", "TransportErrors", "JumpRejects", "FailedSamples"]);
byFile.RetryRate = byFile.sum_Retries ./ max(byFile.sum_ReadAttempts, 1);
byFile.TransportErrorRate = byFile.sum_TransportErrors ./ max(byFile.sum_ReadAttempts, 1);
byFile.JumpRejectRate = byFile.sum_JumpRejects ./ max(byFile.sum_ReadAttempts, 1);
byFile = sortrows(byFile, "RetryRate", "descend");

result = struct(Runs = runs, ByFile = byFile, ...
    TotalReadAttempts = sum(runs.ReadAttempts), TotalRetries = sum(runs.Retries), ...
    TotalTransportErrors = sum(runs.TransportErrors), TotalJumpRejects = sum(runs.JumpRejects), ...
    TotalFailedSamples = sum(runs.FailedSamples));

fprintf("=== MA600 acquisition health: %d sweeps across %d files ===\n", height(runs), numel(unique(runs.File)));
fprintf("Total reads=%d  retries=%d (%.4f%%)  transport errors=%d (%.4f%%)  jump rejects=%d (%.4f%%)  failed samples=%d\n", ...
    result.TotalReadAttempts, result.TotalRetries, 100 * result.TotalRetries / max(result.TotalReadAttempts, 1), ...
    result.TotalTransportErrors, 100 * result.TotalTransportErrors / max(result.TotalReadAttempts, 1), ...
    result.TotalJumpRejects, 100 * result.TotalJumpRejects / max(result.TotalReadAttempts, 1), ...
    result.TotalFailedSamples);
fprintf("-- Top 5 files by retry rate --\n");
disp(byFile(1:min(5, height(byFile)), ["File", "sum_ReadAttempts", "sum_Retries", "RetryRate", "sum_TransportErrors", "sum_JumpRejects"]));
end

function value = extract_field(line, name)
tokens = regexp(line, name + "=(\d+)", "tokens");
if isempty(tokens)
    value = NaN;
else
    value = str2double(tokens{1}{1});
end
end
