"""Tests for first-run and persistent Code OSS settings and optional extensions."""

import json
from unittest.mock import call, patch
import subprocess
from zipfile import ZipFile
from pathlib import Path
import tempfile
import unittest

from configure_editor import merge_defaults, remove_google_ai_extensions
from ensure_language_extensions import EXTENSIONS, ensure_extensions, verify_vsix_files


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
        self.assertEqual(configured["workbench.startupEditor"], "none")
        self.assertEqual(configured["workbench.activityBar.location"], "hidden")
        self.assertTrue(configured["chat.disableAIFeatures"])
        self.assertFalse(configured["git.enabled"])
        self.assertFalse(configured["extensions.autoUpdate"])
        self.assertIs(configured["julia.juliaup.install.hint"], False)
        self.assertIs(configured["julia.symbolCacheDownload"], True)

    def test_reuse_preserves_custom_settings_and_is_idempotent(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text('{"workbench.colorTheme":"Solarized Dark","editor.fontSize":18}\n')
        merge_defaults(self.defaults, self.settings)
        configured = json.loads(self.settings.read_text())
        self.assertEqual(configured["workbench.colorTheme"], "Solarized Dark")
        self.assertEqual(configured["editor.fontSize"], 18)
        self.assertTrue(configured["chat.disableAIFeatures"])
        initial_bytes = self.settings.read_bytes()
        merge_defaults(self.defaults, self.settings)
        self.assertEqual(self.settings.read_bytes(), initial_bytes)

    def test_does_not_replace_invalid_persistent_settings(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text('{"editor.fontSize": 18, // a user comment\n}')
        merge_defaults(self.defaults, self.settings)
        self.assertIn("a user comment", self.settings.read_text())

    def test_google_integrations_removed_julia_and_others_retained(self):
        base = self.root / "extensions"
        for folder, publisher, name in [
            ("cloudcode", "GoogleCloudTools", "cloudcode"),
            ("gemini", "Google", "geminicodeassist"),
            ("dataagent", "GoogleCloudTools", "dataagentkit"),
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
        self.assertEqual(len(removed), 5)
        self.assertEqual(sorted(path.name for path in base.iterdir()), ["julia", "workstations"])
        self.assertEqual(remove_google_ai_extensions(base), [])


class LanguageExtensionTests(unittest.TestCase):
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

    def test_pinned_archives_identify_both_languages(self):
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
        listed.side_effect = ["", "julialang.language-julia@1.219.2\nms-python.python@2026.4.0\n"]
        ensure_extensions(Path("/editor/codeoss"), self.vsix_dir)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list, [
            call(["/editor/codeoss", "--install-extension", str(self.vsix_dir / "julia.vsix"), "--force", "--do-not-include-pack-dependencies"], check=True),
            call(["/editor/codeoss", "--install-extension", str(self.vsix_dir / "python.vsix"), "--force", "--do-not-include-pack-dependencies"], check=True),
        ])

    @patch("ensure_language_extensions.subprocess.run")
    @patch("ensure_language_extensions.subprocess.check_output")
    def test_existing_matching_versions_are_idempotent(self, listed, run):
        listed.return_value = "julialang.language-julia@1.219.2\nms-python.python@2026.4.0\n"
        ensure_extensions(Path("/editor/codeoss"), self.vsix_dir)
        run.assert_not_called()

    @patch("ensure_language_extensions.subprocess.run")
    @patch("ensure_language_extensions.subprocess.check_output")
    def test_fails_if_editor_does_not_register_language_extension(self, listed, run):
        listed.side_effect = ["ms-python.python@2026.4.0\n", "ms-python.python@2026.4.0\n"]
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
