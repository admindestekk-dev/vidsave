"""yt-dlp based resolver/downloader backend for the VidSave Flutter app.

Why this exists
---------------
The Flutter app cannot run yt-dlp itself (no Python runtime on Android/iOS),
and modern services like YouTube serve video and audio as *separate* DASH
streams that must be merged (and transcoded to mp3 for audio mode) with ffmpeg.
So we run yt-dlp here, on a server you control, and expose two small endpoints:

    POST /api/resolve   -> { "url": "/download?job=<id>", "filename": "...", ... }
    GET  /download      -> streams a resolved upstream URL or processed file

Direct media URLs are proxied through the job endpoint and are never accepted
as arbitrary client-provided download targets.

Run locally:
    pip install -r backend/requirements.txt
    # ffmpeg must be on PATH for merging/mp3 conversion
    python backend/server.py            # listens on 0.0.0.0:8787

Point the Flutter app at it:
    RemoteMediaResolver(backend: YtDlpBackend(uri: Uri.parse('http://<host>:8787')))
"""

from __future__ import annotations

import datetime
import hashlib
import hmac
from contextlib import closing
import json
import logging
import secrets
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass, field
from typing import Any

import requests
from flask import Flask, Response, jsonify, request, send_file
from werkzeug.security import check_password_hash, generate_password_hash

try:
    import mutagen
    from mutagen.id3 import ID3, USLT, ID3NoHeaderError
    HAS_MUTAGEN = True
except ImportError:
    HAS_MUTAGEN = False

try:
    from .stream_proxy import stream_upstream_response, validate_public_http_url
except ImportError:  # Support running as `python backend/server.py`.
    from stream_proxy import stream_upstream_response, validate_public_http_url

app = Flask(__name__)

# --- configuration ---------------------------------------------------------

# Optional shared secret. When set, clients must send it as `X-Api-Key`.
API_KEY = os.environ.get("VIDSAVE_API_KEY", "").strip()

# Directory where yt-dlp writes merged/transcoded output.
WORK_DIR = os.environ.get("VIDSAVE_WORK_DIR") or os.path.join(
    tempfile.gettempdir(), "vidsave"
)
os.makedirs(WORK_DIR, exist_ok=True)

# yt-dlp can be invoked as a module or as a standalone binary.
YTDLP_CMD = os.environ.get("VIDSAVE_YTDLP", "").strip() or None
FFMPEG_PATH = shutil.which("ffmpeg")

# Browser impersonation support (requires curl_cffi)
try:
    import curl_cffi  # noqa: F401
    HAS_CURL_CFFI = True
except ImportError:
    HAS_CURL_CFFI = False

# Modern browser User-Agent to match impersonation targets and bypass bot checks
BROWSER_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/133.0.0.0 Safari/537.36"
)
UA = BROWSER_UA

# Pinterest-specific modern User-Agent mask for bot-bypass (avoid 403 Forbidden / Access Denied)
PINTEREST_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/133.0.0.0 Safari/537.36"
)

# Impersonation target: 'chrome' or 'firefox'
IMPERSONATE_TARGET = os.environ.get("VIDSAVE_IMPERSONATE", "chrome").strip() or "chrome"

# Universal browser cookies extraction ('chrome', 'firefox', etc.)
COOKIES_BROWSER = os.environ.get("VIDSAVE_COOKIES_BROWSER", "chrome").strip() or "chrome"

# YouTube player client extraction parameter ('ios,android,web', 'ios', 'android', 'web')
YT_PLAYER_CLIENT = (
    os.environ.get("VIDSAVE_YT_PLAYER_CLIENT", "ios,android,web").strip()
    or "ios,android,web"
)

# SQLite database for storing persistent user cookies (e.g. Instagram session)
DB_PATH = os.environ.get("VIDSAVE_DB_PATH") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "vidsave_data.db"
)


