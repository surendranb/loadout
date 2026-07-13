#!/usr/bin/env bash
# mac-health-check :: read-only baseline audit
# Collects diagnostics across every health dimension. Makes NO changes to the system.
# Safe to run anytime. Requires only built-in macOS tools; smartctl is optional.
set -uo pipefail

hr() { printf '\n============ %s ============\n' "$1"; }

hr "MACHINE"
sw_vers 2>/dev/null
system_profiler SPHardwareDataType 2>/dev/null \
  | grep -E 'Model Name|Chip|Processor Name|Total Number of Cores|Memory:'
printf 'Uptime:%s\n' "$(uptime)"

hr "MEMORY  (the real signal is 'pressure', not 'free')"
memory_pressure -Q 2>/dev/null | grep -iE 'free percentage|pressure' | tail -3
sysctl vm.swapusage 2>/dev/null
echo "-- top memory consumers --"
top -l 1 -o mem -n 8 -stats command,mem 2>/dev/null | tail -9

hr "STORAGE"
df -h /System/Volumes/Data 2>/dev/null | awk 'NR==1 || NR==2'
echo "-- home top-level (largest first) --"
du -xh -d 1 "$HOME" 2>/dev/null | sort -rh | head -15
echo "-- ~/Library/Caches --"
du -xsh "$HOME/Library/Caches" 2>/dev/null
echo "-- local (Time Machine) snapshots --"
tmutil listlocalsnapshots / 2>/dev/null | head
echo "-- container free / purgeable --"
diskutil info /System/Volumes/Data 2>/dev/null | grep -iE 'Container Free Space|Purgeable'

hr "COMPUTE / THERMALS"
pmset -g therm 2>/dev/null | grep -iE 'thermal|CPU_Speed_Limit' || echo "no thermal pressure recorded (healthy)"
echo "-- top cpu consumers (ignore transient post-boot spikes) --"
top -l 1 -o cpu -n 6 -stats command,cpu 2>/dev/null | tail -7

hr "BATTERY  (laptops only)"
system_profiler SPPowerDataType 2>/dev/null \
  | grep -iE 'Cycle Count|Maximum Capacity|Condition|State of Charge|Fully Charged' \
  || echo "(no battery — desktop Mac)"

hr "SSD WEAR"
if command -v smartctl >/dev/null 2>&1; then
  smartctl -a /dev/disk0 2>/dev/null \
    | grep -iE 'SMART overall|Percentage Used|Available Spare|Data Units Written|Temperature:|Power On Hours' \
    || echo "SMART read incomplete (common on Apple Silicon — try: smartctl -d nvme -a /dev/disk0)"
else
  echo "smartctl not installed. Optional wear check: brew install smartmontools"
fi

hr "STARTUP LOAD"
echo "-- user LaunchAgents (autostart at login) --"
la_found=0
for f in "$HOME/Library/LaunchAgents/"*.plist; do
  [ -e "$f" ] || continue
  basename "$f"; la_found=1
done
[ "$la_found" -eq 0 ] && echo "(none)"
echo "-- login-item apps --"
osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "(unavailable)"

hr "DONE — this audit changed nothing. Interpret against the thresholds in SKILL.md."
