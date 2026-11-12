from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server


class AnalyzeEndpointTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()

    def test_options_preflight_returns_204(self):
        res = self.client.options("/api/analyze")
        self.assertEqual(res.status_code, 204)
        self.assertIn("Access-Control-Allow-Origin", res.headers)

    def test_missing_url_returns_400(self):
        res = self.client.post("/api/analyze", json={})
        self.assertEqual(res.status_code, 400)
        data = res.get_json()
        self.assertEqual(data["status"], "error")

    @patch("server._direct_proxy_job", return_value="https://vidsave.test/download?job=abc123")
    @patch("server._run_json")
    def test_successful_video_analyze_returns_proxied_download_url(
        self, mock_run_json, mock_proxy_job
    ):
        mock_run_json.return_value = {
            "title": "Sample Nature Video",
            "duration": 45,
            "thumbnail": "https://example.com/thumb.jpg",
            "formats": [
                {
                    "format_id": "18",
                    "vcodec": "avc1",
                    "acodec": "mp4a",
                    "height": 720,
                    "ext": "mp4",
                    "url": "https://example.com/stream_720p.mp4",
                }
            ],
        }

        res = self.client.post(
            "/api/analyze",
            json={"url": "https://example.com/video/123", "type": "video"},
        )
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertEqual(data["status"], "success")
        # CDN links are IP-bound; the device must download through the backend.
        self.assertEqual(data["download_url"], "https://vidsave.test/download?job=abc123")
        self.assertEqual(data["headers"], {})
        proxy_kwargs = mock_proxy_job.call_args.kwargs
        self.assertEqual(proxy_kwargs["direct_url"], "https://example.com/stream_720p.mp4")
        self.assertEqual(proxy_kwargs["kind"], "video")
        self.assertEqual(data["title"], "Sample Nature Video")
        self.assertEqual(data["ext"], "mp4")
        self.assertEqual(data["filename"], "Sample Nature Video.mp4")

    @patch("server.FFMPEG_PATH", None)
    @patch("server._direct_proxy_job", return_value="https://vidsave.test/download?job=audio1")
    @patch("server._run_json")
    def test_successful_mp3_analyze_returns_audio_download_url(
        self, mock_run_json, mock_proxy_job
    ):
        mock_run_json.return_value = {
            "title": "Chill Acoustic Song",
            "duration": 180,
            "thumbnail": "https://example.com/audio_thumb.jpg",
            "formats": [
                {
                    "format_id": "140",
                    "vcodec": "none",
                    "acodec": "mp4a.40.2",
                    "abr": 128,
                    "ext": "m4a",
                    "url": "https://example.com/audio_stream.m4a",
                }
            ],
        }

        res = self.client.post(
            "/api/analyze",
            json={"url": "https://example.com/music/456", "type": "mp3"},
        )
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertEqual(data["status"], "success")
        self.assertEqual(data["download_url"], "https://vidsave.test/download?job=audio1")
        self.assertEqual(mock_proxy_job.call_args.kwargs["kind"], "audio")
        self.assertEqual(data["title"], "Chill Acoustic Song")
        self.assertEqual(data["type"], "mp3")

    @patch("server._fallback_regex_scrape")
    @patch("server.threading.Thread")
    @patch("server._new_job")
    @patch("server._run_json")
    def test_mp3_analyze_never_falls_back_to_video_format(
        self, mock_run_json, mock_new_job, mock_thread, mock_fallback
    ):
        mock_run_json.return_value = {
            "title": "Video With Audio",
            "formats": [
                {
                    "vcodec": "avc1",
                    "acodec": "mp4a.40.2",
                    "ext": "mp4",
                    "url": "https://example.com/video_with_audio.mp4",
                }
            ],
        }
        mock_new_job.return_value.status = "error"
        mock_fallback.return_value = {
            "url": "https://example.com/video_fallback.mp4",
            "ext": "mp4",
        }

        res = self.client.post(
            "/api/analyze",
            json={"url": "https://example.com/music/789", "type": "mp3"},
        )

        self.assertEqual(res.status_code, 422)
        self.assertEqual(res.get_json()["status"], "error")
        mock_fallback.assert_not_called()
        mock_thread.assert_called_once()

    def test_impersonate_flag_requires_curl_cffi(self):
        with patch.object(server, "HAS_CURL_CFFI", False):
            args = server._base_args()
        self.assertNotIn("--impersonate", args)

        with patch.object(server, "HAS_CURL_CFFI", True):
            args = server._base_args()
        self.assertIn("--impersonate", args)


if __name__ == "__main__":
    unittest.main()
