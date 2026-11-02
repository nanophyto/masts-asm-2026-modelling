"""Behavioral tests for safe once-per-home background preparation."""

from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

from warmup_workstation import fingerprint, ready, run_warmup, stages


class WorkstationWarmupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.workspace = self.home / "masts-asm-2026-modelling"
        self.source = self.root / "image-source"
        self.extension = self.home / ".codeoss-cloudworkstations/extensions/julialang.language-julia-1.250.2"
        self.sysimage = self.root / "science.so"
        for base in (self.workspace, self.source):
            (base / "oceanbiome/exercises").mkdir(parents=True)
            (base / "oceanbiome/Project.toml").write_text("name=\"MASTSWorkshop\"\n")
            (base / "oceanbiome/exercises/00_reference_column.jl").write_text("println(1)\n")
        for language, project in (("languageserver", "v1.11"), ("terminalserver", "v1.10")):
            p = self.extension / "scripts/environments" / language / project / "Project.toml"
            p.parent.mkdir(parents=True)
            p.write_text("[deps]\n")

    def warm(self, runner):
        return run_warmup(home=self.home, workspace=self.workspace, source=self.source,
                          extension=self.extension, sysimage=self.sysimage, runner=runner)

    def test_stages_use_distinct_editor_and_science_julia(self):
        work = list(stages(self.home, self.workspace, self.extension, self.source))
        self.assertEqual([item[0] for item in work], [
            "Two-day OceanBioME reference and plots", "Julia 1.11 language server",
            "Julia 1.10 editor REPL",
        ])
        self.assertEqual(work[0][1][0], "/opt/workshop/bin/julia")
        self.assertEqual(work[0][1][-1], "--quick")
        self.assertTrue(work[0][2]["MASTS_OUTPUT_DIR"].startswith(str(self.home / ".cache")))
        self.assertEqual(work[1][1][0], "/opt/julia-ls/bin/julia")
        self.assertEqual(work[2][1][0], "/opt/julia/bin/julia")

    def test_completes_once_and_preserves_user_files(self):
        original = self.workspace / "oceanbiome/exercises/00_reference_column.jl"
        calls = []
        original.write_text("println(42)\n")
        def runner(cmd, **kwargs):
            calls.append((cmd, kwargs))
        self.assertEqual(self.warm(runner), "ready")
        self.assertEqual(self.warm(runner), "ready")
        self.assertEqual(len(calls), 3)
        self.assertIn(str(self.source / "oceanbiome/exercises/00_reference_column.jl"), calls[0][0])
        self.assertNotIn(str(original), calls[0][0])
        self.assertEqual(original.read_text(), "println(42)\n")
        self.assertTrue(ready(self.home / ".cache/masts-workshop", fingerprint(self.source, self.sysimage)))
        status = json.loads((self.home / ".cache/masts-workshop/status.json").read_text())
        self.assertEqual(status["state"], "ready")
        self.assertEqual(len(status["steps"]), 3)
        self.assertEqual(calls[0][1]["env"]["MASTS_OUTPUT_DIR"],
                         str(self.home / ".cache/masts-workshop/reference-output"))
        self.assertEqual(calls[0][1]["cwd"], str(self.source))

    def test_failure_does_not_mark_ready_and_can_retry(self):
        def broken(cmd, **kwargs):
            raise subprocess.CalledProcessError(9, cmd)
        self.assertEqual(self.warm(broken), "failed")
        cache = self.home / ".cache/masts-workshop"
        self.assertFalse((cache / "complete.json").exists())
        self.assertEqual(json.loads((cache / "status.json").read_text())["state"], "failed")
        self.assertEqual(self.warm(lambda cmd, **kwargs: None), "ready")

    def test_new_image_invalidates_marker(self):
        calls = []
        self.warm(lambda cmd, **kwargs: calls.append(cmd))
        self.source.joinpath("oceanbiome/Project.toml").write_text("version=\"0.2\"\n")
        self.assertFalse(ready(self.home / ".cache/masts-workshop", fingerprint(self.source, self.sysimage)))
        self.warm(lambda cmd, **kwargs: calls.append(cmd))
        self.assertEqual(len(calls), 6)

    def test_missing_extension_environment_fails_after_reference_warms(self):
        (self.extension / "scripts/environments/languageserver/v1.11/Project.toml").unlink()
        calls = []
        self.assertEqual(self.warm(lambda cmd, **kwargs: calls.append(cmd)), "failed")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][-1], "--quick")
        status = json.loads((self.home / ".cache/masts-workshop/status.json").read_text())
        self.assertIn("language-server environment", status["error"])

    def test_sysimage_wrapper_supports_fallback_opt_out_and_explicit_override(self):
        wrapper = Path(__file__).with_name("workshop-julia")
        real = self.root / "fake-julia"
        real.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        real.chmod(0o755)
        env = {**os.environ, "MASTS_REAL_JULIA": str(real), "MASTS_SYSIMAGE": str(self.sysimage)}
        def invoke(*args, enabled="1"):
            return subprocess.check_output([str(wrapper), *args], text=True,
                                           env={**env, "MASTS_USE_SYSIMAGE": enabled}).splitlines()
        self.assertEqual(invoke("--version"), ["--version"])
        self.sysimage.write_bytes(b"placeholder")
        self.assertEqual(invoke("--version"), [f"--sysimage={self.sysimage}", "--version"])
        self.assertEqual(invoke("--version", enabled="0"), ["--version"])
        self.assertEqual(invoke("-J", "other.so", "--version"), ["-J", "other.so", "--version"])


if __name__ == "__main__":
    unittest.main()
