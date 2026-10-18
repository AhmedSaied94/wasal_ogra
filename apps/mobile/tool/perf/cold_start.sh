#!/usr/bin/env bash
# Cold start to الموقف fully drawn on a connected Android device (SC-001).
# Release build on the reference device; see specs/001-m03-app-shell/quickstart.md.
#
# Usage: tool/perf/cold_start.sh <package> <runs>
#   e.g. tool/perf/cold_start.sh com.wassalogra.app 10
# Exits 1 when the median is over the budget.
set -euo pipefail

readonly BUDGET_MS=3000
readonly ACTIVITY_CLASS=com.wassalogra.app.MainActivity
readonly FULLY_DRAWN_WAIT_S=15

# "+1s234ms" or "+850ms" -> milliseconds.
to_ms() {
  if [[ "$1" =~ \+(([0-9]+)s)?([0-9]+)ms ]]; then
    echo $(( 10#${BASH_REMATCH[2]:-0} * 1000 + 10#${BASH_REMATCH[3]} ))
  else
    return 1
  fi
}

# Median of integers on stdin (mean of the middle two for an even count).
median() {
  sort -n | awk '{ v[NR] = $1 } END {
    if (NR == 0) exit 1
    if (NR % 2) print v[(NR + 1) / 2]
    else print int((v[NR / 2] + v[NR / 2 + 1]) / 2)
  }'
}

# Waits for this run's "Fully drawn <package>/...: +…ms" line in logcat.
fully_drawn_ms() {
  local package="$1" line
  for _ in $(seq "$FULLY_DRAWN_WAIT_S"); do
    line="$(adb logcat -d | grep -F "Fully drawn ${package}/" | tail -n 1 || true)"
    if [[ -n "$line" ]]; then
      to_ms "${line##*: }"
      return
    fi
    sleep 1
  done
  echo "No 'Fully drawn ${package}' line within ${FULLY_DRAWN_WAIT_S}s." >&2
  return 1
}

main() {
  local package="${1:?usage: cold_start.sh <package> <runs>}"
  local runs="${2:?usage: cold_start.sh <package> <runs>}"
  local results=() ms

  for run in $(seq "$runs"); do
    adb logcat -c
    # -S force-stops the app first, so every run is a cold start.
    adb shell am start -S -W -n "${package}/${ACTIVITY_CLASS}" >/dev/null
    ms="$(fully_drawn_ms "$package")"
    results+=("$ms")
    echo "run ${run}: ${ms} ms"
  done

  local med
  med="$(printf '%s\n' "${results[@]}" | median)"
  echo "median: ${med} ms (budget ${BUDGET_MS} ms)"
  if (( med > BUDGET_MS )); then
    echo "FAIL: cold start is over budget." >&2
    exit 1
  fi
  echo "PASS"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
