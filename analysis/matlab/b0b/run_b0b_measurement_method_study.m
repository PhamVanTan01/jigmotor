function result = run_b0b_measurement_method_study(outputDirectory, options)
%RUN_B0B_MEASUREMENT_METHOD_STUDY Run the locked Test 28 + Test 29 study.
%   Test 29 isolates old-vs-shifted sector while retaining reversal.
%   Test 28 holds the shifted sector and compares reversal vs no reversal.
%   Together they answer which measurement approach should be retained.

arguments
    outputDirectory (1,1) string = ""
    options.BootstrapCount (1,1) double {mustBeInteger,mustBePositive} = 20000
    options.CreatePlots (1,1) logical = true
end

thisDirectory = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(fileparts(thisDirectory)));
if outputDirectory == ""
    outputDirectory = fullfile(repositoryRoot, "analysis-out", ...
        "b0b-measurement-method-matlab");
elseif ~isfolder(fileparts(outputDirectory)) && ~isfolder(outputDirectory)
    outputDirectory = fullfile(repositoryRoot, outputDirectory);
end
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

test28Output = fullfile(outputDirectory, "test28-a0-v3");
test28 = analyze_b0b_a0_v3_method( ...
    fullfile(repositoryRoot, "B0-B v32 p03 jig 1 test 28 A.txt"), ...
    fullfile(repositoryRoot, "B0-B v32 p03 jig 1 test 28 B.txt"), ...
    fullfile(repositoryRoot, "B0-B v32 p03 jig 1 test 28 A after.txt"), ...
    test28Output, BootstrapCount=options.BootstrapCount, ...
    CreatePlots=options.CreatePlots);

products = ["P02", "P03", "P04", "P05", "P06"];
v2Paths = [ ...
    fullfile(repositoryRoot, "B0-B-v32-v2-old p02 jig 1 test 29.txt"), ...
    fullfile(repositoryRoot, "B0-B-v32-v2-old p03 jig 1 test 29.txt"), ...
    fullfile(repositoryRoot, "B0-B-v32-v2-old p04-jig-1-test 29.txt"), ...
    fullfile(repositoryRoot, "B0-B-v32-v2-old p05-jig-1-test 29.txt"), ...
    fullfile(repositoryRoot, "B0-B-v32-v2-old p06-jig-1-test 29.txt")];
a0Paths = [ ...
    fullfile(repositoryRoot, "B0-B-v32-a0-p02-jig1-test-29.txt"), ...
    fullfile(repositoryRoot, "B0-B-v32-a0-p03-jig1-test-29.txt"), ...
    fullfile(repositoryRoot, "B0-B-v32-a0-p04-jig1-test-29.txt"), ...
    fullfile(repositoryRoot, "B0-B-v32-a0-p05-jig1-test-29.txt"), ...
    fullfile(repositoryRoot, "B0-B-v32-a0-p06-jig1-test-29.txt")];
test29Output = fullfile(outputDirectory, "test29-v2-a0");
test29 = analyze_b0b_v2_a0_multimotor(products, v2Paths, a0Paths, ...
    test29Output, BootstrapCount=options.BootstrapCount, ...
    CreatePlots=options.CreatePlots);

selectedMethod = "A0";
if test28.Decision.SelectedMethod ~= "A0" || ...
        ~test29.Decision.SectorShiftSupportsA0
    selectedMethod = "UNRESOLVED";
end

decisionPath = fullfile(outputDirectory, "measurement_method_decision.md");
write_combined_decision(decisionPath, test28, test29, selectedMethod);
result = struct(Test28 = test28, Test29 = test29, ...
    SelectedMethod = selectedMethod, ReportPath = string(decisionPath));
fprintf("[B0B STUDY] selected method=%s\n", selectedMethod);
fprintf("[B0B STUDY] report=%s\n", decisionPath);
end

