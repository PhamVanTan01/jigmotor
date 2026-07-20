param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [Alias('LogPath')]
    [string[]]$LogFiles,
    [string]$SummaryCsv,
    [string]$RawCsv,
    [string]$ExpectedProfile =
        'CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedParentProfile = 'CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1'
$ExpectedSampleCount = 2048
$ExpectedSampleRateHz = 1000
$ExpectedCaptureMs = 2048
$ExpectedCommandPhaseRaw = 0
$ExpectedPowerPpm = 350000
$ExpectedOffsetRaw = 7971
$ExpectedTransport = 'SPI_DMA_BLOCKING_WRAPPER_V1'
$ExpectedCorrCrc32 = [uint32]0x190A55AD
$PwmBinCount = 32
$TauSamples = @(1, 2, 4, 8, 16, 32, 64, 128)
$U32Modulus = 4294967296L

function Convert-A5Record {
    param([string]$Line, [int]$LineNumber)
    $tokens = $Line.Trim() -split ','
    $record = [ordered]@{
        RecordType = $tokens[0]
        LineNumber = $LineNumber
    }
    for ($i = 1; $i -lt $tokens.Count; $i++) {
        $separator = $tokens[$i].IndexOf('=')
        if ($separator -le 0) { continue }
        $record[$tokens[$i].Substring(0, $separator)] =
            $tokens[$i].Substring($separator + 1)
    }
    [pscustomobject]$record
}

function Get-RequiredField {
    param([object]$Record, [string]$Name)
    if ($null -eq $Record) { throw "Missing record while reading $Name." }
    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Missing $Name in $($Record.RecordType) at line $($Record.LineNumber)."
    }
    [string]$property.Value
}

function Get-I64 {
    param([object]$Record, [string]$Name)
    [int64](Get-RequiredField $Record $Name)
}

function Get-U32 {
    param([object]$Record, [string]$Name)
    $value = Get-RequiredField $Record $Name
    if ($value.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [Convert]::ToUInt32($value.Substring(2), 16)
    }
    [uint32]$value
}

function Resolve-A5InputFiles {
    param([string[]]$Paths)
    $files = @()
    foreach ($candidate in $Paths) {
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
                $candidate)) {
            $files += Get-ChildItem -Path $candidate -File
        } elseif (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $files += Get-Item -LiteralPath $candidate
        } else {
            throw "A5 log not found: $candidate"
        }
    }
    @($files | Sort-Object FullName -Unique)
}

function Add-Reason {
    param([System.Collections.Generic.List[string]]$Reasons, [string]$Reason)
    if (-not $Reasons.Contains($Reason)) { $Reasons.Add($Reason) }
}

function Get-SingleRecord {
    param(
        [object[]]$Records,
        [string]$RecordType,
        [System.Collections.Generic.List[string]]$Reasons
    )
    $matches = @($Records | Where-Object RecordType -eq $RecordType)
    if ($matches.Count -ne 1) {
        Add-Reason $Reasons "$RecordType-count=$($matches.Count)"
        return $null
    }
    $matches[0]
}

function Get-U32Delta {
    param([uint32]$Newer, [uint32]$Older)
    [int64]$delta = [int64]$Newer - [int64]$Older
    if ($delta -lt 0L) { $delta += $U32Modulus }
    [uint32]$delta
}

function Get-WrapDeltaRaw {
    param([int64]$Previous, [int64]$Current)
    [int64]$delta = $Current - $Previous
    if ($delta -gt 32767L) { $delta -= 65536L }
    elseif ($delta -lt -32768L) { $delta += 65536L }
    $delta
}

function Get-Crc32RawWords {
    param([int64[]]$RawWords)
    [uint64]$crc = 0xFFFFFFFFL
    foreach ($raw in $RawWords) {
        foreach ($byte in @([uint32]($raw -band 0xFFL),
                [uint32](($raw -shr 8) -band 0xFFL))) {
            $crc = ($crc -bxor [uint64]$byte) -band 0xFFFFFFFFL
            for ($bit = 0; $bit -lt 8; $bit++) {
                if (($crc -band 1L) -ne 0) {
                    $crc = (($crc -shr 1) -bxor 0xEDB88320L) -band 0xFFFFFFFFL
                } else {
                    $crc = ($crc -shr 1) -band 0xFFFFFFFFL
                }
            }
        }
    }
    [uint32](($crc -bxor 0xFFFFFFFFL) -band 0xFFFFFFFFL)
}

