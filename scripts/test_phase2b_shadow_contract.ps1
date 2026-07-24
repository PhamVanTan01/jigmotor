$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')
$analyzerSource = Get-Content -Raw (Join-Path $PSScriptRoot 'analyze_nonlinear_logs.ps1')
$fixture = Join-Path $PSScriptRoot 'fixtures\schema-v5-shadow-p05-jig3.txt'
$csv = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-phase2b-shadow-contract.csv'

try {
    Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5') `
        'Phase-2B must not promote the official schema to v6.'
    Assert-True ($source -match 'OfficialResultSource=LEGACY') `
        'Phase-2B META no longer declares legacy as official.'
    Assert-True ($source -match 'MA600_ReadAveragedPoint\s*\(\s*&shadowUnwrap') `
        'Canonical point sampler is not wired to the independent shadow context.'
    Assert-True ($source -match 'MA600_ComputeCanonicalErrorAtTargetQ16' -and
            $source -match 'NlTargetRawForPoint') `
        'Shadow error is not derived from the rounded one-degree target through the canonical helper.'
    Assert-True ($source -match 'SHADOW_META' -and $source -match 'SHADOW_DATA' -and
            $source -match 'SHADOW_ACQ' -and $source -match 'SHADOW_RESULT' -and
            $source -match 'SHADOW_END') `
        'One or more Phase-2B shadow records are missing.'
    Assert-True ($source -match 'shadowTransactionCount' -and
            $source -match 'shadowAcceptedSampleCount' -and
            $source -match 'shadowMetadataInvalidCount' -and
            $source -match 'shadowFailedPointCount') `
        'Shadow acquisition counters are not separated from legacy counters.'
    Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
        'Shadow state has leaked into legacy MeasurementValid.'
    Assert-True ($source -notmatch 'pwmCounterSamples\s*\[.*\]\s*=\s*0\s*;') `
        'Legacy PWM counter is being replaced by a fabricated shadow value.'
    Assert-True ($source -match 'MotorIDSource=%s,MotorIDValid=%d') `
        'Motor identity provenance fields are missing.'
    Assert-True ($analyzerSource -match "004C003A3034510B31363339'\s*=\s*'JIG3'") `
        'Host UID registry is missing JIG3.'
    Assert-True ($source -match '(?s)0x0049003A,\s*0x3034510B,\s*0x31363339,\s*"JIG4".*?\{\s*0x00D5,\s*0x00,\s*0x0C,\s*0x00,\s*0x80,\s*0x00,\s*0x190A55AD\s*\}') `
        'Firmware UID registry is missing the locked JIG4 profile.'
    Assert-True ($analyzerSource -match "0049003A3034510B31363339'\s*=\s*'JIG4'") `
        'Host UID registry is missing JIG4.'

    & (Join-Path $PSScriptRoot 'analyze_nonlinear_logs.ps1') -Path $fixture -OutCsv $csv | Out-Null
    $rows = @(Import-Csv $csv)
    Assert-True ($rows.Count -eq 1) 'Shadow fixture did not produce exactly one record.'
    $row = $rows[0]
    Assert-True ($row.OfficialResultSource -eq 'LEGACY' -and
            $row.ShadowCanonicalEnabled -eq '1' -and
            $row.ShadowContractVersion -eq 'CANONICAL_Q16_V1' -and
            $row.ShadowValid -eq '1' -and
            $row.ShadowTransactions -eq '16960' -and
            $row.ShadowFailedPoints -eq '0') `
        'Parsed Phase-2B shadow contract is incomplete.'

    Write-Host '[ OK ] Phase-2B shadow source/log contract tests passed.'
}
finally {
    Remove-Item -LiteralPath $csv -Force -ErrorAction SilentlyContinue
}
