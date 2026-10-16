#!/usr/bin/env bash
# exit on error
set -o errexit

# Python dependencies
pip install --upgrade pip
pip install -r backend/requirements.txt

# Install ffmpeg (required for audio mp3 transcoding and DASH stream merging)
mkdir -p bin
FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
echo "Downloading static ffmpeg binary..."
curl -L -s "$FFMPEG_URL" | tar -xJ --wildcards --strip-components=1 -C bin '*/ffmpeg' '*/ffprobe'
chmod +x bin/ffmpeg bin/ffprobe || true
echo "ffmpeg installation completed."
