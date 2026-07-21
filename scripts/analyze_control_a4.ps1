param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string[]]$LogPath,
    [string]$SummaryCsv,
    [string]$ExpectedProfile = 'CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1',
    [int64]$ExpectedOffsetRaw = 7971L
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ElectricalCycleRaw = 10923L
$PowerRampTicks = 300L
$FullSweepTicks = 2400L
$MinimumSweepTicks = 240L
$HoldTicks = 500L
$EvidenceDecimation = 3L
$AlreadyAlignedSpanRaw = 210L
$CaptureRequiredMinSpanRaw = 1000L
$FinalOffsetRangeLimitRaw = 182.0

function Convert-A4Record {
    param([string]$Line)
    $tokens = $Line.Trim() -split ','
    $record = [ordered]@{ RecordType = $tokens[0] }
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
        throw "Missing $Name in $($Record.RecordType)."
    }
    $property.Value
}

function Get-I64 {
    param([object]$Record, [string]$Name)
    [int64](Get-RequiredField $Record $Name)
}

function Normalize-Cycle {
    param([int64]$Value)
    $valueMod = $Value % $ElectricalCycleRaw
    if ($valueMod -lt 0L) { $valueMod += $ElectricalCycleRaw }
    $valueMod
}

function Get-PopulationStdDev {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return [double]::NaN }
    $mean = ($Values | Measure-Object -Average).Average
    $variance = ($Values | ForEach-Object {
        ($_ - $mean) * ($_ - $mean)
    } | Measure-Object -Average).Average
    [math]::Sqrt($variance)
}

function Get-CircularStats {
    param([double[]]$Values, [double]$Modulo)
    if ($Values.Count -eq 0) {
        return [pscustomobject]@{
            Count = 0; MeanRaw = [double]::NaN; StdRaw = [double]::NaN
            RangeRaw = [double]::NaN; R = [double]::NaN
        }
    }
    $angles = @($Values | ForEach-Object { $_ / $Modulo * 2.0 * [math]::PI })
    $sinMean = ($angles | ForEach-Object { [math]::Sin($_) } |
        Measure-Object -Average).Average
    $cosMean = ($angles | ForEach-Object { [math]::Cos($_) } |
        Measure-Object -Average).Average
    $r = [math]::Sqrt($sinMean * $sinMean + $cosMean * $cosMean)
    $meanAngle = [math]::Atan2($sinMean, $cosMean)
    if ($meanAngle -lt 0.0) { $meanAngle += 2.0 * [math]::PI }
    $meanRaw = $meanAngle / (2.0 * [math]::PI) * $Modulo
    $stdRaw = if ($r -gt 0.0) {
        [math]::Sqrt(-2.0 * [math]::Log($r)) * $Modulo / (2.0 * [math]::PI)
    } else { [double]::NaN }

    $sorted = @($Values | Sort-Object)
    $largestGap = $Modulo
    if ($sorted.Count -gt 1) {
        $largestGap = 0.0
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $next = if ($i + 1 -lt $sorted.Count) {
                $sorted[$i + 1]
            } else {
                $sorted[0] + $Modulo
            }
            $gap = $next - $sorted[$i]
            if ($gap -gt $largestGap) { $largestGap = $gap }
        }
    }

    [pscustomobject]@{
        Count = $Values.Count
        MeanRaw = $meanRaw
        StdRaw = $stdRaw
        RangeRaw = $Modulo - $largestGap
        R = $r
    }
}

function Resolve-InputFiles {
    param([string[]]$Paths)
    $files = @()
    foreach ($candidate in $Paths) {
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($candidate)) {
            $files += Get-ChildItem -Path $candidate -File
        } elseif (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $files += Get-Item -LiteralPath $candidate
        } else {
            throw "A4 log not found: $candidate"
        }
    }
    @($files | Sort-Object FullName -Unique)
}