function Get-PopulationStdDev {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return [double]::NaN }
    [double]$sum = 0.0
    foreach ($value in $Values) { $sum += $value }
    [double]$mean = $sum / $Values.Count
    [double]$sumSquares = 0.0
    foreach ($value in $Values) {
        [double]$difference = $value - $mean
        $sumSquares += $difference * $difference
    }
    [math]::Sqrt($sumSquares / $Values.Count)
}

function Get-Rms {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return [double]::NaN }
    [double]$sumSquares = 0.0
    foreach ($value in $Values) { $sumSquares += $value * $value }
    [math]::Sqrt($sumSquares / $Values.Count)
}

function Get-Median {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return [double]::NaN }
    $sorted = @($Values | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2.0)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function Get-LinearDiagnostics {
    param([double[]]$Values)
    $count = $Values.Count
    if ($count -lt 2) {
        return [pscustomobject]@{ Slope = [double]::NaN; DetrendedSd = [double]::NaN }
    }
    [double]$meanX = ($count - 1) / 2.0
    [double]$sumY = 0.0
    foreach ($value in $Values) { $sumY += $value }
    [double]$meanY = $sumY / $count
    [double]$numerator = 0.0
    [double]$denominator = 0.0
    for ($i = 0; $i -lt $count; $i++) {
        [double]$dx = $i - $meanX
        $numerator += $dx * ($Values[$i] - $meanY)
        $denominator += $dx * $dx
    }
    [double]$slope = $numerator / $denominator
    [double]$intercept = $meanY - $slope * $meanX
    [double[]]$residuals = for ($i = 0; $i -lt $count; $i++) {
        $Values[$i] - ($intercept + $slope * $i)
    }
    [pscustomobject]@{
        Slope = $slope
        DetrendedSd = Get-PopulationStdDev $residuals
    }
}

function Get-Autocorrelation {
    param([double[]]$Values, [int]$Lag)
    if ($Lag -le 0 -or $Values.Count -le $Lag) { return [double]::NaN }
    [double]$mean = 0.0
    foreach ($value in $Values) { $mean += $value }
    $mean /= $Values.Count
    [double]$denominator = 0.0
    foreach ($value in $Values) {
        [double]$centered = $value - $mean
        $denominator += $centered * $centered
    }
    if ($denominator -eq 0.0) { return 0.0 }
    [double]$numerator = 0.0
    for ($i = 0; $i -lt $Values.Count - $Lag; $i++) {
        $numerator += ($Values[$i] - $mean) * ($Values[$i + $Lag] - $mean)
    }
    $numerator / $denominator
}

function Get-OverlappingAllanDeviation {
    param([double[]]$Values, [int]$Tau)
    if ($Tau -le 0 -or $Values.Count -lt (2 * $Tau)) {
        return [double]::NaN
    }
    [double[]]$prefix = New-Object double[] ($Values.Count + 1)
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $prefix[$i + 1] = $prefix[$i] + $Values[$i]
    }
    [double]$sumSquares = 0.0
    [int]$pairs = 0
    for ($start = 0; $start -le $Values.Count - 2 * $Tau; $start++) {
        [double]$meanA = ($prefix[$start + $Tau] - $prefix[$start]) / $Tau
        [double]$meanB = ($prefix[$start + 2 * $Tau] -
            $prefix[$start + $Tau]) / $Tau
        [double]$difference = $meanB - $meanA
        $sumSquares += $difference * $difference
        $pairs++
    }
    [math]::Sqrt(0.5 * $sumSquares / $pairs)
}

