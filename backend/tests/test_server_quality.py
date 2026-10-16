import json
import unittest
from unittest.mock import MagicMock, patch

from backend.server import app


class ServerQualityTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    @patch("backend.server._run_json")
    def test_info_probe_returns_available_qualities(self, mock_run_json):
        mock_run_json.return_value = {
            "title": "Sample 4K Nature Video",
            "duration": 120,
            "uploader": "NatureChannel",
            "formats": [
                {"height": 1080, "filesize": 50000000, "vcodec": "avc1"},
                {"height": 720, "filesize": 25000000, "vcodec": "avc1"},
                {"height": 480, "filesize": 12000000, "vcodec": "avc1"},
                {"height": None, "filesize": 5000000, "vcodec": "none"},  # audio only, ignored
            ],
        }

        response = self.client.post(
            "/api/resolve",
            json={
                "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "kind": "video",
                "info": True,
            },
        )
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data["status"], "info")
        self.assertEqual(data["title"], "Sample 4K Nature Video")
        self.assertEqual(data["duration"], 120)
        self.assertEqual(data["uploader"], "NatureChannel")
        qualities = data["qualities"]
        self.assertEqual(len(qualities), 3)
        self.assertEqual(qualities[0]["height"], 1080)
        self.assertEqual(qualities[0]["label"], "1080p")
        self.assertEqual(qualities[1]["height"], 720)
        self.assertEqual(qualities[2]["height"], 480)

    @patch("backend.server.validate_public_http_url")
    @patch("backend.server._run_json")
    @patch("backend.server._pick_direct_format")
    def test_height_is_passed_to_format_selector(
        self, mock_pick_direct, mock_run_json, mock_validate
    ):
        mock_run_json.return_value = {
            "title": "Short Clip",
            "url": "https://cdn.example/video_720.mp4",
            "ext": "mp4",
        }
        mock_pick_direct.return_value = {
            "url": "https://cdn.example/video_720.mp4",
            "ext": "mp4",
        }

        response = self.client.post(
            "/api/resolve",
            json={
                "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "kind": "video",
                "height": 720,
            },
        )
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data["status"], "ready")
        self.assertEqual(data["height"], 720)

    @patch("backend.server.validate_public_http_url")
    @patch("backend.server._run_json")
    @patch("backend.server._pick_direct_format")
    def test_polling_with_height_and_job_id_reuses_existing_job(
        self, mock_pick_direct, mock_run_json, mock_validate
    ):
        mock_run_json.return_value = {
            "title": "Short Clip",
            "url": "https://cdn.example/video_720.mp4",
            "ext": "mp4",
        }
        mock_pick_direct.return_value = {
            "url": "https://cdn.example/video_720.mp4",
            "ext": "mp4",
        }

        # First request creates the job
        res1 = self.client.post(
            "/api/resolve",
            json={
                "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "kind": "video",
                "height": 720,
            },
        )
        self.assertEqual(res1.status_code, 200)
        job_id = res1.get_json()["job"]

        # Second poll request carries url + height + job: must return same job!
        res2 = self.client.post(
            "/api/resolve",
            json={
                "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "kind": "video",
                "height": 720,
                "job": job_id,
            },
        )
        self.assertEqual(res2.status_code, 200)
        data2 = res2.get_json()
        self.assertEqual(data2["job"], job_id)
        self.assertEqual(data2["status"], "ready")

    def test_invalid_height_returns_bad_request(self):
        response = self.client.post(
            "/api/resolve",
            json={
                "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                "height": "not-a-number",
            },
        )
        self.assertEqual(response.status_code, 400)
        data = response.get_json()
        self.assertEqual(data["error"]["code"], "quality.invalid")

    @patch("backend.server._run_json")
    def test_search_query_like_blok3_resolves_and_probes(self, mock_run_json):
        mock_run_json.return_value = {
            "title": "BLOK3 - BAYBAY (Official Video)",
            "duration": 154,
            "uploader": "BLOK3",
            "webpage_url": "https://www.youtube.com/watch?v=mock123",
            "formats": [
                {"height": 1080, "filesize": 40000000, "vcodec": "avc1"},
                {"height": 720, "filesize": 20000000, "vcodec": "avc1"},
            ],
        }

        # User types search phrase "blok3 indir" instead of a raw URL
        response = self.client.post(
            "/api/resolve",
            json={
                "url": "blok3 indir",
                "kind": "video",
                "info": True,
            },
        )
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data["status"], "info")
        self.assertEqual(data["inputMode"], "search")
        self.assertEqual(data["title"], "BLOK3 - BAYBAY (Official Video)")
        self.assertEqual(len(data["qualities"]), 2)
        self.assertEqual(data["qualities"][0]["height"], 1080)
        self.assertEqual(data["qualities"][1]["height"], 720)


if __name__ == "__main__":
    unittest.main()
