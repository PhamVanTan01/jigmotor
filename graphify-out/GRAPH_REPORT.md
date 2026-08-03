# Graph Report - .  (2026-08-03)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 3797 nodes · 9396 edges · 155 communities (148 shown, 7 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 810 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `00b5f7b8`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 77
- Community 78
- Community 79
- Community 80
- Community 81
- Community 82
- Community 83
- Community 84
- Community 85
- Community 86
- Community 87
- Community 88
- Community 89
- Community 90
- Community 91
- Community 93
- Community 94
- Community 95
- Community 96
- Community 97
- Community 98
- Community 99
- Community 100
- Community 101
- Community 102
- Community 103
- Community 104
- Community 105
- Community 109
- Community 110
- Community 114

## God Nodes (most connected - your core abstractions)
1. `HAL_GetTick()` - 66 edges
2. `__DSB()` - 45 edges
3. `TIM_CCxChannelCmd()` - 40 edges
4. `CaptureSweep()` - 37 edges
5. `__ISB()` - 34 edges
6. `HAL_DMA_Start_IT()` - 31 edges
7. `uxListRemove()` - 28 edges
8. `xTaskResumeAll()` - 27 edges
9. `PrintSweepLog()` - 25 edges
10. `HAL_DMA_Abort_IT()` - 25 edges

## Surprising Connections (you probably didn't know these)
- `ADC_IRQHandler()` --calls--> `HAL_ADC_IRQHandler()`  [INFERRED]
  Core/Src/stm32f4xx_it.c → Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_adc.c
- `TIM2_IRQHandler()` --calls--> `HAL_TIM_IRQHandler()`  [INFERRED]
  Core/Src/stm32f4xx_it.c → Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_tim.c
- `I2C2_EV_IRQHandler()` --calls--> `HAL_I2C_EV_IRQHandler()`  [INFERRED]
  Core/Src/stm32f4xx_it.c → Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_i2c.c
- `I2C2_ER_IRQHandler()` --calls--> `HAL_I2C_ER_IRQHandler()`  [INFERRED]
  Core/Src/stm32f4xx_it.c → Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_i2c.c
- `USART2_IRQHandler()` --calls--> `HAL_UART_IRQHandler()`  [INFERRED]
  Core/Src/stm32f4xx_it.c → Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_uart.c

## Import Cycles
- None detected.

## Communities (155 total, 7 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.04
Nodes (136): __STATIC_INLINE, LL_USART_ClearFlag_FE(), LL_USART_ClearFlag_IDLE(), LL_USART_ClearFlag_LBD(), LL_USART_ClearFlag_nCTS(), LL_USART_ClearFlag_NE(), LL_USART_ClearFlag_ORE(), LL_USART_ClearFlag_PE() (+128 more)

### Community 1 - "Community 1"
Cohesion: 0.03
Nodes (132): __CLREX(), __disable_fault_irq(), __disable_irq(), __enable_fault_irq(), __enable_irq(), __get_APSR(), __get_BASEPRI(), __get_CONTROL() (+124 more)

### Community 2 - "Community 2"
Cohesion: 0.05
Nodes (111): __STATIC_INLINE, LL_I2C_AcknowledgeNextData(), LL_I2C_ClearFlag_ADDR(), LL_I2C_ClearFlag_AF(), LL_I2C_ClearFlag_ARLO(), LL_I2C_ClearFlag_BERR(), LL_I2C_ClearFlag_OVR(), LL_I2C_ClearFlag_STOP() (+103 more)

### Community 3 - "Community 3"
Cohesion: 0.04
Nodes (109): __get_APSR(), __get_BASEPRI(), __get_CONTROL(), __get_FAULTMASK(), __get_IPSR(), __get_MSP(), __get_MSPLIM(), __get_PRIMASK() (+101 more)

### Community 4 - "Community 4"
Cohesion: 0.04
Nodes (95): NonlinearEngine_RequestStart(), MemPool_t, AllocBlock(), StackType_t, __STATIC_INLINE, StaticTask_t, TaskHandle_t, TimerHandle_t (+87 more)

### Community 5 - "Community 5"
Cohesion: 0.06
Nodes (92): HAL_DMA_Abort(), HAL_DMA_GetError(), HAL_StatusTypeDef, RCC_OscInitTypeDef, __weak, HAL_RCC_ClockConfig(), HAL_RCC_CSSCallback(), HAL_RCC_GetClockConfig() (+84 more)

