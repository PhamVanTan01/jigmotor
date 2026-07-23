$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-WrapDelta {
    param([int]$Previous, [int]$Current)
    $delta = $Current - $Previous
    if ($delta -gt 32767) { $delta -= 65536 }
    elseif ($delta -lt -32768) { $delta += 65536 }
    $delta
}

function Get-Crc32RawWords {
    param([int[]]$Raw)
    [uint32]$crc = [Convert]::ToUInt32('FFFFFFFF', 16)
    [uint32]$polynomial = [Convert]::ToUInt32('EDB88320', 16)
    foreach ($word in $Raw) {
        foreach ($byte in @((($word -band 0xFF)),
                ((($word -shr 8) -band 0xFF)))) {
            $crc = [uint32]($crc -bxor [uint32]$byte)
            for ($bit = 0; $bit -lt 8; $bit++) {
                if (($crc -band 1) -ne 0) {
                    $crc = [uint32](($crc -shr 1) -bxor $polynomial)
                } else {
                    $crc = [uint32]($crc -shr 1)
                }
            }
        }
    }
    [uint32]($crc -bxor [Convert]::ToUInt32('FFFFFFFF', 16))
}

function Get-Stats {
    param([int[]]$Raw)
    Assert-True ($Raw.Count -gt 0) 'Reference vector must not be empty.'
    [long]$position = $Raw[0]
    [long]$first = $position
    [long]$sum = 0
    [long]$sumSquares = 0
    [long]$minRel = 0
    [long]$maxRel = 0
    [long]$maxStep = 0
    for ($i = 1; $i -lt $Raw.Count; $i++) {
        $delta = Get-WrapDelta $Raw[$i - 1] $Raw[$i]
        $position += $delta
        $rel = $position - $first
        $sum += $rel
        $sumSquares += $rel * $rel
        if ($rel -lt $minRel) { $minRel = $rel }
        if ($rel -gt $maxRel) { $maxRel = $rel }
        if ([math]::Abs($delta) -gt $maxStep) { $maxStep = [math]::Abs($delta) }
    }
    $scaled = $sum * 65536L
    $meanQ16 = if ($scaled -ge 0) {
        [math]::Truncate(($scaled + [math]::Truncate($Raw.Count / 2)) / $Raw.Count)
    } else {
        -[math]::Truncate((-$scaled + [math]::Truncate($Raw.Count / 2)) / $Raw.Count)
    }
    [pscustomobject]@{
        Min = $minRel
        Max = $maxRel
        P2P = $maxRel - $minRel
        Drift = $position - $first
        MeanQ16 = [long]$meanQ16
        Sum = $sum
        SumSquares = $sumSquares
        MaxStep = $maxStep
        Crc = Get-Crc32RawWords $Raw
    }
}

function Assert-Vector {
    param(
        [string]$Name,
        [int[]]$Raw,
        [long]$Min,
        [long]$Max,
        [long]$P2P,
        [long]$Drift,
        [long]$MeanQ16,
        [long]$MaxStep,
        [uint32]$Crc
    )
    $actual = Get-Stats $Raw
    Assert-True ($actual.Min -eq $Min -and $actual.Max -eq $Max -and
        $actual.P2P -eq $P2P -and $actual.Drift -eq $Drift -and
        $actual.MeanQ16 -eq $MeanQ16 -and $actual.MaxStep -eq $MaxStep -and
        $actual.Crc -eq $Crc) "A5 golden vector failed: $Name"
}

$root = Split-Path -Parent $PSScriptRoot
$header = Get-Content -Raw (Join-Path $root 'Core\Inc\control_a5_math.h')
$source = Get-Content -Raw (Join-Path $root 'Core\Src\control_a5_math.c')
$captureHeader = Get-Content -Raw (Join-Path $root 'Core\Inc\control_a5_capture.h')
$mode = Get-Content -Raw (Join-Path $root 'Core\Inc\app_mode.h')
$engine = Get-Content -Raw (Join-Path $root 'Core\Src\control_engine.c')

