# loadout

[![validate](https://github.com/surendranb/loadout/actions/workflows/validate.yml/badge.svg)](https://github.com/surendranb/loadout/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> The kit you equip your coding agent with — a collection of **universal, agent-agnostic
> skills** that make Claude Code (and other agent tools) sharper at real work.

A skill here isn't a prompt or a snippet. It's a **drilled capability**: a documented
method the agent follows every time, with the judgment, thresholds, and safety rails
baked in — so you get expert behavior on demand instead of improvising each run.

## Skills

| Skill | What it does |
|---|---|
| [`mac-health-check`](skills/mac-health-check) | Monthly macOS performance & longevity check. Measures every dimension, diagnoses the *actual* bottleneck (not symptoms), proposes ranked reversible fixes, never deletes without approval. |

_More on the way._

## Design principles (every skill in here follows these)

- **Measure first, fix the constraint.** Diagnose the one binding bottleneck before
  touching anything. Symptoms lie about their category.
- **Rank by impact ÷ (cost + risk).** Cheap, reversible, high-impact wins go first.
- **Safety contract.** Read-only by default. No deletion or destructive change without
  the user approving a specific list. Reversible where possible. Never touch the user's
  real work or managed/corporate config blindly.
- **Debunk, don't repeat, myths.** Prefer removing over adding.
- **Agnostic.** No hardcoded paths or machine assumptions — detect and adapt.

## Install

**Recommended — as a plugin (one command, auto-updates):**

```
/plugin marketplace add surendranb/loadout
/plugin install loadout@loadout
```

Then ask Claude Code in natural language (e.g. _"run a Mac health check"_) — it picks up
the skill automatically. Refresh later with `/plugin marketplace update loadout`.

**Or manually** — each skill is self-contained and drops straight into your skills dir:

```bash
cp -R skills/mac-health-check ~/.claude/skills/   # one skill
cp -R skills/* ~/.claude/skills/                  # all of them
```

## Safety

These skills run commands on your machine — so safety is a hard requirement, not a footnote:

- **Read-only by default.** Diagnostics make no changes and are safe to run anytime.
- **Nothing destructive without your approval** — a skill must show a specific list (with
  sizes/impact) and wait for your yes before deleting, uninstalling, or reconfiguring.
- **Your work and managed/corporate config are off-limits** unless you confirm per item.

**You are the final check** — read a skill before you run it. Details in [SECURITY.md](SECURITY.md).

## Contributing

New skills start from [`template/`](template) and must pass `bash scripts/validate.sh`
(CI runs the same checks: frontmatter, folder-name match, JSON manifests, `shellcheck`).
See [CONTRIBUTING.md](CONTRIBUTING.md) for the quality bar and the safety contract every
skill must honor.

## License

MIT — see [LICENSE](LICENSE). Provided as-is, without warranty; you run these skills at
your own risk.
