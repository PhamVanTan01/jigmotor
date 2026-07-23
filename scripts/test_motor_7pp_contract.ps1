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

Assert-True ($profile -match '#define\s+MOTOR_NUM_POLSE\s+14U') `
    '7PP profile does not select 14 physical poles.'
Assert-True ($profile -match '#define\s+TEST_RUNS_PER_BUTTON\s+1U') `
    '7PP profile is not one run per button.'
Assert-True ($profile -match '#define\s+ENABLE_AUTO_BATCH_TEST\s+0') `
    'Automatic batch must be disabled for the smoke test.'
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
Assert-True ($main -match 'BUILD_MANIFEST' -and
        $main -match 'RunsPerButton=%u') `
    'Boot manifest does not identify the one-run 7PP build.'

Write-Host '[ OK ] 7PP one-run geometry/profile/manifest contract passed.'
