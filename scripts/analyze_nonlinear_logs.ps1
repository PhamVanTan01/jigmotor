# analyze_nonlinear_logs.ps1
# Parses raw jig console logs and extracts the nonlinear measurement fields used
# by docs/nonlinear-test-plan.md.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,

    [string]$OutCsv,

    [switch]$Summary
)

$KnownJigsByUid = @{
    '003C00273234470438353535' = 'JIG1'
    '0025002C3234470438353535' = 'JIG2'
    '004C003A3034510B31363339' = 'JIG3'
    '0049003A3034510B31363339' = 'JIG4'
    '001D00283234470438353535' = 'JIG5'
    '005100323235511835383831' = 'JIG6'
    '004600323235511835383831' = 'JIG7'
    '003E00323235511835383831' = 'JIG8'
}

function Convert-ToNullableDouble {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return [double]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-RegexValues {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $matches = [regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $values = @()
    foreach ($match in $matches) {
        $values += $match.Groups[1].Value
    }
    return $values
}

function Get-NumberedRegexValues {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $table = @{}
    $matches = [regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($match in $matches) {
        $table[[int]$match.Groups[1].Value] = Convert-ToNullableDouble $match.Groups[2].Value
    }
    return $table
}

function ConvertFrom-LogKeyValueLine {
    param([string]$Line)

    $values = @{}
    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $values
    }

    foreach ($field in ($Line.Trim() -split ',')) {
        $separator = $field.IndexOf('=')
        if ($separator -le 0) {
            continue
        }
        $key = $field.Substring(0, $separator).Trim()
        $value = $field.Substring($separator + 1).Trim()
        $values[$key] = $value
    }
    return $values
}

function Get-Mean {
    param([object[]]$Values)

    $numbers = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($numbers.Count -eq 0) {
        return $null
    }

    return ($numbers | Measure-Object -Average).Average
}

function Round-Nullable {
    param(
        [object]$Value,
        [int]$Digits = 3
    )

    if ($null -eq $Value) {
        return $null
    }

    return [math]::Round([double]$Value, $Digits)
}

function Get-StdDev {
    param([object[]]$Values)

    $numbers = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($numbers.Count -le 1) {
        return 0.0
    }

    $mean = Get-Mean $numbers
    $sum = 0.0
    foreach ($number in $numbers) {
        $sum += [math]::Pow($number - $mean, 2)
    }

    return [math]::Sqrt($sum / ($numbers.Count - 1))
}

# docs/b0b-v3-no-reversal-plan.md muc 6.2 (V3.2 sector gate): reduces
# (Value - Reference) to the range [-32768, 32767] on the 16-bit raw circle,
# correctly handling the 65535->0 wrap. Uses an explicit double-mod (not
# PowerShell's/.NET's truncating %, which can return a negative remainder for
# a negative dividend) so the intermediate wrap is always a proper
# non-negative floor-mod before the final -32768 shift.
function Get-CircularDeltaRaw {
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][double]$Reference
    )

    $diff = $Value - $Reference + 32768.0
    $wrapped = (($diff % 65536.0) + 65536.0) % 65536.0
    return $wrapped - 32768.0
}

# Circular (vector) mean of raw 16-bit encoder values on the 0..65536 circle
# -- a naive arithmetic mean is wrong for any cluster straddling the
# 65535->0 wrap (e.g. {65530, 5} naively averages to ~32767, the opposite
# side of the circle, instead of the correct ~1.5). Returned in [0, 65536).
function Get-CircularMeanRaw {
    param([Parameter(Mandatory)][double[]]$Values)

    $numbers = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($numbers.Count -eq 0) {
        throw 'Get-CircularMeanRaw requires at least one value.'
    }

    $sumSin = 0.0
    $sumCos = 0.0
    foreach ($v in $numbers) {
        $angle = ($v / 65536.0) * 2.0 * [Math]::PI
        $sumSin += [Math]::Sin($angle)
        $sumCos += [Math]::Cos($angle)
    }
    $meanAngle = [Math]::Atan2($sumSin, $sumCos)
    if ($meanAngle -lt 0) { $meanAngle += 2.0 * [Math]::PI }
    return ($meanAngle / (2.0 * [Math]::PI)) * 65536.0
}

# docs/b0b-v3-no-reversal-plan.md muc 6.2, "Khoa cong thuc circular + noi suy
# theo thoi gian" -- per-run sector gate for the B leg of a V3.2 A0-B-A0
# batch. *Timestamp arrays are a common, monotonic time axis across all three
# legs; the raw UART log format captured by this project does NOT include an
# absolute wall-clock field usable across three separately-flashed/rebooted
# firmware sessions (see AnalysisStartRaw's per-line META timestamp gap noted
# in the plan) -- callers must supply one from outside this function (e.g. a
# PC-side receive timestamp recorded by the log-capture tool, or -- as a
# documented approximation only, valid if per-run duration is roughly
# constant -- the run's 1-based sequence index within its leg). This function
# does not fabricate a timestamp axis on its own.
function Get-V32SectorGateResult {
    param(
        [Parameter(Mandatory)][double[]]$A0BeforeAnalysisStartRaw,
        [Parameter(Mandatory)][double[]]$A0BeforeTimestamp,
        [Parameter(Mandatory)][double[]]$A0AfterAnalysisStartRaw,
        [Parameter(Mandatory)][double[]]$A0AfterTimestamp,
        [Parameter(Mandatory)][double[]]$BAnalysisStartRaw,
        [Parameter(Mandatory)][double[]]$BTimestamp,
        [Parameter(Mandatory)][double]$SectorToleranceRaw
    )

    if ($A0BeforeAnalysisStartRaw.Count -ne $A0BeforeTimestamp.Count) {
        throw 'A0BeforeAnalysisStartRaw and A0BeforeTimestamp must have the same count.'
    }
    if ($A0AfterAnalysisStartRaw.Count -ne $A0AfterTimestamp.Count) {
        throw 'A0AfterAnalysisStartRaw and A0AfterTimestamp must have the same count.'
    }
    if ($BAnalysisStartRaw.Count -ne $BTimestamp.Count) {
        throw 'BAnalysisStartRaw and BTimestamp must have the same count.'
    }
    if ($BAnalysisStartRaw.Count -eq 0) {
        throw 'Get-V32SectorGateResult requires at least one B run.'
    }

    # Step 1: circular mean AnalysisStartRaw + mean timestamp per bracket leg.
    $a0BeforeRef = Get-CircularMeanRaw -Values $A0BeforeAnalysisStartRaw
    $tA0BeforeRef = Get-Mean $A0BeforeTimestamp
    $a0AfterRefRaw = Get-CircularMeanRaw -Values $A0AfterAnalysisStartRaw
    $tA0AfterRef = Get-Mean $A0AfterTimestamp

    # Step 2: "unwrap" the after-bracket mean onto a continuous axis around
    # the before-bracket mean.
    $a0AfterUnwrapped = $a0BeforeRef + (Get-CircularDeltaRaw -Value $a0AfterRefRaw -Reference $a0BeforeRef)

    $tSpan = $tA0AfterRef - $tA0BeforeRef
    if ($tSpan -eq 0) {
        throw 'A0-before and A0-after mean timestamps are identical -- cannot interpolate (check the supplied timestamp axis).'
    }

    # Step 3-4: per-run linear-interpolated expected sector + circular error,
    # gated per-run (not on the batch mean) at >=90% of runs passing --
    # ceil(0.9*n) so n=10 reproduces the plan's literal ">=9/10".
    $perRun = @()
    $passCount = 0
    for ($k = 0; $k -lt $BAnalysisStartRaw.Count; $k++) {
        $frac = ($BTimestamp[$k] - $tA0BeforeRef) / $tSpan
        $expectedB = $a0BeforeRef + ($a0AfterUnwrapped - $a0BeforeRef) * $frac
        $sectorError = Get-CircularDeltaRaw -Value $BAnalysisStartRaw[$k] -Reference $expectedB
        $pass = [Math]::Abs($sectorError) -le $SectorToleranceRaw
        if ($pass) { $passCount++ }
        $perRun += [PSCustomObject]@{
            RunIndex                 = $k + 1
            ExpectedAnalysisStartRaw = $expectedB
            ObservedAnalysisStartRaw = $BAnalysisStartRaw[$k]
            SectorErrorRaw           = $sectorError
            Pass                     = $pass
        }
    }

    $n = $BAnalysisStartRaw.Count
    $requiredPassCount = [Math]::Ceiling(0.9 * $n)
    return [PSCustomObject]@{
        A0BeforeRef          = $a0BeforeRef
        A0AfterRefUnwrapped  = $a0AfterUnwrapped
        PerRun               = $perRun
        PassCount            = $passCount
        RequiredPassCount    = $requiredPassCount
        TotalCount           = $n
        GatePass             = ($passCount -ge $requiredPassCount)
    }
}

function Get-SourceMetadata {
    param([string]$FilePath)

    $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $jig = ""
    $product = ""

    $jigMatch = [regex]::Match($name, '(?i)(?:^|[_\-\s])jig[_\-\s]*([A-Za-z0-9]+)')
    if ($jigMatch.Success) {
        $jig = $jigMatch.Groups[1].Value
    }

    if ($name -match '(?i)golden') {
        $product = "Golden"
    } else {
        $productMatch = [regex]::Match($name, '(?i)(?:^|[_\-\s])(?:product|prod|motor)[_\-\s]*([A-Za-z0-9]+)')
        if ($productMatch.Success) {
            $product = $productMatch.Groups[1].Value
        } else {
            $shortProductMatch = [regex]::Match($name, '(?i)(?:^|[_\-\s])p([0-9]+)(?:$|[_\-\s])')
            if ($shortProductMatch.Success) {
                $product = "P$($shortProductMatch.Groups[1].Value)"
            }
        }
    }

    return @{
        Jig = $jig
        Product = $product
    }
}

$records = @()

