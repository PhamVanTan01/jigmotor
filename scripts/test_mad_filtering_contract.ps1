$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$hdr = Get-Content -Raw (Join-Path $root 'Core\Inc\ma600_acquisition.h')
$drv = Get-Content -Raw (Join-Path $root 'Core\Src\ma600_acquisition.c')
$nlt = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')

try {
    # --- Header: constant, new field, both signatures extended. ---
    Assert-True ($hdr -match '#define\s+MA600_MAD_MAX_SAMPLES\s+64U') `
        'MA600_MAD_MAX_SAMPLES constant missing/changed.'
    Assert-True ($hdr -match 'int64_t\s+madFilteredMeanRawQ16;') `
        'MA600_PointSample_t is missing the madFilteredMeanRawQ16 field.'
    Assert-True ($hdr -match '(?s)MA600_Result_t MA600_ReadAveragedPointWithIo\(.*?int64_t \*madRelRawSampleLog,\s*[\r\n]+\s*uint32_t madRelRawSampleLogCapacity,\s*[\r\n]+\s*int64_t madRejectFloorRelRaw,\s*[\r\n]+\s*MA600_PointSample_t \*out\);') `
        'MA600_ReadAveragedPointWithIo declaration is missing the 3 new MAD parameters.'
    Assert-True ($hdr -match '(?s)MA600_Result_t MA600_ReadAveragedPoint\(.*?int64_t \*madRelRawSampleLog,\s*[\r\n]+\s*uint32_t madRelRawSampleLogCapacity,\s*[\r\n]+\s*int64_t madRejectFloorRelRaw,\s*[\r\n]+\s*MA600_PointSample_t \*out\);') `
        'MA600_ReadAveragedPoint declaration is missing the 3 new MAD parameters.'

    # --- Driver: MAD algorithm present, pure integer (no float literals in
    # the new helpers), reuses the existing safe-math/mean helpers. ---
    Assert-True ($drv -match 'static void ComputeMadFilteredPointMean\(') `
        'ComputeMadFilteredPointMean is missing.'
    Assert-True ($drv -match 'static int64_t s_madDeviationScratch\[MA600_MAD_MAX_SAMPLES\];') `
        'MAD deviation scratch buffer (static, not stack) is missing.'
    Assert-True ($drv -match 'static void InsertionSortI64\(' -and
            $drv -match 'static bool MedianOfSortedI64\(') `
        'MAD median helpers are missing.'
    Assert-True ($drv -match '519LL' -and $drv -match '100LL') `
        'MAD reject-threshold multiplier (519/100, pure integer) is missing.'
    Assert-True ($drv -match 'MA600_ComputeCanonicalPointMeanQ16\(pointAnchorUnwrapped, robustSum,\s*[\r\n\s]*robustCount, &discardMeanRel, &out->madFilteredMeanRawQ16\)') `
        'MAD-filtered mean must be computed via the existing MA600_ComputeCanonicalPointMeanQ16 helper, not a new one.'

    # --- Every pre-existing call site defaults NULL/0/0 (behavior-preserving). ---
    $selfTestNullCount = ([regex]::Matches($drv, 'NULL,\s*0U,\s*0,\s*[\r\n\s]*&point\)')).Count
    Assert-True ($selfTestNullCount -eq 6) `
        "Expected 6 self-test call sites defaulted to NULL/0U/0, found $selfTestNullCount."
    Assert-True ($drv -match '(?s)MA600_Result_t MA600_ReadAveragedPoint\(.*?return MA600_ReadAveragedPointWithIo\(sweepCtx, pointAnchorUnwrapped,\s*[\r\n]+\s*config, &io, madRelRawSampleLog, madRelRawSampleLogCapacity,\s*[\r\n]+\s*madRejectFloorRelRaw, out\);') `
        'MA600_ReadAveragedPoint wrapper must forward the 3 new params unchanged, not hardcode NULL/0/0.'
    Assert-True ($nlt -match '(?s)result = MA600_ReadAveragedPoint\(shadowUnwrap, pointAnchorUnwrapped,\s*[\r\n]+\s*config, NULL, 0U, 0, &point\);') `
        'CaptureClosureHoldProbe call site must stay NULL/0U/0 (out of scope for MAD).'

    # --- Main shadow loop: MAD requested only for point 0 and point 360. ---
    Assert-True ($nlt -match '(?s)bool wantMadForThisPoint = \(pointIndex == 0\)\s*[\r\n]+\s*\|\|\s*\(pointIndex == \(int\)NL_CLOSURE_POINT_INDEX\);') `
        'MAD must be requested only for point 0 and point NL_CLOSURE_POINT_INDEX.'
    Assert-True ($nlt -match 'int64_t \*madBuf = wantMadForThisPoint \? nlMadSampleScratch : NULL;') `
        'Main shadow loop must select nlMadSampleScratch only for the 2 Closure-driving points.'
    Assert-True ($nlt -match 'static int64_t nlMadSampleScratch\[MA600_MAD_MAX_SAMPLES\];') `
        'nlMadSampleScratch must be a static workspace, not a stack array.'
    Assert-True ($nlt -match '(?s)MA600_Result_t shadowResult = MA600_ReadAveragedPoint\(&shadowUnwrap,\s*[\r\n]+\s*pointAnchorUnwrapped, &shadowPointConfig, madBuf, madBufCapacity,\s*[\r\n]+\s*madFloor, &shadowPoint\);') `
        'Main shadow loop call site is not wired with the conditional MAD buffer/capacity/floor.'

    # --- Struct/log additions. ---
    Assert-True ($nlt -match '(?s)typedef struct\s*\{\s*bool\s+computed;\s*uint32_t\s+candidateCount;\s*uint32_t\s+rejectedCount;\s*uint32_t\s+robustCount;\s*int64_t\s+madFilteredMeanRawQ16;\s*\}\s*NlShadowMadDiag_t;') `
        'NlShadowMadDiag_t typedef is missing or changed shape.'
    Assert-True ($nlt -match 'NlShadowMadDiag_t shadowPoint0Mad;\s*[\r\n]+\s*NlShadowMadDiag_t shadowPoint360Mad;') `
        'NlSweepCapture_t is missing the shadowPoint0Mad/shadowPoint360Mad fields.'
    Assert-True ($nlt -match 'static void PrintShadowMadLog\(') `
        'PrintShadowMadLog is missing.'
    Assert-True ($nlt -match '"SHADOW_MAD,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"\s*[\r\n]+\s*"Direction=%s,Official=0,PointIndex=%d,Computed=%d,"') `
        'SHADOW_MAD record format missing/changed.'
    Assert-True ($nlt -match 'PrintShadowMadLog\(c, jigId, dirStr\);') `
        'PrintShadowMadLog is not called from PrintSweepLog.'

    # --- RecordShadowPoint: MAD copy is additive, inside the existing
    # success block, gated on point->madFilteringEnabled. ---
    Assert-True ($nlt -match 'if \(point->madFilteringEnabled\)\s*[\r\n]+\s*\{\s*[\r\n]+\s*NlShadowMadDiag_t \*madDst =') `
        'RecordShadowPoint is missing the gated MAD diagnostic copy.'
    Assert-True ($nlt -match 'madDst->madFilteredMeanRawQ16 = point->madFilteredMeanRawQ16;') `
        'RecordShadowPoint must copy madFilteredMeanRawQ16 into the diagnostic struct.'

    # --- CRITICAL: official ClosureErrorDeg / shadowPoint0MeanRawQ16 path
    # is UNCHANGED -- still sourced from the plain pointMeanRawQ16 field,
    # never from madFilteredMeanRawQ16. ---
    Assert-True ($nlt -match 'out->shadowPoint0MeanRawQ16 = point->pointMeanRawQ16;') `
        'RecordShadowPoint no longer sources shadowPoint0MeanRawQ16 from the plain field.'
    Assert-True ($nlt -match (
            "out->shadowPoint0MeanRawQ16 = out->shadowPoints->pointMeanRawQ16\[0\];")) `
        'ComputeShadowMetrics no longer re-derives shadowPoint0MeanRawQ16 from the plain array.'
    Assert-True ($nlt -match '(?s)static bool NlComputeProfileErrorRawQ16\(.*?MA600_ComputeCanonicalErrorAtTargetQ16\(pointMeanRawQ16,\s*point0MeanRawQ16, signedTargetRaw,' -and
            $nlt -match '(?s)NlComputeProfileErrorRawQ16\(\s*out->shadowPoints->pointMeanRawQ16\[i\],\s*out->shadowPoint0MeanRawQ16, signedTargetRaw,') `
        'ClosureErrorRawQ16 no longer computed from the plain pointMeanRawQ16 array.'
    Assert-True ($nlt -notmatch 'ComputeCanonicalErrorAtTargetQ16\([^)]*madFilteredMeanRawQ16') `
        'madFilteredMeanRawQ16 must never feed the official error/closure computation.'
    Assert-True ($nlt -notmatch 'shadowPoint0MeanRawQ16\s*=[^;]*madFilteredMeanRawQ16') `
        'shadowPoint0MeanRawQ16 must never be sourced from the MAD-filtered mean.'
    Assert-True ($nlt -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\s*#define NL_LOG_SCHEMA_VERSION\s+6\s*#else\s*#define NL_LOG_SCHEMA_VERSION\s+5' -and
            $nlt -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_POSITION_DIAGNOSTIC.*?SHADOW_META') `
        'MAD filtering must remain diagnostic-profile-only and must not enter the schema-v6 official mean.'

    # --- No leakage into the official measurement-valid gate. ---
    Assert-True ($nlt -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
        'The MAD diagnostic must not touch the official measurement-valid gate.'

    Write-Host '[ OK ] MAD outlier-filtering diagnostic contract tests passed.'
}
finally {
}
