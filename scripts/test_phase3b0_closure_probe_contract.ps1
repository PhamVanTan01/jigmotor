$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')
$acquisitionHeader = Get-Content -Raw (Join-Path $root 'Core\Inc\ma600_acquisition.h')
$acquisitionSource = Get-Content -Raw (Join-Path $root 'Core\Src\ma600_acquisition.c')
$analyzer = Join-Path $PSScriptRoot 'analyze_nonlinear_logs.ps1'
$fixture = Join-Path $PSScriptRoot 'fixtures\schema-v5-phase3b0-closure-probe-p05-jig3.txt'
$csv = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-phase3b0-closure-probe.csv'
$invalidBaseline = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-phase3b0-invalid-baseline.txt'
$invalidCommand = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-phase3b0-invalid-command.txt'

try {
    Assert-True ($source -match '#define\s+ENABLE_CLOSURE_HOLD_PROBE\s+1') `
        'The passive closure hold probe is not enabled by default.'
    Assert-True ($source -match 'NL_CLOSURE_PROBE_PROTOCOL_ID\s+"CLOSURE_HOLD_V1"') `
        'The closure probe protocol ID changed unexpectedly.'
    Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5' -and
            $source -match 'OfficialResultSource=LEGACY') `
        'Phase-3B0 changed the official schema-v5/legacy result contract.'
    Assert-True ($source -match 'RecordClosureProbeStage\(out,\s*0U,\s*baselinePoint') `
        'INITIAL no longer copies the exact Point-256 shadow baseline.'
    Assert-True ($source -match 'CaptureClosureHoldProbe\(out,\s*&shadowUnwrap') `
        'The hold probe is not continuing the existing shadow unwrap context.'
    Assert-True ($source -match 'pointIndex\s*==\s*\(int\)NL_CLOSURE_POINT_INDEX') `
        'The hold probe is not anchored at the full-turn Point 256.'
    Assert-True ($source -match 'out->postTurnTimingComparable\s*=\s*false') `
        'The intentional post-turn timing discontinuity is not recorded.'
    Assert-True ($source -match 'probeResult\s*!=\s*MA600_RESULT_OK[\s\S]*?acquisitionResult\s*=\s*probeResult[\s\S]*?goto\s+capture_complete') `
        'A probe acquisition failure no longer exits through the sweep safe-stop path.'
    Assert-True ($source -match 'CLOSURE_PROBE_RESULT' -and
            $source -match 'PostTurnTimingComparable=%d' -and
            $source -match 'Official=0,Protocol=%s') `
        'The non-official closure-probe audit records are incomplete.'
    Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
        'Probe numeric values leaked into the official measurement-valid gate.'

    $probeFunction = [regex]::Match($source,
        'static MA600_Result_t CaptureClosureHoldProbe[\s\S]*?(?=static void ComputeShadowMetrics)').Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($probeFunction)) `
        'Could not locate CaptureClosureHoldProbe for static checks.'
    Assert-True ($probeFunction -notmatch 'Motor_SetElectricalPos|Motor_SetPower|PID|PWM') `
        'The passive hold probe must not alter motor command, power, PID, or PWM.'
    Assert-True ($probeFunction -match '0U,\s*50U,\s*100U,\s*200U') `
        'The required 0/50/100/200 ms stages changed.'

    Assert-True ($acquisitionHeader -match 'firstAcceptedUnwrapped') `
        'Point-window first accepted position is missing.'
    Assert-True ($acquisitionSource -match 'acceptedSampleCount\s*==\s*0U[\s\S]*?firstAcceptedUnwrapped\s*=\s*acceptedUnwrapped') `
        'Window drift does not preserve the first accepted position.'
    Assert-True ($acquisitionSource -match 'firstAcceptedUnwrapped\s*==\s*100LL' -and
            $acquisitionSource -match 'firstAcceptedUnwrapped\s*==\s*65534LL') `
        'Point-window first/last deterministic self-tests are incomplete.'
    Assert-True ($acquisitionSource -match 'alternatingWindowOk' -and
            $acquisitionSource -match 'maxRelRaw\s*-\s*point\.minRelRaw\s*==\s*8LL' -and
            $acquisitionSource -match 'monotonicWindowOk' -and
            $acquisitionSource -match 'lastAcceptedUnwrapped\s*-\s*point\.firstAcceptedUnwrapped\s*==\s*3LL') `
        'Deterministic alternating-P2P or monotonic-drift coverage is missing.'
    Assert-True ($acquisitionSource -match 'MA600_AcquisitionRunFaultInjectionSelfTest' -and
            $acquisitionSource -match 'ctx\.acceptedSamples\s*==\s*0U' -and
            $acquisitionSource -match '!ctx\.unwrap\.initialized') `
        'Fault-injection coverage no longer proves rejected input leaves unwrap state unchanged.'

    & $analyzer -Path $fixture -OutCsv $csv | Out-Null
    $rows = @(Import-Csv $csv)
    Assert-True ($rows.Count -eq 1) `
        'Phase-3B0 fixture did not produce exactly one record.'
    $row = $rows[0]
    Assert-True ($row.OfficialResultSource -eq 'LEGACY' -and
            $row.ClosureProbeProtocol -eq 'CLOSURE_HOLD_V1' -and
            $row.ClosureProbeStatus -eq 'VALID' -and
            $row.ClosureProbeComplete -eq '1' -and
            $row.ClosureProbeValidStages -eq '4' -and
            $row.PostTurnTimingComparable -eq '0') `
        'Parsed Phase-3B0 contract is incomplete.'
    Assert-True ([math]::Abs([double]$row.ClosureProbeInitialDeg - -0.00549) -lt 0.000001 -and
            [math]::Abs([double]$row.ClosureProbeDelta200InitialDeg - 0.01648) -lt 0.000001) `
        'Phase-3B0 hold deltas were not exported correctly.'

    $fixtureText = Get-Content -Raw $fixture
    $initialRegex = [regex]::new(
        '(?m)(^CLOSURE_PROBE,.*Stage=INITIAL,.*ClosureErrorRawQ16=)-65536')
    $invalidBaselineText = $initialRegex.Replace($fixtureText, '$1-131072', 1)
    [System.IO.File]::WriteAllText($invalidBaseline, $invalidBaselineText)
    $baselineRejected = $false
    try { & $analyzer -Path $invalidBaseline | Out-Null } catch { $baselineRejected = $true }
    Assert-True $baselineRejected `
        'Analyzer accepted an INITIAL value that differs from Point-256 shadow closure.'

    $hold200Regex = [regex]::new(
        '(?m)(^CLOSURE_PROBE,.*Stage=HOLD_200,.*CommandRaw=)65536')
    $invalidCommandText = $hold200Regex.Replace($fixtureText, '$1' + '65535', 1)
    [System.IO.File]::WriteAllText($invalidCommand, $invalidCommandText)
    $commandRejected = $false
    try { & $analyzer -Path $invalidCommand | Out-Null } catch { $commandRejected = $true }
    Assert-True $commandRejected `
        'Analyzer accepted a command change during the passive hold.'

    Write-Host '[ OK ] Phase-3B0 passive closure hold contract tests passed.'
}
finally {
    Remove-Item -LiteralPath $csv -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $invalidBaseline -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $invalidCommand -Force -ErrorAction SilentlyContinue
}
