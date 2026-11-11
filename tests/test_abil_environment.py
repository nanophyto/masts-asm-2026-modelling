"""Static checks for the Abil notebook container build contract."""
import json
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NOTEBOOK_ROOT = ROOT / 'workshop' / '02_Abil'


class AbilNotebookEnvironmentTests(unittest.TestCase):
    def test_notebooks_and_single_conda_environment(self):
        environment = (NOTEBOOK_ROOT / 'environment.yml').read_text()
        for dependency in ('python=3.11', 'ipykernel', 'cartopy',
                           'matplotlib=3.9.4', 'seaborn=0.13.2',
                           'abil==26.5.4.post2'):
            with self.subTest(dependency=dependency):
                self.assertIn(dependency, environment)
        notebooks = sorted(NOTEBOOK_ROOT.rglob('*.ipynb'))
        self.assertGreaterEqual(len(notebooks), 9)
        for notebook in notebooks:
            with self.subTest(notebook=notebook.name):
                parsed = json.loads(notebook.read_text())
                self.assertEqual(parsed['nbformat'], 4)
                self.assertTrue(parsed['cells'])

    def test_abil_owns_scientific_dependencies(self):
        environment = (NOTEBOOK_ROOT / 'environment.yml').read_text()
        conda, pip = environment.split('  - pip:', maxsplit=1)
        for package in ('numpy', 'pandas', 'xarray', 'netcdf4', 'pyyaml',
                        'scikit-learn', 'joblib', 'xgboost'):
            with self.subTest(package=package):
                self.assertNotRegex(
                    conda, rf'(?m)^\s*-\s*{re.escape(package)}(?:[<=>\s]|$)'
                )
                self.assertNotRegex(
                    pip, rf'(?m)^\s*-\s*{re.escape(package)}(?:[<=>\s]|$)'
                )
        self.assertIn('abil==26.5.4.post2', pip)
        smoke = (ROOT / 'container/check_abil_notebooks.py').read_text()
        self.assertIn('assert version("xgboost") == "1.7.6"', smoke)

    def test_container_checks_installed_dependency_consistency(self):
        for path in ('container/Dockerfile.abil', 'scripts/test_abil_container.sh'):
            with self.subTest(path=path):
                contents = (ROOT / path).read_text()
                self.assertIn('check_abil_notebooks.py', contents)
                self.assertNotIn('/opt/workshop/python/bin/python -m pip check', contents)
        checker = (ROOT / 'container/check_abil_notebooks.py').read_text()
        self.assertIn('check_xgboost_native()', checker)
        self.assertIn('check_package_metadata()', checker)

    def test_pip_metadata_warning_is_narrowly_scoped(self):
        import subprocess
        from unittest.mock import patch
        from container.check_abil_notebooks import check_package_metadata
        cases = [
            (0, 'No broken requirements found.', False),
            (1, 'xgboost 1.7.6 is not supported on this platform', False),
            (1, 'some-package requires a missing dependency', True),
            (1, 'xgboost 1.7.6 is not supported on this platform\n'
                'some-package requires a missing dependency', True),
        ]
        for status, output, should_fail in cases:
            with self.subTest(output=output):
                result = subprocess.CompletedProcess([], status, stdout=output, stderr='')
                with patch('container.check_abil_notebooks.subprocess.run', return_value=result):
                    if should_fail:
                        with self.assertRaisesRegex(RuntimeError, 'pip dependency validation failed'):
                            check_package_metadata()
                    else:
                        check_package_metadata()

    def test_abil_only_image_uses_workshop_environment(self):
        dockerfile = (ROOT / 'container/Dockerfile.abil').read_text()
        self.assertIn('COPY workshop/02_Abil/environment.yml', dockerfile)
        self.assertIn('conda env create', dockerfile)
        self.assertIn('JUPYTER_EXTENSION_VERSION=2025.9.1', dockerfile)
        self.assertIn('jupyter.vsix', dockerfile)
        self.assertIn('check_abil_notebooks.py', dockerfile)

    def test_abil_only_image_build_and_startup(self):
        dockerfile = (ROOT / 'container/Dockerfile.abil').read_text()
        for required in ('FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest',
                         'COPY workshop/02_Abil/environment.yml',
                         'conda env create', 'jupyter.vsix',
                         '100_seed_abil.sh', '120_install_abil_extensions.sh',
                         'check_abil_notebooks.py'):
            with self.subTest(required=required):
                self.assertIn(required, dockerfile)
        for disallowed in ('FROM julia:', 'COPY --from=julia',
                           'COPY oceanbiome', 'Pkg.instantiate',
                           'Pkg.precompile', 'build_workshop_sysimage',
                           'warmup_workstation.py'):
            with self.subTest(disallowed=disallowed):
                self.assertNotIn(disallowed, dockerfile)
        publish = (ROOT / '.github/workflows/publish-container.yml').read_text()
        self.assertIn('file: container/Dockerfile.abil', publish)
        self.assertIn('scripts/test_abil_container.sh', publish)

    def test_abil_only_editor_and_extensions(self):
        from container.ensure_language_extensions import ABIL_EXTENSIONS
        self.assertEqual(set(ABIL_EXTENSIONS), {
            'ms-python.python', 'ms-toolsai.jupyter',
            'devyas319.csv-interactive-table-viewer'})
        for name in ('workspace-settings.abil.json', 'machine-settings.abil.json'):
            settings = json.loads((ROOT / 'container' / name).read_text())
            self.assertFalse(any(k.startswith('julia.') for k in settings))
        for name in ('100_seed_abil.sh', '120_install_abil_extensions.sh'):
            startup = (ROOT / 'container' / name).read_text()
            self.assertNotIn('julia', startup.lower())

    def test_abil_only_image_does_not_globally_cap_native_threads(self):
        names = ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS")
        dockerfile = (ROOT / "container/Dockerfile.abil").read_text()
        settings = json.loads((ROOT / "container/workspace-settings.abil.json").read_text())
        for name in names:
            with self.subTest(name=name):
                self.assertNotIn(name, dockerfile)
                self.assertNotIn(name, settings.get("terminal.integrated.env.linux", {}))

    def test_abil_model_configs_use_eight_workers(self):
        configs = sorted(NOTEBOOK_ROOT.rglob('*.yml'))
        configs = [p for p in configs if p.name != 'environment.yml']
        self.assertEqual(len(configs), 3)
        for path in configs:
            with self.subTest(config=path.name):
                matches = re.findall(r'^\s*n_threads\s*:\s*(\d+)\b',
                                     path.read_text(), flags=re.MULTILINE)
                self.assertEqual(matches, ['8'])

    def test_browser_editor_installs_jupyter_extension(self):
        installer = (ROOT / 'container/ensure_language_extensions.py').read_text()
        self.assertIn('"ms-toolsai.jupyter": ("jupyter.vsix", "2025.9.1")', installer)


if __name__ == '__main__':
    unittest.main()
