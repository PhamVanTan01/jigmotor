param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string[]]$LogPath,
    [string]$SummaryCsv,
    [string]$EvidenceCsvDirectory,
    [string]$CircularSummaryCsv
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Convert-A2Record {
    param([string]$Line)
    $fields = $Line.Trim() -split ','
    $record = [ordered]@{ RecordType = $fields[0] }
    for ($i = 1; $i -lt $fields.Count; $i++) {
        $separator = $fields[$i].IndexOf('=')
        if ($separator -le 0) { continue }
        $record[$fields[$i].Substring(0, $separator)] =
            $fields[$i].Substring($separator + 1)
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

function Raw-ToMilliDeg {
    param([double]$Raw)
    $Raw * 360000.0 / 65536.0
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

function Normalize-Modulo {
    param([double]$Value, [double]$Modulo)
    $normalized = $Value % $Modulo
    if ($normalized -lt 0.0) { $normalized += $Modulo }
    $normalized
}

function Get-CircularStats {
    # Values wrap at Modulo (e.g. SettledModuloRaw wraps at electricalCycle).
    # A plain min/max range is misleading near the wrap boundary: two values
    # a few raw counts apart on either side of 0/Modulo look maximally far
    # apart in linear terms while being circularly adjacent. Mean-resultant
    # vector (R) and largest-gap range are the correct circular analogues of
    # arithmetic mean/std-dev/range.
    param([double[]]$Values, [double]$Modulo)
    $angles = $Values | ForEach-Object { $_ / $Modulo * 2.0 * [math]::PI }
    $sinMean = ($angles | ForEach-Object { [math]::Sin($_) } | Measure-Object -Average).Average
    $cosMean = ($angles | ForEach-Object { [math]::Cos($_) } | Measure-Object -Average).Average
    $resultantLength = [math]::Sqrt($sinMean * $sinMean + $cosMean * $cosMean)
    $meanAngle = [math]::Atan2($sinMean, $cosMean)
    if ($meanAngle -lt 0.0) { $meanAngle += 2.0 * [math]::PI }
    $circularMean = $meanAngle / (2.0 * [math]::PI) * $Modulo
    $circularStdDev = if ($resultantLength -gt 0.0) {
        [math]::Sqrt(-2.0 * [math]::Log($resultantLength)) * $Modulo / (2.0 * [math]::PI)
    } else { [double]::NaN }

    $sorted = @($Values | Sort-Object)
    $maxGap = 0.0
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $next = if ($i + 1 -lt $sorted.Count) { $sorted[$i + 1] } else { $sorted[0] + $Modulo }
        $gap = $next - $sorted[$i]
        if ($gap -gt $maxGap) { $maxGap = $gap }
    }
    $circularRange = $Modulo - $maxGap

    [pscustomobject]@{
        Count = $Values.Count
        CircularMeanRaw = [math]::Round($circularMean, 3)
        CircularStdDevRaw = [math]::Round($circularStdDev, 3)
        CircularRangeRaw = [math]::Round($circularRange, 3)
        ResultantLength = [math]::Round($resultantLength, 4)
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
            throw "A2 log not found: $candidate"
        }
    }
    @($files | Sort-Object FullName -Unique)
}

$inputFiles = @(Resolve-InputFiles $LogPath)
if ($inputFiles.Count -eq 0) { throw 'No A2 log files matched.' }

# Keep A2 and A2B evidence comparable while enforcing each immutable profile's
# own timing envelope. A2B changes only the final hold duration.
$profileSpecifications = @{
    'CONTROL_A2_FIXED_PHASE_ALIGN_P10_V1' = [pscustomobject]@{
        RampTicks = 500L; HoldTicks = 100L; ActiveDurationMs = 600L
        EvidenceCount = 601L; ReadAttempts = 602L; TargetPowerPpm = 100000L
    }
    'CONTROL_A2B_FIXED_PHASE_ALIGN_P10_H500_V1' = [pscustomobject]@{
        RampTicks = 500L; HoldTicks = 500L; ActiveDurationMs = 1000L
        EvidenceCount = 1001L; ReadAttempts = 1002L; TargetPowerPpm = 100000L
    }
    'CONTROL_A2C_FIXED_PHASE_ALIGN_P06_H500_V1' = [pscustomobject]@{
        RampTicks = 500L; HoldTicks = 500L; ActiveDurationMs = 1000L
        EvidenceCount = 1001L; ReadAttempts = 1002L; TargetPowerPpm = 60000L
    }
    'CONTROL_A2D_FIXED_PHASE_ALIGN_P07_H500_V1' = [pscustomobject]@{
        RampTicks = 500L; HoldTicks = 500L; ActiveDurationMs = 1000L
        EvidenceCount = 1001L; ReadAttempts = 1002L; TargetPowerPpm = 70000L
    }
    'CONTROL_A2E_FIXED_PHASE_ALIGN_P08_H500_V1' = [pscustomobject]@{
        RampTicks = 500L; HoldTicks = 500L; ActiveDurationMs = 1000L
        EvidenceCount = 1001L; ReadAttempts = 1002L; TargetPowerPpm = 80000L
    }
    'CONTROL_A2F_FIXED_PHASE_ALIGN_P09_H500_V1' = [pscustomobject]@{
        RampTicks = 500L; HoldTicks = 500L; ActiveDurationMs = 1000L
        EvidenceCount = 1001L; ReadAttempts = 1002L; TargetPowerPpm = 90000L
    }
}

if ($EvidenceCsvDirectory) {
    New-Item -ItemType Directory -Path $EvidenceCsvDirectory -Force | Out-Null
}

$results = @()
foreach ($file in $inputFiles) {
    $recordLines = @(Get-Content -LiteralPath $file.FullName | Where-Object {
        $_ -match '^CONTROL_A2_(ARMED|SUMMARY|SEQUENCE|HEALTH|DATA|RUNTIME),'
    })
    $startIndices = @()
    for ($lineIndex = 0; $lineIndex -lt $recordLines.Count; $lineIndex++) {
        if ($recordLines[$lineIndex] -match '^CONTROL_A2_ARMED,') {
            $startIndices += $lineIndex
        }
    }
    if ($startIndices.Count -eq 0) {
        $startIndices = @(0)
    }
    $recordBlocks = [System.Collections.Generic.List[object]]::new()
    for ($block = 0; $block -lt $startIndices.Count; $block++) {
        $start = $startIndices[$block]
        $end = if ($block + 1 -lt $startIndices.Count) {
            $startIndices[$block + 1] - 1
        } else {
            $recordLines.Count - 1
        }
        $blockRecords = if ($end -ge $start) {
            @($recordLines[$start..$end] | ForEach-Object { Convert-A2Record $_ })
        } else { @() }
        $recordBlocks.Add($blockRecords)
    }

    for ($blockIndex = 0; $blockIndex -lt $recordBlocks.Count; $blockIndex++) {
    $records = @($recordBlocks[$blockIndex])

    $armedRecords = @($records | Where-Object RecordType -eq 'CONTROL_A2_ARMED')
    $summaryRecords = @($records | Where-Object RecordType -eq 'CONTROL_A2_SUMMARY')
    $sequenceRecords = @($records | Where-Object RecordType -eq 'CONTROL_A2_SEQUENCE')
    $healthRecords = @($records | Where-Object RecordType -eq 'CONTROL_A2_HEALTH')
    $runtimeRecords = @($records | Where-Object RecordType -eq 'CONTROL_A2_RUNTIME')
    $dataRecords = @($records | Where-Object RecordType -eq 'CONTROL_A2_DATA')
    $gateReasons = [System.Collections.Generic.List[string]]::new()

    if ($armedRecords.Count -ne 1) { $gateReasons.Add("ArmedRecords=$($armedRecords.Count)") }
    if ($summaryRecords.Count -ne 1) { $gateReasons.Add("SummaryRecords=$($summaryRecords.Count)") }
    if ($sequenceRecords.Count -ne 1) { $gateReasons.Add("SequenceRecords=$($sequenceRecords.Count)") }
    if ($healthRecords.Count -ne 1) { $gateReasons.Add("HealthRecords=$($healthRecords.Count)") }
    if ($dataRecords.Count -eq 0) { $gateReasons.Add('NoData') }

    $armed = $armedRecords | Select-Object -Last 1
    $summary = $summaryRecords | Select-Object -Last 1
    $sequence = $sequenceRecords | Select-Object -Last 1
    $health = $healthRecords | Select-Object -Last 1
    $runtime = $runtimeRecords | Select-Object -Last 1

    $samples = @()
    $telemetryValid = $true
    foreach ($record in $dataRecords) {
        try {
            $samples += [pscustomobject]@{
                Seq = Get-I64 $record 'Seq'
                Phase = Get-RequiredField $record 'Phase'
                EncoderRaw = Get-I64 $record 'EncoderRaw'
                TravelMilliDegLogged = Get-I64 $record 'TravelMilliDeg'
                DeltaRaw = Get-I64 $record 'DeltaRaw'
                VelocityRawPerSecond = Get-I64 $record 'VelocityRawPerSecond'
                AccelerationRawPerSecond2 = Get-I64 $record 'AccelerationRawPerSecond2'
                CommandPhaseRaw = Get-I64 $record 'CommandPhaseRaw'
                PowerPpm = Get-I64 $record 'PowerPpm'
                ScheduledTick = Get-I64 $record 'ScheduledTick'
                SampleTick = Get-I64 $record 'SampleTick'
                LatenessTicks = Get-I64 $record 'LatenessTicks'
                LoopCycles = Get-I64 $record 'LoopCycles'
                SpiLatencyCycles = Get-I64 $record 'SpiLatencyCycles'
                PwmCounterAtCs = Get-I64 $record 'PwmCounterAtCs'
                CorrectionRaw = Get-I64 $record 'CorrectionRaw'
            }
        } catch {
            $telemetryValid = $false
            $gateReasons.Add("TelemetryParse:$($_.Exception.Message)")
            break
        }
    }

    $profile = if ($null -ne $summary) { Get-RequiredField $summary 'Profile' } else { 'MISSING' }
    $resultName = if ($null -ne $summary) { Get-RequiredField $summary 'Result' } else { 'MISSING' }
    $baselineRaw = if ($null -ne $summary) { Get-I64 $summary 'BaselineRaw' } else { 0L }
    $finalRaw = if ($null -ne $summary) { Get-I64 $summary 'FinalRaw' } else { 0L }
    $profileSpec = $profileSpecifications[$profile]

    if ($null -eq $profileSpec) { $gateReasons.Add("Profile=$profile") }
    if ($resultName -ne 'OK') { $gateReasons.Add("Result=$resultName") }
    if ($null -ne $summary -and $null -ne $profileSpec) {
        if ((Get-I64 $summary 'ActiveDurationMs') -ne $profileSpec.ActiveDurationMs) { $gateReasons.Add('ActiveDuration') }
        if ((Get-I64 $summary 'EvidenceCount') -ne $profileSpec.EvidenceCount) { $gateReasons.Add('SummaryEvidenceCount') }
    }
    if ($null -ne $sequence) {
        if ((Get-I64 $sequence 'PrimeStateValid') -ne 1L) { $gateReasons.Add('PrimeState') }
        if ((Get-I64 $sequence 'EnableStateValid') -ne 1L) { $gateReasons.Add('EnableState') }
        if ((Get-I64 $sequence 'EnablePowerPpm') -ne 0L) { $gateReasons.Add('EnablePower') }
    }
    if ($null -ne $health) {
        foreach ($field in @('DeadlineMisses', 'AccelerationSaturations', 'Retries',
                'TransportErrors', 'JumpRejects', 'FailedSamples')) {
            if ((Get-I64 $health $field) -ne 0L) { $gateReasons.Add("$field=$(Get-I64 $health $field)") }
        }
        if ($null -ne $profileSpec -and (Get-I64 $health 'ReadAttempts') -ne $profileSpec.ReadAttempts) { $gateReasons.Add('ReadAttempts') }
        if ($null -ne $profileSpec -and (Get-I64 $health 'Accepted') -ne $profileSpec.ReadAttempts) { $gateReasons.Add('Accepted') }
    }

    if ($telemetryValid -and $samples.Count -gt 0) {
        if ($null -ne $profileSpec -and $samples.Count -ne $profileSpec.EvidenceCount) { $gateReasons.Add("DataCount=$($samples.Count)") }
        $rampCount = @($samples | Where-Object Phase -eq 'ALIGN_RAMP').Count
        $holdCount = @($samples | Where-Object Phase -eq 'ALIGN_HOLD').Count
        if ($null -ne $profileSpec -and ($rampCount -ne ($profileSpec.RampTicks + 1L) -or $holdCount -ne $profileSpec.HoldTicks)) {
            $gateReasons.Add("Phases=$rampCount/$holdCount")
        }
        for ($i = 0; $i -lt $samples.Count; $i++) {
            $sample = $samples[$i]
            if ($sample.Seq -ne $i) { $gateReasons.Add("Seq@$i=$($sample.Seq)"); break }
            if ($null -ne $profileSpec) {
                $expectedPower = if ($i -ge $profileSpec.RampTicks) {
                    $profileSpec.TargetPowerPpm
                } else {
                    [int64]$i * $profileSpec.TargetPowerPpm / $profileSpec.RampTicks
                }
                if ($sample.PowerPpm -ne $expectedPower) {
                    $gateReasons.Add("Power@$i=$($sample.PowerPpm)"); break
                }
            }
            if ($sample.CommandPhaseRaw -ne 0L -or $sample.CorrectionRaw -ne 0L) {
                $gateReasons.Add("CommandOrCorrection@$i"); break
            }
            if ([math]::Abs($sample.DeltaRaw) -gt 45L) {
                $gateReasons.Add("StepLimit@$i=$($sample.DeltaRaw)"); break
            }
            if ($i -gt 0) {
                $tickStep = $sample.ScheduledTick - $samples[$i - 1].ScheduledTick
                if ($tickStep -ne 1L -and $tickStep -ne -4294967295L) {
                    $gateReasons.Add("Schedule@$i=$tickStep"); break
                }
            }
        }
    }

    $exactSamples = @($samples | ForEach-Object {
        $travelRaw = [int64]$_.EncoderRaw - $baselineRaw
        if ($travelRaw -gt 32767L) { $travelRaw -= 65536L }
        if ($travelRaw -lt -32768L) { $travelRaw += 65536L }
        [pscustomobject]@{
            Seq = $_.Seq; Phase = $_.Phase; EncoderRaw = $_.EncoderRaw
            TravelRaw = $travelRaw; TravelMilliDeg = Raw-ToMilliDeg $travelRaw
            DeltaRaw = $_.DeltaRaw; VelocityRawPerSecond = $_.VelocityRawPerSecond
            AccelerationRawPerSecond2 = $_.AccelerationRawPerSecond2
            PowerPpm = $_.PowerPpm; ScheduledTick = $_.ScheduledTick
            SampleTick = $_.SampleTick; LatenessTicks = $_.LatenessTicks
            LoopCycles = $_.LoopCycles; SpiLatencyCycles = $_.SpiLatencyCycles
            PwmCounterAtCs = $_.PwmCounterAtCs
        }
    })
    if (@($exactSamples | Where-Object { [math]::Abs($_.TravelRaw) -gt 910L }).Count -gt 0) {
        $gateReasons.Add('TravelLimit')
    }

    $hold = @(if ($null -ne $profileSpec) {
        $exactSamples | Where-Object { $_.Seq -gt $profileSpec.RampTicks }
    })
    $holdTail20 = @($hold | Select-Object -Last 20)
    $maxStep = $exactSamples | Sort-Object { [math]::Abs($_.DeltaRaw) } -Descending |
        Select-Object -First 1
    $maxTravelRaw = if ($exactSamples.Count) {
        ($exactSamples | ForEach-Object { [math]::Abs($_.TravelRaw) } |
            Measure-Object -Maximum).Maximum
    } else { [double]::NaN }
    $holdTravel = @($hold | ForEach-Object { [double]$_.TravelMilliDeg })
    $holdMean = if ($holdTravel.Count) { ($holdTravel | Measure-Object -Average).Average } else { [double]::NaN }
    $holdMin = if ($holdTravel.Count) { ($holdTravel | Measure-Object -Minimum).Minimum } else { [double]::NaN }
    $holdMax = if ($holdTravel.Count) { ($holdTravel | Measure-Object -Maximum).Maximum } else { [double]::NaN }
    $holdMeanRaw = if ($hold.Count) { ($hold.TravelRaw | Measure-Object -Average).Average } else { [double]::NaN }
    $tailTravel = @($holdTail20 | ForEach-Object { [double]$_.TravelMilliDeg })
    $tailMin = if ($tailTravel.Count) { ($tailTravel | Measure-Object -Minimum).Minimum } else { [double]::NaN }
    $tailMax = if ($tailTravel.Count) { ($tailTravel | Measure-Object -Maximum).Maximum } else { [double]::NaN }
    $settledModuloRaw = if ($hold.Count) {
        Normalize-Modulo ($baselineRaw + $holdMeanRaw) 10923.0
    } else { [double]::NaN }
    $onset50 = $exactSamples | Where-Object { [math]::Abs($_.TravelMilliDeg) -ge 50.0 } | Select-Object -First 1
    $onset100 = $exactSamples | Where-Object { [math]::Abs($_.TravelMilliDeg) -ge 100.0 } | Select-Object -First 1
    $onset250 = $exactSamples | Where-Object { [math]::Abs($_.TravelMilliDeg) -ge 250.0 } | Select-Object -First 1
    $onset500 = $exactSamples | Where-Object { [math]::Abs($_.TravelMilliDeg) -ge 500.0 } | Select-Object -First 1

    $loopValues = @($exactSamples | ForEach-Object { [double]$_.LoopCycles })
    $spiValues = @($exactSamples | ForEach-Object { [double]$_.SpiLatencyCycles })
    $latenessValues = @($exactSamples | ForEach-Object { [double]$_.LatenessTicks })
    $resultObject = [pscustomobject][ordered]@{
        Run = if ($recordBlocks.Count -gt 1) {
            "$($file.BaseName)#$($blockIndex + 1)"
        } else { $file.BaseName }
        File = $file.FullName
        Profile = $profile
        Result = $resultName
        GatePass = ($gateReasons.Count -eq 0)
        HardGatePass = ($gateReasons.Count -eq 0)
        GateReasons = ($gateReasons | Select-Object -Unique) -join ';'
        EvidenceCount = $samples.Count
        BaselineRaw = $baselineRaw
        FinalRaw = $finalRaw
        FinalTravelMilliDeg = if ($exactSamples.Count) { [math]::Round($exactSamples[-1].TravelMilliDeg, 3) } else { [double]::NaN }
        MaxAbsTravelMilliDeg = if ($exactSamples.Count) { [math]::Round((Raw-ToMilliDeg $maxTravelRaw), 3) } else { [double]::NaN }
        MaxAbsStepRaw = if ($null -ne $maxStep) { [math]::Abs($maxStep.DeltaRaw) } else { [double]::NaN }
        MaxAbsStepMilliDeg = if ($null -ne $maxStep) { [math]::Round((Raw-ToMilliDeg ([math]::Abs($maxStep.DeltaRaw))), 3) } else { [double]::NaN }
        MaxStepSeq = if ($null -ne $maxStep) { $maxStep.Seq } else { 'NA' }
        MaxStepPowerPpm = if ($null -ne $maxStep) { $maxStep.PowerPpm } else { 'NA' }
        Onset50mdegSeq = if ($null -ne $onset50) { $onset50.Seq } else { 'NA' }
        Onset100mdegSeq = if ($null -ne $onset100) { $onset100.Seq } else { 'NA' }
        Onset250mdegSeq = if ($null -ne $onset250) { $onset250.Seq } else { 'NA' }
        Onset500mdegSeq = if ($null -ne $onset500) { $onset500.Seq } else { 'NA' }
        HoldMeanMilliDeg = [math]::Round($holdMean, 3)
        HoldStdMilliDeg = [math]::Round((Get-PopulationStdDev $holdTravel), 3)
        HoldP2PMilliDeg = if ($holdTravel.Count) { [math]::Round($holdMax - $holdMin, 3) } else { [double]::NaN }
        HoldDriftMilliDeg = if ($hold.Count) { [math]::Round($hold[-1].TravelMilliDeg - $hold[0].TravelMilliDeg, 3) } else { [double]::NaN }
        HoldTail20MeanMilliDeg = if ($tailTravel.Count) { [math]::Round(($tailTravel | Measure-Object -Average).Average, 3) } else { [double]::NaN }
        HoldTail20StdMilliDeg = [math]::Round((Get-PopulationStdDev $tailTravel), 3)
        HoldTail20P2PMilliDeg = if ($tailTravel.Count) { [math]::Round($tailMax - $tailMin, 3) } else { [double]::NaN }
        SettledModuloRaw = [math]::Round($settledModuloRaw, 3)
        LoopMinUs = if ($loopValues.Count) { [math]::Round((($loopValues | Measure-Object -Minimum).Minimum / 168.0), 3) } else { [double]::NaN }
        LoopMeanUs = if ($loopValues.Count) { [math]::Round((($loopValues | Measure-Object -Average).Average / 168.0), 3) } else { [double]::NaN }
        LoopMaxUs = if ($loopValues.Count) { [math]::Round((($loopValues | Measure-Object -Maximum).Maximum / 168.0), 3) } else { [double]::NaN }
        SpiMeanUs = if ($spiValues.Count) { [math]::Round((($spiValues | Measure-Object -Average).Average / 168.0), 3) } else { [double]::NaN }
        SpiMaxUs = if ($spiValues.Count) { [math]::Round((($spiValues | Measure-Object -Maximum).Maximum / 168.0), 3) } else { [double]::NaN }
        MaxLatenessTicks = if ($latenessValues.Count) { ($latenessValues | Measure-Object -Maximum).Maximum } else { [double]::NaN }
        DeadlineMisses = if ($null -ne $health) { Get-I64 $health 'DeadlineMisses' } else { 'NA' }
        Retries = if ($null -ne $health) { Get-I64 $health 'Retries' } else { 'NA' }
        TransportErrors = if ($null -ne $health) { Get-I64 $health 'TransportErrors' } else { 'NA' }
        JumpRejects = if ($null -ne $health) { Get-I64 $health 'JumpRejects' } else { 'NA' }
        FailedSamples = if ($null -ne $health) { Get-I64 $health 'FailedSamples' } else { 'NA' }
        AccelerationSaturations = if ($null -ne $health) { Get-I64 $health 'AccelerationSaturations' } else { 'NA' }
        FreeHeap = if ($null -ne $runtime) { Get-I64 $runtime 'FreeHeap' } else { 'NA' }
        StackHighWaterWords = if ($null -ne $runtime) { Get-I64 $runtime 'ControlStackHighWaterWords' } else { 'NA' }
    }
    $results += $resultObject

    if ($EvidenceCsvDirectory -and $exactSamples.Count) {
        $runName = if ($recordBlocks.Count -gt 1) {
            "$($file.BaseName)_$($blockIndex + 1)"
        } else { $file.BaseName }
        $safeName = $runName -replace '[^A-Za-z0-9_.-]', '_'
        $exactSamples | Export-Csv -LiteralPath (Join-Path $EvidenceCsvDirectory "$safeName.csv") `
            -NoTypeInformation -Encoding utf8
    }
    }
}

if ($SummaryCsv) {
    $results | Export-Csv -LiteralPath $SummaryCsv -NoTypeInformation -Encoding utf8
}

$electricalCycleRaw = 10923.0
$circularSummaries = @()
foreach ($group in ($results | Group-Object Profile)) {
    $moduloValues = @($group.Group | ForEach-Object { $_.SettledModuloRaw } |
        Where-Object { $_ -is [double] -and -not [double]::IsNaN($_) })
    if ($moduloValues.Count -lt 2) { continue }
    $stats = Get-CircularStats -Values $moduloValues -Modulo $electricalCycleRaw
    $circularSummary = [pscustomobject][ordered]@{
        Profile = $group.Name
        RunCount = $stats.Count
        CircularMeanRaw = $stats.CircularMeanRaw
        CircularStdDevRaw = $stats.CircularStdDevRaw
        CircularRangeRaw = $stats.CircularRangeRaw
        ResultantLength = $stats.ResultantLength
    }
    $circularSummaries += $circularSummary
    Write-Host ("[INFO] {0}: SettledModuloRaw circular mean={1} raw, circular range={2} raw, R={3} (n={4})" -f
        $group.Name, $stats.CircularMeanRaw, $stats.CircularRangeRaw, $stats.ResultantLength, $stats.Count)
}
if ($CircularSummaryCsv -and $circularSummaries.Count) {
    $circularSummaries | Export-Csv -LiteralPath $CircularSummaryCsv -NoTypeInformation -Encoding utf8
}

$results
