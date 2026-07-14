# Phase 2B Shadow Checklist

> Status note — 2026-07-14: this checklist remains the historical Phase-2B
> record. Phase 3A has since been implemented and hardware logs now expose a
> point-256/closure problem. The active blocking review is
> `phase3b0-closure-measurement-review.md`; do not infer 10-run readiness from
> Phase-2B structural pass items.

Ngày cập nhật: 2026-07-13

Trạng thái tổng thể: **phần mềm Phase 2B đã tích hợp và pass kiểm thử host/build;
gate phần cứng còn chờ log mới từ JIG1 và JIG3**. Schema 5/legacy vẫn là kết
quả chính thức. Canonical chỉ là shadow và không được phép quyết định
`MeasurementValid`, `Motor OK`, hay batch pass/fail.

## Đã pass trong phần mềm

- [x] Giữ `NL_LOG_SCHEMA_VERSION=5` và `OfficialResultSource=LEGACY`.
- [x] Canonical dùng context unwrap độc lập; lỗi shadow không sửa state hoặc
  counter của legacy.
- [x] Canonical được lấy tại cùng commanded/settled point, sau khi giá trị
  legacy của point đó đã được đóng băng.
- [x] Sampler dùng `CANONICAL_Q16_V1`, `ALL_TIER1`, 64 accepted samples,
  `BACK_TO_BACK`, MAD tắt.
- [x] Point 0 là reference canonical và `Error0RawQ16=0` theo đúng contract.
- [x] Có budget độc lập: tối đa 96 transactions, tối đa 3 lỗi liên tiếp
  (cấu hình abort khi counter vượt 2), và 20 ms/point.
- [x] Có các record riêng `SHADOW_META`, `SHADOW_DATA`, `SHADOW_ACQ`,
  `SHADOW_RESULT`, `SHADOW_END`.
- [x] Có metric shadow RMS_AC, A36, P2P, closure, legacy-minus-canonical RMS
  và A36.
- [x] Closure limit 0.20 degree chỉ là integrity audit; chưa phải giới hạn
  chất lượng motor và không gate legacy.
- [x] Counter shadow tách khỏi `AcqReadAttempts`, retry/error/jump counter của
  schema 5.
- [x] UID mapping thống nhất cho JIG1, JIG2 và JIG3 trong firmware và parser.
- [x] `MotorIDSource`/`MotorIDValid` làm lộ rõ build chưa gán Motor ID; không
  còn coi `UNKNOWN` như một identity hợp lệ.
- [x] Parser đọc và kiểm tra identity/contract/status của shadow; fixture JIG3
  được thêm vào regression.
- [x] `test_phase1_baseline_integrity.ps1` pass.
- [x] `test_canonical_sampler_contract.ps1` pass.
- [x] `test_analyze_nonlinear_logs.ps1` pass.
- [x] `test_phase2b_shadow_contract.ps1` pass.
- [x] Release build pass, 0 error/0 warning: text 60,492 B, data 96 B.
- [x] Debug build pass, 0 error/0 warning: text 97,436 B, data 96 B.
- [x] Shadow point workspace 6,600 B nằm trong CCM `NOLOAD`, được `memset`
  trước mỗi capture; không chiếm FLASH payload và không dùng DMA.
- [x] Main SRAM linker margin còn khoảng 9.5 KiB; Debug static stack lớn nhất
  trong đường log là `PrintSweepLog` 1,808 B + `LogLineLarge` 1,920 B, nằm
  trong test-task stack 6,656 B. Runtime high-water vẫn phải xác nhận trên JIG.

## Chuẩn bị firmware theo từng motor

- [ ] P03: thêm compiler define `MOTOR_ID=\"P03\"`, clean/rebuild, lưu một
  file HEX có checksum; dùng đúng cùng file HEX đó cho JIG1 và JIG3.
- [ ] P05: thêm compiler define `MOTOR_ID=\"P05\"`, clean/rebuild, lưu một
  file HEX có checksum; dùng đúng cùng file HEX đó cho JIG1 và JIG3.
- [ ] Không chạy matrix nếu META còn `MotorID=UNKNOWN`, `MotorIDSource=UNSET`
  hoặc `MotorIDValid=0`.
- [ ] Sau khi flash, lưu `BuildID`, checksum HEX, Motor ID, operator, ngày giờ
  và điều kiện gá/lắp trong tên thư mục test.

## Preflight trên mỗi JIG

- [ ] `CONFIG` có `GatePolicy=POLICY_A_LOCKED_V1`, `AuditFieldsLocked=1`,
  `ExpectedProfileFound=1`, `ConfigGateSelfTest=1`,
  `PointSamplerSelfTest=1`, `ConfigValid=1`, `PolicyAGatePassed=1`,
  `RejectReason=NONE`.
