---
name: mac-health-check
description: Monthly macOS health check and performance optimization for Apple Silicon and Intel Macs. Measures memory, storage, compute and thermals, battery, SSD wear, and startup load; diagnoses the actual bottleneck (not symptoms); proposes ranked, reversible fixes; never deletes without explicit approval. Use for "check my Mac's health", "optimize my Mac", "why is my Mac slow", "free up disk space", "monthly Mac maintenance", or any Mac performance or longevity request.
---

# Mac Health Check

A diagnostic *discipline* for keeping a Mac fast and long-lived — not a "cleaner."
The difference: you **measure first, find the one binding constraint, and fix that** —
instead of applying generic cleanup tips that optimize things that aren't the problem.

> Symptoms lie about their category. "It's slow" often presents as a CPU problem,
> is caused by memory, and is fixed on disk. That is why you audit every dimension
> before touching any one of them.

## The method (follow in order — do not skip Phase 0)

1. **Baseline** — run the read-only audit. Never diagnose from memory or assumption.
2. **Find the constraint** — apply the USE method (Utilization / Saturation / Errors)
   per resource. A system has *one* binding bottleneck at a time; improving anything
   else is invisible. Saturation (work *queuing* behind a resource) matters more than
   utilization (how busy it looks).
3. **Rank interventions** by `impact-on-the-constraint ÷ (cost + risk)`. Cheap,
   reversible, high-impact first. Amdahl's law: fixing a 2%-of-the-problem thing caps
   your gain at 2%, however elegant.
4. **Propose with trade-offs stated. Get approval. NEVER auto-delete.** Change one
   category at a time.
5. **Re-measure** — confirm the constraint moved. Then find the *next* one.
6. **Stop when the objective is met.** Optimizing a healthy machine is pure cost.

**Prefer removing over adding.** The wins are subtraction (fewer login items, less
junk, a reboot), not addition (RAM utilities, "cleaner" apps — which add another
resident agent and are net-negative; never recommend them).

## Phase 0 — Baseline (always safe, read-only)

Run the read-only audit bundled with this skill — `scripts/audit.sh` in this skill's
own directory. The path depends on how the skill was installed:

```bash
# installed via the loadout plugin/marketplace:
bash "$CLAUDE_PLUGIN_ROOT/skills/mac-health-check/scripts/audit.sh"
# copied manually into your skills dir:
bash ~/.claude/skills/mac-health-check/scripts/audit.sh
```

It detects the machine (chip, RAM, cores, macOS version) and collects every dimension.
It makes **zero** changes. Read its output; do not infer the machine's contents from
names — read the actual numbers.

## Phase 1 — Diagnose against thresholds

Interpret the audit. Classify each dimension 🟢 healthy / 🟡 watch / 🔴 constraint.
Thresholds are chosen to be RAM- and model-agnostic where possible:

| Dimension | Signal | 🟢 Healthy | 🟡 Watch | 🔴 Act |
|---|---|---|---|---|
| **Memory** | `memory_pressure` level | Normal | — | Warn / Critical |
| **Memory** | swap used vs pool | low, pool small | growing | pool maxed + pressure not Normal |
| **Storage** | disk % used | < 80% | 80–90% | **> 90%** (APFS degrades; swap needs room) |
| **Compute** | thermal pressure | none recorded | nominal | any throttle / CPU_Speed_Limit < 100 |
| **Compute** | load avg vs cores | < cores | ~cores | ≫ cores *and sustained* (ignore post-boot spikes) |
| **Uptime** | days | — | > 7 | maxed swap at any uptime → reboot |
| **Battery** | Max Capacity | > 85% | 80–85% | < 80% or Condition ≠ Normal |
| **SSD** | Available Spare | 100% | < 100% | < threshold (usually 99%) |
| **SSD** | Percentage Used | informational — high write-rate points to swap thrashing upstream | | |

**The RAM signal is `memory_pressure`, NOT "free memory."** macOS deliberately uses
most RAM (caches, compressor); "low free RAM" alone is normal and healthy. Only
`memory_pressure` = Warn/Critical, or swap maxed while pressure is elevated, is a
real constraint.

Then name the **single binding constraint** and its causal chain (RCA to the atomic
cause — a symptom is not a cause). Common chain: *slow ← swap thrashing ← swap pool
constrained ← disk near-full + RAM oversubscribed.* Fixing disk+reboot can resolve
what looks like a "CPU" problem.

## Phase 2/3 — Propose ranked, reversible fixes (get approval)

Present a scorecard, then a ranked plan. **Every deletion needs an approved list with
sizes shown first.** Order:

