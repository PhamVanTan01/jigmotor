# Codex handoff: NL validity and cross-jig synchronization

Date: 2026-07-30  
Branch: `codex/motion-control-v2-dma`  
Baseline parent: `2cb8043`

This file is the entry point for the next AI or engineer. Read it before
changing the motor controller, PWM, NL formula, jig calibration, or host
analysis tools.

## 1. Executive verdict

The project is credible today as a repeatable **whole-system command-tracking
measurement** on one controlled jig. It is not yet credible as:

- absolute MA600 sensor INL;
- intrinsic motor-only NL;
- a traceable ISO measurement;
- an interchangeable multi-jig production acceptance system.

Current status:

```text
Within-jig repeatability:        PASS
Acquisition/math integrity:      PASS
Closure/residual under A0:       PASS
Cross-jig NL reproducibility:    FAIL / OPEN
Remount/torque/sector control:    OPEN
Absolute trueness/traceability:  NOT ESTABLISHED
```

Do not restart A3/A4/A5/B0-B/V3 or retune PID merely to make NL smaller.
Those phases improved motion integrity and repeatability. The remaining
problem is metrology reproducibility between jigs.

## 2. What the firmware measures

There is no independent reference encoder. The firmware correctly declares:

```text
MeasurementPolicy=WHOLE_SYSTEM_REPORT_ONLY_V1
MeasurementDefinition=WHOLE_SYSTEM_COMMAND_TRACKING
AcceptanceMode=REPORT_ONLY
```

The measured curve contains:

- motor/cogging/load angle;
- magnet position/eccentricity;
- clamp force and mounting;
- PWM/driver/dead-time;
- approach/ramp/settle behavior;
- jig and MA600 sensor;
- thermal and sector state.

Current robust NL is:

```text
NL = mean(each run's top 5 Error points)
   - mean(each run's bottom 5 Error points)
```

over analysis points 0..359. Point 360 is closure; points 361..370 are
post-turn diagnostics. `Motor OK` means that protocol/acquisition completed;
it is not a product-quality or sensor-INL decision.

## 3. Current production/default source state

The source restored into this branch has these defaults:

```text
Approach:                         SHIFTED_REVERSAL_A0
Grid:                             1 degree, rounded 182/183 raw
Analysis points:                  360
Closure point:                    360
Canonical contract:              CANONICAL_Q16_1DEG360_V2
Batch:                            1 precondition + 10 official
Cooldown:                         120 s
Dead-time feedforward:            OFF
A4 widened P06 diagnostic guard:  OFF
Acceptance mode:                  REPORT_ONLY
```

The 1% dead-time feedforward and wider A4 sample-step limit remain
compile-time, default-OFF diagnostic experiments. They are not production
calibration.

## 4. Pipeline defects fixed on 2026-07-30

### 4.1 Contract ID split

Historical `CANONICAL_Q16_V1` means:

```text
AnalysisPoints=256
ClosureIndex=256
StepRaw=256
```

Current `CANONICAL_Q16_1DEG360_V2` means:

```text
AnalysisPoints=360
ClosureIndex=360
StepRaw=0
Grid=UNIFORM_1_DEG_ROUNDED_RAW_V1
```

Some historical 360-point logs were incorrectly stamped
`CANONICAL_Q16_V1`. The PowerShell analyzer still reads them but exports:

```text
ShadowContractEffectiveVersion=CANONICAL_Q16_1DEG360_V2
ShadowContractLegacyAlias=1
```

New firmware emits the V2 identity. Do not rewrite historical raw logs.

### 4.2 Python analyzer

`tools/analyze_motor_logs.py` previously hardcoded 256 analysis points,
treated point 256 as closure on 360-point logs, admitted PRECONDITION as
official-valid, and then applied a second inconsistent `RunOrder>=2` rule in
group summaries.

It now:

- takes `AnalysisPoints` from META;
- uses closure index `AnalysisPoints`;
- treats `StepRaw=0` as the rounded one-degree grid;
- requires `RunRole=OFFICIAL` and `EligibleForStatistics=1` when declared;
- excludes PRECONDITION even when acquisition/END are valid;
- includes official RunOrder 1;
- labels legacy records without role fields instead of guessing their role.

Cross-check over the 100 Test-33 official sweeps showed the Python
DATA-derived robust NL and the PowerShell analyzer agree within 0.0016
degrees. The small difference is consistent with decimal precision in logged
DATA rows.

## 5. Verification status

After the pipeline fix:

```text
All PowerShell regression/contract tests: 28/28 PASS
Python analyzer self-test:                 PASS
Release build:                             PASS
```

The Release build had only the pre-existing unused diagnostic warnings for
`NlCreepResultName` and `kNlB0BPreRollCheckpoints`.

Key regression fixtures:

- legacy 256-point V1;
- current 360-point V2;
- historical 360-point/V1 legacy alias;
- dynamic closure index;
- RunRole/EligibleForStatistics exclusion.

## 6. Test-33 cross-jig NL result

Each group below contains 10 declared official/eligible sweeps. Precondition
is excluded.

| Product | JIG1 NL | JIG4 NL | JIG4-JIG1 | Relative |
| --- | ---: | ---: | ---: | ---: |
| P02 | 2.997° | 3.298° | +0.301° | +10.0% |
| P03 | 2.645° | 2.696° | +0.051° | +1.9% |
| P05 | 2.655° | 3.109° | +0.454° | +17.1% |
| P06 | 2.882° | 3.008° | +0.126° | +4.4% |
| P07 | 2.434° | 2.795° | +0.362° | +14.9% |

Within-batch NL SD is approximately 0.006..0.026 degrees. The cross-jig
changes are therefore systematic and generally much larger than repeat
noise. There is no valid scalar NL offset shared by all products.

## 7. Point-by-point/top-bottom finding

The batch-mean JIG1/JIG4 curves are strongly correlated for P02/P03/P05/P06:

| Motor | Curve r | Delta top-5 | Delta bottom-5 | Delta robust NL |
| --- | ---: | ---: | ---: | ---: |
| P02 | 0.9841 | +0.1636° | -0.1367° | +0.3003° |
| P03 | 0.9664 | +0.2147° | +0.1641° | +0.0506° |
| P05 | 0.9619 | +0.0665° | -0.3879° | +0.4544° |
| P06 | 0.9695 | +0.5120° | +0.3874° | +0.1246° |
| P07 | 0.9389 after 240° alignment | +0.4069° | +0.0453° | +0.3616° |

The five points in each tail are re-selected in 78..100% of runs within each
batch. They are not random SPI/encoder jitter.

Interpretation:

- P05's cross-jig NL delta is dominated by a much deeper negative trough on
  JIG4.
- P03/P06 show that top and bottom can both move strongly in the same
  direction; subtraction hides most of the underlying curve change.
- Robust NL alone is insufficient for jig synchronization.
- P07 is sector/orientation-confounded and must not be used as a common
  absolute-angle reference yet.

MA600 raw zero is local to each sensor. Equal raw codes on JIG1/JIG4 are not
a shared physical angle. Use sweep-relative coordinates plus an explicitly
controlled mechanical/electrical datum.

## 8. Current decision about dead-time tuning

Do not choose a dead-time coefficient by minimum NL. A global coefficient
could improve the five limiting points on one motor while moving another
motor's opposite tail.

Queued coefficients remain diagnostic. Evaluate:

```text
DeltaError(angle) =
    Error_deadtime(angle) - Error_baseline(angle)
```

Classify the result:

- smooth and shared across products -> driver transfer-function candidate;
- localized at tail/breakaway positions -> friction/cogging interaction;
- changed by same-jig remount -> mounting/sector;
- improves one product while degrading another -> no global coefficient.

## 9. Minimum next plan: synchronize jigs without restarting the project