function Get-TailP2PRaw {
    param([object[]]$Samples)
    $tail = @($Samples | Where-Object Phase -eq 'ALIGN_HOLD' | Select-Object -Last 20)
    if ($tail.Count -eq 0) { return [double]::NaN }
    $unwrapped = [System.Collections.Generic.List[double]]::new()
    $lastRaw = [int64]$tail[0].EncoderRaw
    $position = [double]$lastRaw
    $unwrapped.Add($position)
    for ($i = 1; $i -lt $tail.Count; $i++) {
        $raw = [int64]$tail[$i].EncoderRaw
        $delta = $raw - $lastRaw
        if ($delta -gt 32767L) { $delta -= 65536L }
        if ($delta -lt -32768L) { $delta += 65536L }
        $position += $delta
        $unwrapped.Add($position)
        $lastRaw = $raw
    }
    ($unwrapped | Measure-Object -Maximum).Maximum -
        ($unwrapped | Measure-Object -Minimum).Minimum
}

$files = @(Resolve-InputFiles $LogPath)
if ($files.Count -eq 0) { throw 'No A4 log files matched.' }

$results = @()
$physicalRun = 0
foreach ($file in $files) {
    $lines = @(Get-Content -LiteralPath $file.FullName | Where-Object {
        $_ -match '^CONTROL_A4_(ARMED|SUMMARY|SEQUENCE|HEALTH|DATA|RUNTIME),'
    })
    $starts = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^CONTROL_A4_ARMED,') { $starts += $i }
    }
    if ($starts.Count -eq 0) { throw "No CONTROL_A4_ARMED record in $($file.Name)." }

    for ($blockIndex = 0; $blockIndex -lt $starts.Count; $blockIndex++) {
        $physicalRun++
        $start = $starts[$blockIndex]
        $end = if ($blockIndex + 1 -lt $starts.Count) {
            $starts[$blockIndex + 1] - 1
        } else { $lines.Count - 1 }
        $records = @($lines[$start..$end] | ForEach-Object { Convert-A4Record $_ })
        $armed = @($records | Where-Object RecordType -eq 'CONTROL_A4_ARMED') | Select-Object -Last 1
        $summary = @($records | Where-Object RecordType -eq 'CONTROL_A4_SUMMARY') | Select-Object -Last 1
        $sequence = @($records | Where-Object RecordType -eq 'CONTROL_A4_SEQUENCE') | Select-Object -Last 1
        $health = @($records | Where-Object RecordType -eq 'CONTROL_A4_HEALTH') | Select-Object -Last 1
        $dataRecords = @($records | Where-Object RecordType -eq 'CONTROL_A4_DATA')

        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($null -eq $summary) { throw "Missing A4 summary in $($file.Name) block $($blockIndex + 1)." }
        if ((Get-RequiredField $summary 'Profile') -ne $ExpectedProfile) { $reasons.Add('Profile') }
        if ((Get-RequiredField $summary 'Result') -ne 'OK') { $reasons.Add("Result=$(Get-RequiredField $summary 'Result')") }

        $baselineRaw = Get-I64 $summary 'BaselineRaw'
        $seedRaw = Get-I64 $summary 'SeedPhaseRaw'
        $spanRaw = Get-I64 $summary 'SweepSpanRaw'
        $sweepTicks = Get-I64 $summary 'SweepTicks'
        $captureRequired = Get-I64 $summary 'CaptureRequired'
        $captureDetected = Get-I64 $summary 'CaptureDetected'
        $finalOffset = Get-I64 $summary 'ElectricalOffsetRaw'
        $rampCreepRaw = Get-I64 $summary 'RampCreepRaw'
        $activeDuration = Get-I64 $summary 'ActiveDurationMs'
        $loggedEvidenceCount = Get-I64 $summary 'EvidenceCount'

        $expectedSeed = Normalize-Cycle (($baselineRaw % $ElectricalCycleRaw) - $ExpectedOffsetRaw)
        $expectedSpan = Normalize-Cycle ($ElectricalCycleRaw - $expectedSeed)
        $expectedSweepTicks = if ($expectedSpan -eq 0L) {
            0L
        } else {
            # Match C integer division exactly. PowerShell casts a fractional
            # double with rounding, while uint64_t division truncates.
            $proportional = [int64][math]::Floor(($FullSweepTicks * $expectedSpan +
                [int64]($ElectricalCycleRaw / 2L)) / [double]$ElectricalCycleRaw)
            if ($proportional -lt $MinimumSweepTicks) { $MinimumSweepTicks } else { $proportional }
        }
        $expectedTotalTicks = $PowerRampTicks + $expectedSweepTicks + $HoldTicks
        $expectedEvidenceCount = [int64][math]::Floor(
            $expectedTotalTicks / [double]$EvidenceDecimation) + 1L
        if (($expectedTotalTicks % $EvidenceDecimation) -ne 0L) { $expectedEvidenceCount++ }

        if ($seedRaw -ne $expectedSeed) { $reasons.Add("Seed=$seedRaw/$expectedSeed") }
        if ($spanRaw -ne $expectedSpan) { $reasons.Add("Span=$spanRaw/$expectedSpan") }
        if ($sweepTicks -ne $expectedSweepTicks) { $reasons.Add("SweepTicks=$sweepTicks/$expectedSweepTicks") }
        # HAL_GetTick() is sampled on opposite sides of the first/last loop
        # work, so a completed run can legitimately report nominal or
        # nominal-1 ms while every scheduled deadline is still exact.
        if ([math]::Abs($activeDuration - $expectedTotalTicks) -gt 1L) {
            $reasons.Add("Duration=$activeDuration/$expectedTotalTicks")
        }
        if ($loggedEvidenceCount -ne $expectedEvidenceCount) { $reasons.Add("Evidence=$loggedEvidenceCount/$expectedEvidenceCount") }
        if ($dataRecords.Count -ne $loggedEvidenceCount) { $reasons.Add("Data=$($dataRecords.Count)/$loggedEvidenceCount") }
        if ($captureRequired -eq 1L -and $captureDetected -ne 1L) { $reasons.Add('CaptureRequiredButMissing') }
        if ((Get-I64 $summary 'AlreadyAligned') -ne [int64]($spanRaw -le $AlreadyAlignedSpanRaw)) { $reasons.Add('AlreadyAligned') }
        if ($captureRequired -ne [int64]($spanRaw -ge $CaptureRequiredMinSpanRaw)) { $reasons.Add('CaptureRequired') }

        if ($null -eq $sequence -or (Get-I64 $sequence 'PrimeStateValid') -ne 1L -or
                (Get-I64 $sequence 'EnableStateValid') -ne 1L -or
                (Get-I64 $sequence 'EnablePowerPpm') -ne 0L) {
            $reasons.Add('PrimeOrEnableState')
        }
        $healthClean = $true
        if ($null -eq $health) {
            $healthClean = $false
        } else {
            foreach ($field in @('DeadlineMisses', 'Retries', 'TransportErrors',
                    'JumpRejects', 'FailedSamples')) {
                if ((Get-I64 $health $field) -ne 0L) { $healthClean = $false }
            }
            if ((Get-I64 $health 'ReadAttempts') -ne ($expectedTotalTicks + 2L) -or
                    (Get-I64 $health 'Accepted') -ne ($expectedTotalTicks + 2L)) {
                $healthClean = $false
            }
        }
        if (-not $healthClean) { $reasons.Add('Health') }

        $samples = @($dataRecords | ForEach-Object {
            [pscustomobject]@{
                Seq = Get-I64 $_ 'Seq'
                Phase = Get-RequiredField $_ 'Phase'
                EncoderRaw = Get-I64 $_ 'EncoderRaw'
                DeltaRaw = Get-I64 $_ 'DeltaRaw'
            }
        })
        $rampDeltas = @($samples | Where-Object Phase -eq 'POWER_RAMP' |
            ForEach-Object { [math]::Abs($_.DeltaRaw) })
        $sweepDeltas = @($samples | Where-Object Phase -eq 'PHASE_SWEEP' |
            ForEach-Object { [math]::Abs($_.DeltaRaw) })
        $tailP2PRaw = Get-TailP2PRaw $samples
        $quadrant = [int][math]::Floor($seedRaw * 4.0 / $ElectricalCycleRaw) + 1

        $results += [pscustomobject][ordered]@{
            Run = $physicalRun
            Source = "$($file.BaseName)#$($blockIndex + 1)"
            Result = Get-RequiredField $summary 'Result'
            ContractPass = ($reasons.Count -eq 0)
            Reasons = ($reasons | Select-Object -Unique) -join ';'
            StartQuadrant = $quadrant
            BaselineRaw = $baselineRaw
            SeedPhaseRaw = $seedRaw
            SweepSpanRaw = $spanRaw
            SweepTicks = $sweepTicks
            CaptureRequired = $captureRequired
            CaptureDetected = $captureDetected
            RampCreepRaw = $rampCreepRaw
            RampMaxStepRawEvidence = if ($rampDeltas.Count) { ($rampDeltas | Measure-Object -Maximum).Maximum } else { 0L }
            SweepMaxStepRawEvidence = if ($sweepDeltas.Count) { ($sweepDeltas | Measure-Object -Maximum).Maximum } else { 0L }
            MaxStepMilliDeg = Get-I64 $summary 'MaxStepMilliDeg'
            FinalOffsetRaw = $finalOffset
            HoldTail20P2PRaw = [math]::Round($tailP2PRaw, 3)
            DeadlineMisses = if ($null -ne $health) { Get-I64 $health 'DeadlineMisses' } else { -1L }
            AcquisitionClean = $healthClean
        }
    }
}

