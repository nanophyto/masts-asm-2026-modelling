# Combined scientific image (Cycle 1.4)

This image extends Google's Code OSS for Cloud Workstations base and includes
Julia 1.10 for science, Julia 1.11.9 for the editor language server, Oceananigans, OceanBioME, CairoMakie, Python 3.11, Abil.py and the
MASTS workshop scripts. Julia uses one thread per column. Dependencies are
installed during image construction, and Julia packages are precompiled.

## Build and test locally

Run from the repository root on an amd64 Docker host:

```bash
docker build --platform linux/amd64 -f container/Dockerfile \
  -t masts-asm-2026-modelling:local .
./scripts/test_container.sh masts-asm-2026-modelling:local
```

The smoke test runs the Python imports and short Julia reference/grazing
experiments in the built image. It verifies PNGs and diagnostic CSVs. It runs the reference example twice. Its
output includes `/usr/bin/time -v` elapsed time and peak resident memory for
the Julia commands; results are written to `outputs/container-smoke/`.
The very first image build downloads and precompiles the complete environments.

For a local check of Code OSS itself, start the Google base entrypoint:

```bash
docker run --privileged --rm -p 127.0.0.1:8080:80 \
  -v masts-workshop-home:/home/user \
  masts-asm-2026-modelling:local
```

Open the workshop directly using this URL:

`http://localhost:8080/?folder=/home/user/masts-asm-2026-modelling`

The `folder` parameter is supported by Google's Code OSS and opens the
editable repository in Explorer immediately. For Cloud Workstations, append
`&folder=/home/user/masts-asm-2026-modelling` to the participant launch URL
(or use `?folder=...` if that URL has no existing query parameters). Give
participants this link so the repository is their initial workspace.

The initial UI has a dark theme, a visible repository Explorer and access to the terminal,
no Welcome page, and a hidden Activity Bar, secondary sidebar, Source Control
and built-in chat/AI UI. Google Cloud Code/Gemini and Data Agent integrations
are removed from the image, including the `googlecloudtools.datacloud`
Data Agent Kit identifier. Older installations in a participant's persistent
editor profile are also cleaned up at startup. The Julia and Python language extensions are installed from pinned local
VSIX files into each participant's persistent editor profile on startup.
They appear in the Installed extensions list. The Extensions icon is hidden,
but can be accessed using `Ctrl+Shift+X`.

During workstation startup, after Code OSS is launched, the installer checks:

```bash
/opt/code-oss/bin/codeoss-cloudworkstations --list-extensions --show-versions
```

It installs `julialang.language-julia@1.250.2` and
`ms-python.python@2026.4.0` from bundled VSIX files when needed.
Both extensions should appear in that listing. Optional extension packs are
skipped so no other extensions need to be downloaded. No internet access is
required during participant startup. If installation fails, the startup log reports it.

The Julia extension's Juliaup recommendation is disabled, since the image
pins Julia 1.10. Symbol-cache downloads are enabled in machine settings to
avoid the extension's permission prompt while retaining its faster symbol
index. These defaults also apply to participants reusing an existing home.

Julia package caches are prepared during image construction. In addition to
precompiling the `/opt/workshop/source` environment, the image now loads
`MASTSWorkshop` at its final editable workspace path
(`/home/user/masts-asm-2026-modelling`). On first startup the source is
copied with original timestamps to help the Julia cache remain valid. Source
edits, different dependency versions or Julia's VS Code extension packages
may still trigger normal one-time compilation. `VSCodeServer` belongs to the
Julia editor extension, installed separately in each persistent home, so
its initial compile can still occur when a participant starts the REPL.

The Julia extension is pinned to `1.250.2` (Open VSX, 21 October 2026).
This replaces `1.219.2`, whose bundled SymbolServer was observed to crash
with `MethodError: Cannot convert an object of type String to ... Symbol`
while indexing CairoMakie, OceanBioME and Oceananigans. The startup
installer updates already-provisioned persistent editor profiles as well as
fresh workstations. After rebuilding and restarting the container, reload
the browser editor and verify that `--list-extensions --show-versions`
reports `julialang.language-julia@1.250.2`. Reopen the Julia project and
check the language-server log while loading the reference column.

