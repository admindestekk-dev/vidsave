"""Bounded, validated streaming for resolved media URLs.

This module only accepts HTTP(S) URLs that resolve exclusively to globally
routable addresses. Deployments should additionally apply outbound network
controls; DNS validation alone cannot prevent DNS rebinding.
"""

from __future__ import annotations

import ipaddress
import os
import re
import socket
import time
from urllib.parse import quote, urljoin, urlsplit

import requests
from flask import Response, jsonify, stream_with_context


DEFAULT_MAX_BYTES = 4 * 1024 * 1024 * 1024
try:
    MAX_STREAM_BYTES = max(
        1, int(os.environ.get("VIDSAVE_MAX_DOWNLOAD_BYTES", DEFAULT_MAX_BYTES))
    )
except (TypeError, ValueError):
    MAX_STREAM_BYTES = DEFAULT_MAX_BYTES

CONNECT_TIMEOUT_SECONDS = 10
READ_TIMEOUT_SECONDS = 60
MAX_REDIRECTS = 5
MAX_STREAM_SECONDS = 30 * 60
CHUNK_SIZE = 64 * 1024
REDIRECT_STATUSES = {301, 302, 303, 307, 308}


class ProxyDownloadError(Exception):
    """An upstream response cannot be safely streamed."""


class ProxyDownloadTooLarge(ProxyDownloadError):
    """The upstream body exceeds the configured transfer limit."""


def validate_public_http_url(url: str) -> None:
    """Reject malformed URLs and destinations that are not globally routable."""
    if not isinstance(url, str) or not url or len(url) > 8192:
        raise ValueError("Invalid URL")

    try:
        parsed = urlsplit(url)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError as exc:
        raise ValueError("Invalid URL") from exc

    if (
        parsed.scheme.lower() not in {"http", "https"}
        or not hostname
        or parsed.username is not None
        or parsed.password is not None
    ):
        raise ValueError("Only public HTTP(S) URLs are supported")

    expected_port = 443 if parsed.scheme.lower() == "https" else 80
    if port is not None and port != expected_port:
        raise ValueError("Non-standard ports are not allowed")

    hostname = hostname.rstrip(".").lower()
    if hostname in {"localhost", "localhost.localdomain"} or hostname.endswith(
        (".localhost", ".local", ".internal")
    ):
        raise ValueError("Private network destinations are not allowed")

    try:
        ip = ipaddress.ip_address(hostname)
        addresses = {ip}
    except ValueError:
        try:
            ascii_hostname = hostname.encode("idna").decode("ascii")
            addresses = {
                ipaddress.ip_address(result[4][0])
                for result in socket.getaddrinfo(
                    ascii_hostname,
                    port or expected_port,
                    type=socket.SOCK_STREAM,
                )
            }
        except (OSError, UnicodeError, ValueError) as exc:
            raise ValueError("Unable to resolve URL host") from exc

    if not addresses or any(not address.is_global for address in addresses):
        raise ValueError("Private network destinations are not allowed")


def _content_length(headers: requests.structures.CaseInsensitiveDict) -> int | None:
    value = headers.get("Content-Length")
    if value is None:
        return None
    try:
        length = int(value)
    except (TypeError, ValueError) as exc:
        raise ProxyDownloadError("Invalid upstream response") from exc
    if length < 0:
        raise ProxyDownloadError("Invalid upstream response")
    return length


BROWSER_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/133.0.0.0 Safari/537.36"
)


def _open_upstream(
    url: str,
    range_header: str | None,
    extra_headers: dict[str, str] | None = None,
) -> tuple[requests.Session, requests.Response]:
    session = requests.Session()
    # Avoid inheriting proxy settings from the environment for an untrusted URL.
    session.trust_env = False
    headers = {
        "User-Agent": BROWSER_USER_AGENT,
        "Accept": "*/*",
        "Accept-Encoding": "identity",
    }
    if extra_headers and isinstance(extra_headers, dict):
        for k, v in extra_headers.items():
            if k.lower() not in ("host", "content-length"):
                headers[k] = str(v)
    if range_header and re.fullmatch(r"bytes=\d*-\d*", range_header.strip()):
        headers["Range"] = range_header.strip()

    current_url = url
    try:
        for redirect_count in range(MAX_REDIRECTS + 1):
            validate_public_http_url(current_url)
            response = session.get(
                current_url,
                headers=headers,
                stream=True,
                allow_redirects=False,
                timeout=(CONNECT_TIMEOUT_SECONDS, READ_TIMEOUT_SECONDS),
            )
            if response.status_code in REDIRECT_STATUSES:
                location = response.headers.get("Location")
                response.close()
                if not location or redirect_count == MAX_REDIRECTS:
                    raise ProxyDownloadError("Invalid upstream redirect")
                current_url = urljoin(current_url, location)
                continue

            if response.status_code not in {200, 206}:
                response.close()
                raise ProxyDownloadError("Upstream request failed")

            length = _content_length(response.headers)
            if length is not None and length > MAX_STREAM_BYTES:
                response.close()
                raise ProxyDownloadTooLarge("Upstream body exceeds the size limit")
            return session, response

        raise ProxyDownloadError("Too many upstream redirects")
    except Exception:
        session.close()
        raise


def stream_upstream_response(
    job: object,
    range_header: str | None = None,
    extra_headers: dict[str, str] | None = None,
) -> Response | tuple[Response, int]:
    """Return a Flask response streaming a job's resolved URL in bounded chunks."""
    try:
        if extra_headers is not None:
            session, upstream = _open_upstream(job.direct_url, range_header, extra_headers)
        else:
            session, upstream = _open_upstream(job.direct_url, range_header)
    except ProxyDownloadTooLarge:
        return jsonify(status="error", error={"code": "download.too_large"}), 413
    except (ProxyDownloadError, requests.RequestException, OSError, ValueError):
        return jsonify(status="error", error={"code": "download.upstream_error"}), 502

    expected_length = _content_length(upstream.headers)

    def generate():
        transferred = 0
        deadline = time.monotonic() + MAX_STREAM_SECONDS
        try:
            for chunk in upstream.iter_content(chunk_size=CHUNK_SIZE):
                if not chunk:
                    continue
                transferred += len(chunk)
                if transferred > MAX_STREAM_BYTES or time.monotonic() > deadline:
                    raise ProxyDownloadTooLarge("Upstream transfer limit exceeded")
                yield chunk
        finally:
            upstream.close()
            session.close()

    response = Response(
        stream_with_context(generate()),
        status=upstream.status_code,
        mimetype=job.mime or "application/octet-stream",
    )
    filename = job.filename or "download"
    response.headers["Content-Disposition"] = (
        f"attachment; filename*=UTF-8''{quote(filename, safe='')}"
    )
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    if expected_length is not None and upstream.headers.get(
        "Content-Encoding", "identity"
    ).lower() == "identity":
        response.headers["Content-Length"] = str(expected_length)

    if upstream.headers.get("Accept-Ranges", "").lower() == "bytes":
        response.headers["Accept-Ranges"] = "bytes"
    content_range = upstream.headers.get("Content-Range", "")
    if upstream.status_code == 206 and re.fullmatch(
        r"bytes \d+-\d+/(?:\d+|\*)", content_range
    ):
        response.headers["Content-Range"] = content_range

    return response