### Tier A — Zero-risk, auto-regenerates (safe to clear on approval)
- Package-manager caches: `npm cache clean --force`, `uv cache clean`, `~/.gradle/caches`,
  `~/Library/Caches/*`, browser caches, `~/.cache/puppeteer`, etc.
- Trade-off: next install/launch is slightly slower. No data loss.

### Tier B — Reboot (if uptime high or swap maxed)
- The single highest-value move when swap is maxed: it resets the swap pool, clears
  leaked memory and stale daemons, and applies any staged OS update.
- **You cannot reboot for the user** (needs their saved work + sudo). Instruct them:
  save work → Apple menu → Restart. Give a one-line re-measure command for when back.

### Tier C — User-judgment (ALWAYS ask, show sizes)
- **Local LLM models** (Ollama / LM Studio / HF cache): re-downloadable, but
  **fine-tunes may be irreplaceable** — distinguish public models from the user's own
  work before proposing. Ask which to keep.
- **Dormant apps**: full uninstall = app bundle + `~/Library/Application Support/<id>`
  + Caches + Preferences + Containers + login item. Reclaims far more than caches.
- **Dev artifacts in projects** (`node_modules`, `venv`/`.venv`, `target`, `dist`,
  `.next`, `__pycache__`): regenerable via install/build. Only propose for projects
  the user confirms are dormant; preserve recently-active ones so they stay runnable.
- **Startup trim**: disable updater/autostart agents. Do it *reversibly* (move plists
  to `~/Library/LaunchAgents/disabled/` and `launchctl bootout`), and tell the user how
  to re-enable. Never touch corporate/MDM agents (see gotchas).

## Phase 4/5 — Execute approved, measure, stop
- Execute one category at a time. Capture `df` before/after (note purgeable lag — freed
  space settles over ~1 minute; don't trust the instantaneous delta).
- After a reboot, re-measure memory/swap/uptime to confirm the constraint broke. If swap
  re-maxes immediately, RAM is genuinely undersized — a *different* constraint; report it.
- When every dimension is 🟢, **stop**. Log results to a durable file.

## Gotchas (these make the skill robust — they were learned the hard way)

- **`kMDItemLastUsedDate` is often NULL** (Spotlight/MDM config). Don't rank apps by it.
  Use `~/Library/Application Support/<app>` **modification time** as a usage proxy.
- **`du` output elision**: piping `du | sort | head` can hide large entries mid-list and
  the totals won't add up. Write the full scan to a file and read it; verify sums against
  the volume total (`df`), which is ground truth.
- **`node_modules` trap**: most `node_modules` on a dev machine live *inside* `~/Library`
  (Electron apps, editor extensions) — those are app internals; **deleting them breaks
  apps.** Only `node_modules` in actual project dirs (outside `~/Library` and outside
  editor dot-dirs like `~/.vscode`, `~/.cursor`) are project deps.
- **Regenerable vs. user work**: `node_modules`/venv/build caches regenerate. But tool
  *data dirs* can hold irreplaceable work — e.g. workflow/flow databases, notes, model
  fine-tunes. "No `.app` installed" does NOT mean the data is junk (CLI/pip tools). Verify
  before deleting; when unsure, ask.
- **Purgeable space**: `df` and Finder disagree because APFS reports purgeable
  separately, and freed space is reclaimed lazily. Re-measure after a short delay.
- **Corporate / MDM agents are untouchable**: e.g. SentinelOne, JumpCloud, CrowdStrike,
  Palo Alto GlobalProtect, Netskope, Okta, Jamf. Detect them, report their cost if asked,
  but never disable them — and they usually need sudo anyway.
- **Apple Silicon SSD SMART** may return partial data or need `-d nvme`; `Percentage Used`
  is the wear figure. Don't over-claim if the read is incomplete.

## Myths — do NOT recommend (outdated on modern macOS)
- "Repair disk permissions" (gone since OS X El Capitan).
- Periodic SMC / NVRAM / PRAM resets as routine maintenance (troubleshooting only; SMC
  doesn't even exist on Apple Silicon).
- RAM-purge / memory-freeing utilities (`purge` fights the OS; pressure handles itself).
- Manual cache-clearing as a *ritual* (only when disk-constrained or an app misbehaves).
- Third-party "cleaner" apps — net-negative (resident agent, aggressive deletions).

## Safety contract (this is shared publicly — honor it)
1. The baseline audit is read-only and always safe.
2. **No deletion, uninstall, or config change without the user approving a specific list
   with sizes.** No exceptions, no "I'll just quickly…".
3. Never touch: user documents/databases, model fine-tunes, corporate/MDM agents, or
   artifacts in recently-active projects — without explicit per-item confirmation.
4. Make changes reversible where possible; tell the user how to undo them.
5. Report faithfully: if a step failed or freed less than projected, say so with numbers.
