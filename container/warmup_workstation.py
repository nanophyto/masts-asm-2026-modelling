"""One-time, non-blocking preparation for a participant's persistent home.

Run by Cloud Workstations' 210 startup script after the pinned editor
extensions are installed. No package environment or exercise is modified.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HOME = Path(os.environ.get("HOME", "/home/user"))
WORKSPACE = HOME / "masts-asm-2026-modelling"
CACHE = HOME / ".cache" / "masts-workshop"
SOURCE = Path("/opt/workshop/source")
JULIA = Path("/opt/workshop/bin/julia")
EDITOR_JULIA = Path("/opt/julia-ls/bin/julia")
EXTENSION = HOME / ".codeoss-cloudworkstations/extensions/julialang.language-julia-1.250.2"
SYSIMAGE = Path("/opt/workshop/sysimages/masts-workshop.so")
TIMEOUT_SECONDS = 900


def fingerprint(source: Path = SOURCE, sysimage: Path = SYSIMAGE) -> str:
    """Invalidate a completed warm-up after an image/science update."""
    digest = hashlib.sha256(b"masts-warmup-v2;Julia1.10.12;LS1.11.9;extension1.250.2")
    for relative in (
        "oceanbiome/Project.toml",
        "oceanbiome/Manifest.toml",
        "container/warmup_science.jl",
        "oceanbiome/src/MASTSWorkshop.jl",
        "oceanbiome/src/column_configuration.jl",
        "oceanbiome/src/column_diagnostics.jl",
        "oceanbiome/src/idealised_physics.jl",
        "oceanbiome/ext/MASTSWorkshopMakieExt.jl",
    ):
        path = source / relative
        digest.update(relative.encode())
        digest.update(path.read_bytes() if path.is_file() else b"missing")
    if sysimage.is_file():
        stat = sysimage.stat()
        digest.update(f"sysimage:{stat.st_size}:{stat.st_mtime_ns}".encode())
    return digest.hexdigest()


def write_json(path: Path, data: dict) -> None:
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    temp.replace(path)


def ready(cache: Path, expected: str) -> bool:
    try:
        return json.loads((cache / "complete.json").read_text())["fingerprint"] == expected
    except (FileNotFoundError, KeyError, ValueError, TypeError):
        return False


def stages(home: Path = HOME, workspace: Path = WORKSPACE,
           extension: Path = EXTENSION, source: Path = SOURCE):
    """Prepare editor caches first, then check the two-day scientific path."""
    ls_env = extension / "scripts/environments/languageserver/v1.11"
    if not (ls_env / "Project.toml").is_file():
        raise FileNotFoundError(f"Julia language-server environment is missing: {ls_env}")
    yield "Julia 1.11 language server", [
        str(EDITOR_JULIA), "--startup-file=no", f"--project={ls_env}",
        "-e", "using LanguageServer",
    ], {}

    repl_env = extension / "scripts/environments/terminalserver/v1.10"
    if not (repl_env / "Project.toml").is_file():
        raise FileNotFoundError(f"Julia terminal-server environment is missing: {repl_env}")
    yield "Julia 1.10 editor REPL", [
        "/opt/julia/bin/julia", "--startup-file=no", f"--project={repl_env}",
        "-e", "using VSCodeServer",
    ], {}

    example = source / "container/warmup_science.jl"
    if not example.is_file():
        raise FileNotFoundError(f"Science warm-up is missing: {example}")
    yield "Two-day OceanBioME science and figure", [
        str(JULIA), "--threads=1", "--startup-file=no",
        f"--project={source / 'oceanbiome'}", str(example),
    ], {"MASTS_OUTPUT_DIR": str(home / ".cache/masts-workshop/reference-output")}


def run_warmup(home: Path = HOME, workspace: Path = WORKSPACE,
               source: Path = SOURCE, extension: Path = EXTENSION,
               sysimage: Path = SYSIMAGE, runner=subprocess.run) -> str:
    """Work sequentially under a per-user lock; mark only full success."""
    cache = home / ".cache/masts-workshop"
    cache.mkdir(parents=True, exist_ok=True)
    expected = fingerprint(source, sysimage)
    with (cache / "warmup.lock").open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if ready(cache, expected):
            return "ready"
        status = {"state": "running", "fingerprint": expected, "started": time.time(), "steps": []}
        write_json(cache / "status.json", status)
        try:
            for label, command, extra_env in stages(home, workspace, extension, source):
                status["current_step"] = label
                write_json(cache / "status.json", status)
                print(f"[warm-up] {label}", flush=True)
                started = time.monotonic()
                runner(command, check=True, cwd=str(source),
                       env={**os.environ, **extra_env}, timeout=TIMEOUT_SECONDS)
                status["steps"].append({"name": label, "seconds": round(time.monotonic() - started, 2)})
                write_json(cache / "status.json", status)
            status.pop("current_step", None)
            status.update(state="ready", finished=time.time(),
                          total_seconds=round(time.time() - status["started"], 2))
            write_json(cache / "complete.json", {"fingerprint": expected, "finished": status["finished"]})
            write_json(cache / "status.json", status)
            return "ready"
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            status.update(state="failed", failed=time.time(), error=str(error))
            write_json(cache / "status.json", status)
            print(f"[warm-up] Failed: {error}", file=sys.stderr, flush=True)
            return "failed"


def launch() -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    if ready(CACHE, fingerprint()):
        print("MASTS warm-up already completed for this image")
        return
    # The child writes to the persistent volume, survives the startup script,
    # and never blocks the editor service. A file lock handles repeat launches.
    with (CACHE / "warmup.log").open("a") as output:
        child = subprocess.Popen([sys.executable, __file__, "run"],
                                 stdin=subprocess.DEVNULL, stdout=output,
                                 stderr=subprocess.STDOUT, start_new_session=True,
                                 cwd=str(HOME), env=os.environ.copy())
    print(f"MASTS warm-up launched: pid={child.pid}; log={CACHE / 'warmup.log'}")


def status() -> None:
    path = CACHE / "status.json"
    if not path.exists():
        print("not started")
        return
    state = json.loads(path.read_text())
    if state.get("state") == "ready" and not ready(CACHE, fingerprint()):
        print("outdated (new image or scientific environment)")
    else:
        print(json.dumps(state, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("launch", "run", "status"):
        raise SystemExit("usage: warmup_workstation.py {launch|run|status}")
    if sys.argv[1] == "launch":
        launch()
    elif sys.argv[1] == "status":
        status()
    else:
        raise SystemExit(0 if run_warmup() == "ready" else 1)
