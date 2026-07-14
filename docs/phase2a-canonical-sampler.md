# Phase 2A Canonical Sampler Status

Status: software implementation and locked-profile boot/self-test evidence are
complete for JIG1 and JIG3. The sampler is connected only as a non-official
schema-v5 Phase-2B shadow; legacy remains the official capture path. A locked
JIG2 smoke record is still required if JIG2 remains in production scope.

## Implemented contract

- `CANONICAL_Q16_V1`, signed int64 Q16, half-away-from-zero rounding.
- Q16 scaling uses multiplication by `65536LL`; signed shifts are forbidden.
- Point 0 relative error is exactly zero and the full-turn target is exactly
  `65536LL * 65536LL`.
- `ALL_TIER1` is the only canonical candidate; MAD filtering and robust counts
  remain disabled.
- Explicit back-to-back and scheduled start-to-start timing modes.
- First attempted transaction initializes the schedule even on SPI failure.
- A failed transaction consumes its slot; missed slots advance directly to a
  future slot and cannot cause a catch-up burst.
- DWT wrap-safe timing, transaction/elapsed/consecutive-failure budgets,
  skipped-slot/timing-error/transport/jump counters, and atomic unwrap reject.
- Integer/fixed-point-only acquisition loop with caller-owned/static storage;
  no allocation, sorting, formatting, float conversion, or DFT in the loop.

## Tests

The firmware runs `MA600_PointSamplerSelfTest()` before motor initialization.
A later passing CONFIG record includes `PointSamplerSelfTest=1`; if the test
fails, boot enters `Error_Handler()` and no batch CONFIG record can be emitted.

The C self-test covers:

- positive/negative exact-half rounding;
- positive and negative point means;
- exact point-0 and full-turn error;
- immediate first sample;
- first transaction timeout with correct next-slot timing;
- two missed slots with no catch-up read;
- DWT counter wrap;
- rejected jump leaving accepted unwrap state/timestamp untouched.

`scripts/test_canonical_sampler_contract.ps1` independently models the frozen
math and scheduler rules. Debug compiler stack reports are reviewed after every
change; the timing loop itself does not allocate a large local window.

## Phase-2A gate evidence

Archived JIG1/JIG3 logs contain CONFIG records with all of:

```text
GatePolicy=POLICY_A_LOCKED_V1
AuditFieldsLocked=1
ExpectedProfileFound=1
ConfigGateSelfTest=1
PointSamplerSelfTest=1
ConfigValid=1
PolicyAGatePassed=1
RejectReason=NONE
```

The Phase-2B software integration is now present with
`OfficialResultSource=LEGACY`. Its remaining hardware work and pass tracking
are in `docs/phase2b-shadow-checklist.md`. Schema v6 official output remains
forbidden until that checklist and later closure/settle/validity integration
pass.
