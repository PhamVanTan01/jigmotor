$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Div-RoundNearestAwayFromZero {
    param([long]$Numerator, [long]$Denominator)
    if ($Denominator -le 0 -or $Numerator -eq [long]::MinValue) {
        throw 'Invalid canonical division input.'
    }
    $negative = $Numerator -lt 0
    $magnitude = if ($negative) { -$Numerator } else { $Numerator }
    [long]$remainder = 0
    [long]$quotient = [Math]::DivRem($magnitude, $Denominator, [ref]$remainder)
    if (2 * $remainder -ge $Denominator) { $quotient++ }
    return $(if ($negative) { -$quotient } else { $quotient })
}

function Canonical-MeanQ16 {
    param([long]$Anchor, [long]$SumRel, [long]$Accepted)
    $meanRel = Div-RoundNearestAwayFromZero ($SumRel * 65536L) $Accepted
    return [pscustomobject]@{
        MeanRel = [long]$meanRel
        PointMean = [long]($Anchor * 65536L + $meanRel)
    }
}

function Canonical-ErrorQ16 {
    param([long]$PointMean, [long]$Point0Mean, [int]$Direction, [long]$Index, [long]$StepRaw)
    return ($PointMean - $Point0Mean) - (($Direction * $Index * $StepRaw) * 65536L)
}

function To-U32 {
    param([long]$Value)
    $wrapped = $Value % 0x100000000L
    if ($wrapped -lt 0) { $wrapped += 0x100000000L }
    return [uint32]$wrapped
}

function Signed-CycleDelta {
    param([uint32]$A, [uint32]$B)
    [uint32]$raw = To-U32 ([long]$A - [long]$B)
    if ($raw -ge 0x80000000L) { return [long]$raw - 0x100000000L }
    return [long]$raw
}

function Model-Schedule {
    param([object[]]$Attempts, [uint32]$Interval, [int]$RequiredAccepted)
    $initialized = $false
    [uint32]$first = 0
    [uint32]$next = 0
    $accepted = 0
    $skipped = 0
    $overruns = 0
    $maxAbsError = 0L
    $waits = @()

    foreach ($attempt in $Attempts) {
        $hasSlot = $initialized
        [uint32]$scheduled = 0
        if ($hasSlot) {
            $scheduled = $next
            $waits += $scheduled
        }

        [uint32]$cycle = $attempt.Cycle
        if (-not $initialized) {
            $first = $cycle
            $next = To-U32 ([long]$cycle + $Interval)
            $initialized = $true
        } else {
            $error = Signed-CycleDelta $cycle $scheduled
            if ($error -gt 0) { $overruns++ }
            $absError = [Math]::Abs($error)
            if ($absError -gt $maxAbsError) { $maxAbsError = $absError }
            $next = To-U32 ([long]$scheduled + $Interval)
        }

        if ($attempt.Accepted) { $accepted++ }
        if ($accepted -ge $RequiredAccepted) { break }

        if ((Signed-CycleDelta ([uint32]$attempt.After) $next) -ge 0) {
            [uint32]$late = To-U32 ([long]$attempt.After - $next)
            $missed = [long][Math]::Floor($late / [double]$Interval) + 1L
            $skipped += $missed
            $next = To-U32 ([long]$next + $missed * $Interval)
        }
    }

    return [pscustomobject]@{
        First = $first
        Accepted = $accepted
        Skipped = $skipped
        Overruns = $overruns
        MaxAbsError = $maxAbsError
        Waits = $waits
    }
}

Assert-True ((Div-RoundNearestAwayFromZero 1 2) -eq 1) 'Positive half rounding failed.'
Assert-True ((Div-RoundNearestAwayFromZero -1 2) -eq -1) 'Negative half rounding failed.'
Assert-True ((Div-RoundNearestAwayFromZero 3 2) -eq 2) 'Positive rounding failed.'
Assert-True ((Div-RoundNearestAwayFromZero -3 2) -eq -2) 'Negative rounding failed.'

$mean = Canonical-MeanQ16 100 1 2
Assert-True ($mean.MeanRel -eq 32768L) 'Canonical mean relative Q16 failed.'
Assert-True ($mean.PointMean -eq (100L * 65536L + 32768L)) 'Canonical point mean Q16 failed.'
$negativeMean = Canonical-MeanQ16 -100 -1 2
Assert-True ($negativeMean.MeanRel -eq -32768L) 'Negative canonical mean rounding failed.'

$point0 = 100L * 65536L
$fullTurn = $point0 + 65536L * 65536L
Assert-True ((Canonical-ErrorQ16 $point0 $point0 1 0 256) -eq 0) 'Point-0 error is not exact zero.'
Assert-True ((Canonical-ErrorQ16 $fullTurn $point0 1 256 256) -eq 0) 'Full-turn closure target is not exact.'
Assert-True ((Div-RoundNearestAwayFromZero (2L * 65536L * 65536L) 3600L) -eq 2386093L) 'Pilot 0.20-degree closure limit changed.'

$firstFailure = Model-Schedule @(
    [pscustomobject]@{ Cycle=[uint32]1000; After=[uint32]1005; Accepted=$false },
    [pscustomobject]@{ Cycle=[uint32]1040; After=[uint32]1045; Accepted=$true },
    [pscustomobject]@{ Cycle=[uint32]1080; After=[uint32]1085; Accepted=$true }
) 40 2
Assert-True ($firstFailure.Accepted -eq 2) 'First-failure model did not recover.'
Assert-True (($firstFailure.Waits -join '|') -eq '1040|1080') 'Failed attempt did not consume exactly one scheduled slot.'

$missed = Model-Schedule @(
    [pscustomobject]@{ Cycle=[uint32]1000; After=[uint32]1005; Accepted=$true },
    [pscustomobject]@{ Cycle=[uint32]1125; After=[uint32]1130; Accepted=$true },
    [pscustomobject]@{ Cycle=[uint32]1160; After=[uint32]1165; Accepted=$true }
) 40 3
Assert-True ($missed.Skipped -eq 2) 'Skipped-slot accounting failed.'
Assert-True (($missed.Waits -join '|') -eq '1040|1160') 'Scheduler produced a catch-up burst.'
Assert-True ($missed.Overruns -eq 1 -and $missed.MaxAbsError -eq 85) 'Timing-overrun accounting failed.'

$wrapped = Model-Schedule @(
    [pscustomobject]@{ Cycle=[uint32]4294967280; After=[uint32]4294967285; Accepted=$true },
    [pscustomobject]@{ Cycle=[uint32]0x00000010; After=[uint32]0x00000015; Accepted=$true }
) 32 2
Assert-True (($wrapped.Waits -join '|') -eq '16') 'DWT wrap scheduling failed.'

$source = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Core\Src\ma600_acquisition.c')
Assert-True ($source -notmatch 'sumRelRaw\s*<<\s*16') 'Forbidden signed left shift found for sumRelRaw.'
Assert-True ($source -notmatch 'pointAnchorUnwrapped\s*<<\s*16') 'Forbidden signed left shift found for anchor.'
Assert-True ($source -match 'value\s*\*\s*65536LL') 'Canonical Q16 multiplication is missing.'

Write-Host '[ OK ] CANONICAL_Q16_V1 and scheduler host contract tests passed.'