### Community 6 - "Community 6"
Cohesion: 0.02
Nodes (84): LL_RCC_ClearFlag_HSECSS(), LL_RCC_ClearFlag_HSIRDY(), LL_RCC_ClearFlag_PLLI2SRDY(), LL_RCC_ClearResetFlags(), LL_RCC_DisableIT_HSERDY(), LL_RCC_DisableIT_LSERDY(), LL_RCC_DisableIT_LSIRDY(), LL_RCC_DisableIT_PLLSAIRDY() (+76 more)

### Community 7 - "Community 7"
Cohesion: 0.02
Nodes (85): __STATIC_INLINE, LL_RCC_ClearFlag_HSERDY(), LL_RCC_ClearFlag_LSERDY(), LL_RCC_ClearFlag_LSIRDY(), LL_RCC_ClearFlag_PLLRDY(), LL_RCC_ClearFlag_PLLSAIRDY(), LL_RCC_ConfigMCO(), LL_RCC_DisableIT_HSIRDY() (+77 more)

### Community 8 - "Community 8"
Cohesion: 0.05
Nodes (83): __STATIC_INLINE, LL_DBGMCU_APB1_GRP1_FreezePeriph(), LL_DBGMCU_APB1_GRP1_UnFreezePeriph(), LL_DBGMCU_APB2_GRP1_FreezePeriph(), LL_DBGMCU_APB2_GRP1_UnFreezePeriph(), LL_DBGMCU_DisableDBGSleepMode(), LL_DBGMCU_DisableDBGStandbyMode(), LL_DBGMCU_DisableDBGStopMode() (+75 more)

### Community 9 - "Community 9"
Cohesion: 0.07
Nodes (78): ADC_TypeDef, __STATIC_INLINE, LL_ADC_ClearFlag_AWD1(), LL_ADC_ClearFlag_EOCS(), LL_ADC_ClearFlag_JEOS(), LL_ADC_ClearFlag_OVR(), LL_ADC_DisableIT_AWD1(), LL_ADC_DisableIT_EOCS() (+70 more)

### Community 10 - "Community 10"
Cohesion: 0.08
Nodes (76): HAL_DMA_Abort_IT(), HAL_StatusTypeDef, HAL_TIM_ChannelStateTypeDef, HAL_TIM_StateTypeDef, TIM_HandleTypeDef, HAL_TIM_Base_DeInit(), HAL_TIM_Base_GetState(), HAL_TIM_Base_MspDeInit() (+68 more)

### Community 11 - "Community 11"
Cohesion: 0.07
Nodes (71): configSTACK_DEPTH_TYPE, eNotifyAction, eTaskState, MemoryRegion_t, osThreadTerminate(), UBaseType_t, uxListRemove(), BaseType_t (+63 more)

### Community 12 - "Community 12"
Cohesion: 0.06
Nodes (62): __STATIC_INLINE, LL_PWR_ClearFlag_SB(), LL_PWR_ClearFlag_UD(), LL_PWR_ClearFlag_WU(), LL_PWR_DisableBkUpAccess(), LL_PWR_DisableBkUpRegulator(), LL_PWR_DisableFLASHInterfaceSTOP(), LL_PWR_DisableFLASHMemorySTOP() (+54 more)

### Community 13 - "Community 13"
Cohesion: 0.08
Nodes (56): DMA_HandleTypeDef, FlagStatus, HAL_StatusTypeDef, SPI_HandleTypeDef, __weak, HAL_SPI_Abort_IT(), HAL_SPI_AbortCpltCallback(), HAL_SPI_DeInit() (+48 more)

### Community 14 - "Community 14"
Cohesion: 0.11
Nodes (62): osMessageQueueGetCount(), xCoRoutineRemoveFromEventList(), BaseType_t, TaskHandle_t, TickType_t, UBaseType_t, pcQueueGetName(), prvCopyDataFromQueue() (+54 more)

### Community 15 - "Community 15"
Cohesion: 0.07
Nodes (53): analysis_angle_deg(), build_report(), compute_harmonic(), cross_jig_delta(), DataPoint, group_key(), GroupSummary, HarmonicResult (+45 more)

### Community 16 - "Community 16"
Cohesion: 0.03
Nodes (59): LL_TIM_CC_DisablePreload(), LL_TIM_CC_EnableChannel(), LL_TIM_CC_EnablePreload(), LL_TIM_CC_SetLockLevel(), LL_TIM_ClearFlag_CC2OVR(), LL_TIM_ClearFlag_CC3(), LL_TIM_ClearFlag_CC3OVR(), LL_TIM_ClearFlag_CC4() (+51 more)

### Community 17 - "Community 17"
Cohesion: 0.03
Nodes (60): __STATIC_INLINE, LL_TIM_CC_DisableChannel(), LL_TIM_CC_GetDMAReqTrigger(), LL_TIM_CC_SetDMAReqTrigger(), LL_TIM_ClearFlag_CC1(), LL_TIM_ClearFlag_CC4OVR(), LL_TIM_ClearFlag_COM(), LL_TIM_ConfigETR() (+52 more)

