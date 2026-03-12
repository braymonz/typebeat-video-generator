#!/bin/zsh

# Script to download, trim, loop, and mux a YouTube video with WAV audio
# Usage: ./script.sh -u "YT_VIDEO_URL" -w "WAV_PATH" -o "OUTPUT_PATH" --trim-start TRIM_START [cookies-from-browser chrome]

set -e

# Function to print usage
usage() {
  echo "Usage: $0 -u YT_VIDEO_URL -w WAV_PATH -o OUTPUT_PATH --trim-start TRIM_START [cookies-from-browser chrome]"
  exit 1
}

# Check dependencies
for dep in yt-dlp ffmpeg; do
  if ! command -v $dep >/dev/null 2>&1; then
    echo "$dep is not installed. Install it with:"
    case $dep in
      yt-dlp)
        echo "  brew install yt-dlp";;
      ffmpeg)
        echo "  brew install ffmpeg";;
    esac
    exit 2
  fi
done

# Parse arguments
COOKIES_ARG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u)
      YT_URL="$2"; shift 2;;
    -w)
      WAV_PATH="$2"; shift 2;;
    -o)
      OUTPUT_PATH="$2"; shift 2;;
    --trim-start)
      TRIM_START="$2"; shift 2;;
    --cookies-from-browser)
      BROWSER="$2" # only set if specified
      if [[ -n "$BROWSER" && "$BROWSER" != "none" ]]; then
        COOKIES_ARG=(--cookies-from-browser "$BROWSER")
      fi
      shift 2;;
    *)
      usage;;
  esac
done

if [[ -z "$YT_URL" || -z "$WAV_PATH" || -z "$OUTPUT_PATH" || -z "$TRIM_START" ]]; then
  usage
fi

# Add .mov extension if not present
if [[ "$OUTPUT_PATH" != *.mov && "$OUTPUT_PATH" != *.MOV ]]; then
  OUTPUT_PATH="${OUTPUT_PATH}.mov"
fi

# Convert trim start to seconds if in HH:MM:SS or MM:SS format
if [[ "$TRIM_START" =~ : ]]; then
  TRIM_START=$(echo "$TRIM_START" | awk -F: '{if (NF==3) print ($1 * 3600) + ($2 * 60) + $3; else if (NF==2) print ($1 * 60) + $2; else print $1}')
fi

# Check if WAV file exists
if [[ ! -f "$WAV_PATH" ]]; then
  echo "Error: Audio file not found at: $WAV_PATH"
  exit 1
fi

# Temporary files
TMP_VIDEO="/tmp/yt_downloaded_$$.mp4"
TMP_LOOP="/tmp/yt_loop_$$.mp4"

trap 'rm -f "$TMP_VIDEO" "$TMP_LOOP"' EXIT

# Download only video (no audio needed) - best quality
echo "Downloading video from YouTube..."
yt-dlp "${COOKIES_ARG[@]}" -f "bestvideo[ext=mp4]" \
  -o "$TMP_VIDEO" "$YT_URL"

# Extract trimmed segment and create forward-backward loop in one pass
echo "Extracting 9.5s from ${TRIM_START}s and creating forward-backward loop..."
ffmpeg -y -ss "$TRIM_START" -t 9.5 -i "$TMP_VIDEO" -filter_complex "[0:v]split[v1][v2];[v2]reverse[vr];[v1][vr]concat=n=2:v=1:a=0[out]" -map "[out]" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p "$TMP_LOOP"

# Apply crop, scale, pad and encode with audio
echo "Processing video: cropping to square, letterboxing, and encoding for YouTube..."

ffmpeg -y \
  -stream_loop -1 -i "$TMP_LOOP" \
  -i "$WAV_PATH" \
  -filter_complex "[0:v]crop=min(iw\,ih):min(iw\,ih):(iw-min(iw\,ih))/2:(ih-min(iw\,ih))/2,scale=1080:1080,setsar=1,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black[v]" \
  -map "[v]" -map 1:a \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -c:a copy \
  -movflags +faststart \
  -shortest \
  "$OUTPUT_PATH"

echo "Done! Output: $OUTPUT_PATH\n"

# Analyze the output video's audio stream
echo "Analyzing output video audio..."
OUT_EBUR128=$(ffmpeg -hide_banner -nostats -vn -i "$OUTPUT_PATH" -af ebur128=peak=true -f null - 2>&1 | grep -v "@" | grep -v "^$")

OUT_DURATION_HMS=$(echo "$OUT_EBUR128" | grep "Duration:" | awk -F', ' '{print $1}' | awk '{print $2}' | head -1)
OUT_SAMPLE_RATE=$(echo "$OUT_EBUR128" | grep "Audio:" | grep -o '[0-9]* Hz' | head -1 | grep -o '[0-9]*')
OUT_CODEC=$(echo "$OUT_EBUR128" | grep "Audio:" | awk '{for(i=1;i<=NF;i++) if($i=="Audio:") print $(i+1)}' | head -1 | tr -d ',')

if [[ "$OUT_CODEC" =~ pcm_s([0-9]+) ]]; then
  OUT_BIT_DEPTH="${match[1]}"
elif [[ "$OUT_CODEC" =~ pcm_f([0-9]+) ]]; then
  OUT_BIT_DEPTH="${match[1]}"
else
  OUT_BIT_DEPTH=$(echo "$OUT_EBUR128" | grep "Audio:" | grep -o 's[0-9]*' | head -1 | grep -o '[0-9]*')
  [[ -z "$OUT_BIT_DEPTH" ]] && OUT_BIT_DEPTH="N/A"
fi

case "$OUT_CODEC" in
  pcm_s16le|pcm_s24le|pcm_s32le|pcm_f32le|pcm_f64le) OUT_FORMAT="WAV (PCM)" ;;
  aac) OUT_FORMAT="AAC" ;;
  mp3) OUT_FORMAT="MP3" ;;
  flac) OUT_FORMAT="FLAC" ;;
  vorbis) OUT_FORMAT="Vorbis" ;;
  opus) OUT_FORMAT="Opus" ;;
  alac) OUT_FORMAT="ALAC (Apple Lossless)" ;;
  *) OUT_FORMAT="$OUT_CODEC" ;;
esac

OUT_MAX_PEAK=$(echo "$OUT_EBUR128" | grep "Peak:" | grep "dBFS" | awk '{print $2}')
OUT_INTEGRATED=$(echo "$OUT_EBUR128" | grep "I:" | grep "LUFS" | awk '{print $2}')
[[ -z "$OUT_MAX_PEAK" ]] && OUT_MAX_PEAK="N/A"
[[ -z "$OUT_INTEGRATED" ]] && OUT_INTEGRATED="N/A"

echo "\nOutput Audio Information:"
echo "======================="
echo "Duration: ${OUT_DURATION_HMS}"
echo "Sample Rate: ${OUT_SAMPLE_RATE} Hz"
echo "Bit Depth: ${OUT_BIT_DEPTH} bits"
echo "Format: ${OUT_FORMAT}"
echo "Integrated Loudness: ${OUT_INTEGRATED} LUFS"
echo "Max True Peak: ${OUT_MAX_PEAK} dBFS"
echo "=======================\n"