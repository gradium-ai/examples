#!/bin/bash
# Counts reps in real videos of other people and compares with hand counts: the clips listed
# in scripts/video-clips.tsv are fetched from YouTube into build/clips (not committed), run
# through Vision's body pose by repcoach-video, and counted by repcoach-replay, the same
# counting code the app runs.
#
#   scripts/video-check.sh [exercise]
#
# Needs yt-dlp and ffmpeg (brew install yt-dlp ffmpeg). Runs on the Mac, not the phone, so
# what it measures is the counting logic and Vision on footage; the phone's own camera adds
# its own framing and lighting.
set -euo pipefail
cd "$(dirname "$0")/.."
CLIPS=build/clips
mkdir -p "$CLIPS"
(cd RepCoachCore && swift build -c release --product repcoach-video -q && swift build -c release --product repcoach-replay -q)
BIN=RepCoachCore/.build/release

total=0; ok=0
while IFS=$'\t' read -r exercise id truth note; do
  [[ -z "$exercise" || "$exercise" == \#* ]] && continue
  [[ -n "${1:-}" && "$exercise" != "$1" ]] && continue
  video="$CLIPS/$id.mp4" poses="$CLIPS/$id.jsonl"
  if [ ! -s "$video" ]; then
    yt-dlp -q --no-warnings -f "bv*[height<=720][ext=mp4]/b[height<=720][ext=mp4]" -o "$video" -- "https://www.youtube.com/watch?v=$id"
    # AVFoundation reads H.264, not the VP9 some uploads come in.
    if [ "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$video")" != h264 ]; then
      ffmpeg -v error -y -i "$video" -c:v libx264 -crf 20 -an "$video.h264.mp4" && mv "$video.h264.mp4" "$video"
    fi
  fi
  [ -s "$poses" ] || "$BIN/repcoach-video" "$video" "$poses" --exercise "$exercise" > /dev/null
  counted=$("$BIN/repcoach-replay" "$poses" --exercise "$exercise" | sed -nE 's/^sets: .* total: ([0-9]+).*/\1/p')
  total=$((total + 1))
  if [ "$counted" = "$truth" ]; then ok=$((ok + 1)); mark=ok; else mark=MISS; fi
  printf "%-17s %-12s truth %2s  counted %2s  %-4s  %s\n" "$exercise" "$id" "$truth" "$counted" "$mark" "$note"
done < scripts/video-clips.tsv
echo "$ok of $total clips counted exactly"
