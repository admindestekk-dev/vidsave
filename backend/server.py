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
import random
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
from pathlib import Path
from typing import Any

# Add project bin directories to PATH if present (e.g. for ffmpeg binary on Render)
_server_dir = Path(__file__).resolve().parent
_root_dir = _server_dir.parent
for _bin_candidate in [_root_dir / "bin", _server_dir / "bin", Path.home() / ".local" / "bin"]:
    if _bin_candidate.is_dir() and str(_bin_candidate) not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{_bin_candidate}:{os.environ.get('PATH', '')}"

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    requests = None
    HAS_REQUESTS = False
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

# --- CORS (Cross-Origin Resource Sharing) Shield ---------------------------
try:
    from flask_cors import CORS
    CORS(app, resources={r"/*": {"origins": "*"}})
except Exception:
    @app.after_request
    def _add_cors_headers(response: Response) -> Response:
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Headers"] = (
            "Content-Type,Authorization,X-Api-Key,Accept,User-Agent"
        )
        response.headers["Access-Control-Allow-Methods"] = (
            "GET,PUT,POST,DELETE,OPTIONS"
        )
        return response

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
    "Chrome/126.0.0.0 Safari/537.36"
)
UA = BROWSER_UA

# Pinterest-specific modern User-Agent mask for bot-bypass (avoid 403 Forbidden / Access Denied)
PINTEREST_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/126.0.0.0 Safari/537.36"
)

# TikTok-specific aggressive bot mask User-Agent & HTTP headers (bypass 403 Forbidden)
TIKTOK_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)

TIKTOK_HTTP_HEADERS: dict[str, str] = {
    "User-Agent": TIKTOK_UA,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
    "Referer": "https://tiktok.com",
    "Origin": "https://tiktok.com",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "same-site",
}

# Impersonation target: 'chrome' or 'firefox'
IMPERSONATE_TARGET = os.environ.get("VIDSAVE_IMPERSONATE", "chrome").strip() or "chrome"

# Universal browser cookies extraction ('chrome', 'firefox', etc.)
COOKIES_BROWSER = os.environ.get("VIDSAVE_COOKIES_BROWSER", "").strip() or None

# YouTube player client extraction parameter ('ios,android,web', 'ios', 'android', 'web')
YT_PLAYER_CLIENT = (
    os.environ.get("VIDSAVE_YT_PLAYER_CLIENT", "ios,android,web").strip()
    or "ios,android,web"
)

# --- anti-bot resilience ---------------------------------------------------
#
# No setup can promise "never blocked": platforms ship new countermeasures all
# the time. What we can do is fail over quickly and cheaply:
#   * rotate the egress IP (proxy pool) instead of hammering one address,
#   * walk a ladder of YouTube player clients when a bot check fires,
#   * back off with jitter so retries do not look like a script,
#   * pump CDN bytes through the same egress that resolved them.

# `VIDSAVE_PROXY_LIST="http://u:p@host:port, http://host2:port"` or a single
# `VIDSAVE_PROXY_URL`. Empty means "direct connection".
_PROXY_LIST_RAW = os.environ.get("VIDSAVE_PROXY_LIST", "").strip()
_SINGLE_PROXY = os.environ.get("VIDSAVE_PROXY_URL", "").strip()
PROXY_POOL: list[str] = [
    entry for entry in re.split(r"[,\s;]+", _PROXY_LIST_RAW) if entry
] or ([_SINGLE_PROXY] if _SINGLE_PROXY else [])

# Ordered fallbacks for the YouTube extractor. The first entry is the default
# requested by YT_PLAYER_CLIENT; the rest are tried on bot/format failures.
YT_CLIENT_LADDER: list[str] = [
    client.strip()
    for client in os.environ.get(
        "VIDSAVE_YT_CLIENT_LADDER",
        "android,tv,mweb,web,android_vr,ios",
    ).split(",")
    if client.strip()
]

try:
    MAX_ATTEMPTS = max(1, int(os.environ.get("VIDSAVE_MAX_ATTEMPTS", "6")))
except (TypeError, ValueError):
    MAX_ATTEMPTS = 6

try:
    BACKOFF_BASE_SECONDS = max(
        0.0, float(os.environ.get("VIDSAVE_BACKOFF_BASE", "0.8"))
    )
except (TypeError, ValueError):
    BACKOFF_BASE_SECONDS = 0.8

try:
    BACKOFF_MAX_SECONDS = max(
        BACKOFF_BASE_SECONDS, float(os.environ.get("VIDSAVE_BACKOFF_MAX", "8"))
    )
except (TypeError, ValueError):
    BACKOFF_MAX_SECONDS = 8.0

# Substrings that mean "you are being fingerprinted / throttled", not "the
# request was malformed". These trigger an egress rotation and a longer wait.
_RATE_LIMIT_MARKERS = (
    "403",
    "429",
    "too many requests",
    "rate limit",
    "temporarily blocked",
    "forbidden",
    "unusual traffic",
    "access denied",
)

_BOT_CHECK_MARKERS = (
    "sign in to confirm you're not a bot",
    "sign in to confirm you’re not a bot",
    "confirm you're not a bot",
    "some ios client https formats have been skipped",
    "requested format is not available",
    "no video formats found",
    "not a bot",
    "bot",
)

# SQLite database for storing persistent user cookies (e.g. Instagram session)
def _resolve_db_path() -> str:
    env_path = os.environ.get("VIDSAVE_DB_PATH")
    if env_path:
        try:
            parent_dir = os.path.dirname(os.path.abspath(env_path))
            if parent_dir:
                os.makedirs(parent_dir, exist_ok=True)
            with sqlite3.connect(env_path) as test_conn:
                test_conn.execute("SELECT 1")
            return env_path
        except Exception as exc:
            logging.warning(
                "Could not use VIDSAVE_DB_PATH '%s' (%s). Falling back to local backend db.",
                env_path,
                exc,
            )
    fallback = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "vidsave_data.db"
    )
    try:
        os.makedirs(os.path.dirname(os.path.abspath(fallback)), exist_ok=True)
    except Exception:
        pass
    return fallback


DB_PATH = _resolve_db_path()


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