### S0: Freeze

- Use this branch, V2 contract, A0, dead-time OFF.
- Record commit SHA and firmware SHA-256.
- Use one power supply, cooldown and analyzer version.

### S1: Same-jig remount

Use P03 as the near-synchronized control and P05 as the worst-case product.
On JIG1:

```text
3 independent remounts/product
fixed torque and orientation
1 precondition + 3 official/remount
```

If the remount shift approaches P05's 0.45-degree cross-jig shift, fix the
fixture before investigating electronics.

### S2: A-B-A jig transfer

After S1 is stable:

```text
P03: JIG1 -> JIG4 -> JIG1
P05: JIG1 -> JIG4 -> JIG1
1 precondition + 3 official per leg
```

Decision:

- A1 approximately A2, B different -> real JIG4 contribution;
- A1 different from A2 -> session/remount still uncontrolled;
- same differential curve on both motors -> common jig correction candidate;
- product-dependent differential -> hardware/mount interaction, no scalar
  correction.

### S3: Electrical/sensor isolation

Only if S2 confirms a jig effect:

- loaded supply voltage;
- PWM/dead-time and three phase duties;
- cable/phase resistance;
- MA600/magnet gap and concentricity;
- motor/driver temperature;
- sector at analysis start;
- pointwise differences at both tails.

## 10. Pilot gates for later confirmation

These are engineering gates and must be frozen before viewing the
confirmation batch:

```text
Within-batch NL SD:             <= 0.03 deg
Remount mean shift:             <= 0.05 deg
Cross-jig |Delta NL|:           <= max(0.05 deg, 2.77 * pooled SD)
|Delta top-5 mean|:             <= 0.10 deg
|Delta bottom-5 mean|:          <= 0.10 deg
Curve correlation:              >= 0.98
Centered curve RMSE:            <= 0.10 deg
Closure/config/acquisition:     100% valid
```

Passing these gates establishes interchangeability for
`WHOLE_SYSTEM_COMMAND_TRACKING`, not absolute sensor/motor trueness.

## 11. Reproduction commands

Run every regression:

```powershell
$tests = Get-ChildItem .\scripts -Filter 'test_*.ps1'
foreach ($test in $tests) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test.FullName
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($test.Name)" }
}
```

Build:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build_make.ps1 -Configuration Release
```

Recompute Python metrics:

```powershell
python .\tools\analyze_motor_logs.py <logs...> --csv output.csv
```

Recreate Test-33 extreme analysis:

```powershell
python .\tools\analyze_nl_extreme_angles.py `
  B0-B-v32-a0-p02-jig1-test-33.txt `
  B0-B-v32-a0-p02-jig4-test-33.txt `
  B0-B-v32-a0-p03-jig1-test-33.txt `
  B0-B-v32-a0-p03-jig4-test-33.txt `
  B0-B-v32-a0-p05-jig1-test-33.txt `
  B0-B-v32-a0-p05-jig4-test-33.txt `
  B0-B-v32-a0-p06-jig1-test-33.txt `
  B0-B-v32-a0-p06-jig4-test-33.txt `
  B0-B-v32-a0-p07-jig1-test-33.txt `
  B0-B-v32-a0-p07-jig4-test-33.txt `
  --out-dir .\analysis-out\test33-nl-extreme-angles
```

## 12. Important files

- `Core/Src/nonlinear_test.c`
- `Core/Src/motor_pwm.c`
- `scripts/analyze_nonlinear_logs.ps1`
- `tools/analyze_motor_logs.py`
- `tools/analyze_nl_extreme_angles.py`
- `docs/nonlinear-metric-contract-v2.md`
- `docs/nl-extreme-angle-cross-jig-test33-assessment.md`
- `analysis-out/test33-nl-extreme-angles/`

Large oscilloscope captures and compiled build artifacts are deliberately not
part of the pushed branch. They are not required to reproduce the Test-33 NL
conclusion and exceed normal Git hosting limits.
