# loadout

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

## Contributing

New skills follow the pattern in [`skills/mac-health-check`](skills/mac-health-check):
a `SKILL.md` (the method + thresholds + safety contract), an optional `scripts/` dir for
read-only helpers, and a short `README.md`. Directory names are `lowercase-kebab`,
domain-or-action first.

## License

MIT — see [LICENSE](LICENSE).
