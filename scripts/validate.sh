#!/usr/bin/env bash
# Validate every skill in the repo before it ships.
# Checks: SKILL.md frontmatter, name==folder, description present, no angle
# brackets in frontmatter, reserved-word ban, JSON manifests parse, shell scripts lint.
# Run locally:  bash scripts/validate.sh
set -uo pipefail

fail=0
err() { printf '    \033[31m✗ %s\033[0m\n' "$1"; fail=1; }
ok()  { printf '    \033[32m✓ %s\033[0m\n' "$1"; }

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root" || exit 1

echo "▶ Skills"
shopt -s nullglob
skills=(skills/*/SKILL.md)
if [ ${#skills[@]} -eq 0 ]; then err "no skills found under skills/"; fi
for skill_md in "${skills[@]}"; do
  folder="$(basename "$(dirname "$skill_md")")"
  echo "  • $folder"

  if [ "$(head -1 "$skill_md")" != "---" ]; then
    err "SKILL.md must begin with '---' frontmatter"; continue
  fi
  # frontmatter = lines between the first pair of --- delimiters
  fm="$(awk 'NR>1{if($0=="---")exit; print}' "$skill_md")"

  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | tr -d "\"' " | head -1)"
  if [ -z "$name" ]; then err "missing 'name:'"
  elif [ "$name" != "$folder" ]; then err "name '$name' != folder '$folder'"
  else ok "name matches folder"; fi

  printf '%s\n' "$fm" | grep -q '^description:' && ok "description present" \
    || err "missing 'description:'"

  if printf '%s' "$fm" | grep -q '[<>]'; then
    err "frontmatter contains '<' or '>' (leaks into the system prompt)"
  else ok "frontmatter free of angle brackets"; fi

  printf '%s' "$name" | grep -qiE 'claude|anthropic' \
    && err "name may not contain 'claude'/'anthropic' (reserved)"
done

echo "▶ JSON manifests"
for j in .claude-plugin/*.json; do
  [ -e "$j" ] || continue
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$j" 2>/dev/null; then
    ok "$j"
  else err "$j is not valid JSON"; fi
done

echo "▶ Shell scripts"
if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r s; do
    if shellcheck -S warning "$s" >/dev/null 2>&1; then ok "$s"
    else err "$s (shellcheck -S warning)"; fi
  done < <(find . -name '*.sh' -not -path './.git/*')
else
  echo "    (shellcheck not installed — skipped locally; CI enforces it)"
fi

echo
if [ "$fail" -eq 0 ]; then echo -e "\033[32m✅ all checks passed\033[0m"
else echo -e "\033[31m❌ validation failed\033[0m"; exit 1; fi
