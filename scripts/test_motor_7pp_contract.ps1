$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$profile = Get-Content -Raw (Join-Path $root 'Core\Inc\test_profile.h')
$geometry = Get-Content -Raw (Join-Path $root 'Core\Inc\motor_config.h')
$motor = Get-Content -Raw (Join-Path $root 'Core\Src\motor.c')
$ma600 = Get-Content -Raw (Join-Path $root 'Core\Src\ma600.c')
$nonlinear = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')
$main = Get-Content -Raw (Join-Path $root 'Core\Src\main.c')
$appMode = Get-Content -Raw (Join-Path $root 'Core\Inc\app_mode.h')
$project = Get-Content -Raw (Join-Path $root '.cproject')

Assert-True ($profile -match '#define\s+MOTOR_NUM_POLSE\s+14U') `
    '7PP profile does not select 14 physical poles.'
Assert-True ($profile -match '#define\s+TEST_RUNS_PER_BUTTON\s+1U') `
    '7PP profile is not one run per button.'
Assert-True ($profile -match '#define\s+ENABLE_AUTO_BATCH_TEST\s+0') `
    'Automatic batch must be disabled for the smoke test.'
Assert-True ($profile -match 'TEST_PROFILE_ID\s+"7PP_STUTTER_DIAG_P135_160_1RUN_V1"' -and
        $profile -match '#define\s+ENABLE_7PP_STUTTER_TRACE\s+1') `
    'P7-AB1 profile identity or stutter trace enable is missing.'
Assert-True ($profile -match '#define\s+NL_MOTION_PROFILE\s+2' -and
        $profile -match '#define\s+NL_APPROACH_MODE\s+3' -and
        $profile -match '#define\s+ENABLE_B0B_EQUAL_APPROACH\s+1') `
    '7PP profile must select Motion V2 and V3.2 shifted reversal.'
Assert-True ($profile -match 'SCURVE40_ABSOLUTE_TICK_V2' -and
        $profile -match 'SCURVE_ECYCLE_PREROLL_LOCAL_REVERSAL_V2') `
    '7PP profile identity does not describe the selected Motion V2 protocol.'
Assert-True ($profile -match '#define\s+TEST_EXPECTED_MA600_REG_1F_MA600\s+0x3CU' -and
        $profile -match '#define\s+TEST_EXPECTED_MA600_REG_1F_MA600A\s+0x00U' -and
        $profile -match 'UID_LOCKED_MA600_VARIANT_V1' -and
        $profile -match 'TEST_SENSOR_REG_1F_POLICY\s+"PER_JIG_PROFILE"') `
    '7PP profile must lock original-MA600 and MA600A register 0x1F identities per jig.'
Assert-True ($profile -match '#define\s+ENABLE_B0B_APPROACH_CREEP\s+0' -and
        $profile -match '#define\s+ENABLE_B0B_APPROACH_FEEDFORWARD\s+0' -and
        $profile -match '#define\s+ENABLE_B0B_APPROACH_SOFT_START\s+0' -and
        $profile -match '#define\s+ENABLE_SWEEP_RAMP_SOFT_START\s+0') `
    'Bias, creep, and soft-start controls must remain disabled for B0-B isolation.'
Assert-True ($geometry -match '#define\s+MOTOR_POLE_PAIRS\s+\(MOTOR_NUM_POLSE\s*/\s*2U\)') `
    'Pole pairs are not derived from physical pole count.'
Assert-True ($geometry -match 'MOTOR_COUNT_PER_ELECTRICAL_CYCLE\s+!=\s+9363U') `
    '7PP electrical-cycle compile guard is missing.'
Assert-True ($geometry -match 'MOTOR_ELECTRICAL_RIPPLE_ORDER\s+!=\s+42U') `
    '7PP ripple-order compile guard is missing.'
Assert-True ($nonlinear -match '#define\s+NL_V3_ELECTRICAL_ZERO_TARGET_RAW\s+MOTOR_COUNT_PER_ELECTRICAL_CYCLE' -and
        $nonlinear -match '#define\s+NL_V3_LOCAL_BACKOFF_TARGET_RAW' -and
        $nonlinear -match 'finalTarget\s*=\s*\(int32_t\)NL_V3_ELECTRICAL_ZERO_TARGET_RAW' -and
        $nonlinear -match 'localBackoffTarget\s*=\s*[\r\n\s]*\(int32_t\)NL_V3_LOCAL_BACKOFF_TARGET_RAW') `
    'V3.2 targets are not derived from the 7PP raw electrical-cycle geometry.'
