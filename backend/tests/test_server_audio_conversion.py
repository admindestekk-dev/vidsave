from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server


class AudioConversionTests(unittest.TestCase):
    def test_audio_download_converts_single_file_m4a_to_mp3(self):
        info = {
            "title": "test-audio",
            "url": "https://cdn.example/test-audio.m4a",
            "ext": "m4a",
            "vcodec": "none",
            "acodec": "mp4a.40.2",
        }

        with tempfile.TemporaryDirectory() as work_dir:
            job = server.Job(
                id="audio-job",
                kind="audio",
                source="https://media.example/manifest.mpd",
            )

            def fake_run(command, **_kwargs):
                self.assertIn("-x", command)
                self.assertEqual(command[command.index("--audio-format") + 1], "mp3")
                self.assertEqual(command[command.index("--audio-quality") + 1], "0")
                output = Path(work_dir, "audio-job.mp3")
                output.write_bytes(b"ID3 test audio")
                return subprocess.CompletedProcess(command, 0, "", "")

            with (
                patch.object(server, "_run_json", return_value=info),
                patch.object(server, "FFMPEG_PATH", "ffmpeg"),
                patch.object(server, "WORK_DIR", work_dir),
                patch.object(server.subprocess, "run", side_effect=fake_run),
            ):
                server._work(job)

        self.assertEqual(job.status, "ready")
        self.assertEqual(job.ext, "mp3")
        self.assertEqual(job.mime, "audio/mpeg")
        self.assertEqual(job.filename, "test-audio.mp3")
        self.assertTrue(job.filepath.endswith("audio-job.mp3"))


if __name__ == "__main__":
    unittest.main()
