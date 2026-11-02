"""Run PackageCompiler and report peak memory for its Docker build step.

On Linux cgroup v2, memory.current includes spawned compiler processes, unlike
/usr/bin/time's per-process maximum RSS. BuildKit may expose a different cgroup
layout; in that case the measurement is explicitly reported as unavailable.
"""

from pathlib import Path
import os
import subprocess
import sys
import time


def read_number(path):
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return None


def measure(command, *, cgroup=Path("/sys/fs/cgroup"), poll_seconds=0.5):
    current = cgroup / "memory.current"
    peak = cgroup / "memory.peak"
    limit = cgroup / "memory.max"
    if not current.is_file():
        # cgroup v1 systems put the memory controller in a separate hierarchy.
        current = cgroup / "memory/memory.usage_in_bytes"
        peak = cgroup / "memory/memory.max_usage_in_bytes"
        limit = cgroup / "memory/memory.limit_in_bytes"

    baseline = read_number(current)
    sampled_peak = baseline
    started = time.monotonic()
    process = subprocess.Popen(command)
    while True:
        sample = read_number(current)
        if sample is not None:
            sampled_peak = max(sampled_peak or 0, sample)
        try:
            process.wait(timeout=poll_seconds)
            break
        except subprocess.TimeoutExpired:
            pass

    sample = read_number(current)
    if sample is not None:
        sampled_peak = max(sampled_peak or 0, sample)
    elapsed = time.monotonic() - started

    def mib(value):
        return "unavailable" if value is None else f"{value / (1024**2):.0f} MiB"

    try:
        limit_text = limit.read_text().strip()
    except OSError:
        limit_text = ""
    limit_display = "unlimited" if limit_text == "max" else mib(read_number(limit))

    print(
        "[sysimage-memory] "
        f"phase={os.environ.get('MASTS_MEMORY_PHASE', 'command')}; "
        f"elapsed={elapsed:.1f} s; "
        f"starting cgroup usage={mib(baseline)}; "
        f"sampled peak={mib(sampled_peak)}; "
        f"cgroup lifetime peak={mib(read_number(peak))}; "
        f"cgroup limit={limit_display}",
        flush=True,
    )
    # Includes child processes and other memory in this build-step cgroup.
    # The lifetime peak can also include earlier commands in the same RUN.
    return 128 - process.returncode if process.returncode < 0 else process.returncode


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--":
        args = args[1:]
    if not args:
        sys.exit("Usage: measure_sysimage_memory.py -- COMMAND [ARG ...]")
    sys.exit(measure(args))
