"""Install pinned workshop VSIX files into the persistent Code OSS profile.

Google's Code OSS may expose built-in extension packages differently from user
extensions. Installing from local VSIX with its documented CLI makes all
workshop extensions appear as installed and available to the running editor.
"""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile


LANGUAGE_EXTENSIONS = {
    "julialang.language-julia": ("julia.vsix", "1.250.2"),
    "ms-python.python": ("python.vsix", "2026.4.0"),
    "ms-toolsai.jupyter": ("jupyter.vsix", "2025.9.1"),
}
EXTENSIONS = {**LANGUAGE_EXTENSIONS,
              "devyas319.csv-interactive-table-viewer": ("csv.vsix", "0.1.5")}
ABIL_EXTENSIONS = {key: value for key, value in EXTENSIONS.items()
                   if key != "julialang.language-julia"}


def verify_vsix_files(vsix_dir: Path, packages=EXTENSIONS) -> None:
    """Ensure pinned archives are complete and contain the expected extensions."""
    for extension_id, (filename, version) in packages.items():
        path = vsix_dir / filename
        with ZipFile(path) as archive:
            manifest = json.loads(archive.read("extension/package.json"))
            if archive.testzip() is not None:
                raise ValueError(f"Corrupt extension archive: {path}")
        actual_id = f"{manifest['publisher']}.{manifest['name']}".lower()
        if (actual_id, manifest["version"]) != (extension_id, version):
            raise ValueError(f"Unexpected VSIX {path}: {actual_id}@{manifest['version']}")
        print(f"Validated {extension_id}@{version}")


def _installed_versions(cli: Path) -> set[str]:
    output = subprocess.check_output(
        [str(cli), "--list-extensions", "--show-versions"], text=True
    )
    return {line.strip().lower() for line in output.splitlines()}


def ensure_extensions(cli: Path, vsix_dir: Path, packages=EXTENSIONS) -> None:
    """Install missing/mismatched versions once per persistent workstation home."""
    versions = _installed_versions(cli)
    for extension_id, (filename, version) in packages.items():
        desired = f"{extension_id}@{version}".lower()
        if desired not in versions:
            vsix = vsix_dir / filename
            print(f"Installing {desired} from {vsix}", flush=True)
            subprocess.run(
                [str(cli), "--install-extension", str(vsix), "--force",
                 "--do-not-include-pack-dependencies"],
                check=True,
            )
        else:
            print(f"Already installed: {desired}")
    versions = _installed_versions(cli)
    missing = [f"{eid}@{ver}" for eid, (_, ver) in packages.items()
               if f"{eid}@{ver}".lower() not in versions]
    if missing:
        raise RuntimeError(f"Code OSS did not register: {', '.join(missing)}")
    print("Workshop Code OSS extensions are installed.")


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "verify":
        verify_vsix_files(Path(sys.argv[2]))
    elif len(sys.argv) == 3 and sys.argv[1] == "verify-language":
        verify_vsix_files(Path(sys.argv[2]), LANGUAGE_EXTENSIONS)
    elif len(sys.argv) == 3 and sys.argv[1] == "verify-abil":
        verify_vsix_files(Path(sys.argv[2]), ABIL_EXTENSIONS)
    elif len(sys.argv) == 4 and sys.argv[1] in ("ensure", "ensure-abil"):
        packages = ABIL_EXTENSIONS if sys.argv[1] == "ensure-abil" else EXTENSIONS
        ensure_extensions(Path(sys.argv[2]), Path(sys.argv[3]), packages)
    else:
        sys.exit("Usage: ensure_language_extensions.py verify|verify-language|verify-abil VSIX_DIR | "
                 "ensure|ensure-abil CODE_OSS_CLI VSIX_DIR")


if __name__ == "__main__":
    main()
