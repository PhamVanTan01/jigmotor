$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-SettleModelResult {
    param([int[]]$DeltaRaw, [int[]]$PositionErrorRaw)
    $stableCount = 0
    $combinedCount = 0
    $stableEver = $false
    for ($i = 0; $i -lt $DeltaRaw.Count; $i++) {
        $stable = [math]::Abs($DeltaRaw[$i]) -le 9
        $near = [math]::Abs($PositionErrorRaw[$i]) -le 910
        $stableCount = if ($stable) { $stableCount + 1 } else { 0 }
        $combinedCount = if ($stable -and $near) { $combinedCount + 1 } else { 0 }
        if ($stableCount -ge 8) { $stableEver = $true }
        if ($combinedCount -ge 8) { return 'OK' }
    }
    if ($stableEver -and [math]::Abs($PositionErrorRaw[-1]) -gt 910) {
        return 'WRONG_POSITION'
    }
    return 'TIMEOUT'
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')
$motorConfig = Get-Content -Raw (Join-Path $root 'Core\Inc\motor_config.h')
$analyzerSource = Get-Content -Raw (Join-Path $PSScriptRoot 'analyze_nonlinear_logs.ps1')
$fixture = Join-Path $PSScriptRoot 'fixtures\schema-v5-phase3a-motion-p03-jig2.txt'
$csv = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-phase3a-motion-contract.csv'

try {
    Assert-True ($motorConfig -match '#define\s+MOTOR_NUM_POLSE\s+12U') `
        'The PIXY 12-pole motor configuration is not the default geometry.'
    Assert-True ($motorConfig -match '#define\s+MOTOR_POLE_PAIRS\s+\(MOTOR_NUM_POLSE\s*/\s*2U\)') `
        'Pole pairs are not derived from the physical pole count.'
    Assert-True ($motorConfig -match 'MOTOR_NUM_POLSE\s*%\s*2U') `
        'Odd physical pole counts are not rejected at build time.'

    $sweepInitMatches = [regex]::Matches($source, 'MA600_AcquisitionInit\s*\(\s*&sweepAcquisition\s*\)')
    Assert-True ($sweepInitMatches.Count -eq 1) `
        'CaptureSweep must create exactly one continuous acquisition context.'
    Assert-True ($source -match 'WaitForPointSettle\s*\(\s*MA600_AcquisitionContext_t\s*\*sweepAcquisition') `
        'Settle does not consume the caller-owned continuous context.'
    Assert-True ($source -match 'stable\s*&&\s*\(!targetRequired\s*\|\|\s*targetNear\)' -and
            $source -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\s*#define NL_SETTLE_CONTRACT_ID\s+"STABILITY_ONLY_CAPTURE_V1".*?#else\s*#define NL_SETTLE_CONTRACT_ID\s+"STABILITY_AND_TARGET_V1"') `
        'Settle must be stability-only for official open-loop capture and stability+target for legacy diagnostics.'
    Assert-True ($source -match 'NL_SETTLE_WRONG_POSITION') `
        'Stable-at-wrong-position classification is missing.'
    Assert-True ($source -match 'SetEngineState\(NL_ENGINE_RAMP\)[\s\S]*?MA600_AcquireSample\s*\(\s*&sweepAcquisition') `
        'Encoder feedback is not sampled during the ramp.'
    Assert-True ($source -match 'const\s+int64_t\s+pointAnchorUnwrapped\s*=\s*settleObservation\.finalSample\.unwrappedRaw') `
        'Canonical point anchor is not frozen from the post-settle observation.'
    Assert-True ($source -match 'CaptureCanonicalPointFromSweepContext\(\s*&sweepAcquisition, pointAnchorUnwrapped' -and
            $source -match 'MA600_ReadAveragedPoint\(&shadowUnwrap,\s*pointAnchorUnwrapped') `
        'Canonical sampling must use the post-settle anchor in both official and diagnostic profiles.'
    Assert-True ($source -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP.*?OfficialResultSource=CANONICAL_Q16.*?#else.*?OfficialResultSource=LEGACY') `
        'Official schema-v6 and diagnostic schema-v5 result sources are not isolated.'
    Assert-True ($source -match 'MotorPoleCount=%u,MotorPolePairs=%u' -and
            $source -match 'ElectricalRippleOrder=%u' -and
            $source -match 'AElectrical6=%s') `
        'Pole geometry or electrical-ripple audit fields are missing.'
    Assert-True ($source -notmatch 'measurementValid\s*=.*IsMotorIdConfigured') `
        'Motor ID unexpectedly became part of the measurement-valid gate.'
    Assert-True ($analyzerSource -match 'MOTION_RESULT' -and
            $analyzerSource -match 'ContextReacquireCount') `
        'Analyzer does not enforce/export the Phase-3A motion contract.'

    Assert-True ((Get-SettleModelResult @(1,1,1,1,1,1,1,1) @(10,10,10,10,10,10,10,10)) -eq 'OK') `
        'Deterministic settle model rejected stable and near samples.'
    Assert-True ((Get-SettleModelResult @(1,1,1,1,1,1,1,1) @(1000,1000,1000,1000,1000,1000,1000,1000)) -eq 'WRONG_POSITION') `
        'Deterministic settle model did not distinguish stable-but-wrong position.'
    Assert-True ((Get-SettleModelResult @(20,20,20,20,20,20,20,20) @(10,10,10,10,10,10,10,10)) -eq 'TIMEOUT') `
        'Deterministic settle model accepted unstable samples.'

    powershell -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $PSScriptRoot 'analyze_nonlinear_logs.ps1') -Path $fixture -OutCsv $csv | Out-Null
    $rows = @(Import-Csv $csv)
    Assert-True ($rows.Count -eq 1) 'Phase-3A fixture did not produce exactly one record.'
    $row = $rows[0]
    Assert-True ($row.MotorPoleCount -eq '12' -and $row.MotorPolePairs -eq '6' -and
            $row.ElectricalRippleOrder -eq '36' -and $row.AElectrical6 -eq '0.91') `
        'Pole geometry/electrical-ripple fields were not parsed correctly.'
    Assert-True ($row.ContinuousSweepContext -eq 'SWEEP_CONTEXT_V1' -and
            $row.ContextReacquireCount -eq '0' -and
            $row.RampAcceptedSamples -eq '8448' -and
            $row.SettleAcceptedSamples -eq '2385') `
        'Continuous motion acquisition counters were not parsed correctly.'
    Assert-True ($row.SettleStabilityValid -eq '1' -and
            $row.SettleTargetProximityValid -eq '1' -and $row.SettleValid -eq '1') `
        'Settle aggregate validity was not parsed correctly.'

    Write-Host '[ OK ] Phase-3A continuous motion/settle/pole contract tests passed.'
}
finally {
    Remove-Item -LiteralPath $csv -Force -ErrorAction SilentlyContinue
}
