from __future__ import annotations

import sqlite3
import sys
import tempfile
from contextlib import closing
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
        if server.COOKIES_BROWSER:
            self.assertIn("--cookies-from-browser", args)
            self.assertEqual(args[args.index("--cookies-from-browser") + 1], server.COOKIES_BROWSER)
        else:
            self.assertNotIn("--cookies-from-browser", args)
        self.assertIn("--impersonate", args)
        self.assertEqual(args[args.index("--impersonate") + 1], "chrome")
        self.assertIn("--extractor-args", args)
        self.assertTrue(args[args.index("--extractor-args") + 1].startswith("youtube:player_client=ios"))

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


class PlatformSpecificTests(unittest.TestCase):
    def test_pinterest_url_is_cleaned(self):
        raw = "https://www.pinterest.com/pin/123456789/?inviter_user_id=98765&sender=54321"
        source, mode = server.resolve_source_input(raw)
        self.assertEqual(source, "https://www.pinterest.com/pin/123456789")
        self.assertEqual(mode, "url")

    def test_pinterest_args_include_specialized_ua_and_referer(self):
        args = server._base_args(source_url="https://www.pinterest.com/pin/123456789")
        self.assertIn(server.PINTEREST_UA, args)
        self.assertIn("https://www.pinterest.com/", args)

    def test_clean_song_title_removes_noise_tags(self):
        cases = [
            ("Sagopa Kajmer - Ateşten Gömlek (Official Video)", "Sagopa Kajmer - Ateşten Gömlek"),
            ("Eminem - Without Me [Official Music Video] (HD)", "Eminem - Without Me"),
            ("Dua Lipa - Levitating (feat. DaBaby) [Official Lyrics Video]", "Dua Lipa - Levitating"),
            ("BLOK3 - BAYBAY (Official Video)", "BLOK3 - BAYBAY"),
            ("Sefo - Bilmem Mi? (prod. Aerro) [Official Video]", "Sefo - Bilmem Mi?"),
        ]
        for raw, expected in cases:
            with self.subTest(raw=raw):
                self.assertEqual(server.clean_song_title(raw), expected)

    def test_tiktok_args_include_bot_mask_and_headers(self):
        args = server._base_args(source_url="https://www.tiktok.com/@user/video/123456789")
        self.assertIn(server.TIKTOK_UA, args)
        self.assertIn("https://tiktok.com", args)
        self.assertIn("Accept-Language:en-US,en;q=0.5", args)
        self.assertIn("Origin:https://tiktok.com", args)
        self.assertIn("Sec-Fetch-Mode:cors", args)
        self.assertIn("Sec-Fetch-Site:same-site", args)
        self.assertIn("tiktok:web_search=", args)

    def test_ydl_opts_tiktok_configuration(self):
        self.assertIn("tiktok", server.ydl_opts["extractor_args"])
        self.assertEqual(server.ydl_opts["extractor_args"]["tiktok"], {"web_search": [""]})
        headers = server.ydl_opts["http_headers"]
        self.assertEqual(headers["User-Agent"], server.TIKTOK_UA)
        self.assertEqual(headers["Referer"], "https://tiktok.com")
        self.assertEqual(headers["Origin"], "https://tiktok.com")
        self.assertEqual(headers["Sec-Fetch-Mode"], "cors")
        self.assertEqual(headers["Sec-Fetch-Site"], "same-site")
        self.assertEqual(headers["Accept-Language"], "en-US,en;q=0.5")
        self.assertEqual(server.ydl_opts["buffersize"], 1024 * 16)
        self.assertEqual(server.ydl_opts["external_downloader_args"], ["--min-chunk-size", "1M"])
        self.assertEqual(server.ydl_opts["hls_use_mpegts"], True)
        self.assertEqual(server.ydl_opts["http_chunk_size"], 1024 * 1024)


class SubscriptionMonthlyTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self._temporary_directory = tempfile.TemporaryDirectory()
        self._original_db_path = server.DB_PATH
        self._original_api_key = server.API_KEY
        server.DB_PATH = str(Path(self._temporary_directory.name) / "test.db")
        server.API_KEY = ""
        server._init_db()

    def tearDown(self):
        server.DB_PATH = self._original_db_path
        server.API_KEY = self._original_api_key
        server._JOBS.clear()
        self._temporary_directory.cleanup()

    def test_turkish_subscription_accounting_is_9_99_try(self):
        res = self.client.post("/api/auth/subscribe-monthly", json={"lang": "tr", "userId": "11111111-1111-4111-8111-111111111111"})
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertTrue(data["success"])
        sub = data["subscription"]
        self.assertEqual(sub["amount"], 9.99)
        self.assertEqual(sub["currency"], "TRY")
        self.assertEqual(sub["lang"], "tr")
        self.assertIn("9,99 TL (KDV Dahil)", sub["receiptMessage"])

    def test_english_subscription_accounting_is_0_99_usd(self):
        res = self.client.post("/api/auth/subscribe-monthly", json={"lang": "en", "userId": "22222222-2222-4222-8222-222222222222"})
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertTrue(data["success"])
        sub = data["subscription"]
        self.assertEqual(sub["amount"], 0.99)
        self.assertEqual(sub["currency"], "USD")
        self.assertEqual(sub["lang"], "en")
        self.assertIn("$0.99 (All taxes included)", sub["receiptMessage"])


    def test_verify_purchase_extends_premium_until_by_30_days(self):
        res = self.client.post("/api/auth/verify-purchase", json={
            "token": "google_play_purchase_token_xyz_123",
            "productId": "vidsave_premium_monthly",
            "userId": "33333333-3333-4333-8333-333333333333",
            "lang": "tr",
        })
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertTrue(data["success"])
        self.assertTrue(data["verified"])
        self.assertEqual(data["userId"], "33333333-3333-4333-8333-333333333333")
        self.assertIn("premiumUntil", data)
        self.assertIn("30 gün uzatıldı", data["receiptMessage"])

    def test_verify_purchase_missing_token_returns_bad_request(self):
        res = self.client.post("/api/auth/verify-purchase", json={
            "productId": "vidsave_premium_monthly",
            "userId": "33333333-3333-4333-8333-333333333333",
        })
        self.assertEqual(res.status_code, 400)
        data = res.get_json()
        self.assertEqual(data["error"]["code"], "token.missing")


    def test_delete_account_only_deletes_the_requested_installation(self):
        user_a = "11111111-1111-4111-8111-111111111111"
        user_b = "22222222-2222-4222-8222-222222222222"
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            for user_id in (user_a, user_b):
                conn.execute(
                    "INSERT INTO user_subscriptions (user_id) VALUES (?)",
                    (user_id,),
                )
                conn.execute(
                    "INSERT INTO subscriptions (id, user_id, lang, amount, currency, status) "
                    "VALUES (?, ?, 'tr', 9.99, 'TRY', 'active')",
                    (f"sub_{user_id}", user_id),
                )
            conn.execute(
                "INSERT INTO user_cookies (platform, cookies) VALUES ('instagram', 'session=shared')"
            )
            conn.commit()

        job = server._new_job("video", "https://example.com/video")
        response = self.client.post(
            "/api/auth/delete-account", json={"userId": user_a}
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.get_json()["success"])
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            subscriptions = conn.execute(
                "SELECT user_id FROM user_subscriptions ORDER BY user_id"
            ).fetchall()
            invoices = conn.execute(
                "SELECT user_id FROM subscriptions ORDER BY user_id"
            ).fetchall()
            cookies = conn.execute("SELECT cookies FROM user_cookies").fetchall()
            jobs = conn.execute("SELECT id FROM jobs WHERE id = ?", (job.id,)).fetchall()

        self.assertEqual(subscriptions, [(user_b,)])
        self.assertEqual(invoices, [(user_b,)])
        self.assertEqual(cookies, [("session=shared",)])
        self.assertEqual(jobs, [(job.id,)])
        self.assertIn(job.id, server._JOBS)

    def test_delete_account_rejects_missing_or_invalid_user_id(self):
        for user_id in (None, "device_user", "guest", "not-a-uuid"):
            with self.subTest(user_id=user_id):
                payload = {} if user_id is None else {"userId": user_id}
                response = self.client.post("/api/auth/delete-account", json=payload)
                self.assertEqual(response.status_code, 400)
                self.assertEqual(
                    response.get_json()["error"]["code"], "user.id_invalid"
                )

    def test_delete_account_requires_configured_api_key(self):
        user_id = "11111111-1111-4111-8111-111111111111"
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            conn.execute(
                "INSERT INTO user_subscriptions (user_id) VALUES (?)", (user_id,)
            )
            conn.commit()

        server.API_KEY = "test-api-key"
        response = self.client.post(
            "/api/auth/delete-account", json={"userId": user_id}
        )
        self.assertEqual(response.status_code, 401)
        with closing(sqlite3.connect(server.DB_PATH)) as conn:
            count = conn.execute(
                "SELECT COUNT(*) FROM user_subscriptions WHERE user_id = ?",
                (user_id,),
            ).fetchone()[0]
        self.assertEqual(count, 1)


if __name__ == "__main__":
    unittest.main()
