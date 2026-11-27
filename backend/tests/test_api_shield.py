from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from werkzeug.middleware.proxy_fix import ProxyFix

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


class ApiShieldTests(unittest.TestCase):
    def setUp(self):
        self.original_key = server.API_KEY
        self.rate_limit = int(server.RATE_LIMIT.split()[0])
        server.API_KEY = "test-key"
        server.limiter.reset()
        self.client = server.app.test_client()

    def tearDown(self):
        server.API_KEY = self.original_key
        server.limiter.reset()

    def test_api_and_download_require_key_even_when_not_configured(self):
        for path in ("/api/ping", "/api/analyze", "/api/lyrics", "/download"):
            missing = self.client.get(path)
            self.assertEqual(missing.status_code, 401)
            self.assertEqual(missing.get_json()["error"]["code"], "api_key.invalid")
            invalid = self.client.get(path, headers={"X-Api-Key": "wrong"})
            self.assertEqual(invalid.status_code, 401)
            self.assertEqual(invalid.get_json()["error"]["code"], "api_key.invalid")
        self.assertEqual(
            self.client.get("/api/ping", headers={"X-Api-Key": "test-key"}).status_code,
            200,
        )
        server.API_KEY = ""
        missing_configuration = self.client.get(
            "/api/ping", headers={"X-Api-Key": "test-key"}
        )
        self.assertEqual(missing_configuration.status_code, 503)
        self.assertEqual(
            missing_configuration.get_json()["error"]["code"],
            "api_key.not_configured",
        )
        self.assertIn(
            "VIDSAVE_API_KEY",
            missing_configuration.get_json()["error"]["message"],
        )

    def test_loads_dotenv_without_overriding_process_environment(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            env_path = Path(temporary_directory) / ".env"
            env_path.write_text("VIDSAVE_API_KEY=dotenv-test-key\n", encoding="utf-8")

            with patch.dict(os.environ):
                os.environ.pop("VIDSAVE_API_KEY", None)
                server._load_environment(env_path)
                self.assertEqual(os.environ["VIDSAVE_API_KEY"], "dotenv-test-key")

            with patch.dict(os.environ, {"VIDSAVE_API_KEY": "process-test-key"}):
                server._load_environment(env_path)
                self.assertEqual(os.environ["VIDSAVE_API_KEY"], "process-test-key")

    def test_limit_is_shared_between_routes_and_separate_per_ip(self):
        headers = {"X-Api-Key": "test-key"}
        for index in range(self.rate_limit):
            path = "/api/ping" if index % 2 == 0 else "/download"
            response = self.client.get(
                path, headers=headers, environ_base={"REMOTE_ADDR": "192.0.2.1"}
            )
            self.assertNotEqual(response.status_code, 429)
        self.assertEqual(
            self.client.get(
                "/api/ping", headers=headers, environ_base={"REMOTE_ADDR": "192.0.2.1"}
            ).status_code,
            429,
        )
        self.assertEqual(
            self.client.get(
                "/api/ping", headers=headers, environ_base={"REMOTE_ADDR": "192.0.2.2"}
            ).status_code,
            200,
        )

    def test_unauthorized_requests_are_rate_limited(self):
        for _ in range(self.rate_limit):
            self.assertEqual(self.client.get("/api/ping").status_code, 401)
        self.assertEqual(self.client.get("/api/ping").status_code, 429)

    def test_render_proxy_chain_ignores_spoofed_leftmost_address(self):
        original_wsgi_app = server.app.wsgi_app
        server.app.wsgi_app = ProxyFix(original_wsgi_app, x_for=3)
        try:
            for index in range(self.rate_limit):
                response = self.client.get(
                    "/api/ping",
                    headers={
                        "X-Api-Key": "test-key",
                        "X-Forwarded-For": f"198.51.100.{index + 1}, 192.0.2.1, 192.0.2.2, 192.0.2.3",
                    },
                )
                self.assertEqual(response.status_code, 200)
            self.assertEqual(
                self.client.get(
                    "/api/ping",
                    headers={
                        "X-Api-Key": "test-key",
                        "X-Forwarded-For": "198.51.100.50, 192.0.2.1, 192.0.2.2, 192.0.2.3",
                    },
                ).status_code,
                429,
            )
        finally:
            server.app.wsgi_app = original_wsgi_app

    def test_preflight_and_health_check_do_not_need_a_key(self):
        self.assertIn(self.client.options("/api/analyze").status_code, (200, 204))
        self.assertEqual(self.client.get("/").status_code, 200)


if __name__ == "__main__":
    unittest.main()
