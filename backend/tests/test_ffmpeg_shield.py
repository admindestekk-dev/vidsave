"""Test FFmpeg and Bot Shield Configuration."""
from pathlib import Path
import unittest

import app as root_app
import backend.app as backend_app
import backend.server as server


class FfmpegShieldTests(unittest.TestCase):
    def test_app_ydl_opts_configuration(self):
        for app_mod in (root_app, backend_app):
            opts = app_mod.ydl_opts
            self.assertEqual(opts.get("format"), "bestaudio/best")
            self.assertTrue(opts.get("extract_audio"))
            self.assertEqual(opts.get("audio_format"), "mp3")
            self.assertEqual(opts.get("outtmpl"), "%(title)s.%(ext)s")
            self.assertTrue(opts.get("no_warnings"))
            self.assertTrue(opts.get("quiet"))
            self.assertIsNone(opts.get("cookiesfrombrowser"))

            headers = opts.get("http_headers", {})
            self.assertIn("Chrome/126.0.0.0", headers.get("User-Agent", ""))
            self.assertEqual(headers.get("Accept-Language"), "tr-TR,tr;q=0.9,en-US;q=0.8")

    def test_requirements_txt_pinning(self):
        root_dir = Path(__file__).resolve().parent.parent.parent
        for req_path in (root_dir / "requirements.txt", root_dir / "backend" / "requirements.txt"):
            lines = [line.strip().lower() for line in req_path.read_text(encoding="utf-8").splitlines() if line.strip()]
            # curl-cffi backs yt-dlp's --impersonate flag; without it every
            # extraction is retried without impersonation.
            self.assertEqual(
                lines,
                ["flask", "flask-cors", "requests", "yt-dlp", "curl-cffi", "gunicorn"],
            )

    def test_audio_format_selector_uses_bestaudio(self):
        selector = server._format_selector("audio")
        self.assertIn("bestaudio", selector)


if __name__ == "__main__":
    unittest.main()
