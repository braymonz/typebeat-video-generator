# YouTube Video Loop + Audio Mux Script

A zsh script that downloads a YouTube video, trims and loops a specific segment, then synchronizes it with a custom audio file (WAV) to create YouTube-optimized music videos.

## Features

- Downloads high-quality video from YouTube (video only, no audio)
- Extracts 9.5 seconds of video starting from custom start time
- Creates seamless forward-backward loop effect (plays forward, then reverses)
- Square crops video to 1080x1080 and letterboxes to 1920x1080 (YouTube standard)
- Loops the segment to match your audio file's duration
- Muxes with high-quality audio using libfdk_aac encoding (320kbps AAC)
- Outputs YouTube-optimized video (H.264, CRF 18, yuv420p, faststart)
- Displays detailed audio file information (sample rate, bit depth, format, integrated loudness, true peak)
- Supports timestamp formats (HH:MM:SS, MM:SS, or seconds)
- Automatically adds .mp4 extension if not present
- Supports cookie-based authentication for restricted YouTube videos

## Requirements

The script automatically checks for the following dependencies:

- **yt-dlp** - YouTube video downloader
- **ffmpeg** - Video/audio processing (with libfdk_aac support)

### Installation (macOS)

```bash
# Install yt-dlp
brew install yt-dlp

# Install ffmpeg with fdk-aac encoder
brew tap homebrew-ffmpeg/ffmpeg
brew install homebrew-ffmpeg/ffmpeg/ffmpeg --with-fdk-aac
```

## Usage

```bash
./yt_loop_mux.sh -u "YT_VIDEO_URL" -w "WAV_PATH" -o "OUTPUT_PATH" --trim-start TRIM_START [cookies-from-browser chrome]
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `-u` | Yes | YouTube video URL to download |
| `-w` | Yes | Path to audio file (WAV, MP3, FLAC, etc.) |
| `-o` | Yes | Output video file path (.mp4 extension added automatically if missing) |
| `--trim-start` | Yes | Start time for video extraction (formats: `5`, `1:30`, or `00:01:30`) |
| `cookies-from-browser` | Optional | Browser to extract cookies from (e.g., `chrome`, `firefox`) |

### Example

```bash
./yt_loop_mux.sh \
  -u "https://www.youtube.com/watch?v=dQw4w9WgXcQ" \
  -w "/Users/brayan/Music/my_beat.wav" \
  -o "/Users/brayan/Downloads/Yan Block x Dei V Type Beat - \"Trapstar\" | Traphall Type Beat 2025.mp4" \
  --trim-start 15.5 \
  cookies-from-browser chrome
```

This command will:
1. Download the video from YouTube
2. Extract 9.5 seconds starting from 15.5 seconds (15.5s to 25s)
3. Create a forward-backward loop (9.5s forward + 9.5s backward = 19s per loop)
4. Square crop to 1080x1080 and letterbox to 1920x1080
5. Loop this seamlessly to match the duration of `my_beat.wav`
6. Encode with high-quality settings optimized for YouTube
7. Output the final video to the specified path

### With Cookie Authentication (for age-restricted or private videos)

```bash
./yt_loop_mux.sh \
  -u "https://www.youtube.com/watch?v=RESTRICTED_VIDEO" \
  -w "/path/to/audio.wav" \
  -o "/path/to/output.mp4" \
  --trim-start 10 \
  cookies-from-browser chrome
```

## How It Works

1. **Dependency Check**: Verifies all required tools are installed
2. **Download**: Downloads best quality video from YouTube (video stream only)
3. **Video Extraction**: Extracts 9.5 seconds of video starting from `--trim-start`
4. **Loop Creation**: Creates forward-backward loop effect:
   - Plays extracted segment forward (9.5s)
   - Reverses and plays backward (9.5s)
   - Total loop duration: 19 seconds
5. **Audio Analysis**: Uses single EBU R128 analysis to extract all audio properties:
   - Duration (parsed from stream info)
   - Sample rate (Hz)
   - Bit depth (bits)
   - Format/codec (human-readable: WAV, MP3, AAC, FLAC, etc.)
   - Integrated loudness (LUFS - industry-standard loudness measurement)
   - Max true peak (dBFS - inter-sample peak detection)
6. **Video Processing**: 
   - Loops the forward-backward segment to match audio duration
   - Crops to centered square (1080x1080)
   - Letterboxes to 1920x1080 with black bars
7. **Encoding**: Combines video and audio with YouTube-optimized settings:
   - **Video**: H.264 codec, CRF 18 (high quality), slow preset, yuv420p pixel format
   - **Audio**: libfdk_aac encoder at 320kbps bitrate
   - **Optimization**: faststart flag for web streaming
8. **Cleanup**: Removes temporary files

## Video Quality Settings

The script uses the following settings for maximum quality and YouTube compatibility:

- **Codec**: `libx264` (H.264)
- **Quality**: `CRF 18` (visually lossless)
- **Preset**: `slow` (better compression efficiency)
- **Resolution**: Square crop to 1080x1080, letterboxed to 1920x1080
- **Pixel Format**: `yuv420p` (universal compatibility)
- **Audio**: `libfdk_aac` at 320kbps (high quality AAC)
- **Streaming**: `faststart` (optimized for web playback)
- **Loop Effect**: Forward-backward seamless loop (19 seconds per cycle)

## Troubleshooting

### "command not found: yt-dlp"
Install dependencies using the commands in the Requirements section.

### "libfdk_aac encoder not found"
Install ffmpeg with fdk-aac support:
```bash
brew tap homebrew-ffmpeg/ffmpeg
brew install homebrew-ffmpeg/ffmpeg/ffmpeg --with-fdk-aac
```

### YouTube download fails (403/429 errors)
Use the `cookies-from-browser` option to authenticate:
```bash
cookies-from-browser chrome
```

### Video and audio out of sync
Ensure your `--trim-start` value is accurate. The script extracts 9.5 seconds starting from this timestamp.

### Loop doesn't look seamless
The forward-backward loop effect creates smooth transitions. Make sure to choose a video segment with consistent motion for best results.

## Output Example

```
Downloading video from YouTube...
Extracting 9.5 seconds of video starting from 5s...
Creating forward-backward loop effect...
Analyzing audio file...

Audio File Information:
=======================
Duration: 173.33s
Sample Rate: 44100 Hz
Bit Depth: 24 bits
Format: WAV (PCM)
Integrated Loudness: -8.5 LUFS
Max True Peak: -0.2 dBFS
=======================

Processing video: looping forward-backward segment to match audio duration and encoding for YouTube...
Done! Output: /Users/brayan/Downloads/output.mp4
```

## License

Free to use and modify.
