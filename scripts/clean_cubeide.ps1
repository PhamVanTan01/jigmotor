# clean_cubeide.ps1
# Removes local build outputs and the throwaway CubeIDE headless workspace.
# Does not touch source files.

. (Join-Path $PSScriptRoot "toolchain.ps1")

function Test-IsUnderRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path.TrimEnd("\")
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd("\")

    return ($resolvedPath -eq $resolvedRoot) -or
        $resolvedPath.StartsWith("$resolvedRoot\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-TreeIfSafe {
    param(
        [string]$Path,
        [string[]]$AllowedRoots
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $isAllowed = $false
    foreach ($root in $AllowedRoots) {
        if ((Test-Path -LiteralPath $root) -and (Test-IsUnderRoot -Path $Path -Root $root)) {
            $isAllowed = $true
            break
        }
    }

    if (-not $isAllowed) {
        throw "Refusing to remove '$Path' because it is outside the allowed roots."
    }

    Write-Host "Removing $Path"
    Remove-Item -LiteralPath $Path -Recurse -Force
}

$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$tempRootResolved = (Resolve-Path -LiteralPath $env:TEMP).Path

foreach ($dir in @("Debug", "Release", ".cubeide-workspace")) {
    $p = Join-Path $ProjectRoot $dir
    Remove-TreeIfSafe -Path $p -AllowedRoots @($projectRootResolved)
}

Remove-TreeIfSafe -Path $Global:WorkspaceDir -AllowedRoots @($tempRootResolved)

Write-Host "Clean complete."
