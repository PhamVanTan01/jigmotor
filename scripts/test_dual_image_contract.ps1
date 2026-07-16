$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$modeHeader = Get-Content -Raw (Join-Path $root 'Core\Inc\app_mode.h')
$appEngine = Get-Content -Raw (Join-Path $root 'Core\Src\app_engine.c')
$controlEngine = Get-Content -Raw (Join-Path $root 'Core\Src\control_engine.c')
$main = Get-Content -Raw (Join-Path $root 'Core\Src\main.c')
$project = Get-Content -Raw (Join-Path $root '.cproject')
$buildScript = Get-Content -Raw (Join-Path $root 'scripts\build_dual_image.ps1')

Assert-True ($modeHeader -match '#define\s+JIG_APP_CONTROL\s+1' -and
    $modeHeader -match '#define\s+JIG_APP_MEASUREMENT\s+2' -and
    $modeHeader -match '#error "JIG_APP_MODE must be supplied') `
    'App-mode compile-time contract is incomplete.'
Assert-True ($project -match 'JIG_APP_MODE=2') `
    'CubeIDE Debug/Release measurement identity is missing.'
Assert-True ($appEngine -match '#if JIG_APP_MODE == JIG_APP_CONTROL' -and
    $appEngine -match 'ControlEngine_Init' -and
    $appEngine -match 'NonlinearEngine_Init') `
    'AppEngine does not compile-select the two implementations.'
Assert-True ($main -match 'AppEngine_Init\(\)' -and
    $main -match 'AppEngine_RequestStart\(\)' -and
    $main -match 'AppEngine_IsBusy\(\)' -and
    $main -notmatch 'NonlinearEngine_(Init|RequestStart|IsBusy)') `
    'main.c bypasses the mode-neutral AppEngine boundary.'
Assert-True ($controlEngine -match 'CONTROL_C0_TARGET_DEG\s+1U' -and
    $controlEngine -match 'CONTROL_C0_MAX_TRAVEL_RAW' -and
    $controlEngine -match 'CONTROL_C0_MAX_ACTIVE_MS' -and
    $controlEngine -match 'Motor_Disable\(\)') `
    'Control C0 motion path is missing its fail-safe envelope.'
Assert-True ($main -match 'BUILD_MANIFEST,AppMode=%s,AppProfile=%s') `
    'Startup build identity record is missing.'
Assert-True ($main -match 'SourceId=%s,ProfileFingerprint=0x%08lX' -and
    $appEngine -match 'JIG_BUILD_SOURCE_ID' -and
    $appEngine -match 'AppEngine_ProfileFingerprint') `
    'Source/profile fingerprint identity is incomplete.'
Assert-True ($buildScript -match "ValidateSet\('Control', 'Measurement', 'All'\)" -and
    $buildScript -match 'Build-ModeImage' -and
    $buildScript -match 'JIG_BUILD_SOURCE_ID' -and
    $buildScript -match 'jigmotor_\$\(\$ModeName\.ToLowerInvariant\(\)\)') `
    'Dual-image build script does not independently compile/name both modes.'

$controlElf = Join-Path $root 'Build\Control\jigmotor_control.elf'
$measurementElf = Join-Path $root 'Build\Measurement\jigmotor_measurement.elf'
if ((Test-Path $controlElf) -and (Test-Path $measurementElf)) {
    . (Join-Path $PSScriptRoot 'toolchain.ps1')
    $nm = Join-Path $Global:ArmGccBinDir 'arm-none-eabi-nm.exe'
    $strings = Join-Path $Global:ArmGccBinDir 'arm-none-eabi-strings.exe'
    $controlSymbols = (& $nm $controlElf) -join "`n"
    $measurementSymbols = (& $nm $measurementElf) -join "`n"
    $controlStrings = (& $strings $controlElf) -join "`n"
    $measurementStrings = (& $strings $measurementElf) -join "`n"

    Assert-True ($controlSymbols -notmatch 'NonlinearEngine_Init|NonlinearTest_Run|nlCaptures') `
        'Control ELF still links the nonlinear measurement engine/state.'
    Assert-True ($measurementSymbols -match 'NonlinearEngine_Init') `
        'Measurement ELF is missing the nonlinear measurement engine.'
    Assert-True ($controlStrings -match 'CONTROL_C0_OPEN_LOOP_1DEG_V1' -and
        $controlStrings -notmatch 'MEASUREMENT_MOTION_V2_DMA_P1') `
        'Control ELF identity is mixed or missing.'
    Assert-True ($measurementStrings -match 'MEASUREMENT_MOTION_V2_DMA_P1' -and
        $measurementStrings -notmatch 'CONTROL_C0_OPEN_LOOP_1DEG_V1') `
        'Measurement ELF identity is mixed or missing.'
    $controlHash = (Get-FileHash $controlElf -Algorithm SHA256).Hash
    $measurementHash = (Get-FileHash $measurementElf -Algorithm SHA256).Hash
    Assert-True ($controlHash -ne $measurementHash) `
        'Control and Measurement ELF artifacts are unexpectedly identical.'
}

Write-Host '[ OK ] Dual-image build/identity/isolation contract passed.'
