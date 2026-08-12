$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')
$analyzer = Join-Path $PSScriptRoot 'analyze_nonlinear_logs.ps1'
$fixture = Join-Path $PSScriptRoot 'fixtures\schema-v5-preconditioned-10run-p03-jig1.txt'
$csv = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-preconditioned-10run.csv'
$invalidEligibility = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-precondition-invalid-eligibility.txt'
$missingResult = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-precondition-missing-result.txt'
$invalidCooldown = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-precondition-invalid-cooldown.txt'

try {
    Assert-True ($source -match '#define\s+NL_TEST_REPEAT_3_RUNS\s+0' -and
            $source -match '#define\s+NL_TEST_REPEAT_10_RUNS\s+1') `
        'Firmware is not configured for the requested ten official runs.'
    Assert-True ($source -match '#define\s+NL_PRECONDITION_COUNT\s+1U' -and
            $source -match 'NL_BATCH_TOTAL_CYCLE_COUNT\s+\(NL_PRECONDITION_COUNT\s*\+\s*NL_OFFICIAL_RUN_COUNT\)' -and
            $source -match 'NL_PRECONDITION_PROTOCOL_ID\s+"ONE_FULL_SWEEP_120S_V1"') `
        'The one-precondition plus ten-official cycle contract is incomplete.'
    Assert-True ($source -match 'officialRunOrder\s*=\s*preconditionRun\s*\?\s*0U[\s\S]*?nlCurrentCycle\s*-\s*NL_PRECONDITION_COUNT') `
        'Precondition RunOrder=0 / official RunOrder=1..10 mapping changed.'
    Assert-True ($source -match '(?s)eligibleForStatistics\s*=\s*\(NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\)\s*&& !preconditionRun\s*&& preconditionValid\s*&& nlCaptures\[i\]\.measurementValid;' -and
            $source -match 'emitLegacyResult\s*=\s*c->eligibleForStatistics') `
        'Precondition can leak into official legacy/statistical output.'
    Assert-True ($source -match 'if\s*\(preconditionRun\)[\s\S]*?PRECONDITION_RESULT[\s\S]*?return true;[\s\S]*?Nonlinear Final Average') `
        'Precondition is not terminated before the final average/Motor OK path.'
    Assert-True ($source -match 'if\s*\(!runValid\)[\s\S]*?Status=FAILED[\s\S]*?return;[\s\S]*?nlPreconditionValid\s*=\s*true') `
        'An invalid precondition may continue into official RunOrder 1.'
    Assert-True ($source -match 'if\s*\(!nlCooldownValid\)[\s\S]*?Reason=COOLDOWN_INVALID[\s\S]*?return;[\s\S]*?nlCurrentCycle\+\+') `
        'An out-of-tolerance cooldown may still advance to the next cycle.'

    & $analyzer -Path $fixture -OutCsv $csv | Out-Null
    $rows = @(Import-Csv $csv)
    Assert-True ($rows.Count -eq 2) 'Precondition fixture did not produce exactly two records.'

    $precondition = $rows | Where-Object { $_.RunRole -eq 'PRECONDITION' }
    $official = $rows | Where-Object { $_.RunRole -eq 'OFFICIAL' }
    Assert-True (($null -ne $precondition) -and
            $precondition.CycleOrder -eq '1' -and
            $precondition.Run -eq '0' -and
            $precondition.EligibleForStatistics -eq '0' -and
            $precondition.PreconditionValid -eq 'NA' -and
            [string]::IsNullOrWhiteSpace($precondition.NLAvg) -and
            [string]::IsNullOrWhiteSpace($precondition.Result)) `
        'Precondition was not preserved as a non-statistical, non-Motor-OK audit record.'
    Assert-True (($null -ne $official) -and
            $official.CycleOrder -eq '2' -and
            $official.Run -eq '1' -and
            $official.EligibleForStatistics -eq '1' -and
            $official.PreconditionValid -eq '1' -and
            $official.NLAvg -eq '3.31' -and
            $official.Result -eq 'OK') `
        'Official run mapping/result contract is invalid.'

    $summaryText = (& $analyzer -Path $fixture -Summary 6>&1 | Out-String)
    Assert-True ($summaryText -match '(?m)^JIG1\s+P03\s+1\s+3\.31') `
        'Analyzer summary counted the ineligible precondition row.'

    $fixtureText = Get-Content -Raw $fixture
    $invalidEligibilityText = [regex]::Replace($fixtureText,
        '(RunRole=PRECONDITION,EligibleForStatistics=)0', '$1' + '1', 1)
    [System.IO.File]::WriteAllText($invalidEligibility, $invalidEligibilityText)
    $eligibilityRejected = $false
    try { & $analyzer -Path $invalidEligibility | Out-Null } catch { $eligibilityRejected = $true }
    Assert-True $eligibilityRejected 'Analyzer accepted a statistical precondition record.'

    $missingResultText = [regex]::Replace($fixtureText,
        '(?m)^PRECONDITION_RESULT,.*\r?\n?', '', 1)
    [System.IO.File]::WriteAllText($missingResult, $missingResultText)
    $missingResultRejected = $false
    try { & $analyzer -Path $missingResult | Out-Null } catch { $missingResultRejected = $true }
    Assert-True $missingResultRejected 'Analyzer accepted a precondition without its audit result.'

    $invalidCooldownText = [regex]::Replace($fixtureText,
        '(RunRole=OFFICIAL,.*?CooldownActualMs=)120050', '$1' + '120301', 1)
    [System.IO.File]::WriteAllText($invalidCooldown, $invalidCooldownText)
    $cooldownRejected = $false
    try { & $analyzer -Path $invalidCooldown | Out-Null } catch { $cooldownRejected = $true }
    Assert-True $cooldownRejected 'Analyzer accepted an out-of-tolerance official cooldown.'

    Write-Host '[ OK ] One-precondition plus ten-official-run contract tests passed.'
}
finally {
    Remove-Item -LiteralPath $csv -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $invalidEligibility -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $missingResult -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $invalidCooldown -Force -ErrorAction SilentlyContinue
}