Assert-True ($nonlinear -match 'roundedGridTarget\s*>=\s*finalTarget' -and
        $nonlinear -match 'prePositionSegmentCount\s*\*\s*NL_SCURVE_SEGMENT_TICKS') `
    'V3.2 pre-position does not safely segment a non-integer-degree electrical cycle.'
Assert-True ($nonlinear -match 'finalCommandDeltaRaw\s*=\s*[\r\n\s]*\(int64_t\)finalTarget\s*-\s*\(int64_t\)localBackoffTarget') `
    'V3.2 final local leg is not derived from the exact 182-raw backoff target.'
Assert-True ($motor -notmatch '#define\s+MOTOR_POLE_PAIRS\s+6') `
    'motor.c still owns a hard-coded 6PP geometry.'
Assert-True ($motor -match 'MOTOR_COUNT_PER_ELECTRICAL_CYCLE') `
    'PWM commutator is not using shared geometry.'
Assert-True ($nonlinear -match 'AElectrical6=%s' -and
        $nonlinear -match 'ElectricalRippleOrder=%u') `
    'Dynamic electrical-ripple audit fields are missing.'
Assert-True ($nonlinear -match 'NL_MOTION_PROFILE_SCURVE_V2' -and
        $nonlinear -match 'NL_SCURVE_SEGMENT_TICKS\s+40U' -and
        $nonlinear -match 'NL_GRID_PROTOCOL_ID\s+"UNIFORM_1_DEG_ROUNDED_RAW_V1"') `
    'Motion V2 or one-degree measurement grid is missing.'
Assert-True ($nonlinear -match 'NL_STUTTER_POINT_FIRST\s+135U' -and
        $nonlinear -match 'NL_STUTTER_POINT_LAST\s+160U' -and
        $nonlinear -match 'NL_STUTTER_RAMP_SAMPLE_CAPACITY\s+NL_SCURVE_SEGMENT_TICKS') `
    'P7-AB1 point window or full 40-tick trace bound changed.'
Assert-True ($nonlinear -match 'NL_POINT_SETTLE_ERROR_RAW\s+9LL' -and
        $nonlinear -match 'NL_SETTLE_TARGET_TOLERANCE_RAW\s+910LL' -and
        $nonlinear -match 'NL_POINT_SETTLE_TIMEOUT_MS\s+100') `
    'P7-AB1 must preserve the baseline settle contract.'
Assert-True ($nonlinear -match 'STUTTER_TRACE_META' -and
        $nonlinear -match 'STUTTER_RAMP_STEP' -and
        $nonlinear -match 'STUTTER_SETTLE_SAMPLE' -and
        $nonlinear -match 'LagSign=OBSERVED_MINUS_COMMAND') `
    'P7-AB1 deferred trace record contract is incomplete.'
Assert-True ($nonlinear -match 'static\s+NlStutterTrace_t\s+nlStutterTrace[\s\S]*?ccmram_bss') `
    'P7-AB1 static trace buffer is missing.'
Assert-True (($nonlinear | Select-String -AllMatches `
        'TEST_EXPECTED_MA600_REG_1F_MA600').Matches.Count -eq 4 -and
        $nonlinear -match '0x0027002E,\s*0x32344704,\s*0x38353535,\s*"JIG4"[\s\S]*?TEST_EXPECTED_MA600_REG_1F_MA600A') `
    'Known jig profiles do not preserve the UID-locked MA600/MA600A identity mapping.'
Assert-True ($ma600 -match 'MA600_ReadConfigurationSnapshot' -and
        $ma600 -match 'MA600_ConfigurationSnapshotsEqual' -and
        $ma600 -match 'attempt\s*=\s*1U;\s*attempt\s*<\s*3U' -and
        $ma600 -match 'out->valid\s*=\s*false;\s*[\r\n\s]*out->calState\s*=\s*MA600_CAL_UNKNOWN') `
    'Configuration audit must require two consecutive equal snapshots and fail closed if unstable.'
Assert-True ($main -match 'BUILD_MANIFEST' -and
        $main -match 'char\s+manifestLine\[768\]' -and
        $main -match 'MotorPolePairs=%u' -and
        $main -match 'ExpectedSensorReg1F=%s' -and
        $main -match 'RunsPerButton=%u' -and
        $main -match 'Transport=%s') `
    'Boot manifest does not identify the one-run 7PP build.'
Assert-True ($appMode -match '#define\s+JIG_APP_PROFILE_ID\s+TEST_PROFILE_ID') `
    'Measurement application identity is not tied to the 7PP profile.'
Assert-True (($project | Select-String -AllMatches 'JIG_APP_MODE=2').Matches.Count -eq 2) `
    'Debug and Release must both build the measurement application.'

Write-Host '[ OK ] 7PP V3.2 shifted-reversal/DMA one-run geometry/profile/manifest contract passed.'