- [ ] UID tự ánh xạ đúng: JIG1 = `003C00273234470438353535`; JIG3 =
  `004C003A3034510B31363339`. Không suy ra JIG từ tên file.
- [ ] META có đúng Motor ID của firmware, `MotorIDSource=BUILD_DEFINE` và
  `MotorIDValid=1`.
- [ ] META có `OfficialResultSource=LEGACY`, `ShadowCanonicalEnabled=1`,
  `ShadowContractVersion=CANONICAL_Q16_V1`, `ShadowOfficial=0`.
- [ ] Motor disable an toàn sau test; không reset, HardFault, stack-overflow
  hoặc UART record bị thiếu/truncated.

## Matrix Phase 2B tối thiểu

Chạy 3 sweep cho mỗi ô, giữ cùng protocol cooldown/remount đã dùng cho bộ log
v5. Tổng tối thiểu: 12 sweep.

| Motor | JIG1 | JIG3 |
| --- | --- | --- |
| P03 | [ ] 3/3 | [ ] 3/3 |
| P05 | [ ] 3/3 | [ ] 3/3 |

Nếu JIG2 vẫn nằm trong production scope, chạy thêm cùng matrix trên UID
`0025002C3234470438353535`; JIG2 chưa được phép suy diễn từ kết quả JIG3.

## Điều kiện pass cho từng sweep

- [ ] Legacy vẫn có `MeasurementValid=1`, `TrackingValid=1`,
  `AcquisitionResult=OK`, `END ... Status=VALID` và `Motor OK`.
- [ ] Legacy `AcqReadAttempts=17226`, không retry/transport error/jump reject,
  đúng frozen baseline khỏe mạnh.
- [ ] `SHADOW_END ... Status=VALID`, `AcquisitionResult=OK`.
- [ ] Shadow có `AttemptedPoints=265`, `CapturedPoints=265`,
  `Transactions=16960`, `AcceptedSamples=16960`, `FailedPoints=0`.
- [ ] Shadow có `SpiFailures=0`, `JumpRejects=0`, `MetadataInvalid=0`,
  `SkippedSlots=0`, `TimingOverruns=0` trong mode back-to-back.
- [ ] `Error0RawQ16=0` chính xác; không chỉ gần bằng zero sau đổi sang float.
- [ ] Point 256 tồn tại và closure được log đủ Q16/degree/validity. Nếu
  `ClosureValid=0`, giữ log nhưng không dùng sweep đó để promote canonical.
- [ ] `RUNTIME` không giảm bất thường: không malloc failure; ghi lại
  `FreeHeap`, `MinEverFreeHeap`, `TestStackHighWaterWords`; yêu cầu tối thiểu
  256 words high-water trước khi đóng gate.
- [ ] Parser chạy không exception và identity trong CSV khớp UID + Motor ID,
  không dựa vào tên file.

## Đánh giá sau khi đủ 12 sweep

- [ ] Tính theo từng cặp Motor/JIG: median, SD và range của canonical RMS_AC,
  A36, P2P, closure, `LegacyMinusCanonicalRMS`,
  `LegacyMinusCanonicalA36` và motor-active duration.
- [ ] So sánh JIG1/JIG3 theo từng motor; không gộp P03 và P05 thành một mẫu.
- [ ] Kiểm tra delta legacy-canonical có ổn định theo sweep/JIG hay phụ thuộc
  thứ tự chạy, nhiệt, remount hoặc lỗi acquisition.
- [ ] Xác nhận shadow không thay đổi pass/fail và không làm legacy vượt khỏi
  vùng repeatability của baseline trước đó.
- [ ] Chỉ khi toàn bộ gate trên pass mới đề xuất Phase 3. Không promote schema
  6 hoặc canonical official chỉ vì canonical cho con số nhỏ hơn legacy.

## Lệnh kiểm tra host

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_phase1_baseline_integrity.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_canonical_sampler_contract.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_analyze_nonlinear_logs.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_phase2b_shadow_contract.ps1
```

## Operator decision override - 2026-07-14

Motor ID preparation items above are no longer a software gate for the next
Phase-3A hardware run. The operator will fill Motor ID after each test. An
unset Motor ID remains visible as `MotorID=UNKNOWN`, `MotorIDSource=UNSET`, and
`MotorIDValid=0`; it must not be mistaken for a verified identity, but it does
not invalidate the sweep. This is a waived/operator-managed item, not a passed
automatic identity check.

Motor pole count is different: it affects commutation and must be correct
before testing. The current PIXY configuration is 12 physical poles, derived
as 6 pole pairs. See `phase3a-motion-settle-checklist.md`.