### Community 18 - "Community 18"
Cohesion: 0.03
Nodes (60): TIM_TypeDef, LL_TIM_CC_IsEnabledChannel(), LL_TIM_CC_SetUpdate(), LL_TIM_ClearFlag_BRK(), LL_TIM_ClearFlag_CC1OVR(), LL_TIM_ClearFlag_CC2(), LL_TIM_ClearFlag_TRIG(), LL_TIM_DisableBRK() (+52 more)

### Community 19 - "Community 19"
Cohesion: 0.08
Nodes (57): ADC_AnalogWDGConfTypeDef, ADC_ChannelConfTypeDef, ADC_InjectionConfTypeDef, ADC_MultiModeTypeDef, ADC_DMAConvCplt(), ADC_DMAError(), ADC_DMAHalfConvCplt(), ADC_Init() (+49 more)

### Community 20 - "Community 20"
Cohesion: 0.07
Nodes (55): __CLZ(), __get_APSR(), __get_MSPLIM(), __get_PSPLIM(), __packed, __STATIC_INLINE, __iar_u32(), __iar_uint16_read() (+47 more)

### Community 21 - "Community 21"
Cohesion: 0.10
Nodes (52): DMA_HandleTypeDef, HAL_StatusTypeDef, HAL_TIM_ChannelStateTypeDef, HAL_TIM_StateTypeDef, TIM_HandleTypeDef, TIM_TypeDef, __weak, HAL_TIMEx_BreakCallback() (+44 more)

### Community 22 - "Community 22"
Cohesion: 0.10
Nodes (49): ClosureProbeStageName(), ComputeFittedMinMaxDenseByOrders(), ComputeHarmonicFull(), ComputeModelMetricsByOrders(), ComputeResidualRms(), ComputeShadowMetrics(), FindHarmonic(), FindKnownJigByUid() (+41 more)

### Community 23 - "Community 23"
Cohesion: 0.04
Nodes (49): DMA_TypeDef, LL_DMA_ClearFlag_DME1(), LL_DMA_ClearFlag_DME2(), LL_DMA_ClearFlag_DME4(), LL_DMA_ClearFlag_DME7(), LL_DMA_ClearFlag_HT0(), LL_DMA_ClearFlag_HT3(), LL_DMA_ClearFlag_TC5() (+41 more)

### Community 24 - "Community 24"
Cohesion: 0.04
Nodes (48): LL_DMA_ClearFlag_DME3(), LL_DMA_ClearFlag_DME5(), LL_DMA_ClearFlag_FE0(), LL_DMA_ClearFlag_FE6(), LL_DMA_ClearFlag_FE7(), LL_DMA_ClearFlag_HT2(), LL_DMA_ClearFlag_TC2(), LL_DMA_ClearFlag_TC3() (+40 more)

### Community 25 - "Community 25"
Cohesion: 0.04
Nodes (49): __STATIC_INLINE, LL_DMA_ClearFlag_DME0(), LL_DMA_ClearFlag_DME6(), LL_DMA_ClearFlag_FE1(), LL_DMA_ClearFlag_FE2(), LL_DMA_ClearFlag_FE3(), LL_DMA_ClearFlag_FE4(), LL_DMA_ClearFlag_FE5() (+41 more)

### Community 26 - "Community 26"
Cohesion: 0.10
Nodes (45): HAL_StatusTypeDef, __weak, HAL_StatusTypeDef, FLASH_Erase_Sector(), FLASH_FlushCaches(), FLASH_MassErase(), FLASH_OB_BootConfig(), FLASH_OB_BOR_LevelConfig() (+37 more)

### Community 27 - "Community 27"
Cohesion: 0.10
Nodes (47): __DSB(), __ISB(), __NVIC_SystemReset(), __NVIC_SystemReset(), __NVIC_SystemReset(), __NVIC_SystemReset(), __NVIC_SystemReset(), __NVIC_SystemReset() (+39 more)

### Community 28 - "Community 28"
Cohesion: 0.12
Nodes (43): as_float(), as_int(), build_fit_rows(), build_stability_rows(), csv_write(), DataPoint, describe(), dft_amplitude() (+35 more)

### Community 29 - "Community 29"
Cohesion: 0.09
Nodes (42): ControlA4Report_t, ControlA4Result_t, AbsI32ToU32(), ControlA5CaptureReport_t, ControlA5Result_t, MA600_Sample_t, ControlA4PhaseProgressRaw(), ControlA4PowerPpm() (+34 more)

