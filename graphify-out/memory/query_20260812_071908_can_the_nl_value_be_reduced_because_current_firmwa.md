---
type: "query"
date: "2026-08-12T07:19:08.559638+00:00"
question: "Can the NL value be reduced because current firmware can adjust it?"
contributor: "graphify"
outcome: "useful"
---

# Q: Can the NL value be reduced because current firmware can adjust it?

## Answer

Yes, the reported number can be made smaller with creep, live encoder feedback, per-point correction, or subtracting a learned curve, but then it is corrected residual and no longer pure open-loop NL. V5.x demonstrates measurand manipulation, not physical motor improvement. True open-loop whole-system NL can be reduced legitimately only by improving the physical/electrical plant or a fixed predeclared commutation contract that does not adapt to the DUT/run; such a change creates a new versioned measurand and needs independent validation. Separate measurement firmware from product-compensation development, and never tune and qualify on the same batch.

## Outcome

- Signal: useful