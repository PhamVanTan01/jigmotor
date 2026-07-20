# A3 — Đề xuất struct/hằng số cho Codex review

Đề xuất code-level cho `CONTROL_A3_ROTATING_CAPTURE_P35_V1` theo plan
`docs/control-a3-phase-trajectory-plan.md`. Toàn bộ định nghĩa dưới đây dự
kiến nằm **private trong `Core/Src/control_engine.c`** đúng style A2F (không
export ra header). Chưa có dòng nào được đưa vào build — đây là bản để
review/graft.

## Khối hằng số + khóa profile

```c
/* A3 is the first phase-trajectory profile after the fixed-phase closeout
 * (docs/control-a2f-p09-result.md): the commanded phase sweeps exactly one
 * electrical cycle with a quintic S-curve so the field is guaranteed to pass
 * the rotor's equilibrium and drag it to the phase-0 equivalent. There is
 * still no HOME/PID and no feedback into the trajectory; the encoder is
 * evidence plus safety only. Single variable vs A2F: the phase moves. */
#define CONTROL_A3_PROFILE_ID              "CONTROL_A3_ROTATING_CAPTURE_P35_V1"

/* Trajectory geometry. Raw scale: 65536/mech rev; one electrical cycle =
 * MOTOR_COUNT_PER_ELECTRICAL_CYCLE = 10923 raw = 60 mech deg. */
#define CONTROL_A3_PHASE_START_RAW         0U
#define CONTROL_A3_PHASE_SWEEP_SPAN_RAW    MOTOR_COUNT_PER_ELECTRICAL_CYCLE

/* Power: 35 percent, the C0 home precedent. NOT in the 6-9 percent band
 * proven ineffective by A2C..A2F. Capture jolt shrinks as power rises
 * (~305 raw predicted at 35 percent -- see the plan doc). */
#define CONTROL_A3_TARGET_POWER_PPM        350000U
#define CONTROL_A3_TARGET_POWER_MILLI      350U

/* Timing, 1 ms tick like A2F. Sweep cadence matches Motion V2's proven
 * 40 ms per mech degree: 60 deg -> 2400 ticks. */
#define CONTROL_A3_PERIOD_MS               1U
#define CONTROL_A3_POWER_RAMP_TICKS        300U
#define CONTROL_A3_SWEEP_TICKS             2400U
#define CONTROL_A3_HOLD_TICKS              500U
#define CONTROL_A3_TOTAL_TICKS             \
    (CONTROL_A3_POWER_RAMP_TICKS + CONTROL_A3_SWEEP_TICKS + CONTROL_A3_HOLD_TICKS)
#define CONTROL_A3_MAX_ACTIVE_MS           4000U

/* Evidence decimation: the run is ~3.2x longer than A2F but CCM stays 64 KB.
 * Record every 3rd tick plus the final tick; guards still run at full 1 ms
 * rate on every tick. */
#define CONTROL_A3_EVIDENCE_DECIMATION     3U
#define CONTROL_A3_MAX_EVIDENCE            \
    ((CONTROL_A3_TOTAL_TICKS / CONTROL_A3_EVIDENCE_DECIMATION) + 2U)

/* Acquisition, unchanged from A2F. */
#define CONTROL_A3_MAX_JUMP_RAW            1821
#define CONTROL_A3_READ_ATTEMPTS           3U

/* Guards -- widened from A2F with reasoning, never silently:
 * - travel: drag can legitimately cover one full cycle (10923 raw = 60 deg)
 *   plus ramp creep and settle overshoot;
 * - step: capture releases ~asin(mu_s/P)-asin(mu_k/P) ~ 305 raw over
 *   ~10-30 ms -> expected peak 30-100 raw/ms; 150 is a reasoned ceiling,
 *   not a tuned one;
 * - active: 300 + 2400 + 500 ticks + margin. */
#define CONTROL_A3_MAX_TRAVEL_RAW          12000
#define CONTROL_A3_MAX_SAMPLE_STEP_RAW     150
#define CONTROL_A3_MAX_CONSECUTIVE_MISSES  3U

/* Capture criterion (window-based; per-tick rotor deltas are +/-1 raw
 * quantized so single-tick comparison is meaningless): captured when rotor
 * displacement over the trailing window is at least half of the field
 * displacement over the same window. Evaluated every tick during SWEEP. */
#define CONTROL_A3_CAPTURE_WINDOW_TICKS    100U
#define CONTROL_A3_CAPTURE_VELOCITY_NUM    1
#define CONTROL_A3_CAPTURE_VELOCITY_DEN    2

/* Drag-slip guard, armed ONLY after capture latches: if the field runs more
 * than 90 elec deg (pull-out angle) ahead of the rotor, torque has reversed
 * slope and the rotor is lost -> safe stop. Before capture this distance is
 * geometry (field legitimately travels toward a stationary rotor), so the
 * guard must stay disarmed. */
#define CONTROL_A3_DRAG_LOSS_LAG_RAW       2731

#if CONTROL_A3_TARGET_POWER_PPM != 350000U
#error "A3 pilot must remain locked to 35 percent power"
#endif
#if CONTROL_A3_POWER_RAMP_TICKS != 300U || CONTROL_A3_SWEEP_TICKS != 2400U \
    || CONTROL_A3_HOLD_TICKS != 500U
#error "A3 pilot timing changed without a new profile identity"
#endif
#if CONTROL_A3_PHASE_SWEEP_SPAN_RAW != MOTOR_COUNT_PER_ELECTRICAL_CYCLE
#error "A3 sweep span must remain exactly one electrical cycle"
#endif
```