foreach ($inputPath in $Path) {
    $resolvedPaths = @(Resolve-Path -Path $inputPath -ErrorAction Stop)

    foreach ($resolvedPath in $resolvedPaths) {
        $file = $resolvedPath.Path
        $metadata = Get-SourceMetadata $file
        $text = Get-Content -Raw -Path $file
        $seenStructuredRecordKeys = @{}
        $blocks = @([regex]::Split($text, '(?m)^\s*Getting result!\s*$') | Where-Object {
            $_ -match '(?m)^\s*META,|Nonlinear\s+\d+\s+Angle|Nonlinear Final Average|^\s*END,'
        })
        $runIndex = 0

        foreach ($block in $blocks) {
            $runIndex++

            $offsets = @(Get-RegexValues $block '^\s*Motor offset:\s*(-?\d+)')
            $angleOffsets = @(Get-RegexValues $block '^\s*Motor angle offset:\s*(-?\d+(?:\.\d+)?)\s*degree')
            $ma600Modes = @(Get-RegexValues $block '^\s*MA600 diagnostic mode:\s+LUT\s+([A-Z]+)')
            $metaMatch = [regex]::Match($block, '^\s*META,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $meta = if ($metaMatch.Success) {
                ConvertFrom-LogKeyValueLine ("META," + $metaMatch.Groups[1].Value)
            } else {
                @{}
            }
            $containsStructuredRecord = [regex]::IsMatch($block,
                '^\s*(?:DATA,\d|ACQ,\d|MOTION(?:_RESULT)?,|RESULT,|DIAGNOSTIC_RESULT,|PRECONDITION_RESULT,|SHADOW_(?:META|DATA|ACQ|RESULT|END),|CLOSURE_PROBE(?:_RESULT)?,|APPROACH_RESULT,|END,SchemaVersion=)',
                [System.Text.RegularExpressions.RegexOptions]::Multiline)
            if (-not $metaMatch.Success -and $containsStructuredRecord) {
                # A UART attach/detach can leave a partial structured record block. It is not
                # a measurement without its authoritative META identity and must not be
                # merged into the next batch.
                continue
            }
            $endMatch = [regex]::Match($block, '^\s*END,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $end = if ($endMatch.Success) {
                ConvertFrom-LogKeyValueLine ("END," + $endMatch.Groups[1].Value)
            } else {
                @{}
            }
            $officialResultMatch = [regex]::Match($block, '^\s*RESULT,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $diagnosticResultMatch = [regex]::Match($block, '^\s*DIAGNOSTIC_RESULT,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $resultFields = if ($officialResultMatch.Success) {
                ConvertFrom-LogKeyValueLine ("RESULT," + $officialResultMatch.Groups[1].Value)
            } elseif ($diagnosticResultMatch.Success) {
                ConvertFrom-LogKeyValueLine ("DIAGNOSTIC_RESULT," + $diagnosticResultMatch.Groups[1].Value)
            } else {
                @{}
            }
            $preconditionResultMatch = [regex]::Match($block,
                '^\s*PRECONDITION_RESULT,(.+)$',
                [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $preconditionResult = if ($preconditionResultMatch.Success) {
                ConvertFrom-LogKeyValueLine (
                    "PRECONDITION_RESULT," + $preconditionResultMatch.Groups[1].Value)
            } else {
                @{}
            }
            $shadowMetaMatch = [regex]::Match($block, '^\s*SHADOW_META,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $shadowMeta = if ($shadowMetaMatch.Success) {
                ConvertFrom-LogKeyValueLine ("SHADOW_META," + $shadowMetaMatch.Groups[1].Value)
            } else {
                @{}
            }
            $shadowResultMatch = [regex]::Match($block, '^\s*SHADOW_RESULT,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $shadowResult = if ($shadowResultMatch.Success) {
                ConvertFrom-LogKeyValueLine ("SHADOW_RESULT," + $shadowResultMatch.Groups[1].Value)
            } else {
                @{}
            }
            $shadowEndMatch = [regex]::Match($block, '^\s*SHADOW_END,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $shadowEnd = if ($shadowEndMatch.Success) {
                ConvertFrom-LogKeyValueLine ("SHADOW_END," + $shadowEndMatch.Groups[1].Value)
            } else {
                @{}
            }
            # Phase-3B0-B equal-approach diagnostic record (Official=0). Parse +
            # export only -- no validation/derivation logic here by design; the
            # offline B0BEligible gate lives in the analysis scripts that consume
            # this export, not in this parser.
            $approachResultMatch = [regex]::Match($block, '^\s*APPROACH_RESULT,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $approachResult = if ($approachResultMatch.Success) {
                ConvertFrom-LogKeyValueLine ("APPROACH_RESULT," + $approachResultMatch.Groups[1].Value)
            } else {
                @{}
            }
            $closureProbeStages = @{}
            $closureProbeMatches = [regex]::Matches($block,
                '^\s*CLOSURE_PROBE,(.+)$',
                [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($closureProbeMatch in $closureProbeMatches) {
                $probeStage = ConvertFrom-LogKeyValueLine (
                    "CLOSURE_PROBE," + $closureProbeMatch.Groups[1].Value)
                if (-not $probeStage.ContainsKey('Stage') -or
                        [string]::IsNullOrWhiteSpace($probeStage['Stage'])) {
                    throw "CLOSURE_PROBE record is missing Stage in $file."
                }
                $stageName = $probeStage['Stage']
                if ($closureProbeStages.ContainsKey($stageName)) {
                    throw "Duplicate CLOSURE_PROBE stage $stageName in $file."
                }
                $closureProbeStages[$stageName] = $probeStage
            }
            $closureProbeResultMatch = [regex]::Match($block,
                '^\s*CLOSURE_PROBE_RESULT,(.+)$',
                [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $closureProbeResult = if ($closureProbeResultMatch.Success) {
                ConvertFrom-LogKeyValueLine (
                    "CLOSURE_PROBE_RESULT," + $closureProbeResultMatch.Groups[1].Value)
            } else {
                @{}
            }
            $motionResultMatch = [regex]::Match($block, '^\s*MOTION_RESULT,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $motionResult = if ($motionResultMatch.Success) {
                ConvertFrom-LogKeyValueLine ("MOTION_RESULT," + $motionResultMatch.Groups[1].Value)
            } else {
                @{}
            }
            $metaUid = if ($meta.ContainsKey('MCU_UID')) { $meta['MCU_UID'].ToUpperInvariant() } else { "" }
            if ($KnownJigsByUid.ContainsKey($metaUid)) {
                $expectedJig = $KnownJigsByUid[$metaUid]
                if (-not $meta.ContainsKey('JigID') -or $meta['JigID'] -ne $expectedJig) {
                    throw "Known MCU UID $metaUid must map to $expectedJig, got '$($meta['JigID'])' in $file."
                }
            } elseif ($meta.ContainsKey('JigKnown') -and $meta['JigKnown'] -eq '1') {
                throw "Log marks unknown MCU UID '$metaUid' as JigKnown=1 in $file."
            }
            $testCaseProduct = $null
            $testCaseRun = $null
            $testCaseMode = $null
            $lutCompareTcMatch = [regex]::Match($block, '^\s*LUT_COMPARE_TC\s+Mode\s+(\d+)\/(\d+)\s+([A-Z]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $rawOffsetTcMatch = [regex]::Match($block, '^\s*RAW_OFFSET_TC\s+Product\s+(\d+)\/(\d+)\s+ExternalRun\s+(\d+)\/(\d+)\s+Mode=([A-Z]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            if ($lutCompareTcMatch.Success) {
                $testCaseProduct = if ([string]::IsNullOrWhiteSpace($metadata.Product)) { "Product01" } else { $metadata.Product }
                $testCaseRun = [int]$lutCompareTcMatch.Groups[1].Value
                $testCaseMode = $lutCompareTcMatch.Groups[3].Value
            } elseif ($rawOffsetTcMatch.Success) {
                $testCaseProduct = "Product$($rawOffsetTcMatch.Groups[1].Value.PadLeft(2, '0'))"
                $testCaseRun = [int]$rawOffsetTcMatch.Groups[3].Value
                $testCaseMode = $rawOffsetTcMatch.Groups[5].Value
            } else {
                $legacyRawOffsetTcMatch = [regex]::Match($block, '^\s*RAW_OFFSET_TC\s+Product\s+P(\d+)\s+ExternalRun\s+(\d+)\/(\d+)\s+Mode=([A-Z]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
                if ($legacyRawOffsetTcMatch.Success) {
                    $testCaseProduct = "Product$($legacyRawOffsetTcMatch.Groups[1].Value.PadLeft(2, '0'))"
                    $testCaseRun = [int]$legacyRawOffsetTcMatch.Groups[2].Value
                    $testCaseMode = $legacyRawOffsetTcMatch.Groups[4].Value
                }
            }
            $startDiagnostics = @([regex]::Matches($block, '^\s*MA600 start raw=(-?\d+)\s+count=(-?\d+)\s+filtered=(-?\d+(?:\.\d+)?)\s+rawAngle=(-?\d+(?:\.\d+)?)\s+degree', [System.Text.RegularExpressions.RegexOptions]::Multiline))
            $nlAngles = Get-NumberedRegexValues $block '^\s*Nonlinear\s+(\d+)\s+Angle:\s*(-?\d+(?:\.\d+)?)\s*degree'
            $rawNlAngles = Get-NumberedRegexValues $block '^\s*MA600 Raw Nonlinear\s+(\d+)\s+Angle:\s*(-?\d+(?:\.\d+)?)\s*degree'
            $filterRawDiffs = Get-NumberedRegexValues $block '^\s*MA600 Filter-Raw Max Diff\s+(\d+):\s*(-?\d+(?:\.\d+)?)\s*degree'
            $dataErrors = Get-NumberedRegexValues $block '^\s*DATA,\d+,[^,]+,[^,]+,[^,]+,[^,]+,[^,]+,(\d+),[^,]+,[^,]+,[^,]+,(-?\d+(?:\.\d+)?)'

            $finalAverageMatch = [regex]::Match($block, '^\s*Nonlinear Final Average:\s*(-?\d+(?:\.\d+)?)\s*degree', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $rawFinalAverageMatch = [regex]::Match($block, '^\s*MA600 Raw Nonlinear Final Average:\s*(-?\d+(?:\.\d+)?)\s*degree', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $powerMatch = [regex]::Match($block, '^\s*Power min CW:\s*(-?\d+(?:\.\d+)?)%', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $resultMatch = [regex]::Match($block, '^\s*Motor\s+(OK|ERROR:\s*[^!\r\n]+!?)', [System.Text.RegularExpressions.RegexOptions]::Multiline)

            $motorOffset1 = if ($offsets.Count -ge 1) { [int]$offsets[0] } else { $null }
            $motorOffset2 = if ($offsets.Count -ge 2) { [int]$offsets[1] } else { $null }
            $motorOffset3 = if ($offsets.Count -ge 3) { [int]$offsets[2] } else { $null }

            $angleOffset1 = if ($angleOffsets.Count -ge 1) { Convert-ToNullableDouble $angleOffsets[0] } else { $null }
            $angleOffset2 = if ($angleOffsets.Count -ge 2) { Convert-ToNullableDouble $angleOffsets[1] } else { $null }
            $angleOffset3 = if ($angleOffsets.Count -ge 3) { Convert-ToNullableDouble $angleOffsets[2] } else { $null }

            $startRaw = @()
            $startCount = @()
            $startFiltered = @()
            $startRawAngle = @()
            foreach ($diag in $startDiagnostics) {
                $startRaw += [int]$diag.Groups[1].Value
                $startCount += [int]$diag.Groups[2].Value
                $startFiltered += Convert-ToNullableDouble $diag.Groups[3].Value
                $startRawAngle += Convert-ToNullableDouble $diag.Groups[4].Value
            }

            $nlAvg = if ($finalAverageMatch.Success) { Convert-ToNullableDouble $finalAverageMatch.Groups[1].Value } else { Get-Mean @($nlAngles[2], $nlAngles[3]) }
            $rawNlAvg = if ($rawFinalAverageMatch.Success) { Convert-ToNullableDouble $rawFinalAverageMatch.Groups[1].Value } else { Get-Mean @($rawNlAngles[2], $rawNlAngles[3]) }
            $recordProduct = if ($null -ne $testCaseProduct) { $testCaseProduct } else { $metadata.Product }
            $metaMotorId = if ($meta.ContainsKey('MotorID')) { $meta['MotorID'] } else { "" }
            $motorIdentityConsistent = if ([string]::IsNullOrWhiteSpace($recordProduct) -or
                    [string]::IsNullOrWhiteSpace($metaMotorId)) {
                ""
            } else {
                $(if ($recordProduct.ToUpperInvariant() -eq $metaMotorId.ToUpperInvariant()) { '1' } else { '0' })
            }
            if ($meta.ContainsKey('MotorIDValid') -and $meta['MotorIDValid'] -eq '1' -and
                    ($metaMotorId -eq 'UNKNOWN' -or $metaMotorId -eq 'UNKNOWN_MOTOR' -or
                     [string]::IsNullOrWhiteSpace($metaMotorId))) {
                throw "Log claims MotorIDValid=1 for an unset MotorID in $file."
            }
            $recordRun = if ($meta.ContainsKey('RunOrder')) {
                [int]$meta['RunOrder']
            } elseif ($null -ne $testCaseRun) {
                $testCaseRun
            } else {
                $runIndex
            }
            $recordMode = if ($null -ne $testCaseMode) { $testCaseMode } elseif ($ma600Modes.Count -gt 0) { $ma600Modes[0] } else { "" }
            $recordJig = if ($meta.ContainsKey('JigID') -and -not [string]::IsNullOrWhiteSpace($meta['JigID'])) {
                $meta['JigID']
            } else {
                $metadata.Jig
            }
            $officialValid = if ($meta.ContainsKey('OfficialMeasurementValid')) {
                $meta['OfficialMeasurementValid']
            } elseif ($meta.ContainsKey('MeasurementValid')) {
                $meta['MeasurementValid']
            } else {
                ""
            }
            $schemaVersion = if ($meta.ContainsKey('SchemaVersion')) { $meta['SchemaVersion'] } else { "LEGACY" }
            $sessionId = if ($meta.ContainsKey('SessionID')) { $meta['SessionID'] } else { "BOOT_UNFRAMED" }
            $batchId = if ($meta.ContainsKey('BatchID')) { $meta['BatchID'] } else { "" }
            $testId = if ($meta.ContainsKey('TestID')) { $meta['TestID'] } else { "" }
            $sweepId = if ($meta.ContainsKey('SweepID')) { $meta['SweepID'] } else { "" }

            if ($schemaVersion -ne 'LEGACY' -and
                    -not [string]::IsNullOrWhiteSpace($testId) -and
                    -not [string]::IsNullOrWhiteSpace($sweepId)) {
                $recordKey = "$sessionId|$batchId|$testId|$sweepId"
                if ($seenStructuredRecordKeys.ContainsKey($recordKey)) {
                    throw "Duplicate structured record identity $recordKey in $file."
                }
                $seenStructuredRecordKeys[$recordKey] = $true

                foreach ($identityField in @('TestID', 'SweepID')) {
                    if ($resultFields.ContainsKey($identityField) -and
                            $resultFields[$identityField] -ne $meta[$identityField]) {
                        throw "META/$($identityField) does not match result in $file."
                    }
                    if ($end.ContainsKey($identityField) -and
                            $end[$identityField] -ne $meta[$identityField]) {
                        throw "META/$($identityField) does not match END in $file."
                    }
                }
            }

            if ($meta.ContainsKey('PreconditionProtocol')) {
                # ONE_FULL_SWEEP_120S_V1 (validated, 10 official runs) and
                # ONE_FULL_SWEEP_120S_V1_FAST3 (fast-iteration screening
                # only, 3 official runs -- see nonlinear_test.c's
                # NL_TEST_REPEAT_3_RUNS branch) share the same batch
                # structure and are both accepted here; everything else
                # about the contract below is identical between them.
                $preconditionProtocolBatchRunCounts = @{
                    'ONE_FULL_SWEEP_120S_V1' = '10'
                    'ONE_FULL_SWEEP_120S_V1_FAST3' = '3'
                }
                $observedPreconditionProtocol = $meta['PreconditionProtocol']
                if (-not $preconditionProtocolBatchRunCounts.ContainsKey($observedPreconditionProtocol)) {
                    throw "Unrecognized PreconditionProtocol=$observedPreconditionProtocol in $file."
                }
                $requiredBatchValues = @{
                    PreconditionProtocol = $observedPreconditionProtocol
                    BatchRunCount = $preconditionProtocolBatchRunCounts[$observedPreconditionProtocol]
                    ThermalProtocol = 'COOLDOWN_120S_V1'
                }
                foreach ($requiredField in $requiredBatchValues.Keys) {
                    if (-not $meta.ContainsKey($requiredField) -or
                            $meta[$requiredField] -ne $requiredBatchValues[$requiredField]) {
                        throw "Preconditioned batch META requires $requiredField=$($requiredBatchValues[$requiredField]) in $file."
                    }
                }
                foreach ($requiredField in @(
                        'BatchID', 'CycleOrder', 'RunOrder', 'RunRole',
                        'EligibleForStatistics', 'PreconditionValid', 'FirstRunInBatch',
                        'CooldownTargetMs', 'CooldownActualMs', 'CooldownValid',
                        'TimeSincePreviousRunMs')) {
                    if (-not $meta.ContainsKey($requiredField)) {
                        throw "Preconditioned batch META is missing $requiredField in $file."
                    }
                }

                $cycleOrder = [int]$meta['CycleOrder']
                $runOrder = [int]$meta['RunOrder']
                if ($meta['RunRole'] -eq 'PRECONDITION') {
                    if ($cycleOrder -ne 1 -or $runOrder -ne 0 -or
                            $meta['EligibleForStatistics'] -ne '0' -or
                            $meta['PreconditionValid'] -ne 'NA' -or
                            $meta['FirstRunInBatch'] -ne '1' -or
                            $meta['CooldownTargetMs'] -ne 'NA' -or
                            $meta['CooldownActualMs'] -ne 'NA' -or
                            $meta['CooldownValid'] -ne 'NA') {
                        throw "Invalid precondition role/eligibility/order contract in $file."
                    }
                    if (-not $preconditionResultMatch.Success) {
                        throw "Precondition cycle is missing PRECONDITION_RESULT in $file."
                    }
                    $requiredPreconditionResult = @{
                        Protocol = $observedPreconditionProtocol
                        RunRole = 'PRECONDITION'
                        EligibleForStatistics = '0'
                    }
                    foreach ($requiredField in $requiredPreconditionResult.Keys) {
                        if (-not $preconditionResult.ContainsKey($requiredField) -or
                                $preconditionResult[$requiredField] -ne
                                    $requiredPreconditionResult[$requiredField]) {
                            throw "PRECONDITION_RESULT requires $requiredField=$($requiredPreconditionResult[$requiredField]) in $file."
                        }
                    }
                    if (-not $preconditionResult.ContainsKey('Status')) {
                        throw "PRECONDITION_RESULT is missing Status in $file."
                    }
                    $preconditionResultValid =
                        ($preconditionResult['Status'] -eq 'VALID' -and
                         (-not $preconditionResult.ContainsKey('CreepIntegrityValid') -or
                          $preconditionResult['CreepIntegrityValid'] -eq '1'))
                    $preconditionResultDiagnosticInvalid =
                        ($preconditionResult['Status'] -eq 'DIAGNOSTIC_INVALID' -and
                         $preconditionResult.ContainsKey('CreepIntegrityValid') -and
                         $preconditionResult['CreepIntegrityValid'] -eq '0')
                    if (-not $preconditionResultValid -and
                            -not $preconditionResultDiagnosticInvalid) {
                        throw "PRECONDITION_RESULT has inconsistent Status/CreepIntegrityValid in $file."
                    }
                    foreach ($identityField in @('BatchID', 'CycleOrder', 'TestID')) {
                        if (-not $preconditionResult.ContainsKey($identityField) -or
                                $preconditionResult[$identityField] -ne $meta[$identityField]) {
                            throw "PRECONDITION_RESULT $identityField does not match META in $file."
                        }
                    }
                } elseif ($meta['RunRole'] -eq 'OFFICIAL') {
                    $cooldownActualMs = [int64]$meta['CooldownActualMs']
                    $timeSincePreviousRunMs = [int64]$meta['TimeSincePreviousRunMs']
                    $maxCycleOrder = 1 + [int]$requiredBatchValues['BatchRunCount']
                    $eligibilityContractValid =
                        (($meta['EligibleForStatistics'] -eq '1' -and
                          $meta['PreconditionValid'] -eq '1') -or
                         ($meta['EligibleForStatistics'] -eq '0' -and
                          ($meta['PreconditionValid'] -eq '0' -or
                           $meta['PreconditionValid'] -eq '1')))
                    if ($cycleOrder -lt 2 -or $cycleOrder -gt $maxCycleOrder -or
                            $runOrder -ne ($cycleOrder - 1) -or
                            -not $eligibilityContractValid -or
                            $meta['FirstRunInBatch'] -ne '0' -or
                            $meta['CooldownTargetMs'] -ne '120000' -or
                            $meta['CooldownValid'] -ne '1' -or
                            $cooldownActualMs -lt 120000 -or
                            $cooldownActualMs -gt 120300 -or
                            $timeSincePreviousRunMs -lt $cooldownActualMs -or
                            $preconditionResultMatch.Success) {
                        throw "Invalid official role/eligibility/order contract in $file."
                    }
                    if ($meta['EligibleForStatistics'] -eq '0' -and
                            $meta['PreconditionValid'] -eq '1' -and
                            $end.ContainsKey('Status') -and $end['Status'] -ne 'INVALID') {
                        throw "Ineligible official record with valid precondition requires END.Status=INVALID in $file."
                    }
                } else {
                    throw "Unknown preconditioned batch RunRole '$($meta['RunRole'])' in $file."
                }
            }
            if ($schemaVersion -eq '6') {
                $requiredMetaValues = @{
                    MathContractVersion = 'CANONICAL_Q16_V1'
                    SignedRoundingMode = 'NEAREST_AWAY_FROM_ZERO'
                    ReferenceDefinition = 'POINT0_CANONICAL_MEAN'
                    CanonicalMeanSource = 'ALL_TIER1'
                    MadFilteringEnabled = '0'
                    OfficialResultSource = 'CANONICAL_Q16'
                }
                foreach ($requiredField in $requiredMetaValues.Keys) {
                    if (-not $meta.ContainsKey($requiredField) -or
                            $meta[$requiredField] -ne $requiredMetaValues[$requiredField]) {
                        throw "Schema-v6 META requires $requiredField=$($requiredMetaValues[$requiredField]) in $file."
                    }
                }
                foreach ($requiredField in @(
                        'OfficialInvalidReasonMask',
                        'SettleStabilityValid',
                        'SettleTargetProximityValid',
                        'SettleValid')) {
                    if (-not $meta.ContainsKey($requiredField)) {
                        throw "Schema-v6 META is missing $requiredField in $file."
                    }
                }
                foreach ($requiredField in @(
                        'Point0MeanRawQ16',
                        'ClosureErrorRawQ16',
                        'ClosureErrorDeg',
                        'ClosureLimitDeg',
                        'ClosureValid')) {
                    if (-not $resultFields.ContainsKey($requiredField)) {
                        throw "Schema-v6 result is missing $requiredField in $file."
                    }
                }

                $hasOfficialResult = $officialResultMatch.Success
                $hasDiagnosticResult = $diagnosticResultMatch.Success
                $endStatus = if ($end.ContainsKey('Status')) { $end['Status'] } else { "" }
                if ($officialValid -eq '1') {
                    if (-not $hasOfficialResult -or $hasDiagnosticResult -or $endStatus -ne 'VALID') {
                        throw "Invalid schema-v6 official record contract in $file."
                    }
                    if ($meta['OfficialInvalidReasonMask'] -notmatch '^(?:0|0x0+)$' -or
                            $meta['SettleValid'] -ne '1' -or
                            $resultFields['ClosureValid'] -ne '1') {
                        throw "Schema-v6 official record has an invalid validity field in $file."
                    }
                } else {
                    if ($hasOfficialResult -or -not $hasDiagnosticResult -or $endStatus -ne 'INVALID') {
                        throw "Invalid schema-v6 diagnostic record contract in $file."
                    }
                    if ($meta['OfficialInvalidReasonMask'] -match '^(?:0|0x0+)$') {
                        throw "Schema-v6 invalid record requires a non-zero OfficialInvalidReasonMask in $file."
                    }
                }
            }

            if ($meta.ContainsKey('ContinuousSweepContext') -and
                    $meta['ContinuousSweepContext'] -eq 'SWEEP_CONTEXT_V1') {
                if (-not $motionResultMatch.Success) {
                    throw "Phase-3A continuous sweep record is missing MOTION_RESULT in $file."
                }
                $requiredMotionValues = @{
                    ContractVersion = 'STABILITY_AND_TARGET_V1'
                    ContinuousSweepContext = 'SWEEP_CONTEXT_V1'
                    ContextReacquireCount = '0'
                }
                foreach ($requiredField in $requiredMotionValues.Keys) {
                    if (-not $motionResult.ContainsKey($requiredField) -or
                            $motionResult[$requiredField] -ne $requiredMotionValues[$requiredField]) {
                        throw "Phase-3A MOTION_RESULT requires $requiredField=$($requiredMotionValues[$requiredField]) in $file."
                    }
                }
                foreach ($identityField in @('TestID', 'SweepID', 'JigID', 'MotorID', 'Direction')) {
                    if (-not $meta.ContainsKey($identityField) -or
                            -not $motionResult.ContainsKey($identityField) -or
                            $motionResult[$identityField] -ne $meta[$identityField]) {
                        throw "Phase-3A $identityField does not match META in $file."
                    }
                }
                foreach ($requiredField in @(
                        'SettleStabilityValid',
                        'SettleTargetProximityValid',
                        'SettleValid')) {
                    if (-not $meta.ContainsKey($requiredField) -or
                            -not $motionResult.ContainsKey($requiredField) -or
                            $motionResult[$requiredField] -ne $meta[$requiredField]) {
                        throw "Phase-3A $requiredField is missing or inconsistent in $file."
                    }
                }
                foreach ($geometryField in @('MotorPoleCount', 'MotorPolePairs', 'ElectricalRippleOrder')) {
                    if (-not $meta.ContainsKey($geometryField) -or
                            -not $resultFields.ContainsKey($geometryField) -or
                            $resultFields[$geometryField] -ne $meta[$geometryField]) {
                        throw "Phase-3A $geometryField is missing or inconsistent in $file."
                    }
                }
            }

            $shadowContractEffectiveVersion = ""
            $shadowContractLegacyAlias = '0'
            $shadowEnabled = $meta.ContainsKey('ShadowCanonicalEnabled') -and
                $meta['ShadowCanonicalEnabled'] -eq '1'
            if ($shadowEnabled) {
                if (-not $meta.ContainsKey('OfficialResultSource') -or
                        $meta['OfficialResultSource'] -ne 'LEGACY') {
                    throw "Phase-2B shadow record must keep OfficialResultSource=LEGACY in $file."
                }
                if (-not $shadowMetaMatch.Success -or -not $shadowResultMatch.Success -or
                        -not $shadowEndMatch.Success) {
                    throw "Phase-2B shadow record is missing SHADOW_META/RESULT/END in $file."
                }
                $analysisPointsForContract = if ($meta.ContainsKey('AnalysisPoints')) {
                    [int]$meta['AnalysisPoints']
                } else {
                    256
                }
                $expectedShadowContract = if ($analysisPointsForContract -eq 360) {
                    'CANONICAL_Q16_1DEG360_V2'
                } elseif ($analysisPointsForContract -eq 256) {
                    'CANONICAL_Q16_V1'
                } else {
                    throw "Unsupported shadow AnalysisPoints=$analysisPointsForContract in $file."
                }
                $observedShadowContract = if ($shadowMeta.ContainsKey('ContractVersion')) {
                    $shadowMeta['ContractVersion']
                } else {
                    ""
                }
                $historicalV1On360 = $analysisPointsForContract -eq 360 -and
                    $observedShadowContract -eq 'CANONICAL_Q16_V1'
                if ($observedShadowContract -ne $expectedShadowContract -and
                        -not $historicalV1On360) {
                    throw "Shadow ContractVersion=$observedShadowContract is incompatible with AnalysisPoints=$analysisPointsForContract in $file."
                }
                if ($meta.ContainsKey('ShadowContractVersion') -and
                        $meta['ShadowContractVersion'] -ne $observedShadowContract) {
                    throw "META.ShadowContractVersion does not match SHADOW_META.ContractVersion in $file."
                }
                $shadowContractEffectiveVersion = $expectedShadowContract
                $shadowContractLegacyAlias = if ($historicalV1On360) { '1' } else { '0' }

                $requiredShadowMeta = @{
                    Official = '0'
                    SignedConvention = 'MEASURED_MINUS_TARGET'
                    ReferenceDefinition = 'POINT0_CANONICAL_MEAN'
                    CanonicalMeanSource = 'ALL_TIER1'
                    MadFilteringEnabled = '0'
                }
                foreach ($requiredField in $requiredShadowMeta.Keys) {
                    if (-not $shadowMeta.ContainsKey($requiredField) -or
                            $shadowMeta[$requiredField] -ne $requiredShadowMeta[$requiredField]) {
                        throw "Phase-2B SHADOW_META requires $requiredField=$($requiredShadowMeta[$requiredField]) in $file."
                    }
                }
                foreach ($identityField in @('TestID', 'SweepID')) {
                    foreach ($shadowRecord in @($shadowMeta, $shadowResult, $shadowEnd)) {
                        if (-not $shadowRecord.ContainsKey($identityField) -or
                                $shadowRecord[$identityField] -ne $meta[$identityField]) {
                            throw "Phase-2B $identityField does not match META in $file."
                        }
                    }
                }
                foreach ($identityField in @('JigID', 'MotorID')) {
                    foreach ($shadowRecord in @($shadowMeta, $shadowResult, $shadowEnd)) {
                        if (-not $meta.ContainsKey($identityField) -or
                                -not $shadowRecord.ContainsKey($identityField) -or
                                $shadowRecord[$identityField] -ne $meta[$identityField]) {
                            throw "Phase-2B $identityField does not match META in $file."
                        }
                    }
                }
                if (-not $shadowResult.ContainsKey('Official') -or $shadowResult['Official'] -ne '0' -or
                        -not $shadowEnd.ContainsKey('Official') -or $shadowEnd['Official'] -ne '0') {
                    throw "Phase-2B shadow records must remain non-official in $file."
                }
                $shadowValid = $shadowResult.ContainsKey('Valid') -and $shadowResult['Valid'] -eq '1'
                $expectedShadowStatus = if ($shadowValid) { 'VALID' } else { 'INVALID' }
                if (-not $shadowEnd.ContainsKey('Status') -or
                        $shadowEnd['Status'] -ne $expectedShadowStatus) {
                    throw "Phase-2B SHADOW_END status does not match SHADOW_RESULT validity in $file."
                }
                if ($shadowValid -and (-not $shadowResult.ContainsKey('Error0RawQ16') -or
                        $shadowResult['Error0RawQ16'] -ne '0')) {
                    throw "Valid Phase-2B shadow result requires exact Error0RawQ16=0 in $file."
                }
            }

            $closureProbeDeclared = $meta.ContainsKey('ClosureProbeEnabled')
            $closureProbeEnabled = $closureProbeDeclared -and
                $meta['ClosureProbeEnabled'] -eq '1'
            if ($closureProbeDeclared) {
                if (-not $meta.ContainsKey('ClosureProbeProtocol') -or
                        $meta['ClosureProbeProtocol'] -ne 'CLOSURE_HOLD_V1' -or
                        -not $meta.ContainsKey('ClosureProbeOfficial') -or
                        $meta['ClosureProbeOfficial'] -ne '0') {
                    throw "Phase-3B0 META closure-probe contract is invalid in $file."
                }
                if (-not $closureProbeResultMatch.Success) {
                    throw "Phase-3B0 record is missing CLOSURE_PROBE_RESULT in $file."
                }

                foreach ($requiredField in @(
                        'Official', 'Protocol', 'Enabled', 'Started', 'Complete',
                        'ExpectedStages', 'AttemptedStages', 'ValidStages',
                        'PostTurnTimingComparable', 'AcquisitionResult', 'Status')) {
                    if (-not $closureProbeResult.ContainsKey($requiredField)) {
                        throw "CLOSURE_PROBE_RESULT is missing $requiredField in $file."
                    }
                }
                if ($closureProbeResult['Official'] -ne '0' -or
                        $closureProbeResult['Protocol'] -ne 'CLOSURE_HOLD_V1' -or
                        $closureProbeResult['ExpectedStages'] -ne '4') {
                    throw "Phase-3B0 result must remain Official=0 with four CLOSURE_HOLD_V1 stages in $file."
                }
                foreach ($identityField in @('TestID', 'SweepID', 'JigID', 'MotorID', 'Direction')) {
                    if (-not $meta.ContainsKey($identityField) -or
                            -not $closureProbeResult.ContainsKey($identityField) -or
                            $closureProbeResult[$identityField] -ne $meta[$identityField]) {
                        throw "Phase-3B0 result $identityField does not match META in $file."
                    }
                }

                $expectedEnabled = if ($closureProbeEnabled) { '1' } else { '0' }
                if ($closureProbeResult['Enabled'] -ne $expectedEnabled) {
                    throw "Phase-3B0 Enabled does not match META in $file."
                }
                if ([int]$closureProbeResult['AttemptedStages'] -ne $closureProbeStages.Count) {
                    throw "Phase-3B0 AttemptedStages does not match stage records in $file."
                }
                $validProbeStageCount = @($closureProbeStages.Values | Where-Object {
                    $_.ContainsKey('Valid') -and $_['Valid'] -eq '1'
                }).Count
                if ([int]$closureProbeResult['ValidStages'] -ne $validProbeStageCount) {
                    throw "Phase-3B0 ValidStages does not match stage records in $file."
                }

                if (-not $closureProbeEnabled) {
                    if ($closureProbeStages.Count -ne 0 -or
                            $closureProbeResult['Started'] -ne '0' -or
                            $closureProbeResult['Complete'] -ne '0' -or
                            $closureProbeResult['Status'] -ne 'DISABLED') {
                        throw "Disabled Phase-3B0 probe emitted an active result in $file."
                    }
                } else {
                    $probeStarted = $closureProbeResult['Started'] -eq '1'
                    $probeComplete = $closureProbeResult['Complete'] -eq '1'
                    if (($probeStarted -and $closureProbeResult['PostTurnTimingComparable'] -ne '0') -or
                            (-not $probeStarted -and
                             $closureProbeResult['PostTurnTimingComparable'] -ne '1')) {
                        throw "Phase-3B0 PostTurnTimingComparable is inconsistent in $file."
                    }
                    if (($probeStarted -and -not $closureProbeStages.ContainsKey('INITIAL')) -or
                            (-not $probeStarted -and $closureProbeStages.Count -ne 0)) {
                        throw "Phase-3B0 Started does not match its INITIAL stage in $file."
                    }
                    if ($probeComplete -and
                            ($closureProbeStages.Count -ne 4 -or
                             $validProbeStageCount -ne 4 -or
                             $closureProbeResult['AcquisitionResult'] -ne 'OK' -or
                             $closureProbeResult['Status'] -ne 'VALID')) {
                        throw "Complete Phase-3B0 probe is not a valid four-stage record in $file."
                    }
                    if (-not $probeComplete -and $closureProbeResult['Status'] -eq 'VALID') {
                        throw "Incomplete Phase-3B0 probe cannot have Status=VALID in $file."
                    }

                    $expectedNominalMs = @{
                        INITIAL = 0
                        HOLD_50 = 50
                        HOLD_100 = 100
                        HOLD_200 = 200
                    }
                    $probeCommandRaw = $null
                    $probePower = $null
                    $expectedProbePoint = if ($meta.ContainsKey('AnalysisPoints')) {
                        $meta['AnalysisPoints']
                    } elseif ($resultFields.ContainsKey('AnalysisPoints')) {
                        $resultFields['AnalysisPoints']
                    } else {
                        throw "Phase-3B0 cannot resolve the closure point from META/RESULT in $file."
                    }
                    foreach ($stageName in $closureProbeStages.Keys) {
                        $probeStage = $closureProbeStages[$stageName]
                        if (-not $expectedNominalMs.ContainsKey($stageName)) {
                            throw "Unknown Phase-3B0 stage $stageName in $file."
                        }
                        foreach ($requiredField in @(
                                'Official', 'Protocol', 'Point', 'CommandRaw', 'Power',
                                'NominalHoldMs', 'CaptureStartElapsedMs',
                                'CaptureEndElapsedMs', 'AcquisitionResult', 'Valid')) {
                            if (-not $probeStage.ContainsKey($requiredField)) {
                                throw "CLOSURE_PROBE $stageName is missing $requiredField in $file."
                            }
                        }
                        foreach ($identityField in @('TestID', 'SweepID', 'JigID', 'MotorID', 'Direction')) {
                            if (-not $meta.ContainsKey($identityField) -or
                                    -not $probeStage.ContainsKey($identityField) -or
                                    $probeStage[$identityField] -ne $meta[$identityField]) {
                                throw "CLOSURE_PROBE $stageName $identityField does not match META in $file."
                            }
                        }
                        if ($probeStage['Official'] -ne '0' -or
                                $probeStage['Protocol'] -ne 'CLOSURE_HOLD_V1' -or
                                $probeStage['Point'] -ne $expectedProbePoint -or
                                [int]$probeStage['NominalHoldMs'] -ne $expectedNominalMs[$stageName]) {
                            throw "CLOSURE_PROBE $stageName has an invalid fixed contract in $file."
                        }
                        if ($null -eq $probeCommandRaw) {
                            $probeCommandRaw = $probeStage['CommandRaw']
                            $probePower = $probeStage['Power']
                        } elseif ($probeStage['CommandRaw'] -ne $probeCommandRaw -or
                                $probeStage['Power'] -ne $probePower) {
                            throw "Phase-3B0 changed command or power during the hold in $file."
                        }

                        $captureStartMs = [uint32]$probeStage['CaptureStartElapsedMs']
                        $captureEndMs = [uint32]$probeStage['CaptureEndElapsedMs']
                        if ($captureEndMs -lt $captureStartMs -or
                                ($stageName -eq 'INITIAL' -and
                                 ($captureStartMs -ne 0 -or $captureEndMs -ne 0)) -or
                                ($stageName -ne 'INITIAL' -and
                                 $captureStartMs -lt [uint32]$expectedNominalMs[$stageName])) {
                            throw "CLOSURE_PROBE $stageName timing is invalid in $file."
                        }
                        if ($probeStage['Valid'] -eq '1') {
                            foreach ($numericField in @(
                                    'PointMeanRawQ16', 'ClosureErrorRawQ16', 'ClosureErrorDeg',
                                    'WindowP2PRaw', 'WindowP2PDeg',
                                    'WindowDriftRaw', 'WindowDriftDeg')) {
                                if (-not $probeStage.ContainsKey($numericField) -or
                                        $probeStage[$numericField] -eq 'NA') {
                                    throw "Valid CLOSURE_PROBE $stageName is missing $numericField in $file."
                                }
                            }
                            if ($probeStage['AcquisitionResult'] -ne 'OK') {
                                throw "Valid CLOSURE_PROBE $stageName has a failed acquisition in $file."
                            }
                        }
                    }

                    if ($closureProbeStages.ContainsKey('INITIAL') -and
                            $closureProbeStages['INITIAL']['Valid'] -eq '1') {
                        $initialProbe = $closureProbeStages['INITIAL']
                        if ($shadowResult.ContainsKey('ClosureErrorRawQ16') -and
                                $shadowResult['ClosureErrorRawQ16'] -ne 'NA' -and
                                $initialProbe['ClosureErrorRawQ16'] -ne
                                    $shadowResult['ClosureErrorRawQ16']) {
                            throw "Phase-3B0 INITIAL is not the exact Point-256 shadow baseline in $file."
                        }
                        if (-not $shadowResult.ContainsKey('Point0MeanRawQ16') -or
                                $shadowResult['Point0MeanRawQ16'] -eq 'NA') {
                            throw "Phase-3B0 INITIAL has no canonical Point-0 reference in $file."
                        }
                        $directionSign = if ($meta['Direction'] -eq 'CW') { 1L } else { -1L }
                        $expectedPointMean = [int64]$shadowResult['Point0MeanRawQ16'] +
                            $directionSign * 65536L * 65536L +
                            [int64]$initialProbe['ClosureErrorRawQ16']
                        if ([int64]$initialProbe['PointMeanRawQ16'] -ne $expectedPointMean) {
                            throw "Phase-3B0 INITIAL point mean is inconsistent with canonical closure math in $file."
                        }
                    }
                }
            }

            $closureErrorDeg = $null
            $closureValid = ""
            $closureMeaning = ""
            if ($resultFields.ContainsKey('ClosureErrorDeg')) {
                $closureErrorDeg = Convert-ToNullableDouble $resultFields['ClosureErrorDeg']
                $closureValid = if ($resultFields.ContainsKey('ClosureValid')) { $resultFields['ClosureValid'] } else { "" }
                $closureMeaning = if ($schemaVersion -eq '6') { 'OFFICIAL_INTEGRITY' } else { 'DIAGNOSTIC' }
            } else {
                # Legacy schema-v5 logs never carry ClosureErrorDeg on RESULT, so the closure
                # point must be resolved from the sweep's own grid size (AnalysisPoints), not
                # assumed. Pre-migration 256-raw-count-step logs close at point 256; the current
                # 1-degree grid (UNIFORM_1_DEG_ROUNDED_RAW_V1) closes at point 360. Hardcoding
                # 256 here silently mislabeled every 360-point sweep's closure as point 256's
                # ordinary mid-sweep error -- see docs/measured-and-checked-parameters.md.
                $legacyClosureIndex = if ($meta.ContainsKey('AnalysisPoints')) {
                    [int]$meta['AnalysisPoints']
                } elseif ($resultFields.ContainsKey('AnalysisPoints')) {
                    [int]$resultFields['AnalysisPoints']
                } else {
                    256
                }
                if ($null -ne $dataErrors[0] -and $null -ne $dataErrors[$legacyClosureIndex]) {
                    $closureErrorDeg = [double]$dataErrors[$legacyClosureIndex] - [double]$dataErrors[0]
                    $closureValid = if ([math]::Abs($closureErrorDeg) -le 0.20) { '1' } else { '0' }
                    $closureMeaning = 'DIAGNOSTIC_SCHEMA_V5_PILOT'
                }
            }

            # Post-turn residual (docs/b0b-v3-no-reversal-plan.md muc 4/5): points
            # 361..370 repeat mechanical angles 1..10 after one full turn. Formula is
            # locked to DATA.Error (legacy TARGET_MINUS_MEASURED, see muc 4 sign-convention
            # lock) -- must NOT be normalized against SHADOW_RESULT.ClosureErrorDeg
            # (canonical MEASURED_MINUS_TARGET, different sampling pipeline/reference).
            # Only meaningful for the current 360-point-grid protocol -- pre-migration
            # 256-point logs have no points past 264 and must not compute this.
            $postTurnAnalysisPoints = if ($meta.ContainsKey('AnalysisPoints')) {
                [int]$meta['AnalysisPoints']
            } elseif ($resultFields.ContainsKey('AnalysisPoints')) {
                [int]$resultFields['AnalysisPoints']
            } else {
                0
            }
            $postTurnCapturedPoints = if ($meta.ContainsKey('CapturedPoints')) {
                [int]$meta['CapturedPoints']
            } elseif ($resultFields.ContainsKey('CapturedPoints')) {
                [int]$resultFields['CapturedPoints']
            } else {
                0
            }
            $postTurnRepeatRmsDeg = $null
            $closureNormalizedDeltaRmsDeg = $null
            $closureNormalizedDeltaMaxAbsDeg = $null
            $postTurnAnalysisValid = '0'
            if ($postTurnAnalysisPoints -eq 360 -and $postTurnCapturedPoints -ge 371 -and
                    $officialValid -eq '1' -and $null -ne $dataErrors[0] -and
                    $null -ne $dataErrors[360]) {
                $allIndicesPresent = $true
                for ($i = 1; $i -le 10; $i++) {
                    if ($null -eq $dataErrors[$i] -or $null -eq $dataErrors[360 + $i]) {
                        $allIndicesPresent = $false
                        break
                    }
                }
                if ($allIndicesPresent) {
                    $legacyClosureForResidual = [double]$dataErrors[360] - [double]$dataErrors[0]
                    $postValues = @()
                    $normalizedValues = @()
                    for ($i = 1; $i -le 10; $i++) {
                        $post = [double]$dataErrors[360 + $i] - [double]$dataErrors[$i]
                        $postValues += $post
                        $normalizedValues += ($post - $legacyClosureForResidual)
                    }
                    $postTurnRepeatRmsDeg = [math]::Sqrt(
                        ($postValues | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum / $postValues.Count)
                    $closureNormalizedDeltaRmsDeg = [math]::Sqrt(
                        ($normalizedValues | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum / $normalizedValues.Count)
                    $closureNormalizedDeltaMaxAbsDeg = ($normalizedValues | ForEach-Object { [math]::Abs($_) } | Measure-Object -Maximum).Maximum
                    $postTurnAnalysisValid = '1'
                }
            }

            # H2 amplitude/phase -> (C2, S2) rectangular components (per user request,
            # V3.2 setup-consistency check across A0-before/B/A0-after -- mechanical
            # eccentricity/clamp harmonic, tracked as a vector so a phase shift can't hide
            # behind an unchanged amplitude). Source: RESULT.A2 (H2 amplitude, deg) and
            # RESULT.H2_PhaseSweepDeg (phase relative to sweep progress, deg). Convention:
            # C2 = A2*cos(phase), S2 = A2*sin(phase) -- an internally-consistent vector for
            # comparing runs/legs against each other; not independently validated against any
            # external phase reference, so treat cross-leg comparisons as relative, not as a
            # calibrated absolute angle.
            $h2AmplitudeDeg = if ($resultFields.ContainsKey('A2')) { Convert-ToNullableDouble $resultFields['A2'] } else { $null }
            $h2PhaseSweepDeg = if ($resultFields.ContainsKey('H2_PhaseSweepDeg')) { Convert-ToNullableDouble $resultFields['H2_PhaseSweepDeg'] } else { $null }
            $h2C = $null
            $h2S = $null
            if ($null -ne $h2AmplitudeDeg -and $null -ne $h2PhaseSweepDeg) {
                $h2PhaseRad = $h2PhaseSweepDeg * [Math]::PI / 180.0
                $h2C = $h2AmplitudeDeg * [Math]::Cos($h2PhaseRad)
                $h2S = $h2AmplitudeDeg * [Math]::Sin($h2PhaseRad)
            }

            $probeInitialDeg = if ($closureProbeStages.ContainsKey('INITIAL') -and
                    $closureProbeStages['INITIAL'].ContainsKey('ClosureErrorDeg') -and
                    $closureProbeStages['INITIAL']['ClosureErrorDeg'] -ne 'NA') {
                Convert-ToNullableDouble $closureProbeStages['INITIAL']['ClosureErrorDeg']
            } else { $null }
            $probeHold50Deg = if ($closureProbeStages.ContainsKey('HOLD_50') -and
                    $closureProbeStages['HOLD_50'].ContainsKey('ClosureErrorDeg') -and
                    $closureProbeStages['HOLD_50']['ClosureErrorDeg'] -ne 'NA') {
                Convert-ToNullableDouble $closureProbeStages['HOLD_50']['ClosureErrorDeg']
            } else { $null }
            $probeHold100Deg = if ($closureProbeStages.ContainsKey('HOLD_100') -and
                    $closureProbeStages['HOLD_100'].ContainsKey('ClosureErrorDeg') -and
                    $closureProbeStages['HOLD_100']['ClosureErrorDeg'] -ne 'NA') {
                Convert-ToNullableDouble $closureProbeStages['HOLD_100']['ClosureErrorDeg']
            } else { $null }
            $probeHold200Deg = if ($closureProbeStages.ContainsKey('HOLD_200') -and
                    $closureProbeStages['HOLD_200'].ContainsKey('ClosureErrorDeg') -and
                    $closureProbeStages['HOLD_200']['ClosureErrorDeg'] -ne 'NA') {
                Convert-ToNullableDouble $closureProbeStages['HOLD_200']['ClosureErrorDeg']
            } else { $null }

            $record = [pscustomobject]@{
                Source = [System.IO.Path]::GetFileName($file)
                SchemaVersion = $schemaVersion
                MCU_UID = if ($meta.ContainsKey('MCU_UID')) { $meta['MCU_UID'] } else { "" }
                Jig = $recordJig
                JigKnown = if ($meta.ContainsKey('JigKnown')) { $meta['JigKnown'] } else { "" }
                Product = $recordProduct
                MetaMotorID = $metaMotorId
                MotorIDSource = if ($meta.ContainsKey('MotorIDSource')) { $meta['MotorIDSource'] } else { "" }
                MotorIDValid = if ($meta.ContainsKey('MotorIDValid')) { $meta['MotorIDValid'] } else { "" }
                MotorIdentityConsistent = $motorIdentityConsistent
                MotorPoleCount = if ($meta.ContainsKey('MotorPoleCount')) { $meta['MotorPoleCount'] } else { "" }
                MotorPolePairs = if ($meta.ContainsKey('MotorPolePairs')) { $meta['MotorPolePairs'] } else { "" }
                ElectricalRippleOrder = if ($meta.ContainsKey('ElectricalRippleOrder')) { $meta['ElectricalRippleOrder'] } else { "" }
                AElectrical6 = if ($resultFields.ContainsKey('AElectrical6')) { Convert-ToNullableDouble $resultFields['AElectrical6'] } else { $null }
                ElectricalRippleValid = if ($resultFields.ContainsKey('ElectricalRippleValid')) { $resultFields['ElectricalRippleValid'] } else { "" }
                H2AmplitudeDeg = $h2AmplitudeDeg
                H2PhaseSweepDeg = $h2PhaseSweepDeg
                H2C = $h2C
                H2S = $h2S
                Run = $recordRun
                SessionID = $sessionId
                BatchID = $batchId
                CycleOrder = if ($meta.ContainsKey('CycleOrder')) { $meta['CycleOrder'] } else { "" }
                RunRole = if ($meta.ContainsKey('RunRole')) { $meta['RunRole'] } else { "" }
                EligibleForStatistics = if ($meta.ContainsKey('EligibleForStatistics')) { $meta['EligibleForStatistics'] } else { "" }
                PreconditionProtocol = if ($meta.ContainsKey('PreconditionProtocol')) { $meta['PreconditionProtocol'] } else { "" }
                PreconditionValid = if ($meta.ContainsKey('PreconditionValid')) { $meta['PreconditionValid'] } else { "" }
                BatchRunCount = if ($meta.ContainsKey('BatchRunCount')) { $meta['BatchRunCount'] } else { "" }
                ThermalProtocol = if ($meta.ContainsKey('ThermalProtocol')) { $meta['ThermalProtocol'] } else { "" }
                TestID = $testId
                SweepID = $sweepId
                MA600Mode = $recordMode
                MathContractVersion = if ($meta.ContainsKey('MathContractVersion')) { $meta['MathContractVersion'] } else { "" }
                SignedRoundingMode = if ($meta.ContainsKey('SignedRoundingMode')) { $meta['SignedRoundingMode'] } else { "" }
                CanonicalMeanSource = if ($meta.ContainsKey('CanonicalMeanSource')) { $meta['CanonicalMeanSource'] } else { "" }
                OfficialResultSource = if ($meta.ContainsKey('OfficialResultSource')) { $meta['OfficialResultSource'] } else { "" }
                ShadowCanonicalEnabled = if ($shadowEnabled) { '1' } else { '0' }
                ShadowContractVersion = if ($shadowMeta.ContainsKey('ContractVersion')) { $shadowMeta['ContractVersion'] } else { "" }
                ShadowContractEffectiveVersion = $shadowContractEffectiveVersion
                ShadowContractLegacyAlias = $shadowContractLegacyAlias
                ShadowValid = if ($shadowResult.ContainsKey('Valid')) { $shadowResult['Valid'] } else { "" }
                ShadowRMS_AC = if ($shadowResult.ContainsKey('RMS_AC')) { Convert-ToNullableDouble $shadowResult['RMS_AC'] } else { $null }
                ShadowA36 = if ($shadowResult.ContainsKey('A36')) { Convert-ToNullableDouble $shadowResult['A36'] } else { $null }
                ShadowP2P = if ($shadowResult.ContainsKey('P2P')) { Convert-ToNullableDouble $shadowResult['P2P'] } else { $null }
                ShadowClosureErrorDeg = if ($shadowResult.ContainsKey('ClosureErrorDeg')) { Convert-ToNullableDouble $shadowResult['ClosureErrorDeg'] } else { $null }
                ShadowClosureValid = if ($shadowResult.ContainsKey('ClosureValid')) { $shadowResult['ClosureValid'] } else { "" }
                ShadowLegacyMinusCanonicalRMS = if ($shadowResult.ContainsKey('LegacyMinusCanonicalRMS')) { Convert-ToNullableDouble $shadowResult['LegacyMinusCanonicalRMS'] } else { $null }
                ShadowLegacyMinusCanonicalA36 = if ($shadowResult.ContainsKey('LegacyMinusCanonicalA36')) { Convert-ToNullableDouble $shadowResult['LegacyMinusCanonicalA36'] } else { $null }
                ShadowTransactions = if ($shadowResult.ContainsKey('Transactions')) { $shadowResult['Transactions'] } else { "" }
                ShadowAcceptedSamples = if ($shadowResult.ContainsKey('AcceptedSamples')) { $shadowResult['AcceptedSamples'] } else { "" }
                ShadowFailedPoints = if ($shadowResult.ContainsKey('FailedPoints')) { $shadowResult['FailedPoints'] } else { "" }
                ShadowEndStatus = if ($shadowEnd.ContainsKey('Status')) { $shadowEnd['Status'] } else { "" }
                ClosureProbeEnabled = if ($closureProbeDeclared) { $meta['ClosureProbeEnabled'] } else { "" }
                ClosureProbeProtocol = if ($closureProbeResult.ContainsKey('Protocol')) { $closureProbeResult['Protocol'] } else { "" }
                ClosureProbeStatus = if ($closureProbeResult.ContainsKey('Status')) { $closureProbeResult['Status'] } else { "" }
                ClosureProbeComplete = if ($closureProbeResult.ContainsKey('Complete')) { $closureProbeResult['Complete'] } else { "" }
                ClosureProbeAttemptedStages = if ($closureProbeResult.ContainsKey('AttemptedStages')) { $closureProbeResult['AttemptedStages'] } else { "" }
                ClosureProbeValidStages = if ($closureProbeResult.ContainsKey('ValidStages')) { $closureProbeResult['ValidStages'] } else { "" }
                PostTurnTimingComparable = if ($closureProbeResult.ContainsKey('PostTurnTimingComparable')) { $closureProbeResult['PostTurnTimingComparable'] } else { "" }
                ClosureProbeInitialDeg = $probeInitialDeg
                ClosureProbeHold50Deg = $probeHold50Deg
                ClosureProbeHold100Deg = $probeHold100Deg
                ClosureProbeHold200Deg = $probeHold200Deg
                ClosureProbeDelta50InitialDeg = if ($null -ne $probeInitialDeg -and $null -ne $probeHold50Deg) { $probeHold50Deg - $probeInitialDeg } else { $null }
                ClosureProbeDelta100InitialDeg = if ($null -ne $probeInitialDeg -and $null -ne $probeHold100Deg) { $probeHold100Deg - $probeInitialDeg } else { $null }
                ClosureProbeDelta200InitialDeg = if ($null -ne $probeInitialDeg -and $null -ne $probeHold200Deg) { $probeHold200Deg - $probeInitialDeg } else { $null }
                ClosureProbeInitialWindowP2PRaw = if ($closureProbeStages.ContainsKey('INITIAL')) { $closureProbeStages['INITIAL']['WindowP2PRaw'] } else { "" }
                ClosureProbeHold200WindowP2PRaw = if ($closureProbeStages.ContainsKey('HOLD_200')) { $closureProbeStages['HOLD_200']['WindowP2PRaw'] } else { "" }
                ClosureProbeInitialWindowDriftRaw = if ($closureProbeStages.ContainsKey('INITIAL')) { $closureProbeStages['INITIAL']['WindowDriftRaw'] } else { "" }
                ClosureProbeHold200WindowDriftRaw = if ($closureProbeStages.ContainsKey('HOLD_200')) { $closureProbeStages['HOLD_200']['WindowDriftRaw'] } else { "" }
                ApproachProtocol = if ($meta.ContainsKey('ApproachProtocol')) { $meta['ApproachProtocol'] } else { "" }
                ApproachStructuralValid = if ($meta.ContainsKey('ApproachStructuralValid')) { $meta['ApproachStructuralValid'] } else { "" }
                ApproachStatus = if ($approachResult.ContainsKey('Status')) { $approachResult['Status'] } else { "" }
                ApproachComplete = if ($approachResult.ContainsKey('Complete')) { $approachResult['Complete'] } else { "" }
                ApproachAcquisitionClean = if ($approachResult.ContainsKey('ApproachAcquisitionClean')) { $approachResult['ApproachAcquisitionClean'] } else { "" }
                ApproachStepCountValid = if ($approachResult.ContainsKey('ApproachStepCountValid')) { $approachResult['ApproachStepCountValid'] } else { "" }
                ApproachDirectionValid = if ($approachResult.ContainsKey('ApproachDirectionValid')) { $approachResult['ApproachDirectionValid'] } else { "" }
                BackoffDirectionValid = if ($approachResult.ContainsKey('BackoffDirectionValid')) { $approachResult['BackoffDirectionValid'] } else { "" }
                ApproachObservedDeltaRaw = if ($approachResult.ContainsKey('ApproachObservedDeltaRaw')) { $approachResult['ApproachObservedDeltaRaw'] } else { "" }
                ApproachTargetErrorRaw = if ($approachResult.ContainsKey('ApproachTargetErrorRaw')) { $approachResult['ApproachTargetErrorRaw'] } else { "" }
                ApproachReturnErrorRaw = if ($approachResult.ContainsKey('ApproachReturnErrorRaw')) { $approachResult['ApproachReturnErrorRaw'] } else { "" }
                BackoffObservedDeltaRaw = if ($approachResult.ContainsKey('BackoffObservedDeltaRaw')) { $approachResult['BackoffObservedDeltaRaw'] } else { "" }
                BackoffTargetErrorRaw = if ($approachResult.ContainsKey('BackoffTargetErrorRaw')) { $approachResult['BackoffTargetErrorRaw'] } else { "" }
                ApproachMotionQualification = if ($approachResult.ContainsKey('ApproachMotionQualification')) { $approachResult['ApproachMotionQualification'] } else { "" }
                # V3 no-reversal (NL_APPROACH_MODE_NO_REVERSAL_V3, docs/b0b-v3-no-reversal-plan.md
                # muc 4b) fields -- empty/"" for V1/V2 logs (field absent from APPROACH_RESULT there).
                ApproachPath = if ($approachResult.ContainsKey('ApproachPath')) { $approachResult['ApproachPath'] } else { "" }
                ReversalCount = if ($approachResult.ContainsKey('ReversalCount')) { $approachResult['ReversalCount'] } else { "" }
                PreRollCommandDeltaRaw = if ($approachResult.ContainsKey('PreRollCommandDeltaRaw')) { Convert-ToNullableDouble $approachResult['PreRollCommandDeltaRaw'] } else { $null }
                PreRollObservedDeltaRaw = if ($approachResult.ContainsKey('PreRollObservedDeltaRaw')) { Convert-ToNullableDouble $approachResult['PreRollObservedDeltaRaw'] } else { $null }
                PreRollTargetErrorRaw = if ($approachResult.ContainsKey('PreRollTargetErrorRaw')) { Convert-ToNullableDouble $approachResult['PreRollTargetErrorRaw'] } else { $null }
                PreRollDurationMs = if ($approachResult.ContainsKey('PreRollDurationMs')) { $approachResult['PreRollDurationMs'] } else { "" }
                FinalCommandDeltaRaw = if ($approachResult.ContainsKey('FinalCommandDeltaRaw')) { Convert-ToNullableDouble $approachResult['FinalCommandDeltaRaw'] } else { $null }
                FinalObservedDeltaRaw = if ($approachResult.ContainsKey('FinalObservedDeltaRaw')) { Convert-ToNullableDouble $approachResult['FinalObservedDeltaRaw'] } else { $null }
                FinalTargetErrorRaw = if ($approachResult.ContainsKey('FinalTargetErrorRaw')) { Convert-ToNullableDouble $approachResult['FinalTargetErrorRaw'] } else { $null }
                FinalDurationMs = if ($approachResult.ContainsKey('FinalDurationMs')) { $approachResult['FinalDurationMs'] } else { "" }
                OriginShiftObservedRaw = if ($approachResult.ContainsKey('OriginShiftObservedRaw')) { Convert-ToNullableDouble $approachResult['OriginShiftObservedRaw'] } else { $null }
                OriginShiftTargetErrorRaw = if ($approachResult.ContainsKey('OriginShiftTargetErrorRaw')) { Convert-ToNullableDouble $approachResult['OriginShiftTargetErrorRaw'] } else { $null }
                InitialSettleResult = if ($approachResult.ContainsKey('InitialSettleResult')) { $approachResult['InitialSettleResult'] } else { "" }
                PreRollSettleResult = if ($approachResult.ContainsKey('PreRollSettleResult')) { $approachResult['PreRollSettleResult'] } else { "" }
                FinalSettleResult = if ($approachResult.ContainsKey('FinalSettleResult')) { $approachResult['FinalSettleResult'] } else { "" }
                # A0 (NL_APPROACH_MODE_SHIFTED_REVERSAL_A0, docs/b0b-v3-no-reversal-plan.md
                # muc 6.2/4b) local-backoff/pre-position fields -- "" / null under
                # B/V2 logs (fixed-shape record prints NA there, and PreRollSettleResult
                # is itself NA under A0 -- see PrePositionSettleResult instead).
                PrePositionSettleResult = if ($approachResult.ContainsKey('PrePositionSettleResult')) { $approachResult['PrePositionSettleResult'] } else { "" }
                LocalBackoffSettleResult = if ($approachResult.ContainsKey('LocalBackoffSettleResult')) { $approachResult['LocalBackoffSettleResult'] } else { "" }
                LocalBackoffCommandDeltaRaw = if ($approachResult.ContainsKey('LocalBackoffCommandDeltaRaw')) { Convert-ToNullableDouble $approachResult['LocalBackoffCommandDeltaRaw'] } else { $null }
                LocalBackoffObservedDeltaRaw = if ($approachResult.ContainsKey('LocalBackoffObservedDeltaRaw')) { Convert-ToNullableDouble $approachResult['LocalBackoffObservedDeltaRaw'] } else { $null }
                LocalBackoffTargetErrorRaw = if ($approachResult.ContainsKey('LocalBackoffTargetErrorRaw')) { Convert-ToNullableDouble $approachResult['LocalBackoffTargetErrorRaw'] } else { $null }
                LocalBackoffDurationMs = if ($approachResult.ContainsKey('LocalBackoffDurationMs')) { $approachResult['LocalBackoffDurationMs'] } else { "" }
                ApproachReadAttempts = if ($approachResult.ContainsKey('ApproachReadAttempts')) { $approachResult['ApproachReadAttempts'] } else { "" }
                ApproachRetries = if ($approachResult.ContainsKey('ApproachRetries')) { $approachResult['ApproachRetries'] } else { "" }
                ApproachTransportErrors = if ($approachResult.ContainsKey('ApproachTransportErrors')) { $approachResult['ApproachTransportErrors'] } else { "" }
                ApproachJumpRejects = if ($approachResult.ContainsKey('ApproachJumpRejects')) { $approachResult['ApproachJumpRejects'] } else { "" }
                ApproachFailedSamples = if ($approachResult.ContainsKey('ApproachFailedSamples')) { $approachResult['ApproachFailedSamples'] } else { "" }
                OfficialMeasurementValid = $officialValid
                OfficialInvalidReasonMask = if ($meta.ContainsKey('OfficialInvalidReasonMask')) { $meta['OfficialInvalidReasonMask'] } else { "" }
                TrackingValid = if ($meta.ContainsKey('TrackingValid')) { $meta['TrackingValid'] } else { "" }
                SettleStabilityValid = if ($meta.ContainsKey('SettleStabilityValid')) { $meta['SettleStabilityValid'] } else { "" }
                SettleTargetProximityValid = if ($meta.ContainsKey('SettleTargetProximityValid')) { $meta['SettleTargetProximityValid'] } else { "" }
                SettleValid = if ($meta.ContainsKey('SettleValid')) { $meta['SettleValid'] } else { "" }
                ContinuousSweepContext = if ($meta.ContainsKey('ContinuousSweepContext')) { $meta['ContinuousSweepContext'] } else { "" }
                RampFeedbackEnabled = if ($meta.ContainsKey('RampFeedbackEnabled')) { $meta['RampFeedbackEnabled'] } else { "" }
                ContextReacquireCount = if ($motionResult.ContainsKey('ContextReacquireCount')) { $motionResult['ContextReacquireCount'] } elseif ($meta.ContainsKey('ContextReacquireCount')) { $meta['ContextReacquireCount'] } else { "" }
                ContextReadAttempts = if ($motionResult.ContainsKey('ContextReadAttempts')) { $motionResult['ContextReadAttempts'] } else { "" }
                ContextAcceptedSamples = if ($motionResult.ContainsKey('ContextAcceptedSamples')) { $motionResult['ContextAcceptedSamples'] } else { "" }
                RampReadAttempts = if ($motionResult.ContainsKey('RampReadAttempts')) { $motionResult['RampReadAttempts'] } else { "" }
                RampAcceptedSamples = if ($motionResult.ContainsKey('RampAcceptedSamples')) { $motionResult['RampAcceptedSamples'] } else { "" }
                SettleReadAttempts = if ($motionResult.ContainsKey('SettleReadAttempts')) { $motionResult['SettleReadAttempts'] } else { "" }
                SettleAcceptedSamples = if ($motionResult.ContainsKey('SettleAcceptedSamples')) { $motionResult['SettleAcceptedSamples'] } else { "" }
                SettleTimeoutPoints = if ($motionResult.ContainsKey('SettleTimeoutPoints')) { $motionResult['SettleTimeoutPoints'] } else { "" }
                SettleWrongPositionPoints = if ($motionResult.ContainsKey('SettleWrongPositionPoints')) { $motionResult['SettleWrongPositionPoints'] } else { "" }
                MaxAbsSettlePositionErrorRaw = if ($motionResult.ContainsKey('MaxAbsSettlePositionErrorRaw')) { $motionResult['MaxAbsSettlePositionErrorRaw'] } else { "" }
                MaxAbsSettlePositionErrorDeg = if ($motionResult.ContainsKey('MaxAbsSettlePositionErrorDeg')) { Convert-ToNullableDouble $motionResult['MaxAbsSettlePositionErrorDeg'] } else { $null }
                ClosureErrorDeg = $closureErrorDeg
                ClosureLimitDeg = if ($resultFields.ContainsKey('ClosureLimitDeg')) { $resultFields['ClosureLimitDeg'] } else { "" }
                ClosureValid = $closureValid
                ClosureMeaning = $closureMeaning
                PostTurnRepeatRMSDeg = $postTurnRepeatRmsDeg
                ClosureNormalizedDeltaRMSDeg = $closureNormalizedDeltaRmsDeg
                ClosureNormalizedDeltaMaxAbsDeg = $closureNormalizedDeltaMaxAbsDeg
                PostTurnAnalysisValid = $postTurnAnalysisValid
                AnalysisStartRaw = if ($meta.ContainsKey('AnalysisStartRaw')) { Convert-ToNullableDouble $meta['AnalysisStartRaw'] } else { $null }
                AcquisitionResult = if ($meta.ContainsKey('AcquisitionResult')) { $meta['AcquisitionResult'] } else { "" }
                EndStatus = if ($end.ContainsKey('Status')) { $end['Status'] } else { "" }
                MotorOffset1 = $motorOffset1
                MotorOffset2 = $motorOffset2
                MotorOffset3 = $motorOffset3
                MotorOffsetUsedMean = Get-Mean @($motorOffset2, $motorOffset3)
                AngleOffset1 = $angleOffset1
                AngleOffset2 = $angleOffset2
                AngleOffset3 = $angleOffset3
                AngleOffsetUsedMean = Get-Mean @($angleOffset2, $angleOffset3)
                StartRaw1 = if ($startRaw.Count -ge 1) { $startRaw[0] } else { $null }
                StartRaw2 = if ($startRaw.Count -ge 2) { $startRaw[1] } else { $null }
                StartRaw3 = if ($startRaw.Count -ge 3) { $startRaw[2] } else { $null }
                StartRawUsedMean = Get-Mean @(
                    $(if ($startRaw.Count -ge 2) { $startRaw[1] } else { $null }),
                    $(if ($startRaw.Count -ge 3) { $startRaw[2] } else { $null })
                )
                StartCount1 = if ($startCount.Count -ge 1) { $startCount[0] } else { $null }
                StartCount2 = if ($startCount.Count -ge 2) { $startCount[1] } else { $null }
                StartCount3 = if ($startCount.Count -ge 3) { $startCount[2] } else { $null }
                StartCountUsedMean = Get-Mean @(
                    $(if ($startCount.Count -ge 2) { $startCount[1] } else { $null }),
                    $(if ($startCount.Count -ge 3) { $startCount[2] } else { $null })
                )
                StartFilteredUsedMean = Get-Mean @(
                    $(if ($startFiltered.Count -ge 2) { $startFiltered[1] } else { $null }),
                    $(if ($startFiltered.Count -ge 3) { $startFiltered[2] } else { $null })
                )
                StartRawAngleUsedMean = Get-Mean @(
                    $(if ($startRawAngle.Count -ge 2) { $startRawAngle[1] } else { $null }),
                    $(if ($startRawAngle.Count -ge 3) { $startRawAngle[2] } else { $null })
                )
                NL1 = $nlAngles[1]
                NL2 = $nlAngles[2]
                NL3 = $nlAngles[3]
                NLAvg = $nlAvg
                RawNL1 = $rawNlAngles[1]
                RawNL2 = $rawNlAngles[2]
                RawNL3 = $rawNlAngles[3]
                RawNLAvg = $rawNlAvg
                NLMinusRawAvg = if (($null -ne $nlAvg) -and ($null -ne $rawNlAvg)) { $nlAvg - $rawNlAvg } else { $null }
                FilterRawDiff2 = $filterRawDiffs[2]
                FilterRawDiff3 = $filterRawDiffs[3]
                FilterRawDiffUsedMax = (@($filterRawDiffs[2], $filterRawDiffs[3]) | Where-Object { $null -ne $_ } | Measure-Object -Maximum).Maximum
                PowerMinCW = if ($powerMatch.Success) { Convert-ToNullableDouble $powerMatch.Groups[1].Value } else { $null }
                Result = if ($resultMatch.Success) { $resultMatch.Groups[1].Value.Trim() } else { "" }
            }

            $records += $record
        }
    }
}

if ($records.Count -eq 0) {
    Write-Host "[FAIL] No nonlinear result blocks found."
    exit 1
}

$records |
    Sort-Object Source, Run |
    Format-Table Source, SchemaVersion, Jig, Product, CycleOrder, Run, RunRole,
        EligibleForStatistics, OfficialMeasurementValid, EndStatus, NLAvg, RawNLAvg,
        MotorOffsetUsedMean -AutoSize

if ($OutCsv) {
    $outDir = Split-Path -Parent $OutCsv
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir | Out-Null
    }

    $records | Sort-Object Source, Run | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutCsv
    Write-Host ""
    Write-Host "[ OK ] CSV written: $OutCsv"
}

if ($Summary) {
    Write-Host ""
    Write-Host "== Summary by Jig/Product =="

    $statisticsRecords = @($records | Where-Object { $_.EligibleForStatistics -ne '0' })
    $statisticsRecords |
        Group-Object Jig, Product, MA600Mode |
        ForEach-Object {
            $values = @($_.Group | ForEach-Object { $_.NLAvg } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            $rawValues = @($_.Group | ForEach-Object { $_.RawNLAvg } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            $offsetValues = @($_.Group | ForEach-Object { $_.MotorOffsetUsedMean } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            $nlMinusRawValues = @($_.Group | ForEach-Object { $_.NLMinusRawAvg } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            $min = if ($values.Count -gt 0) { ($values | Measure-Object -Minimum).Minimum } else { $null }
            $max = if ($values.Count -gt 0) { ($values | Measure-Object -Maximum).Maximum } else { $null }
            $rawMin = if ($rawValues.Count -gt 0) { ($rawValues | Measure-Object -Minimum).Minimum } else { $null }
            $rawMax = if ($rawValues.Count -gt 0) { ($rawValues | Measure-Object -Maximum).Maximum } else { $null }
            $offsetMin = if ($offsetValues.Count -gt 0) { ($offsetValues | Measure-Object -Minimum).Minimum } else { $null }
            $offsetMax = if ($offsetValues.Count -gt 0) { ($offsetValues | Measure-Object -Maximum).Maximum } else { $null }

            [pscustomobject]@{
                Jig = $_.Group[0].Jig
                Product = $_.Group[0].Product
                MA600Mode = $_.Group[0].MA600Mode
                Count = $_.Count
                NLAvgMean = Round-Nullable (Get-Mean $values)
                NLAvgRange = if (($null -ne $min) -and ($null -ne $max)) { Round-Nullable ($max - $min) } else { $null }
                NLAvgStdDev = Round-Nullable (Get-StdDev $values)
                RawNLAvgMean = Round-Nullable (Get-Mean $rawValues)
                RawNLAvgRange = if (($null -ne $rawMin) -and ($null -ne $rawMax)) { Round-Nullable ($rawMax - $rawMin) } else { $null }
                NLMinusRawMean = Round-Nullable (Get-Mean $nlMinusRawValues)
                MotorOffsetRange = if (($null -ne $offsetMin) -and ($null -ne $offsetMax)) { Round-Nullable ($offsetMax - $offsetMin) } else { $null }
            }
        } |
        Sort-Object Product, Jig, MA600Mode |
        Format-Table -AutoSize
}