### Community 30 - "Community 30"
Cohesion: 0.12
Nodes (45): HAL_DMA_Start_IT(), HAL_StatusTypeDef, I2C_HandleTypeDef, HAL_I2C_AddrCallback(), HAL_I2C_DeInit(), HAL_I2C_DisableListen_IT(), HAL_I2C_EnableListen_IT(), HAL_I2C_GetError() (+37 more)

### Community 31 - "Community 31"
Cohesion: 0.13
Nodes (39): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_ClearTargetState(), NVIC_DecodePriority() (+31 more)

### Community 32 - "Community 32"
Cohesion: 0.13
Nodes (39): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_ClearTargetState(), NVIC_DecodePriority() (+31 more)

### Community 33 - "Community 33"
Cohesion: 0.10
Nodes (39): Motor_SetElectricalPos(), AbsI64ToU64(), AccumulateCounterDelta(), MA600_AcquisitionContext_t, MA600_PointSample_t, MA600_PointSamplerConfig_t, MA600_Result_t, MA600_Sample_t (+31 more)

### Community 34 - "Community 34"
Cohesion: 0.10
Nodes (38): __STATIC_INLINE, LL_AHB1_GRP1_DisableClock(), LL_AHB1_GRP1_DisableClockLowPower(), LL_AHB1_GRP1_EnableClock(), LL_AHB1_GRP1_EnableClockLowPower(), LL_AHB1_GRP1_ForceReset(), LL_AHB1_GRP1_IsEnabledClock(), LL_AHB1_GRP1_ReleaseReset() (+30 more)

### Community 35 - "Community 35"
Cohesion: 0.10
Nodes (36): BlockLink_t, ControlA5_CaptureResourcesInit(), HeapStats_t, osKernelGetState(), osKernelLock(), osKernelRestoreLock(), osKernelUnlock(), osMemoryPoolNew() (+28 more)

### Community 36 - "Community 36"
Cohesion: 0.13
Nodes (37): osTimerNew(), BaseType_t, TaskHandle_t, TickType_t, TimerHandle_t, UBaseType_t, pcTimerGetName(), prvCheckForValidListAndQueue() (+29 more)

### Community 37 - "Community 37"
Cohesion: 0.08
Nodes (18): TIM_HandleTypeDef, HAL_TIM_PeriodElapsedCallback(), HAL_StatusTypeDef, __weak, HAL_NVIC_SetPriorityGrouping(), HAL_SYSTICK_Config(), HAL_DeInit(), HAL_Delay() (+10 more)

### Community 38 - "Community 38"
Cohesion: 0.12
Nodes (27): HAL_GetTick(), FlagStatus, HAL_I2C_IsDeviceReady(), HAL_I2C_Master_Receive(), HAL_I2C_Master_Transmit(), HAL_I2C_Mem_Read(), HAL_I2C_Mem_Write(), HAL_I2C_Slave_Receive() (+19 more)

### Community 39 - "Community 39"
Cohesion: 0.12
Nodes (32): MA600_AcquisitionRunFaultInjectionSelfTest(), MA600_ReadMeta_t, MA600_Result_t, MA600_UnwrapContext_t, SPI_HandleTypeDef, Crc32IsoHdlc(), HAL_SPI_ErrorCallback(), HAL_SPI_TxRxCpltCallback() (+24 more)

### Community 40 - "Community 40"
Cohesion: 0.14
Nodes (30): AbsDeltaI64(), MA600_PointSample_t, MA600_PointSamplerConfig_t, MA600_ReadMeta_t, MA600_Result_t, MA600_UnwrapContext_t, ComputeMadFilteredPointMean(), CycleReached() (+22 more)

