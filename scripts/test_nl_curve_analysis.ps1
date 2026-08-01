$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $root 'tools\analyze_nl_curve.py'

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    throw 'Python is required for tools/analyze_nl_curve.py contract tests.'
}

& $python.Source $tool --self-test
if ($LASTEXITCODE -ne 0) {
    throw "NL pointwise-curve self-test failed with exit code $LASTEXITCODE."
}

$help = & $python.Source $tool --help
if ($LASTEXITCODE -ne 0) {
    throw "NL pointwise-curve --help failed with exit code $LASTEXITCODE."
}

$requiredTerms = @(
    '--a1',
    '--b',
    '--a2',
    '--out-dir',
    '--remount-shift-limit',
    '--correlation-min',
    '--closure-limit'
)
foreach ($term in $requiredTerms) {
    if (($help -join "`n") -notmatch [regex]::Escape($term)) {
        throw "NL pointwise-curve CLI contract is missing $term."
    }
}

$source = Get-Content -Raw $tool
$requiredContracts = @(
    'zero-shift is primary',
    'closure_in_curve',
    'robust_nl',
    'pointwise error curve'
)
foreach ($contract in $requiredContracts) {
    if ($source -notmatch [regex]::Escape($contract)) {
        throw "NL pointwise-curve source contract is missing '$contract'."
    }
}

Write-Host '[ OK ] NL pointwise-curve CLI/math/contract tests passed.'
