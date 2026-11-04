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
            (base / "workshop/01_OceanBioME").mkdir(parents=True)
            (base / "oceanbiome").mkdir(parents=True)
            (base / "oceanbiome/Project.toml").write_text("name=\"MASTSWorkshop\"\n")
            (base / "workshop/01_OceanBioME/00_reference_column.jl").write_text("println(1)\n")
        (self.source / "container").mkdir()
        (self.source / "container/warmup_science.jl").write_text("println(2)\n")
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
            "Julia 1.11 language server", "Julia 1.10 editor REPL",
            "Two-day OceanBioME science and figure",
        ])
        self.assertEqual(work[0][1][0], "/opt/julia-ls/bin/julia")
        self.assertEqual(work[1][1][0], "/opt/julia/bin/julia")
        self.assertEqual(work[2][1][0], "/opt/workshop/bin/julia")
        self.assertEqual(work[2][1][-1], str(self.source / "container/warmup_science.jl"))
        self.assertTrue(work[2][2]["MASTS_OUTPUT_DIR"].startswith(str(self.home / ".cache")))

    def test_completes_once_and_preserves_user_files(self):
        original = self.workspace / "workshop/01_OceanBioME/00_reference_column.jl"
        calls = []
        original.write_text("println(42)\n")
        def runner(cmd, **kwargs):
            calls.append((cmd, kwargs))
        self.assertEqual(self.warm(runner), "ready")
        self.assertEqual(self.warm(runner), "ready")
        self.assertEqual(len(calls), 3)
        self.assertIn(str(self.source / "container/warmup_science.jl"), calls[2][0])
        self.assertNotIn(str(original), str(calls))
        self.assertEqual(original.read_text(), "println(42)\n")
        self.assertTrue(ready(self.home / ".cache/masts-workshop", fingerprint(self.source, self.sysimage)))
        status = json.loads((self.home / ".cache/masts-workshop/status.json").read_text())
        self.assertEqual(status["state"], "ready")
        self.assertEqual(len(status["steps"]), 3)
        self.assertEqual(calls[2][1]["env"]["MASTS_OUTPUT_DIR"],
                         str(self.home / ".cache/masts-workshop/reference-output"))
        self.assertEqual(calls[2][1]["cwd"], str(self.source))
        self.assertIn("total_seconds", status)

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

    def test_new_warmup_script_invalidates_marker_but_user_edits_do_not(self):
        self.warm(lambda cmd, **kwargs: None)
        marker = self.home / ".cache/masts-workshop"
        current = fingerprint(self.source, self.sysimage)
        self.workspace.joinpath("workshop/01_OceanBioME/00_reference_column.jl").write_text("modified\n")
        self.assertTrue(ready(marker, current))
        (self.source / "container/warmup_science.jl").write_text("changed workload\n")
        self.assertFalse(ready(marker, fingerprint(self.source, self.sysimage)))

    def test_missing_language_server_environment_fails_before_science(self):
        (self.extension / "scripts/environments/languageserver/v1.11/Project.toml").unlink()
        calls = []
        self.assertEqual(self.warm(lambda cmd, **kwargs: calls.append(cmd)), "failed")
        self.assertEqual(len(calls), 0)
        status = json.loads((self.home / ".cache/masts-workshop/status.json").read_text())
        self.assertIn("language-server environment", status["error"])

    def test_missing_terminal_server_fails_after_language_server(self):
        (self.extension / "scripts/environments/terminalserver/v1.10/Project.toml").unlink()
        calls = []
        self.assertEqual(self.warm(lambda cmd, **kwargs: calls.append(cmd)), "failed")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], "/opt/julia-ls/bin/julia")

    def test_science_workload_is_short_and_headless(self):
        science = Path(__file__).with_name("warmup_science.jl").read_text()
        self.assertIn("stop_time = 2days", science)
        self.assertIn("preview = false", science)
        self.assertIn("plot_vertical_evolution", science)
        self.assertNotIn("365days", science)
        self.assertIn('"container/warmup_science.jl"', Path(__file__).with_name("warmup_workstation.py").read_text())

    def test_seed_adds_new_material_without_overwriting_edits(self):
        script = Path(__file__).with_name("100_seed-workshop.sh").read_text()
        self.assertIn("cp -R --no-clobber --preserve=mode,timestamps", script)
        existing = self.workspace / "workshop/01_OceanBioME/00_reference_column.jl"
        existing.write_text("student changes\n")
        added = self.source / "workshop/01_OceanBioME/new_exercise.jl"
        added.write_text("new exercise\n")
        subprocess.run(["cp", "-R", "--no-clobber", "--preserve=mode,timestamps",
                        str(self.source) + "/.", str(self.workspace)], check=True)
        self.assertEqual(existing.read_text(), "student changes\n")
        self.assertEqual((self.workspace / "workshop/01_OceanBioME/new_exercise.jl").read_text(),
                         "new exercise\n")

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
