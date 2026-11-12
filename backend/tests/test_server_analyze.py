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
                    "acodec": "mp3",
                    "abr": 128,
                    "ext": "mp3",
                    "url": "https://example.com/audio_stream.mp3",
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
        self.assertEqual(data["ext"], "mp3")

    @patch("server._direct_proxy_job")
    @patch("server.threading.Thread")
    @patch("server._new_job")
    @patch("server._run_json")
    def test_m4a_audio_stream_is_not_mislabelled_as_mp3(
        self, mock_run_json, mock_new_job, mock_thread, mock_proxy_job
    ):
        """An AAC/M4A stream must be extracted into a real MP3 server-side.

        Serving those bytes under a .mp3 name is exactly why downloaded tracks
        failed to play in music apps.
        """
        mock_run_json.return_value = {
            "title": "Chill Acoustic Song",
            "duration": 180,
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
        job = MagicMock()
        job.id = "jobmp3"
        job.status = "ready"
        job.ext = "mp3"
        job.title = "Chill Acoustic Song"
        job.duration = 180
        mock_new_job.return_value = job

        res = self.client.post(
            "/api/analyze",
            json={"url": "https://example.com/music/456", "type": "mp3"},
        )

        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        mock_proxy_job.assert_not_called()
        self.assertEqual(data["ext"], "mp3")
        self.assertTrue(data["filename"].endswith(".mp3"))
        self.assertNotIn(".m4a", data["filename"])

    @patch("server._fallback_regex_scrape", return_value=None)
    @patch("server._direct_proxy_job")
    @patch("server.threading.Thread")
    @patch("server._new_job")
    @patch("server._run_json")
    def test_video_only_formats_are_merged_instead_of_returned_silent(
        self, mock_run_json, mock_new_job, mock_thread, mock_proxy_job, mock_fallback
    ):
        """DASH sources expose video-only streams; handing one over is silent."""
        mock_run_json.return_value = {
            "title": "Reel With Sound",
            "duration": 30,
            "formats": [
                {
                    "format_id": "v1080",
                    "vcodec": "avc1.640028",
                    "acodec": "none",
                    "height": 1080,
                    "ext": "mp4",
                    "url": "https://example.com/video_only_1080.mp4",
                },
                {
                    "format_id": "v720",
                    "vcodec": "avc1.64001f",
                    "acodec": "none",
                    "height": 720,
                    "ext": "mp4",
                    "url": "https://example.com/video_only_720.mp4",
                },
            ],
        }
        job = MagicMock()
        job.id = "jobmerged"
        job.status = "ready"
        job.ext = "mp4"
        job.title = "Reel With Sound"
        job.duration = 30
        mock_new_job.return_value = job

        res = self.client.post(
            "/api/analyze",
            json={"url": "https://example.com/reel/1", "type": "video"},
        )

        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        mock_proxy_job.assert_not_called()
        self.assertIn("job=jobmerged", data["download_url"])
        self.assertEqual(data["ext"], "mp4")


class StreamValidationTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()

    def test_pick_direct_format_rejects_video_only_streams(self):
        video_only = {
            "vcodec": "avc1",
            "acodec": "none",
            "url": "https://example.com/v.mp4",
        }
        self.assertIsNone(server._pick_direct_format(dict(video_only), "video"))
        self.assertIsNone(
            server._pick_direct_format({"requested_formats": [video_only]}, "video")
        )

        progressive = {
            "vcodec": "avc1",
            "acodec": "mp4a.40.2",
            "url": "https://example.com/av.mp4",
        }
        self.assertEqual(
            server._pick_direct_format(progressive, "video")["url"],
            "https://example.com/av.mp4",
        )

    def test_audio_kind_rejects_progressive_video_stream(self):
        progressive = {
            "vcodec": "avc1",
            "acodec": "mp4a.40.2",
            "ext": "mp4",
            "url": "https://example.com/video.mp4",
        }
        self.assertIsNone(server._pick_direct_format(progressive, "audio"))

    def test_is_mp3_file_accepts_id3_and_mpeg_sync(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            id3_path = Path(tmp) / "with_id3.mp3"
            id3_path.write_bytes(b"ID3\x03\x00\x00\x00\x00\x00\x00")
            self.assertTrue(server._is_mp3_file(str(id3_path)))

            fake_mp3 = Path(tmp) / "fake.mp3"
            fake_mp3.write_bytes(b"\x00\x00\x00\x1cftypM4A ")
            self.assertFalse(server._is_mp3_file(str(fake_mp3)))

    def test_mp3_signature_accepts_raw_frame_sync(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            raw = Path(tmp) / "raw.mp3"
            raw.write_bytes(bytes([0xFF, 0xFB, 0x90, 0x64]))
            self.assertTrue(server._is_mp3_file(str(raw)))

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
