param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$Analyzer = Join-Path $PSScriptRoot 'analyze_control_a5.ps1'
$Profile = 'CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1'
$ParentProfile = 'CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1'
$SampleCount = 2048
$PeriodCycles = 168000L
$PwmPeriodCounts = 4200L
$U32Modulus = 4294967296L
$PowerShellExe = (Get-Process -Id $PID).Path

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
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

function New-A5Fixture {
    param([ValidateSet('constant', 'wrap')][string]$Kind)
    [int64[]]$raw = New-Object int64[] $SampleCount
    for ($i = 0; $i -lt $SampleCount; $i++) {
        if ($Kind -eq 'constant') {
            [int64[]]$pattern = @(0, 1, 0, -1, 0, 2, 0, -2)
            $raw[$i] = 12000L + $pattern[$i % $pattern.Count]
        } else {
            # Crosses 65535/0 repeatedly while physical movement remains a
            # bounded 0..39 raw sawtooth with one-raw adjacent steps.
            $raw[$i] = (65530L + [int64][math]::Floor($i / 32.0) % 40L) % 65536L
        }
    }

    [int64[]]$relative = New-Object int64[] $SampleCount
    [int64]$position = 0
    [int64]$maxStep = 0
    for ($i = 1; $i -lt $SampleCount; $i++) {
        [int64]$delta = Get-WrapDeltaRaw $raw[$i - 1] $raw[$i]
        $position += $delta
        $relative[$i] = $position
        if ([math]::Abs($delta) -gt $maxStep) { $maxStep = [math]::Abs($delta) }
    }
    $measure = $relative | Measure-Object -Minimum -Maximum -Sum
    [int64]$minRel = $measure.Minimum
    [int64]$maxRel = $measure.Maximum
    [int64]$sumRel = $measure.Sum
    [int64]$scaled = $sumRel * 65536L
    [int64]$half = [int64][math]::Floor($SampleCount / 2.0)
    [int64]$meanQ16 = if ($scaled -ge 0L) {
        [int64][math]::Floor(($scaled + $half) / [double]$SampleCount)
    } else {
        -[int64][math]::Floor((-$scaled + $half) / [double]$SampleCount)
    }
    [uint32]$crc = Get-Crc32RawWords $raw

    [int64[]]$cs = New-Object int64[] $SampleCount
    [int64[]]$pwm = New-Object int64[] $SampleCount
    [int64[]]$spi = New-Object int64[] $SampleCount
    [uint32]$pwmMask = 0
    [int64]$spiSum = 0
    [int64]$spiMin = [int64]::MaxValue
    [int64]$spiMax = 0
    [int64]$firstCycle = 4294967040L
    for ($i = 0; $i -lt $SampleCount; $i++) {
        $cs[$i] = ($firstCycle + $i * $PeriodCycles) % $U32Modulus
        $pwm[$i] = ($i * 137L) % $PwmPeriodCounts
        $spi[$i] = 420L + ($i % 7)
        [int]$bin = [int][math]::Floor($pwm[$i] * 32.0 / $PwmPeriodCounts)
        $pwmMask = [uint32]($pwmMask -bor ([uint32]1 -shl $bin))
        $spiSum += $spi[$i]
        if ($spi[$i] -lt $spiMin) { $spiMin = $spi[$i] }
        if ($spi[$i] -gt $spiMax) { $spiMax = $spi[$i] }
    }
    [int64]$spiMean = [int64][math]::Floor(
        ($spiSum + $SampleCount / 2.0) / $SampleCount)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("CONTROL_A5_ARMED,RecordVersion=1,Profile=$Profile,ParentProfile=$ParentProfile,Metric=MA600_ANGLE_WORD_RAW16,SampleCount=2048,SampleRateHz=1000,CaptureMs=2048,CommandPhaseRaw=0,PowerPpm=350000,OffsetRaw=7971,Transport=SPI_DMA_BLOCKING_WRAPPER_V1,Filt=0x05")
    $lines.Add("CONTROL_A5_IDENTITY,RecordVersion=1,Profile=$Profile,ParentProfile=$ParentProfile,AppProfile=$Profile,BuildSourceId=SYNTHETIC_A5_FIXTURE")
    $lines.Add("CONTROL_A5_CLOCK,RecordVersion=1,Profile=$Profile,SystemClockHz=168000000,PeriodCycles=168000,PwmPeriodCounts=4200")
    $lines.Add("CONTROL_A5_CONFIG,RecordVersion=1,Profile=$Profile,GatePolicy=POLICY_A_AUDIT_V1,ExpectedCalibrationState=ZERO_TABLE,CalibrationState=ZERO_TABLE,ConfigReadValid=1,ConfigValid=1,RejectReason=NONE,Zero=0x0000,Dir=0x00,Filt=0x05,Status=0x00,Prt=0x00,RmapId=0x00,CorrNonZeroCount=0,CorrCRC32=0x190A55AD")
    $lines.Add(("CONTROL_A5_SUMMARY,RecordVersion=1,Profile=$Profile,Result=OK,MeasurementValid=1,InvalidReason=NONE,InvalidReasonMask=0x00000000,Accepted=2048,FirstRaw={0},LastRaw={1},MinRelRaw={2},MaxRelRaw={3},P2PRaw={4},DriftRaw={5},MaxAbsStepRaw={6},MeanRelRawQ16={7},RawCRC32=0x{8:X8}" -f $raw[0], $raw[$SampleCount - 1], $minRel, $maxRel, ($maxRel - $minRel), $relative[$SampleCount - 1], $maxStep, $meanQ16, $crc))
    $lines.Add(("CONTROL_A5_TIMING,RecordVersion=1,Profile=$Profile,SlotsReached=2048,SkippedSlots=0,Overruns=0,CaptureDurationMs=2048,IntervalMinCycles=168000,IntervalMaxCycles=168000,MaxAbsScheduleErrorCycles=0,SpiLatencyMinCycles={0},SpiLatencyMaxCycles={1},SpiLatencyMeanCycles={2},PwmPhaseBinMask=0x{3:X8}" -f $spiMin, $spiMax, $spiMean, $pwmMask))
    $lines.Add("CONTROL_A5_HEALTH,RecordVersion=1,Profile=$Profile,ReadAttempts=2048,Accepted=2048,Retries=0,TransportErrors=0,JumpRejects=0,FailedSamples=0,AcquisitionValid=1,TimingValid=1,StaticWindowValid=1,RecordIntegrityValid=1")
    $lines.Add("CONTROL_A5_STATE,RecordVersion=1,Profile=$Profile,ResourcesValid=1,ParentAlignmentValid=1,PreStateValid=1,PostStateValid=1,CommandChanged=0,PreEnabled=1,PrePhaseRaw=0,PrePowerPpm=350000,PostEnabled=1,PostPhaseRaw=0,PostPowerPpm=350000,SafeStopValid=1,SafeStopEnabled=0,SafeStopPhaseRaw=0,SafeStopPowerPpm=0")
    $lines.Add("CONTROL_A5_RUNTIME,RecordVersion=1,Profile=$Profile,FreeHeapBeforeAllocation=91688,FreeHeapAfterAllocation=67112,FreeHeapNow=67112,MinEverFreeHeap=66000,ControlStackHighWaterWords=1100")
    for ($i = 0; $i -lt $SampleCount; $i++) {
        $lines.Add(("CONTROL_A5_DATA,RecordVersion=1,Profile=$Profile,Index={0},Raw={1},CsAssertCycle={2},PwmCounterAtCs={3},SpiLatencyCycles={4},Attempts=1,Flags=0x00" -f $i, $raw[$i], $cs[$i], $pwm[$i], $spi[$i]))
    }
    $lines.ToArray()
}

