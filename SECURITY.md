# Security & Safety

loadout skills instruct a coding agent to run commands on your machine — some inspect the
system, and some (with your approval) delete files or change settings. Treat them like any
script you'd run: read before you trust.

## What these skills may and may not do

- **Read-only by default.** Diagnostics (e.g. `scripts/audit.sh`) make no changes and are
  safe to run anytime.
- **No destructive action without your explicit approval.** Skills must present a specific
  list — with sizes and impact — and wait for you to approve before deleting, uninstalling,
  or reconfiguring anything. This is enforced socially (the contract in `CONTRIBUTING.md`)
  and by review, not by a sandbox — **you are the final check.**
- **Your work and managed config are off-limits** unless you confirm per item: documents,
  databases, model fine-tunes, and any corporate/MDM/endpoint agents.

## Using safely

- Read a skill's `SKILL.md` and any `scripts/` before running it.
- Prefer reviewing the proposed changes; don't blanket-approve deletions.
- These skills are provided under the MIT license **with no warranty** — you run them at
  your own risk.

## Reporting a problem

Found a skill that deletes without asking, hardcodes a secret, or otherwise breaks the
safety contract? Please **open a GitHub issue** (or a private security advisory for
sensitive reports) at https://github.com/surendranb/loadout. Include the skill name and
the exact behavior. Safety bugs are treated as the highest priority.
