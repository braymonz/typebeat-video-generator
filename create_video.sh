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
        echo "  brew tap homebrew-ffmpeg/ffmpeg
                brew install homebrew-ffmpeg/ffmpeg/ffmpeg --with-fdk-aac # includes improved fdk-aac encoder";;
    esac
    exit 2
  fi
done

# Parse arguments
COOKIES_ARG=""
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
    cookies-from-browser)
      BROWSER="$2" # only set if specified
      if [[ -n "$BROWSER" && "$BROWSER" != "none" ]]; then
        COOKIES_ARG="--cookies-from-browser $BROWSER"
      fi
      shift 2;;
    *)
      usage;;
  esac
done

if [[ -z "$YT_URL" || -z "$WAV_PATH" || -z "$OUTPUT_PATH" || -z "$TRIM_START" ]]; then
  usage
fi

# Add .mp4 extension if not present
if [[ "$OUTPUT_PATH" != *.mp4 && "$OUTPUT_PATH" != *.MP4 ]]; then
  OUTPUT_PATH="${OUTPUT_PATH}.mp4"
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
TMP_TRIMMED="/tmp/yt_trimmed_$$.mp4"
TMP_LOOP="/tmp/yt_loop_$$.mp4"

# Download only video (no audio needed) - best quality
echo "Downloading video from YouTube..."
yt-dlp $COOKIES_ARG -f "bestvideo[ext=mp4]" \
  -o "$TMP_VIDEO" "$YT_URL"

# Extract the trimmed segment first
echo "Extracting 9.5 seconds of video starting from ${TRIM_START}s..."
ffmpeg -y -ss "$TRIM_START" -t 9.5 -i "$TMP_VIDEO" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p "$TMP_TRIMMED"

# Create forward-backward loop segment
echo "Creating forward-backward loop effect..."
ffmpeg -y -i "$TMP_TRIMMED" -filter_complex "[0:v]split[v1][v2];[v2]reverse[vr];[v1][vr]concat=n=2:v=1:a=0[out]" -map "[out]" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p "$TMP_LOOP"

# Get all audio information using EBU R128 analysis (includes stream info + loudness measurements)
echo "Analyzing audio file..."
EBUR128_OUTPUT=$(ffmpeg -hide_banner -nostats -i "$WAV_PATH" -filter_complex "[0:a]ebur128=peak=true" -vn -f null - 2>&1 | grep -v "@" | grep -v "^$")

# Check if analysis succeeded
if [[ -z "$EBUR128_OUTPUT" ]]; then
  echo "Error: Failed to analyze audio file. Please check that the file exists and is a valid audio file."
  exit 1
fi

# Parse duration (convert HH:MM:SS.MS to seconds)
DURATION_HMS=$(echo "$EBUR128_OUTPUT" | grep "Duration:" | awk -F', ' '{print $1}' | awk '{print $2}')
AUDIO_DURATION=$(echo "$DURATION_HMS" | awk -F: '{print ($1 * 3600) + ($2 * 60) + $3}')

# Parse sample rate
SAMPLE_RATE=$(echo "$EBUR128_OUTPUT" | grep "Audio:" | grep -o '[0-9]* Hz' | head -1 | grep -o '[0-9]*')

# Parse codec name
CODEC=$(echo "$EBUR128_OUTPUT" | grep "Audio:" | awk '{for(i=1;i<=NF;i++) if($i=="Audio:") print $(i+1)}' | head -1 | tr -d ',')

# Extract bit depth from codec name (e.g., pcm_s16le = 16-bit, pcm_s24le = 24-bit)
if [[ "$CODEC" =~ pcm_s([0-9]+) ]]; then
  BIT_DEPTH="${match[1]}"
elif [[ "$CODEC" =~ pcm_f([0-9]+) ]]; then
  BIT_DEPTH="${match[1]}"
else
  # For compressed formats, try to find bit depth in stream info or default to N/A
  BIT_DEPTH=$(echo "$EBUR128_OUTPUT" | grep "Audio:" | grep -o 's[0-9]*' | head -1 | grep -o '[0-9]*')
  [[ -z "$BIT_DEPTH" ]] && BIT_DEPTH="N/A"
fi

# Convert codec name to human-readable format
case "$CODEC" in
  pcm_s16le|pcm_s24le|pcm_s32le|pcm_f32le|pcm_f64le) FORMAT="WAV (PCM)" ;;
  aac) FORMAT="AAC" ;;
  mp3) FORMAT="MP3" ;;
  flac) FORMAT="FLAC" ;;
  vorbis) FORMAT="Vorbis" ;;
  opus) FORMAT="Opus" ;;
  alac) FORMAT="ALAC (Apple Lossless)" ;;
  wmav2) FORMAT="WMA" ;;
  ac3) FORMAT="AC3 (Dolby Digital)" ;;
  eac3) FORMAT="EAC3 (Dolby Digital Plus)" ;;
  dts) FORMAT="DTS" ;;
  *) FORMAT="$CODEC" ;;
esac

# Parse max true peak and integrated loudness from EBU R128 summary

MAX_PEAK=$(echo "$EBUR128_OUTPUT" | grep "Peak:" | grep "dBFS" | awk '{print $2}')
INTEGRATED_LUFS=$(echo "$EBUR128_OUTPUT" | grep "I:" | grep "LUFS" | awk '{print $2}')

# If empty, set as N/A
if [[ -z "$MAX_PEAK" ]]; then
  MAX_PEAK="N/A"
fi

# If empty, set as N/A
if [[ -z "$INTEGRATED_LUFS" ]]; then
  INTEGRATED_LUFS="N/A"
fi

# Apply crop, scale, pad and encode with audio
echo "Processing video: cropping to square, letterboxing, and encoding for YouTube..."

ffmpeg -y \
  -stream_loop -1 -i "$TMP_LOOP" \
  -i "$WAV_PATH" \
  -filter_complex "[0:v]crop=min(iw\,ih):min(iw\,ih):(iw-min(iw\,ih))/2:(ih-min(iw\,ih))/2,scale=1080:1080,setsar=1,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black[v]" \
  -map "[v]" -map 1:a \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -c:a libfdk_aac -b:a 320k \
  -movflags +faststart \
  -t "$AUDIO_DURATION" \
  "$OUTPUT_PATH"

# Clean up
rm -f "$TMP_VIDEO" "$TMP_TRIMMED" "$TMP_LOOP"

echo "Done! Output: $OUTPUT_PATH\n"

echo "\nAudio File Information:"
echo "======================="
echo "Duration: ${AUDIO_DURATION}s"
echo "Sample Rate: ${SAMPLE_RATE} Hz"
echo "Bit Depth: ${BIT_DEPTH} bits"
echo "Format: ${FORMAT}"
echo "Integrated Loudness: ${INTEGRATED_LUFS} LUFS"
echo "Max True Peak: ${MAX_PEAK} dBFS"
echo "=======================\n"