$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')
$acq = Get-Content -Raw (Join-Path $root 'Core\Src\ma600_acquisition.c')

Assert-True ($source -match '#define\s+NL_POINTS_PER_REV\s+360U' -and
        $source -match '#define\s+NL_GRID_STEP_DEG\s+1\.0f' -and
        $source -match 'UNIFORM_1_DEG_ROUNDED_RAW_V1') `
    'The uniform one-degree grid identity/constants are incomplete.'
Assert-True ($source -notmatch '\bNL_POS_INCREASE\b') `
    'A fixed raw point increment remains; one degree requires rounded absolute targets.'
Assert-True ($source -match '(?s)NlTargetRawMagnitudeForPoint.*?pointIndex.*?MOTOR_MECHANICAL_COUNTS_PER_REV.*?NL_POINTS_PER_REV\s*/\s*2U.*?NL_POINTS_PER_REV') `
    'Target generation is not round(index * 65536 / 360).'
Assert-True ($source -match 'targetPos\s*=\s*NlTargetRawForPoint\(') `
    'The sweep ramp does not use the rounded absolute target.'
Assert-True ($source -match 'expectedAnalysisCount\s*=\s*NL_POINTS_PER_REV' -and
        $source -match 'analysisCount\s*=\s*\(capturedCount\s*<\s*\(int\)expectedAnalysisCount\)') `
    'Analysis is not limited to points 0..359.'
Assert-True ($source -match '#define\s+NL_CLOSURE_POINT_INDEX\s+NL_POINTS_PER_REV' -and
        $source -match 'i\s*==\s*\(int\)NL_CLOSURE_POINT_INDEX') `
    'Closure is not evaluated at point 360.'
Assert-True (([regex]::Matches($source, 'NlGridAngleDeg\(\(uint32_t\)i\)')).Count -ge 3) `
    'Harmonic/residual/log math is not using the uniform degree coordinate.'
Assert-True ($source -match 'MA600_ComputeCanonicalErrorAtTargetQ16' -and
        $acq -match 'bool\s+MA600_ComputeCanonicalErrorAtTargetQ16') `
    'Canonical Q16 path still assumes a fixed raw step.'
Assert-True ($source -match '(?s)GRID,SchemaVersion=%d.*?NominalStepDeg=1\.00000' -and
        $source -match 'RawStepMin=%u,RawStepMax=%u') `
    'The log does not expose the one-degree target protocol.'
Assert-True ($source -match '#define\s+NL_MAX_SWEEP_POINTS\s+372') `
    'Sweep buffers do not cover points 0..370 plus guard margin.'
Assert-True ($source -match 'NlOneDegreeGridSelfTest\(\)' -and
        $source -match 'if\s*\(!NlOneDegreeGridSelfTest\(\)\)') `
    'The boot-time grid invariant self-test is not fail-closed.'

$targets = for ($i = 0; $i -le 370; $i++) {
    [int][math]::Floor((($i * 65536.0) + 180.0) / 360.0)
}
$deltas = for ($i = 1; $i -lt $targets.Count; $i++) {
    $targets[$i] - $targets[$i - 1]
}
Assert-True ($targets[0] -eq 0 -and $targets[1] -eq 182 -and
        $targets[180] -eq 32768 -and $targets[359] -eq 65354 -and
        $targets[360] -eq 65536) `
    'Rounded target reference values are wrong.'
Assert-True (@($deltas | Where-Object { $_ -ne 182 -and $_ -ne 183 }).Count -eq 0) `
    'One-degree raw target sequence contains a step other than 182/183.'

Write-Host '[ OK ] Uniform one-degree grid/closure/canonical contract tests passed.'
