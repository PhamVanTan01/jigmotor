# toolchain.ps1
# Resolves paths to STM32CubeIDE and related tools used by the other build scripts.
# Do not call arm-none-eabi-gcc directly and do not rely on global PATH -- always
# go through this file so every script agrees on the same toolchain location.

$Global:ProjectRoot = Split-Path -Parent $PSScriptRoot

function Get-CubeProjectName {
    param([string]$ProjectRoot)

    $projectFile = Join-Path $ProjectRoot ".project"
    if (Test-Path $projectFile) {
        try {
            [xml]$projectXml = Get-Content -Path $projectFile -Raw
            $name = $projectXml.projectDescription.name
            if ($name) { return $name.Trim() }
        } catch {
            Write-Host "[WARN] Failed to parse $projectFile; falling back to folder name."
        }
    }

    return Split-Path -Leaf $ProjectRoot
}

function Get-BuildArtifactName {
    param(
        [string]$ProjectRoot,
        [string]$Configuration,
        [string]$ProjectName
    )

    $makefile = Join-Path $ProjectRoot "$Configuration\makefile"
    if (Test-Path $makefile) {
        $artifactLine = Select-String -Path $makefile -Pattern "^\s*BUILD_ARTIFACT_NAME\s*:=" | Select-Object -First 1
        if ($artifactLine) {
            $artifactName = ($artifactLine.Line -replace "^\s*BUILD_ARTIFACT_NAME\s*:=\s*", "").Trim()
            if ($artifactName) { return $artifactName }
        }
    }

    return $ProjectName
}

$Global:ProjectName = Get-CubeProjectName -ProjectRoot $Global:ProjectRoot

function Get-CubeIdeExe {
    if ($env:CUBEIDE_EXE -and (Test-Path $env:CUBEIDE_EXE)) {
        return $env:CUBEIDE_EXE
    }

    $candidates = @()

    if (Test-Path "C:\ST") {
        $candidates += Get-ChildItem -Path "C:\ST" -Directory -Filter "STM32CubeIDE_*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "STM32CubeIDE\stm32cubeidec.exe" }
    }

    $candidates += @(
        "${env:ProgramFiles}\STMicroelectronics\STM32Cube\STM32CubeIDE\stm32cubeidec.exe",
        "${env:ProgramFiles(x86)}\STMicroelectronics\STM32Cube\STM32CubeIDE\stm32cubeidec.exe"
    )

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    return $null
}

function Get-CubeIdeInstallDir {
    param([string]$CubeIdeExe)
    if (-not $CubeIdeExe) { return $null }
    return Split-Path -Parent $CubeIdeExe
}

function Get-CubeMxJar {
    param([string]$CubeIdeInstallDir)
    if (-not $CubeIdeInstallDir) { return $null }
    $plugin = Get-ChildItem -Path (Join-Path $CubeIdeInstallDir "plugins") -Directory -Filter "com.st.stm32cube.common.mx_*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $plugin) { return $null }
    $jar = Join-Path $plugin.FullName "STM32CubeMX.jar"
    if (Test-Path $jar) { return $jar }
    return $null
}

function Get-BundledJavaExe {
    param([string]$CubeIdeInstallDir)
    if (-not $CubeIdeInstallDir) { return $null }
    $jrePlugin = Get-ChildItem -Path (Join-Path $CubeIdeInstallDir "plugins") -Directory -Filter "com.st.stm32cube.ide.jre.win64_*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $jrePlugin) { return $null }
    $java = Join-Path $jrePlugin.FullName "jre\bin\java.exe"
    if (Test-Path $java) { return $java }
    return $null
}

function Get-ArmGccBinDir {
    param([string]$CubeIdeInstallDir)
    if (-not $CubeIdeInstallDir) { return $null }
    $plugin = Get-ChildItem -Path (Join-Path $CubeIdeInstallDir "plugins") -Directory -Filter "com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.*.win32_*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $plugin) { return $null }
    $bin = Join-Path $plugin.FullName "tools\bin"
    if (Test-Path (Join-Path $bin "arm-none-eabi-gcc.exe")) { return $bin }
    return $null
}

function Get-MakeExe {
    param([string]$CubeIdeInstallDir)
    if (-not $CubeIdeInstallDir) { return $null }
    $plugin = Get-ChildItem -Path (Join-Path $CubeIdeInstallDir "plugins") -Directory -Filter "com.st.stm32cube.ide.mcu.externaltools.make.win32_*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $plugin) { return $null }
    $make = Get-ChildItem -Path $plugin.FullName -Recurse -Filter "make.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($make) { return $make.FullName }
    return $null
}

$Global:CubeIdeExe = Get-CubeIdeExe
$Global:CubeIdeInstallDir = Get-CubeIdeInstallDir -CubeIdeExe $Global:CubeIdeExe
$Global:CubeMxJar = Get-CubeMxJar -CubeIdeInstallDir $Global:CubeIdeInstallDir
$Global:BundledJavaExe = Get-BundledJavaExe -CubeIdeInstallDir $Global:CubeIdeInstallDir
$Global:ArmGccBinDir = Get-ArmGccBinDir -CubeIdeInstallDir $Global:CubeIdeInstallDir
$Global:MakeExe = Get-MakeExe -CubeIdeInstallDir $Global:CubeIdeInstallDir
$Global:WorkspaceDir = Join-Path $env:TEMP "$($Global:ProjectName)-cubeide-workspace"
