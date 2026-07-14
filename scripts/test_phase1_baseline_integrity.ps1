$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$analyzer = Join-Path $PSScriptRoot 'analyze_nonlinear_logs.ps1'
$csv = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-phase1-baseline.csv'
$fixtures = @(
    @{
        Name = 'v6-p03-jig1.txt'
        Hash = 'EA1407992E41F3E0EBBB5457A116C9E5FAC4B211DC7B108161EFA5D627942074'
        Jig = 'JIG1'
        Uid = '003C00273234470438353535'
    },
    @{
        Name = 'v6-p03-jig2.txt'
        Hash = 'A89AF55F1DBCC9C1A48DFAB778AFFAE147094D6C455F44DBAA279BF694FF3839'
        Jig = 'JIG2'
        Uid = '0025002C3234470438353535'
    }
)

try {
    $paths = @()
    foreach ($fixture in $fixtures) {
        $path = Join-Path $repo $fixture.Name
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing immutable baseline fixture $($fixture.Name)."
        }
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
        if ($actualHash -ne $fixture.Hash) {
            throw "Hash mismatch for $($fixture.Name): $actualHash."
        }
        $text = Get-Content -Raw -LiteralPath $path
        if ($text -match 'SchemaVersion=6' -or
                $text -notmatch 'SchemaVersion=5' -or
                $text -notmatch 'GatePolicy=POLICY_A_AUDIT_V1' -or
                $text -notmatch 'AuditFieldsLocked=0') {
            throw "$($fixture.Name) is no longer the frozen schema-v5 audit fixture."
        }
        $paths += $path
    }

    & $analyzer -Path $paths -OutCsv $csv | Out-Null
    $rows = @(Import-Csv $csv)
    if ($rows.Count -ne 6) {
        throw "Expected 6 measurements from the two baseline fixtures, got $($rows.Count)."
    }
    foreach ($fixture in $fixtures) {
        $jigRows = @($rows | Where-Object {
            $_.Jig -eq $fixture.Jig -and $_.MCU_UID -eq $fixture.Uid
        })
        if ($jigRows.Count -ne 3 -or @($jigRows | Where-Object { $_.SchemaVersion -ne '5' }).Count -ne 0) {
            throw "Unexpected schema/identity/run count for $($fixture.Name)."
        }
    }

    $jig1ClosurePasses = @($rows | Where-Object {
        $_.Jig -eq 'JIG1' -and $_.ClosureValid -eq '1'
    }).Count
    $jig2ClosurePasses = @($rows | Where-Object {
        $_.Jig -eq 'JIG2' -and $_.ClosureValid -eq '1'
    }).Count
    if ($jig1ClosurePasses -ne 0 -or $jig2ClosurePasses -ne 2 -or
            @($rows | Where-Object { $_.ClosureMeaning -ne 'DIAGNOSTIC_SCHEMA_V5_PILOT' }).Count -ne 0) {
        throw 'Schema-v5 diagnostic closure regression changed unexpectedly.'
    }

    Write-Host '[ OK ] Frozen Phase-1 schema-v5 baseline fixtures passed.'
}
finally {
    Remove-Item -LiteralPath $csv -Force -ErrorAction SilentlyContinue
}
