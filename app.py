"""VidSave Backend Application Root Entrypoint.

Facilitates execution via `python app.py` or `gunicorn app:app` from the project root.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Add backend directory to sys.path
root_dir = Path(__file__).resolve().parent
backend_dir = root_dir / "backend"
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

# Add project bin directories to PATH if present (e.g. for ffmpeg binary)
for bin_candidate in [root_dir / "bin", backend_dir / "bin", Path.home() / ".local" / "bin"]:
    if bin_candidate.is_dir() and str(bin_candidate) not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{bin_candidate}:{os.environ.get('PATH', '')}"

from server import app, ydl_opts, YTDLP_UNIVERSAL_OPTS  # noqa: F401

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8787"))
    app.run(host="0.0.0.0", port=port, debug=False)