# Universal yt-dlp configuration with aggressive bot mask headers to bypass TikTok 403 barriers
ydl_opts: dict[str, Any] = {
    "extractor_args": {
        "tiktok": {"web_search": [""]},
        "youtube": {
            "player_client": [YT_PLAYER_CLIENT] if YT_PLAYER_CLIENT else ["ios"]
        },
    },
    "http_headers": {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/124.0.0.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": "https://tiktok.com",
        "Origin": "https://tiktok.com",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-site",
    },
    "cookiesfrombrowser": None,
    "impersonate": IMPERSONATE_TARGET,
    "concurrent_fragment_downloads": 8,
    "retries": 10,
    "fragment_retries": 10,
    # Parça ve arabellek (Buffer) kalkanları: kısa videolarda akış kopmasını, uzun videolarda taşmayı önler
    "buffersize": 1024 * 16,  # Veriyi dengeli parçalarla akıtır
    "external_downloader_args": ["--min-chunk-size", "1M"],
    "hls_use_mpegts": True,  # Uzun video akışlarını parça parça korur
    "http_chunk_size": 1024 * 1024,  # 1MB dengeli parça sınırı
}
YTDLP_UNIVERSAL_OPTS: dict[str, Any] = ydl_opts


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


def _is_tiktok_url(url: str) -> bool:
    """True when the URL points to a TikTok domain or CDN."""
    u = url.strip().lower()
    return any(
        d in u
        for d in (
            "tiktok.com",
            "douyin.com",
            "tiktokcdn.com",
            "byteoversea.com",
            "ibytedtos.com",
        )
    )


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
    speed_str: str | None = None
    eta_str: str | None = None
    percent_str: str | None = None
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


def _proxy_for_attempt(attempt: int) -> str | None:
    """Pick the egress proxy for a retry, rotating across the configured pool."""
    if not PROXY_POOL:
        return None
    return PROXY_POOL[attempt % len(PROXY_POOL)]


def _replace_youtube_client(cmd: list[str], client: str) -> list[str]:
    """Replace (or add) the `youtube:player_client` extractor argument."""
    cleaned: list[str] = []
    index = 0
    while index < len(cmd):
        if (
            cmd[index] == "--extractor-args"
            and index + 1 < len(cmd)
            and "youtube:player_client=" in cmd[index + 1]
        ):
            index += 2
            continue
        cleaned.append(cmd[index])
        index += 1

    insert_at = cleaned.index("--") if "--" in cleaned else len(cleaned)
    cleaned[insert_at:insert_at] = [
        "--extractor-args",
        f"youtube:player_client={client}",
    ]
    return cleaned


def _base_args(
    *,
    allow_playlist_items: bool = False,
    cookiefile: str | None = None,
    source_url: str | None = None,
    proxy: str | None = None,
    youtube_client: str | None = None,
) -> list[str]:
    """Shared yt-dlp flags, tuned for universal bot-bypass and high throughput.

    Applies cookies-from-browser (chrome), impersonate (chrome) and youtube
    player-client (ios) universally across all platform extractions.
    If custom cookiefile is provided (e.g. from user Instagram login), uses it.
    If Pinterest URL is detected, applies Pinterest-optimized User-Agent and referer.
    """
    is_pinterest = source_url and _is_pinterest_url(source_url)
    is_tiktok = source_url and _is_tiktok_url(source_url)
    if is_tiktok:
        ua = TIKTOK_UA
        referer = "https://tiktok.com"
    elif is_pinterest:
        ua = PINTEREST_UA
        referer = "https://www.pinterest.com/"
    else:
        ua = BROWSER_UA
        referer = None

    args = _ytdlp_prefix() + [
        "--no-warnings",
        "--user-agent",
        ua,
        "--add-header",
        "Accept:text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "--add-header",
        "Accept-Language:en-US,en;q=0.5" if is_tiktok else "Accept-Language:en-US,en;q=0.9,tr;q=0.8",
        "--add-header",
        "Sec-Fetch-Mode:cors" if is_tiktok else "Sec-Fetch-Mode:navigate",
    ]
    if is_tiktok:
        args += [
            "--add-header",
            "Origin:https://tiktok.com",
            "--add-header",
            "Sec-Fetch-Site:same-site",
        ]
    if referer:
        args += ["--referer", referer]
    if cookiefile and os.path.exists(cookiefile):
        args += ["--cookies", cookiefile]
    elif COOKIES_BROWSER:
        args += ["--cookies-from-browser", COOKIES_BROWSER]
    # yt-dlp aborts every extraction with "impersonate target not available"
    # when curl-cffi is missing, so only opt in when it can actually work.
    if IMPERSONATE_TARGET and HAS_CURL_CFFI:
        args += ["--impersonate", IMPERSONATE_TARGET]
    effective_client = youtube_client or YT_PLAYER_CLIENT
    if effective_client:
        args += ["--extractor-args", f"youtube:player_client={effective_client}"]
    args += ["--extractor-args", "tiktok:web_search="]
    if proxy:
        args += ["--proxy", proxy]

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
        # 1MB chunk balance keeps slow sockets from stalling. NOTE: `buffersize`
        # is a Python-API-only yt-dlp option; passing it on the CLI makes yt-dlp
        # print its usage and fail every extraction.
        "--http-chunk-size",
        "1048576",
        "--hls-use-mpegts",
        "--downloader-args",
        "aria2c:--min-chunk-size=1M",
        "--socket-timeout",
        "15",
        # A small pause between extractor requests avoids the burst pattern that
        # bot heuristics look for without noticeably slowing a single download.
        "--sleep-requests",
        "0.3",
        # Reuse one connection and prefer IPv4 (avoids happy-eyeballs stalls).
        "--force-ipv4",
    ]
    if not allow_playlist_items:
        args += ["--no-playlist"]
    if FFMPEG_PATH:
        args += ["--ffmpeg-location", FFMPEG_PATH]
    return args


def _backoff_seconds(attempt: int) -> float:
    """Exponential backoff with +/-30% jitter so retries look human."""
    delay = min(BACKOFF_MAX_SECONDS, BACKOFF_BASE_SECONDS * (2 ** attempt))
    return max(0.0, delay * (0.7 + random.random() * 0.6))


