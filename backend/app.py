"""VidSave Backend Application Entrypoint.

Delegates directly to server.py.
"""
from __future__ import annotations

import sys
from pathlib import Path

# Add backend directory to path if accessed directly
current_dir = Path(__file__).resolve().parent
if str(current_dir) not in sys.path:
    sys.path.insert(0, str(current_dir))

from server import app, DB_PATH, API_KEY, ydl_opts, YTDLP_UNIVERSAL_OPTS  # noqa: F401

# Universal yt-dlp configuration with aggressive bot mask headers to bypass TikTok 403 barriers
ydl_opts = {
    'extractor_args': {'tiktok': {'web_search': ['']}},
    'http_headers': {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Referer': 'https://tiktok.com',
        'Origin': 'https://tiktok.com',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-site',
    }
}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8787, debug=True)
