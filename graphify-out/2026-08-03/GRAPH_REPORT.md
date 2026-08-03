# Graph Report - jigmotor  (2026-08-03)

## Corpus Check
- 386 files · ~8,240,642 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 5086 nodes · 10899 edges · 270 communities (257 shown, 13 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 837 edges (avg confidence: 0.79)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `172fa7ea`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- stm32f4xx_ll_usart.h
- cmsis_gcc.h
- stm32f4xx_ll_i2c.h
- cmsis_armclang.h
- cmsis_os2.c
- stm32f4xx_hal_uart.c
- stm32f4xx_ll_rcc.h
- __STATIC_INLINE
- stm32f4xx_ll_system.h
- stm32f4xx_ll_adc.h
- stm32f4xx_hal_tim.c
- tasks.c
- stm32f4xx_ll_pwr.h
- stm32f4xx_hal_spi.c
- queue.c
- analyze_motor_logs.py
- stm32f4xx_ll_tim.h
- __STATIC_INLINE
- TIM_TypeDef
- stm32f4xx_hal_adc.c
- cmsis_iccarm.h
- stm32f4xx_hal_tim_ex.c
- nonlinear_test.c
- DMA_TypeDef
- stm32f4xx_ll_dma.h
- __STATIC_INLINE
- stm32f4xx_hal_flash_ex.c
- __DSB
- analyze_nl_stability.py
- control_engine.c
- stm32f4xx_hal_i2c.c
- core_armv8mml.h
- core_cm33.h
- CaptureSweep
- stm32f4xx_ll_bus.h
- pvPortMalloc
- timers.c
- stm32f4xx_hal.c
- HAL_GetTick
- Thiết kế hệ thống firmware V2 — tái cấu trúc nhưng giữ nguyên thuật toán
- ma600_acquisition.c
- core_armv8mbl.h
- core_cm23.h
- stream_buffer.c
- event_groups.c
- stm32f4xx_ll_cortex.h
- TIM_TypeDef
- stm32f4xx_hal_msp.c
- croutine.c
- cmsis_armcc.h
- stm32f4xx_ll_gpio.h
- control_a5_capture.c
- stm32f4xx_it.c
- core_cm3.h
- core_cm4.h
- core_sc300.h
- ADC_Common_TypeDef
- stm32f4xx_ll_adc.c
- TIM_Base_SetConfig
- __weak
- task.h
- StartDefaultTask
- mpu_armv8.h
- Tăng K (NL_SAMPLES_PER_POINT) từ 20 lên 64, giữ N=256
- Motor_MoveToAngle
- stm32f4xx_hal_pwr.c
- syscalls.c
- __weak
- stm32f4xx_hal_rcc_ex.c
- analyze_control_a5.ps1
- control_a5_math.c
- stm32f4xx_ll_exti.h
- plot_metric_trend.py
- core_cm0.h
- core_cm0plus.h
- core_cm1.h
- core_sc000.h
- stm32f4xx_hal_cortex.c
- main
- stm32f4xx_hal_dma.c
- stm32f4xx_hal_exti.c
- portmacro.h
- gremsyMotor.c
- analyze_scope_capture.py
- HAL_I2C_EV_IRQHandler
- atomic.h
- analyze_detrended_harmonics.py
- analyze_nonlinear_logs.ps1
- analyze_b0b_transient.py
- mpu_armv7.h
- HAL_GPIO_WritePin
- analyze_control_a2.ps1
- analyze_control_a4.ps1
- cmsis_compiler.h
- stm32f4xx_ll_utils.h
- stm32f4xx_hal_dma_ex.c
- test_canonical_sampler_contract.ps1
- stm32f4xx.h
- void
- test_control_a5_math_contract.ps1
- __PACKED_STRUCT
- __PACKED_STRUCT
- HAL_I2CEx_ConfigAnalogFilter
- build_dual_image.ps1
- __STATIC_INLINE
- clean_cubeide.ps1
- test_control_a5_capture_contract.ps1
- T_UINT32
- BatchLogRecorder
- Plan A5 — MA600 static RawAngle stability
- B0-B V3 — CW no-reversal approach plan
- MA600A Canonical Acquisition Improvement Plan
- FlasherApp
- analyze_nl_curve.py
- Plan sửa trình tự alignment/enable cho Motor Control C0
- Plan tái cấu trúc và tối ưu SPI acquisition có kiểm soát
- Thiết kế hệ thống dual-image tối ưu STM32F405
- STM32Bootloader
- Phase 3B0 - Closure and Measurement-Validity Design Review
- What You Must Do When Invoked
- Tổng hợp phát hiện: yếu tố ảnh hưởng NL, so sánh JIG, và rà soát thuật toán PID/sensor (2026-07-27)
- Nonlinear Algorithm Audit — toàn bộ finding, theo mục 6.1-6.13
- analyze_nl_extreme_angles.py
- Codex handoff: NL validity and cross-jig synchronization
- Plan thử nghiệm motor 7 cặp cực
- GremsyQAApp
- Codex handoff — Motion Control V2, lưới 1° và SPI1 DMA
- 3. Kế hoạch hành động — theo thứ tự ưu tiên
- FirmwareSegment
- 3. Call graph cho 9 luồng yêu cầu
- SweepReport
- Extreme points on each batch-mean curve
- End-of-Shaft Mounting Verification Test Plan (MA600A)
- STM32 UART Flasher
- Plan A3 — Alignment bằng phase trajectory (rotating capture + drag)
- Kết quả A3 — sub-mechanism PASS, arbitrary-start alignment FAIL; đóng A3, chuyển A4
- Plan MATLAB — phân tích offline A2/A2B/A2C power-envelope
- 2. Việc bạn cần làm trên phần cứng
- A5 implementation and validation checklist
- Kết quả A5 — MA600 RawAngle static stability: đã khóa
- Cross-jig measurement analysis — P03/P05 × JIG1/JIG3
- Thông số đo và kiểm tra (Measured & Checked Parameters)
- Motion Control V2 — implementation and hardware qualification
- Sweep
- NL pointwise-curve assessment — p05
- NL pointwise-curve assessment — p03
- NL pointwise-curve assessment — p05
- NL pointwise-curve assessment — p03
- NL pointwise-curve assessment — p03
- NL pointwise-curve assessment — p03
- NL pointwise-curve assessment — p05
- NL pointwise-curve assessment — p05
- Control A2F — fixed-phase power-envelope, P09/H500
- Architecture Migration Hardware Validation
- Nonlinear Log Schema v6 Contract
- 1. Vì sao phải thay đổi cách tính nonlinear hiện tại (legacy, schema v5)
- Nonlinear Metric Definition Contract v1
- Phase 2B Shadow Checklist
- NL pointwise-curve assessment — p03
- NL pointwise-curve assessment — p05
- CONTROL A5 activation build (A5.4)
- graphify reference: extra exports and benchmark
- B0-B — kết quả closure và approach (test 18–23), tính độc lập bằng MATLAB
- Kết quả A2F — P09 hoàn tất power envelope, đóng sổ fixed-phase
- A3 — Đề xuất struct/hằng số cho Codex review
- Control C0 — hardware test 1°
- Đánh giá cách đọc dữ liệu MA600A trong firmware Gremsy cũ (gremsyEncoder.c / gremsyMotor.c / gremsyTaskManager.c / gremsyAnalog.c)
- Nonlinear Metric Definition Contract v2
- Kế hoạch triển khai dual-image trên STM32F405
- Serial
- Extreme points on each batch-mean curve
- Extreme points on each batch-mean curve
- Extreme points on each batch-mean curve
- MoveToZeroAndCheckDirection
- Architecture Migration Baseline
- Baseline manifest — Motion V2 + SPI DMA trước dual-image
- NL pointwise-curve analysis tool
- Phase 3A - Continuous Motion, Settle, and Motor Pole Checklist
- Extreme points on each batch-mean curve
- Extreme points on each batch-mean curve
- Extreme points on each batch-mean curve
- Extreme points on each batch-mean curve
- B0-B soft-start — Phase A result (log mining) và thiết kế Phase B
- MATLAB result — A2 đến A2E power-envelope
- A2 — Quét xoay vòng (rotating-capture), phi tuyến & sóng hài
- Preconditioned 10-run repeatability experiment
- Extreme points on each batch-mean curve
- CONTROL A4B rollback baseline
- graphify reference: query, path, explain
- Phase 3B0-R - Controller-State Synchronization Checklist
- Test 33: NL extreme-angle cross-jig assessment
- Chốt phương thức đo B0-B bằng MATLAB
- B0-B test 21 A-B-A assessment
- Phase 2A Canonical Sampler Status
- 3. Phase P0 — đóng băng baseline (hoàn tất)
- 5. Phase P2 — memory map và RTOS observability
- 7. Phase C0 — Control image quan sát plant, chưa đóng loop (source/build gate hoàn tất)
- jigmotor
- Chốt phương thức đo B0-B bằng MATLAB
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- A5 — Ổn định góc thô tĩnh (MA600 static RawAngle stability)
- 15. Phase Q — qualification cuối
- 4. Phase P1 — build identity và compile-time isolation (hoàn tất source/build gate)
- 8. Phase C1 — hardware-timed control pipeline
- 9. Phase C2 — controller P-only
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- A3 — Căn chỉnh quỹ đạo pha (rotating-capture)
- 10. Phase C3 — damping và static-error removal
- 11. Phase M0 — khóa Measurement image
- 14. Phase S1 — safety và watchdog
- 6. Phase P3 — shared platform và ownership
- AGENTS.md
- extraction-spec.md
- schema-v5-phase1-baseline.md
- MA600A.md

## God Nodes (most connected - your core abstractions)
1. `HAL_GetTick()` - 66 edges
2. `FlasherApp` - 46 edges
3. `__DSB()` - 45 edges
4. `TIM_CCxChannelCmd()` - 40 edges
5. `CaptureSweep()` - 37 edges
6. `__ISB()` - 34 edges
7. `HAL_DMA_Start_IT()` - 31 edges
8. `uxListRemove()` - 28 edges
9. `xTaskResumeAll()` - 27 edges
10. `BatchLogRecorder` - 27 edges

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

## Communities (270 total, 13 thin omitted)

### Community 0 - "stm32f4xx_ll_usart.h"
Cohesion: 0.04
Nodes (136): __STATIC_INLINE, LL_USART_ClearFlag_FE(), LL_USART_ClearFlag_IDLE(), LL_USART_ClearFlag_LBD(), LL_USART_ClearFlag_nCTS(), LL_USART_ClearFlag_NE(), LL_USART_ClearFlag_ORE(), LL_USART_ClearFlag_PE() (+128 more)

### Community 1 - "cmsis_gcc.h"
Cohesion: 0.03
Nodes (133): __CLREX(), __disable_fault_irq(), __disable_irq(), __DMB(), __enable_fault_irq(), __enable_irq(), __get_APSR(), __get_BASEPRI() (+125 more)

### Community 2 - "stm32f4xx_ll_i2c.h"
Cohesion: 0.05
Nodes (111): __STATIC_INLINE, LL_I2C_AcknowledgeNextData(), LL_I2C_ClearFlag_ADDR(), LL_I2C_ClearFlag_AF(), LL_I2C_ClearFlag_ARLO(), LL_I2C_ClearFlag_BERR(), LL_I2C_ClearFlag_OVR(), LL_I2C_ClearFlag_STOP() (+103 more)

### Community 3 - "cmsis_armclang.h"
Cohesion: 0.04
Nodes (109): __get_APSR(), __get_BASEPRI(), __get_CONTROL(), __get_FAULTMASK(), __get_IPSR(), __get_MSP(), __get_MSPLIM(), __get_PRIMASK() (+101 more)

### Community 4 - "cmsis_os2.c"
Cohesion: 0.03
Nodes (99): AppEngine_RequestStart(), ControlEngine_RequestStart(), NonlinearEngine_RequestStart(), MemPool_t, AllocBlock(), StackType_t, __STATIC_INLINE, StaticTask_t (+91 more)

### Community 5 - "stm32f4xx_hal_uart.c"
Cohesion: 0.06
Nodes (92): HAL_DMA_Abort(), HAL_DMA_GetError(), HAL_StatusTypeDef, RCC_OscInitTypeDef, __weak, HAL_RCC_ClockConfig(), HAL_RCC_CSSCallback(), HAL_RCC_GetClockConfig() (+84 more)

### Community 6 - "stm32f4xx_ll_rcc.h"
Cohesion: 0.02
Nodes (84): LL_RCC_ClearFlag_HSECSS(), LL_RCC_ClearFlag_HSIRDY(), LL_RCC_ClearFlag_PLLI2SRDY(), LL_RCC_ClearResetFlags(), LL_RCC_DisableIT_HSERDY(), LL_RCC_DisableIT_LSERDY(), LL_RCC_DisableIT_LSIRDY(), LL_RCC_DisableIT_PLLSAIRDY() (+76 more)

### Community 7 - "__STATIC_INLINE"
Cohesion: 0.02
Nodes (85): __STATIC_INLINE, LL_RCC_ClearFlag_HSERDY(), LL_RCC_ClearFlag_LSERDY(), LL_RCC_ClearFlag_LSIRDY(), LL_RCC_ClearFlag_PLLRDY(), LL_RCC_ClearFlag_PLLSAIRDY(), LL_RCC_ConfigMCO(), LL_RCC_DisableIT_HSIRDY() (+77 more)

### Community 8 - "stm32f4xx_ll_system.h"
Cohesion: 0.05
Nodes (41): LL_DBGMCU_APB2_GRP1_FreezePeriph(), LL_DBGMCU_APB2_GRP1_UnFreezePeriph(), LL_DBGMCU_DisableDBGStandbyMode(), LL_DBGMCU_DisableDBGStopMode(), LL_DBGMCU_EnableDBGSleepMode(), LL_DBGMCU_EnableDBGStopMode(), LL_DBGMCU_GetRevisionID(), LL_DBGMCU_GetTracePinAssignment() (+33 more)

### Community 9 - "stm32f4xx_ll_adc.h"
Cohesion: 0.07
Nodes (78): ADC_TypeDef, __STATIC_INLINE, LL_ADC_ClearFlag_AWD1(), LL_ADC_ClearFlag_EOCS(), LL_ADC_ClearFlag_JEOS(), LL_ADC_ClearFlag_OVR(), LL_ADC_DisableIT_AWD1(), LL_ADC_DisableIT_EOCS() (+70 more)

### Community 10 - "stm32f4xx_hal_tim.c"
Cohesion: 0.08
Nodes (76): HAL_DMA_Abort_IT(), HAL_StatusTypeDef, HAL_TIM_ChannelStateTypeDef, HAL_TIM_StateTypeDef, TIM_HandleTypeDef, HAL_TIM_Base_DeInit(), HAL_TIM_Base_GetState(), HAL_TIM_Base_MspDeInit() (+68 more)

### Community 11 - "tasks.c"
Cohesion: 0.06
Nodes (89): configSTACK_DEPTH_TYPE, eNotifyAction, eTaskState, HeapStats_t, MemoryRegion_t, osKernelRestoreLock(), osThreadGetStackSpace(), vEventGroupDelete() (+81 more)

### Community 12 - "stm32f4xx_ll_pwr.h"
Cohesion: 0.06
Nodes (62): __STATIC_INLINE, LL_PWR_ClearFlag_SB(), LL_PWR_ClearFlag_UD(), LL_PWR_ClearFlag_WU(), LL_PWR_DisableBkUpAccess(), LL_PWR_DisableBkUpRegulator(), LL_PWR_DisableFLASHInterfaceSTOP(), LL_PWR_DisableFLASHMemorySTOP() (+54 more)

### Community 13 - "stm32f4xx_hal_spi.c"
Cohesion: 0.05
Nodes (84): MA600_ReadMeta_t, MA600_Result_t, SPI_HandleTypeDef, Crc32IsoHdlc(), HAL_SPI_ErrorCallback(), HAL_SPI_TxRxCpltCallback(), MA600_ClearErrorFlags(), MA600_ConfigurationGateSelfTest() (+76 more)

### Community 14 - "queue.c"
Cohesion: 0.10
Nodes (67): osMessageQueueGet(), osMessageQueueGetCount(), xCoRoutineRemoveFromEventList(), BaseType_t, TaskHandle_t, TickType_t, UBaseType_t, pcQueueGetName() (+59 more)

### Community 15 - "analyze_motor_logs.py"
Cohesion: 0.16
Nodes (20): analysis_angle_deg(), compute_harmonic(), DataPoint, HarmonicResult, load_sweeps(), _parse_data_line(), _parse_kv_line(), META/RESULT/END/CONFIG/BATCH/SHADOW_* lines: RECORD,key=val,key=val,... Values… (+12 more)

### Community 16 - "stm32f4xx_ll_tim.h"
Cohesion: 0.03
Nodes (59): LL_TIM_CC_DisablePreload(), LL_TIM_CC_EnableChannel(), LL_TIM_CC_EnablePreload(), LL_TIM_CC_SetLockLevel(), LL_TIM_ClearFlag_CC2OVR(), LL_TIM_ClearFlag_CC3(), LL_TIM_ClearFlag_CC3OVR(), LL_TIM_ClearFlag_CC4() (+51 more)

### Community 17 - "__STATIC_INLINE"
Cohesion: 0.03
Nodes (60): __STATIC_INLINE, LL_TIM_CC_DisableChannel(), LL_TIM_CC_GetDMAReqTrigger(), LL_TIM_CC_SetDMAReqTrigger(), LL_TIM_ClearFlag_CC1(), LL_TIM_ClearFlag_CC4OVR(), LL_TIM_ClearFlag_COM(), LL_TIM_ConfigETR() (+52 more)

### Community 18 - "TIM_TypeDef"
Cohesion: 0.03
Nodes (60): TIM_TypeDef, LL_TIM_CC_IsEnabledChannel(), LL_TIM_CC_SetUpdate(), LL_TIM_ClearFlag_BRK(), LL_TIM_ClearFlag_CC1OVR(), LL_TIM_ClearFlag_CC2(), LL_TIM_ClearFlag_TRIG(), LL_TIM_DisableBRK() (+52 more)

### Community 19 - "stm32f4xx_hal_adc.c"
Cohesion: 0.08
Nodes (57): ADC_AnalogWDGConfTypeDef, ADC_ChannelConfTypeDef, ADC_InjectionConfTypeDef, ADC_MultiModeTypeDef, ADC_DMAConvCplt(), ADC_DMAError(), ADC_DMAHalfConvCplt(), ADC_Init() (+49 more)

### Community 20 - "cmsis_iccarm.h"
Cohesion: 0.07
Nodes (55): __CLZ(), __get_APSR(), __get_MSPLIM(), __get_PSPLIM(), __packed, __STATIC_INLINE, __iar_u32(), __iar_uint16_read() (+47 more)

### Community 21 - "stm32f4xx_hal_tim_ex.c"
Cohesion: 0.11
Nodes (50): DMA_HandleTypeDef, HAL_StatusTypeDef, HAL_TIM_ChannelStateTypeDef, HAL_TIM_StateTypeDef, TIM_HandleTypeDef, TIM_TypeDef, __weak, HAL_TIMEx_BreakCallback() (+42 more)

### Community 22 - "nonlinear_test.c"
Cohesion: 0.10
Nodes (49): ClosureProbeStageName(), ComputeFittedMinMaxDenseByOrders(), ComputeHarmonicFull(), ComputeModelMetricsByOrders(), ComputeResidualRms(), ComputeShadowMetrics(), FindHarmonic(), FindKnownJigByUid() (+41 more)

### Community 23 - "DMA_TypeDef"
Cohesion: 0.04
Nodes (49): DMA_TypeDef, LL_DMA_ClearFlag_DME1(), LL_DMA_ClearFlag_DME2(), LL_DMA_ClearFlag_DME4(), LL_DMA_ClearFlag_DME7(), LL_DMA_ClearFlag_HT0(), LL_DMA_ClearFlag_HT3(), LL_DMA_ClearFlag_TC5() (+41 more)

### Community 24 - "stm32f4xx_ll_dma.h"
Cohesion: 0.04
Nodes (48): LL_DMA_ClearFlag_DME3(), LL_DMA_ClearFlag_DME5(), LL_DMA_ClearFlag_FE0(), LL_DMA_ClearFlag_FE6(), LL_DMA_ClearFlag_FE7(), LL_DMA_ClearFlag_HT2(), LL_DMA_ClearFlag_TC2(), LL_DMA_ClearFlag_TC3() (+40 more)

### Community 25 - "__STATIC_INLINE"
Cohesion: 0.04
Nodes (49): __STATIC_INLINE, LL_DMA_ClearFlag_DME0(), LL_DMA_ClearFlag_DME6(), LL_DMA_ClearFlag_FE1(), LL_DMA_ClearFlag_FE2(), LL_DMA_ClearFlag_FE3(), LL_DMA_ClearFlag_FE4(), LL_DMA_ClearFlag_FE5() (+41 more)

### Community 26 - "stm32f4xx_hal_flash_ex.c"
Cohesion: 0.10
Nodes (45): HAL_StatusTypeDef, __weak, HAL_StatusTypeDef, FLASH_Erase_Sector(), FLASH_FlushCaches(), FLASH_MassErase(), FLASH_OB_BootConfig(), FLASH_OB_BOR_LevelConfig() (+37 more)

### Community 27 - "__DSB"
Cohesion: 0.10
Nodes (47): __DSB(), __ISB(), __NVIC_SystemReset(), __NVIC_SystemReset(), __NVIC_SystemReset(), __NVIC_SystemReset(), __NVIC_SystemReset(), __NVIC_SystemReset() (+39 more)

### Community 28 - "analyze_nl_stability.py"
Cohesion: 0.12
Nodes (43): as_float(), as_int(), build_fit_rows(), build_stability_rows(), csv_write(), DataPoint, describe(), dft_amplitude() (+35 more)

### Community 29 - "control_engine.c"
Cohesion: 0.08
Nodes (44): ControlA4Report_t, ControlA4Result_t, AbsI32ToU32(), ControlA5CaptureReport_t, ControlA5Result_t, MA600_Sample_t, ControlA4PhaseProgressRaw(), ControlA4PowerPpm() (+36 more)

### Community 30 - "stm32f4xx_hal_i2c.c"
Cohesion: 0.12
Nodes (45): HAL_DMA_Start_IT(), HAL_StatusTypeDef, I2C_HandleTypeDef, HAL_I2C_AddrCallback(), HAL_I2C_DeInit(), HAL_I2C_DisableListen_IT(), HAL_I2C_EnableListen_IT(), HAL_I2C_GetError() (+37 more)

### Community 31 - "core_armv8mml.h"
Cohesion: 0.13
Nodes (39): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_ClearTargetState(), NVIC_DecodePriority() (+31 more)

### Community 32 - "core_cm33.h"
Cohesion: 0.13
Nodes (39): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_ClearTargetState(), NVIC_DecodePriority() (+31 more)

### Community 33 - "CaptureSweep"
Cohesion: 0.10
Nodes (41): Motor_SetElectricalPos(), AbsI64ToU64(), AccumulateCounterDelta(), MA600_AcquisitionContext_t, MA600_PointSample_t, MA600_PointSamplerConfig_t, MA600_Result_t, MA600_Sample_t (+33 more)

### Community 34 - "stm32f4xx_ll_bus.h"
Cohesion: 0.10
Nodes (38): __STATIC_INLINE, LL_AHB1_GRP1_DisableClock(), LL_AHB1_GRP1_DisableClockLowPower(), LL_AHB1_GRP1_EnableClock(), LL_AHB1_GRP1_EnableClockLowPower(), LL_AHB1_GRP1_ForceReset(), LL_AHB1_GRP1_IsEnabledClock(), LL_AHB1_GRP1_ReleaseReset() (+30 more)

### Community 35 - "pvPortMalloc"
Cohesion: 0.16
Nodes (17): BlockLink_t, osMemoryPoolNew(), osThreadEnumerate(), osThreadGetCount(), osTimerNew(), prvHeapInit(), prvInsertBlockIntoFreeList(), pvPortMalloc() (+9 more)

### Community 36 - "timers.c"
Cohesion: 0.16
Nodes (31): BaseType_t, TaskHandle_t, TickType_t, TimerHandle_t, UBaseType_t, pcTimerGetName(), prvCheckForValidListAndQueue(), prvGetNextExpireTime() (+23 more)

### Community 37 - "stm32f4xx_hal.c"
Cohesion: 0.08
Nodes (18): TIM_HandleTypeDef, HAL_TIM_PeriodElapsedCallback(), HAL_StatusTypeDef, __weak, HAL_NVIC_SetPriorityGrouping(), HAL_SYSTICK_Config(), HAL_DeInit(), HAL_Delay() (+10 more)

### Community 38 - "HAL_GetTick"
Cohesion: 0.12
Nodes (27): HAL_GetTick(), FlagStatus, HAL_I2C_IsDeviceReady(), HAL_I2C_Master_Receive(), HAL_I2C_Master_Transmit(), HAL_I2C_Mem_Read(), HAL_I2C_Mem_Write(), HAL_I2C_Slave_Receive() (+19 more)

### Community 39 - "Thiết kế hệ thống firmware V2 — tái cấu trúc nhưng giữ nguyên thuật toán"
Cohesion: 0.04
Nodes (48): 10. Timing và deterministic behavior, 11. Configuration và protocol versioning, 12.1 Contract firmware, 12.2 Contract parser, 12. Logging và offline tools, 13. Chiến lược migration không đổi thuật toán, 14. Verification matrix, 15. Acceptance criteria cho kiến trúc mới (+40 more)

### Community 40 - "ma600_acquisition.c"
Cohesion: 0.13
Nodes (32): AbsDeltaI64(), MA600_PointSample_t, MA600_PointSamplerConfig_t, MA600_ReadMeta_t, MA600_Result_t, MA600_UnwrapContext_t, ComputeMadFilteredPointMean(), CycleReached() (+24 more)

### Community 41 - "core_armv8mbl.h"
Cohesion: 0.16
Nodes (32): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_ClearTargetState(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority() (+24 more)

### Community 42 - "core_cm23.h"
Cohesion: 0.16
Nodes (32): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_ClearTargetState(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority() (+24 more)

### Community 43 - "stream_buffer.c"
Cohesion: 0.16
Nodes (32): BaseType_t, TickType_t, UBaseType_t, prvBytesInBuffer(), prvInitialiseNewStreamBuffer(), prvReadBytesFromBuffer(), prvReadMessageFromBuffer(), prvWriteBytesToBuffer() (+24 more)

### Community 44 - "event_groups.c"
Cohesion: 0.13
Nodes (31): EventBits_t, EventGroupHandle_t, osEventFlagsClear(), osEventFlagsDelete(), osEventFlagsGet(), osEventFlagsNew(), osEventFlagsSet(), osEventFlagsWait() (+23 more)

### Community 45 - "stm32f4xx_ll_cortex.h"
Cohesion: 0.14
Nodes (26): __STATIC_INLINE, LL_CPUID_GetConstant(), LL_CPUID_GetImplementer(), LL_CPUID_GetParNo(), LL_CPUID_GetRevision(), LL_CPUID_GetVariant(), LL_HANDLER_DisableFault(), LL_HANDLER_EnableFault() (+18 more)

### Community 46 - "TIM_TypeDef"
Cohesion: 0.13
Nodes (28): TIM_TypeDef, HAL_TIM_ConfigClockSource(), HAL_TIM_ConfigOCrefClear(), HAL_TIM_IC_ConfigChannel(), HAL_TIM_OC_ConfigChannel(), HAL_TIM_OnePulse_ConfigChannel(), HAL_TIM_PWM_ConfigChannel(), HAL_TIM_SlaveConfigSynchro() (+20 more)

### Community 47 - "stm32f4xx_hal_msp.c"
Cohesion: 0.16
Nodes (26): ADC_HandleTypeDef, I2C_HandleTypeDef, SPI_HandleTypeDef, TIM_HandleTypeDef, UART_HandleTypeDef, HAL_ADC_MspDeInit(), HAL_ADC_MspInit(), HAL_I2C_MspDeInit() (+18 more)

### Community 48 - "croutine.c"
Cohesion: 0.16
Nodes (16): crCOROUTINE_CODE, BaseType_t, List_t, TickType_t, UBaseType_t, prvCheckDelayedList(), prvCheckPendingReadyList(), prvInitialiseCoRoutineLists() (+8 more)

### Community 49 - "cmsis_armcc.h"
Cohesion: 0.14
Nodes (22): __get_APSR(), __get_BASEPRI(), __get_CONTROL(), __get_FAULTMASK(), __get_FPSCR(), __get_IPSR(), __get_MSP(), __get_PRIMASK() (+14 more)

### Community 50 - "stm32f4xx_ll_gpio.h"
Cohesion: 0.21
Nodes (25): GPIO_TypeDef, __STATIC_INLINE, LL_GPIO_GetAFPin_0_7(), LL_GPIO_GetAFPin_8_15(), LL_GPIO_GetPinMode(), LL_GPIO_GetPinOutputType(), LL_GPIO_GetPinPull(), LL_GPIO_GetPinSpeed() (+17 more)

### Community 51 - "control_a5_capture.c"
Cohesion: 0.12
Nodes (29): ControlA5AbortRequestedFn_t, ControlA5Sample_t, AppEngine_Init(), ControlA5CaptureReport_t, ControlA5Result_t, Motor_ControllerState_t, ControlA5_AbsI32(), ControlA5_CaptureReportInit() (+21 more)

### Community 52 - "stm32f4xx_it.c"
Cohesion: 0.11
Nodes (17): ADC_IRQHandler(), DMA1_Stream1_IRQHandler(), DMA1_Stream3_IRQHandler(), DMA1_Stream5_IRQHandler(), DMA1_Stream6_IRQHandler(), DMA1_Stream7_IRQHandler(), DMA2_Stream0_IRQHandler(), DMA2_Stream2_IRQHandler() (+9 more)

### Community 53 - "core_cm3.h"
Cohesion: 0.20
Nodes (22): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ() (+14 more)

### Community 54 - "core_cm4.h"
Cohesion: 0.19
Nodes (23): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ() (+15 more)

### Community 55 - "core_sc300.h"
Cohesion: 0.20
Nodes (22): IRQn_Type, __STATIC_INLINE, ITM_CheckChar(), ITM_ReceiveChar(), ITM_SendChar(), __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ() (+14 more)

### Community 57 - "ADC_Common_TypeDef"
Cohesion: 0.09
Nodes (23): ADC_Common_TypeDef, LL_ADC_GetCommonClock(), LL_ADC_GetCommonPathInternalCh(), LL_ADC_GetMultiDMATransfer(), LL_ADC_GetMultimode(), LL_ADC_GetMultiTwoSamplingDelay(), LL_ADC_IsActiveFlag_MST_AWD1(), LL_ADC_IsActiveFlag_MST_EOCS() (+15 more)

### Community 58 - "stm32f4xx_ll_adc.c"
Cohesion: 0.14
Nodes (22): LL_ADC_Disable(), LL_ADC_INJ_SetSequencerLength(), LL_ADC_INJ_SetTriggerSource(), LL_ADC_IsEnabled(), LL_ADC_REG_SetSequencerLength(), LL_ADC_REG_SetTriggerSource(), LL_ADC_SetCommonClock(), ADC_TypeDef (+14 more)

### Community 59 - "TIM_Base_SetConfig"
Cohesion: 0.15
Nodes (19): MX_TIM2_Init(), HAL_TIMEx_HallSensor_Init(), HAL_TIM_Base_Init(), HAL_TIM_Base_MspInit(), HAL_TIM_Encoder_Init(), HAL_TIM_Encoder_MspInit(), HAL_TIM_IC_Init(), HAL_TIM_IC_MspInit() (+11 more)

### Community 60 - "__weak"
Cohesion: 0.14
Nodes (22): DMA_HandleTypeDef, __weak, HAL_TIM_ErrorCallback(), HAL_TIM_IC_CaptureCallback(), HAL_TIM_IC_CaptureHalfCpltCallback(), HAL_TIM_IRQHandler(), HAL_TIM_OC_DelayElapsedCallback(), HAL_TIM_PeriodElapsedCallback() (+14 more)

### Community 61 - "task.h"
Cohesion: 0.07
Nodes (18): eSleepModeStatus, SysTick_Handler(), BaseType_t, StackType_t, TaskFunction_t, TickType_t, prvPortStartFirstTask(), prvTaskExitError() (+10 more)

### Community 62 - "StartDefaultTask"
Cohesion: 0.17
Nodes (10): AppEngine_IsBusy(), AppEngine_ModeId(), AppEngine_ProfileFingerprint(), AppEngine_ProfileId(), AppEngine_SourceId(), ControlEngine_IsBusy(), MA600_AngleTransportName(), MA600_RawToDegrees() (+2 more)

### Community 63 - "mpu_armv8.h"
Cohesion: 0.24
Nodes (20): ARM_MPU_ClrRegion(), ARM_MPU_ClrRegion_NS(), ARM_MPU_ClrRegionEx(), ARM_MPU_Disable(), ARM_MPU_Disable_NS(), ARM_MPU_Enable(), ARM_MPU_Enable_NS(), ARM_MPU_Load() (+12 more)

### Community 64 - "Tăng K (NL_SAMPLES_PER_POINT) từ 20 lên 64, giữ N=256"
Cohesion: 0.04
Nodes (46): 1. `Core/Src/nonlinear_test.c` — tách ramp loop thành helper tự suy chiều, trả lỗi đúng cách, 1. Thêm chế độ thứ 3 vào bộ macro loại-trừ-lẫn-nhau (dòng ~245-263), 1. Thêm `Motor_Error_P2P_Deg`/`Motor_System_INL_Deg` vào RESULT, 2. Flag + hằng số mới, mặc định TẮT, 2. Thêm H4/H8, 2. Thêm `TimeSincePreviousRunMs`, 3. Comment làm rõ khái niệm (đầu file, cạnh comment lịch sử schema), 3. In vào dòng `META` (+38 more)

### Community 65 - "Motor_MoveToAngle"
Cohesion: 0.18
Nodes (17): MA600_UnwrappedRawToDegrees(), MA600_Result_t, Motor_Init(), Motor_MoveToAngle(), Motor_MoveToAngleWithPower(), MotorPwm_Disable(), MotorPwm_Init(), MotorPwm_PhaseValue() (+9 more)

### Community 66 - "stm32f4xx_hal_pwr.c"
Cohesion: 0.11
Nodes (5): __weak, HAL_PWR_ConfigPVD(), HAL_PWR_PVD_IRQHandler(), HAL_PWR_PVDCallback(), PWR_PVDTypeDef

### Community 68 - "__weak"
Cohesion: 0.22
Nodes (18): DMA_HandleTypeDef, __weak, HAL_I2C_AbortCpltCallback(), HAL_I2C_ER_IRQHandler(), HAL_I2C_ErrorCallback(), HAL_I2C_ListenCpltCallback(), HAL_I2C_MasterRxCpltCallback(), HAL_I2C_MemRxCpltCallback() (+10 more)

### Community 69 - "stm32f4xx_hal_rcc_ex.c"
Cohesion: 0.15
Nodes (15): HAL_StatusTypeDef, RCC_OscInitTypeDef, HAL_RCC_DeInit(), HAL_RCC_GetOscConfig(), HAL_RCC_OscConfig(), HAL_RCCEx_DisablePLLI2S(), HAL_RCCEx_DisablePLLSAI(), HAL_RCCEx_EnablePLLI2S() (+7 more)

### Community 70 - "analyze_control_a5.ps1"
Cohesion: 0.15
Nodes (8): Add-Reason(), Assert-FieldEquals(), Get-I64(), Get-LinearDiagnostics(), Get-PopulationStdDev(), Get-RequiredField(), Get-SingleRecord(), Get-U32()

### Community 71 - "control_a5_math.c"
Cohesion: 0.24
Nodes (17): ControlA5GoldenVector_t, ControlA5Stats_t, ControlA5Summary_t, AbsI32ToU32(), ControlA5_MathSelfTest(), ControlA5_MeanRelRawQ16(), ControlA5_RawWordsCrc32(), ControlA5_StatsFinalize() (+9 more)

### Community 72 - "stm32f4xx_ll_exti.h"
Cohesion: 0.21
Nodes (17): __STATIC_INLINE, LL_EXTI_ClearFlag_0_31(), LL_EXTI_DisableEvent_0_31(), LL_EXTI_DisableFallingTrig_0_31(), LL_EXTI_DisableIT_0_31(), LL_EXTI_DisableRisingTrig_0_31(), LL_EXTI_EnableEvent_0_31(), LL_EXTI_EnableFallingTrig_0_31() (+9 more)

### Community 73 - "plot_metric_trend.py"
Cohesion: 0.18
Nodes (16): expand_logfiles(), export_runs_csv(), launch_gui(), linear_fit(), load_runs(), main(), parse_kv(), Path (+8 more)

### Community 74 - "core_cm0.h"
Cohesion: 0.28
Nodes (16): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority(), __NVIC_GetEnableIRQ() (+8 more)

### Community 75 - "core_cm0plus.h"
Cohesion: 0.28
Nodes (16): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority(), __NVIC_GetEnableIRQ() (+8 more)

### Community 76 - "core_cm1.h"
Cohesion: 0.28
Nodes (16): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), NVIC_DecodePriority(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), NVIC_EncodePriority(), __NVIC_GetEnableIRQ() (+8 more)

### Community 77 - "core_sc000.h"
Cohesion: 0.29
Nodes (14): IRQn_Type, __STATIC_INLINE, __NVIC_ClearPendingIRQ(), __NVIC_DisableIRQ(), __NVIC_EnableIRQ(), __NVIC_GetEnableIRQ(), __NVIC_GetPendingIRQ(), __NVIC_GetPriority() (+6 more)

### Community 78 - "stm32f4xx_hal_cortex.c"
Cohesion: 0.16
Nodes (13): IRQn_Type, __weak, HAL_MPU_ConfigRegion(), HAL_MPU_Disable(), HAL_NVIC_ClearPendingIRQ(), HAL_NVIC_DisableIRQ(), HAL_NVIC_GetActive(), HAL_NVIC_GetPendingIRQ() (+5 more)

### Community 79 - "main"
Cohesion: 0.23
Nodes (16): TaskHandle_t, vApplicationMallocFailedHook(), vApplicationStackOverflowHook(), Error_Handler(), main(), MX_ADC1_Init(), MX_DMA_Init(), MX_GPIO_Init() (+8 more)

### Community 80 - "stm32f4xx_hal_dma.c"
Cohesion: 0.29
Nodes (15): DMA_HandleTypeDef, HAL_StatusTypeDef, DMA_CalcBaseAndBitshift(), DMA_CheckFifoParam(), DMA_SetConfig(), HAL_DMA_DeInit(), HAL_DMA_GetState(), HAL_DMA_Init() (+7 more)

### Community 81 - "stm32f4xx_hal_exti.c"
Cohesion: 0.29
Nodes (13): HAL_StatusTypeDef, HAL_EXTI_ClearConfigLine(), HAL_EXTI_ClearPending(), HAL_EXTI_GenerateSWI(), HAL_EXTI_GetConfigLine(), HAL_EXTI_GetHandle(), HAL_EXTI_GetPending(), HAL_EXTI_IRQHandler() (+5 more)

### Community 82 - "portmacro.h"
Cohesion: 0.21
Nodes (5): portFORCE_INLINE, ulPortRaiseBASEPRI(), vPortRaiseBASEPRI(), vPortSetBASEPRI(), xPortIsInsideInterrupt()

### Community 83 - "gremsyMotor.c"
Cohesion: 0.25
Nodes (6): gremsyMotorInit(), gremsyMotorMoveAngle(), gremsyMotorMovePos(), gremsyMotorMoveSpeed(), gremsyMotorSetPWM(), limit_integer()

### Community 84 - "analyze_scope_capture.py"
Cohesion: 0.26
Nodes (12): DataFrame, ndarray, detect_transitions(), format_si_time(), load_waveform(), main(), parse_header(), Path (+4 more)

### Community 85 - "HAL_I2C_EV_IRQHandler"
Cohesion: 0.19
Nodes (14): HAL_I2C_EV_IRQHandler(), HAL_I2C_MasterTxCpltCallback(), HAL_I2C_MemTxCpltCallback(), I2C_ConvertOtherXferOptions(), I2C_Master_ADD10(), I2C_Master_ADDR(), I2C_Master_SB(), I2C_MasterTransmit_BTF() (+6 more)

### Community 86 - "atomic.h"
Cohesion: 0.28
Nodes (12): Atomic_Add_u32(), Atomic_AND_u32(), Atomic_CompareAndSwap_u32(), Atomic_CompareAndSwapPointers_p32(), Atomic_Decrement_u32(), Atomic_Increment_u32(), Atomic_NAND_u32(), Atomic_OR_u32() (+4 more)

### Community 87 - "analyze_detrended_harmonics.py"
Cohesion: 0.26
Nodes (12): amp_phase(), analytic_detrend(), analyze_file(), dft(), main(), parse_log(), Return {sweepId: {'err': {pointIndex: errDeg}, 'res': {k: v}, 'closure': f}}., Single-bin DFT identical to firmware ComputeHarmonicFull (mean-removed). (+4 more)

### Community 88 - "analyze_nonlinear_logs.ps1"
Cohesion: 0.24
Nodes (7): Convert-ToNullableDouble(), Get-CircularDeltaRaw(), Get-CircularMeanRaw(), Get-Mean(), Get-NumberedRegexValues(), Get-StdDev(), Get-V32SectorGateResult()

### Community 89 - "analyze_b0b_transient.py"
Cohesion: 0.29
Nodes (10): analyze_a4(), analyze_b0b(), blend(), expected_cum(), main(), parse_a4_log(), parse_b0b_log(), Return list of per-tick dicts from CONTROL_A4_DATA (decimated 3:1, plus final… (+2 more)

### Community 90 - "mpu_armv7.h"
Cohesion: 0.36
Nodes (9): ARM_MPU_ClrRegion(), ARM_MPU_Disable(), ARM_MPU_Enable(), ARM_MPU_Load(), ARM_MPU_SetRegion(), ARM_MPU_SetRegionEx(), ARM_MPU_Region_t, __STATIC_INLINE (+1 more)

### Community 91 - "HAL_GPIO_WritePin"
Cohesion: 0.22
Nodes (12): gremsyMotorDisable(), gremsyMotorEnable(), GPIO_TypeDef, HAL_StatusTypeDef, __weak, HAL_GPIO_EXTI_Callback(), HAL_GPIO_EXTI_IRQHandler(), HAL_GPIO_LockPin() (+4 more)

### Community 95 - "cmsis_compiler.h"
Cohesion: 0.36
Nodes (7): packed, __PACKED_STRUCT, T_UINT16_READ(), T_UINT16_WRITE(), T_UINT32(), T_UINT32_READ(), T_UINT32_WRITE()

### Community 96 - "stm32f4xx_ll_utils.h"
Cohesion: 0.43
Nodes (7): __STATIC_INLINE, LL_GetFlashSize(), LL_GetPackageType(), LL_GetUID_Word0(), LL_GetUID_Word1(), LL_GetUID_Word2(), LL_InitTick()

### Community 97 - "stm32f4xx_hal_dma_ex.c"
Cohesion: 0.50
Nodes (7): DMA_HandleTypeDef, HAL_StatusTypeDef, DMA_MultiBufferSetConfig(), HAL_DMAEx_ChangeMemory(), HAL_DMAEx_MultiBufferStart(), HAL_DMAEx_MultiBufferStart_IT(), HAL_DMA_MemoryTypeDef

### Community 98 - "test_canonical_sampler_contract.ps1"
Cohesion: 0.39
Nodes (5): Canonical-MeanQ16(), Div-RoundNearestAwayFromZero(), Model-Schedule(), Signed-CycleDelta(), To-U32()

### Community 100 - "void"
Cohesion: 0.33
Nodes (5): void(), HAL_FLASHEx_DisableFlashSleepMode, HAL_FLASHEx_EnableFlashSleepMode, HAL_FLASHEx_StartFlashInterfaceClk, HAL_FLASHEx_StopFlashInterfaceClk

### Community 101 - "test_control_a5_math_contract.ps1"
Cohesion: 0.67
Nodes (5): Assert-True(), Assert-Vector(), Get-Crc32RawWords(), Get-Stats(), Get-WrapDelta()

### Community 102 - "__PACKED_STRUCT"
Cohesion: 0.40
Nodes (5): __PACKED_STRUCT, T_UINT16_READ(), T_UINT16_WRITE(), T_UINT32_READ(), T_UINT32_WRITE()

### Community 103 - "__PACKED_STRUCT"
Cohesion: 0.40
Nodes (5): __PACKED_STRUCT, T_UINT16_READ(), T_UINT16_WRITE(), T_UINT32_READ(), T_UINT32_WRITE()

### Community 104 - "HAL_I2CEx_ConfigAnalogFilter"
Cohesion: 0.60
Nodes (4): HAL_StatusTypeDef, I2C_HandleTypeDef, HAL_I2CEx_ConfigAnalogFilter(), HAL_I2CEx_ConfigDigitalFilter()

### Community 105 - "build_dual_image.ps1"
Cohesion: 0.80
Nodes (4): Assert-ChildPath(), Build-ModeImage(), Copy-ArtifactSet(), Invoke-BundledMake()

### Community 107 - "__STATIC_INLINE"
Cohesion: 0.05
Nodes (42): __STATIC_INLINE, LL_DBGMCU_APB1_GRP1_FreezePeriph(), LL_DBGMCU_APB1_GRP1_UnFreezePeriph(), LL_DBGMCU_DisableDBGSleepMode(), LL_DBGMCU_EnableDBGStandbyMode(), LL_DBGMCU_GetDeviceID(), LL_FLASH_DisableDataCacheReset(), LL_FLASH_DisableInstCache() (+34 more)

### Community 156 - "BatchLogRecorder"
Cohesion: 0.10
Nodes (22): AnalysisOutcome, analyze_saved_log(), BatchLogRecorder, CompletedCapture, _configuration_health(), parse_kv_record(), Path, Flush a partial UART line and preserve an interrupted active batch. (+14 more)

### Community 157 - "Plan A5 — MA600 static RawAngle stability"
Cohesion: 0.05
Nodes (39): 10. Host analyzer, 11. Implementation phases, 12. Failure decision tree, 13. Rollback and change discipline, 14. Final A5 deliverables, 1. Decision and objective, 2.1 Frozen A4B behavior, 2.2 Explicit non-goals (+31 more)

### Community 158 - "B0-B V3 — CW no-reversal approach plan"
Cohesion: 0.05
Nodes (37): 10. Điều kiện hoàn thành V3, 1. Mục tiêu, 2. Baseline đã có, 3.1. Nguyên lý, 3.2. Phần giữ nguyên tuyệt đối, 3.3. Feature isolation, 3. Maneuver V3, 4. Khóa quy ước dấu Closure và nguồn dữ liệu residual (+29 more)

### Community 159 - "MA600A Canonical Acquisition Improvement Plan"
Cohesion: 0.05
Nodes (37): Baseline and non-goals, Change-control rule, Gate, Gate, Gate, Gate, Gate, Gate (+29 more)

### Community 160 - "FlasherApp"
Cohesion: 0.13
Nodes (3): FlasherApp, Open the application UART directly without sending a bootloader GO command., Reconnect to ROM bootloader, send GO, then reopen as app UART. This button is…

### Community 161 - "analyze_nl_curve.py"
Cohesion: 0.16
Nodes (28): Namespace, build_analysis(), center_curve(), circular_shift(), extreme_rows(), find_best_circular_alignment(), fmt(), gate_rows() (+20 more)

### Community 162 - "Plan sửa trình tự alignment/enable cho Motor Control C0"
Cohesion: 0.07
Nodes (29): 10. Phase A4 — alignment + home, chưa chạy 1°, 11. Phase A5 — khôi phục C0 open-loop 1°, 12. File dự kiến thay đổi, 13. Contract/build gate mỗi commit, 14. Điều không được làm trong plan này, 15. Definition of Done, 1. Mục tiêu và phạm vi, 2. Evidence phần cứng đã có (+21 more)

### Community 163 - "Plan tái cấu trúc và tối ưu SPI acquisition có kiểm soát"
Cohesion: 0.07
Nodes (26): 10. Acceptance criteria, 11. Thứ tự triển khai đã chốt, 1.1 Quyết định triển khai, 1. Mục tiêu, 2. Các bất biến không được thay đổi, 3. Hiện trạng và khoảng trống cần xử lý, 4.1 Quy tắc phân lớp, 4. Kiến trúc acquisition mục tiêu (+18 more)

### Community 164 - "Thiết kế hệ thống dual-image tối ưu STM32F405"
Cohesion: 0.07
Nodes (26): 10. Performance contract, 11. Những tối ưu không làm ngay, 1. Nguồn sự thật và giới hạn phần cứng, 2.1 Clock và peripheral, 2.2 DMA map hiện tại, 2.3 Memory footprint Release hiện tại, 2. Audit firmware hiện tại, 3.1 Hai image, không phải hai nhánh runtime trong cùng test (+18 more)

### Community 165 - "STM32Bootloader"
Cohesion: 0.23
Nodes (7): BootloaderError, Collect bytes for a short window without blocking for the full port timeout., Synchronize with the ROM bootloader and tolerate stale UART traffic. Unlike the…, Legacy v1 synchronization after a DTR-generated reset. The original v1 cleared…, Write one block with retry and adaptive frame splitting. A NACK at varying…, Raised when the STM32 ROM bootloader rejects or times out., STM32Bootloader

### Community 166 - "Phase 3B0 - Closure and Measurement-Validity Design Review"
Cohesion: 0.08
Nodes (25): 1. Measurand and reference, 2. Command and control state, 3. Settle state, 4. Mechanical and magnetic state, 5. Thermal and electrical state, 6. Sensor and acquisition state, 7. Analysis and decision state, B0-A implementation checklist (+17 more)

### Community 167 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (24): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+16 more)

### Community 168 - "Tổng hợp phát hiện: yếu tố ảnh hưởng NL, so sánh JIG, và rà soát thuật toán PID/sensor (2026-07-27)"
Cohesion: 0.10
Nodes (20): 1. Yếu tố ảnh hưởng giá trị NL_RobustP2P_Deg, 2. Công thức đo torque/ma sát bằng MA600, 3. So sánh JIG4 vs JIG5, 4.1. Đính chính cặp jig đúng, 4.2. Kết quả ban đầu (n=4 sản phẩm, JIG1 test29 vs JIG4 test31), 4.3. Kiểm tra mở rộng — hạ thấp mức độ tin tưởng ban đầu, 4.4. Kiểm chứng phép sửa (before/after), 4.5. Khuyến nghị khắc phục thực sự (+12 more)

### Community 169 - "Nonlinear Algorithm Audit — toàn bộ finding, theo mục 6.1-6.13"
Cohesion: 0.10
Nodes (20): 6.10 — Phạm vi 360° và 370°, 6.11 — PID và scheduler, 6.12 — Signed/unsigned, 6.13 — Correction table, 6.1 — Reference và target, 6.2 — Pole-pair mapping, 6.3 — Full-scale và unwrap, 6.4 — Move-to-zero (+12 more)

### Community 170 - "analyze_nl_extreme_angles.py"
Cohesion: 0.22
Nodes (20): assign_jig_colors(), best_set_matching(), build_group_curve(), centered_rmse(), circular_distance(), compare_groups(), fmt_indices(), GroupCurve (+12 more)

### Community 171 - "Codex handoff: NL validity and cross-jig synchronization"
Cohesion: 0.10
Nodes (19): 10. Pilot gates for later confirmation, 11. Reproduction commands, 12. Important files, 1. Executive verdict, 2. What the firmware measures, 3. Current production/default source state, 4.1 Contract ID split, 4.2 Python analyzer (+11 more)

### Community 172 - "Plan thử nghiệm motor 7 cặp cực"
Cohesion: 0.11
Nodes (18): 1. Mục tiêu, 2.1. Giới hạn đã biết của bộ đổi pha PWM hiện tại, 2. Hình học bắt buộc, 3.1. Contract build cần bổ sung trước khi flash, 3. Cấu hình build thử nghiệm, 4. Trình tự thử nghiệm, 5. Decision tree, 6. File và bằng chứng phải lưu (+10 more)

### Community 173 - "GremsyQAApp"
Cohesion: 0.22
Nodes (3): GremsyQAApp, Hiển thị dialog yêu cầu nhập các trường còn thiếu. missing_fields: list các tên…, Kiểm tra các trường bắt buộc trong row_data: 'Checked By', 'Product Detail',…

### Community 174 - "Codex handoff — Motion Control V2, lưới 1° và SPI1 DMA"
Cohesion: 0.12
Nodes (16): 1. Trạng thái bàn giao, 2. Measurement contract đang có hiệu lực, 3.1 Lưới đo 1°, 3.2 SPI1 DMA cho MA600A, 3.3 Motion profile cho sweep, 3.4 Điểm 0 và hướng tiếp cận, 3.5 Home controller, 3.6 Logging và observability (+8 more)

### Community 175 - "3. Kế hoạch hành động — theo thứ tự ưu tiên"
Cohesion: 0.12
Nodes (15): 1.1. Vì sao không có "bias JIG4" ổn định, 1. Tình trạng hiện tại — đã biết / đã loại trừ / còn mở, 2. Vấn đề hệ quy chiếu pha harmonic — phải sửa trước khi diễn giải bất kỳ số H1/H2 nào, 3. Kế hoạch hành động — theo thứ tự ưu tiên, 4. Hành động khắc phục, theo kết quả từng nhánh, 5. Bảng công cụ MATLAB dùng cho từng bước, 6. Tiêu chí coi là "đã tìm ra root cause", Bước 0 — Khoá định danh & điều kiện đo (bắt buộc TRƯỚC mọi thực nghiệm nhân quả) (+7 more)

### Community 176 - "FirmwareSegment"
Cohesion: 0.23
Nodes (7): RuntimeError, default_log_directory(), FirmwareLoader, FirmwareSegment, Path, Return a writable, predictable log folder in source and packaged modes., Snapshot Tk options, then save/analyze without blocking the GUI.

### Community 177 - "3. Call graph cho 9 luồng yêu cầu"
Cohesion: 0.13
Nodes (14): 1. Data-flow tổng thể, 2. Bảng chi tiết từng block, 3.1 Start nonlinear test, 3.2 Move-to-zero, 3.3 Move tới từng test point (ramp), 3.4 Đọc encoder, 3.5 Unwrap, 3.6 Average sample (+6 more)

### Community 178 - "SweepReport"
Cohesion: 0.23
Nodes (15): build_report(), cross_jig_delta(), group_key(), GroupSummary, infer_run_order(), main(), mean_sd_cv(), print_text_report() (+7 more)

### Community 179 - "Extreme points on each batch-mean curve"
Cohesion: 0.15
Nodes (12): Extreme points on each batch-mean curve, NL extreme-angle and cross-jig curve analysis, p02 / JIG1, p02 / JIG4, p03 / JIG1, p03 / JIG4, p05 / JIG1, p05 / JIG4 (+4 more)

### Community 180 - "End-of-Shaft Mounting Verification Test Plan (MA600A)"
Cohesion: 0.15
Nodes (12): Datasheet context (not firmware acceptance limits), End-of-Shaft Mounting Verification Test Plan (MA600A), Goal, Magnetic field strength, Mechanical (from the MA600A datasheet, "Sensor (Magnet Mounting)" /, Parse Raw Logs, Part A -- Mechanical checklist (do this before powering on), Part B -- Firmware angle sweep (+4 more)

### Community 181 - "STM32 UART Flasher"
Cohesion: 0.15
Nodes (12): BIN, Chức năng, Cài đặt và chạy, ELF/AXF, File firmware, HEX, Kết nối STM32F405, Lưu ý an toàn (+4 more)

### Community 182 - "Plan A3 — Alignment bằng phase trajectory (rotating capture + drag)"
Cohesion: 0.17
Nodes (11): Bối cảnh, Decision tree, Evidence budget (ràng buộc CCM 64 KB), Guard — phải nới có chủ đích so với A2F (ghi rõ lý do, không im lặng), Ngoài phạm vi (giữ kỷ luật một-biến), Nguyên lý A3 và vì sao nó né được bế tắc stick-slip, Phân tích & acceptance, Plan A3 — Alignment bằng phase trajectory (rotating capture + drag) (+3 more)

### Community 183 - "Kết quả A3 — sub-mechanism PASS, arbitrary-start alignment FAIL; đóng A3, chuyển A4"
Cohesion: 0.17
Nodes (11): 1. Kết quả theo run, 2. Vật lý khớp dự đoán từng con số, 3. Con số vàng: `ElectricalOffsetRaw = 6742 ± 81 raw`, 4. Hai run STEP_LIMIT: lỗ hổng thiết kế đã lộ đúng chỗ — và gate đã cứu đúng lúc, 5. Đối chiếu acceptance đã đặt trước (plan A3), 6. A4 — ENCODER_SEEDED_DRAG (spec đã chốt sau review), Acceptance A4, Dataset và integrity (+3 more)

### Community 184 - "Plan MATLAB — phân tích offline A2/A2B/A2C power-envelope"
Cohesion: 0.17
Nodes (11): Kiến trúc dữ liệu, Mục tiêu, Phase M0 — xác nhận môi trường, Phase M1 — contract CSV và units, Phase M2 — MATLAB analysis package, Phase M3 — thuật toán quyết định power-envelope, Phase M4 — cross-check và regression, Phase M5 — quy trình hardware cho A2C (+3 more)

### Community 185 - "2. Việc bạn cần làm trên phần cứng"
Cohesion: 0.17
Nodes (11): 1. Cơ chế firmware (đã implement, mặc định TẮT), 2. Việc bạn cần làm trên phần cứng, 3.1. Kiểm tra độ chính xác pre-position, 3.2. Fit mô hình sector-response cho ĐÚNG 1 motor này, 3. Phân tích kết quả (đã chuẩn bị sẵn, chạy được ngay khi có log), 4. Đề xuất dài hạn (chưa bật, cần bạn quyết định thời điểm), Bước 1 — Build firmware với cờ bật, Bước 2 — Chọn 1 motor cố định, KHÔNG tháo lắp giữa các batch (+3 more)

### Community 186 - "A5 implementation and validation checklist"
Cohesion: 0.18
Nodes (11): A5.0 — Freeze specification and rollback, A5.1 — Data model and pure math, A5.2 — Capture integration, A5.3 — Schema and host analyzer, A5.4 — Build and isolation, A5.5 — Hardware pilot, A5.6 — Confirmation and lock, A5 implementation and validation checklist (+3 more)

### Community 187 - "Kết quả A5 — MA600 RawAngle static stability: đã khóa"
Cohesion: 0.18
Nodes (10): Cold vs warm — quan sát nhẹ, không phải kết luận cứng, Gate cho tham số MA600 tiếp theo (A5B), Giới hạn quan sát được (không phải ngưỡng pass/fail sản phẩm), Hướng đi tiếp theo (không phải quyết định của tôi — cần bạn chọn), Kết luận quyết định: sensor không còn là nút thắt, Kết quả A5 — MA600 RawAngle static stability: đã khóa, PWM-phase, phân bố, drift dài hạn — sạch, Trạng thái (+2 more)

### Community 188 - "Cross-jig measurement analysis — P03/P05 × JIG1/JIG3"
Cohesion: 0.18
Nodes (10): 0. Xác nhận tính hợp lệ dữ liệu đầu vào (trả lời trực tiếp ALG-018), 1. Bảng per-sweep (Run 1 = precondition), 2. Mean/SD/CV theo run 2-3 (conditioned), theo Motor×Jig, 3. Phân tích harmonic — bằng chứng phân tách motor-signature vs jig-signature, 4. Vì sao P2P khác nhiều dù A36 gần nhau, 5. Delta P03 khác delta P05 → có Product × Jig interaction thật không?, 6. Closure — phát hiện quan trọng nhất của phần này, 7. Có thể đồng bộ hai jig bằng một scalar offset không? (+2 more)

### Community 189 - "Thông số đo và kiểm tra (Measured & Checked Parameters)"
Cohesion: 0.18
Nodes (11): A4 / A4B — Kéo lệch có mồi từ encoder (encoder-seeded drag-alignment), B0-B — Tiếp cận điểm đóng (backoff/forward), creep, feedforward, soft-start, Chỉ mục file/dòng tham chiếu, Hằng số cấu hình, Hằng số cấu hình, Ngưỡng pass/fail, Phân tích độ lặp lại / xu hướng NL (`tools/analyze_nl_stability.py`), Self-test (+3 more)

### Community 190 - "Motion Control V2 — implementation and hardware qualification"
Cohesion: 0.18
Nodes (10): Acceptance gates, Home controller, Implemented profiles, Motion Control V2 — implementation and hardware qualification, Objective, Point-zero alignment, Qualification sequence, Rollback and tuning order (+2 more)

### Community 191 - "Sweep"
Cohesion: 0.18
Nodes (4): Returns the analysis coordinate for one point. Legacy fixed-step logs use…, True only when META, END, and declared batch-role semantics agree. Deliberately…, Everything collected under one (TestID, SweepID)., Sweep

### Community 192 - "NL pointwise-curve assessment — p05"
Cohesion: 0.20
Nodes (9): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p05, Selected harmonic fingerprint (+1 more)

### Community 193 - "NL pointwise-curve assessment — p03"
Cohesion: 0.20
Nodes (9): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p03, Selected harmonic fingerprint (+1 more)

### Community 194 - "NL pointwise-curve assessment — p05"
Cohesion: 0.20
Nodes (9): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p05, Selected harmonic fingerprint (+1 more)

### Community 195 - "NL pointwise-curve assessment — p03"
Cohesion: 0.20
Nodes (9): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p03, Selected harmonic fingerprint (+1 more)

### Community 196 - "NL pointwise-curve assessment — p03"
Cohesion: 0.20
Nodes (9): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p03, Selected harmonic fingerprint (+1 more)

### Community 197 - "NL pointwise-curve assessment — p03"
Cohesion: 0.20
Nodes (9): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p03, Selected harmonic fingerprint (+1 more)

### Community 198 - "NL pointwise-curve assessment — p05"
Cohesion: 0.20
Nodes (9): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p05, Selected harmonic fingerprint (+1 more)

### Community 199 - "NL pointwise-curve assessment — p05"
Cohesion: 0.20
Nodes (9): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p05, Selected harmonic fingerprint (+1 more)

### Community 200 - "Control A2F — fixed-phase power-envelope, P09/H500"
Cohesion: 0.20
Nodes (9): Build và artifact, Control A2F — fixed-phase power-envelope, P09/H500, Gate trước A3/A4, Kết quả: fit mô hình phục hồi gộp toàn bộ dữ liệu an toàn (P06–P10), Log mong đợi, Mục tiêu, Quyết định: dừng power-envelope tại P09, Safety envelope (+1 more)

### Community 201 - "Architecture Migration Hardware Validation"
Cohesion: 0.20
Nodes (9): Architecture Migration Hardware Validation, Before testing, Canonical jig identity, Endpoint and repeatability gate, Failure behavior, Healthy run, Phase-1 configuration audit, Phase-3B0-A passive hold run checklist (+1 more)

### Community 202 - "Nonlinear Log Schema v6 Contract"
Cohesion: 0.20
Nodes (9): Acquisition observability, Canonical DATA contract, Compatibility tests, Identity precedence, Nonlinear Log Schema v6 Contract, Record sequence, Required META fields, Session and batch framing (+1 more)

### Community 203 - "1. Vì sao phải thay đổi cách tính nonlinear hiện tại (legacy, schema v5)"
Cohesion: 0.20
Nodes (9): 1.1 — Có bằng chứng thật: một run tracking-lost từng bị báo "Motor OK", 1.2 — Lỗi kiến trúc lấy mẫu: một điểm dữ liệu đến từ hai lần đọc khác thời điểm, 1.3 — Settle chỉ kiểm tra "đã dừng", chưa kiểm tra "dừng đúng vị trí", 1.4 — Nhầm lẫn giữa "nonlinear của cả hệ thống" và "INL của riêng sensor", 1. Vì sao phải thay đổi cách tính nonlinear hiện tại (legacy, schema v5), 2. Cách xác định giá trị nonlinear "đúng" — hợp đồng `CANONICAL_Q16_V1`, 3. Tình hình triển khai hiện tại (theo đúng tài liệu trong `docs/`, không suy đoán), Việc đang cần làm ngay tiếp theo (+1 more)

### Community 204 - "Nonlinear Metric Definition Contract v1"
Cohesion: 0.20
Nodes (10): Acquisition-loop boundary, Analysis index sets, Canonical point mean, Canonical relative error, Closure, Integer and rounding rules, Nonlinear Metric Definition Contract v1, Official validity (+2 more)

### Community 205 - "Phase 2B Shadow Checklist"
Cohesion: 0.20
Nodes (9): Chuẩn bị firmware theo từng motor, Lệnh kiểm tra host, Matrix Phase 2B tối thiểu, Operator decision override - 2026-07-14, Phase 2B Shadow Checklist, Preflight trên mỗi JIG, Điều kiện pass cho từng sweep, Đánh giá sau khi đủ 12 sweep (+1 more)

### Community 206 - "NL pointwise-curve assessment — p03"
Cohesion: 0.22
Nodes (8): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p03, Selected harmonic fingerprint

### Community 207 - "NL pointwise-curve assessment — p05"
Cohesion: 0.22
Nodes (8): A-B-A effects, Batch summary, Data health, Files produced, Frozen pilot gates, Interpretation boundary, NL pointwise-curve assessment — p05, Selected harmonic fingerprint

### Community 208 - "CONTROL A5 activation build (A5.4)"
Cohesion: 0.22
Nodes (8): A5.5 hardware pilot, round 1 (`A5 test 1.txt` .. `A5 test 5.txt`), CONTROL A5 activation build (A5.4), Identity, Rollback, SHA-256, Verification performed (software/build only), What changed vs the A4B rollback baseline, What this build has NOT proven yet

### Community 209 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 210 - "B0-B — kết quả closure và approach (test 18–23), tính độc lập bằng MATLAB"
Cohesion: 0.22
Nodes (8): 1. Soft-start (test 18) — delay=4ms tệ hơn baseline, không nên dùng, 2. Creep correction (test 19, A→B→A2) — hiệu quả rõ rệt, 3. Adaptive precondition (test 20, A/A2/B) — đúng thiết kế, có bug log, 4. NL closure (test 21/22, sản phẩm P03) — KHÔNG đạt 0.20°, 5. NL closure (test 23, đa sản phẩm) — P02/P04/P05/P06 đạt, **P07 không đạt**, 6. Tổng kết claim "toàn bộ đều dưới 0,20", B0-B — kết quả closure và approach (test 18–23), tính độc lập bằng MATLAB, Công cụ

### Community 211 - "Kết quả A2F — P09 hoàn tất power envelope, đóng sổ fixed-phase"
Cohesion: 0.22
Nodes (8): Ba sự thật quyết định, Bản đồ power envelope cuối cùng, Dataset và integrity, Kết quả A2F — P09 hoàn tất power envelope, đóng sổ fixed-phase, Kết quả theo run, Quyết định, Tái lập phân tích, Định hướng thiết kế A3 (phase trajectory)

### Community 212 - "A3 — Đề xuất struct/hằng số cho Codex review"
Cohesion: 0.22
Nodes (8): A3 — Đề xuất struct/hằng số cho Codex review, Chữ ký helper (private), Câu hỏi mở cho Codex (điểm cần quyết khi review), Dòng log mới (đổi record name để parser không lẫn với A2), Enum kết quả và pha, Evidence record (CCM, decimated), Khối hằng số + khóa profile, Report

### Community 213 - "Control C0 — hardware test 1°"
Cohesion: 0.22
Nodes (8): Build, Chuẩn bị an toàn, Control C0 — hardware test 1°, Log và gate, Mục tiêu, Profile đã khóa, Trình tự test, Điều kiện mở phase tiếp theo

### Community 214 - "Đánh giá cách đọc dữ liệu MA600A trong firmware Gremsy cũ (gremsyEncoder.c / gremsyMotor.c / gremsyTaskManager.c / gremsyAnalog.c)"
Cohesion: 0.22
Nodes (8): 1. Cấu hình `FW=12` triệt tiêu bandwidth — sai mục đích ngay từ thiết kế, 2. Đọc "speed" bằng giao dịch SPI sai kích thước — dữ liệu là rác, 3. Không có lớp kiểm tra nào — mọi lỗi truyền/ghi dữ liệu đều im lặng, 4. Phương pháp lấy mẫu cho bài "nonlinear" tự tạo thêm nhiễu/trễ, Kết luận, Phạm vi, Tóm tắt, Đánh giá cách đọc dữ liệu MA600A trong firmware Gremsy cũ (gremsyEncoder.c / gremsyMotor.c / gremsyTaskManager.c / gremsyAnalog.c)

### Community 215 - "Nonlinear Metric Definition Contract v2"
Cohesion: 0.22
Nodes (9): Analysis and closure index sets, Canonical relative error, Compatibility and the historical V1 mislabel, Integer and rounding rules, Measurand boundary, Nonlinear Metric Definition Contract v2, One-degree target grid, Selected-order DFT (+1 more)

### Community 216 - "Kế hoạch triển khai dual-image trên STM32F405"
Cohesion: 0.22
Nodes (8): 12. Phase M1 — measurement timing optimization độc lập, 13. Phase O1 — tối ưu CPU sau profiling, 16. Thứ tự commit đề xuất, 17. Definition of done, 1. Nguyên tắc thực hiện, 2. Deliverable cuối, Kế hoạch triển khai dual-image trên STM32F405, Trạng thái triển khai (2026-07-16)

### Community 217 - "Serial"
Cohesion: 0.22
Nodes (3): Event, Serial, Open COM exactly like v1 so the DTR transition can reset the board. In v1,…

### Community 218 - "Extreme points on each batch-mean curve"
Cohesion: 0.25
Nodes (7): Extreme points on each batch-mean curve, NL extreme-angle and cross-jig curve analysis, P03 / JIG1, P03 / JIG4, P03 / JIG5, P03 / JIG6, Same-motor cross-jig comparison

### Community 219 - "Extreme points on each batch-mean curve"
Cohesion: 0.25
Nodes (7): Extreme points on each batch-mean curve, NL extreme-angle and cross-jig curve analysis, P03 / JIG1-A1, P03 / JIG1-A2, P03 / JIG4-B, P03 / JIG4-test-1, Same-motor cross-jig comparison

### Community 220 - "Extreme points on each batch-mean curve"
Cohesion: 0.25
Nodes (7): Extreme points on each batch-mean curve, NL extreme-angle and cross-jig curve analysis, p03 / JIG1, p03 / JIG4, p05 / JIG1, p05 / JIG4, Same-motor cross-jig comparison

### Community 221 - "MoveToZeroAndCheckDirection"
Cohesion: 0.39
Nodes (8): Motor_GetCommandedPos(), Motor_ControllerState_t, ControllerStateIsReset(), FinishMoveToZeroObservation(), MoveToZeroAndCheckDirection(), RecordControllerObservation(), NlZeroObservation_t, NlZeroResult_t

### Community 222 - "Architecture Migration Baseline"
Cohesion: 0.25
Nodes (7): Architecture Migration Baseline, Build, Chosen Architecture, Deferred Decisions, Hardware Log, Measurement Policy, Negative regression fixture

### Community 223 - "Baseline manifest — Motion V2 + SPI DMA trước dual-image"
Cohesion: 0.25
Nodes (7): Artifact identity, Baseline manifest — Motion V2 + SPI DMA trước dual-image, Measurement invariants của rollback point, Rollback procedure, Size baseline, Source và toolchain, Verification

### Community 224 - "NL pointwise-curve analysis tool"
Cohesion: 0.25
Nodes (7): Command, Default pilot gates, Measurement contract, NL pointwise-curve analysis tool, Outputs, Purpose, Regression

### Community 225 - "Phase 3A - Continuous Motion, Settle, and Motor Pole Checklist"
Cohesion: 0.25
Nodes (7): Comparison matrix, Configuration decision, Hardware evidence and corrected gate status, Hardware gate for each new sweep, Host verification, Phase 3A - Continuous Motion, Settle, and Motor Pole Checklist, Software checklist

### Community 226 - "Extreme points on each batch-mean curve"
Cohesion: 0.29
Nodes (6): Extreme points on each batch-mean curve, NL extreme-angle and cross-jig curve analysis, P03 / JIG4-B, P03 / JIG4-test-1, P03 / S1-P03-JIG1, Same-motor cross-jig comparison

### Community 227 - "Extreme points on each batch-mean curve"
Cohesion: 0.29
Nodes (6): Extreme points on each batch-mean curve, NL extreme-angle and cross-jig curve analysis, P05 / JIG4-B, P05 / JIG4-test-1, P05 / S1-P05-JIG1, Same-motor cross-jig comparison

### Community 228 - "Extreme points on each batch-mean curve"
Cohesion: 0.29
Nodes (6): Extreme points on each batch-mean curve, NL extreme-angle and cross-jig curve analysis, P03 / 01, P03 / 02, P03 / 03, Same-motor cross-jig comparison

### Community 229 - "Extreme points on each batch-mean curve"
Cohesion: 0.29
Nodes (6): Extreme points on each batch-mean curve, NL extreme-angle and cross-jig curve analysis, P05 / 01, P05 / 02, P05 / 03, Same-motor cross-jig comparison

### Community 230 - "B0-B soft-start — Phase A result (log mining) và thiết kế Phase B"
Cohesion: 0.29
Nodes (6): B0-B soft-start — Phase A result (log mining) và thiết kế Phase B, Build đã lưu (A→B→A trên jig thật), Bối cảnh, Không làm trong lần này, Phase A — mine log đã có, không chạy hardware mới, Phase B — thiết kế đã triển khai

### Community 231 - "MATLAB result — A2 đến A2E power-envelope"
Cohesion: 0.29
Nodes (6): Dataset và integrity, Kết luận thuật toán, Kết quả theo profile, MATLAB result — A2 đến A2E power-envelope, Output, Settle sau chuyển động

### Community 232 - "A2 — Quét xoay vòng (rotating-capture), phi tuyến & sóng hài"
Cohesion: 0.29
Nodes (7): A2 — Quét xoay vòng (rotating-capture), phi tuyến & sóng hài, Chỉ số hậu vòng (post-turn repeat, điểm 361–370) — *đề xuất bổ sung, chưa có trong firmware*, Cổng hợp lệ chính thức (Official validity gate), Ngưỡng pass/fail (limits), Phân tích tương quan (n=30, Test 21) — đã hiệu chỉnh sau phản biện, Thông số tính toán (derived), Thông số đo (per-point)

### Community 233 - "Preconditioned 10-run repeatability experiment"
Cohesion: 0.29
Nodes (6): Analysis gate, Final artifact, Fixed protocol, Hardware run checklist, Preconditioned 10-run repeatability experiment, Software checklist

### Community 234 - "Extreme points on each batch-mean curve"
Cohesion: 0.33
Nodes (5): Extreme points on each batch-mean curve, NL extreme-angle and cross-jig curve analysis, p03 / JIG1, p05 / JIG1, Same-motor cross-jig comparison

### Community 235 - "CONTROL A4B rollback baseline"
Cohesion: 0.33
Nodes (5): CONTROL A4B rollback baseline, Hardware evidence, Identity, Rollback procedure, SHA-256

### Community 236 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 237 - "Phase 3B0-R - Controller-State Synchronization Checklist"
Cohesion: 0.33
Nodes (5): Decision rules, Fixed experiment contract, Phase 3B0-R - Controller-State Synchronization Checklist, Required hardware A/B data, Software checklist

### Community 238 - "Test 33: NL extreme-angle cross-jig assessment"
Cohesion: 0.33
Nodes (5): Coordinate limitation, Interpretation, Next decision experiment, Results, Test 33: NL extreme-angle cross-jig assessment

### Community 239 - "Chốt phương thức đo B0-B bằng MATLAB"
Cohesion: 0.40
Nodes (4): Chốt phương thức đo B0-B bằng MATLAB, Các gate quan trọng, Kết luận, Phạm vi kết luận

### Community 240 - "B0-B test 21 A-B-A assessment"
Cohesion: 0.40
Nodes (4): A-B-A means, B0-B test 21 A-B-A assessment, Decision table, Feedforward calibration result

### Community 241 - "Phase 2A Canonical Sampler Status"
Cohesion: 0.40
Nodes (4): Implemented contract, Phase 2A Canonical Sampler Status, Phase-2A gate evidence, Tests

### Community 242 - "3. Phase P0 — đóng băng baseline (hoàn tất)"
Cohesion: 0.40
Nodes (5): 3. Phase P0 — đóng băng baseline (hoàn tất), Công việc, Deliverable, Gate, Rollback

### Community 243 - "5. Phase P2 — memory map và RTOS observability"
Cohesion: 0.40
Nodes (5): 5. Phase P2 — memory map và RTOS observability, Budget đề xuất sau profiling, Contract test, Công việc, Hardware gate

### Community 244 - "7. Phase C0 — Control image quan sát plant, chưa đóng loop (source/build gate hoàn tất)"
Cohesion: 0.40
Nodes (5): 7. Phase C0 — Control image quan sát plant, chưa đóng loop (source/build gate hoàn tất), Evidence, Output, Safety gate, Workflow

### Community 245 - "jigmotor"
Cohesion: 0.40
Nodes (4): Architecture, Building from the command line, jigmotor, STM32CubeIDE

### Community 246 - "Chốt phương thức đo B0-B bằng MATLAB"
Cohesion: 0.50
Nodes (3): Chốt phương thức đo B0-B bằng MATLAB, Kết luận, Phạm vi kết luận

### Community 247 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 248 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 249 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 251 - "A5 — Ổn định góc thô tĩnh (MA600 static RawAngle stability)"
Cohesion: 0.50
Nodes (4): A5 — Ổn định góc thô tĩnh (MA600 static RawAngle stability), Dải pass đã chốt (`docs/control-a5-checklist.md`, profile `CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1`, trạng thái A5.6 COMPLETE), Hằng số cấu hình, Thông số tính toán

### Community 252 - "15. Phase Q — qualification cuối"
Cohesion: 0.50
Nodes (4): 15. Phase Q — qualification cuối, Control image, Measurement image, Release gate

### Community 253 - "4. Phase P1 — build identity và compile-time isolation (hoàn tất source/build gate)"
Cohesion: 0.50
Nodes (4): 4. Phase P1 — build identity và compile-time isolation (hoàn tất source/build gate), Contract test, Công việc, Gate

### Community 254 - "8. Phase C1 — hardware-timed control pipeline"
Cohesion: 0.50
Nodes (4): 8. Phase C1 — hardware-timed control pipeline, Công việc, Gate, Timing budget 1 ms

### Community 255 - "9. Phase C2 — controller P-only"
Cohesion: 0.50
Nodes (4): 9. Phase C2 — controller P-only, Công việc, Gate, Theo dõi

### Community 259 - "A3 — Căn chỉnh quỹ đạo pha (rotating-capture)"
Cohesion: 0.67
Nodes (3): A3 — Căn chỉnh quỹ đạo pha (rotating-capture), Ngưỡng pass/fail, Thông số đo

### Community 260 - "10. Phase C3 — damping và static-error removal"
Cohesion: 0.67
Nodes (3): 10. Phase C3 — damping và static-error removal, Acceptance hai cấp, Thứ tự

### Community 261 - "11. Phase M0 — khóa Measurement image"
Cohesion: 0.67
Nodes (3): 11. Phase M0 — khóa Measurement image, Công việc, Numeric gate

### Community 262 - "14. Phase S1 — safety và watchdog"
Cohesion: 0.67
Nodes (3): 14. Phase S1 — safety và watchdog, Công việc, Gate

### Community 263 - "6. Phase P3 — shared platform và ownership"
Cohesion: 0.67
Nodes (3): 6. Phase P3 — shared platform và ownership, Công việc, Gate

## Knowledge Gaps
- **820 isolated node(s):** `v`, `Usage`, `What graphify is for`, `Step 0 - GitHub repos and multi-path merge (only if a URL or several paths)`, `Step 1 - Ensure graphify is installed` (+815 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `HAL_GetTick()` connect `HAL_GetTick` to `CaptureSweep`, `stm32f4xx_hal.c`, `stm32f4xx_hal_uart.c`, `stm32f4xx_hal_rcc_ex.c`, `stm32f4xx_hal_spi.c`, `stm32f4xx_hal_dma.c`, `control_engine.c`, `control_a5_capture.c`, `stm32f4xx_hal_adc.c`, `nonlinear_test.c`, `stm32f4xx_hal_flash_ex.c`, `MoveToZeroAndCheckDirection`, `stm32f4xx_hal_i2c.c`?**
  _High betweenness centrality (0.072) - this node is a cross-community bridge._
- **Why does `LL_MPU_Enable()` connect `stm32f4xx_ll_cortex.h` to `__DSB`?**
  _High betweenness centrality (0.046) - this node is a cross-community bridge._
- **Why does `osDelay()` connect `CaptureSweep` to `tasks.c`, `cmsis_os2.c`, `MoveToZeroAndCheckDirection`, `StartDefaultTask`?**
  _High betweenness centrality (0.037) - this node is a cross-community bridge._
- **What connects `v`, `Usage`, `What graphify is for` to the rest of the system?**
  _820 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `stm32f4xx_ll_usart.h` be split into smaller, more focused modules?**
  _Cohesion score 0.043151567196221555 - nodes in this community are weakly interconnected._
- **Should `cmsis_gcc.h` be split into smaller, more focused modules?**
  _Cohesion score 0.02962630456738862 - nodes in this community are weakly interconnected._
- **Should `stm32f4xx_ll_i2c.h` be split into smaller, more focused modules?**
  _Cohesion score 0.052606177606177605 - nodes in this community are weakly interconnected._