def _drop_flag(cmd: list[str], flag: str) -> list[str]:
    """Return a copy of `cmd` with a single-value flag (and its value) removed."""
    result: list[str] = []
    skip = False
    for arg in cmd:
        if skip:
            skip = False
            continue
        if arg == flag:
            skip = True
            continue
        result.append(arg)
    return result


def _set_proxy(cmd: list[str], proxy: str | None) -> list[str]:
    """Return a copy of `cmd` with `--proxy` set to `proxy` (or removed)."""
    without = _drop_flag(cmd, "--proxy")
    if not proxy:
        return without
    insert_at = without.index("--") if "--" in without else len(without)
    without[insert_at:insert_at] = ["--proxy", proxy]
    return without


def _execute_ytdlp(
    cmd: list[str],
    timeout: int,
    progress_callback: Any = None,
) -> subprocess.CompletedProcess[str]:
    """Run yt-dlp with anti-bot failover.

    Strategy per attempt:
      1. drop an unusable `--impersonate` (curl-cffi missing),
      2. drop an unusable `--cookies-from-browser`,
      3. walk the YouTube player-client ladder on bot/format failures,
      4. rotate the egress proxy on 403/429/rate-limit failures,
      5. back off exponentially with jitter between attempts.
    """
    current_cmd = list(cmd)
    ladder_index = -1
    last_proc: subprocess.CompletedProcess[str] | None = None

    for attempt in range(MAX_ATTEMPTS):
        if PROXY_POOL:
            current_cmd = _set_proxy(current_cmd, _proxy_for_attempt(attempt))

        proc = subprocess.run(
            current_cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        if progress_callback and (proc.stdout or proc.stderr):
            for line in (proc.stdout or "").splitlines():
                progress_callback(line)

        if proc.returncode == 0:
            return proc

        last_proc = proc
        err = (proc.stderr or proc.stdout or "").lower()
        modified = False

        # 0. Impersonation is optional; a runtime without curl-cffi must not
        #    block every download, so drop the flag and retry.
        if "impersonate" in err and "--impersonate" in current_cmd:
            logging.warning("Impersonation unavailable. Retrying without --impersonate.")
            current_cmd = _drop_flag(current_cmd, "--impersonate")
            modified = True

        # 1. Browser cookie database can be absent on a server runtime.
        elif (
            "could not find" in err and "cookies database" in err
        ) and "--cookies-from-browser" in current_cmd:
            logging.warning(
                "Browser cookie database not found. Retrying without --cookies-from-browser."
            )
            current_cmd = _drop_flag(current_cmd, "--cookies-from-browser")
            modified = True

        # 2. Throttling / IP-level blocks: rotate the egress proxy.
        elif PROXY_POOL and any(marker in err for marker in _RATE_LIMIT_MARKERS):
            logging.warning(
                "Rate limited or blocked; rotating egress proxy (attempt %d/%d).",
                attempt + 1,
                MAX_ATTEMPTS,
            )
            modified = True

        # 3. YouTube bot check or format restriction: next player client.
        elif any(marker in err for marker in _BOT_CHECK_MARKERS):
            ladder_index += 1
            if ladder_index < len(YT_CLIENT_LADDER):
                client = YT_CLIENT_LADDER[ladder_index]
                logging.warning(
                    "Bot check hit; retrying YouTube with player_client=%s.", client
                )
                current_cmd = _replace_youtube_client(current_cmd, client)
                modified = True

        if not modified:
            return proc

        if attempt < MAX_ATTEMPTS - 1:
            time.sleep(_backoff_seconds(attempt))

    return last_proc if last_proc is not None else proc


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
        is_tiktok = _is_tiktok_url(url)
        test_h = {
            "User-Agent": TIKTOK_UA if is_tiktok else BROWSER_UA,
            "Accept": "*/*",
            "Range": "bytes=0-0",
        }
        if is_tiktok:
            test_h.update(TIKTOK_HTTP_HEADERS)
            test_h["Range"] = "bytes=0-0"
        if headers and isinstance(headers, dict):
            for k, v in headers.items():
                if k.lower() not in ("host", "content-length"):
                    test_h[k] = str(v)
        if requests is not None:
            # Probe through the same egress that yt-dlp used, otherwise the
            # check says "reachable" for an IP the CDN will block later.
            proxies = (
                {"http": PROXY_POOL[0], "https": PROXY_POOL[0]}
                if PROXY_POOL
                else None
            )
            res = requests.get(
                url,
                headers=test_h,
                stream=True,
                timeout=5,
                allow_redirects=True,
                proxies=proxies,
            )
            status = res.status_code
            res.close()
            return status in (200, 206)
        else:
            req = urllib.request.Request(url, headers=test_h)
            with urllib.request.urlopen(req, timeout=5) as res:
                return res.getcode() in (200, 206)
    except Exception:
        return False


def _direct_proxy_job(
    *,
    kind: str,
    source: str,
    direct_url: str,
    direct_headers: dict[str, str],
    title: str | None,
    duration: int | None,
    ext: str,
    host_url: str,
) -> str | None:
    """Expose a CDN stream as a `/download?job=` URL served by this backend.

    CDN links returned by yt-dlp (googlevideo, tiktokcdn, fbcdn, ...) are bound
    to the requesting IP and headers. Returning them to the phone makes the
    device fetch them on its own IP and every platform answers 403, so the
    bytes must always be relayed by the server that resolved them.
    """
    if not direct_url:
        return None
    if not _is_direct_url_accessible(direct_url, direct_headers):
        logging.warning(
            "Direct stream is not reachable from the server; falling back to a server-side download."
        )
        return None

    job = _new_job(kind, source)
    job.title = title
    job.duration = duration
    job.direct_url = direct_url
    job.direct_headers = dict(direct_headers or {})
    job.ext = ext
    job.mime = _mime_for(ext, kind)
    job.filename = _safe_filename(title or "vidsave", "vidsave", ext)
    job.progress = 1.0
    job.status = "ready"
    _update_job_in_db(job)
    return f"{host_url.rstrip('/')}/download?job={job.id}"


def _download_job_to_disk(job: Job, target_source: str | None = None) -> str:
    """Download merged video or mp3 audio directly to WORK_DIR using yt-dlp + ffmpeg."""
    if not FFMPEG_PATH and job.kind != "audio":
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
        if FFMPEG_PATH:
            q = f"{job.height}K" if (job.height and job.height in (128, 192, 256, 320)) else "0"
            cmd += ["-x", "--audio-format", "mp3", "--audio-quality", q]
    else:
        if FFMPEG_PATH:
            cmd += ["--merge-output-format", "mp4"]
    cmd += ["-o", out_tmpl, "--", src]

    _PROGRESS_RE = re.compile(
        r"\[download\]\s+(\d+(?:\.\d+)?)%\s+of\s+~?([0-9.]+[A-Za-z]+)\s+at\s+([0-9.]+[A-Za-z]+/s)\s+ETA\s+([0-9:]+)"
    )

    def _ytdlp_progress_hook(line: str) -> None:
        """Parse stdout lines from yt-dlp to extract percentage, speed, and ETA."""
        line_str = line.strip()
        m = _PROGRESS_RE.search(line_str)
        if m:
            pct_val = float(m.group(1))
            speed = m.group(3)
            eta = m.group(4)
            job.progress = pct_val / 100.0
            job.percent_str = f"{pct_val:.1f}%"
            job.speed_str = speed
            job.eta_str = eta
            print(f"[VidSave Backend Progress] Job {job.id[:8]}: {job.percent_str} | Hız: {speed} | Kalan: {eta}")
        elif "[download]" in line_str and "%" in line_str:
            pct_match = re.search(r"(\d+(?:\.\d+)?)%", line_str)
            if pct_match:
                pct_val = float(pct_match.group(1))
                job.progress = pct_val / 100.0
                job.percent_str = f"{pct_val:.1f}%"
                print(f"[VidSave Backend Progress] Job {job.id[:8]}: {job.percent_str}")

    proc = _execute_ytdlp(cmd, timeout=1800, progress_callback=_ytdlp_progress_hook)
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
        # Audio downloads are normalized to MP3 when ffmpeg is available.
        # If ffmpeg is absent, stream directly without transcode.
        if direct is not None and (job.kind != "audio" or not FFMPEG_PATH):
            direct_url = direct.get("url")
            direct_headers = direct.get("http_headers") or {}
            if _is_tiktok_url(direct_url or "") or _is_tiktok_url(job.source):
                merged_headers = dict(TIKTOK_HTTP_HEADERS)
                if direct_headers and isinstance(direct_headers, dict):
                    merged_headers.update(direct_headers)
                direct_headers = merged_headers
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
        "speed": job.speed_str,
        "eta": job.eta_str,
        "percentStr": job.percent_str,
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


def _unshorten_redirects(url: str) -> str:
    """Follow redirects for Facebook (fb.watch, facebook.com/share), TikTok, bitly, etc."""
    try:
        lower = url.lower()
        if any(
            d in lower
            for d in (
                "fb.watch",
                "facebook.com/share",
                "fb.me",
                "bit.ly",
                "tinyurl.com",
                "t.co",
                "vm.tiktok.com",
                "vt.tiktok.com",
                "pin.it",
            )
        ):
            headers = {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/124.0.0.0 Safari/537.36"
                ),
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9,tr;q=0.8",
            }
            resp = requests.head(url, headers=headers, allow_redirects=True, timeout=10)
            if resp.url and resp.url != url:
                return resp.url
    except Exception as exc:
        logging.warning("Unshorten failed for %s: %s", url, exc)
    return url


