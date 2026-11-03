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

    def test_sysimage_workload_uses_only_tested_library_imports(self):
        # Any modelling callback here would duplicate workshop code and create
        # another signature to maintain (the source of the two build failures).
        workload = Path(__file__).with_name('precompile_reference.jl').read_text()
        statements = [line.strip() for line in workload.splitlines()
                      if line.strip() and not line.lstrip().startswith('#')]
        self.assertEqual(statements, ['using OceanBioME, Oceananigans, CairoMakie'])

    def test_fallback_switch_preserves_expensive_layers(self):
        dockerfile = Path(__file__).with_name('Dockerfile').read_text()
        fallback = dockerfile.index('ARG COMPILE_WORKSHOP_SYSIMAGE=1')
        for marker in ('pip install --no-cache-dir -r abil/requirements.txt',
                       'Pkg.instantiate()', 'Pkg.precompile()',
                       'PackageSpec(name="PackageCompiler", version="2.2.5")'):
            self.assertLess(dockerfile.index(marker), fallback)
        self.assertIn('if [ "$BUILD_WORKSHOP_SYSIMAGE" = "1" ] && [ "$COMPILE_WORKSHOP_SYSIMAGE" = "1" ]; then', dockerfile)
        self.assertGreater(dockerfile.index('COPY . /opt/workshop/source'), fallback)
        self.assertIn('!isempty(methods(MASTSWorkshop.plot_reference_export))', dockerfile)

    def test_optional_build_controls_image_codegen_threads(self):
        dockerfile = Path(__file__).with_name("Dockerfile").read_text()
        for expected in ("ARG SYSIMAGE_IMAGE_THREADS=1",
                         'JULIA_IMAGE_THREADS="$SYSIMAGE_IMAGE_THREADS"',
                         "JULIA_IMAGE_TIMINGS=1", "container/measure_sysimage_memory.py",
                         "RUN set -eu;", "test -s /opt/workshop/sysimages/masts-workshop.so",
                         "ENV JULIA_NUM_PRECOMPILE_TASKS=1", "OMP_NUM_THREADS=1",
                         "MKL_NUM_THREADS=1", "Sysimage concurrency:"):
            self.assertIn(expected, dockerfile)
        limits = dockerfile.index("ENV JULIA_NUM_PRECOMPILE_TASKS=1")
        for cached_step in ("pip install --no-cache-dir", "Pkg.instantiate()",
                            "Pkg.precompile()", 'Pkg.add(Pkg.PackageSpec(name="PackageCompiler"'):
            self.assertLess(dockerfile.index(cached_step), limits)
        self.assertLess(limits, dockerfile.index("MASTS_MEMORY_PHASE=create-sysimage"))


if __name__ == "__main__":
    unittest.main()