function Get-PwmDiagnostics {
    param([double[]]$Values, [int64[]]$Counters, [int64]$PeriodCounts)
    $binCounts = New-Object int[] $PwmBinCount
    $binSums = New-Object double[] $PwmBinCount
    [uint32]$mask = 0
    [double]$mean = 0.0
    foreach ($value in $Values) { $mean += $value }
    $mean /= $Values.Count
    [double]$cosProjection = 0.0
    [double]$sinProjection = 0.0
    for ($i = 0; $i -lt $Values.Count; $i++) {
        [int]$bin = [int][math]::Floor($Counters[$i] * $PwmBinCount /
            [double]$PeriodCounts)
        if ($bin -lt 0) { $bin = 0 }
        if ($bin -ge $PwmBinCount) { $bin = $PwmBinCount - 1 }
        $binCounts[$bin]++
        $binSums[$bin] += $Values[$i]
        $mask = [uint32]($mask -bor ([uint32]1 -shl $bin))
        [double]$angle = 2.0 * [math]::PI * $Counters[$i] / $PeriodCounts
        $cosProjection += ($Values[$i] - $mean) * [math]::Cos($angle)
        $sinProjection += ($Values[$i] - $mean) * [math]::Sin($angle)
    }
    $binMeans = @()
    $minimumCount = [int]::MaxValue
    for ($bin = 0; $bin -lt $PwmBinCount; $bin++) {
        if ($binCounts[$bin] -lt $minimumCount) { $minimumCount = $binCounts[$bin] }
        if ($binCounts[$bin] -gt 0) { $binMeans += $binSums[$bin] / $binCounts[$bin] }
    }
    [double]$meanRange = [double]::NaN
    if ($binMeans.Count -gt 0) {
        $measurement = $binMeans | Measure-Object -Minimum -Maximum
        $meanRange = $measurement.Maximum - $measurement.Minimum
    }
    [pscustomobject]@{
        Mask = $mask
        CoveredBins = @($binCounts | Where-Object { $_ -gt 0 }).Count
        MinimumBinCount = $minimumCount
        BinMeanRangeRaw = $meanRange
        FirstHarmonicP2PRaw = 4.0 * [math]::Sqrt(
            $cosProjection * $cosProjection + $sinProjection * $sinProjection) /
            $Values.Count
    }
}

function Assert-FieldEquals {
    param(
        [object]$Record,
        [string]$Name,
        [object]$Expected,
        [System.Collections.Generic.List[string]]$Reasons,
        [switch]$Unsigned
    )
    try {
        $actual = if ($Unsigned) { Get-U32 $Record $Name } else {
            Get-RequiredField $Record $Name
        }
        if ([string]$actual -ne [string]$Expected) {
            Add-Reason $Reasons "$($Record.RecordType).$Name=$actual/$Expected"
        }
    } catch {
        Add-Reason $Reasons "$($Record.RecordType).$Name-missing"
    }
}

$results = @()
$rawRows = @()
$physicalRun = 0
$anyInvalid = $false