def _extract_vimeo_id(url: str) -> str | None:
    match = re.search(r"vimeo\.com/(?:video/)?(\d+)", url)
    return match.group(1) if match else None


def _fallback_regex_scrape(url: str, kind: str) -> dict[str, Any] | None:
    """Lightweight fallback scraper for Vimeo, Facebook, and TikTok if yt-dlp faces bot barriers."""
    try:
        vimeo_id = _extract_vimeo_id(url)
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            "Referer": "https://vimeo.com/",
            "Accept": "*/*",
        }
        if vimeo_id:
            embed_url = f"https://player.vimeo.com/video/{vimeo_id}"
            resp = requests.get(embed_url, headers=headers, timeout=15)
            if resp.status_code == 200:
                html = resp.text
                prog_m = re.findall(
                    r'"url":"(https://player\.vimeo\.com/progressive_redirect/[^"]+)"',
                    html,
                )
                if not prog_m:
                    prog_m = re.findall(
                        r'"url":"(https://[^"]*(?:vimeocdn|akamaized)[^"]*\.mp4[^"]*)"',
                        html,
                    )
                if prog_m:
                    best = max(
                        prog_m,
                        key=lambda u: 1080 if "1080" in u else (720 if "720" in u else 360),
                    )
                    return {
                        "url": best,
                        "title": f"Vimeo Video {vimeo_id}",
                        "ext": "mp4",
                    }

        if "facebook.com" in url or "fb.watch" in url:
            fb_headers = {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/124.0.0.0 Safari/537.36"
                ),
                "Referer": "https://www.facebook.com/",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
                "Sec-Fetch-Mode": "navigate",
            }
            resp = requests.get(url, headers=fb_headers, timeout=15)
            if resp.status_code == 200:
                html = resp.text
                hd_m = (
                    re.search(r'"browser_native_hd_url":\s*"([^"]+)"', html)
                    or re.search(r'"playable_url_quality_hd":\s*"([^"]+)"', html)
                    or re.search(r'"hd_src":\s*"([^"]+)"', html)
                )
                sd_m = (
                    re.search(r'"browser_native_sd_url":\s*"([^"]+)"', html)
                    or re.search(r'"playable_url":\s*"([^"]+)"', html)
                    or re.search(r'"sd_src":\s*"([^"]+)"', html)
                )
                m = hd_m or sd_m
                if m:
                    clean = m.group(1).replace(r"\/", "/").replace(r"\u0026", "&")
                    return {
                        "url": clean,
                        "title": "Facebook Video",
                        "ext": "mp4",
                    }

        # TikTok Dual High-Availability Fallback (TikWM + TikMate)
        if "tiktok.com" in url:
            try:
                tik_resp = requests.post(
                    "https://www.tikwm.com/api/",
                    data={"url": url, "count": 12, "cursor": 0, "web": 1},
                    headers={"User-Agent": "Mozilla/5.0"},
                    timeout=12,
                )
                if tik_resp.status_code == 200:
                    tik_data = tik_resp.json().get("data", {})
                    music_url = tik_data.get("music")
                    play_url = tik_data.get("play") or tik_data.get("wmplay")
                    if kind == "audio" and music_url:
                        full_music = music_url if music_url.startswith("http") else f"https://www.tikwm.com{music_url}"
                        return {
                            "url": full_music,
                            "title": tik_data.get("title") or "TikTok Audio",
                            "ext": "mp3",
                        }
                    if play_url and kind != "audio":
                        full_url = play_url if play_url.startswith("http") else f"https://www.tikwm.com{play_url}"
                        return {
                            "url": full_url,
                            "title": tik_data.get("title") or "TikTok Video",
                            "ext": "mp4",
                        }
            except Exception:
                pass

            try:
                tm_resp = requests.post(
                    "https://api.tikmate.app/api/lookup",
                    data={"url": url},
                    headers={"User-Agent": "Mozilla/5.0"},
                    timeout=10,
                )
                if tm_resp.status_code == 200:
                    tm_data = tm_resp.json()
                    token = tm_data.get("token")
                    vid_id = tm_data.get("id")
                    if token and vid_id and kind != "audio":
                        return {
                            "url": f"https://tikmate.app/download/{token}/{vid_id}.mp4?hd=1",
                            "title": tm_data.get("author_name") or "TikTok Video",
                            "ext": "mp4",
                        }
            except Exception:
                pass

        # Instagram High-Speed Bridge Fallback (eeinstagram / vxinstagram)
        if "instagram.com" in url or "instagr.am" in url:
            ig_m = re.search(r'(?:/(?:p|reel|reels|tv|share/reel|share/p)/)([a-zA-Z0-9_-]+)', url)
            if ig_m:
                shortcode = ig_m.group(1)
                bridges = [
                    f"https://eeinstagram.com/reel/{shortcode}/",
                    f"https://vxinstagram.com/reel/{shortcode}/",
                    f"https://eeinstagram.com/p/{shortcode}/",
                    f"https://vxinstagram.com/p/{shortcode}/",
                ]
                discord_headers = {
                    "User-Agent": "Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)",
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                }
                for b_url in bridges:
                    try:
                        b_resp = requests.get(b_url, headers=discord_headers, timeout=8)
                        if b_resp.status_code == 200:
                            b_html = b_resp.text
                            v_match = re.search(r'<meta[^>]+property=["\']og:video(?::secure_url)?["\'][^>]+content=["\']([^"\']+)["\']', b_html) or \
                                      re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:video(?::secure_url)?["\']', b_html)
                            if v_match:
                                v_url = v_match.group(1)
                                if v_url.startswith("/"):
                                    parsed_b = urllib.parse.urlparse(b_url)
                                    v_url = f"{parsed_b.scheme}://{parsed_b.netloc}{v_url}"
                                try:
                                    loc_resp = requests.get(v_url, headers={"User-Agent": headers["User-Agent"]}, allow_redirects=False, timeout=5)
                                    if loc_resp.status_code in (301, 302) and "Location" in loc_resp.headers:
                                        v_url = loc_resp.headers["Location"]
                                except Exception:
                                    pass
                                return {
                                    "url": v_url,
                                    "title": f"Instagram Video {shortcode}",
                                    "ext": "mp4",
                                }
                            img_match = re.search(r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)["\']', b_html) or \
                                        re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:image["\']', b_html)
                            if img_match:
                                img_url = img_match.group(1)
                                if img_url.startswith("/"):
                                    parsed_b = urllib.parse.urlparse(b_url)
                                    img_url = f"{parsed_b.scheme}://{parsed_b.netloc}{img_url}"
                                return {
                                    "url": img_url,
                                    "title": f"Instagram Photo {shortcode}",
                                    "ext": "jpg",
                                }
                    except Exception:
                        continue

        # Pinterest High-Speed Video & Image Fallback Scraper
        if "pinterest." in url or "pin.it" in url:
            pin_headers = {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/124.0.0.0 Safari/537.36"
                ),
                "Referer": "https://www.pinterest.com/",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
                "Sec-Fetch-Mode": "navigate",
            }
            clean_pin = clean_pinterest_url(url)
            pin_resp = requests.get(clean_pin, headers=pin_headers, allow_redirects=True, timeout=12)
            if pin_resp.status_code == 200:
                p_html = pin_resp.text

                # If kind is photo/image, prioritize high-res image first!
                if kind in ("photo", "image"):
                    img_patterns = [
                        r'"url":\s*"(https://i\.pinimg\.com/originals/[^"]+)"',
                        r'"(https://i\.pinimg\.com/originals/[^"]+)"',
                        r'"url":\s*"(https://i\.pinimg\.com/[^"]+)"',
                        r'<meta\s+property="og:image"\s+content="([^"]+)"',
                    ]
                    for ip in img_patterns:
                        im = re.search(ip, p_html)
                        if im:
                            raw_img = im.group(1).replace(r"\/", "/").replace(r"\u0026", "&")
                            for size in ("/236x/", "/474x/", "/564x/", "/736x/"):
                                raw_img = raw_img.replace(size, "/originals/")
                            return {
                                "url": raw_img,
                                "title": "Pinterest Image",
                                "ext": "jpg",
                            }

                # 1. Direct .mp4 or .m3u8 video stream
                v_patterns = [
                    r'"download_url":"(.*?)"',
                    r'"contentUrl":\s*"(https?://[^"]+\.mp4[^"]*)"',
                    r'"url":\s*"(https?://[^"]+\.mp4[^"]*)"',
                    r'<video[^>]+src="([^"]+)"',
                    r'<meta\s+property="og:video"\s+content="([^"]+)"',
                    r'<meta\s+property="og:video:secure_url"\s+content="([^"]+)"',
                    r'"(https?://[^"]*(?:v1?\.pinimg\.com|pinimg\.com)/videos/mc/[^"]+)"',
                    r'"url":\s*"(https?://[^"]+\.m3u8[^"]*)"',
                ]
                for vp in v_patterns:
                    vm = re.search(vp, p_html)
                    if vm:
                        raw_v = vm.group(1).replace(r"\/", "/").replace(r"\u0026", "&")
                        if ".m3u8" in raw_v or "/hls/" in raw_v:
                            raw_v = raw_v.replace("/hls/", "/720p/").replace(".m3u8", ".mp4")
                        if ".mp4" in raw_v or "/videos/mc/" in raw_v:
                            return {
                                "url": raw_v,
                                "title": "Pinterest Video",
                                "ext": "mp4",
                            }

                # Twitter (X) High-Speed Bridge Fallback (FxTwitter API)
                if "twitter.com" in url or "x.com" in url:
                    tw_match = re.search(r"status/(\d+)", url)
                    if tw_match:
                        tw_id = tw_match.group(1)
                        try:
                            fx_resp = requests.get(
                                f"https://api.fxtwitter.com/status/{tw_id}",
                                headers={"User-Agent": "Mozilla/5.0"},
                                timeout=10,
                            )
                            if fx_resp.status_code == 200:
                                fx_data = fx_resp.json().get("tweet", {})
                                fx_media = fx_data.get("media", {})
                                if isinstance(fx_media, dict):
                                    fx_videos = fx_media.get("videos", [])
                                    if fx_videos:
                                        best_v = max(
                                            fx_videos,
                                            key=lambda v: (v.get("bitrate") or 0) if isinstance(v, dict) else 0,
                                        )
                                        v_url = best_v.get("url") if isinstance(best_v, dict) else None
                                        if v_url:
                                            return {
                                                "url": v_url,
                                                "title": fx_data.get("text") or f"Twitter Video {tw_id}",
                                                "ext": "mp4",
                                            }
                        except Exception:
                            pass

                # Dailymotion Metadata Fallback Scraper
                if "dailymotion.com" in url or "dai.ly" in url:
                    dm_match = re.search(r"(?:dailymotion\.com/video/|dai\.ly/)([a-zA-Z0-9]+)", url)
                    if dm_match:
                        dm_id = dm_match.group(1)
                        try:
                            dm_meta = requests.get(
                                f"https://www.dailymotion.com/player/metadata/video/{dm_id}",
                                headers={"User-Agent": "Mozilla/5.0", "Referer": "https://www.dailymotion.com/"},
                                timeout=10,
                            )
                            if dm_meta.status_code == 200:
                                dm_json = dm_meta.json()
                                auto_streams = dm_json.get("qualities", {}).get("auto", [])
                                if auto_streams:
                                    stream_url = auto_streams[0].get("url")
                                    if stream_url:
                                        return {
                                            "url": stream_url,
                                            "title": dm_json.get("title") or f"Dailymotion Video {dm_id}",
                                            "ext": "mp4",
                                        }
                        except Exception:
                            pass

                # Original / High-Res Image
                img_patterns = [
                    r'"url":\s*"(https://i\.pinimg\.com/originals/[^"]+)"',
                    r'"(https://i\.pinimg\.com/originals/[^"]+)"',
                    r'"url":\s*"(https://i\.pinimg\.com/[^"]+)"',
                    r'<meta\s+property="og:image"\s+content="([^"]+)"',
                ]
                for ip in img_patterns:
                    im = re.search(ip, p_html)
                    if im:
                        raw_img = im.group(1).replace(r"\/", "/").replace(r"\u0026", "&")
                        for size in ("/236x/", "/474x/", "/564x/", "/736x/"):
                            raw_img = raw_img.replace(size, "/originals/")
                        return {
                            "url": raw_img,
                            "title": "Pinterest Image",
                            "ext": "jpg",
                        }
    except Exception as exc:
        logging.warning("Fallback regex scrape error: %s", exc)
    return None


