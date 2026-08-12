## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Mandatory project objective: pure open-loop NL

The primary and authoritative objective of this repository is to measure and
evaluate **pure Gremsy-compatible open-loop nonlinearity (NL)**. Read
`docs/open-loop-nl-direction-correction-handoff-2026-08-12.md` before planning
or implementing any firmware, analysis, logging, build, test-procedure, or
hardware-validation change.

Rules:

- Every proposed change MUST state which part of open-loop NL evaluation it
  improves: measurement accuracy, repeatability, traceability, validity,
  comparability, acquisition integrity, or test time without changing the
  measurand. A change with no direct open-loop NL purpose is out of scope
  unless the user explicitly authorizes a separate diagnostic experiment.
- The official measurement path MUST keep motor actuation open-loop. Encoder
  samples may be observed and logged, but they MUST NOT modify the motor
  command before the official DATA sample is frozen.
- Creep, PID/FOC position correction, adaptive endpoint correction, recovery,
  feedforward learned from the same encoder response, and terminal correction
  MUST NOT be used in the official open-loop NL path.
- A stability/acquisition failure MUST invalidate the point or sweep. The
  firmware MUST NOT rescue a failed point by changing its command and then
  publish the corrected value as official open-loop NL.
- Any feedback-actuated experiment MUST use a separate diagnostic profile,
  declare `OfficialOpenLoopNL=0`, and set `EligibleForStatistics=0`. Its values
  MUST NOT be pooled with official open-loop NL statistics.
- All official point data and derived metrics MUST come from one canonical
  sample mean for that point. A separate single raw read MUST NOT replace or
  label the canonical mean used to compute Error/NL.
- The Gremsy-compatible primary metric is
  `Error[i] = CommandAngle[i] - (EncoderMeanAngle[i] - EncoderOffset)` and
  `OpenLoopNL = max(Error) - min(Error)`. RMS, robust P2P, harmonics, closure,
  and the full 360-point curve are supporting metrics; none may silently
  redefine the primary measurand.
- Any change to motor command/profile, approach history, sample timing,
  settling, point grid, reference/zero, MA600 configuration/filter, sample
  count, error formula, validity gates, schema, or analyzer MUST include an
  explicit measurement-contract impact assessment and appropriate versioning.
- Validation MUST inspect the full 360-point error curve, extrema locations,
  repeatability, harmonics, acquisition/settle validity, and scalar NL. Do not
  promote or reject a change using only one scalar NL value.
- Before implementation, classify the change as `OPEN_LOOP_MEASUREMENT` or
  `DIAGNOSTIC_ONLY`. After implementation, report evidence that the
  classification and invariants above still hold.
- If a requested change conflicts with these rules, stop and explain the
  conflict before editing code. Do not silently change the measurement goal.