try {
    $files = @(Resolve-A5InputFiles $LogFiles)
    if ($files.Count -eq 0) { throw 'No A5 log files matched.' }

    foreach ($file in $files) {
        $records = @()
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $lineNumber++
            if ($line -match '^CONTROL_A5_[A-Z]+,') {
                $records += Convert-A5Record $line $lineNumber
            }
        }
        $starts = @()
        for ($i = 0; $i -lt $records.Count; $i++) {
            if ($records[$i].RecordType -eq 'CONTROL_A5_ARMED') { $starts += $i }
        }
        if ($starts.Count -eq 0) { throw "No CONTROL_A5_ARMED record in $($file.Name)." }

        for ($blockIndex = 0; $blockIndex -lt $starts.Count; $blockIndex++) {
            $physicalRun++
            $start = $starts[$blockIndex]
            $end = if ($blockIndex + 1 -lt $starts.Count) {
                $starts[$blockIndex + 1] - 1
            } else { $records.Count - 1 }
            $block = @($records[$start..$end])
            $reasons = [System.Collections.Generic.List[string]]::new()

            $armed = Get-SingleRecord $block 'CONTROL_A5_ARMED' $reasons
            $identity = Get-SingleRecord $block 'CONTROL_A5_IDENTITY' $reasons
            $clock = Get-SingleRecord $block 'CONTROL_A5_CLOCK' $reasons
            $config = Get-SingleRecord $block 'CONTROL_A5_CONFIG' $reasons
            $summary = Get-SingleRecord $block 'CONTROL_A5_SUMMARY' $reasons
            $timing = Get-SingleRecord $block 'CONTROL_A5_TIMING' $reasons
            $health = Get-SingleRecord $block 'CONTROL_A5_HEALTH' $reasons
            $state = Get-SingleRecord $block 'CONTROL_A5_STATE' $reasons
            $runtime = Get-SingleRecord $block 'CONTROL_A5_RUNTIME' $reasons
            $data = @($block | Where-Object RecordType -eq 'CONTROL_A5_DATA')

            foreach ($record in $block) {
                Assert-FieldEquals $record 'RecordVersion' '1' $reasons
                Assert-FieldEquals $record 'Profile' $ExpectedProfile $reasons
            }
            if ($null -ne $armed) {
                Assert-FieldEquals $armed 'ParentProfile' $ExpectedParentProfile $reasons
                Assert-FieldEquals $armed 'Metric' 'MA600_ANGLE_WORD_RAW16' $reasons
                Assert-FieldEquals $armed 'SampleCount' $ExpectedSampleCount $reasons -Unsigned
                Assert-FieldEquals $armed 'SampleRateHz' $ExpectedSampleRateHz $reasons -Unsigned
                Assert-FieldEquals $armed 'CaptureMs' $ExpectedCaptureMs $reasons -Unsigned
                Assert-FieldEquals $armed 'CommandPhaseRaw' $ExpectedCommandPhaseRaw $reasons -Unsigned
                Assert-FieldEquals $armed 'PowerPpm' $ExpectedPowerPpm $reasons -Unsigned
                Assert-FieldEquals $armed 'OffsetRaw' $ExpectedOffsetRaw $reasons -Unsigned
                Assert-FieldEquals $armed 'Transport' $ExpectedTransport $reasons
                Assert-FieldEquals $armed 'Filt' '0x05' $reasons
            }
            if ($null -ne $identity) {
                Assert-FieldEquals $identity 'ParentProfile' $ExpectedParentProfile $reasons
                Assert-FieldEquals $identity 'AppProfile' $ExpectedProfile $reasons
                try {
                    if ([string]::IsNullOrWhiteSpace((Get-RequiredField $identity 'BuildSourceId'))) {
                        Add-Reason $reasons 'BuildSourceId-empty'
                    }
                } catch { Add-Reason $reasons 'BuildSourceId-missing' }
            }
            if ($null -ne $config) {
                foreach ($pair in @(
                    @('GatePolicy', 'POLICY_A_AUDIT_V1'),
                    @('ExpectedCalibrationState', 'ZERO_TABLE'),
                    @('CalibrationState', 'ZERO_TABLE'),
                    @('ConfigReadValid', '1'), @('ConfigValid', '1'),
                    @('RejectReason', 'NONE'), @('Zero', '0x0000'),
                    @('Dir', '0x00'), @('Filt', '0x05'),
                    @('Status', '0x00'), @('Prt', '0x00'),
                    @('RmapId', '0x00'), @('CorrNonZeroCount', '0'),
                    @('CorrCRC32', '0x190A55AD'))) {
                    Assert-FieldEquals $config $pair[0] $pair[1] $reasons
                }
            }
            if ($null -ne $summary) {
                Assert-FieldEquals $summary 'Result' 'OK' $reasons
                Assert-FieldEquals $summary 'MeasurementValid' '1' $reasons
                Assert-FieldEquals $summary 'InvalidReason' 'NONE' $reasons
                Assert-FieldEquals $summary 'InvalidReasonMask' '0x00000000' $reasons
            }
            if ($null -ne $health) {
                foreach ($pair in @(
                    @('ReadAttempts', $ExpectedSampleCount),
                    @('Accepted', $ExpectedSampleCount), @('Retries', 0),
                    @('TransportErrors', 0), @('JumpRejects', 0),
                    @('FailedSamples', 0), @('AcquisitionValid', 1),
                    @('TimingValid', 1), @('StaticWindowValid', 1),
                    @('RecordIntegrityValid', 1))) {
                    Assert-FieldEquals $health $pair[0] $pair[1] $reasons -Unsigned
                }
            }
            if ($null -ne $state) {
                foreach ($pair in @(
                    @('ResourcesValid', 1), @('ParentAlignmentValid', 1),
                    @('PreStateValid', 1), @('PostStateValid', 1),
                    @('CommandChanged', 0), @('PreEnabled', 1),
                    @('PrePhaseRaw', 0), @('PrePowerPpm', $ExpectedPowerPpm),
                    @('PostEnabled', 1), @('PostPhaseRaw', 0),
                    @('PostPowerPpm', $ExpectedPowerPpm), @('SafeStopValid', 1),
                    @('SafeStopEnabled', 0), @('SafeStopPhaseRaw', 0),
                    @('SafeStopPowerPpm', 0))) {
                    Assert-FieldEquals $state $pair[0] $pair[1] $reasons -Unsigned
                }
            }
            if ($null -ne $runtime) {
                try {
                    if ((Get-U32 $runtime 'FreeHeapAfterAllocation') -lt 65536) {
                        Add-Reason $reasons 'FreeHeapAfterAllocation<65536'
                    }
                    if ((Get-U32 $runtime 'ControlStackHighWaterWords') -lt 256) {
                        Add-Reason $reasons 'ControlStackHighWaterWords<256'
                    }
                } catch { Add-Reason $reasons 'RuntimeFields' }
            }

            if ($data.Count -ne $ExpectedSampleCount) {
                Add-Reason $reasons "DataCount=$($data.Count)/$ExpectedSampleCount"
            }
            $rawWords = [System.Collections.Generic.List[int64]]::new()
            $csCycles = [System.Collections.Generic.List[int64]]::new()
            $pwmCounters = [System.Collections.Generic.List[int64]]::new()
            $spiLatencies = [System.Collections.Generic.List[int64]]::new()
            for ($i = 0; $i -lt $data.Count; $i++) {
                try {
                    $index = Get-I64 $data[$i] 'Index'
                    if ($index -ne $i) { Add-Reason $reasons "IndexOrder@$i=$index" }
                    $raw = Get-I64 $data[$i] 'Raw'
                    if ($raw -lt 0L -or $raw -gt 65535L) {
                        Add-Reason $reasons "RawRange@$i=$raw"
                    }
                    $rawWords.Add($raw)
                    $csCycles.Add([int64](Get-U32 $data[$i] 'CsAssertCycle'))
                    $pwmCounters.Add((Get-I64 $data[$i] 'PwmCounterAtCs'))
                    $spiLatencies.Add((Get-I64 $data[$i] 'SpiLatencyCycles'))
                    if ((Get-I64 $data[$i] 'Attempts') -ne 1L) {
                        Add-Reason $reasons "Attempts@$i"
                    }
                    if ((Get-U32 $data[$i] 'Flags') -ne 0) {
                        Add-Reason $reasons "Flags@$i"
                    }
                } catch {
                    Add-Reason $reasons "MalformedData@$i"
                }
            }

            [double]$populationSd = [double]::NaN
            [double]$rmsRel = [double]::NaN
            [double]$median = [double]::NaN
            [double]$mad = [double]::NaN
            [double]$robustSigma = [double]::NaN
            [double]$slope = [double]::NaN
            [double]$detrendedSd = [double]::NaN
            [double]$pwmBinMeanRange = [double]::NaN
            [double]$pwmFirstHarmonic = [double]::NaN
            [int]$pwmCoveredBins = 0
            [int]$pwmMinimumBinCount = 0
            [uint32]$computedCrc = 0
            [uint32]$computedPwmMask = 0
            [int64]$minRel = 0
            [int64]$maxRel = 0
            [int64]$p2p = 0
            [int64]$drift = 0
            [int64]$meanQ16 = 0
            [int64]$maxAbsStep = 0
            [int64]$intervalMin = 0
            [int64]$intervalMax = 0
            [int64]$maxAbsScheduleError = 0
            [int64]$spiMin = 0
            [int64]$spiMax = 0
            [int64]$spiMeanRounded = 0
            $deltaHistogram = ''
            $tauValues = [ordered]@{}
            foreach ($tau in $TauSamples) {
                $tauValues["Autocorr$($tau)ms"] = [double]::NaN
                $tauValues["Allan$($tau)msRaw"] = [double]::NaN
            }

            if ($rawWords.Count -gt 0) {
                $relative = [System.Collections.Generic.List[double]]::new()
                $deltas = [System.Collections.Generic.List[int64]]::new()
                [int64]$position = 0
                $relative.Add(0.0)
                for ($i = 1; $i -lt $rawWords.Count; $i++) {
                    [int64]$delta = Get-WrapDeltaRaw $rawWords[$i - 1] $rawWords[$i]
                    $deltas.Add($delta)
                    $position += $delta
                    $relative.Add([double]$position)
                    [int64]$absDelta = [math]::Abs($delta)
                    if ($absDelta -gt $maxAbsStep) { $maxAbsStep = $absDelta }
                }
                $relativeMeasure = $relative | Measure-Object -Minimum -Maximum -Sum
                $minRel = [int64]$relativeMeasure.Minimum
                $maxRel = [int64]$relativeMeasure.Maximum
                $p2p = $maxRel - $minRel
                $drift = [int64]$relative[$relative.Count - 1]
                [int64]$sumRel = [int64]$relativeMeasure.Sum
                [int64]$scaled = $sumRel * 65536L
                [int64]$half = [int64][math]::Floor($relative.Count / 2.0)
                $meanQ16 = if ($scaled -ge 0L) {
                    [int64][math]::Floor(($scaled + $half) / [double]$relative.Count)
                } else {
                    -[int64][math]::Floor((-$scaled + $half) / [double]$relative.Count)
                }
                $computedCrc = Get-Crc32RawWords $rawWords.ToArray()
                $populationSd = Get-PopulationStdDev $relative.ToArray()
                $rmsRel = Get-Rms $relative.ToArray()
                $median = Get-Median $relative.ToArray()
                [double[]]$absoluteDeviations = @($relative | ForEach-Object {
                    [math]::Abs($_ - $median)
                })
                $mad = Get-Median $absoluteDeviations
                $robustSigma = 1.4826 * $mad
                $linear = Get-LinearDiagnostics $relative.ToArray()
                $slope = $linear.Slope
                $detrendedSd = $linear.DetrendedSd
                $deltaHistogram = (@($deltas | Group-Object | Sort-Object {
                    [int64]$_.Name
                } | ForEach-Object { "$($_.Name):$($_.Count)" })) -join ';'
                foreach ($tau in $TauSamples) {
                    $tauValues["Autocorr$($tau)ms"] =
                        Get-Autocorrelation $relative.ToArray() $tau
                    $tauValues["Allan$($tau)msRaw"] =
                        Get-OverlappingAllanDeviation $relative.ToArray() $tau
                }
            }

            [int64]$systemClockHz = 0
            [int64]$periodCycles = 0
            [int64]$pwmPeriodCounts = 0
            if ($null -ne $clock) {
                try {
                    $systemClockHz = Get-I64 $clock 'SystemClockHz'
                    $periodCycles = Get-I64 $clock 'PeriodCycles'
                    $pwmPeriodCounts = Get-I64 $clock 'PwmPeriodCounts'
                    if ($systemClockHz -le 0L -or
                            ($systemClockHz % $ExpectedSampleRateHz) -ne 0L -or
                            $periodCycles -ne [int64]($systemClockHz /
                                $ExpectedSampleRateHz) -or $pwmPeriodCounts -le 0L) {
                        Add-Reason $reasons 'ClockContract'
                    }
                } catch { Add-Reason $reasons 'ClockFields' }
            }

            if ($csCycles.Count -gt 1 -and $periodCycles -gt 0L) {
                $intervals = [System.Collections.Generic.List[int64]]::new()
                for ($i = 1; $i -lt $csCycles.Count; $i++) {
                    $intervals.Add([int64](Get-U32Delta -Newer ([uint32]$csCycles[$i]) -Older ([uint32]$csCycles[$i - 1])))
                }
                $intervalMeasure = $intervals | Measure-Object -Minimum -Maximum
                $intervalMin = [int64]$intervalMeasure.Minimum
                $intervalMax = [int64]$intervalMeasure.Maximum
                for ($i = 0; $i -lt $csCycles.Count; $i++) {
                    [int64]$offset = Get-U32Delta -Newer ([uint32]$csCycles[$i]) -Older ([uint32]$csCycles[0])
                    [int64]$errorCycles = $offset - $i * $periodCycles
                    [int64]$absError = [math]::Abs($errorCycles)
                    if ($absError -gt $maxAbsScheduleError) {
                        $maxAbsScheduleError = $absError
                    }
                }
            }
            if ($spiLatencies.Count -gt 0) {
                $spiMeasure = $spiLatencies | Measure-Object -Minimum -Maximum -Sum
                $spiMin = [int64]$spiMeasure.Minimum
                $spiMax = [int64]$spiMeasure.Maximum
                $spiMeanRounded = [int64][math]::Floor(
                    ($spiMeasure.Sum + $spiLatencies.Count / 2.0) /
                    $spiLatencies.Count)
            }
            if ($rawWords.Count -gt 0 -and
                    $pwmCounters.Count -eq $rawWords.Count -and
                    $pwmPeriodCounts -gt 0L) {
                $pwmArguments = @{
                    Values = [double[]]$relative.ToArray()
                    Counters = [int64[]]$pwmCounters.ToArray()
                    PeriodCounts = $pwmPeriodCounts
                }
                $pwm = Get-PwmDiagnostics @pwmArguments
                $computedPwmMask = $pwm.Mask
                $pwmCoveredBins = $pwm.CoveredBins
                $pwmMinimumBinCount = $pwm.MinimumBinCount
                $pwmBinMeanRange = $pwm.BinMeanRangeRaw
                $pwmFirstHarmonic = $pwm.FirstHarmonicP2PRaw
            }

            if ($null -ne $summary -and $rawWords.Count -gt 0) {
                $summaryChecks = @(
                    @('Accepted', $rawWords.Count), @('FirstRaw', $rawWords[0]),
                    @('LastRaw', $rawWords[$rawWords.Count - 1]),
                    @('MinRelRaw', $minRel), @('MaxRelRaw', $maxRel),
                    @('P2PRaw', $p2p), @('DriftRaw', $drift),
                    @('MaxAbsStepRaw', $maxAbsStep), @('MeanRelRawQ16', $meanQ16))
                foreach ($pair in $summaryChecks) {
                    try {
                        $actual = Get-I64 $summary $pair[0]
                        if ($actual -ne [int64]$pair[1]) {
                            Add-Reason $reasons "Summary.$($pair[0])=$actual/$($pair[1])"
                        }
                    } catch { Add-Reason $reasons "Summary.$($pair[0])-missing" }
                }
                try {
                    $loggedCrc = Get-U32 $summary 'RawCRC32'
                    if ($loggedCrc -ne $computedCrc) {
                        Add-Reason $reasons ('CRC=0x{0:X8}/0x{1:X8}' -f
                            $loggedCrc, $computedCrc)
                    }
                } catch { Add-Reason $reasons 'Summary.RawCRC32-missing' }
            }
            if ($null -ne $timing) {
                $timingChecks = @(
                    @('SlotsReached', $rawWords.Count), @('SkippedSlots', 0),
                    @('Overruns', 0), @('IntervalMinCycles', $intervalMin),
                    @('IntervalMaxCycles', $intervalMax),
                    @('MaxAbsScheduleErrorCycles', $maxAbsScheduleError),
                    @('SpiLatencyMinCycles', $spiMin),
                    @('SpiLatencyMaxCycles', $spiMax),
                    @('SpiLatencyMeanCycles', $spiMeanRounded))
                foreach ($pair in $timingChecks) {
                    try {
                        $actual = Get-I64 $timing $pair[0]
                        if ($actual -ne [int64]$pair[1]) {
                            Add-Reason $reasons "Timing.$($pair[0])=$actual/$($pair[1])"
                        }
                    } catch { Add-Reason $reasons "Timing.$($pair[0])-missing" }
                }
                try {
                    if ((Get-U32 $timing 'PwmPhaseBinMask') -ne $computedPwmMask) {
                        Add-Reason $reasons 'Timing.PwmPhaseBinMask'
                    }
                    if ((Get-I64 $timing 'CaptureDurationMs') -gt 2300L) {
                        Add-Reason $reasons 'Timing.CaptureDurationMs>2300'
                    }
                } catch { Add-Reason $reasons 'Timing.Metadata' }
            }
            if ($data.Count -gt 0 -and $null -ne $state) {
                $firstDataLine = ($data | Measure-Object LineNumber -Minimum).Minimum
                if ($state.LineNumber -ge $firstDataLine) {
                    Add-Reason $reasons 'DATA-before-safe-stop-state'
                }
            }

            $valid = $reasons.Count -eq 0
            if (-not $valid) { $anyInvalid = $true }
            $source = "$($file.BaseName)#$($blockIndex + 1)"
            $resultObject = [ordered]@{
                Run = $physicalRun
                Source = $source
                File = $file.FullName
                RunInFile = $blockIndex + 1
                ThermalRoleProxy = if ($blockIndex -eq 0) {
                    'FIRST_IN_FILE_COLD_CANDIDATE'
                } else { 'FOLLOWUP_WARM_CANDIDATE' }
                Valid = $valid
                Reasons = if ($valid) { 'NONE' } else { $reasons -join '|' }
                Accepted = $rawWords.Count
                FirstRaw = if ($rawWords.Count -gt 0) { $rawWords[0] } else { 0 }
                LastRaw = if ($rawWords.Count -gt 0) {
                    $rawWords[$rawWords.Count - 1]
                } else { 0 }
                MinRelRaw = $minRel
                MaxRelRaw = $maxRel
                P2PRaw = $p2p
                DriftRaw = $drift
                MeanRelRaw = $meanQ16 / 65536.0
                MeanRelRawQ16 = $meanQ16
                PopulationSdRaw = $populationSd
                RmsRelRaw = $rmsRel
                MedianRelRaw = $median
                MadRaw = $mad
                RobustSigmaRaw = $robustSigma
                SlopeRawPerSecond = $slope * $ExpectedSampleRateHz
                DetrendedSdRaw = $detrendedSd
                MaxAbsStepRaw = $maxAbsStep
                DeltaHistogram = $deltaHistogram
                RawCRC32 = ('0x{0:X8}' -f $computedCrc)
                IntervalMinCycles = $intervalMin
                IntervalMaxCycles = $intervalMax
                MaxAbsScheduleErrorCycles = $maxAbsScheduleError
                SpiLatencyMinCycles = $spiMin
                SpiLatencyMaxCycles = $spiMax
                SpiLatencyMeanCycles = $spiMeanRounded
                PwmPhaseBinMask = ('0x{0:X8}' -f $computedPwmMask)
                PwmCoveredBins = $pwmCoveredBins
                PwmMinimumBinCount = $pwmMinimumBinCount
                PwmBinMeanRangeRaw = $pwmBinMeanRange
                PwmFirstHarmonicP2PRaw = $pwmFirstHarmonic
            }
            foreach ($name in $tauValues.Keys) { $resultObject[$name] = $tauValues[$name] }
            $results += [pscustomobject]$resultObject

            for ($i = 0; $i -lt $rawWords.Count; $i++) {
                [int64]$scheduleError = 0
                if ($periodCycles -gt 0L -and $csCycles.Count -eq $rawWords.Count) {
                    $scheduleError = [int64](Get-U32Delta -Newer ([uint32]$csCycles[$i]) -Older ([uint32]$csCycles[0])) - $i * $periodCycles
                }
                [int]$pwmBin = 0
                if ($pwmPeriodCounts -gt 0L) {
                    $pwmBin = [int][math]::Floor(
                        $pwmCounters[$i] * $PwmBinCount / [double]$pwmPeriodCounts)
                    if ($pwmBin -ge $PwmBinCount) { $pwmBin = $PwmBinCount - 1 }
                }
                $rawRows += [pscustomobject][ordered]@{
                    Run = $physicalRun; Source = $source; Index = $i
                    Raw = $rawWords[$i]; RelativeRaw = $relative[$i]
                    CsAssertCycle = $csCycles[$i]
                    ScheduleErrorCycles = $scheduleError
                    PwmCounterAtCs = $pwmCounters[$i]; PwmBin = $pwmBin
                    SpiLatencyCycles = $spiLatencies[$i]
                }
            }
        }
    }

    if ($SummaryCsv) {
        $summaryParent = Split-Path -Parent $SummaryCsv
        if ($summaryParent -and -not (Test-Path -LiteralPath $summaryParent)) {
            New-Item -ItemType Directory -Path $summaryParent -Force | Out-Null
        }
        $results | Export-Csv -LiteralPath $SummaryCsv -NoTypeInformation -Encoding UTF8
    }
    if ($RawCsv) {
        $rawParent = Split-Path -Parent $RawCsv
        if ($rawParent -and -not (Test-Path -LiteralPath $rawParent)) {
            New-Item -ItemType Directory -Path $rawParent -Force | Out-Null
        }
        $rawRows | Export-Csv -LiteralPath $RawCsv -NoTypeInformation -Encoding UTF8
    }

    if (-not $Quiet) {
        foreach ($result in $results) {
            $tag = if ($result.Valid) { 'PASS' } else { 'FAIL' }
            Write-Host ("[{0}] {1}: N={2}, P2P={3} raw, SD={4:N4} raw, " +
                "drift={5} raw, detrended SD={6:N4} raw, reasons={7}" -f
                $tag, $result.Source, $result.Accepted, $result.P2PRaw,
                $result.PopulationSdRaw, $result.DriftRaw,
                $result.DetrendedSdRaw, $result.Reasons)
        }
        $validResults = @($results | Where-Object Valid)
        if ($validResults.Count -gt 0) {
            foreach ($group in @($validResults | Group-Object File)) {
                $ordered = @($group.Group | Sort-Object RunInFile)
                [double]$batchMean = ($ordered | Measure-Object MeanRelRaw -Average).Average
                Write-Host ("[DIAG] {0}: batch mean={1:N5} raw over {2} run(s)." -f
                    (Split-Path -Leaf $group.Name), $batchMean, $ordered.Count)
                if ($ordered.Count -ge 2) {
                    Write-Host ("[DIAG] {0}: first-minus-second mean={1:N5} raw. " +
                        "First-in-file is only a cold-candidate proxy." -f
                        (Split-Path -Leaf $group.Name),
                        ($ordered[0].MeanRelRaw - $ordered[1].MeanRelRaw))
                }
            }
        }
    }

    $results
    if ($anyInvalid) { exit 2 }
} catch {
    Write-Error $_
    exit 2
}
