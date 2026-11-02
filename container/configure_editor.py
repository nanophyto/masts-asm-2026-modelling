"""Small build/startup helpers for the browser Code OSS workshop environment."""

import json
import os
from pathlib import Path
import shutil
import sys
import tempfile


def merge_defaults(defaults_path: Path, settings_path: Path) -> None:
    """Apply first-run machine defaults, retaining settings already chosen by a user."""
    defaults = json.loads(defaults_path.read_text(encoding="utf-8"))
    if settings_path.exists():
        try:
            existing = json.loads(settings_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            # VS Code can also use JSON with comments. Respect user-edited files,
            # and keep the workstation starting even when those cannot be merged.
            print(f"Keeping existing editor settings at {settings_path} (JSON with comments)",
                  file=sys.stderr)
            return
    else:
        existing = {}
    if not isinstance(defaults, dict) or not isinstance(existing, dict):
        raise ValueError("Code OSS settings must be JSON objects")

    result = {**defaults, **existing}
    if result == existing:
        return

    settings_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_path = tempfile.mkstemp(prefix=".settings-", dir=settings_path.parent)
    try:
        if settings_path.exists():
            os.fchmod(fd, settings_path.stat().st_mode & 0o777)
        else:
            os.fchmod(fd, 0o644)
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(result, output, indent=2)
            output.write("\n")
        os.replace(temp_path, settings_path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def remove_google_ai_extensions(extensions_dir: Path) -> list[str]:
    """Remove bundled Google Cloud Code/Gemini integrations, preserving other extensions."""
    removed = []
    if not extensions_dir.exists():
        return removed

    for extension in extensions_dir.iterdir():
        manifest = extension / "package.json"
        if not manifest.is_file():
            continue
        info = json.loads(manifest.read_text(encoding="utf-8"))
        publisher = str(info.get("publisher", "")).casefold()
        # Data Agent Kit is published as googlecloudtools.datacloud; earlier
        # Google builds also use dataagent* identifiers.
        name = str(info.get("name", "")).casefold().replace("-", "").replace("_", "")
        if publisher.startswith("google") and any(
            component in name for component in ("cloudcode", "gemini", "dataagent", "datacloud")
        ):
            if extension.is_symlink():
                extension.unlink()
            else:
                shutil.rmtree(extension)
            removed.append(f"{info['publisher']}.{info['name']}")
    return removed


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "merge-defaults":
        merge_defaults(Path(sys.argv[2]), Path(sys.argv[3]))
    elif len(sys.argv) == 3 and sys.argv[1] == "remove-google-ai":
        removed = remove_google_ai_extensions(Path(sys.argv[2]))
        print("Removed optional Google editor extensions: " +
              (", ".join(removed) if removed else "none found"))
    else:
        sys.exit("Usage: configure_editor.py merge-defaults DEFAULTS SETTINGS | "
                 "remove-google-ai EXTENSIONS_DIR")
