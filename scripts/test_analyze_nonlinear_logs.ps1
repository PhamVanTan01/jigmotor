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
        (Join-Path $fixtures 'schema-v5-shadow-360-v2-p05-jig3.txt'),
        (Join-Path $fixtures 'schema-v5-shadow-360-v1-legacy-alias-p05-jig3.txt'),
        (Join-Path $fixtures 'schema-v5-phase3b0-closure-probe-p05-jig3.txt'),
        (Join-Path $fixtures 'schema-v5-preconditioned-10run-p03-jig1.txt'),
        (Join-Path $fixtures 'schema-v5-360grid-closure-p03-jig1.txt'),
        (Join-Path $fixtures 'schema-v5-postturn-residual-p03-jig1.txt')
    ) -OutCsv $csv | Out-Null

    $rows = @(Import-Csv $csv)
    if ($rows.Count -ne 14) {
        throw "Expected 14 parsed records, got $($rows.Count)."
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
            ($shadow.ShadowContractEffectiveVersion -ne 'CANONICAL_Q16_V1') -or
            ($shadow.ShadowContractLegacyAlias -ne '0') -or
            ($shadow.ShadowValid -ne '1') -or
            ($shadow.ShadowEndStatus -ne 'VALID') -or
            ($shadow.ShadowTransactions -ne '16960') -or
            ($shadow.ShadowFailedPoints -ne '0')) {
        throw 'Phase-2B shadow/JIG3 parsing failed.'
    }

    $shadowV2 = $rows | Where-Object {
        $_.Source -eq 'schema-v5-shadow-360-v2-p05-jig3.txt'
    }
    if (($null -eq $shadowV2) -or
            ($shadowV2.ShadowContractVersion -ne 'CANONICAL_Q16_1DEG360_V2') -or
            ($shadowV2.ShadowContractEffectiveVersion -ne 'CANONICAL_Q16_1DEG360_V2') -or
            ($shadowV2.ShadowContractLegacyAlias -ne '0')) {
        throw 'Current 360-point V2 shadow contract parsing failed.'
    }

    $shadowLegacyAlias = $rows | Where-Object {
        $_.Source -eq 'schema-v5-shadow-360-v1-legacy-alias-p05-jig3.txt'
    }
    if (($null -eq $shadowLegacyAlias) -or
            ($shadowLegacyAlias.ShadowContractVersion -ne 'CANONICAL_Q16_V1') -or
            ($shadowLegacyAlias.ShadowContractEffectiveVersion -ne 'CANONICAL_Q16_1DEG360_V2') -or
            ($shadowLegacyAlias.ShadowContractLegacyAlias -ne '1')) {
        throw 'Historical 360-point/V1 alias parsing failed.'
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

    # Guards the index-256 -> index-360 closure fix: this fixture declares
    # AnalysisPoints=360 and puts a deliberately wrong-looking value at DATA
    # point 256 (error=-5.0) so a regression to a hardcoded legacy index 256
    # would compute ClosureErrorDeg=-5.01 instead of the correct -0.09 from
    # DATA point 360. See docs/measured-and-checked-parameters.md.
    $grid360 = $rows | Where-Object { $_.Source -eq 'schema-v5-360grid-closure-p03-jig1.txt' }
    if (($null -eq $grid360) -or
            ($grid360.ClosureMeaning -ne 'DIAGNOSTIC_SCHEMA_V5_PILOT') -or
            ([math]::Abs([double]$grid360.ClosureErrorDeg - -0.09) -gt 0.000001) -or
            ($grid360.ClosureValid -ne '1')) {
        throw "Schema-v5 360-point-grid closure fallback did not resolve DATA point 360 (got ClosureErrorDeg=$($grid360.ClosureErrorDeg))."
    }

    # Post-turn residual (docs/b0b-v3-no-reversal-plan.md muc 4/5): fixture has
    # known post[i]/normalized[i] values (i=1..10, odd/even alternating 0.3/0.5
    # before closure-normalization) so the three metrics are hand-verifiable,
    # not just "the analyzer agrees with itself":
    #   post[i]       alternates 0.3 (odd i) / 0.5 (even i)
    #   legacyClosure = Error[360]-Error[0] = -0.08 - 0.01 = -0.09
    #   normalized[i] = post[i] - legacyClosure -> 0.39 (odd) / 0.59 (even)
    #   PostTurnRepeatRMSDeg            = sqrt(mean(post^2))       = sqrt(0.17)   = 0.41231056...
    #   ClosureNormalizedDeltaRMSDeg    = sqrt(mean(normalized^2)) = sqrt(0.2501) = 0.50009999...
    #   ClosureNormalizedDeltaMaxAbsDeg = max(|normalized|)                      = 0.59
    $postTurn = $rows | Where-Object { $_.Source -eq 'schema-v5-postturn-residual-p03-jig1.txt' }
    if (($null -eq $postTurn) -or
            ($postTurn.PostTurnAnalysisValid -ne '1') -or
            ([math]::Abs([double]$postTurn.PostTurnRepeatRMSDeg - 0.412310562561766) -gt 0.000001) -or
            ([math]::Abs([double]$postTurn.ClosureNormalizedDeltaRMSDeg - 0.500099990001999) -gt 0.000001) -or
            ([math]::Abs([double]$postTurn.ClosureNormalizedDeltaMaxAbsDeg - 0.59) -gt 0.000001)) {
        throw "Post-turn residual fixture did not resolve the expected RMS/MaxAbs values (got PostTurnRepeatRMSDeg=$($postTurn.PostTurnRepeatRMSDeg), ClosureNormalizedDeltaRMSDeg=$($postTurn.ClosureNormalizedDeltaRMSDeg), ClosureNormalizedDeltaMaxAbsDeg=$($postTurn.ClosureNormalizedDeltaMaxAbsDeg), PostTurnAnalysisValid=$($postTurn.PostTurnAnalysisValid))."
    }

    # AnalysisStartRaw export (docs/b0b-v3-no-reversal-plan.md muc 6.2 sector
    # gate needs this column downstream) -- the postturn-residual fixture's
    # META line was given AnalysisStartRaw=65530 specifically to also double
    # as a near-wrap-boundary sanity value.
    if ([double]$postTurn.AnalysisStartRaw -ne 65530) {
        throw "AnalysisStartRaw did not export correctly (got $($postTurn.AnalysisStartRaw), expected 65530)."
    }

    # docs/b0b-v3-no-reversal-plan.md muc 6.2: circular-delta/circular-mean/
    # sector-gate math, dot-sourced so the pure functions are directly
    # testable against hand-computed values (not just "the analyzer agrees
    # with itself"). Dot-sourcing re-runs the script's own -Path/-OutCsv
    # parse over a harmless fixture into a throwaway CSV; only the function
    # definitions are what this block actually needs.
    $sectorGateCsv = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-analyzer-sectorgate.csv'
    try {
        . $analyzer -Path (Join-Path $fixtures 'schema-v5-postturn-residual-p03-jig1.txt') -OutCsv $sectorGateCsv | Out-Null

        # CircularDelta must handle the 65535->0 wrap: 5 is 11 raw steps CW
        # past 65530 (65536-65530=6, +5=11), not the naive -65525.
        $delta = Get-CircularDeltaRaw -Value 5 -Reference 65530
        if ([Math]::Abs($delta - 11.0) -gt 0.000001) {
            throw "Get-CircularDeltaRaw wrap case wrong: got $delta, expected 11."
        }
        $deltaReverse = Get-CircularDeltaRaw -Value 65530 -Reference 5
        if ([Math]::Abs($deltaReverse - (-11.0)) -gt 0.000001) {
            throw "Get-CircularDeltaRaw reverse wrap case wrong: got $deltaReverse, expected -11."
        }

        # CircularMean of a boundary-straddling, symmetric pair {65534, 2}
        # (each 2 raw steps from 0 on opposite sides) must land on 0, not the
        # naive arithmetic mean (~32768, the opposite side of the circle).
        $circMean = Get-CircularMeanRaw -Values @(65534, 2)
        if ([Math]::Abs($circMean - 0.0) -gt 0.000001) {
            throw "Get-CircularMeanRaw wrap case wrong: got $circMean, expected 0."
        }

        # Full sector gate, hand-computed (no wrap, to isolate the
        # interpolation/gate logic from the circular-wrap logic already
        # covered above): A0-before ref=100 @t=5, A0-after ref=200 @t=105 ->
        # unwrapped after=200 (100+CircularDelta(200,100)=100+100). B run at
        # t=55 (the exact midpoint) expects 100+(200-100)*0.5=150.
        #   run1 AnalysisStartRaw=150 (exact)   -> SectorError=0   -> pass
        #   run2 AnalysisStartRaw=170 (+20 off) -> SectorError=20  -> fail (tolerance=15)
        # n=2 -> RequiredPassCount=ceil(0.9*2)=2, PassCount=1 -> GatePass=false
        # (deliberately includes one failing run so this proves the gate
        # actually discriminates, not just "always true").
        $gate = Get-V32SectorGateResult `
            -A0BeforeAnalysisStartRaw @(100, 100) -A0BeforeTimestamp @(0, 10) `
            -A0AfterAnalysisStartRaw @(200, 200) -A0AfterTimestamp @(100, 110) `
            -BAnalysisStartRaw @(150, 170) -BTimestamp @(55, 55) `
            -SectorToleranceRaw 15
        if ([Math]::Abs($gate.A0BeforeRef - 100.0) -gt 0.000001 -or
                [Math]::Abs($gate.A0AfterRefUnwrapped - 200.0) -gt 0.000001 -or
                [Math]::Abs($gate.PerRun[0].SectorErrorRaw - 0.0) -gt 0.000001 -or
                [Math]::Abs($gate.PerRun[1].SectorErrorRaw - 20.0) -gt 0.000001 -or
                ($gate.PerRun[0].Pass -ne $true) -or
                ($gate.PerRun[1].Pass -ne $false) -or
                ($gate.PassCount -ne 1) -or
                ($gate.RequiredPassCount -ne 2) -or
                ($gate.GatePass -ne $false)) {
            throw "Get-V32SectorGateResult did not match the hand-computed synthetic batch (got PassCount=$($gate.PassCount)/$($gate.RequiredPassCount), GatePass=$($gate.GatePass), errors=[$($gate.PerRun[0].SectorErrorRaw),$($gate.PerRun[1].SectorErrorRaw)])."
        }
    }
    finally {
        Remove-Item -LiteralPath $sectorGateCsv -Force -ErrorAction SilentlyContinue
    }

    Write-Host '[ OK ] Analyzer regression tests passed.'
}
finally {
    Remove-Item -LiteralPath $csv -Force -ErrorAction SilentlyContinue
}
