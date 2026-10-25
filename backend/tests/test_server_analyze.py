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

    @patch("server._run_json")
    def test_successful_video_analyze_returns_download_url(self, mock_run_json):
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
        self.assertEqual(data["download_url"], "https://example.com/stream_720p.mp4")
        self.assertEqual(data["title"], "Sample Nature Video")
        self.assertEqual(data["ext"], "mp4")
        self.assertEqual(data["filename"], "Sample Nature Video.mp4")

    @patch("server._run_json")
    def test_successful_mp3_analyze_returns_audio_download_url(self, mock_run_json):
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
        self.assertEqual(data["download_url"], "https://example.com/audio_stream.m4a")
        self.assertEqual(data["title"], "Chill Acoustic Song")
        self.assertEqual(data["type"], "mp3")


if __name__ == "__main__":
    unittest.main()
