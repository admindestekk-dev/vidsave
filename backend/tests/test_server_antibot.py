from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server


def _ok(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(cmd, 0, "{}", "")


def _fail(cmd: list[str], stderr: str) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(cmd, 1, "", stderr)


class ProxyRotationTests(unittest.TestCase):
    def test_proxy_flag_is_added_only_when_configured(self):
        self.assertNotIn("--proxy", server._base_args())

        args = server._base_args(proxy="http://proxy.example:8080")
        self.assertIn("--proxy", args)
        self.assertEqual(
            args[args.index("--proxy") + 1], "http://proxy.example:8080"
        )

    def test_proxy_pool_rotates_per_attempt(self):
        with patch.object(server, "PROXY_POOL", ["http://a:1", "http://b:2"]):
            self.assertEqual(server._proxy_for_attempt(0), "http://a:1")
            self.assertEqual(server._proxy_for_attempt(1), "http://b:2")
            self.assertEqual(server._proxy_for_attempt(2), "http://a:1")

    def test_proxy_is_removed_when_not_configured(self):
        args = server._set_proxy(
            server._base_args(proxy="http://proxy.example:8080"), None
        )
        self.assertNotIn("--proxy", args)
        self.assertNotIn("http://proxy.example:8080", args)


class PlayerClientLadderTests(unittest.TestCase):
    def test_youtube_client_is_replaced_not_duplicated(self):
        args = server._base_args(youtube_client="ios") + ["--", "https://x.test"]
        updated = server._replace_youtube_client(args, "tv")

        youtube_args = [
            value
            for index, value in enumerate(updated)
            if index > 0
            and updated[index - 1] == "--extractor-args"
            and value.startswith("youtube:player_client=")
        ]
        self.assertEqual(youtube_args, ["youtube:player_client=tv"])
        # The URL separator must stay last so the URL is still passed through.
        self.assertEqual(updated[-2:], ["--", "https://x.test"])

    def test_bot_check_walks_to_the_next_client(self):
        cmd = server._base_args(youtube_client="ios") + ["--", "https://x.test"]
        calls: list[list[str]] = []

        def fake_run(command, **kwargs):
            calls.append(list(command))
            if len(calls) == 1:
                return _fail(
                    command, "ERROR: Sign in to confirm you're not a bot"
                )
            return _ok(command)

        with (
            patch.object(server, "subprocess") as mocked_subprocess,
            patch.object(server.time, "sleep") as sleep,
        ):
            mocked_subprocess.run.side_effect = fake_run
            result = server._execute_ytdlp(cmd, timeout=10)

        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(calls), 2)
        expected_client = server.YT_CLIENT_LADDER[0]
        self.assertIn(f"youtube:player_client={expected_client}", calls[1])
        sleep.assert_called_once()

    def test_rate_limit_rotates_egress_proxy(self):
        cmd = server._base_args() + ["--", "https://x.test"]
        calls: list[list[str]] = []

        def fake_run(command, **kwargs):
            calls.append(list(command))
            if len(calls) == 1:
                return _fail(command, "ERROR: HTTP Error 403: Forbidden")
            return _ok(command)

        with (
            patch.object(server, "PROXY_POOL", ["http://a:1", "http://b:2"]),
            patch.object(server, "subprocess") as mocked_subprocess,
            patch.object(server.time, "sleep"),
        ):
            mocked_subprocess.run.side_effect = fake_run
            result = server._execute_ytdlp(cmd, timeout=10)

        self.assertEqual(result.returncode, 0)
        self.assertIn("http://a:1", calls[0])
        self.assertIn("http://b:2", calls[1])

    def test_unrecognised_failure_is_not_retried(self):
        cmd = server._base_args() + ["--", "https://x.test"]

        with (
            patch.object(server, "subprocess") as mocked_subprocess,
            patch.object(server.time, "sleep") as sleep,
        ):
            mocked_subprocess.run.return_value = _fail(
                cmd, "ERROR: Unsupported URL"
            )
            result = server._execute_ytdlp(cmd, timeout=10)

        self.assertEqual(result.returncode, 1)
        self.assertEqual(mocked_subprocess.run.call_count, 1)
        sleep.assert_not_called()


class AntiBotStatusTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.original_api_key = server.API_KEY
        server.API_KEY = ""

    def tearDown(self):
        server.API_KEY = self.original_api_key

    def test_status_reports_strategy_without_leaking_proxy_credentials(self):
        secret_proxy = "http://user:supersecret@proxy.example:8080"
        with patch.object(server, "PROXY_POOL", [secret_proxy, secret_proxy]):
            response = self.client.get("/api/anti-bot/status")

        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data["egress"]["proxyCount"], 2)
        self.assertTrue(data["egress"]["rotatesOnRateLimit"])
        self.assertEqual(data["retries"]["jitterPercent"], 30)
        self.assertIn(data["extractor"]["youtubePlayerClient"], {"ios,android,web", data["extractor"]["youtubePlayerClient"]})
        self.assertNotIn("supersecret", response.get_data(as_text=True))

    def test_status_requires_configured_api_key(self):
        server.API_KEY = "test-api-key"
        response = self.client.get("/api/anti-bot/status")
        self.assertEqual(response.status_code, 401)


if __name__ == "__main__":
    unittest.main()
