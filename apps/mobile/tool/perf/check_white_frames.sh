#!/usr/bin/env bash
# Fails if any frame of a launch recording is mostly white (SC-001a): the
# splash, the boot screen and الموقف must all be شمس, never a white flash.
#
# Usage: tool/perf/check_white_frames.sh <video>
#   Record with: adb shell screenrecord --time-limit 5 /sdcard/launch.mp4
set -euo pipefail

readonly WHITE_LUMA=245     # full-range luma counted as white
readonly MAX_WHITE_SHARE=50 # percent of a frame's pixels

main() {
  local video="${1:?usage: check_white_frames.sh <video>}"
  command -v ffmpeg >/dev/null || { echo "ffmpeg is required." >&2; exit 2; }
  [[ -f "$video" ]] || { echo "No such file: $video" >&2; exit 2; }

  # Per frame: map white pixels to 255 and the rest to 0, so the frame's mean
  # luma (YAVG) is the white share times 255. Phone recordings are usually
  # limited range, so expand to full range first.
  local filter="scale=out_range=full,format=gray"
  filter+=",lut=c0='if(gte(val,${WHITE_LUMA}),255,0)'"
  filter+=",signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-"

  local stats
  stats="$(ffmpeg -nostdin -v error -i "$video" -vf "$filter" -f null - )"

  local result
  result="$(awk -F= -v max="$MAX_WHITE_SHARE" '
    /lavfi.signalstats.YAVG=/ {
      frames++
      share = $2 / 255 * 100
      if (share > max) { bad++; printf "frame %d: %.0f%% white\n", frames - 1, share }
    }
    END {
      printf "%d frames checked, %d mostly white\n", frames, bad
      if (frames == 0 || bad > 0) exit 1
    }' <<<"$stats")" && status=0 || status=$?
  echo "$result"
  if (( status != 0 )); then
    echo "FAIL" >&2
    exit 1
  fi
  echo "PASS"
}

main "$@"