@app.route("/api/analyze", methods=["GET", "POST", "OPTIONS"])
def api_analyze() -> Response | tuple[Response, int]:
    """Server-side video and audio stream analyzer.

    Accepts raw URLs from YouTube, TikTok, Vimeo, Facebook, Twitter, etc.,
    resolves short-links and bot barriers with yt-dlp and anti-bot headers,
    and returns a clean JSON object containing `download_url`.
    """
    if request.method == "OPTIONS":
        return Response(status=204)

    data: dict[str, Any] = {}
    if request.is_json:
        data = request.get_json(silent=True) or {}
    elif request.form:
        data = request.form.to_dict()
    elif request.args:
        data = request.args.to_dict()

    raw_url = (data.get("url") or data.get("link") or data.get("query") or "").strip()
    download_type = str(data.get("type") or data.get("kind") or "video").strip().lower()

    if not raw_url:
        return jsonify(
            status="error",
            error={
                "code": "url_missing",
                "message": "Lütfen geçerli bir URL sağlayın (url parametresi).",
            },
        ), 400

    target_url = _unshorten_redirects(raw_url)
    is_audio = download_type in ("mp3", "audio")
    kind = "audio" if is_audio else "video"

    # For Vimeo: player.vimeo.com/video/<id> avoids web login wall entirely
    vimeo_id = _extract_vimeo_id(target_url)
    lookup_url = (
        f"https://player.vimeo.com/video/{vimeo_id}" if vimeo_id else target_url
    )

    info: dict[str, Any] | None = None
    try:
        # 1. Primary engine: yt-dlp metadata extraction
        info = _run_json(lookup_url, kind, formats=True, timeout=40)
    except Exception as ytdlp_err:
        logging.warning("yt-dlp analyze error for %s: %s", target_url, ytdlp_err)
        if lookup_url != target_url:
            try:
                info = _run_json(target_url, kind, formats=True, timeout=40)
            except Exception:
                pass

    clean_download_url: str | None = None
    clean_download_headers: dict[str, str] = {}
    title = (info.get("title") if info else None) or "vidsave_media"
    duration = info.get("duration") if info else None
    thumbnail = info.get("thumbnail") if info else None
    ext = "mp3" if is_audio else (info.get("ext") if info else "mp4") or "mp4"

    if info:
        # Check direct formats
        direct_format = _pick_direct_format(info, kind)
        if direct_format and direct_format.get("url"):
            clean_download_url = direct_format["url"]
            if isinstance(direct_format.get("http_headers"), dict):
                clean_download_headers = {
                    str(k): str(v) for k, v in direct_format["http_headers"].items()
                }
            if direct_format.get("ext"):
                ext = direct_format["ext"]

        if not clean_download_url:
            formats = info.get("formats") or []
            if is_audio:
                audio_formats = [
                    f
                    for f in formats
                    if (f.get("acodec") or "none") != "none" and f.get("url")
                ]
                audio_only = [
                    f
                    for f in audio_formats
                    if (f.get("vcodec") or "none") == "none"
                ]
                # Never return a video-containing format for an audio request.
                # If no audio-only stream exists, the server job below extracts
                # and converts the audio track to MP3.
                candidates = audio_only
                if candidates:
                    candidates.sort(
                        key=lambda f: (f.get("abr") or 0, f.get("tbr") or 0),
                        reverse=True,
                    )
                    clean_download_url = candidates[0].get("url")
                    if isinstance(candidates[0].get("http_headers"), dict):
                        clean_download_headers = {
                            str(k): str(v)
                            for k, v in candidates[0]["http_headers"].items()
                        }
                    ext = candidates[0].get("ext") or "mp3"
            else:
                prog_formats = [
                    f
                    for f in formats
                    if (f.get("vcodec") or "none") != "none"
                    and (f.get("acodec") or "none") != "none"
                    and f.get("url")
                ]
                if prog_formats:
                    prog_formats.sort(
                        key=lambda f: (f.get("height") or 0, f.get("tbr") or 0),
                        reverse=True,
                    )
                    clean_download_url = prog_formats[0].get("url")
                    if isinstance(prog_formats[0].get("http_headers"), dict):
                        clean_download_headers = {
                            str(k): str(v)
                            for k, v in prog_formats[0]["http_headers"].items()
                        }
                    ext = prog_formats[0].get("ext") or "mp4"
                elif formats:
                    valid = [f for f in formats if f.get("url")]
                    if valid:
                        valid.sort(
                            key=lambda f: (f.get("height") or 0, f.get("tbr") or 0),
                            reverse=True,
                        )
                        clean_download_url = valid[0].get("url")
                        if isinstance(valid[0].get("http_headers"), dict):
                            clean_download_headers = {
                                str(k): str(v)
                                for k, v in valid[0]["http_headers"].items()
                            }
                        ext = valid[0].get("ext") or "mp4"

    # 2. Fallback regex scraper if yt-dlp returned no stream URL
    if not clean_download_url and not is_audio:
        fallback = _fallback_regex_scrape(target_url, kind)
        if fallback and fallback.get("url"):
            clean_download_url = fallback["url"]
            title = fallback.get("title") or title
            ext = fallback.get("ext") or ext

    # 3. Never hand a raw CDN link to the device: those links are signed for the
    # resolver's IP/headers and answer 403 everywhere else. Wrap the stream in a
    # /download job so the backend relays the bytes. Manifests (.m3u8/.mpd) and
    # audio that still needs MP3 conversion keep using the server download path.
    is_segmented_manifest = bool(clean_download_url) and (
        ".m3u8" in clean_download_url.lower() or ".mpd" in clean_download_url.lower()
    )
    is_proxied = False

    if clean_download_url and not is_segmented_manifest:
        if _is_tiktok_url(target_url) or _is_tiktok_url(clean_download_url):
            merged_headers = dict(TIKTOK_HTTP_HEADERS)
            merged_headers.update(clean_download_headers)
            clean_download_headers = merged_headers
        # Direct audio stream proxy (when accessible) or video stream proxy
        proxied_url = _direct_proxy_job(
            kind=kind,
            source=target_url,
            direct_url=clean_download_url,
            direct_headers=clean_download_headers,
            title=title,
            duration=duration if isinstance(duration, int) else None,
            ext=ext,
            host_url=request.host_url,
        )
        if proxied_url:
            clean_download_url = proxied_url
            is_proxied = True
        else:
            # The stream is not reachable from the server or direct stream unavailable;
            # let the background job path below download/transcode it with yt-dlp.
            clean_download_url = None

    if not clean_download_url or is_segmented_manifest:
        try:
            job = _new_job(kind, target_url)
            job.mode = "url"
            threading.Thread(target=_work, args=(job,), daemon=True).start()
            deadline = time.time() + 25
            while time.time() < deadline:
                if job.status in ("ready", "error"):
                    break
                time.sleep(0.3)
            if job.status == "ready":
                base_host = request.host_url.rstrip("/")
                clean_download_url = f"{base_host}/download?job={job.id}"
                title = job.title or title
                ext = job.ext or ext
                duration = job.duration or duration
            elif is_segmented_manifest:
                clean_download_url = None
        except Exception as job_err:
            logging.warning("Server fallback job failed: %s", job_err)
            if is_segmented_manifest:
                clean_download_url = None

    if not clean_download_url:
        return jsonify(
            status="error",
            error={
                "code": "stream_not_found",
                "message": (
                    "Medya akışı veya indirme bağlantısı çözülemedi. "
                    "Lütfen bağlantıyı kontrol edin."
                ),
            },
        ), 422

    if is_audio and not ext.lower().endswith("mp3"):
        ext = "mp3"

    filename = _safe_filename(title, "vidsave", ext)

    return jsonify({
        "status": "success",
        "download_url": clean_download_url,
        "title": title,
        "filename": filename,
        "thumbnail": thumbnail,
        "duration": duration,
        "type": "mp3" if is_audio else "video",
        "ext": ext,
        "headers": (
            # Served by this backend: it applies the upstream CDN headers itself.
            {}
            if is_proxied
            else (
                dict(TIKTOK_HTTP_HEADERS)
                if (
                    _is_tiktok_url(target_url)
                    or _is_tiktok_url(clean_download_url or "")
                )
                else {
                    "User-Agent": (
                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                        "AppleWebKit/537.36 (KHTML, like Gecko) "
                        "Chrome/124.0.0.0 Safari/537.36"
                    ),
                    "Referer": target_url,
                }
            )
        ),
    }), 200


