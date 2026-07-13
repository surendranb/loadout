# Contributing to loadout

Thanks for wanting to add to the kit. loadout skills clear a higher bar than typical
snippets because **they run on people's machines** — so the standard is: useful, safe,
and honest about what they touch.

## Add a skill in 4 steps

1. **Copy the template:**
   ```bash
   cp -R template skills/your-skill-name
   ```
   Folder name is `lowercase-kebab`, domain-or-action first (e.g. `pr-review`,
   `repo-onboard`). It must **not** contain `claude` or `anthropic` (reserved).

2. **Write `SKILL.md`.** The frontmatter `name:` must match the folder exactly, and
   `description:` must say **what it does and when to use it** — that's how the agent
   decides to invoke it. No angle brackets in frontmatter (it goes into the system prompt).

3. **Put any helpers in `scripts/`** (read-only diagnostics) or `references/` (docs loaded
   on demand). Shell scripts must pass `shellcheck -S warning`.

4. **Validate, then open a PR:**
   ```bash
   bash scripts/validate.sh      # must pass; CI runs the same checks
   ```
   Add a row to the skills table in `README.md`, and bump `version` in
   `.claude-plugin/plugin.json` + `marketplace.json`.

## The quality bar (what reviewers look for)

- **Measures before it acts.** Diagnose the real constraint; don't apply generic fixes.
- **Ranks fixes by impact ÷ (cost + risk).** Cheapest reversible win first.
- **Honest thresholds.** State the numbers and *why* they're the thresholds.
- **No cargo-cult.** If it repeats a myth (see any skill's "myths" section), it won't merge.

## The safety contract (non-negotiable)

Every skill must:

1. Be **read-only by default**; state explicitly what, if anything, changes state.
2. **Never delete, uninstall, or reconfigure without the user approving a specific list**
   (with sizes/impact shown). No "I'll just quickly…".
3. **Never touch** the user's own work (documents, databases, models), managed/corporate
   configuration, or anything ambiguous — without explicit per-item confirmation.
4. Prefer **reversible** changes and tell the user how to undo them.
5. **Report faithfully** — if something failed or did less than projected, say so.

A skill that can't honor this contract doesn't belong here.
