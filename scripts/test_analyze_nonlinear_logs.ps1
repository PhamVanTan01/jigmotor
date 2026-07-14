$ErrorActionPreference = 'Stop'

$analyzer = Join-Path $PSScriptRoot 'analyze_nonlinear_logs.ps1'
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$csv = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-analyzer-regression.csv'

try {
    & $analyzer -Path @(
        (Join-Path $fixtures 'schema-v5-p03-jig1-misleading-name.txt'),
        (Join-Path $fixtures 'legacy-p03-jig9.txt'),
        (Join-Path $fixtures 'schema-v4-p03-jig1.txt'),
        (Join-Path $fixtures 'schema-v6-valid-p03-jig1.txt'),
        (Join-Path $fixtures 'schema-v6-invalid-p03-jig2.txt'),
        (Join-Path $fixtures 'schema-v5-interrupted-preamble-p03-jig2.txt'),
        (Join-Path $fixtures 'schema-v5-shadow-p05-jig3.txt'),
        (Join-Path $fixtures 'schema-v5-phase3b0-closure-probe-p05-jig3.txt'),
        (Join-Path $fixtures 'schema-v5-preconditioned-10run-p03-jig1.txt')
    ) -OutCsv $csv | Out-Null

    $rows = @(Import-Csv $csv)
    if ($rows.Count -ne 10) {
        throw "Expected 10 parsed records, got $($rows.Count)."
    }

    $schema5Misleading = $rows | Where-Object {
        $_.Source -eq 'schema-v5-p03-jig1-misleading-name.txt'
    }
    if (($null -eq $schema5Misleading) -or
            ($schema5Misleading.Jig -ne 'JIG2') -or
            ($schema5Misleading.MCU_UID -ne '0025002C3234470438353535')) {
        throw 'Schema-v5 META/UID did not override the misleading filename.'
    }

    $legacy = $rows | Where-Object { $_.SchemaVersion -eq 'LEGACY' }
    if ($null -eq $legacy -or $legacy.Jig -ne '9') {
        throw 'Legacy filename fallback changed unexpectedly.'
    }

    $validV6 = $rows | Where-Object { $_.SchemaVersion -eq '6' -and $_.OfficialMeasurementValid -eq '1' }
    $invalidV6 = $rows | Where-Object { $_.SchemaVersion -eq '6' -and $_.OfficialMeasurementValid -eq '0' }
    if (($null -eq $validV6) -or
            ($validV6.EndStatus -ne 'VALID') -or
            ($validV6.MathContractVersion -ne 'CANONICAL_Q16_V1') -or
            ($validV6.CanonicalMeanSource -ne 'ALL_TIER1') -or
            ($validV6.OfficialInvalidReasonMask -ne '0x00000000') -or
            ($validV6.SettleTargetProximityValid -ne '1') -or
            ($validV6.ClosureValid -ne '1') -or
            ($null -eq $invalidV6) -or
            ($invalidV6.EndStatus -ne 'INVALID') -or
            ($invalidV6.OfficialInvalidReasonMask -eq '0x00000000') -or
            ($invalidV6.SettleTargetProximityValid -ne '0') -or
            ($invalidV6.ClosureValid -ne '0')) {
        throw 'Schema-v6 valid/diagnostic contract parsing failed.'
    }

    $mismatchRejected = $false
    try {
        & $analyzer -Path (Join-Path $fixtures 'schema-v6-uid-mismatch.txt') | Out-Null
    }
    catch {
        $mismatchRejected = $true
    }
    if (-not $mismatchRejected) {
        throw 'Known UID/JigID mismatch was not rejected.'
    }

    $interrupted = $rows | Where-Object {
        $_.SchemaVersion -eq '5' -and $_.SessionID -eq 'ABC00001'
    }
    if (($null -eq $interrupted) -or
            ($interrupted.BatchID -ne '2') -or
            ($interrupted.TestID -ne '2') -or
            ($interrupted.SweepID -ne '1') -or
            ($interrupted.Run -ne '1')) {
        throw 'Interrupted-preamble/session identity parsing failed.'
    }

    $shadow = $rows | Where-Object {
        $_.Source -eq 'schema-v5-shadow-p05-jig3.txt'
    }
    if (($null -eq $shadow) -or
            ($shadow.Jig -ne 'JIG3') -or
            ($shadow.MetaMotorID -ne 'p05') -or
            ($shadow.MotorIdentityConsistent -ne '1') -or
            ($shadow.OfficialResultSource -ne 'LEGACY') -or
            ($shadow.ShadowContractVersion -ne 'CANONICAL_Q16_V1') -or
            ($shadow.ShadowValid -ne '1') -or
            ($shadow.ShadowEndStatus -ne 'VALID') -or
            ($shadow.ShadowTransactions -ne '16960') -or
            ($shadow.ShadowFailedPoints -ne '0')) {
        throw 'Phase-2B shadow/JIG3 parsing failed.'
    }

    $closureProbe = $rows | Where-Object { $_.ClosureProbeEnabled -eq '1' }
    if (($null -eq $closureProbe) -or
            ($closureProbe.ClosureProbeProtocol -ne 'CLOSURE_HOLD_V1') -or
            ($closureProbe.ClosureProbeStatus -ne 'VALID') -or
            ($closureProbe.ClosureProbeComplete -ne '1') -or
            ($closureProbe.ClosureProbeValidStages -ne '4') -or
            ($closureProbe.PostTurnTimingComparable -ne '0') -or
            ([math]::Abs([double]$closureProbe.ClosureProbeInitialDeg - -0.00549) -gt 0.000001) -or
            ([math]::Abs([double]$closureProbe.ClosureProbeDelta200InitialDeg - 0.01648) -gt 0.000001)) {
        throw 'Phase-3B0 closure-probe parsing failed.'
    }

    $precondition = $rows | Where-Object { $_.RunRole -eq 'PRECONDITION' }
    $preconditionedOfficial = $rows | Where-Object {
        $_.Source -eq 'schema-v5-preconditioned-10run-p03-jig1.txt' -and
        $_.RunRole -eq 'OFFICIAL'
    }
    if (($null -eq $precondition) -or
            ($precondition.Run -ne '0') -or
            ($precondition.EligibleForStatistics -ne '0') -or
            ($null -eq $preconditionedOfficial) -or
            ($preconditionedOfficial.Run -ne '1') -or
            ($preconditionedOfficial.EligibleForStatistics -ne '1')) {
        throw 'Precondition/official statistical eligibility parsing failed.'
    }

    Write-Host '[ OK ] Analyzer regression tests passed.'
}
finally {
    Remove-Item -LiteralPath $csv -Force -ErrorAction SilentlyContinue
}
