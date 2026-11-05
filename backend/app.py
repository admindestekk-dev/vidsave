"""VidSave Backend Application Entrypoint.

Delegates directly to server.py.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any

# Add backend directory to path if accessed directly
current_dir = Path(__file__).resolve().parent
if str(current_dir) not in sys.path:
    sys.path.insert(0, str(current_dir))

# Add project bin directories to PATH if present (e.g. for ffmpeg binary)
root_dir = current_dir.parent
for bin_candidate in [root_dir / "bin", current_dir / "bin", Path.home() / ".local" / "bin"]:
    if bin_candidate.is_dir() and str(bin_candidate) not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{bin_candidate}:{os.environ.get('PATH', '')}"

from server import app, DB_PATH, API_KEY, TIKTOK_UA  # noqa: F401

# Universal yt-dlp configuration with aggressive bot mask headers to bypass CDN blocks
ydl_opts: dict[str, Any] = {
    'format': 'bestaudio/best',  # En kararlı ses akışını doğrudan yakala
    'extract_audio': True,
    'audio_format': 'mp3',
    'outtmpl': '%(title)s.%(ext)s',
    # Sunucu IP engellerini ve çerez hatalarını susturan ağ maskesi
    'no_warnings': True,
    'quiet': True,
    'cookiesfrombrowser': None,
    'http_headers': {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8',
    },
    'concurrent_fragment_downloads': 8,
    'retries': 10,
    'fragment_retries': 10,
    # Parça ve arabellek (Buffer) kalkanları: kısa videolarda akış kopmasını, uzun videolarda taşmayı önler
    'buffersize': 1024 * 16,  # Veriyi dengeli parçalarla akıtır
    'external_downloader_args': ['--min-chunk-size', '1M'],
    'hls_use_mpegts': True,  # Uzun video akışlarını parça parça korur
    'http_chunk_size': 1024 * 1024,  # 1MB dengeli parça sınırı
}
YTDLP_UNIVERSAL_OPTS: dict[str, Any] = ydl_opts

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8787"))
    app.run(host="0.0.0.0", port=port, debug=False)