$validResults = @($results | Where-Object {
    $_.ContractPass -and $_.Result -eq 'OK'
})
# A fault exits before HOLD, so its FinalOffsetRaw is merely the raw angle at
# abort and must never contaminate settled-offset statistics. The run still
# fails overall acceptance through allContractPass/allResultsOk below.
$offsets = @($validResults | ForEach-Object { [double]$_.FinalOffsetRaw })
$stats = Get-CircularStats -Values $offsets -Modulo ([double]$ElectricalCycleRaw)
$quadrants = @($validResults.StartQuadrant | Sort-Object -Unique)
$allContractPass = @($results | Where-Object { -not $_.ContractPass }).Count -eq 0
$allResultsOk = @($results | Where-Object Result -ne 'OK').Count -eq 0
$a4Acceptance = $results.Count -ge 5 -and $allContractPass -and $allResultsOk -and
    $quadrants.Count -ge 4 -and $stats.RangeRaw -le $FinalOffsetRangeLimitRaw

Write-Host ("[INFO] A4 runs={0}, files={1}, quadrants={2}, result/contract pass={3}/{0}" -f
    $results.Count, $files.Count, ($quadrants -join '|'),
    @($results | Where-Object ContractPass).Count)
Write-Host ("[INFO] FinalOffset circular mean={0:F2} raw, SD={1:F2} raw, range={2:F2} raw, R={3:F5}, limit={4:F0} raw" -f
    $stats.MeanRaw, $stats.StdRaw, $stats.RangeRaw, $stats.R,
    $FinalOffsetRangeLimitRaw)

