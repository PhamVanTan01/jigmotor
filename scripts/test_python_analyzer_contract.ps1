$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$analyzer = Join-Path $root 'tools\analyze_motor_logs.py'

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    throw 'Python is required for tools/analyze_motor_logs.py contract tests.'
}

& $python.Source $analyzer --self-test
if ($LASTEXITCODE -ne 0) {
    throw "Python analyzer self-test failed with exit code $LASTEXITCODE."
}

Write-Host '[ OK ] Python analyzer dynamic-grid/closure/role contract tests passed.'
