from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server


class SmartInputTests(unittest.TestCase):
    """The UI text box accepts both a URL and a plain search phrase."""

    def test_direct_urls_are_passed_through(self):
        for value in (
            "https://www.youtube.com/watch?v=abc123",
            "http://vimeo.com/12345",
            "youtu.be/abc123",
            "www.youtube.com/watch?v=x",
            "example.com/video.mp4",
        ):
            source, mode = server.resolve_source_input(value)
            self.assertEqual(source, value)
            self.assertEqual(mode, "url")

    def test_plain_text_becomes_youtube_search(self):
        source, mode = server.resolve_source_input("Sagopa Kajmer")
        self.assertEqual(source, "ytsearch1:Sagopa Kajmer")
        self.assertEqual(mode, "search")

        source, mode = server.resolve_source_input("komik videolar")
        self.assertEqual(source, "ytsearch1:komik videolar")
        self.assertEqual(mode, "search")

    def test_existing_search_prefix_is_respected(self):
        source, mode = server.resolve_source_input("ytsearch5:test")
        self.assertEqual(source, "ytsearch5:test")
        self.assertEqual(mode, "search")

    def test_empty_input_raises(self):
        with self.assertRaises(ValueError):
            server.resolve_source_input("   ")


class ResolveSearchRoutingTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.original_api_key = server.API_KEY
        server.API_KEY = ""
        server._JOBS.clear()

    def tearDown(self):
        server.API_KEY = self.original_api_key
        server._JOBS.clear()

    def test_search_text_is_not_ssrf_validated_but_starts_a_job(self):
        captured = {}

        def fake_work(job):
            captured["source"] = job.source
            captured["mode"] = job.mode
            job.status = "ready"
            job.title = "Top hit"

        with (
            patch.object(server, "validate_public_http_url") as validate,
            patch.object(server, "_work", side_effect=fake_work),
        ):
            response = self.client.post(
                "/api/resolve", json={"url": "Sagopa Kajmer", "kind": "audio"}
            )

        self.assertEqual(response.status_code, 200)
        validate.assert_not_called()
        self.assertEqual(captured["source"], "ytsearch1:Sagopa Kajmer")
        self.assertEqual(captured["mode"], "search")
        # The payload reports how the input was interpreted as `inputMode`;
        # `mode` is reserved for the transfer mode ("proxy").
        self.assertEqual(response.get_json()["inputMode"], "search")

    def test_url_input_is_ssrf_validated(self):
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

    def test_query_field_is_accepted_as_alias_for_url(self):
        captured = {}

        def fake_work(job):
            captured["source"] = job.source
            job.status = "ready"

        with patch.object(server, "_work", side_effect=fake_work):
            response = self.client.post(
                "/api/resolve", json={"query": "komik videolar"}
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(captured["source"], "ytsearch1:komik videolar")

    def test_poll_with_only_a_job_id_does_not_require_input(self):
        """The client must be able to poll with `{"job": id}` and nothing else."""
        with patch.object(server, "_work") as work:
            started = self.client.post(
                "/api/resolve", json={"url": "Sagopa Kajmer", "kind": "audio"}
            )
        work.assert_called_once()
        job_id = started.get_json()["job"]

        response = self.client.post("/api/resolve", json={"job": job_id})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["job"], job_id)

    def test_poll_with_unknown_job_id_reports_not_found(self):
        response = self.client.post("/api/resolve", json={"job": "does-not-exist"})
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.get_json()["error"]["code"], "job.not_found")


class SearchDownloadArgsTests(unittest.TestCase):
    """A `ytsearch:` source must NOT receive `--no-playlist`."""

    def test_search_source_omits_no_playlist(self):
        args = server._base_args(allow_playlist_items=True)
        self.assertNotIn("--no-playlist", args)
        # Speed knobs must always be present.
        self.assertIn("--concurrent-fragments", args)

    def test_plain_url_keeps_no_playlist(self):
        args = server._base_args()
        self.assertIn("--no-playlist", args)

    def test_universal_bypass_options_present(self):
        args = server._base_args()
        self.assertIn("--cookies-from-browser", args)
        self.assertEqual(args[args.index("--cookies-from-browser") + 1], "chrome")
        self.assertIn("--impersonate", args)
        self.assertEqual(args[args.index("--impersonate") + 1], "chrome")
        self.assertIn("--extractor-args", args)
        self.assertEqual(args[args.index("--extractor-args") + 1], "youtube:player_client=ios")

    def test_is_search_source_detection(self):
        self.assertTrue(server._is_search_source("ytsearch1:Sagopa"))
        self.assertTrue(server._is_search_source("ytsearch5:test"))
        self.assertFalse(server._is_search_source("https://youtube.com/watch?v=x"))

    def test_search_empty_detection(self):
        empty_playlist = {"_type": "playlist", "entries": []}
        self.assertFalse(server._search_has_result(empty_playlist))
        populated = {"_type": "playlist", "entries": [{"id": "abc", "url": "u"}]}
        self.assertTrue(server._search_has_result(populated))
        single = {"url": "https://cdn/x", "formats": [{"url": "u"}]}
        self.assertTrue(server._search_has_result(single))


if __name__ == "__main__":
    unittest.main()
