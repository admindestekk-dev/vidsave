from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import stream_proxy


class PublicUrlValidationTests(unittest.TestCase):
    def test_rejects_loopback_and_non_http_urls(self):
        for url in (
            "http://127.0.0.1/file",
            "http://localhost/file",
            "file:///etc/passwd",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                stream_proxy.validate_public_http_url(url)

    @patch.object(stream_proxy.socket, "getaddrinfo")
    def test_rejects_host_resolving_to_private_address(self, getaddrinfo):
        getaddrinfo.return_value = [(None, None, None, None, ("10.0.0.4", 80))]
        with self.assertRaises(ValueError):
            stream_proxy.validate_public_http_url("http://media.example/file")

    @patch.object(stream_proxy.socket, "getaddrinfo")
    def test_accepts_public_http_destination(self, getaddrinfo):
        getaddrinfo.return_value = [(None, None, None, None, ("93.184.216.34", 80))]
        stream_proxy.validate_public_http_url("http://media.example/file")


class StreamResponseTests(unittest.TestCase):
    def setUp(self):
        self.job = SimpleNamespace(
            direct_url="https://media.example/video.mp4",
            filename="sample video.mp4",
            mime="video/mp4",
        )

    @patch.object(stream_proxy, "_open_upstream")
    def test_streams_chunks_and_sets_download_headers(self, open_upstream):
        session = Mock()
        upstream = Mock()
        upstream.status_code = 200
        upstream.headers = {
            "Content-Length": "5",
            "Accept-Ranges": "bytes",
        }
        upstream.iter_content.return_value = [b"he", b"llo"]
        open_upstream.return_value = (session, upstream)

        from flask import Flask

        app = Flask(__name__)
        with app.test_request_context("/download"):
            response = stream_proxy.stream_upstream_response(self.job)
            body = b"".join(response.response)

        self.assertEqual(body, b"hello")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Content-Length"], "5")
        self.assertEqual(response.headers["Accept-Ranges"], "bytes")
        self.assertIn(
            "filename*=UTF-8''sample%20video.mp4",
            response.headers["Content-Disposition"],
        )
        upstream.close.assert_called_once()
        session.close.assert_called_once()

    @patch.object(stream_proxy, "_open_upstream")
    def test_forwards_valid_range_request(self, open_upstream):
        session = Mock()
        upstream = Mock()
        upstream.status_code = 206
        upstream.headers = {"Content-Range": "bytes 1-2/5", "Content-Length": "2"}
        upstream.iter_content.return_value = [b"el"]
        open_upstream.return_value = (session, upstream)

        from flask import Flask

        app = Flask(__name__)
        with app.test_request_context("/download"):
            response = stream_proxy.stream_upstream_response(self.job, "bytes=1-2")
            body = b"".join(response.response)

        self.assertEqual(body, b"el")
        self.assertEqual(response.status_code, 206)
        self.assertEqual(response.headers["Content-Range"], "bytes 1-2/5")
        open_upstream.assert_called_once_with(self.job.direct_url, "bytes=1-2")

    @patch.object(stream_proxy, "_open_upstream", side_effect=stream_proxy.ProxyDownloadTooLarge())
    def test_rejects_oversized_upstream_response(self, _open_upstream):
        from flask import Flask

        app = Flask(__name__)
        with app.app_context():
            response, status = stream_proxy.stream_upstream_response(self.job)

        self.assertEqual(status, 413)
        self.assertEqual(response.get_json()["error"]["code"], "download.too_large")

    @patch.object(stream_proxy, "validate_public_http_url")
    @patch.object(stream_proxy.requests, "Session")
    def test_validates_redirect_destination(self, session_factory, validate_url):
        session = Mock()
        redirect = Mock(status_code=302, headers={"Location": "https://cdn.example/file"})
        final = Mock(status_code=200, headers={"Content-Length": "2"})
        session.get.side_effect = [redirect, final]
        session_factory.return_value = session

        returned_session, response = stream_proxy._open_upstream(
            "https://origin.example/file", None
        )

        self.assertIs(returned_session, session)
        self.assertIs(response, final)
        self.assertEqual(validate_url.call_count, 2)
        self.assertEqual(session.get.call_count, 2)


if __name__ == "__main__":
    unittest.main()
