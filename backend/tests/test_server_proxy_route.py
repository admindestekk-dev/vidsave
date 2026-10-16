from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server


class DownloadRouteTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.original_api_key = server.API_KEY
        server.API_KEY = ""
        server._JOBS.clear()

    def tearDown(self):
        server.API_KEY = self.original_api_key
        server._JOBS.clear()

    def test_proxy_route_forwards_range_header_for_resolved_job(self):
        job = server.Job(
            id="test-job",
            kind="video",
            source="https://source.example/video",
            status="ready",
            filename="video.mp4",
            direct_url="https://cdn.example/video.mp4",
            mime="video/mp4",
        )
        server._JOBS[job.id] = job

        with patch.object(server, "stream_upstream_response", return_value=("stream", 206)) as proxy:
            response = self.client.get(
                "/download?job=test-job", headers={"Range": "bytes=0-10"}
            )

        self.assertEqual(response.status_code, 206)
        proxy.assert_called_once_with(job, "bytes=0-10")

    def test_job_payload_includes_id_for_polling(self):
        job = server.Job(
            id="pollable-job",
            kind="audio",
            source="https://source.example/audio",
            status="running",
        )

        self.assertEqual(server._job_payload(job)["job"], "pollable-job")

    def test_resolve_rejects_invalid_source_before_starting_job(self):
        with (
            patch.object(server, "validate_public_http_url", side_effect=ValueError),
            patch.object(server.threading, "Thread") as thread,
        ):
            response = self.client.post(
                "/api/resolve", json={"url": "http://127.0.0.1/private"}
            )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"]["code"], "url.invalid")
        thread.assert_not_called()


if __name__ == "__main__":
    unittest.main()