### Community 41 - "Community 41"
Cohesion: 0.16
Nodes (32): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_ClearTargetState(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority() (+24 more)

### Community 42 - "Community 42"
Cohesion: 0.16
Nodes (32): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_ClearTargetState(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority() (+24 more)

### Community 43 - "Community 43"
Cohesion: 0.16
Nodes (32): BaseType_t, TickType_t, UBaseType_t, prvBytesInBuffer(), prvInitialiseNewStreamBuffer(), prvReadBytesFromBuffer(), prvReadMessageFromBuffer(), prvWriteBytesToBuffer() (+24 more)

### Community 44 - "Community 44"
Cohesion: 0.14
Nodes (29): EventBits_t, EventGroupHandle_t, osEventFlagsClear(), osEventFlagsDelete(), osEventFlagsGet(), osEventFlagsNew(), osEventFlagsSet(), osEventFlagsWait() (+21 more)

### Community 45 - "Community 45"
Cohesion: 0.13
Nodes (28): __DMB(), __STATIC_INLINE, LL_CPUID_GetConstant(), LL_CPUID_GetImplementer(), LL_CPUID_GetParNo(), LL_CPUID_GetRevision(), LL_CPUID_GetVariant(), LL_HANDLER_DisableFault() (+20 more)

### Community 46 - "Community 46"
Cohesion: 0.13
Nodes (28): TIM_TypeDef, HAL_TIM_ConfigClockSource(), HAL_TIM_ConfigOCrefClear(), HAL_TIM_IC_ConfigChannel(), HAL_TIM_OC_ConfigChannel(), HAL_TIM_OnePulse_ConfigChannel(), HAL_TIM_PWM_ConfigChannel(), HAL_TIM_SlaveConfigSynchro() (+20 more)

### Community 47 - "Community 47"
Cohesion: 0.18
Nodes (26): ADC_HandleTypeDef, I2C_HandleTypeDef, SPI_HandleTypeDef, TIM_HandleTypeDef, UART_HandleTypeDef, HAL_ADC_MspDeInit(), HAL_ADC_MspInit(), HAL_I2C_MspDeInit() (+18 more)

### Community 48 - "Community 48"
Cohesion: 0.12
Nodes (25): crCOROUTINE_CODE, osThreadFlagsWait(), BaseType_t, List_t, TickType_t, UBaseType_t, prvCheckDelayedList(), prvCheckPendingReadyList() (+17 more)

### Community 49 - "Community 49"
Cohesion: 0.14
Nodes (22): __get_APSR(), __get_BASEPRI(), __get_CONTROL(), __get_FAULTMASK(), __get_FPSCR(), __get_IPSR(), __get_MSP(), __get_PRIMASK() (+14 more)

### Community 50 - "Community 50"
Cohesion: 0.21
Nodes (25): GPIO_TypeDef, __STATIC_INLINE, LL_GPIO_GetAFPin_0_7(), LL_GPIO_GetAFPin_8_15(), LL_GPIO_GetPinMode(), LL_GPIO_GetPinOutputType(), LL_GPIO_GetPinPull(), LL_GPIO_GetPinSpeed() (+17 more)

### Community 51 - "Community 51"
Cohesion: 0.18
Nodes (23): ControlA5AbortRequestedFn_t, ControlA5Sample_t, ControlA5CaptureReport_t, ControlA5Result_t, Motor_ControllerState_t, ControlA5_AbsI32(), ControlA5_CaptureReportInit(), ControlA5_CaptureResourcesReady() (+15 more)

### Community 52 - "Community 52"
Cohesion: 0.11
Nodes (17): ADC_IRQHandler(), DMA1_Stream1_IRQHandler(), DMA1_Stream3_IRQHandler(), DMA1_Stream5_IRQHandler(), DMA1_Stream6_IRQHandler(), DMA1_Stream7_IRQHandler(), DMA2_Stream0_IRQHandler(), DMA2_Stream2_IRQHandler() (+9 more)

### Community 53 - "Community 53"
Cohesion: 0.20
Nodes (22): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ() (+14 more)

### Community 54 - "Community 54"
Cohesion: 0.20
Nodes (22): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ() (+14 more)

### Community 55 - "Community 55"
Cohesion: 0.20
Nodes (22): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ() (+14 more)

### Community 57 - "Community 57"
Cohesion: 0.09
Nodes (23): ADC_Common_TypeDef, LL_ADC_GetCommonClock(), LL_ADC_GetCommonPathInternalCh(), LL_ADC_GetMultiDMATransfer(), LL_ADC_GetMultimode(), LL_ADC_GetMultiTwoSamplingDelay(), LL_ADC_IsActiveFlag_MST_AWD1(), LL_ADC_IsActiveFlag_MST_EOCS() (+15 more)

### Community 58 - "Community 58"
Cohesion: 0.14
Nodes (22): LL_ADC_Disable(), LL_ADC_INJ_SetSequencerLength(), LL_ADC_INJ_SetTriggerSource(), LL_ADC_IsEnabled(), LL_ADC_REG_SetSequencerLength(), LL_ADC_REG_SetTriggerSource(), LL_ADC_SetCommonClock(), ADC_TypeDef (+14 more)

### Community 59 - "Community 59"
Cohesion: 0.12
Nodes (19): MX_TIM2_Init(), HAL_StatusTypeDef, HAL_InitTick(), HAL_TIM_Base_Init(), HAL_TIM_Base_MspInit(), HAL_TIM_Encoder_Init(), HAL_TIM_Encoder_MspInit(), HAL_TIM_IC_Init() (+11 more)

### Community 60 - "Community 60"
Cohesion: 0.14
Nodes (22): DMA_HandleTypeDef, __weak, HAL_TIM_ErrorCallback(), HAL_TIM_IC_CaptureCallback(), HAL_TIM_IC_CaptureHalfCpltCallback(), HAL_TIM_IRQHandler(), HAL_TIM_OC_DelayElapsedCallback(), HAL_TIM_PeriodElapsedCallback() (+14 more)

### Community 61 - "Community 61"
Cohesion: 0.11
Nodes (16): eSleepModeStatus, BaseType_t, StackType_t, TaskFunction_t, TickType_t, prvPortStartFirstTask(), prvTaskExitError(), pxPortInitialiseStack() (+8 more)

### Community 62 - "Community 62"
Cohesion: 0.13
Nodes (14): AppEngine_Init(), AppEngine_IsBusy(), AppEngine_ModeId(), AppEngine_ProfileFingerprint(), AppEngine_ProfileId(), AppEngine_RequestStart(), AppEngine_SourceId(), ControlA5_CaptureResourcesReleaseForInitFailure() (+6 more)

### Community 63 - "Community 63"
Cohesion: 0.24
Nodes (20): ARM_MPU_ClrRegion(), ARM_MPU_ClrRegion_NS(), ARM_MPU_ClrRegionEx(), ARM_MPU_Disable(), ARM_MPU_Disable_NS(), ARM_MPU_Enable(), ARM_MPU_Enable_NS(), ARM_MPU_Load() (+12 more)

### Community 64 - "Community 64"
Cohesion: 0.14
Nodes (11): TaskHandle_t, vApplicationMallocFailedHook(), vApplicationStackOverflowHook(), Motor_Enable(), MotorPwm_Disable(), MotorPwm_Enable(), MotorPwm_Init(), MotorPwm_PhaseValue() (+3 more)

### Community 65 - "Community 65"
Cohesion: 0.18
Nodes (19): MA600_UnwrappedRawToDegrees(), MA600_Result_t, Motor_GetCommandedPos(), Motor_MoveToAngle(), Motor_MoveToAngleWithPower(), Motor_ControllerState_t, ControllerStateIsReset(), FinishMoveToZeroObservation() (+11 more)

### Community 66 - "Community 66"
Cohesion: 0.11
Nodes (5): __weak, HAL_PWR_ConfigPVD(), HAL_PWR_PVD_IRQHandler(), HAL_PWR_PVDCallback(), PWR_PVDTypeDef

### Community 68 - "Community 68"
Cohesion: 0.18
Nodes (20): DMA_HandleTypeDef, __weak, HAL_I2C_AbortCpltCallback(), HAL_I2C_ER_IRQHandler(), HAL_I2C_ErrorCallback(), HAL_I2C_ListenCpltCallback(), HAL_I2C_MasterRxCpltCallback(), HAL_I2C_MemRxCpltCallback() (+12 more)

### Community 69 - "Community 69"
Cohesion: 0.15
Nodes (15): HAL_StatusTypeDef, RCC_OscInitTypeDef, HAL_RCC_DeInit(), HAL_RCC_GetOscConfig(), HAL_RCC_OscConfig(), HAL_RCCEx_DisablePLLI2S(), HAL_RCCEx_DisablePLLSAI(), HAL_RCCEx_EnablePLLI2S() (+7 more)

### Community 70 - "Community 70"
Cohesion: 0.15
Nodes (8): Add-Reason(), Assert-FieldEquals(), Get-I64(), Get-LinearDiagnostics(), Get-PopulationStdDev(), Get-RequiredField(), Get-SingleRecord(), Get-U32()

### Community 71 - "Community 71"
Cohesion: 0.24
Nodes (17): ControlA5GoldenVector_t, ControlA5Stats_t, ControlA5Summary_t, AbsI32ToU32(), ControlA5_MathSelfTest(), ControlA5_MeanRelRawQ16(), ControlA5_RawWordsCrc32(), ControlA5_StatsFinalize() (+9 more)

### Community 72 - "Community 72"
Cohesion: 0.21
Nodes (17): __STATIC_INLINE, LL_EXTI_ClearFlag_0_31(), LL_EXTI_DisableEvent_0_31(), LL_EXTI_DisableFallingTrig_0_31(), LL_EXTI_DisableIT_0_31(), LL_EXTI_DisableRisingTrig_0_31(), LL_EXTI_EnableEvent_0_31(), LL_EXTI_EnableFallingTrig_0_31() (+9 more)

### Community 73 - "Community 73"
Cohesion: 0.18
Nodes (16): expand_logfiles(), export_runs_csv(), launch_gui(), linear_fit(), load_runs(), main(), parse_kv(), Path (+8 more)

### Community 74 - "Community 74"
Cohesion: 0.28
Nodes (16): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority(), __NVIC_GetEnableIRQ() (+8 more)

### Community 75 - "Community 75"
Cohesion: 0.28
Nodes (16): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority(), __NVIC_GetEnableIRQ() (+8 more)

### Community 76 - "Community 76"
Cohesion: 0.28
Nodes (16): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority(), __NVIC_GetEnableIRQ() (+8 more)

### Community 77 - "Community 77"
Cohesion: 0.29
Nodes (14): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), __NVIC_GetEnableIRQ(), __NVIC_GetPendingIRQ(), __NVIC_GetPriority() (+6 more)

### Community 78 - "Community 78"
Cohesion: 0.17
Nodes (12): IRQn_Type, __weak, HAL_MPU_ConfigRegion(), HAL_MPU_Enable(), HAL_NVIC_ClearPendingIRQ(), HAL_NVIC_GetActive(), HAL_NVIC_GetPendingIRQ(), HAL_NVIC_GetPriority() (+4 more)

### Community 79 - "Community 79"
Cohesion: 0.33
Nodes (13): Error_Handler(), main(), MX_ADC1_Init(), MX_DMA_Init(), MX_GPIO_Init(), MX_I2C1_Init(), MX_I2C2_Init(), MX_SPI1_Init() (+5 more)

### Community 80 - "Community 80"
Cohesion: 0.30
Nodes (14): DMA_HandleTypeDef, HAL_StatusTypeDef, DMA_CalcBaseAndBitshift(), DMA_CheckFifoParam(), DMA_SetConfig(), HAL_DMA_GetState(), HAL_DMA_Init(), HAL_DMA_PollForTransfer() (+6 more)

### Community 81 - "Community 81"
Cohesion: 0.29
Nodes (13): HAL_StatusTypeDef, HAL_EXTI_ClearConfigLine(), HAL_EXTI_ClearPending(), HAL_EXTI_GenerateSWI(), HAL_EXTI_GetConfigLine(), HAL_EXTI_GetHandle(), HAL_EXTI_GetPending(), HAL_EXTI_IRQHandler() (+5 more)

### Community 82 - "Community 82"
Cohesion: 0.21
Nodes (5): portFORCE_INLINE, ulPortRaiseBASEPRI(), vPortRaiseBASEPRI(), vPortSetBASEPRI(), xPortIsInsideInterrupt()

### Community 83 - "Community 83"
Cohesion: 0.21
Nodes (8): gremsyMotorDisable(), gremsyMotorEnable(), gremsyMotorInit(), gremsyMotorMoveAngle(), gremsyMotorMovePos(), gremsyMotorMoveSpeed(), gremsyMotorSetPWM(), limit_integer()

### Community 84 - "Community 84"
Cohesion: 0.26
Nodes (12): DataFrame, ndarray, detect_transitions(), format_si_time(), load_waveform(), main(), parse_header(), Path (+4 more)

### Community 85 - "Community 85"
Cohesion: 0.23
Nodes (12): HAL_I2C_EV_IRQHandler(), HAL_I2C_MasterTxCpltCallback(), HAL_I2C_MemTxCpltCallback(), I2C_ConvertOtherXferOptions(), I2C_Master_ADD10(), I2C_Master_ADDR(), I2C_Master_SB(), I2C_MasterTransmit_BTF() (+4 more)

### Community 86 - "Community 86"
Cohesion: 0.28
Nodes (12): Atomic_Add_u32(), Atomic_AND_u32(), Atomic_CompareAndSwap_u32(), Atomic_CompareAndSwapPointers_p32(), Atomic_Decrement_u32(), Atomic_Increment_u32(), Atomic_NAND_u32(), Atomic_OR_u32() (+4 more)

### Community 87 - "Community 87"
Cohesion: 0.26
Nodes (12): amp_phase(), analytic_detrend(), analyze_file(), dft(), main(), parse_log(), Return {sweepId: {'err': {pointIndex: errDeg}, 'res': {k: v}, 'closure': f}}., Single-bin DFT identical to firmware ComputeHarmonicFull (mean-removed). (+4 more)

### Community 88 - "Community 88"
Cohesion: 0.24
Nodes (7): Convert-ToNullableDouble(), Get-CircularDeltaRaw(), Get-CircularMeanRaw(), Get-Mean(), Get-NumberedRegexValues(), Get-StdDev(), Get-V32SectorGateResult()

### Community 89 - "Community 89"
Cohesion: 0.29
Nodes (10): analyze_a4(), analyze_b0b(), blend(), expected_cum(), main(), parse_a4_log(), parse_b0b_log(), Return list of per-tick dicts from CONTROL_A4_DATA (decimated 3:1, plus final… (+2 more)

### Community 90 - "Community 90"
Cohesion: 0.36
Nodes (9): ARM_MPU_ClrRegion(), ARM_MPU_Disable(), ARM_MPU_Enable(), ARM_MPU_Load(), ARM_MPU_SetRegion(), ARM_MPU_SetRegionEx(), ARM_MPU_Region_t, __STATIC_INLINE (+1 more)

### Community 91 - "Community 91"
Cohesion: 0.27
Nodes (9): GPIO_TypeDef, HAL_StatusTypeDef, __weak, HAL_GPIO_EXTI_Callback(), HAL_GPIO_EXTI_IRQHandler(), HAL_GPIO_LockPin(), HAL_GPIO_ReadPin(), HAL_GPIO_TogglePin() (+1 more)

### Community 95 - "Community 95"
Cohesion: 0.36
Nodes (7): packed, __PACKED_STRUCT, T_UINT16_READ(), T_UINT16_WRITE(), T_UINT32(), T_UINT32_READ(), T_UINT32_WRITE()

### Community 96 - "Community 96"
Cohesion: 0.43
Nodes (7): __STATIC_INLINE, LL_GetFlashSize(), LL_GetPackageType(), LL_GetUID_Word0(), LL_GetUID_Word1(), LL_GetUID_Word2(), LL_InitTick()

### Community 97 - "Community 97"
Cohesion: 0.50
Nodes (7): DMA_HandleTypeDef, HAL_StatusTypeDef, DMA_MultiBufferSetConfig(), HAL_DMAEx_ChangeMemory(), HAL_DMAEx_MultiBufferStart(), HAL_DMAEx_MultiBufferStart_IT(), HAL_DMA_MemoryTypeDef

### Community 98 - "Community 98"
Cohesion: 0.39
Nodes (5): Canonical-MeanQ16(), Div-RoundNearestAwayFromZero(), Model-Schedule(), Signed-CycleDelta(), To-U32()

### Community 100 - "Community 100"
Cohesion: 0.33
Nodes (5): void(), HAL_FLASHEx_DisableFlashSleepMode, HAL_FLASHEx_EnableFlashSleepMode, HAL_FLASHEx_StartFlashInterfaceClk, HAL_FLASHEx_StopFlashInterfaceClk

### Community 101 - "Community 101"
Cohesion: 0.67
Nodes (5): Assert-True(), Assert-Vector(), Get-Crc32RawWords(), Get-Stats(), Get-WrapDelta()

### Community 102 - "Community 102"
Cohesion: 0.40
Nodes (5): __PACKED_STRUCT, T_UINT16_READ(), T_UINT16_WRITE(), T_UINT32_READ(), T_UINT32_WRITE()

### Community 103 - "Community 103"
Cohesion: 0.40
Nodes (5): __PACKED_STRUCT, T_UINT16_READ(), T_UINT16_WRITE(), T_UINT32_READ(), T_UINT32_WRITE()

### Community 104 - "Community 104"
Cohesion: 0.60
Nodes (4): HAL_StatusTypeDef, I2C_HandleTypeDef, HAL_I2CEx_ConfigAnalogFilter(), HAL_I2CEx_ConfigDigitalFilter()

### Community 105 - "Community 105"
Cohesion: 0.80
Nodes (4): Assert-ChildPath(), Build-ModeImage(), Copy-ArtifactSet(), Invoke-BundledMake()

## Knowledge Gaps
- **1 isolated node(s):** `v`
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `HAL_GetTick()` connect `Community 38` to `Community 65`, `Community 33`, `Community 37`, `Community 5`, `Community 69`, `Community 13`, `Community 80`, `Community 51`, `Community 19`, `Community 22`, `Community 26`, `Community 29`, `Community 30`?**
  _High betweenness centrality (0.127) - this node is a cross-community bridge._
- **Why does `LL_MPU_Enable()` connect `Community 45` to `Community 27`?**
  _High betweenness centrality (0.078) - this node is a cross-community bridge._
- **Why does `Error_Handler()` connect `Community 79` to `Community 64`, `Community 1`, `Community 59`, `Community 47`, `Community 83`, `Community 91`?**
  _High betweenness centrality (0.073) - this node is a cross-community bridge._
- **What connects `v` to the rest of the system?**
  _1 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.043151567196221555 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.02984734563681932 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.052606177606177605 - nodes in this community are weakly interconnected._