if ($validResults.Count -ge 4) {
    $best = $null
    for ($split = 2; $split -le $validResults.Count - 2; $split++) {
        $left = @($validResults[0..($split - 1)] | ForEach-Object { [double]$_.FinalOffsetRaw })
        $right = @($validResults[$split..($validResults.Count - 1)] | ForEach-Object { [double]$_.FinalOffsetRaw })
        $leftMean = ($left | Measure-Object -Average).Average
        $rightMean = ($right | Measure-Object -Average).Average
        $sse = 0.0
        foreach ($v in $left) { $sse += ($v - $leftMean) * ($v - $leftMean) }
        foreach ($v in $right) { $sse += ($v - $rightMean) * ($v - $rightMean) }
        if ($null -eq $best -or $sse -lt $best.Sse) {
            $best = [pscustomobject]@{ Split = $split; LeftMean = $leftMean; RightMean = $rightMean; Sse = $sse }
        }
    }
    Write-Host ("[INFO] Best sequential offset split: after run {0}, means={1:F2}/{2:F2} raw, delta={3:F2} raw" -f
        $best.Split, $best.LeftMean, $best.RightMean,
        [math]::Abs($best.RightMean - $best.LeftMean))
}

Write-Host ("[RESULT] A4 acceptance: {0}" -f $(if ($a4Acceptance) { 'PASS' } else { 'FAIL' }))

if ($SummaryCsv) {
    $results | Export-Csv -LiteralPath $SummaryCsv -NoTypeInformation -Encoding utf8
}

$results