function Invoke-Analyzer {
    param([string]$InputFile, [string]$SummaryCsv, [string]$RawCsv)
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Analyzer,
        '-LogFiles', $InputFile, '-SummaryCsv', $SummaryCsv, '-Quiet')
    if ($RawCsv) { $arguments += @('-RawCsv', $RawCsv) }
    $output = @(& $PowerShellExe @arguments 2>&1)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

$temp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(),
    ("control-a5-analyzer-{0}" -f [guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $validLines = @(New-A5Fixture constant)
    $wrapLines = @(New-A5Fixture wrap)
    $validFile = Join-Path $temp 'valid.txt'
    $wrapFile = Join-Path $temp 'wrap.txt'
    [System.IO.File]::WriteAllLines($validFile, $validLines)
    [System.IO.File]::WriteAllLines($wrapFile, $wrapLines)

    foreach ($case in @(
        [pscustomobject]@{ Name = 'valid'; File = $validFile },
        [pscustomobject]@{ Name = 'wrap'; File = $wrapFile })) {
        $csv = Join-Path $temp "$($case.Name).csv"
        $rawCsv = Join-Path $temp "$($case.Name)-raw.csv"
        $run = Invoke-Analyzer $case.File $csv $rawCsv
        Assert-True ($run.ExitCode -eq 0) "$($case.Name) fixture failed: $($run.Output -join [Environment]::NewLine)"
        $summary = @(Import-Csv -LiteralPath $csv)
        $raw = @(Import-Csv -LiteralPath $rawCsv)
        Assert-True -Condition ($summary.Count -eq 1 -and $summary[0].Valid -eq 'True') -Message "$($case.Name) did not produce one valid summary."
        Assert-True -Condition ($raw.Count -eq $SampleCount) -Message "$($case.Name) raw export count mismatch."
    }

    $multiFile = Join-Path $temp 'multi-run.txt'
    [System.IO.File]::WriteAllLines($multiFile, @($validLines + $wrapLines))
    $multiCsv = Join-Path $temp 'multi.csv'
    $multi = Invoke-Analyzer $multiFile $multiCsv ''
    Assert-True ($multi.ExitCode -eq 0) "multi-run fixture failed."
    Assert-True -Condition (@(Import-Csv -LiteralPath $multiCsv).Count -eq 2) -Message 'Physical-run splitting failed.'

    $cases = @()
    $truncated = [System.Collections.Generic.List[string]]::new()
    $truncated.AddRange([string[]]$validLines)
    $truncated.RemoveAt($truncated.Count - 1)
    $cases += [pscustomobject]@{ Name = 'truncated'; Lines = $truncated.ToArray(); Token = 'DataCount' }

    $duplicate = [string[]]$validLines.Clone()
    $dataStart = 9
    $duplicate[$dataStart + 100] = $duplicate[$dataStart + 100] -replace 'Index=100,', 'Index=99,'
    $cases += [pscustomobject]@{ Name = 'duplicate'; Lines = $duplicate; Token = 'IndexOrder' }

    $reordered = [string[]]$validLines.Clone()
    $swap = $reordered[$dataStart + 200]
    $reordered[$dataStart + 200] = $reordered[$dataStart + 201]
    $reordered[$dataStart + 201] = $swap
    $cases += [pscustomobject]@{ Name = 'reordered'; Lines = $reordered; Token = 'IndexOrder' }

    $badCrc = [string[]]$validLines.Clone()
    $badCrc[4] = $badCrc[4] -replace 'RawCRC32=0x[0-9A-F]{8}', 'RawCRC32=0x00000000'
    $cases += [pscustomobject]@{ Name = 'bad-crc'; Lines = $badCrc; Token = 'CRC=' }

    foreach ($case in $cases) {
        $file = Join-Path $temp "$($case.Name).txt"
        $csv = Join-Path $temp "$($case.Name).csv"
        [System.IO.File]::WriteAllLines($file, [string[]]$case.Lines)
        $run = Invoke-Analyzer $file $csv ''
        Assert-True -Condition ($run.ExitCode -eq 2) -Message "$($case.Name) was not rejected."
        $summary = @(Import-Csv -LiteralPath $csv)
        Assert-True -Condition ($summary.Count -eq 1 -and $summary[0].Valid -eq 'False') -Message "$($case.Name) rejection was not exported."
        Assert-True -Condition ($summary[0].Reasons -like "*$($case.Token)*") -Message "$($case.Name) rejection missed $($case.Token): $($summary[0].Reasons)"
    }

    Write-Host '[ OK ] A5.3 analyzer valid/wrap/multi-run/corruption contract passed.'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