The newer extension requires Julia 1.11 or newer **for its language server**.
The image installs a separate Julia 1.11.9 binary at `/opt/julia-ls/bin/julia`
and configures `julia.languageServerExecutablePath` in both the workspace
and machine defaults. `julia.executablePath`, the terminal's `julia`
command, `.julia-version`, and all scientific precompilation remain on Julia
1.10.12. This version pairing is checked in the Docker build and smoke tests.
Existing participant volumes receive the machine default when they restart;
the repository's workspace configuration also includes this setting. The
extra Julia runtime adds image size, but leaves the tested scientific
packages unchanged. Confirm live indexing in the browser before deploying.

If a Julia editor crash notification appears while an experiment finishes, inspect
**View > Output > Julia Language Server** (and the **Julia** output channel)
before changing the image. A language-server failure is separate from a
successfully completed Julia script. For local containers, `docker stats
masts-workshop` can help identify memory pressure. Keep actual crash
notifications visible until the cause is understood.

Machine defaults are seeded into
`/home/user/.codeoss-cloudworkstations/data/Machine/settings.json` before
Code OSS launches, including on an existing home volume. Existing participant
settings take precedence and their files remain intact. Julia/Python paths
remain defined in the repository's `.vscode/settings.json`.

Files copied into the repository are writable and persist on the named Docker
volume. The startup script initialises each new participant workspace once;
it preserves later edits.

## Public image

On `main`, run the **Publish workshop container** GitHub Actions workflow
manually. It builds and smoke-tests the image, then publishes to
`ghcr.io/<owner>/masts-asm-2026-modelling` with `latest` and immutable
commit-based `sha-...` tags. Replace `<owner>` with the repository owner.

GitHub Container Registry creates new packages as private by default.
After the first successful publication, open the package settings in GitHub
and change its visibility to **Public**. Public images can then be pulled
anonymously. Publishing is opt-in and does not require cloud credentials.

For Google Cloud Workstations, copy the *tested* image to Google Artifact
Registry and deploy its digest. This transfer and the cloud IAM configuration
are part of PR 2. Google's recommended Artifact Registry hosting avoids
external-registry compatibility issues for Workstations.

## Runtime layout

- `/opt/workshop/source`: immutable teaching source used for the precompiled
  Julia environment; its `oceanbiome/Manifest.toml` is created during build
  when the repository does not yet provide one.
- `/opt/workshop/julia-depot`: baked Julia packages and compiled caches.
- `/opt/workshop/python`: Python 3.11 conda environment with Abil.py.
- `/home/user/masts-asm-2026-modelling`: editable copy seeded at first
  Workstation startup, after the persistent home is mounted.

The existing Google `/google/scripts/entrypoint.sh`, user creation and Code
OSS startup scripts are retained. The startup script seeds the user workspace
and configures the machine and workspace editor defaults before Code OSS starts.

For reproducibility, commit the resolved `oceanbiome/Manifest.toml` after
successful scientific testing. The Dockerfile uses pinned direct package
versions and reproduces the installation into a fresh image.

## Running a Julia script in the browser editor

Open `oceanbiome/exercises/00_reference_column.jl` in Explorer. With the Julia extension loaded, `Ctrl+Shift+P` offers `Julia: Run File in
New Process` and `Julia: Execute File in REPL`. Julia also contributes a
Run action for `.jl` editors. Python contributes `Python: Run Python File in
Terminal` for `.py` editors. Check both commands after the browser loads.

If a command is absent, inspect the installed extensions with the CLI above
and use `Developer: Show Running Extensions` from `Ctrl+Shift+P`.

For a fast two-day test, use **Terminal > New Terminal** from the repository
root:

```bash
julia --project=oceanbiome oceanbiome/exercises/00_reference_column.jl --quick
```

