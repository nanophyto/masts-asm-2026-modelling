"""Checks for the optional low-memory PackageCompiler build."""

from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import sys
import tempfile
import unittest

from measure_sysimage_memory import measure


class SysimageMemoryTests(unittest.TestCase):
    def test_monitor_reports_cgroup_memory_and_propagates_exit_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            cgroup = Path(tmp)
            (cgroup / "memory.current").write_text("104857600\n")
            (cgroup / "memory.peak").write_text("209715200\n")
            (cgroup / "memory.max").write_text("1073741824\n")
            output = StringIO()
            script = ("from pathlib import Path; import time; "
                      f"Path({str(cgroup / 'memory.current')!r}).write_text('314572800'); "
                      "time.sleep(0.1); raise SystemExit(7)")
            with redirect_stdout(output):
                status = measure([sys.executable, "-c", script],
                                 cgroup=cgroup, poll_seconds=0.01)
            self.assertEqual(status, 7)
            for expected in ("starting cgroup usage=100 MiB", "sampled peak=300 MiB",
                             "cgroup lifetime peak=200 MiB", "cgroup limit=1024 MiB"):
                self.assertIn(expected, output.getvalue())

    def test_monitor_runs_without_cgroup_accounting(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = StringIO()
            with redirect_stdout(output):
                status = measure([sys.executable, "-c", "print('done')"],
                                 cgroup=Path(tmp), poll_seconds=0.01)
            self.assertEqual(status, 0)
            self.assertIn("sampled peak=unavailable", output.getvalue())

    def test_optional_build_controls_image_codegen_threads(self):
        dockerfile = Path(__file__).with_name("Dockerfile").read_text()
        for expected in ("ARG SYSIMAGE_IMAGE_THREADS=1",
                         'JULIA_IMAGE_THREADS="$SYSIMAGE_IMAGE_THREADS"',
                         "JULIA_IMAGE_TIMINGS=1", "container/measure_sysimage_memory.py",
                         "RUN set -eu;", "test -s /opt/workshop/sysimages/masts-workshop.so"):
            self.assertIn(expected, dockerfile)


if __name__ == "__main__":
    unittest.main()
