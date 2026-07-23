# Baseline manifest — Motion V2 + SPI DMA trước dual-image

Baseline này là rollback point P0 trước khi tách `MOTOR_CONTROL` và
`MEASUREMENT` thành hai firmware image.

## Source và toolchain

- Git branch: `codex/motion-control-v2-dma`
- Git commit: `07188e5ff0a38a0cb1b51222d090abed9d3fde37`
- Target: `STM32F405RGTx`, LQFP64
- Toolchain: GNU Tools for STM32 14.3.rel1, GCC 14.3.1
- Configuration: Release, `-Os`, hard-float `fpv4-sp-d16`
- Linker: `STM32F405RGTX_FLASH.ld`
- App behavior: measurement firmware trước khi có compile-time dual-image
- Motion profile: `SCURVE40_ABSOLUTE_TICK_V2`
- Home controller: `WRAPPED_PID_SLEW_V2`
- MA600 angle transport: `SPI_DMA_BLOCKING_WRAPPER_V1`

## Artifact identity

| Artifact | SHA-256 |
| --- | --- |
| `Release/jigmotor.elf` | `92DEA893990919912122BDF6AC19C90CED545DA27C05BD59B53CC5584B73847F` |
| `Release/jigmotor.hex` | `147F6370E93E806B0D92B5C2F8B2386B8ADDBE3374B38693DA3C2D8672EE8825` |

Build timestamp strings có thể làm hash thay đổi khi clean rebuild. Khi đó phải
so sánh source commit, compiler flags, section/map và runtime profile identity;
không được tự động coi hash khác là algorithm khác hoặc tương đương.

## Size baseline

```text
text=77836 data=96 bss=138936 dec=216868
```

Section detail:

| Section | Bytes |
| --- | ---: |
| `.isr_vector` | 392 |
| `.text` | 62,580 |
| `.rodata` | 14,848 |
| `.data` | 96 |
| `.bss` | 124,372 |
| `.ccmram_bss` | 13,024 |
| `._user_heap_stack` | 1,540 |

Largest RAM allocations:

| Symbol | Bytes | Region |
| --- | ---: | --- |
| `ucHeap` | 102,400 | main SRAM |
| `nlShadowPointStorage` | 13,024 | CCM |
| `nlCaptures` | 10,192 | main SRAM |
| `Timer_Stack` | 4,096 | FreeRTOS static object/main SRAM |
| `Idle_Stack` | 2,048 | FreeRTOS static object/main SRAM |

## Verification

- Release build: PASS, 0 compiler warning.
- Host contracts: 12/12 PASS.
- One-degree contract: 371 captured, 360 analysis, exact rounded targets.
- SPI1 DMA source/CubeMX contract: PASS.
- Motion Control V2 contract: PASS.

## Measurement invariants của rollback point

- Sweep 0..370°: 371 captured point.
- Analysis point 0..359: 360 point.
- Closure: point 360.
- 64 accepted samples/point, 23,744 samples/run.
- Official capture open-loop sau settle.
- Batch: một precondition + mười official runs, cooldown 120 s.
- Measurement math và validity theo schema-v5 hiện tại.

## Rollback procedure

```powershell
git worktree add ..\jigmotor-baseline-07188e5 `
  07188e5ff0a38a0cb1b51222d090abed9d3fde37
Set-Location ..\jigmotor-baseline-07188e5
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build_make.ps1 -Configuration Release
```

Cách này không sửa hoặc xóa working tree phát triển hiện tại.
