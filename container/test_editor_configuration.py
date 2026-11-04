"""Tests for first-run and persistent Code OSS settings and optional extensions."""

import json
from unittest.mock import call, patch
import subprocess
from zipfile import ZipFile
from pathlib import Path
import tempfile
import unittest

from configure_editor import merge_defaults, migrate_workshop_julia_executable, remove_google_ai_extensions
from ensure_language_extensions import EXTENSIONS, LANGUAGE_EXTENSIONS, ensure_extensions, verify_vsix_files


class EditorConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.defaults = Path(__file__).with_name("machine-settings.json")
        self.settings = self.root / "home/.codeoss-cloudworkstations/data/Machine/settings.json"

    def test_first_start_creates_machine_settings(self):
        merge_defaults(self.defaults, self.settings)
        configured = json.loads(self.settings.read_text())
        self.assertEqual(configured["workbench.colorTheme"], "Default Dark Modern")
        self.assertEqual(configured["workbench.startupEditor"], "readme")
        self.assertEqual(configured["workbench.activityBar.location"], "hidden")
        self.assertTrue(configured["chat.disableAIFeatures"])
        self.assertFalse(configured["git.enabled"])
        self.assertFalse(configured["extensions.autoUpdate"])
        self.assertIs(configured["julia.juliaup.install.hint"], False)
        self.assertIs(configured["julia.symbolCacheDownload"], True)
        self.assertEqual(configured["julia.languageServerExecutablePath"], "/opt/julia-ls/bin/julia")
        self.assertTrue(configured["julia.usePlotPane"])

    def test_participant_workspace_uses_julia_plot_pane(self):
        settings = json.loads((Path(__file__).with_name("workspace-settings.json")).read_text())
        self.assertTrue(settings["julia.usePlotPane"])

    def test_workshop_source_edits_reuse_scientific_build_layers(self):
        dockerfile = Path(__file__).with_name("Dockerfile").read_text()
        dependency_copy = dockerfile.index("COPY oceanbiome/*.toml")
        sysimage_build = dockerfile.index("MASTS_MEMORY_PHASE=create-sysimage")
        source_copy = dockerfile.index("COPY . /opt/workshop/source")
        self.assertLess(dependency_copy, sysimage_build)
        self.assertLess(sysimage_build, source_copy)
        workload = Path(__file__).with_name("precompile_reference.jl").read_text()
        self.assertNotIn('include(', workload)
        self.assertNotIn('using MASTSWorkshop', workload)

    def test_extension_stub_and_source_only_layers(self):
        dockerfile = Path(__file__).with_name("Dockerfile").read_text()
        pip_install = dockerfile.index("pip install --no-cache-dir")
        extension_stub = dockerfile.index("mkdir -p /opt/workshop/source/oceanbiome/ext")
        instantiate = dockerfile.index("-e 'using Pkg; Pkg.instantiate()'")
        precompile = dockerfile.index("-e 'using Pkg; Pkg.precompile()'")
        source_copy = dockerfile.index("COPY . /opt/workshop/source")
        self.assertLess(pip_install, extension_stub)
        self.assertLess(extension_stub, instantiate)
        self.assertLess(instantiate, precompile)
        self.assertLess(precompile, source_copy)
        self.assertIn("module MASTSWorkshopMakieExt", dockerfile)
        self.assertTrue((Path(__file__).parent.parent / "oceanbiome/ext/MASTSWorkshopMakieExt.jl").is_file())

    def test_sysimage_workload_reuses_dependency_and_compiler_layers(self):
        dockerfile = Path(__file__).with_name("Dockerfile").read_text()
        self.assertLess(dockerfile.index("pip install --no-cache-dir"),
                        dockerfile.index("-e 'using Pkg; Pkg.precompile()'"))
        self.assertLess(dockerfile.index("-e 'using Pkg; Pkg.precompile()'"),
                        dockerfile.index('Pkg.add(Pkg.PackageSpec(name="PackageCompiler"'))
        self.assertLess(dockerfile.index("COPY container/measure_sysimage_memory.py"),
                        dockerfile.index('Pkg.add(Pkg.PackageSpec(name="PackageCompiler"'))
        self.assertLess(dockerfile.index('Pkg.add(Pkg.PackageSpec(name="PackageCompiler"'),
                        dockerfile.index("COPY container/build_workshop_sysimage.jl"))
        self.assertLess(dockerfile.index("COPY container/build_workshop_sysimage.jl"),
                        dockerfile.index("container/precompile_reference.jl;"))
        self.assertLess(dockerfile.index("container/precompile_reference.jl;"),
                        dockerfile.index("MASTS_MEMORY_PHASE=create-sysimage"))
        self.assertLess(dockerfile.index("MASTS_MEMORY_PHASE=create-sysimage"),
                        dockerfile.index("COPY . /opt/workshop/source"))

    def test_workshop_forcing_matches_oceananigans_callback_shapes(self):
        physics = (Path(__file__).parent.parent / "oceanbiome/src/idealised_physics.jl").read_text()
        for signature in ("surface_PAR(t) =", "surface_PAR(x, y, t) = surface_PAR(t)",
                          "vertical_diffusivity(z, t) =",
                          "vertical_diffusivity(x, y, z, t) = vertical_diffusivity(z, t)"):
            self.assertIn(signature, physics)

    def test_source_refresh_inherits_sysimage_without_compilation(self):
        folder = Path(__file__).parent
        dockerfile = (folder / "Dockerfile.refresh").read_text()
        self.assertIn("FROM ${BASE_IMAGE}", dockerfile)
        self.assertIn("cmp /tmp/refresh-env/Project.toml", dockerfile)
        self.assertIn("COPY . /opt/workshop/source", dockerfile)
        self.assertNotIn("create_sysimage(", dockerfile)
        self.assertIn("ENV MASTS_WARMUP_ON_START=1", dockerfile)
        self.assertIn("ENV MASTS_WARMUP_ON_START=1", (folder / "Dockerfile").read_text())

    def test_participant_start_page_is_in_the_docker_context(self):
        root = Path(__file__).resolve().parent.parent
        self.assertTrue((root / "workshop/README.md").is_file())
        self.assertTrue((root / "workshop/START_HERE.md").is_file())
        self.assertTrue((root / "workshop/01_OceanBioME/00_reference_column.jl").is_file())

    def test_reuse_preserves_custom_settings_and_is_idempotent(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text('{"workbench.colorTheme":"Solarized Dark","editor.fontSize":18}\n')
        merge_defaults(self.defaults, self.settings)
        configured = json.loads(self.settings.read_text())
        self.assertEqual(configured["workbench.colorTheme"], "Solarized Dark")
        self.assertEqual(configured["editor.fontSize"], 18)
        self.assertTrue(configured["chat.disableAIFeatures"])
        self.assertEqual(configured["julia.languageServerExecutablePath"], "/opt/julia-ls/bin/julia")
        self.assertTrue(configured["julia.usePlotPane"])
        initial_bytes = self.settings.read_bytes()
        merge_defaults(self.defaults, self.settings)
        self.assertEqual(self.settings.read_bytes(), initial_bytes)

    def test_migrates_activity_bar_from_previous_workshop_default(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text('{"workbench.activityBar.location":"default","editor.fontSize":18}\n')
        merge_defaults(self.defaults, self.settings)
        configured = json.loads(self.settings.read_text())
        self.assertEqual(configured["workbench.activityBar.location"], "hidden")
        self.assertEqual(configured["editor.fontSize"], 18)
        original = self.settings.read_bytes()
        merge_defaults(self.defaults, self.settings)
        self.assertEqual(self.settings.read_bytes(), original)

    def test_keeps_participant_activity_bar_choice(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text('{"workbench.activityBar.location":"top"}\n')
        merge_defaults(self.defaults, self.settings)
        self.assertEqual(json.loads(self.settings.read_text())["workbench.activityBar.location"], "top")

    def test_does_not_replace_invalid_persistent_settings(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text('{"editor.fontSize": 18, // a user comment\n}')
        merge_defaults(self.defaults, self.settings)
        self.assertIn("a user comment", self.settings.read_text())

    def test_migrates_old_science_executable_without_erasing_user_settings(self):
        workspace = self.root / "workspace/.vscode/settings.json"
        workspace.parent.mkdir(parents=True)
        workspace.write_text('{\n  // participant preference\n  "editor.fontSize": 18,\n'
                             '  "julia.executablePath": "/opt/julia/bin/julia"\n}\n')
        migrate_workshop_julia_executable(workspace)
        result = workspace.read_text()
        self.assertIn('"julia.executablePath": "/opt/workshop/bin/julia"', result)
        self.assertIn('// participant preference', result)
        self.assertIn('"editor.fontSize": 18', result)
        migrate_workshop_julia_executable(workspace)
        self.assertEqual(workspace.read_text(), result)

    def test_respects_custom_science_executable(self):
        workspace = self.root / "workspace/.vscode/settings.json"
        workspace.parent.mkdir(parents=True)
        workspace.write_text('{"julia.executablePath":"/custom/julia"}\n')
        migrate_workshop_julia_executable(workspace)
        self.assertIn('/custom/julia', workspace.read_text())

    def test_google_integrations_removed_julia_and_others_retained(self):
        base = self.root / "extensions"
        for folder, publisher, name in [
            ("cloudcode", "GoogleCloudTools", "cloudcode"),
            ("gemini", "Google", "geminicodeassist"),
            ("dataagent", "GoogleCloudTools", "dataagentkit"),
            ("antigravity", "Google", "google-antigravity"),
            ("datacloud", "googlecloudtools", "datacloud"),
            ("hyphenated", "GoogleCloudTools", "data-agent-kit"),
            ("julia", "julialang", "language-julia"),
            ("workstations", "GoogleCloudTools", "cloud-workstations"),
        ]:
            path = base / folder
            path.mkdir(parents=True)
            (path / "package.json").write_text(json.dumps({
                "publisher": publisher, "name": name,
            }))
        removed = remove_google_ai_extensions(base)
        self.assertEqual(len(removed), 6)
        self.assertEqual(sorted(path.name for path in base.iterdir()), ["julia", "workstations"])
        self.assertEqual(remove_google_ai_extensions(base), [])


class WorkshopExtensionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.vsix_dir = Path(self.tmp.name)
        for extension_id, (filename, version) in EXTENSIONS.items():
            publisher, name = extension_id.split(".", 1)
            with ZipFile(self.vsix_dir / filename, "w") as archive:
                archive.writestr("extension/package.json", json.dumps({
                    "publisher": publisher, "name": name, "version": version,
                }))

    def test_docker_version_pins_match_installer(self):
        dockerfile = Path(__file__).with_name("Dockerfile").read_text()
        self.assertIn(
            f"ARG JULIA_EXTENSION_VERSION={EXTENSIONS['julialang.language-julia'][1]}",
            dockerfile,
        )
        self.assertIn(
            f"ARG PYTHON_EXTENSION_VERSION={EXTENSIONS['ms-python.python'][1]}",
            dockerfile,
        )

    def test_csv_extension_is_pinned_and_cached_in_source_refresh(self):
        folder = Path(__file__).parent
        extension = "devyas319.csv-interactive-table-viewer"
        self.assertEqual(EXTENSIONS[extension], ("csv.vsix", "0.1.5"))
        for name in ("Dockerfile", "Dockerfile.refresh"):
            dockerfile = (folder / name).read_text()
            self.assertIn("ARG CSV_EXTENSION_VERSION=0.1.5", dockerfile)
            self.assertIn("/api/devyas319/csv-interactive-table-viewer/${CSV_EXTENSION_VERSION}/file/", dockerfile)
            self.assertIn("/opt/workshop/vsix/csv.vsix", dockerfile)
            source = dockerfile.index("COPY . /opt/workshop/source")
            extension = dockerfile.index("ARG CSV_EXTENSION_VERSION=0.1.5")
            if name == "Dockerfile.refresh":
                self.assertLess(extension, source)  # Cached across source-only edits.
            else:
                self.assertLess(source, extension)  # Built after the scientific sysimage.
        self.assertLess((folder / "Dockerfile").read_text().index("MASTS_MEMORY_PHASE=create-sysimage"),
                        (folder / "Dockerfile").read_text().index("ARG CSV_EXTENSION_VERSION=0.1.5"))
        self.assertIn("verify-language", (folder / "Dockerfile").read_text())
        self.assertIn("COPY container/ensure_language_extensions.py /opt/workshop/ensure_language_extensions.py",
                      (folder / "Dockerfile.refresh").read_text())

    def test_language_server_runtime_is_independent_of_science_julia(self):
        dockerfile = Path(__file__).with_name("Dockerfile").read_text()
        machine = json.loads(Path(__file__).with_name("machine-settings.json").read_text())
        workspace = json.loads(Path(__file__).with_name("workspace-settings.json").read_text())
        self.assertIn("FROM julia:1.10.12-bookworm AS julia-runtime", dockerfile)
        self.assertIn("FROM julia:1.11.9-bookworm AS julia-language-server", dockerfile)
        self.assertIn("COPY --from=julia-language-server /usr/local/julia /opt/julia-ls", dockerfile)
        self.assertIn("PATH=/opt/workshop/python/bin:/opt/workshop/bin:/opt/julia/bin:${PATH}", dockerfile)
        self.assertEqual(workspace["julia.executablePath"], "/opt/workshop/bin/julia")
        self.assertEqual(workspace["julia.languageServerExecutablePath"], "/opt/julia-ls/bin/julia")
        self.assertEqual(machine["julia.languageServerExecutablePath"], "/opt/julia-ls/bin/julia")

    def test_pinned_archives_identify_workshop_extensions(self):
        verify_vsix_files(self.vsix_dir)
        with ZipFile(self.vsix_dir / "python.vsix", "w") as archive:
            archive.writestr("extension/package.json", json.dumps({
                "publisher": "other", "name": "python", "version": "2026.4.0",
            }))
        with self.assertRaisesRegex(ValueError, "Unexpected VSIX"):
            verify_vsix_files(self.vsix_dir)

    @patch("ensure_language_extensions.subprocess.run")
    @patch("ensure_language_extensions.subprocess.check_output")
    def test_installs_missing_extensions_and_checks_registration(self, listed, run):
        listed.side_effect = ["", "julialang.language-julia@1.250.2\nms-python.python@2026.4.0\ndevyas319.csv-interactive-table-viewer@0.1.5\n"]
        ensure_extensions(Path("/editor/codeoss"), self.vsix_dir)
        self.assertEqual(run.call_count, 3)
        self.assertEqual(run.call_args_list, [
            call(["/editor/codeoss", "--install-extension", str(self.vsix_dir / "julia.vsix"), "--force", "--do-not-include-pack-dependencies"], check=True),
            call(["/editor/codeoss", "--install-extension", str(self.vsix_dir / "python.vsix"), "--force", "--do-not-include-pack-dependencies"], check=True),
            call(["/editor/codeoss", "--install-extension", str(self.vsix_dir / "csv.vsix"), "--force", "--do-not-include-pack-dependencies"], check=True),
        ])

    @patch("ensure_language_extensions.subprocess.run")
    @patch("ensure_language_extensions.subprocess.check_output")
    def test_existing_matching_versions_are_idempotent(self, listed, run):
        listed.return_value = "julialang.language-julia@1.250.2\nms-python.python@2026.4.0\ndevyas319.csv-interactive-table-viewer@0.1.5\n"
        ensure_extensions(Path("/editor/codeoss"), self.vsix_dir)
        run.assert_not_called()

    @patch("ensure_language_extensions.subprocess.run")
    @patch("ensure_language_extensions.subprocess.check_output")
    def test_fails_if_editor_does_not_register_language_extension(self, listed, run):
        listed.side_effect = ["ms-python.python@2026.4.0\ndevyas319.csv-interactive-table-viewer@0.1.5\n", "ms-python.python@2026.4.0\ndevyas319.csv-interactive-table-viewer@0.1.5\n"]
        with self.assertRaisesRegex(RuntimeError, "julialang.language-julia"):
            ensure_extensions(Path("/editor/codeoss"), self.vsix_dir)
        self.assertEqual(run.call_count, 1)

    @patch("ensure_language_extensions.subprocess.run", side_effect=subprocess.CalledProcessError(1, ["codeoss"]))
    @patch("ensure_language_extensions.subprocess.check_output", return_value="")
    def test_install_failure_is_reported(self, listed, run):
        with self.assertRaises(subprocess.CalledProcessError):
            ensure_extensions(Path("/editor/codeoss"), self.vsix_dir)



if __name__ == "__main__":
    unittest.main()
