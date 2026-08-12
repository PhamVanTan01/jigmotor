$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$testFile = Join-Path $root 'tools\test_schema6_plotting.py'
$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    throw 'Python is required for schema-v6 plotting tests.'
}

& $python.Source $testFile
if ($LASTEXITCODE -ne 0) {
    throw "Schema-v6 plotting test failed with exit code $LASTEXITCODE."
}

Write-Host '[ OK ] Schema-v6 live NL and saved NL/polar plotting contract passed.'
