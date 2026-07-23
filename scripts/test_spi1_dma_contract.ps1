$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$ma600 = Get-Content (Join-Path $root "Core\Src\ma600.c") -Raw
$main = Get-Content (Join-Path $root "Core\Src\main.c") -Raw
$msp = Get-Content (Join-Path $root "Core\Src\stm32f4xx_hal_msp.c") -Raw
$irq = Get-Content (Join-Path $root "Core\Src\stm32f4xx_it.c") -Raw
$ioc = Get-Content (Join-Path $root "jigmotor.ioc") -Raw

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

Assert-Match $ma600 '#define\s+MA600_USE_SPI_DMA\s+1' `
    "SPI DMA must be the default angle transport for this trial."
Assert-Match $ma600 'HAL_SPI_TransmitReceive_DMA\s*\(' `
    "MA600 angle path does not start a full-duplex DMA transaction."
Assert-Match $ma600 'SPI_DMA_BLOCKING_WRAPPER_V1' `
    "DMA transport identity is missing."
Assert-Match $ma600 'HAL_SPI_TxRxCpltCallback[\s\S]*?MA600_Deselect\s*\(' `
    "/CS is not deasserted by the SPI DMA completion path."
Assert-Match $ma600 'HAL_SPI_ErrorCallback[\s\S]*?MA600_Deselect\s*\(' `
    "/CS is not deasserted by the SPI DMA error path."
Assert-Match $ma600 'HAL_SPI_Abort\s*\(&hspi1\)[\s\S]*?MA600_Deselect\s*\(' `
    "DMA timeout does not abort SPI and deassert /CS."

Assert-Match $msp 'hdma_spi1_rx\.Instance\s*=\s*DMA2_Stream2' `
    "SPI1 RX must use free DMA2 Stream2."
Assert-Match $msp 'hdma_spi1_tx\.Instance\s*=\s*DMA2_Stream3' `
    "SPI1 TX must use free DMA2 Stream3."
Assert-Match $msp 'hdma_spi1_rx\.Init\.Channel\s*=\s*DMA_CHANNEL_3' `
    "SPI1 RX DMA channel must be Channel3."
Assert-Match $msp 'hdma_spi1_tx\.Init\.Channel\s*=\s*DMA_CHANNEL_3' `
    "SPI1 TX DMA channel must be Channel3."
Assert-Match $msp '__HAL_LINKDMA\(hspi,hdmarx,hdma_spi1_rx\)' `
    "SPI1 RX DMA handle is not linked."
Assert-Match $msp '__HAL_LINKDMA\(hspi,hdmatx,hdma_spi1_tx\)' `
    "SPI1 TX DMA handle is not linked."

Assert-Match $irq 'DMA2_Stream2_IRQHandler[\s\S]*?HAL_DMA_IRQHandler\(&hdma_spi1_rx\)' `
    "SPI1 RX DMA IRQ handler is missing."
Assert-Match $irq 'DMA2_Stream3_IRQHandler[\s\S]*?HAL_DMA_IRQHandler\(&hdma_spi1_tx\)' `
    "SPI1 TX DMA IRQ handler is missing."
Assert-Match $irq 'SPI1_IRQHandler[\s\S]*?HAL_SPI_IRQHandler\(&hspi1\)' `
    "SPI1 error IRQ handler is missing."

Assert-Match $ioc 'Dma\.ADC1\.3\.Instance=DMA2_Stream0' `
    "ADC1 baseline DMA mapping changed unexpectedly."
Assert-Match $ioc 'Dma\.SPI1_RX\.6\.Instance=DMA2_Stream2' `
    "CubeMX SPI1 RX mapping is missing."
Assert-Match $ioc 'Dma\.SPI1_TX\.7\.Instance=DMA2_Stream3' `
    "CubeMX SPI1 TX mapping is missing."
Assert-Match $main 'MA600 angle transport=%s' `
    "Startup log does not identify the active MA600 angle transport."

Write-Host "[ OK ] SPI1 DMA transport/source/CubeMX contract tests passed."
