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
    Assert-True ($source -match '(?s)0x0049003A,\s*0x3034510B,\s*0x31363339,\s*"JIG4".*?\{\s*0x0000,\s*0x00,\s*0x05,\s*0x00,\s*0x00,\s*0x00,\s*0x190A55AD\s*\}') `
        'Firmware UID registry is missing the locked JIG4 profile (corrected 2026-07-27; Zero=0x0000, confirmed across 33 gated reads over 3 sessions -- the earlier 0x00E7 lock was a stale/transient read).'
    Assert-True ($analyzerSource -match "0049003A3034510B31363339'\s*=\s*'JIG4'") `
        'Host UID registry is missing JIG4.'
    Assert-True ($source -match '(?s)0x001D0028,\s*0x32344704,\s*0x38353535,\s*"JIG5".*?\{\s*0x0000,\s*0x00,\s*0x05,\s*0x00,\s*0x00,\s*0x00,\s*0x190A55AD\s*\}') `
        'Firmware UID registry is missing the locked JIG5 profile (new control board, 2026-07-27; Zero=0x0000 confirmed across two power cycles via PRECONDITION_PRE_MOTOR, not the unreliable BOOT_SMOKE read).'
    Assert-True ($analyzerSource -match "001D00283234470438353535'\s*=\s*'JIG5'") `
        'Host UID registry is missing JIG5.'
    Assert-True ($source -match '(?s)0x00510032,\s*0x32355118,\s*0x35383831,\s*"JIG6".*?\{\s*0x0000,\s*0x00,\s*0x05,\s*0x00,\s*0x00,\s*0x00,\s*0x190A55AD\s*\}') `
        'Firmware UID registry is missing the JIG6 placeholder profile (new control board, 2026-07-28; registered from a bare MCU_UID read before the MA600 sensor was attached -- profile is an unconfirmed placeholder matching JIG1-5, pending a real post-assembly read).'
    Assert-True ($analyzerSource -match "005100323235511835383831'\s*=\s*'JIG6'") `
        'Host UID registry is missing JIG6.'
    Assert-True ($source -match '(?s)0x00460032,\s*0x32355118,\s*0x35383831,\s*"JIG7".*?\{\s*0x0000,\s*0x00,\s*0x05,\s*0x00,\s*0x00,\s*0x00,\s*0x190A55AD\s*\}') `
        'Firmware UID registry is missing the JIG7 profile (new control board, 2026-07-28; registered from a single real CONFIG read, matching JIG1-6 -- needs re-verification across more reads before full trust).'
    Assert-True ($analyzerSource -match "004600323235511835383831'\s*=\s*'JIG7'") `
        'Host UID registry is missing JIG7.'

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
