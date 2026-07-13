# mac-health-check

A **Claude Code skill** that runs a monthly macOS health check the way a performance
engineer would: measure every dimension first, find the one real bottleneck, fix that,
and stop — instead of blindly applying "clean your Mac" tips.

Works on Apple Silicon and Intel Macs. Read-only by default. **Never deletes anything
without showing you a list with sizes and getting your approval.**

## What it checks
Memory pressure & swap · storage & APFS purgeable space · compute & thermal throttling ·
battery health & cycles · SSD wear (SMART) · startup / login load.

## Why it's different
- **Diagnoses the constraint, not the symptom.** "Slow" is usually a memory-pressure
  problem that shows up as disk-full — it fixes the cause, not the noise.
- **Ranks fixes by impact ÷ (cost + risk)** — cheapest reversible wins first.
- **Safety contract:** the audit is read-only; nothing is deleted, uninstalled, or
  reconfigured without your explicit approval; corporate/MDM agents and your own work
  (documents, databases, model fine-tunes, active projects) are never touched blindly.
- **Debunks the myths** (repair permissions, RAM purgers, routine NVRAM resets, "cleaner"
  apps) instead of repeating them.

## Usage
Install into your Claude Code skills directory:

```
~/.claude/skills/mac-health-check/
```

Then in Claude Code: **"run a Mac health check"** (or "why is my Mac slow", "free up
disk space", "monthly Mac maintenance"). Or run just the read-only audit yourself:

```bash
bash ~/.claude/skills/mac-health-check/scripts/audit.sh
```

## Files
- `SKILL.md` — the method, thresholds, gotchas, and safety contract Claude follows.
- `scripts/audit.sh` — read-only diagnostic collector (makes no changes).

## License
MIT — part of the [`loadout`](https://github.com/surendranb/loadout) skill collection.
