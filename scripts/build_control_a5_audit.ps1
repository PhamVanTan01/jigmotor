param([switch]$KeepBuild)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'toolchain.ps1')

$Root = Split-Path -Parent $PSScriptRoot
$AuditDirectory = Join-Path $Root 'A5IntegrationAudit'
$RootPrefix = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
$AuditFullPath = [System.IO.Path]::GetFullPath($AuditDirectory)
if (-not $AuditFullPath.StartsWith($RootPrefix,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing A5 audit outside project: $AuditFullPath"
}
if (-not $Global:MakeExe -or -not $Global:ArmGccBinDir) {
    throw 'Bundled STM32CubeIDE make/GCC toolchain not found.'
}

$ReleaseDirectory = Join-Path $Root 'Release'
if (-not (Test-Path (Join-Path $ReleaseDirectory 'makefile'))) {
    throw 'Release makefile missing.'
}

try {
    if (Test-Path -LiteralPath $AuditDirectory) {
        Remove-Item -LiteralPath $AuditDirectory -Recurse -Force
    }
    Copy-Item -LiteralPath $ReleaseDirectory -Destination $AuditDirectory -Recurse

    $defines = '-DJIG_APP_MODE=1 ' +
        '-DJIG_BUILD_SOURCE_ID=\"A5_3_ENABLED_AUDIT\" ' +
        '-DCONTROL_A5_CAPTURE_INTEGRATION_ENABLED=1 ' +
        '-DCONTROL_A5_PROFILE_ACTIVATION_ACK=1'
    foreach ($fragment in @(Get-ChildItem -LiteralPath $AuditDirectory -Recurse -Filter 'subdir.mk')) {
        $content = Get-Content -LiteralPath $fragment.FullName -Raw
        if ($content.Contains('-DJIG_APP_MODE=2')) {
            $content = $content.Replace('-DJIG_APP_MODE=2', $defines)
            Set-Content -LiteralPath $fragment.FullName -Value $content -NoNewline
        }
    }

    $oldPath = $env:PATH
    try {
        $env:PATH = "$Global:ArmGccBinDir;$(Split-Path -Parent $Global:MakeExe);$oldPath"
        Push-Location $AuditDirectory
        & $Global:MakeExe clean | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'A5 audit make clean failed.' }
        $buildOutput = @(& $Global:MakeExe -j4 all 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $buildOutput | Select-Object -Last 80 | Out-Host
            throw 'A5 audit build failed.'
        }
        Pop-Location

        $includeArguments = @(
            "-I$(Join-Path $Root 'Core/Inc')",
            '-isystem', (Join-Path $Root 'Drivers/STM32F4xx_HAL_Driver/Inc'),
            '-isystem', (Join-Path $Root 'Drivers/STM32F4xx_HAL_Driver/Inc/Legacy'),
            '-isystem', (Join-Path $Root 'Middlewares/Third_Party/FreeRTOS/Source/include'),
            '-isystem', (Join-Path $Root 'Middlewares/Third_Party/FreeRTOS/Source/CMSIS_RTOS_V2'),
            '-isystem', (Join-Path $Root 'Middlewares/Third_Party/FreeRTOS/Source/portable/GCC/ARM_CM4F'),
            '-isystem', (Join-Path $Root 'Drivers/CMSIS/Device/ST/STM32F4xx/Include'),
            '-isystem', (Join-Path $Root 'Drivers/CMSIS/Include')
        )
        $strictArguments = @(
            '-mcpu=cortex-m4', '-std=gnu11', '-DUSE_HAL_DRIVER',
            '-DSTM32F405xx', '-DJIG_APP_MODE=1',
            '-DCONTROL_A5_CAPTURE_INTEGRATION_ENABLED=1',
            '-DCONTROL_A5_PROFILE_ACTIVATION_ACK=1',
            '-Os', '-ffunction-sections', '-fdata-sections',
            '-Wall', '-Wextra', '-Wconversion', '-Wsign-conversion',
            '-Wshadow', '-Werror', '-fanalyzer', '--specs=nano.specs',
            '-mfpu=fpv4-sp-d16', '-mfloat-abi=hard', '-mthumb'
        ) + $includeArguments
        $gcc = Join-Path $Global:ArmGccBinDir 'arm-none-eabi-gcc.exe'
        foreach ($sourceName in @('control_a5_math.c', 'control_a5_capture.c',
                'control_engine.c')) {
            $source = Join-Path (Join-Path $Root 'Core/Src') $sourceName
            $object = Join-Path $AuditDirectory ($sourceName + '.strict.o')
            & $gcc @strictArguments -c $source -o $object
            if ($LASTEXITCODE -ne 0) {
                throw "Strict A5 compile failed: $sourceName"
            }
        }

        $elf = Join-Path $AuditDirectory 'jigmotor.elf'
        $size = Join-Path $Global:ArmGccBinDir 'arm-none-eabi-size.exe'
        $nm = Join-Path $Global:ArmGccBinDir 'arm-none-eabi-nm.exe'
        $strings = Join-Path $Global:ArmGccBinDir 'arm-none-eabi-strings.exe'
        Write-Host '== A5 enabled audit size =='
        & $size $elf
        $symbols = (& $nm $elf) -join "`n"
        $text = (& $strings $elf) -join "`n"
        if ($symbols -notmatch 'ControlA5_CaptureStaticWindow') {
            throw 'A5 enabled capture symbol was removed from the link.'
        }
        foreach ($record in @('CONTROL_A5_ARMED', 'CONTROL_A5_SUMMARY',
                'CONTROL_A5_DATA')) {
            if ($text -notmatch $record) {
                throw "A5 enabled audit missing record string: $record"
            }
        }
        Write-Host '[ OK ] A5 enabled full link and strict compile passed.'
    } finally {
        if ((Get-Location).Path -eq $AuditDirectory) { Pop-Location }
        $env:PATH = $oldPath
    }
} finally {
    if (-not $KeepBuild -and (Test-Path -LiteralPath $AuditDirectory)) {
        Remove-Item -LiteralPath $AuditDirectory -Recurse -Force
    }
}
