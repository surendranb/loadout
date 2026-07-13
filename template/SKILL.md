---
name: your-skill-name
description: One sentence on WHAT this skill does, then WHEN to use it (situations and trigger phrases). Both halves matter — the description is how the agent decides to invoke the skill. Keep it a single concrete line. No angle brackets and no YAML folded scalars in frontmatter (it enters the system prompt).
---

# Your Skill Name

State the outcome this skill produces and the method it follows — in one paragraph.
A skill is a *drilled capability*, not a prompt: same disciplined behavior every run.

## Method

1. **Measure first.** Gather the real state before deciding anything.
2. **Find the constraint.** Diagnose the one binding bottleneck; ignore symptoms.
3. **Rank fixes** by impact divided by (cost plus risk). Cheapest reversible win first.
4. **Propose, get approval, act.** Never take a destructive step without a shown, approved list.
5. **Re-measure and stop** when the objective is met.

## Thresholds / rules

List the concrete numbers or rules the agent applies, and *why* each is the threshold
(rationale, not just the rule).

## Safety contract

- Read-only by default; name exactly what (if anything) changes state.
- No deletion/uninstall/reconfig without the user approving a specific list.
- Never touch the user's own work or managed configuration without explicit confirmation.
- Make changes reversible where possible; report outcomes faithfully.