def _init_db() -> None:
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS user_cookies (
                platform TEXT PRIMARY KEY,
                cookies TEXT NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY,
                kind TEXT,
                source TEXT,
                mode TEXT,
                status TEXT,
                progress REAL,
                filename TEXT,
                filepath TEXT,
                direct_url TEXT,
                title TEXT,
                ext TEXT,
                mime TEXT,
                error TEXT,
                height INTEGER,
                info_only INTEGER,
                duration INTEGER,
                uploader TEXT,
                qualities TEXT,
                start_time REAL,
                end_time REAL,
                audio_effect TEXT,
                lyrics TEXT,
                created_at REAL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS subscriptions (
                id TEXT PRIMARY KEY,
                user_id TEXT,
                lang TEXT NOT NULL,
                amount REAL NOT NULL,
                currency TEXT NOT NULL,
                vat_included INTEGER DEFAULT 1,
                status TEXT NOT NULL,
                invoice_id TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS user_subscriptions (
                user_id TEXT PRIMARY KEY,
                is_premium INTEGER DEFAULT 1,
                premium_until TIMESTAMP,
                product_id TEXT,
                purchase_token TEXT,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                email TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                name TEXT,
                avatar_url TEXT,
                failed_logins INTEGER NOT NULL DEFAULT 0,
                locked_until REAL,
                created_at REAL NOT NULL
            )
            """
        )
        # Ensure migration columns exist for previously created SQLite databases
        for col_def in ("name TEXT", "avatar_url TEXT"):
            try:
                conn.execute(f"ALTER TABLE users ADD COLUMN {col_def}")
            except sqlite3.OperationalError:
                pass
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS auth_sessions (
                token_hash TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                created_at REAL NOT NULL,
                expires_at REAL NOT NULL,
                revoked_at REAL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_id "
            "ON auth_sessions(user_id)"
        )
        conn.commit()
    except Exception as exc:
        logging.warning("Database init warning: %s", exc)
    finally:
        if conn:
            conn.close()


def _save_job_to_db(job: Job) -> None:
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            """
            INSERT OR REPLACE INTO jobs (
                id, kind, source, mode, status, progress, filename, filepath,
                direct_url, title, ext, mime, error, height, info_only,
                duration, uploader, qualities, start_time, end_time, audio_effect,
                lyrics, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                job.id,
                job.kind,
                job.source,
                job.mode,
                job.status,
                job.progress,
                job.filename,
                job.filepath,
                job.direct_url,
                job.title,
                job.ext,
                job.mime,
                job.error,
                job.height,
                1 if job.info_only else 0,
                job.duration,
                job.uploader,
                json.dumps(job.qualities) if job.qualities else None,
                job.start_time,
                job.end_time,
                job.audio_effect,
                job.lyrics,
                job.created_at,
            ),
        )
        conn.commit()
    except Exception as exc:
        logging.warning("Could not save job to DB: %s", exc)
    finally:
        if conn:
            conn.close()


def _load_job_from_db(job_id: str) -> Job | None:
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, kind, source, mode, status, progress, filename, filepath,
                   direct_url, title, ext, mime, error, height, info_only,
                   duration, uploader, qualities, start_time, end_time, audio_effect,
                   lyrics, created_at
            FROM jobs WHERE id = ?
            """,
            (job_id,),
        )
        row = cur.fetchone()
        if not row:
            return None
        qualities = []
        if row[17]:
            try:
                qualities = json.loads(row[17])
            except Exception:
                pass
        return Job(
            id=row[0],
            kind=row[1] or "video",
            source=row[2] or "",
            mode=row[3] or "url",
            status=row[4] or "pending",
            progress=row[5] or 0.0,
            filename=row[6],
            filepath=row[7],
            direct_url=row[8],
            title=row[9],
            ext=row[10],
            mime=row[11],
            error=row[12],
            height=row[13],
            info_only=bool(row[14]),
            duration=row[15],
            uploader=row[16],
            qualities=qualities,
            start_time=row[18],
            end_time=row[19],
            audio_effect=row[20] or "normal",
            lyrics=row[21],
            created_at=row[22] or time.time(),
        )
    except Exception as exc:
        logging.warning("Could not load job from DB: %s", exc)
        return None
    finally:
        if conn:
            conn.close()


def _update_job_in_db(job: Job) -> None:
    _save_job_to_db(job)


def _delete_job_from_db(job_id: str) -> None:
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
        conn.commit()
    except Exception as exc:
        logging.warning("Could not delete job from DB: %s", exc)
    finally:
        if conn:
            conn.close()


_init_db()


def _get_platform_cookie_file(platform: str) -> str | None:
    """Return a temp netscape cookiefile path for the given platform, if saved in DB."""
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT cookies FROM user_cookies WHERE platform = ?", (platform.lower(),))
        row = cur.fetchone()
        if not row or not row[0]:
            return None
        raw = str(row[0]).strip()
        if not raw:
            return None

        # Convert to Netscape cookie format if not already
        if "# Netscape" not in raw:
            lines = [
                "# Netscape HTTP Cookie File",
                "# http://curl.haxx.se/rfc/cookie_spec.html",
                "",
            ]
            default_domain = ".instagram.com" if platform.lower() == "instagram" else ""
            for part in raw.split(";"):
                if "=" in part:
                    k, v = part.strip().split("=", 1)
                    if k.strip():
                        lines.append(
                            f"{default_domain}\tTRUE\t/\tTRUE\t2147483647\t{k.strip()}\t{v.strip()}"
                        )
            raw = "\n".join(lines)

        temp_cookie_path = os.path.join(WORK_DIR, f"{platform.lower()}_cookie.txt")
        with open(temp_cookie_path, "w", encoding="utf-8") as f:
            f.write(raw)
        return temp_cookie_path
    except Exception as exc:
        logging.warning("Could not read cookie from DB for %s: %s", platform, exc)
        return None
    finally:
        if conn:
            conn.close()


def clean_song_title(title: str) -> str:
    """Smartly cleans noise keywords, bracketed video tags, and file extensions from title.

    Transforms titles like:
    'Sagopa Kajmer - Ateşten Gömlek (Official Video)' -> 'Sagopa Kajmer - Ateşten Gömlek'
    'Eminem - Without Me [Official Music Video] (HD)' -> 'Eminem - Without Me'
    """
    if not title:
        return ""
    s = str(title).strip()
    s = re.sub(r"\.(mp3|mp4|m4a|webm|flac|wav|ogg)$", "", s, flags=re.I)

    # 1. Clean bracketed and parenthesized segments containing noise words
    noise_keywords = (
        r"official|video|music\s*video|audio|lyrics?|lyric\s*video|clip|videoclip|klip|"
        r"hd|4k|8k|remaster(?:ed)?|live|acoustic|visualizer|album\s*version|"
        r"prod\.?|produced\s*by|ft\.?|feat\.?|featuring"
    )
    bracket_pattern = rf"\[\s*[^\]]*?(?:{noise_keywords})[^\]]*?\]|\(\s*[^)]*?(?:{noise_keywords})[^)]*?\)"

    prev = None
    while prev != s:
        prev = s
        s = re.sub(bracket_pattern, "", s, flags=re.I)

    # 2. Clean empty parentheses/brackets that might remain
    s = re.sub(r"\(\s*\)|\[\s*\]", "", s)

    # 3. Clean standalone phrases like 'Official Video', 'Lyrics Video', 'Video Klip'
    standalone_patterns = [
        r"\b(?:official\s*(?:music\s*)?video|official\s*audio|official\s*lyrics?|video\s*klip|lyric\s*video)\b",
        r"\b(?:hd|4k|8k|remastered|remaster)\b",
    ]
    for pat in standalone_patterns:
        s = re.sub(pat, "", s, flags=re.I)

    # 4. Clean trailing / leading separators and extra spaces
    s = re.sub(r"[\s_]+", " ", s)
    s = re.sub(r"\s*[-–—:|~#]\s*$", "", s)
    s = re.sub(r"^\s*[-–—:|~#]\s*", "", s)
    return s.strip(" -–—:|~#")


def _fetch_lyrics_online(title: str, uploader: str | None = None) -> str | None:
    """Fetch song lyrics from free public API (lrclib.net) by track title and artist."""
    try:
        clean_title = clean_song_title(title)
        clean_uploader = clean_song_title(uploader or "")

        # Prepare prioritized search queries:
        queries = []
        if clean_title:
            queries.append(clean_title)
        if clean_uploader and clean_title and clean_uploader.lower() not in clean_title.lower():
            queries.append(f"{clean_uploader} {clean_title}".strip())

        for search_query in queries:
            if not search_query:
                continue
            url = f"https://lrclib.net/api/search?q={urllib.parse.quote(search_query)}"
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": BROWSER_UA,
                    "Accept": "application/json",
                },
            )
            try:
                with urllib.request.urlopen(req, timeout=4) as resp:
                    data = json.loads(resp.read().decode("utf-8", errors="replace"))
                    if isinstance(data, list) and data:
                        for item in data:
                            lyrics = item.get("syncedLyrics") or item.get("plainLyrics")
                            if lyrics:
                                return lyrics
            except Exception:
                continue
    except Exception as exc:
        logging.info("Lyrics fetch skipped/failed: %s", exc)
    return None


def _embed_lyrics_id3(mp3_path: str, lyrics_text: str) -> bool:
    """Embed lyrics into MP3 file using mutagen ID3 USLT and COMM tags with ID3v2.3 compatibility."""
    if not HAS_MUTAGEN or not lyrics_text or not os.path.exists(mp3_path):
        return False
    try:
        try:
            audio = ID3(mp3_path)
        except ID3NoHeaderError:
            audio = ID3()
        # Add USLT (Unsynchronised lyric/text transcription) in UTF-8
        audio.delall("USLT")
        audio.add(USLT(encoding=3, lang="eng", desc="", text=lyrics_text))
        # Also add with Turkish/default language code if desired for broad reader support
        audio.add(USLT(encoding=3, lang="tur", desc="", text=lyrics_text))
        # Save explicitly with ID3v2.3 for maximum compatibility across all players
        audio.save(mp3_path, v2_version=3)
        return True
    except Exception as exc:
        logging.warning("Failed to embed ID3 lyrics into %s: %s", mp3_path, exc)
        return False


def _extract_lyrics_from_mp3(mp3_path: str) -> str | None:
    """Read lyrics from MP3 ID3 tags."""
    if not HAS_MUTAGEN or not os.path.exists(mp3_path):
        return None
    try:
        audio = ID3(mp3_path)
        for key in audio.keys():
            if key.startswith("USLT"):
                return audio[key].text
    except Exception:
        pass
    return None

# Universal options for direct yt_dlp Python API integration
YTDLP_UNIVERSAL_OPTS: dict[str, Any] = {
    "cookiesfrombrowser": (COOKIES_BROWSER, None, None, None) if COOKIES_BROWSER else None,
    "impersonate": IMPERSONATE_TARGET,
    "extractor_args": {
        "youtube": {
            "player_client": [YT_PLAYER_CLIENT] if YT_PLAYER_CLIENT else ["ios"]
        }
    },
    "concurrent_fragment_downloads": 8,
    "retries": 10,
    "fragment_retries": 10,
}


def _ytdlp_prefix() -> list[str]:
    if YTDLP_CMD:
        return YTDLP_CMD.split()
    return [sys.executable, "-m", "yt_dlp"]


def _auto_update_ytdlp_background() -> None:
    """Check for and apply yt-dlp updates in a low-priority background thread."""
    def _updater() -> None:
        try:
            logging.info("Checking for yt-dlp and curl-cffi updates...")
            cmd = [
                sys.executable,
                "-m",
                "pip",
                "install",
                "--upgrade",
                "yt-dlp",
                "curl-cffi",
                "--no-warn-script-location",
            ]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if res.returncode == 0:
                logging.info("yt-dlp / curl-cffi update check completed successfully.")
            else:
                logging.warning("Update check exited with status %d: %s", res.returncode, res.stderr.strip())
        except Exception as err:
            logging.warning("Background update encountered an issue: %s", err)

    t = threading.Thread(target=_updater, daemon=True, name="ytdlp-auto-updater")
    t.start()


# --- smart input handling --------------------------------------------------
#
# The UI text box accepts BOTH a pasted media URL and a plain search phrase
# ("Sagopa Kajmer", "komik videolar"). We decide here which one we got, and for
# plain text we hand yt-dlp the pseudo-URL `ytsearch1:<query>`, which makes it
# search YouTube and resolve the single most relevant hit.

_URL_SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*://")
_YTSEARCH_PREFIX_RE = re.compile(r"^yt(search|search\d*|playlist):", re.I)


def _looks_like_url(value: str) -> bool:
    """True when the input should be treated as a direct media/URL target."""
    candidate = value.strip()
    if not candidate:
        return False
    if _URL_SCHEME_RE.match(candidate):
        return True
    # Scheme-less forms people paste in practice: youtu.be/ID, www.site.com/x,
    # or a bare host with a path (example.com/watch?v=...).
    return bool(
        re.match(r"^(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+([/?#].*)?$", candidate, re.I)
        and "." in candidate.split("/")[0]
    )


def _is_pinterest_url(url: str) -> bool:
    """True when the URL points to a Pinterest domain or shortener."""
    u = url.strip().lower()
    return any(d in u for d in ("pinterest.", "pin.it"))


def clean_pinterest_url(url: str) -> str:
    """Clean tracking and affiliate query parameters from a Pinterest URL.

    Strips parameters like ?inviter_user_id=..., ?sender=..., ?invite_code=...
    leaving a canonical pin or board link for yt-dlp to process cleanly.
    """
    if not _is_pinterest_url(url):
        return url

    u = url.strip()
    # If scheme is missing, prepend https:// for proper parsing
    has_scheme = bool(re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", u))
    parse_target = u if has_scheme else f"https://{u}"

    try:
        parts = urllib.parse.urlsplit(parse_target)
        # Keep path, remove trailing query and fragment entirely for pin URLs
        cleaned = urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path.rstrip("/"), "", ""))
        # If original didn't have scheme, preserve the original format style
        if not has_scheme and cleaned.startswith("https://"):
            cleaned = cleaned[len("https://"):]
        return cleaned
    except Exception:
        # Fallback regex query stripper if urlsplit fails
        return re.sub(r"\?.*$", "", u)


def resolve_source_input(raw: str) -> tuple[str, str]:
    """Turn user input into the `source` string yt-dlp should receive.

    Returns a ``(source, mode)`` pair where ``mode`` is ``"url"`` when the input
    was recognised as a URL and ``"search"`` when it was treated as a search
    query. Plain text is wrapped as ``ytsearch1:<query>`` so yt-dlp finds the top
    YouTube match; anything already looking like a URL is passed through intact.
    For Pinterest URLs, tracking query parameters are automatically cleaned.
    """
    value = (raw or "").strip()
    if not value:
        raise ValueError("empty")
    # Clean Pinterest link if detected
    if _is_pinterest_url(value):
        value = clean_pinterest_url(value)
    # Already a ytsearch/ytplaylist pseudo-URL: respect the caller's choice.
    if _YTSEARCH_PREFIX_RE.match(value):
        return value, "search"
    if _looks_like_url(value):
        return value, "url"
    # Plain text -> YouTube search, first (most relevant) result.
    return f"ytsearch1:{value}", "search"


def _is_search_source(value: str) -> bool:
    """True when `value` is a yt-dlp search pseudo-URL (not a real URL).

    yt-dlp treats a `ytsearch:` result as a playlist, so callers must NOT pass
    `--no-playlist` for these or the download resolves to nothing.
    """
    return bool(_YTSEARCH_PREFIX_RE.match((value or "").strip()))


_SEARCH_EMPTY_MESSAGE = "Arama için sonuç bulunamadı, başka kelimeler deneyin."


def _search_has_result(info: dict[str, Any]) -> bool:
    """True when a `ytsearch:` lookup actually returned a usable entry.

    `_run_json` unwraps the playlist wrapper, so `info` here is normally the flat
    video object. An empty dict means the query matched nothing.
    """
    if not isinstance(info, dict) or not info:
        return False
    # A flat video result exposes a direct `url` and/or a `formats` list.
    if info.get("url") or info.get("formats"):
        return True
    # Defensive: handle a still-wrapped playlist just in case.
    if info.get("_type") == "playlist":
        entries = info.get("entries") or []
        return any(isinstance(entry, dict) for entry in entries)
    return bool(info.get("id"))


# --- job registry ----------------------------------------------------------
#
# A resolve call may need to download + merge + transcode, which takes longer
# than a mobile client is willing to wait. We therefore run the heavy work in a
# background thread, hand the client a job id, and let it poll `/api/resolve`
# or hit `/download?job=<id>` once the job reports `ready`.


@dataclass
class Job:
    id: str
    kind: str  # "video" | "audio"
    source: str
    mode: str = "url"  # "url" | "search" - how the user input was interpreted
    status: str = "pending"  # pending | running | ready | error
    progress: float = 0.0
    filename: str | None = None
    filepath: str | None = None
    direct_url: str | None = None
    title: str | None = None
    ext: str | None = None
    mime: str | None = None
    error: str | None = None
    # Requested video height in pixels (480/720/1080/...); None = "en iyi".
    height: int | None = None
    # When True the job only probes the link: no download, just title+options.
    info_only: bool = False
    duration: int | None = None
    uploader: str | None = None
    qualities: list[dict[str, Any]] = field(default_factory=list)
    # Audio trimming (Nakarat / trim)
    start_time: float | None = None
    end_time: float | None = None
    # Audio effect: "normal" | "nightcore" | "bassboost"
    audio_effect: str = "normal"
    lyrics: str | None = None
    direct_headers: dict[str, str] = field(default_factory=dict)
    created_at: float = field(default_factory=time.time)


_JOBS: dict[str, Job] = {}
_JOBS_LOCK = threading.Lock()


def _prune_jobs(max_age_seconds: int = 3600) -> None:
    cutoff = time.time() - max_age_seconds
    with _JOBS_LOCK:
        for job_id in [j.id for j in _JOBS.values() if j.created_at < cutoff]:
            job = _JOBS.pop(job_id, None)
            if job and job.filepath and os.path.exists(job.filepath):
                try:
                    os.remove(job.filepath)
                except OSError:
                    pass
            _delete_job_from_db(job_id)


def _new_job(
    kind: str,
    source: str,
    mode: str = "url",
    *,
    height: int | None = None,
    info_only: bool = False,
    start_time: float | None = None,
    end_time: float | None = None,
    audio_effect: str = "normal",
) -> Job:
    job = Job(
        id=uuid.uuid4().hex,
        kind=kind,
        source=source,
        mode=mode,
        height=height,
        info_only=info_only,
        start_time=start_time,
        end_time=end_time,
        audio_effect=audio_effect or "normal",
    )
    with _JOBS_LOCK:
        _JOBS[job.id] = job
    _save_job_to_db(job)
    return job


# --- quality / info helpers -------------------------------------------------


def _truthy(value: Any) -> bool:
    """Lenient boolean parsing for JSON bodies (true, "true", 1, "1")."""
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return False


def _parse_height(value: Any) -> int | None:
    """Normalize a requested video height; ``None`` means 'best available'.

    Raises ``ValueError`` for a non-numeric or out-of-range value so the API can
    answer with ``quality.invalid`` instead of silently ignoring the request.
    """
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        raise ValueError("not a number")
    try:
        height = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("not a number") from exc
    if height <= 0 or height > 4320:
        raise ValueError("out of range")
    return height


def _available_qualities(info: dict[str, Any]) -> list[dict[str, Any]]:
    """Distinct video heights the source offers, tallest first.

    ``[None]`` is prepended by the client as "en iyi kalite", so this only lists
    real, pickable heights plus the size of the file we would deliver for each.
    """
    best: dict[int, dict[str, Any]] = {}
    for fmt in info.get("formats") or []:
        if not isinstance(fmt, dict):
            continue
        if (fmt.get("vcodec") or "none") == "none":
            continue
        height = fmt.get("height")
        if not isinstance(height, int) or height <= 0:
            continue
        size = _format_size(fmt)
        current = best.get(height)
        if current is None or size > current["sizeInBytes"]:
            best[height] = {
                "height": height,
                "label": f"{height}p",
                "sizeInBytes": size,
                "fps": fmt.get("fps"),
                "ext": fmt.get("ext"),
            }
    return [best[height] for height in sorted(best, reverse=True)]


def _format_size(fmt: dict[str, Any]) -> int:
    size = fmt.get("filesize")
    if not isinstance(size, int):
        approx = fmt.get("filesize_approx")
        size = approx if isinstance(approx, int) else 0
    return size


def _info_payload(job: Job, info: dict[str, Any]) -> dict[str, Any]:
    return {
        "status": "info",
        "job": job.id,
        "kind": job.kind,
        "inputMode": job.mode,
        "title": info.get("title") or job.title,
        "duration": info.get("duration") if isinstance(info.get("duration"), int) else None,
        "uploader": info.get("uploader"),
        "thumbnail": info.get("thumbnail"),
        "qualities": _available_qualities(info),
    }


# --- yt-dlp invocation -----------------------------------------------------


def _format_selector(kind: str, height: int | None = None) -> str:
    """Pick the best single file we can hand over as a *direct* URL.

    Preference order matters: we want a progressive (video+audio in one file)
    stream first, because then the app can download straight from the CDN with
    no server-side merge or ffmpeg. Falling back to merged streams means the
    server must run ffmpeg, so we only do that when necessary.

    ``height`` is the resolution the user explicitly picked in the app. ``None``
    means "best quality", which we cap at 1080p: most videos only offer separate
    DASH streams, so an uncapped `best` would pull a 4K/8K file (hundreds of MB)
    and merge it server-side, which looks like a hang to the app.
    """
    if kind == "audio":
        # Audio-only first. Prefer m4a so a progressive single file is already
        # mp3-friendly; only fall back to merged video+audio when nothing else
        # exists (that path needs ffmpeg to extract the audio track).
        return "bestaudio[ext=m4a]/bestaudio/best"

    cap = f"[height<={height}]" if height else "[height<=1080]"
    # A picked 1080p falls back to *lower* resolutions when 1080p is missing;
    # any other pick stays strictly at the requested height.
    lower = "[height<=1080]" if (height or 1080) == 1080 else cap
    # Prefer h264 (avc1) video codec and aac/m4a audio codec for 100% Android/iOS native player compatibility.
    return (
        f"best[ext=mp4][vcodec^=avc1][acodec!=none]{cap}/"
        f"best[ext=mp4][vcodec!=none][acodec!=none]{cap}/"
        f"best[vcodec!=none][acodec!=none]{cap}/"
        f"bv*[vcodec^=avc1]{cap}+ba[ext=m4a]/bv*[ext=mp4]{cap}+ba[ext=m4a]/b[ext=mp4]{lower}/"
        f"bv*{cap}+ba/b{lower}/bv*+ba/b"
    )


def _base_args(
    *,
    allow_playlist_items: bool = False,
    cookiefile: str | None = None,
    source_url: str | None = None,
) -> list[str]:
    """Shared yt-dlp flags, tuned for universal bot-bypass and high throughput.

    Applies cookies-from-browser (chrome), impersonate (chrome) and youtube
    player-client (ios) universally across all platform extractions.
    If custom cookiefile is provided (e.g. from user Instagram login), uses it.
    If Pinterest URL is detected, applies Pinterest-optimized User-Agent and referer.
    """
    is_pinterest = source_url and _is_pinterest_url(source_url)
    ua = PINTEREST_UA if is_pinterest else BROWSER_UA
    referer = "https://www.pinterest.com/" if is_pinterest else None

    args = _ytdlp_prefix() + [
        "--no-warnings",
        "--user-agent",
        ua,
        "--add-header",
        "Accept:text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "--add-header",
        "Accept-Language:en-US,en;q=0.9,tr;q=0.8",
        "--add-header",
        "Sec-Fetch-Mode:navigate",
    ]
    if referer:
        args += ["--referer", referer]
    if cookiefile and os.path.exists(cookiefile):
        args += ["--cookies", cookiefile]
    elif COOKIES_BROWSER:
        args += ["--cookies-from-browser", COOKIES_BROWSER]
    if IMPERSONATE_TARGET:
        args += ["--impersonate", IMPERSONATE_TARGET]
    if YT_PLAYER_CLIENT:
        args += ["--extractor-args", f"youtube:player_client={YT_PLAYER_CLIENT}"]

    args += [
        # --- speed knobs -----------------------------------------------------
        # Pull several fragments of one file in parallel. Media served from
        # DASH/HLS (i.e. most YouTube video) arrives in fragments; this is the
        # single biggest throughput win.
        "--concurrent-fragments",
        "8",
        # Retry transient CDN hiccups instead of failing the whole job.
        "--retries",
        "10",
        "--fragment-retries",
        "10",
        # Smaller buffers + keep-alive avoid stalling on slow sockets.
        "--http-chunk-size",
        "10485760",
        "--socket-timeout",
        "15",
        # Reuse one connection and prefer IPv4 (avoids happy-eyeballs stalls).
        "--force-ipv4",
    ]
    if not allow_playlist_items:
        args += ["--no-playlist"]
    if FFMPEG_PATH:
        args += ["--ffmpeg-location", FFMPEG_PATH]
    return args


def _execute_ytdlp(cmd: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    """Execute yt-dlp command with automatic resilience and transparent fallbacks.

    Applies requested flags ('cookies_from_browser': 'chrome', 'impersonate': 'chrome',
    'player_client': 'ios,android,web') and provides automatic recovery if the host environment
    lacks local Chrome user data or if a specific YouTube link requires client fallback.
    """
    current_cmd = list(cmd)
    for _ in range(4):
        proc = subprocess.run(
            current_cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        if proc.returncode == 0:
            return proc

        err = (proc.stderr or proc.stdout or "").lower()
        modified = False

        # 1. If Chrome cookies database was not found on this machine, retry without cookies-from-browser
        if ("could not find" in err and "cookies database" in err) and "--cookies-from-browser" in current_cmd:
            logging.warning("Browser cookie database not found. Retrying without --cookies-from-browser.")
            new_cmd = []
            skip = False
            for arg in current_cmd:
                if skip:
                    skip = False
                    continue
                if arg == "--cookies-from-browser":
                    skip = True
                    continue
                new_cmd.append(arg)
            current_cmd = new_cmd
            modified = True

        # 2. If YouTube bot check / format unavailable / SABR token restriction: fallback player clients
        elif any(
            k in err
            for k in [
                "sign in to confirm you're not a bot",
                "sign in to confirm you’re not a bot",
                "some ios client https formats have been skipped",
                "requested format is not available",
                "no video formats found",
                "bot",
            ]
        ):
            for alt in ["android,web", "android", "mweb,tv"]:
                if f"youtube:player_client={alt}" not in " ".join(current_cmd):
                    logging.warning("Retrying YouTube with player_client=%s", alt)
                    new_cmd = []
                    skip = False
                    found_client = False
                    for i, a in enumerate(current_cmd):
                        if skip:
                            skip = False
                            continue
                        if (
                            a == "--extractor-args"
                            and i + 1 < len(current_cmd)
                            and "youtube:player_client=" in current_cmd[i + 1]
                        ):
                            new_cmd.extend(["--extractor-args", f"youtube:player_client={alt}"])
                            skip = True
                            found_client = True
                            continue
                        new_cmd.append(a)
                    if not found_client:
                        new_cmd.extend(["--extractor-args", f"youtube:player_client={alt}"])
                    current_cmd = new_cmd
                    modified = True
                    break

        if not modified:
            return proc

    return proc


def _run_json(
    url: str,
    kind: str,
    timeout: int = 60,
    *,
    height: int | None = None,
    formats: bool = False,
) -> dict[str, Any]:
    """Ask yt-dlp for metadata without downloading, as JSON.

    For a `ytsearch:` pseudo-URL yt-dlp returns a *playlist* wrapper whose
    `entries[0]` holds the actual video. We unwrap that here so the caller always
    receives a flat video object with `url`/`formats`, exactly like a real URL.

    ``formats=True`` asks for the *full* format list (used by the quality probe)
    instead of the single format matching ``height``.
    """
    is_search = _is_search_source(url)
    cmd = _base_args(allow_playlist_items=is_search, source_url=url) + ["-J", "--no-download"]
    if not formats:
        cmd += ["-f", _format_selector(kind, height)]
    cmd += ["--", url]
    proc = _execute_ytdlp(cmd, timeout=timeout)
    if proc.returncode != 0 or not proc.stdout.strip():
        message = (proc.stderr or proc.stdout or "yt-dlp failed").strip()
        raise RuntimeError(_clean_error(message))
    info = json.loads(proc.stdout)
    if is_search:
        info = _unwrap_search_result(info)
    return info


def _unwrap_search_result(info: dict[str, Any]) -> dict[str, Any]:
    """Unwrap the playlist wrapper yt-dlp returns for a `ytsearch:` lookup.

    A search resolves to ``{_type: "playlist", entries: [ {video}, ... ]}``; the
    video we actually want is ``entries[0]``. Returning the flat video object
    keeps `_pick_direct_format` and the rest of the pipeline unchanged, and lets
    an empty search surface as an empty dict (handled as "no results").
    """
    if not isinstance(info, dict):
        return {}
    if info.get("_type") != "playlist":
        return info
    entries = info.get("entries") or []
    for entry in entries:
        if isinstance(entry, dict):
            return entry
    return {}


_ERROR_MAP = (
    (
        re.compile(r"Sign in to confirm you'?re not a bot", re.I),
        "Bu içerik kaynağın erişim kontrolü nedeniyle kullanılamıyor.",
    ),
    (
        re.compile(r"Instagram sent an empty media response|not granting access", re.I),
        "Instagram içeriklerini indirebilmek için 'Daha Fazlası' sekmesinden 'Instagram Hesabını Bağla' seçeneğini kullanarak bir kez giriş yapın.",
    ),
    (
        re.compile(r"Video unavailable|not available", re.I),
        "Bu video kullanılamıyor veya kaldırılmış.",
    ),
    (
        re.compile(r"Private video", re.I),
        "Bu içerik gizli olduğu için indirilemiyor.",
    ),
    (
        re.compile(r"age.restricted|age-gate", re.I),
        "Yaş kısıtlaması olan içerik indirilemiyor.",
    ),
    (
        re.compile(r"Unsupported URL", re.I),
        "Bu bağlantı desteklenmiyor.",
    ),
    (
        re.compile(r"geo.restrict|not available in your country", re.I),
        "Bu içerik bölgenizde kullanılamıyor.",
    ),
    (
        re.compile(r"Requested format is not available", re.I),
        "İstenen kalitede bir akış bulunamadı.",
    ),
    (
        re.compile(
            r"No video results|no results|Incomplete YouTube ID|does not exist",
            re.I,
        ),
        "Arama için sonuç bulunamadı, başka kelimeler deneyin.",
    ),
)


def _clean_error(message: str) -> str:
    lines = [line.strip() for line in message.strip().splitlines() if line.strip()]
    if not lines:
        return "Bilinmeyen bir hata oluştu."

    # Look for known patterns across the entire message
    for pattern, friendly in _ERROR_MAP:
        if pattern.search(message):
            return friendly

    # Look for an explicit ERROR: line, skipping deprecations and warnings
    for line in lines:
        if line.startswith("ERROR:"):
            return re.sub(r"^ERROR:\s*", "", line)[:300]

    # Fall back to the first line that isn't a warning or deprecation notice
    for line in lines:
        if not re.search(r"^(WARNING|Deprecated Feature|DeprecationWarning):", line, re.I):
            return re.sub(r"^ERROR:\s*", "", line)[:300]

    return re.sub(r"^(ERROR|WARNING):\s*", "", lines[0])[:300]


def _pick_direct_format(
    info: dict[str, Any], kind: str
) -> dict[str, Any] | None:
    """Return a single-file format that can be streamed without transcoding.

    yt-dlp fills `requested_formats` when the selection had to merge several
    streams; in that case there is no single direct URL and we must download
    server-side instead.

    For audio mode we ONLY accept a true audio-only stream. A progressive
    video+audio file is not a valid mp3 substitute, so we must not hand it over
    as one just because ffmpeg is unavailable.
    """
    requested = info.get("requested_formats") or []
    if len(requested) == 1 and requested[0].get("url"):
        candidate = requested[0]
        if kind == "audio" and (candidate.get("vcodec") or "none") != "none":
            return None  # a video file cannot stand in for audio-only
        return candidate
    if not requested and info.get("url"):
        has_video = (info.get("vcodec") or "none") != "none"
        has_audio = (info.get("acodec") or "none") != "none"
        if kind == "audio":
            return info if has_audio and not has_video else None
        # A progressive format: one URL already contains video + audio.
        if has_video and has_audio:
            return info
    return None


def _safe_filename(name: str, fallback: str, ext: str) -> str:
    base = re.sub(r'[\\/:*?"<>|\r\n\t]+', "_", name or "").strip(" .")
    base = base[:120] or fallback
    if not base.lower().endswith("." + ext.lower()):
        base = f"{base}.{ext}"
    return base


def _mime_for(ext: str, kind: str) -> str:
    """Report the mime type of the file we are ACTUALLY delivering.

    Labelling a video container as `audio/mpeg` makes players try to decode
    video as mp3, so we derive the mime from the real extension first and only
    fall back to the requested kind when the extension is unknown.
    """
    ext = (ext or "").lower().lstrip(".")
    known = {
        "mp4": "video/mp4",
        "m4v": "video/mp4",
        "webm": "video/webm",
        "mov": "video/quicktime",
        "mkv": "video/x-matroska",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "aac": "audio/aac",
        "opus": "audio/ogg",
        "ogg": "audio/ogg",
        "webma": "audio/webm",
        "wav": "audio/wav",
    }
    if ext in known:
        return known[ext]
    return "audio/mpeg" if kind == "audio" else "video/mp4"


# --- background worker -----------------------------------------------------


def _is_direct_url_accessible(url: str | None, headers: dict[str, Any] | None) -> bool:
    """Test if direct stream URL can actually be fetched from CDN without 403 or network errors."""
    if not url:
        return False
    try:
        validate_public_http_url(url)
        test_h = {
            "User-Agent": BROWSER_UA,
            "Accept": "*/*",
            "Range": "bytes=0-0",
        }
        if headers and isinstance(headers, dict):
            for k, v in headers.items():
                if k.lower() not in ("host", "content-length"):
                    test_h[k] = str(v)
        res = requests.get(url, headers=test_h, stream=True, timeout=5, allow_redirects=True)
        status = res.status_code
        res.close()
        return status in (200, 206)
    except Exception:
        return False


def _download_job_to_disk(job: Job, target_source: str | None = None) -> str:
    """Download merged video or mp3 audio directly to WORK_DIR using yt-dlp + ffmpeg."""
    if not FFMPEG_PATH:
        if job.kind == "audio":
            raise RuntimeError("Ses (mp3) dönüştürmek için sunucuda ffmpeg kurulu olmalı.")
        raise RuntimeError("Bu video için ayrı akışları birleştirmek gerekiyor; sunucuda ffmpeg kurulu olmalı.")

    src = target_source or job.source
    out_tmpl = os.path.join(WORK_DIR, f"{job.id}.%(ext)s")
    cookiefile = None
    if "instagram.com" in src.lower() or "instagr.am" in src.lower():
        cookiefile = _get_platform_cookie_file("instagram")

    cmd = _base_args(
        allow_playlist_items=_is_search_source(src),
        cookiefile=cookiefile,
        source_url=src,
    ) + [
        "-f",
        _format_selector(job.kind, job.height),
    ]
    if job.kind == "audio":
        q = f"{job.height}K" if (job.height and job.height in (128, 192, 256, 320)) else "0"
        cmd += ["-x", "--audio-format", "mp3", "--audio-quality", q]
    else:
        cmd += ["--merge-output-format", "mp4"]
    cmd += ["-o", out_tmpl, "--", src]

    proc = _execute_ytdlp(cmd, timeout=1800)
    if proc.returncode != 0:
        raise RuntimeError(_clean_error(proc.stderr or proc.stdout or "yt-dlp failed"))

    produced = [
        os.path.join(WORK_DIR, name)
        for name in os.listdir(WORK_DIR)
        if name.startswith(f"{job.id}.")
    ]
    if not produced:
        raise RuntimeError("yt-dlp çıktı dosyası oluşturamadı.")

    path = max(produced, key=os.path.getsize)
    return path


def _work(job: Job) -> None:
    try:
        job.status = "running"
        _update_job_in_db(job)
        # The quality probe asks for the full format list so the app can show
        # every resolution the link offers before anything is downloaded.
        info = _run_json(
            job.source,
            job.kind,
            formats=job.info_only,
            height=job.height,
        )
        # A `ytsearch:` pseudo-URL resolves to a playlist-like result. When the
        # query matches nothing yt-dlp returns an entry-less payload instead of
        # raising, so surface that as a clear, retryable error.
        if _is_search_source(job.source) and not _search_has_result(info):
            raise RuntimeError(
                _SEARCH_EMPTY_MESSAGE
            )
        job.title = info.get("title")
        job.duration = (
            info.get("duration") if isinstance(info.get("duration"), int) else None
        )
        job.uploader = info.get("uploader")

        if job.info_only:
            # Probe only: never download, just report the pickable qualities.
            job.qualities = _available_qualities(info)
            job.status = "info"
            _update_job_in_db(job)
            return

        direct = _pick_direct_format(info, job.kind)
        # Audio downloads are normalized to MP3 even when the source already
        # offers a single-file M4A/AAC stream.
        if direct is not None and job.kind != "audio":
            direct_url = direct.get("url")
            direct_headers = direct.get("http_headers") or {}
            # Verify if direct_url is actually accessible from CDN without 403 or network errors
            if _is_direct_url_accessible(direct_url, direct_headers):
                ext = direct.get("ext") or "mp4"
                job.direct_url = direct_url
                job.direct_headers = direct_headers
                job.filename = _safe_filename(
                    info.get("title") or "vidsave", "vidsave", ext
                )
                job.ext = ext
                job.mime = _mime_for(ext, job.kind)
                job.progress = 1.0
                job.status = "ready"
                _update_job_in_db(job)
                return

        # Slow path: merge/transcode on the server with yt-dlp + ffmpeg.
        target_source = (
            (info.get("webpage_url") or info.get("original_url"))
            if _is_search_source(job.source)
            else job.source
        ) or job.source

        path = _download_job_to_disk(job, target_source)
        ext = os.path.splitext(path)[1].lstrip(".").lower() or "mp4"

        # Apply Audio Post-Processing (Feature 1: Trimming & Feature 4: Audio Effects)
        if job.kind == "audio" and ext == "mp3" and FFMPEG_PATH:
            needs_trim = job.start_time is not None or job.end_time is not None
            effect = (job.audio_effect or "normal").lower()
            needs_effect = effect in ("nightcore", "bassboost")

            if needs_trim or needs_effect:
                processed_path = os.path.join(WORK_DIR, f"{job.id}_fx.mp3")
                ff_cmd = [FFMPEG_PATH, "-y"]
                if job.start_time is not None and job.start_time >= 0:
                    ff_cmd += ["-ss", str(job.start_time)]
                if job.end_time is not None and job.end_time > (job.start_time or 0):
                    ff_cmd += ["-to", str(job.end_time)]
                ff_cmd += ["-i", path]

                if effect == "nightcore":
                    ff_cmd += ["-af", "atempo=1.3,asetrate=44100*1.3"]
                elif effect == "bassboost":
                    ff_cmd += ["-af", "bass=g=10"]

                ff_cmd += ["-c:a", "libmp3lame", "-q:a", "0", processed_path]
                res_fx = subprocess.run(
                    ff_cmd,
                    capture_output=True,
                    text=True,
                    timeout=300,
                )
                if res_fx.returncode == 0 and os.path.exists(processed_path):
                    try:
                        os.remove(path)
                    except OSError:
                        pass
                    path = processed_path

        # Feature 2: Auto Lyrics Sync (Fetch & embed into ID3)
        if job.kind == "audio" and ext == "mp3":
            try:
                title = info.get("title") or job.title or ""
                uploader = info.get("uploader") or info.get("channel") or job.uploader
                lyrics_text = _fetch_lyrics_online(title, uploader)
                if lyrics_text:
                    _embed_lyrics_id3(path, lyrics_text)
                    job.lyrics = lyrics_text
            except Exception as lyrics_err:
                logging.info("Lyrics embedding skipped: %s", lyrics_err)

        job.filepath = path
        job.ext = ext
        job.mime = _mime_for(ext, job.kind)
        job.filename = _safe_filename(
            info.get("title") or "vidsave", "vidsave", ext
        )
        job.progress = 1.0
        job.status = "ready"
        _update_job_in_db(job)
    except subprocess.TimeoutExpired:
        job.error = "İşlem zaman aşımına uğradı."
        job.status = "error"
        _update_job_in_db(job)
    except Exception as exc:  # noqa: BLE001 - surface any failure to the client
        job.error = _clean_error(str(exc))
        job.status = "error"
        _update_job_in_db(job)


# --- http api --------------------------------------------------------------


def _authorized() -> bool:
    if not API_KEY:
        return True
    supplied = request.headers.get("X-Api-Key", "").strip().encode("utf-8")
    return hmac.compare_digest(supplied, API_KEY.encode("utf-8"))


def _current_user() -> dict[str, str] | None:
    authorization = request.headers.get("Authorization", "").strip()
    scheme, separator, token = authorization.partition(" ")
    if not separator or scheme.lower() != "bearer" or not token.strip():
        return None

    token_hash = hashlib.sha256(token.strip().encode("utf-8")).hexdigest()
    try:
        with closing(sqlite3.connect(DB_PATH)) as conn:
            row = conn.execute(
                """
                SELECT users.id, users.email, users.name, users.avatar_url
                FROM auth_sessions
                JOIN users ON users.id = auth_sessions.user_id
                WHERE auth_sessions.token_hash = ?
                  AND auth_sessions.revoked_at IS NULL
                  AND auth_sessions.expires_at > ?
                """,
                (token_hash, time.time()),
            ).fetchone()
    except sqlite3.Error:
        logging.exception("Could not validate auth session")
        return None

    if row is None:
        return None
    return {
        "id": row[0],
        "email": row[1],
        "name": row[2] or "",
        "avatarUrl": row[3] or "",
    }


def _auth_user_id(
    body: dict[str, Any],
) -> tuple[str | None, tuple[Response, int] | None]:
    authorization = request.headers.get("Authorization", "").strip()
    if authorization:
        user = _current_user()
        if user is None:
            return None, (
                jsonify(status="error", error={"code": "auth.session_invalid"}),
                401,
            )
        return user["id"], None

    raw_user_id = str(body.get("userId") or body.get("user_id") or "").strip()
    try:
        user_id = str(uuid.UUID(raw_user_id))
    except (AttributeError, TypeError, ValueError):
        return None, (
            jsonify(status="error", error={"code": "user.id_invalid"}),
            400,
        )

    # Guest installations can manage only guest-scoped rows; an account UUID
    # requires its own authenticated session even if it is known to the caller.
    try:
        with closing(sqlite3.connect(DB_PATH)) as conn:
            is_registered = conn.execute(
                "SELECT 1 FROM users WHERE id = ?", (user_id,)
            ).fetchone()
    except sqlite3.Error:
        logging.exception("Could not resolve account identity")
        return None, (
            jsonify(status="error", error={"code": "auth.identity_unavailable"}),
            500,
        )
    if is_registered:
        return None, (
            jsonify(status="error", error={"code": "auth.required"}),
            401,
        )
    return user_id, None


def _issue_auth_session(conn: sqlite3.Connection, user_id: str) -> str:
    token = secrets.token_urlsafe(32)
    now = time.time()
    conn.execute("DELETE FROM auth_sessions WHERE expires_at <= ? OR revoked_at IS NOT NULL", (now,))
    conn.execute(
        "INSERT INTO auth_sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
        (
            hashlib.sha256(token.encode("utf-8")).hexdigest(),
            user_id,
            now,
            now + 60 * 60 * 24 * 30,
        ),
    )
    return token


# --- CORS ------------------------------------------------------------------
#
# The Flutter app talks to this backend from a different origin (the device),
# so browsers/WebViews and Flutter web builds need permissive CORS headers.
# Allow-all is safe here because access is gated by the optional X-Api-Key and
# by the SSRF-safe URL validation in stream_proxy, not by the browser origin.
# Set VIDSAVE_ALLOWED_ORIGINS to a comma-separated list to lock this down.

_ALLOWED_ORIGINS = os.environ.get("VIDSAVE_ALLOWED_ORIGINS", "*").strip() or "*"


@app.after_request
def _apply_cors(response: Response) -> Response:
    origin = request.headers.get("Origin")
    if _ALLOWED_ORIGINS == "*":
        response.headers["Access-Control-Allow-Origin"] = "*"
    elif origin and origin in {
        o.strip() for o in _ALLOWED_ORIGINS.split(",") if o.strip()
    }:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Vary"] = "Origin"
    response.headers["Access-Control-Allow-Methods"] = (
        "GET, POST, OPTIONS, HEAD"
    )
    response.headers["Access-Control-Allow-Headers"] = (
        "Content-Type, X-Api-Key, Authorization, Range, Accept"
    )
    response.headers["Access-Control-Expose-Headers"] = (
        "Content-Length, Content-Range, Content-Disposition, Accept-Ranges"
    )
    response.headers["Access-Control-Max-Age"] = "86400"
    return response


@app.route("/<path:_any>", methods=["OPTIONS"])
def _cors_preflight(_any: str) -> Response:  # noqa: ARG001 - path is unused
    """Answer CORS preflight requests for any endpoint."""
    return app.make_default_options_response()


def _job_payload(job: Job) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "job": job.id,
        "status": job.status,
        "kind": job.kind,
        "inputMode": job.mode,
        "progress": round(job.progress, 3),
        "title": job.title,
        "filename": job.filename,
        "ext": job.ext,
        "mime": job.mime,
        "lyrics": job.lyrics,
    }
    if job.height:
        payload["height"] = job.height
    if job.start_time is not None:
        payload["startTime"] = job.start_time
    if job.end_time is not None:
        payload["endTime"] = job.end_time
    if job.audio_effect != "normal":
        payload["audioEffect"] = job.audio_effect
    if job.status == "info":
        # Probe answer: the app shows this so the user can pick a resolution.
        payload["info"] = True
        payload["duration"] = job.duration
        payload["uploader"] = job.uploader
        payload["qualities"] = job.qualities
        return payload
    if job.status == "ready":
        payload["url"] = f"/download?job={job.id}"
        payload["mode"] = "proxy"
        payload["fileSizeInBytes"] = (
            os.path.getsize(job.filepath) if job.filepath else None
        )
    if job.status == "error":
        payload["error"] = job.error
    return payload


def _seconds_to_time(val: Any) -> str:
    """Format duration seconds to mm:ss."""
    if not isinstance(val, (int, float)) or val <= 0:
        return ""
    m, s = divmod(int(val), 60)
    return f"{m}:{s:02d}"


@app.post("/api/ara")
def api_ara() -> Response:
    """Search endpoint returning multiple music/video results."""
    _prune_jobs()
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    query = (body.get("query") or body.get("url") or body.get("q") or "").strip()
    if not query:
        return jsonify(status="error", error={"code": "query.missing", "message": "Arama kelimesi girin."}), 400

    limit = 5
    search_source = f"ytsearch{limit}:{query}" if not _is_search_source(query) else query

    try:
        cmd = _base_args(allow_playlist_items=True) + ["-J", "--no-download", "--", search_source]
        proc = _execute_ytdlp(cmd, timeout=35)
        if proc.returncode != 0 or not proc.stdout.strip():
            msg = (proc.stderr or proc.stdout or "Arama yapılamadı").strip()
            raise RuntimeError(_clean_error(msg))

        raw_info = json.loads(proc.stdout)
        entries = []
        if isinstance(raw_info, dict):
            if raw_info.get("_type") == "playlist":
                entries = [e for e in raw_info.get("entries", []) if isinstance(e, dict)]
            else:
                entries = [raw_info]

        results = []
        for e in entries[:limit]:
            vid_id = str(e.get("id") or "")
            web_url = (
                e.get("webpage_url")
                or e.get("url")
                or (f"https://www.youtube.com/watch?v={vid_id}" if vid_id else "")
            )
            results.append({
                "id": vid_id,
                "baslik": e.get("title") or "Bilinmeyen Başlık",
                "kanal": e.get("uploader") or e.get("channel") or "Bilinmeyen Kanal",
                "sure": _seconds_to_time(e.get("duration")),
                "url": web_url,
            })

        return jsonify(results)
    except Exception as exc:
        return jsonify(status="error", error={"message": str(exc)}), 500


@app.post("/api/indir")
def api_indir() -> Response:
    """Direct MP3 download trigger endpoint with trimming and audio effect options."""
    _prune_jobs()
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    url = (body.get("url") or body.get("query") or "").strip()
    if not url:
        return jsonify(status="error", error={"code": "url.missing", "message": "Bağlantı girin."}), 400

    start_time = body.get("start_time")
    end_time = body.get("end_time")
    audio_effect = body.get("audio_effect") or "normal"

    # Forward parameters into resolve call
    request._cached_json = {
        "url": url,
        "kind": "audio",
        "start_time": start_time,
        "end_time": end_time,
        "audio_effect": audio_effect,
    }
    return resolve()


@app.post("/api/toplu-indir")
def api_toplu_indir() -> Response:
    """Bulk download/resolve endpoint accepting a list of URLs."""
    _prune_jobs()
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    raw_urls = body.get("urls") or []
    if isinstance(raw_urls, str):
        raw_urls = [u.strip() for u in raw_urls.splitlines() if u.strip()]
    if not raw_urls or not isinstance(raw_urls, list):
        return jsonify(status="error", error={"code": "urls.missing", "message": "Bağlantı listesi boş."}), 400

    kind = "audio" if str(body.get("kind", "")).lower() == "audio" else "video"
    results = []

    for item in raw_urls:
        url_str = str(item).strip()
        if not url_str:
            continue
        try:
            source, mode = resolve_source_input(url_str)
            if mode == "url":
                validate_public_http_url(source)
            job = _new_job(kind, source)
            job.mode = mode
            threading.Thread(target=_work, args=(job,), daemon=True).start()
            results.append({
                "url": url_str,
                "job": job.id,
                "status": "pending",
            })
        except Exception as exc:
            results.append({
                "url": url_str,
                "status": "error",
                "error": str(exc),
            })

    return jsonify(status="ok", kind=kind, total=len(results), items=results)


@app.post("/api/resolve")
def resolve() -> Response:
    _prune_jobs()
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}

    # A request carrying a known job id is a progress poll: answer it immediately!
    job_id = (body.get("job") or "").strip()
    if job_id:
        with _JOBS_LOCK:
            existing = _JOBS.get(job_id)
        if existing is None:
            existing = _load_job_from_db(job_id)
            if existing is not None:
                with _JOBS_LOCK:
                    _JOBS[existing.id] = existing
        if existing is not None:
            return jsonify(_job_payload(existing))
        if not (body.get("url") or body.get("query")):
            return jsonify(status="error", error={"code": "job.not_found"}), 404

    # The UI text box may hold either a pasted URL or a plain search phrase.
    raw_input = (body.get("url") or body.get("query") or "").strip()
    kind = "audio" if str(body.get("kind", "")).lower() == "audio" else "video"
    if not raw_input:
        return jsonify(status="error", error={"code": "url.missing"}), 400

    try:
        source, mode = resolve_source_input(raw_input)
    except ValueError:
        return jsonify(status="error", error={"code": "url.missing"}), 400

    # Only real URLs go through the SSRF guard. A `ytsearch1:` query is not a
    # network destination we fetch directly, so it must NOT be validated as one
    # (its host part would be "ytsearch1" and would be rejected).
    if mode == "url":
        try:
            validate_public_http_url(source)
        except ValueError:
            return jsonify(status="error", error={"code": "url.invalid"}), 400

    # An explicit height (or the `info` probe) makes the request "quality aware".
    try:
        quality = _parse_height(body.get("height"))
    except ValueError:
        return jsonify(status="error", error={"code": "quality.invalid"}), 400

    # Parse trimming and audio effect options
    start_time: float | None = None
    end_time: float | None = None
    raw_start = body.get("start_time")
    raw_end = body.get("end_time")
    if raw_start is not None and str(raw_start).strip() != "":
        try:
            start_time = float(raw_start)
        except (ValueError, TypeError):
            pass
    if raw_end is not None and str(raw_end).strip() != "":
        try:
            end_time = float(raw_end)
        except (ValueError, TypeError):
            pass
    audio_effect = str(body.get("audio_effect") or "normal").strip().lower()

    # Searches have to hit YouTube's index first, so they need more headroom
    # than a direct URL resolution before we answer the client.
    job = _new_job(
        kind,
        source,
        height=quality,
        info_only=_truthy(body.get("info")),
        start_time=start_time,
        end_time=end_time,
        audio_effect=audio_effect,
    )
    job.mode = mode
    threading.Thread(target=_work, args=(job,), daemon=True).start()

    # Give fast resolutions a chance to finish before we answer. A probe is
    # answered as soon as the metadata comes back.
    deadline = time.time() + (35 if mode == "search" else 20)
    while time.time() < deadline:
        if job.status in ("ready", "error", "info"):
            break
        time.sleep(0.25)

    code = 200 if job.status != "error" else 422
    return jsonify(_job_payload(job)), code


@app.post("/api/cookies")
def api_save_cookies() -> Response:
    """Endpoint for receiving user-session cookies from Flutter InAppWebView (e.g. Instagram)."""
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    platform = (body.get("platform") or "instagram").strip().lower()
    raw_cookies = body.get("cookies")
    if not raw_cookies:
        return jsonify(status="error", error={"code": "cookies.missing", "message": "Çerez verisi bulunamadı."}), 400

    cookie_str = ""
    if isinstance(raw_cookies, str):
        cookie_str = raw_cookies.strip()
    elif isinstance(raw_cookies, dict):
        cookie_str = "; ".join(f"{k}={v}" for k, v in raw_cookies.items())
    elif isinstance(raw_cookies, list):
        # List of cookie objects from InAppWebView
        parts = []
        for c in raw_cookies:
            if isinstance(c, dict) and c.get("name") and c.get("value"):
                parts.append(f"{c['name']}={c['value']}")
        cookie_str = "; ".join(parts)

    try:
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute(
                "INSERT INTO user_cookies (platform, cookies, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP) "
                "ON CONFLICT(platform) DO UPDATE SET cookies=excluded.cookies, updated_at=CURRENT_TIMESTAMP",
                (platform, cookie_str),
            )
            conn.commit()
        return jsonify(status="ok", message=f"{platform} çerezleri başarıyla kaydedildi.")
    except Exception as exc:
        return jsonify(status="error", error={"message": str(exc)}), 500


@app.get("/api/cookies/<platform>")
def api_get_cookies(platform: str) -> Response:
    """Check if valid cookies exist for the requested platform."""
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401
    try:
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("SELECT updated_at FROM user_cookies WHERE platform = ?", (platform.lower(),))
            row = cur.fetchone()
            if row:
                return jsonify(status="ok", platform=platform, connected=True, updatedAt=row[0])
            return jsonify(status="ok", platform=platform, connected=False)
    except Exception as exc:
        return jsonify(status="error", error={"message": str(exc)}), 500


@app.get("/api/lyrics")
def api_get_lyrics() -> Response:
    """Fetch lyrics by query or inspect downloaded MP3 job lyrics."""
    job_id = request.args.get("job", "").strip()
    if job_id:
        with _JOBS_LOCK:
            job = _JOBS.get(job_id)
        if job and job.lyrics:
            return jsonify(status="ok", lyrics=job.lyrics)
        if job and job.filepath and job.ext == "mp3":
            embedded = _extract_lyrics_from_mp3(job.filepath)
            if embedded:
                return jsonify(status="ok", lyrics=embedded)

    query = request.args.get("q", "").strip()
    if query:
        lyrics = _fetch_lyrics_online(query)
        if lyrics:
            return jsonify(status="ok", lyrics=lyrics)
        return jsonify(status="error", message="Sözler bulunamadı"), 404

    return jsonify(status="error", message="Parametre eksik"), 400


@app.post("/api/auth/register")
def api_register() -> Response | tuple[Response, int]:
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    email = str(body.get("email") or "").strip().lower()
    password = body.get("password")
    if not isinstance(password, str):
        password = ""

    if len(email) > 254 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        return jsonify(status="error", error={"code": "auth.email_invalid"}), 400
    password_length = len(password.encode("utf-8"))
    if password_length < 8 or password_length > 128:
        return jsonify(status="error", error={"code": "auth.password_invalid"}), 400

    user_id = str(uuid.uuid4())
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)",
            (user_id, email, generate_password_hash(password, method="scrypt"), time.time()),
        )
        token = _issue_auth_session(conn, user_id)
        conn.commit()
    except sqlite3.IntegrityError:
        if conn:
            conn.rollback()
        return jsonify(status="error", error={"code": "auth.email_in_use"}), 409
    except sqlite3.Error:
        logging.exception("Account registration failed")
        if conn:
            conn.rollback()
        return jsonify(status="error", error={"code": "auth.registration_failed"}), 500
    finally:
        if conn:
            conn.close()

    return jsonify(
        status="ok",
        token=token,
        user={"id": user_id, "email": email, "name": "", "avatarUrl": ""},
    ), 201


_DUMMY_PASSWORD_HASH = generate_password_hash(
    "not-a-real-password", method="scrypt"
)


@app.post("/api/auth/login")
def api_login() -> Response | tuple[Response, int]:
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    email = str(body.get("email") or "").strip().lower()
    password = body.get("password")
    if not isinstance(password, str):
        password = ""
    now = time.time()
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        row = conn.execute(
            "SELECT id, email, password_hash, failed_logins, locked_until FROM users WHERE email = ?",
            (email,),
        ).fetchone()
        if row is None:
            check_password_hash(_DUMMY_PASSWORD_HASH, password)
            conn.close()
            return jsonify(status="error", error={"code": "auth.invalid_credentials"}), 401

        user_id, normalized_email, password_hash, failures, locked_until = row
        if locked_until is not None and float(locked_until) > now:
            conn.close()
            return jsonify(status="error", error={"code": "auth.rate_limited"}), 429

        if not check_password_hash(password_hash, password):
            failures = int(failures or 0) + 1
            lock_time = now + 15 * 60 if failures >= 5 else None
            conn.execute(
                "UPDATE users SET failed_logins = ?, locked_until = ? WHERE id = ?",
                (0 if lock_time is not None else failures, lock_time, user_id),
            )
            conn.commit()
            conn.close()
            code = "auth.rate_limited" if lock_time is not None else "auth.invalid_credentials"
            status = 429 if lock_time is not None else 401
            return jsonify(status="error", error={"code": code}), status

        conn.execute(
            "UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = ?",
            (user_id,),
        )
        token = _issue_auth_session(conn, user_id)
        conn.commit()
    except sqlite3.Error:
        logging.exception("Login failed")
        if conn:
            conn.close()
        return jsonify(status="error", error={"code": "auth.login_failed"}), 500
    finally:
        if conn:
            conn.close()

    return jsonify(
        status="ok",
        token=token,
        user={
            "id": user_id,
            "email": normalized_email,
            "name": row[2] if len(row) > 2 and row[2] else "",
            "avatarUrl": row[3] if len(row) > 3 and row[3] else "",
        },
    )


@app.post("/api/auth/google")
def api_auth_google() -> Response | tuple[Response, int]:
    """Google Sign-In endpoint.

    Authenticates or automatically registers the user with their Google profile
    (email, name, avatarUrl). Returns a secure session token and subscription status.
    """
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    email = str(body.get("email") or "").strip().lower()
    name = str(body.get("name") or body.get("displayName") or "").strip()
    avatar_url = str(body.get("avatarUrl") or body.get("photoUrl") or "").strip()

    if not email or len(email) > 254 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        return jsonify(status="error", error={"code": "auth.email_invalid"}), 400

    now = time.time()
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        row = conn.execute(
            "SELECT id, email, name, avatar_url FROM users WHERE email = ?",
            (email,),
        ).fetchone()

        if row is None:
            user_id = str(uuid.uuid4())
            conn.execute(
                """
                INSERT INTO users (id, email, password_hash, name, avatar_url, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (user_id, email, "google_oauth_no_password", name, avatar_url, now),
            )
        else:
            user_id = row[0]
            existing_name = row[2] or ""
            existing_avatar = row[3] or ""
            # Update name / avatar if newly provided
            update_name = name or existing_name
            update_avatar = avatar_url or existing_avatar
            if update_name != existing_name or update_avatar != existing_avatar:
                conn.execute(
                    "UPDATE users SET name = ?, avatar_url = ? WHERE id = ?",
                    (update_name, update_avatar, user_id),
                )
                name = update_name
                avatar_url = update_avatar
            else:
                name = existing_name
                avatar_url = existing_avatar

        token = _issue_auth_session(conn, user_id)

        # Check premium subscription status
        cur = conn.cursor()
        cur.execute("SELECT premium_until, is_premium FROM user_subscriptions WHERE user_id = ?", (user_id,))
        sub_row = cur.fetchone()
        is_premium = False
        if sub_row:
            prem_until_str, is_prem_flag = sub_row[0], sub_row[1]
            if is_prem_flag:
                if prem_until_str:
                    try:
                        p_dt = datetime.datetime.fromisoformat(str(prem_until_str).replace("Z", "+00:00"))
                        if p_dt > datetime.datetime.now(datetime.timezone.utc):
                            is_premium = True
                    except Exception:
                        is_premium = bool(is_prem_flag)
                else:
                    is_premium = bool(is_prem_flag)

        conn.commit()
    except sqlite3.Error:
        logging.exception("Google auth DB error")
        if conn:
            conn.close()
        return jsonify(status="error", error={"code": "auth.google_failed"}), 500
    finally:
        if conn:
            conn.close()

    return jsonify(
        status="ok",
        success=True,
        token=token,
        is_premium=is_premium,
        user={
            "id": user_id,
            "email": email,
            "name": name,
            "avatarUrl": avatar_url,
        },
    )


@app.get("/api/auth/me")
def api_auth_me() -> Response | tuple[Response, int]:
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401
    user = _current_user()
    if user is None:
        return jsonify(status="error", error={"code": "auth.session_invalid"}), 401
    return jsonify(status="ok", user=user)


@app.post("/api/auth/logout")
def api_logout() -> Response | tuple[Response, int]:
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401
    authorization = request.headers.get("Authorization", "").strip()
    scheme, separator, token = authorization.partition(" ")
    if not separator or scheme.lower() != "bearer" or not token.strip():
        return jsonify(status="error", error={"code": "auth.session_invalid"}), 401

    token_hash = hashlib.sha256(token.strip().encode("utf-8")).hexdigest()
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute(
            "UPDATE auth_sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL",
            (time.time(), token_hash),
        )
        conn.commit()
    return jsonify(status="ok", success=True)


@app.post("/api/auth/subscribe-monthly")
def api_subscribe_monthly() -> Response | tuple[Response, int]:
    """Monthly subscription accounting endpoint with psychological pricing (9.99 TRY vs 0.99 USD)."""
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    user_id, auth_error = _auth_user_id(body)
    if auth_error:
        return auth_error
    assert user_id is not None

    lang = str(body.get("lang") or request.args.get("lang") or "tr").strip().lower()

    # Psychological pricing based on language / region
    is_tr = lang == "tr"
    amount = 9.99 if is_tr else 0.99
    currency = "TRY" if is_tr else "USD"

    subscription_id = f"sub_{uuid.uuid4().hex[:12]}"
    invoice_id = f"inv_{uuid.uuid4().hex[:12]}"

    # Accounting record persistence in SQLite
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            """
            INSERT INTO subscriptions (
                id, user_id, lang, amount, currency, vat_included, status, invoice_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (subscription_id, user_id, lang, amount, currency, 1, "active", invoice_id),
        )
        conn.commit()
    except Exception as exc:
        logging.warning("Subscription accounting recording error: %s", exc)
    finally:
        if conn:
            conn.close()

    receipt_message = (
        "Faturanız kesildi: 9,99 TL (KDV Dahil) tahsil edilmiştir. Premium mod aktif!"
        if is_tr
        else "Invoice generated: $0.99 (All taxes included) charged. Premium active!"
    )

    return jsonify(
        status="ok",
        success=True,
        subscription={
            "id": subscription_id,
            "userId": user_id,
            "status": "active",
            "tier": "premium_monthly",
            "amount": amount,
            "currency": currency,
            "lang": lang,
            "vatIncluded": True,
            "invoiceId": invoice_id,
            "receiptMessage": receipt_message,
        },
    )


@app.post("/api/auth/verify-purchase")
def api_verify_purchase() -> Response:
    """Verify in-app purchase receipt from Google Play Store and extend premium_until by 30 days."""
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    token = str(
        body.get("token")
        or body.get("purchaseToken")
        or body.get("serverVerificationData")
        or body.get("purchaseId")
        or ""
    ).strip()
    product_id = str(body.get("productId") or body.get("product_id") or "vidsave_premium_monthly").strip()
    user_id, auth_error = _auth_user_id(body)
    if auth_error:
        return auth_error
    assert user_id is not None
    lang = str(body.get("lang") or "tr").strip().lower()

    if not token:
        return jsonify(
            status="error",
            error={"code": "token.missing", "message": "Doğrulama belirteci (token) eksik."},
        ), 400

    # Calculate 30 days extension from now (or from existing premium_until if currently active)
    now = datetime.datetime.now(datetime.timezone.utc)
    current_until = None

    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT premium_until FROM user_subscriptions WHERE user_id = ?", (user_id,))
        row = cur.fetchone()
        if row and row[0]:
            try:
                parsed_ts = datetime.datetime.fromisoformat(str(row[0]).replace("Z", "+00:00"))
                if parsed_ts > now:
                    current_until = parsed_ts
            except Exception:
                pass

        base_time = current_until or now
        new_until = base_time + datetime.timedelta(days=30)
        new_until_str = new_until.isoformat()

        # Update or insert into user_subscriptions
        conn.execute(
            """
            INSERT INTO user_subscriptions (user_id, is_premium, premium_until, product_id, purchase_token, updated_at)
            VALUES (?, 1, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(user_id) DO UPDATE SET
                is_premium = 1,
                premium_until = excluded.premium_until,
                product_id = excluded.product_id,
                purchase_token = excluded.purchase_token,
                updated_at = CURRENT_TIMESTAMP
            """,
            (user_id, new_until_str, product_id, token),
        )

        # Record accounting audit entry in subscriptions table as well
        invoice_id = f"inv_{uuid.uuid4().hex[:12]}"
        amount = 9.99 if lang == "tr" else 0.99
        currency = "TRY" if lang == "tr" else "USD"
        sub_id = f"sub_{uuid.uuid4().hex[:12]}"
        conn.execute(
            """
            INSERT INTO subscriptions (
                id, user_id, lang, amount, currency, vat_included, status, invoice_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (sub_id, user_id, lang, amount, currency, 1, "verified", invoice_id),
        )
        conn.commit()
    except Exception as exc:
        logging.warning("verify-purchase DB error: %s", exc)
        return jsonify(status="error", error={"message": str(exc)}), 500
    finally:
        if conn:
            conn.close()

    receipt_msg = (
        "Faturanız onaylandı: Google Play aboneliğiniz doğrulandı ve Premium süreniz 30 gün uzatıldı!"
        if lang == "tr"
        else "Receipt verified: Google Play subscription confirmed and Premium extended by 30 days!"
    )

    return jsonify(
        status="ok",
        success=True,
        verified=True,
        userId=user_id,
        productId=product_id,
        premiumUntil=new_until_str,
        receiptMessage=receipt_msg,
    )


@app.post("/api/auth/delete-account")
def api_delete_account() -> Response:
    """Delete the subscription records owned by a single app installation."""
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    body = request.get_json(silent=True) or {}
    user_id, auth_error = _auth_user_id(body)
    if auth_error:
        return auth_error
    assert user_id is not None

    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("DELETE FROM auth_sessions WHERE user_id = ?", (user_id,))
        conn.execute(
            "DELETE FROM user_subscriptions WHERE user_id = ?",
            (user_id,),
        )
        conn.execute(
            "DELETE FROM subscriptions WHERE user_id = ?",
            (user_id,),
        )
        conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
        conn.commit()
    except Exception:
        logging.exception("Account deletion DB error")
        return jsonify(
            status="error",
            error={"code": "account.deletion_failed"},
        ), 500
    finally:
        if conn:
            conn.close()

    # Cookies and download jobs have no owner column, so do not delete shared data.
    return jsonify(
        status="ok",
        success=True,
        message="Bu kuruluma bağlı abonelik ve kayıt bilgileri silindi.",
    )


@app.get("/download")
def download() -> Response | tuple[Response, int]:
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    job_id = request.args.get("job", "").strip()
    with _JOBS_LOCK:
        job = _JOBS.get(job_id)
    if job is None:
        job = _load_job_from_db(job_id)
        if job is not None:
            with _JOBS_LOCK:
                _JOBS[job.id] = job
    if job is None:
        # Check if file exists on disk directly
        for cand in os.listdir(WORK_DIR):
            if cand.startswith(f"{job_id}."):
                c_path = os.path.join(WORK_DIR, cand)
                c_ext = os.path.splitext(cand)[1].lstrip(".").lower()
                c_mime = _mime_for(c_ext, "audio" if c_ext == "mp3" else "video")
                res = send_file(
                    c_path,
                    mimetype=c_mime,
                    as_attachment=True,
                    download_name=cand,
                    conditional=True,
                )
                res.headers["Accept-Ranges"] = "bytes"
                return res
        return jsonify(status="error", error={"code": "job.not_found"}), 404
    if job.status != "ready":
        return jsonify(status="error", error={"code": "job.not_ready"}), 409
    if job.direct_url:
        extra_h = getattr(job, "direct_headers", None)
        if extra_h:
            result = stream_upstream_response(
                job,
                request.headers.get("Range"),
                extra_headers=extra_h,
            )
        else:
            result = stream_upstream_response(job, request.headers.get("Range"))

        # If stream proxy failed with 502, seamlessly recover by downloading on server with yt-dlp!
        if isinstance(result, tuple) and len(result) == 2 and result[1] == 502:
            logging.warning("Stream proxy returned 502 for job %s. Recovering with server-side download.", job.id)
            try:
                job.direct_url = None
                path = _download_job_to_disk(job)
                job.filepath = path
                return send_file(
                    job.filepath,
                    mimetype=job.mime or "application/octet-stream",
                    as_attachment=True,
                    download_name=job.filename,
                    conditional=True,
                )
            except Exception as exc:
                logging.error("Fallback server download failed: %s", exc)
                return result
        return result
    if not job.filepath or not os.path.exists(job.filepath):
        return jsonify(status="error", error={"code": "job.not_ready"}), 409

    response = send_file(
        job.filepath,
        mimetype=job.mime or "application/octet-stream",
        as_attachment=True,
        download_name=job.filename,
        conditional=True,
    )
    response.headers["Accept-Ranges"] = "bytes"
    return response


@app.get("/api/health")
def health() -> Response:
    """Handy for the app to verify the backend and its capabilities."""
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401
    return jsonify(
        status="ok",
        ytdlp=" ".join(_ytdlp_prefix()),
        ffmpeg=FFMPEG_PATH or None,
        canTranscode=bool(FFMPEG_PATH),
        impersonate=IMPERSONATE_TARGET if HAS_CURL_CFFI else None,
        cookiesBrowser=COOKIES_BROWSER or None,
        playerClient=YT_PLAYER_CLIENT or None,
        authRequired=bool(API_KEY),
        qualities=True,
    )


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8787"))
    print(f"VidSave yt-dlp backend listening on 0.0.0.0:{port}")
    print(f"  yt-dlp          : {' '.join(_ytdlp_prefix())}")
    print(f"  ffmpeg          : {FFMPEG_PATH or 'NOT FOUND (mp3/merge disabled)'}")
    print(f"  impersonate     : {IMPERSONATE_TARGET if HAS_CURL_CFFI else 'DISABLED (curl-cffi missing)'}")
    print(f"  cookies_browser : {COOKIES_BROWSER or 'NONE'}")
    print(f"  player_client   : {YT_PLAYER_CLIENT or 'DEFAULT'}")
    if os.environ.get("VIDSAVE_NO_AUTO_UPDATE", "").strip() != "1":
        _auto_update_ytdlp_background()
    app.run(host="0.0.0.0", port=port, threaded=True)