## Enum kết quả và pha

```c
typedef enum
{
    CONTROL_A3_OK = 0,
    /* A2F set, unchanged semantics: */
    CONTROL_A3_STATUS_FAULT,
    CONTROL_A3_BASELINE_ACQUISITION_FAULT,
    CONTROL_A3_PRIME_FAULT,
    CONTROL_A3_ENABLE_STATE_FAULT,
    CONTROL_A3_ACQUISITION_FAULT,
    CONTROL_A3_TRAVEL_LIMIT,
    CONTROL_A3_SAMPLE_STEP_LIMIT,
    CONTROL_A3_DEADLINE_FAULT,
    CONTROL_A3_DURATION_LIMIT,
    CONTROL_A3_EVIDENCE_OVERFLOW,
    CONTROL_A3_OPERATOR_ABORT,
    /* A3 additions: */
    CONTROL_A3_CAPTURE_FAULT,   /* sweep completed, capture criterion never met */
    CONTROL_A3_DRAG_SLIP,       /* captured then lost (lag > pull-out angle)   */
} ControlA3Result_t;

typedef enum
{
    CONTROL_A3_PHASE_POWER_RAMP = 0,  /* phase fixed at START_RAW, power 0->35% */
    CONTROL_A3_PHASE_SWEEP,           /* quintic phase trajectory, one cycle    */
    CONTROL_A3_PHASE_HOLD,            /* phase == START_RAW + span (== phase 0) */
} ControlA3Phase_t;
```

## Evidence record (CCM, decimated)

```c
/* 56 bytes/record. vs A2F: +commandPhaseProgressRaw, +dragLagRaw,
 * +captureLatched; -accelerationRawPerSecond2 (double-differenced noise gave
 * no decision value in A2; dragLagRaw is the quantity A3 actually acts on). */
typedef struct
{
    uint32_t sequence;                /* tick index, NOT decimated index      */
    uint32_t scheduledTick;
    uint32_t sampleTick;
    uint32_t loopCycles;
    uint32_t spiLatencyCycles;
    uint32_t latenessTicks;
    uint32_t commandPowerPpm;
    uint32_t commandPhaseProgressRaw; /* field displacement since sweep start */
    int32_t  travelRaw;               /* rotor displacement vs baseline       */
    int32_t  deltaRaw;
    int32_t  velocityRawPerSecond;
    int32_t  dragLagRaw;              /* fieldProgress - rotorProgressSinceSweepStart;
                                       * meaningful from SWEEP onward         */
    uint16_t encoderRaw;
    uint16_t commandElectricalRaw;    /* absolute commanded phase, mod cycle  */
    uint16_t pwmCounterAtCs;
    uint8_t  phase;                   /* ControlA3Phase_t                     */
    uint8_t  captureLatched;          /* 1 from the capture tick onward       */
} ControlA3Evidence_t;

static ControlA3Evidence_t controlEvidence[CONTROL_A3_MAX_EVIDENCE]
    __attribute__((section(".ccmram_bss"), aligned(8)));

/* 1068 * 56 = 59,808 B. Must stay under the 64 KB CCM with headroom for
 * stacks/other .ccmram users of this image (audit the map file). If headroom
 * is judged too thin, DECIMATION 4 -> 802 records = 44.9 KB. */
_Static_assert(sizeof(ControlA3Evidence_t) == 56U,
    "A3 evidence record layout changed -- re-audit the CCM budget");
_Static_assert(sizeof(ControlA3Evidence_t) * CONTROL_A3_MAX_EVIDENCE
    <= 60U * 1024U, "A3 evidence exceeds the CCM budget");
```

## Report

