#!/usr/bin/env bash
# A trip's frame rate, response and memory on a connected Android device
# (specs/008-m02-trip-screen SC-003 to SC-005). Profile build of the dev
# flavor, with the real character; see the feature's quickstart.md.
#
# Usage: tool/perf/trip_fps.sh <package> <trip_id>
#   e.g. tool/perf/trip_fps.sh com.wassalogra.app.dev line_gamaa.02
# Prints the summary; exits 1 when a budget is missed.
set -euo pipefail

readonly MIN_AVERAGE_FPS=55
readonly MIN_WINDOW_FPS=45
readonly MAX_MEMORY_MB=300
readonly MAX_TAP_MS=100
readonly MAX_FIRST_FRAME_MS=1000
readonly REPORT=build/integration_response_data.json

# The app's total PSS in KB, or nothing while it isn't running.
pss_kb() {
  adb shell dumpsys meminfo "$1" 2>/dev/null |
    awk '/TOTAL PSS:/ { print $3; exit } /^ *TOTAL / { print $2; exit }'
}

main() {
  local package="${1:?usage: trip_fps.sh <package> <trip_id>}"
  local trip="${2:?usage: trip_fps.sh <package> <trip_id>}"
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
    --target=integration_test/trip_perf_test.dart \
    --dart-define=WASSAL_PERF_TRIP="$trip"

  kill "$sampler" 2>/dev/null || true
  local peak_pss_kb
  peak_pss_kb="$(sort -n "$samples" | tail -n 1)"

  python3 - "$REPORT" "${peak_pss_kb:-0}" <<EOF
import json, sys

report = json.load(open(sys.argv[1]))
perf = report["trip_perf"]
frames = report.get("frame_summary", {})
pss_mb = int(sys.argv[2]) / 1024
memory_mb = max(pss_mb, perf["peak_rss_mb"])

checks = [
    ("average fps", perf["average_fps"], ">=", $MIN_AVERAGE_FPS),
    ("worst one-second window (fps)", perf["worst_window_fps"], ">=", $MIN_WINDOW_FPS),
    ("memory, MB (PSS or RSS, the larger)", memory_mb, "<", $MAX_MEMORY_MB),
    ("drawer tap to hand, ms", perf["drawer_tap_to_hand_ms"], "<=", $MAX_TAP_MS),
    ("trip's first frame, ms", perf["first_frame_ms"], "<=", $MAX_FIRST_FRAME_MS),
]
print(f"{perf['trip_id']}: {perf['frames']} frames")
for key in ("average_frame_build_time_millis", "90th_percentile_frame_build_time_millis",
            "average_frame_rasterizer_time_millis", "90th_percentile_frame_rasterizer_time_millis",
            "missed_frame_build_budget_count", "missed_frame_rasterizer_budget_count"):
    if key in frames:
        print(f"  {key}: {frames[key]}")
failed = False
for name, value, op, budget in checks:
    ok = value is not None and {">=": value >= budget, "<": value < budget, "<=": value <= budget}[op]
    failed |= not ok
    shown = "n/a" if value is None else f"{value:.1f}"
    print(f"  {'PASS' if ok else 'FAIL'} {name}: {shown} (budget {op} {budget})")
sys.exit(1 if failed else 0)
EOF
}

main "$@"
