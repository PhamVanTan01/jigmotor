---
type: "bugfix"
date: "2026-08-12T09:30:38.892218+00:00"
question: "Why did schema-v6 open-loop logs stop drawing the live NL curve and polar chart, and how was plotting restored?"
contributor: "graphify"
outcome: "corrected"
---

# Q: Why did schema-v6 open-loop logs stop drawing the live NL curve and polar chart, and how was plotting restored?

## Answer

Firmware still emitted all DATA points. Schema v6 appended CommandRawQ16, MeanUnwrappedRawQ16, and ErrorRawQ16, while the live plot and analyze_motor_logs parser required exactly 12 CSV fields, so they silently rejected every schema-v6 DATA row. Parsers now accept the extension and treat ErrorRawQ16 as authoritative. The app produces both <log>.nl.png and <log>.polar.png, and live plotting uses the same canonical parser. App v1.11 was packaged; 39/39 regression tests and EXE launch smoke pass.

## Outcome

- Signal: corrected