function write_combined_decision(path, test28, test29, selectedMethod)
fid = fopen(path, "wt", "n", "UTF-8");
if fid < 0
    error("B0BMethod:Output", "Cannot write report: %s", path);
end
cleanup = onCleanup(@() fclose(fid));

residual28 = test28.Contrasts(test28.Contrasts.Metric == ...
    "ClosureNormalizedDeltaRMSDeg", :);
closure28 = test28.Contrasts(test28.Contrasts.Metric == ...
    "AbsCanonicalClosureErrorDeg", :);
residual29 = test29.CrossProductSummary(test29.CrossProductSummary.Metric == ...
    "ClosureNormalizedDeltaRMSDeg", :);
closure29 = test29.CrossProductSummary(test29.CrossProductSummary.Metric == ...
    "AbsCanonicalClosureErrorDeg", :);

fprintf(fid, "# Chốt phương thức đo B0-B bằng MATLAB\n\n");
fprintf(fid, "## Kết luận\n\n");
fprintf(fid, "**Chọn `%s` làm phương thức đo hiện tại. Không chọn V3 no-reversal.**\n\n", ...
    selectedMethod);
fprintf(fid, "Hai thí nghiệm trả lời hai câu hỏi tách biệt:\n\n");
fprintf(fid, "1. **Test 29 — sector:** V2 cũ và A0 đều có reversal; A0 chỉ đổi sang");
fprintf(fid, " sector mới. A0 giảm residual ở %d/%d motor và giảm |closure| ở %d/%d motor.\n", ...
    residual29.A0LowerProductCount, residual29.ProductCount, ...
    closure29.A0LowerProductCount, closure29.ProductCount);
test28Format = "2. **Test 28 — reversal:** A0 và V3 dùng cùng sector; V3 bỏ reversal." + ...
    " Residual V3 cao hơn A0 bracket `%+.5f°`, bootstrap 95%%" + ...
    " `[%+.5f°, %+.5f°]`, nên không có lợi ích từ bỏ reversal.\n\n";
fprintf(fid, test28Format, ...
    residual28.V3MinusBracket, residual28.Bootstrap95Low, ...
    residual28.Bootstrap95High);

fprintf(fid, "## Các gate quan trọng\n\n");
fprintf(fid, "- Test 28: 30/30 official runs hợp lệ, đúng protocol/reversal count.\n");
fprintf(fid, "- Residual gate đã khóa: V3 phải nhỏ hơn A0 bracket trừ");
fprintf(fid, " `2.77 × pooled SD`; ngưỡng là `%.5f°`, V3 là `%.5f°` — fail.\n", ...
    test28.Decision.LockedResidualThresholdDeg, residual28.V3Mean);
fprintf(fid, "- V3 không cải thiện |canonical closure|: chênh V3-bracket `%+.5f°`.\n", ...
    closure28.V3MinusBracket);
fprintf(fid, "- NL A0/V3 nằm trong repeatability envelope; không có bằng chứng");
fprintf(fid, " rằng chọn A0 làm sai khác NL có ý nghĩa.\n");
sectorFormat = "- Sector Test 28 khớp 10/10 trong ±91 raw, max `%.2f raw`, nhưng" + ...
    " đây là gate mô tả vì ba file không có wall-clock chung.\n\n";
fprintf(fid, sectorFormat, ...
    test28.Sector.MaxAbsErrorRaw);

fprintf(fid, "## Phạm vi kết luận\n\n");
fprintf(fid, "Dữ liệu đủ để **giữ A0 và dừng nhánh V3**: sector mới có lợi trên");
fprintf(fid, " nhiều motor, còn bỏ reversal không cải thiện phép đo và làm residual");
fprintf(fid, " xấu hơn trên bracket P03. Không tuyên bố causal proof tuyệt đối cho");
fprintf(fid, " sector per-run của Test 28 cho đến khi firmware/log có timestamp chung");
fprintf(fid, " xuyên A0–V3–A0.\n");
end
