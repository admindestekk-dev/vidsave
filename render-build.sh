#!/usr/bin/env bash
# Exit on critical error
set -o errexit

echo "===> Python bagimliliklari kuruluyor..."
python -m pip install --upgrade pip
pip install -r requirements.txt 2>/dev/null || pip install -r backend/requirements.txt

echo "===> ffmpeg kontrol ediliyor..."
mkdir -p bin

if command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg zaten sistemde mevcut: $(command -v ffmpeg)"
else
    echo "ffmpeg binary indiriliyor (GitHub CDN)..."
    FFMPEG_ZIP="ffmpeg-linux.zip"
    FFPROBE_ZIP="ffprobe-linux.zip"
    FFMPEG_URL="https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v6.1/ffmpeg-6.1-linux-64.zip"
    FFPROBE_URL="https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v6.1/ffprobe-6.1-linux-64.zip"

    set +e
    if curl -f -s -S -L --connect-timeout 10 --max-time 90 -o "$FFMPEG_ZIP" "$FFMPEG_URL"; then
        python -m zipfile -e "$FFMPEG_ZIP" bin 2>/dev/null || unzip -o -q "$FFMPEG_ZIP" -d bin 2>/dev/null || true
        rm -f "$FFMPEG_ZIP"
        chmod +x bin/ffmpeg 2>/dev/null || true
        echo "ffmpeg basariyla kuruldu: bin/ffmpeg"
    else
        echo "UYARI: ffmpeg indirilemedi, yt-dlp temel modda devam edecek."
    fi

    if curl -f -s -S -L --connect-timeout 10 --max-time 90 -o "$FFPROBE_ZIP" "$FFPROBE_URL"; then
        python -m zipfile -e "$FFPROBE_ZIP" bin 2>/dev/null || unzip -o -q "$FFPROBE_ZIP" -d bin 2>/dev/null || true
        rm -f "$FFPROBE_ZIP"
        chmod +x bin/ffprobe 2>/dev/null || true
        echo "ffprobe basariyla kuruldu: bin/ffprobe"
    fi
    set -e
fi

# Virtualenv varsa ffmpeg ve ffprobe'u oraya da kopyala (otomatik PATH'te olmasi icin)
if [ -n "$VIRTUAL_ENV" ] && [ -d "$VIRTUAL_ENV/bin" ]; then
    cp bin/ffmpeg "$VIRTUAL_ENV/bin/" 2>/dev/null || true
    cp bin/ffprobe "$VIRTUAL_ENV/bin/" 2>/dev/null || true
fi

echo "===> Build islemi basariyla tamamlandi!"
