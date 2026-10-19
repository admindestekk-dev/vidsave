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

from server import app, DB_PATH, API_KEY  # noqa: F401

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8787, debug=True)
