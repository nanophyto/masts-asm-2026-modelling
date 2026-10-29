"""Minimal environment check against Abil's published package."""

import importlib
import sys
import unittest
from importlib.metadata import version


class InstallationTests(unittest.TestCase):
    def test_python_version(self):
        self.assertEqual(sys.version_info[:2], (3, 11))

    def test_abil_and_scientific_dependencies_import(self):
        self.assertEqual(version("abil"), "26.5.4.post2")
        for name in ("abil", "numpy", "pandas", "sklearn", "xarray", "xgboost", "netCDF4"):
            with self.subTest(package=name):
                importlib.import_module(name)


if __name__ == "__main__":
    unittest.main()