Assert-True ($header -match 'CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1' -and
    $header -match 'CONTROL_A5_SAMPLE_COUNT\s+2048U' -and
    $header -match 'CONTROL_A5_PERIOD_MS\s+1U' -and
    $header -match 'CONTROL_A5_CAPTURE_MS\s+2048U' -and
    $header -match 'CONTROL_A5_ELECTRICAL_OFFSET_RAW\s+7971U' -and
    $header -match 'CONTROL_A5_COMMAND_POWER_PPM\s+350000U') `
    'A5 approved identity/sample/hold constants are not locked.'
Assert-True ($header -match '_Static_assert\(sizeof\(ControlA5Sample_t\) == 12U' -and
    $header -match '== 24576U') 'A5 24 KiB evidence layout is not locked.'
Assert-True ($header -match 'ControlA5Result_t' -and
    $header -match 'ControlA5InvalidReason_t' -and
    $header -match 'ControlA5Stats_t' -and
    $header -match 'ControlA5Summary_t' -and
    $header -match 'ControlA5Report_t') 'A5 data/validity model is incomplete.'
Assert-True ($source -match 'ControlA5_WrapDeltaRaw' -and
    $source -match 'ControlA5_MeanRelRawQ16' -and
    $source -match 'ControlA5_RawWordsCrc32' -and
    $source -match 'ControlA5_ScheduleErrorCycles' -and
    $source -match 'ControlA5_StatsPush' -and
    $source -match 'ControlA5_StatsFinalize' -and
    $source -match 'ControlA5_MathSelfTest') 'A5 pure math implementation is incomplete.'
Assert-True ($source -notmatch '#include\s+"(main|motor|ma600|cmsis_os|FreeRTOS)\.h"' -and
    $source -notmatch 'HAL_|Motor_|ControlLog|printf|UART|osDelay|DWT->') `
    'A5.1 pure module unexpectedly depends on hardware/runtime behavior.'
Assert-True ($mode -match 'CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1') `
    'A5.4 must have switched the active app profile to A5.'
Assert-True ($captureHeader -match 'CONTROL_A5_CAPTURE_INTEGRATION_ENABLED\s+1U' -and
    $engine -match 'if \(CONTROL_A5_CAPTURE_INTEGRATION_ENABLED != 0U\)' -and
    $engine -match '(?s)else\s*\{\s*ControlRunA4\(\);\s*\}') `
    'A5.4 must activate capture while keeping the A4B fallback path compiled.'

Assert-Vector 'constant' @(1000,1000,1000,1000) 0 0 0 0 0 0 `
    ([Convert]::ToUInt32('A76BE7CF', 16))
Assert-Vector 'wrap' @(65534,65535,0,1) 0 3 3 3 98304 1 `
    ([Convert]::ToUInt32('2A4ECE20', 16))
Assert-Vector 'quantized-noise' @(1000,1001,999,1000) -1 1 2 0 0 2 `
    ([Convert]::ToUInt32('3454243C', 16))
Assert-Vector 'linear-drift' @(100,101,102,103,104,105,106,107) 0 7 7 7 229376 1 `
    ([Convert]::ToUInt32('0386FD67', 16))
Assert-Vector 'impulse' @(1000,1000,1016,1000) 0 16 16 0 262144 16 `
    ([Convert]::ToUInt32('F772B050', 16))

Assert-True ((Get-WrapDelta 65535 0) -eq 1 -and
    (Get-WrapDelta 0 65535) -eq -1 -and
    (Get-WrapDelta 0 32768) -eq -32768) 'A5 wrap boundary contract failed.'

[uint32]$first = [Convert]::ToUInt32('FFFFFF00', 16)
[uint32]$onTime = [uint32](([uint64]$first + 168000) -band 0xFFFFFFFFL)
[uint32]$late = [uint32](([uint64]$onTime + 25) -band 0xFFFFFFFFL)
[uint32]$onTimeDelta = [uint32](
    (([uint64]$onTime + [uint64]4294967296 - [uint64]$first) -band
        [uint64]4294967295))
[uint32]$lateDelta = [uint32](
    (([uint64]$late + [uint64]4294967296 - [uint64]$first) -band
        [uint64]4294967295))
Assert-True ($onTimeDelta -eq 168000 -and
    ([long]$lateDelta - 168000L) -eq 25L) 'A5 DWT wrap/schedule model failed.'

$maxSafeSum = [math]::Truncate([long]::MaxValue / 65536L)
Assert-True (($maxSafeSum + 1L) -gt $maxSafeSum) `
    'A5 overflow boundary vector is invalid.'
Assert-True ($source -match 'sumRelRaw > INT64_MAX / 65536LL' -and
    $source -match 'memcmp\(&overflow, &before, sizeof\(overflow\)\) == 0') `
    'A5 overflow rejection/atomicity self-test is missing.'

Write-Host '[ OK ] A5.1 pure data-model/math deterministic contract passed.'