```c
typedef struct
{
    ControlA3Result_t result;
    uint32_t activeDurationMs;
    uint32_t evidenceCount;           /* decimated records actually written   */
    uint32_t deadlineMisses;
    uint32_t maxLatenessTicks;
    uint32_t maxLoopCycles;
    uint32_t maxAbsTravelRaw;
    uint32_t maxSampleStepRaw;
    uint32_t maxAbsVelocityRawPerSecond;
    uint32_t enablePowerPpm;

    /* A3 capture/drag telemetry */
    bool     captureDetected;
    uint32_t captureSeq;              /* tick where the criterion first held;
                                       * UINT32_MAX when never                */
    uint32_t capturePhaseProgressRaw; /* how far the field had traveled       */
    int32_t  dragLagMeanRaw;          /* mean over post-capture SWEEP ticks   */
    int32_t  dragLagMaxRaw;
    int32_t  rampCreepRaw;            /* rotor travel accumulated during
                                       * POWER_RAMP (the known ~0.8 deg A2
                                       * creep, now measured per run)         */

    /* Alignment outcome + calibration byproduct */
    uint16_t baselineRaw;
    uint16_t finalRaw;
    uint16_t electricalOffsetRaw;     /* finalRaw mod cycle at end of HOLD:
                                       * the encoder<->electrical offset of
                                       * this motor+mount. Must repeat across
                                       * runs within the noise band.          */

    bool     primeStateValid;
    bool     enableStateValid;
    MA600_AcquisitionContext_t acquisition;
} ControlA3Report_t;
```

## Chữ ký helper (private)

```c
/* Quintic smoothstep phase progress, pure integer, int64 intermediates.
 * Reference implementation: NlSmoothstepCommandRaw (nonlinear_test.c) -- the
 * Control image does not link the nonlinear engine, so this is a local
 * reimplementation with the same math; add a boot self-check comparing
 * endpoints (0 -> 0, SWEEP_TICKS -> SWEEP_SPAN) and monotonicity. */
static uint32_t ControlA3PhaseProgressRaw(uint32_t sweepTick);

/* Power: linear 0..TARGET over POWER_RAMP_TICKS, then flat (same shape as
 * A2F's ControlA2PowerPpm, target 35 percent). */
static uint32_t ControlA3PowerPpm(uint32_t sequence);

/* Capture criterion over the trailing window (needs travel history; use a
 * small ring of CONTROL_A3_CAPTURE_WINDOW_TICKS int32 travel entries in
 * regular RAM, not CCM-evidence, so decimation does not affect detection). */
static bool ControlA3CaptureCriterionMet(int32_t travelNow,
    uint32_t fieldProgressNow);
```

## Dòng log mới (đổi record name để parser không lẫn với A2)

```text
CONTROL_A3_ARMED,Profile=...,PhaseStartRaw=0,SweepSpanRaw=10923,TargetPowerMilli=350,
  PowerRampMs=300,SweepMs=2400,HoldMs=500,PeriodMs=1,MaxTravelMilliDeg=65918,
  MaxStepMilliDeg=824,CorrectionRaw=0
CONTROL_A3_SUMMARY,...,Result=,CaptureDetected=,CaptureSeq=,CapturePhaseProgressRaw=,
  DragLagMeanRaw=,DragLagMaxRaw=,RampCreepRaw=,BaselineRaw=,FinalRaw=,
  ElectricalOffsetRaw=,MaxTravelMilliDeg=,MaxStepMilliDeg=
CONTROL_A3_SEQUENCE / CONTROL_A3_HEALTH / CONTROL_A3_RUNTIME: như A2F
CONTROL_A3_DATA,Seq=,Phase=,EncoderRaw=,TravelMilliDeg=,DeltaRaw=,
  VelocityRawPerSecond=,DragLagRaw=,CommandPhaseRaw=,PhaseProgressRaw=,
  PowerPpm=,CaptureLatched=,ScheduledTick=,SampleTick=,LatenessTicks=,
  LoopCycles=,SpiLatencyCycles=,PwmCounterAtCs=,CorrectionRaw=0
```

## Câu hỏi mở cho Codex (điểm cần quyết khi review)

1. **CCM budget**: 59.8 KB/64 KB có đủ headroom sau khi cộng mọi thứ khác
   trong `.ccmram_bss` của Control image? Nếu không → DECIMATION 4.
2. **Capture window 100 ms / tỉ lệ 1/2**: có muốn siết (75 ms hoặc 2/3) để
   CaptureSeq sắc hơn không? Ring buffer travel 100×int32 = 400 B RAM thường.
3. **Slip threshold 90° điện**: pull-out lý thuyết; có muốn trừ margin
   (vd 80°) không?
4. **Bỏ accelerationRawPerSecond2**: đồng ý không? (A2 cho thấy nhiễu
   double-difference không phục vụ quyết định nào; dragLagRaw thay thế.)
5. **Record name A3 riêng** (`CONTROL_A3_*`): đồng ý để tách parser, hay
   muốn giữ schema A2 + field Profile phân biệt?
6. **Contract test**: `test_control_alignment_contract.ps1` sẽ cần case A3
   (khóa power/timing/span, guard values, decimation, record names) — làm
   trong cùng commit implement.
7. `MaxStepMilliDeg` trong ARMED: 150 raw = 824 mdeg — giữ đơn vị mdeg như
   A2F hay đổi sang raw cho thẳng với guard?
```

(Hết phần đề xuất — implement thuộc về Control image line, không đụng
measurement image.)
