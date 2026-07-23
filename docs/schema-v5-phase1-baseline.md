# Phase-1 Schema-v5 Baseline Fixtures

The filenames below contain `v6`, but filename text is not schema authority.
Their `META`, `RESULT`, and `END` records all declare `SchemaVersion=5`, and
their configuration records declare `POLICY_A_AUDIT_V1` with
`AuditFieldsLocked=0`.

They are therefore immutable **Phase-1 audit / schema-v5 numerical regression
fixtures**, not evidence that the canonical Phase-2 sampler or schema v6 has
passed.

| File | Jig/UID | Runs | SHA-256 |
| --- | --- | ---: | --- |
| `v6-p03-jig1.txt` | JIG1 / `003C00273234470438353535` | 3 | `EA1407992E41F3E0EBBB5457A116C9E5FAC4B211DC7B108161EFA5D627942074` |
| `v6-p03-jig2.txt` | JIG2 / `0025002C3234470438353535` | 3 | `A89AF55F1DBCC9C1A48DFAB778AFFAE147094D6C455F44DBAA279BF694FF3839` |

The JIG2 fixture contains an interrupted move-to-zero preamble before the
official batch. Offline tools accept only complete structured blocks with an
authoritative `META`, and identify runs by SessionID/BatchID/TestID/SweepID
when those fields exist. Preamble text and filenames cannot supply identity.

Observed scope:

- both audited MA600 configurations match and use a zero correction table;
- all six official schema-v5 runs have clean ordinary acquisition counters;
- the files remain useful for legacy numerical and parser regression;
- closure is diagnostic in schema v5 and does not affect its `Status=VALID`;
- no canonical Q16 mean, scheduled-slot, skipped-slot, or MAD evidence exists.

Run `scripts/test_phase1_baseline_integrity.ps1` to verify the hashes, schema,
identity, record count, and audit-only classification.
