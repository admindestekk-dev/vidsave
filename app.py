"""VidSave Backend Application Root Entrypoint.

Facilitates execution via `python app.py` from the project root.
"""
from __future__ import annotations

import sys
from pathlib import Path

backend_dir = Path(__file__).resolve().parent / "backend"
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from server import app  # noqa: F401

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8787, debug=True)