The script writes figures and diagnostics into `outputs/oceanbiome/`.

## Early workstation preparation and scientific startup timing (Cycle 1.6)

The Julia extension has its own Julia 1.11 language-server and indexing
processes. In the 2 November local browser log, the language-server
precompilation itself took **230 seconds**, followed by symbol-cache downloads.
This occurs in the participant's persistent editor profile, separately from
scientific compilation. Launching Cloud Workstations early lets these processes
finish before the workshop opens.

### Prepare each participant account when its workstation starts

Set `MASTS_WARMUP_ON_START=1` as a container environment variable in the
Cloud Workstations configuration (or via `docker run -e`). Google's existing
container entrypoint executes `210_warmup_workstation.sh` *after* the
extension-installation stage. The script starts preparation as the `user`
account in the background and immediately returns control to Code OSS.
It performs these steps sequentially:

1. Run the image's tested `00_reference_column.jl --quick` with Julia 1.10,
   writing figures and diagnostics into `~/.cache/masts-workshop/reference-output`.
   The participant's editable files are never executed automatically.
2. Precompile the Julia 1.11 language-server environment from the installed
   Julia extension, into the participant's persistent Julia depot.
3. Precompile the Julia 1.10 VS Code terminal-server environment, when present.

It runs once per image/science version. An exclusive file lock prevents
parallel warm-ups, and the completion marker is written only after all steps
succeed. Participant exercises, edits and the normal `outputs/` directory are
preserved. Failed preparation is recorded and retried on the next startup.

For a local Docker rehearsal, with the image built:

```bash
docker run --privileged --rm -p 127.0.0.1:8080:80 \
  -e MASTS_WARMUP_ON_START=1 \
  -v masts-workshop-home:/home/user \
  masts-asm-2026-modelling:local
```

Monitor preparation from the workstation terminal:

```bash
python /opt/workshop/warmup_workstation.py status
tail -f ~/.cache/masts-workshop/warmup.log
```

The status becomes `ready` after the two-day run has produced its output.
Cloud operators should start all participant workstations early and verify
`ready` before sharing launch links. Precompilation of the package index and
symbol downloads may still be performed by the language-server process when
participants first open the workspace. Running the quick example in a
separate process also does not preserve all JIT-compiled methods by itself.

### Optional shared science sysimage

To reduce compilation across separate Julia processes, test an image built
with PackageCompiler 2.2.5. It uses `00_reference_column.jl --quick` as a
precompile workload and builds a portable generic x86-64 sysimage containing
OceanBioME, Oceananigans and CairoMakie. The editable `MASTSWorkshop` package
is loaded from the participant workspace, so students can change workshop
code. The compiler is in a separate build-only environment.

```bash
docker build --platform linux/amd64 --build-arg BUILD_WORKSHOP_SYSIMAGE=1 \
  -f container/Dockerfile -t masts-asm-2026-modelling:sysimage .
./scripts/benchmark_container_startup.sh masts-asm-2026-modelling:sysimage
./scripts/test_container.sh masts-asm-2026-modelling:sysimage
```

`/opt/workshop/bin/julia` automatically selects the sysimage if present. The
VS Code Julia executable setting points to the same wrapper; the language
server continues using `/opt/julia-ls/bin/julia` on Julia 1.11.9. Compare
run time and peak memory with the non-sysimage case using the benchmark. Set
`MASTS_USE_SYSIMAGE=0` to run plain Julia 1.10, including when investigating
an extension or compilation issue. Regular builds default to
`BUILD_WORKSHOP_SYSIMAGE=0` until the optional image is validated on the
actual workstation architecture and shown to improve first-run performance.
PackageCompiler can significantly increase build time, memory use and image
size. Its baked dependency versions follow the pinned scientific environment.

For the 4 November rehearsal, a validated ordinary image with early per-user
warm-up is the minimum viable configuration. Enable the sysimage for the
workshop once both cold and warm runs, diagnostics, and scientific figures pass
and its speed-up is confirmed.
