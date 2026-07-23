$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$profile = Get-Content -Raw (Join-Path $root 'Core\Inc\test_profile.h')
$geometry = Get-Content -Raw (Join-Path $root 'Core\Inc\motor_config.h')
$motor = Get-Content -Raw (Join-Path $root 'Core\Src\motor.c')
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
Assert-True ($profile -match '#define\s+NL_MOTION_PROFILE\s+2' -and
        $profile -match '#define\s+NL_APPROACH_MODE\s+0') `
    '7PP profile must select Motion V2 and lock-only approach.'
Assert-True ($profile -match 'SCURVE40_ABSOLUTE_TICK_V2' -and
        $profile -match 'SCURVE_LOCK_V2') `
    '7PP profile identity does not describe the selected Motion V2 protocol.'
Assert-True ($profile -match '#define\s+TEST_EXPECTED_MA600_REG_1F\s+0x3CU' -and
        $profile -match 'MA600_PRODUCTID_0x3C') `
    '7PP profile must require the observed MA600 PRODUCTID 0x3C.'
Assert-True ($profile -match '#define\s+ENABLE_B0B_APPROACH_CREEP\s+0' -and
        $profile -match '#define\s+ENABLE_B0B_APPROACH_FEEDFORWARD\s+0' -and
        $profile -match '#define\s+ENABLE_SWEEP_RAMP_SOFT_START\s+0') `
    'Experimental motion controls must remain disabled for first movement.'
Assert-True ($geometry -match '#define\s+MOTOR_POLE_PAIRS\s+\(MOTOR_NUM_POLSE\s*/\s*2U\)') `
    'Pole pairs are not derived from physical pole count.'
Assert-True ($geometry -match 'MOTOR_COUNT_PER_ELECTRICAL_CYCLE\s+!=\s+9363U') `
    '7PP electrical-cycle compile guard is missing.'
Assert-True ($geometry -match 'MOTOR_ELECTRICAL_RIPPLE_ORDER\s+!=\s+42U') `
    '7PP ripple-order compile guard is missing.'
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
Assert-True (($nonlinear | Select-String -AllMatches `
        'TEST_EXPECTED_MA600_REG_1F').Matches.Count -eq 3) `
    'Every known jig profile must use the 7PP sensor identity expectation.'
Assert-True ($main -match 'BUILD_MANIFEST' -and
        $main -match 'char\s+manifestLine\[768\]' -and
        $main -match 'MotorPolePairs=%u' -and
        $main -match 'ExpectedSensorReg1F=0x%02X' -and
        $main -match 'RunsPerButton=%u' -and
        $main -match 'Transport=%s') `
    'Boot manifest does not identify the one-run 7PP build.'
Assert-True ($appMode -match '#define\s+JIG_APP_PROFILE_ID\s+TEST_PROFILE_ID') `
    'Measurement application identity is not tied to the 7PP profile.'
Assert-True (($project | Select-String -AllMatches 'JIG_APP_MODE=2').Matches.Count -eq 2) `
    'Debug and Release must both build the measurement application.'

Write-Host '[ OK ] 7PP Motion V2/DMA one-run geometry/profile/manifest contract passed.'
