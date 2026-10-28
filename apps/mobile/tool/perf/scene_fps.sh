#!/usr/bin/env bash
# The scenes' frame rate and memory on a connected Android device
# (specs/012.5-m22-animated-scenes SC-002, research R14). Profile build of
# the dev flavor, on a fresh install's first session; see the feature's
# quickstart.md.
#
# Usage: tool/perf/scene_fps.sh <package>
#   e.g. tool/perf/scene_fps.sh com.wassalogra.app.dev
# Prints the summary; exits 1 when a budget is missed, or when a panel
# played without its animation. The budgets are the Galaxy A06's (SC-002):
# a miss on another phone isn't an SC-002 failure.
set -euo pipefail

readonly MIN_AVERAGE_FPS=55
readonly MIN_WINDOW_FPS=45
readonly MAX_MEMORY_MB=300
readonly REPORT=build/integration_response_data.json

# The app's total PSS in KB, or nothing while it isn't running.
pss_kb() {
  adb shell dumpsys meminfo "$1" 2>/dev/null |
    awk '/TOTAL PSS:/ { print $3; exit } /^ *TOTAL / { print $2; exit }'
}

main() {
  local package="${1:?usage: scene_fps.sh <package>}"
  command -v adb >/dev/null || { echo "adb is required." >&2; exit 2; }
  cd "$(dirname "$0")/../.."
  rm -f "$REPORT"

  # The process's memory as Android counts it, sampled during the run.
  local samples
  samples="$(mktemp)"
  (
    while true; do
      pss_kb "$package" >>"$samples" || true
      sleep 1
    done
  ) &
  local sampler=$!
  trap 'kill "$sampler" 2>/dev/null || true; rm -f "$samples"' EXIT

  fvm flutter drive --flavor dev --profile \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/scene_perf_test.dart

  kill "$sampler" 2>/dev/null || true
  local peak_pss_kb
  peak_pss_kb="$(sort -n "$samples" | tail -n 1)"

  python3 - "$REPORT" "${peak_pss_kb:-0}" <<EOF
import json, sys

report = json.load(open(sys.argv[1]))
perf = report["scene_perf"]
frames = report.get("frame_summary", {})
pss_mb = int(sys.argv[2]) / 1024
memory_mb = max(pss_mb, perf["peak_rss_mb"])

checks = [
    ("average fps, the worse scene", perf["average_fps"], ">=", $MIN_AVERAGE_FPS),
    ("worst one-second window (fps)", perf["worst_window_fps"], ">=", $MIN_WINDOW_FPS),
    ("memory, MB (PSS or RSS, the larger)", memory_mb, "<", $MAX_MEMORY_MB),
    ("panels animated", perf["animated_panels"], ">=", perf["panels"]),
]
print(f"{' and '.join(perf['scenes'])}: {perf['panels']} panels, {perf['frames']} frames")
for key in ("average_frame_build_time_millis", "90th_percentile_frame_build_time_millis",
            "average_frame_rasterizer_time_millis", "90th_percentile_frame_rasterizer_time_millis",
            "missed_frame_build_budget_count", "missed_frame_rasterizer_budget_count"):
    if key in frames:
        print(f"  {key}: {frames[key]}")
failed = False
for name, value, op, budget in checks:
    ok = value is not None and {">=": value >= budget, "<": value < budget}[op]
    failed |= not ok
    shown = "n/a" if value is None else f"{value:.1f}"
    print(f"  {'PASS' if ok else 'FAIL'} {name}: {shown} (budget {op} {budget})")
sys.exit(1 if failed else 0)
EOF
}

main "$@"