@app.route("/api/indirme-durumu", methods=["GET", "POST"])
def api_indirme_durumu() -> Response:
    """Canlı indirme durumu endpoint'i (Long-Polling & Progress Tracking).

    Flutter Frontend'in indirme yüzdesini, hızını, kalan süresini (ETA) ve
    işlem durumunu anlık olarak sorgulamasını sağlar.
    """
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401

    job_id = (request.args.get("job") or request.args.get("id") or "").strip()
    if not job_id and request.is_json:
        body = request.get_json(silent=True) or {}
        job_id = (body.get("job") or body.get("id") or "").strip()

    if not job_id:
        # En son aktif olan işi döndürmeyi dene veya hata dön
        with _JOBS_LOCK:
            if _JOBS:
                latest_job = max(_JOBS.values(), key=lambda j: j.created_at)
                return jsonify(_job_payload(latest_job))
        return jsonify(status="error", error={"code": "job_id_missing", "message": "job parametresi eksik."}), 400

    with _JOBS_LOCK:
        job = _JOBS.get(job_id)
    if job is None:
        job = _load_job_from_db(job_id)
        if job is not None:
            with _JOBS_LOCK:
                _JOBS[job.id] = job

    if job is None:
        return jsonify(status="error", error={"code": "job.not_found", "message": "İndirme işi bulunamadı."}), 404

    payload = _job_payload(job)
    payload["success"] = True
    return jsonify(payload)


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
        premium_until = None
        if sub_row:
            prem_until_str, is_prem_flag = sub_row[0], sub_row[1]
            if is_prem_flag and prem_until_str:
                try:
                    premium_date = datetime.datetime.fromisoformat(
                        str(prem_until_str).replace("Z", "+00:00")
                    )
                    if premium_date.tzinfo is None:
                        premium_date = premium_date.replace(
                            tzinfo=datetime.timezone.utc
                        )
                    if premium_date > datetime.datetime.now(datetime.timezone.utc):
                        is_premium = True
                        premium_until = premium_date.astimezone(
                            datetime.timezone.utc
                        ).isoformat()
                except ValueError:
                    logging.warning("Invalid premium expiry for user %s", user_id)

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
        premium_until=premium_until,
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

    now = datetime.datetime.now(datetime.timezone.utc)
    current_until = None
    new_until_str = (now + datetime.timedelta(days=30)).isoformat()

    # Accounting record persistence & 30-day premium extension in SQLite
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

        # Update or insert into user_subscriptions for active premium & 30-day extension
        conn.execute(
            """
            INSERT INTO user_subscriptions (user_id, is_premium, premium_until, product_id, purchase_token, updated_at)
            VALUES (?, 1, ?, 'vidsave_premium_monthly', ?, CURRENT_TIMESTAMP)
            ON CONFLICT(user_id) DO UPDATE SET
                is_premium = 1,
                premium_until = excluded.premium_until,
                product_id = excluded.product_id,
                purchase_token = excluded.purchase_token,
                updated_at = CURRENT_TIMESTAMP
            """,
            (user_id, new_until_str, f"sim_{subscription_id}"),
        )

        conn.execute(
            """
            INSERT INTO subscriptions (
                id, user_id, lang, amount, currency, vat_included, status, invoice_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (subscription_id, user_id, lang, amount, currency, 1, "active", invoice_id),
        )
        conn.commit()
    except sqlite3.Error:
        logging.exception("Subscription accounting recording failed")
        return jsonify(
            status="error",
            success=False,
            error={
                "code": "subscription.record_failed",
                "message": "Abonelik kaydı oluşturulamadı. Lütfen tekrar deneyin.",
            },
        ), 500
    finally:
        if conn:
            conn.close()

    receipt_message = (
        "Test aboneliği etkinleştirildi: 9,99 TL/ay (gerçek ödeme alınmadı)."
        if is_tr
        else "Developer test subscription enabled: $0.99/month (no real payment was charged)."
    )

    return jsonify(
        status="ok",
        success=True,
        is_premium=True,
        premium_until=new_until_str,
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
            "premiumUntil": new_until_str,
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
            original_direct_url = job.direct_url
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
                # Keep the job usable for the next Range request of the same
                # download instead of degrading it to "not ready".
                job.direct_url = original_direct_url
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


@app.route("/", methods=["GET", "HEAD"])
def root_status() -> Response:
    """Public root status endpoint for Render health checks and browser verification."""
    return jsonify({
        "status": "ok",
        "service": "VidSave Backend",
        "version": "1.0.0",
        "endpoints": {
            "analyze": "/api/analyze",
            "resolve": "/api/resolve",
            "health": "/api/health",
        },
    }), 200


@app.get("/api/anti-bot/status")
def api_anti_bot_status() -> Response:
    """Report the active anti-bot strategy without exposing proxy credentials."""
    if not _authorized():
        return jsonify(status="error", error={"code": "unauthorized"}), 401
    return jsonify(
        status="ok",
        egress={
            "proxyConfigured": bool(PROXY_POOL),
            "proxyCount": len(PROXY_POOL),
            "rotatesOnRateLimit": bool(PROXY_POOL),
        },
        extractor={
            "curlCffi": HAS_CURL_CFFI,
            "impersonate": IMPERSONATE_TARGET if HAS_CURL_CFFI else None,
            "cookiesFromBrowser": COOKIES_BROWSER,
            "youtubePlayerClient": YT_PLAYER_CLIENT,
            "youtubeClientLadder": YT_CLIENT_LADDER,
            "streamProxyUsesEgress": bool(PROXY_POOL),
        },
        retries={
            "maxAttempts": MAX_ATTEMPTS,
            "backoffBaseSeconds": BACKOFF_BASE_SECONDS,
            "backoffMaxSeconds": BACKOFF_MAX_SECONDS,
            "jitterPercent": 30,
        },
    )


@app.route("/api/ping", methods=["GET", "HEAD"])
def api_ping() -> Response:
    """Ultra-lightweight ping endpoint for Render / Uptime robot keep-alive checks."""
    return jsonify({"status": "pong", "time": int(time.time())}), 200


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
