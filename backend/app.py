"""VidSave Backend Application Entrypoint.

Delegates directly to server.py.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Add backend directory to path if accessed directly
current_dir = Path(__file__).resolve().parent
if str(current_dir) not in sys.path:
    sys.path.insert(0, str(current_dir))

# Add project bin directories to PATH if present (e.g. for ffmpeg binary)
root_dir = current_dir.parent
for bin_candidate in [root_dir / "bin", current_dir / "bin", Path.home() / ".local" / "bin"]:
    if bin_candidate.is_dir() and str(bin_candidate) not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{bin_candidate}:{os.environ.get('PATH', '')}"

from server import app, DB_PATH, API_KEY, ydl_opts, YTDLP_UNIVERSAL_OPTS  # noqa: F401

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8787"))
    app.run(host="0.0.0.0", port=port, debug=False)
