#!/usr/bin/env bash
# Exit on error
set -o errexit

echo "===> Python bagimliliklari kuruluyor..."
python -m pip install --upgrade pip
pip install -r backend/requirements.txt

echo "===> ffmpeg kuruluyor..."
mkdir -p bin
FFMPEG_TAR="ffmpeg-release-amd64-static.tar.xz"
FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/${FFMPEG_TAR}"

if command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg zaten sistemde mevcut: $(command -v ffmpeg)"
else
    echo "Statik ffmpeg indiriliyor: $FFMPEG_URL"
    if curl -f -L --retry 3 -o "$FFMPEG_TAR" "$FFMPEG_URL"; then
        tar -xJf "$FFMPEG_TAR" --wildcards --strip-components=1 -C bin '*/ffmpeg' '*/ffprobe' || true
        rm -f "$FFMPEG_TAR"
        chmod +x bin/ffmpeg bin/ffprobe 2>/dev/null || true
        echo "ffmpeg kurulumu tamamlandi: bin/ffmpeg"
    else
        echo "UYARI: ffmpeg indirilemedi, yt-dlp temel video indirme modunda calisacak."
    fi
fi

echo "===> Build islemi basariyla tamamlandi!"

