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

The smoke test runs Python checks and the annual Julia reference, grazing,
sinking, remineralisation, light affinity, nutrient affinity and mortality experiments in the built image. It verifies
PNGs and diagnostic CSVs. Its
output includes `/usr/bin/time -v` elapsed time and peak resident memory for
the Julia commands; results are written to `outputs/container-smoke/`.
The first image build downloads and precompiles the complete environments.
Subsequent changes to `workshop/` exercises, `oceanbiome/src/` helpers,
`oceanbiome/ext/` plots or documentation reuse the Julia dependency and
PackageCompiler layers. Only source copying and the lightweight workshop-package
cache run again. The initial dependency layer uses a minimal
`MASTSWorkshopMakieExt` entry point because the Julia project declares that
extension; the real plotting implementation is copied with editable sources
later in the build. Julia package downloads and precompilation also have
separate cache layers. The optional PackageCompiler installation has its own
cache layer. Changes to `container/precompile_reference.jl` reuse the Python,
Julia package and PackageCompiler layers. The PackageCompiler workload imports
only the pinned scientific libraries; the workshop tests exercise the actual
column physics, output writers and figures. This avoids duplicating callback
signatures in the sysimage build. Changes to `oceanbiome/Project.toml`
or `Manifest.toml` refresh the corresponding dependency layers.

The default `BUILD_WORKSHOP_SYSIMAGE=1` route includes a scientific sysimage.
If PackageCompiler encounters a separate build problem, use the same build
arguments and add `--build-arg COMPILE_WORKSHOP_SYSIMAGE=0`. This switch is
introduced **after** the Python/Julia dependency and PackageCompiler layers,
so the fallback rebuild reuses their caches and runs Julia with its regular
precompiled dependencies through `/opt/workshop/bin/julia`. The regular smoke
test is the acceptance test for either build mode.

Build successfully before testing an image tag. If a build fails, Docker keeps
that tag pointing to the previous successful image; the smoke test checks that
the expected workshop exercises exist and reports stale images early.

### Fast source updates from the tested sysimage

For workshop scripts, plotting helpers, documentation and startup changes, use
`Dockerfile.refresh`. It inherits a **previously built and tested image** and
never invokes PackageCompiler. The image keeps the compiled sysimage and pinned
third-party dependencies. It verifies that Julia and Python dependency files
match the base image before copying the updated source.

```bash
sudo docker build --platform linux/amd64 --progress=plain \
  --build-arg BASE_IMAGE=masts-asm-2026-modelling:pr2 \
  -f container/Dockerfile.refresh \
  -t masts-asm-2026-modelling:pr3 .
sudo ./scripts/test_sysimage.sh masts-asm-2026-modelling:pr3
```

Use the exact tag of your tested sysimage image as `BASE_IMAGE`. For changes to
`oceanbiome/Project.toml`, `Manifest.toml` or `abil/requirements.txt`, build
and test a new dependency/sysimage base using `container/Dockerfile`. A source
refresh preserves the Google Code OSS entrypoint, both Julia runtimes, the
sysimage and installed editor VSIX archives from its base.


Cloud Workstations uses an immutable container digest: publish a new image and
update the deployment's `IMAGE=` reference after editing source. Layer reuse
also avoids uploading unchanged dependency/sysimage layers to Artifact Registry.

For a local check of Code OSS itself, start the Google base entrypoint:

```bash
docker run --privileged --rm -p 127.0.0.1:8080:80 \
  -v masts-workshop-home:/home/user \
  masts-asm-2026-modelling:local
```

Open the workshop directly using this URL:

`http://localhost:8080/?folder=/home/user/masts-asm-2026-modelling/workshop`

On startup, existing home volumes gain newly added exercise scripts, and the
instructor-maintained `MASTSWorkshop.jl` and Makie extension are refreshed from
the image. Existing exercise edits and generated results are preserved.

The `folder` parameter is supported by Google's Code OSS and opens the
participant-only `workshop/` directory. The developer folders remain available
inside the repository, and the examples import the package by its installed
absolute project path. For Cloud Workstations, append
`&folder=/home/user/masts-asm-2026-modelling/workshop` to the participant launch URL
(or use `?folder=...` if that URL has no existing query parameters). Give
participants this link so the exercises are their initial workspace.
A new session opens `workshop/README.md` as its starting page.

The initial UI uses a dark theme, the participant workspace and the terminal,
a workshop README instead of the Welcome page, and a hidden Activity Bar.
The Explorer panel remains accessible with `Ctrl+Shift+E`, Search with
`Ctrl+Shift+F`, and Extensions with `Ctrl+Shift+X`.
The secondary sidebar, Source Control and built-in chat/AI UI remain hidden. If Explorer was hidden in a previous
session, use `Ctrl+B` then `Ctrl+Shift+E` to restore it.
Google Cloud Code/Gemini and Data Agent integrations
are removed from the image, including the `googlecloudtools.datacloud`
Data Agent Kit identifier. Older installations in a participant's persistent
editor profile are also cleaned up at startup. The Julia and Python language extensions are installed from pinned local
VSIX files into each participant's persistent editor profile on startup.
They appear in the Installed extensions list. The Extensions view remains available through `Ctrl+Shift+X`.
The workshop defaults hide the entire Activity Bar, and migrate the `default`
position saved by earlier workshop images when a persistent home is restarted.
An intentionally selected `top` or `bottom` position is retained. The workshop removes
Google Antigravity (`Google.google-antigravity`) alongside other Google AI
extensions from both the base image and persistent extension folders.

During workstation startup, after Code OSS is launched, the installer checks:

```bash
/opt/code-oss/bin/codeoss-cloudworkstations --list-extensions --show-versions
```

It installs `julialang.language-julia@1.250.2`,
`ms-python.python@2026.4.0`, and
`devyas319.csv-interactive-table-viewer@0.1.5` from bundled VSIX files when needed.
The CSV viewer renders data in an interactive grid with sorting and filtering.
Right-click a CSV tab and choose **Reopen Editor With → CSV Table Viewer**
if the file opens as plain text. Its VSIX archive is downloaded after the
scientific sysimage layer; `Dockerfile.refresh` adds it to an existing image.
All three extensions should appear in that listing. Optional extension packs are
skipped so no other extensions need to be downloaded. No internet access is
required during participant startup. If installation fails, the startup log reports it.

The Julia extension's Juliaup recommendation is disabled, since the image
pins Julia 1.10. Symbol-cache downloads are enabled in machine settings to
avoid the extension's permission prompt while retaining its faster symbol
index. These defaults also apply to participants reusing an existing home.

Julia package caches are prepared during image construction. In addition to
precompiling the dependencies before copying editable source, the image loads
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
are written to `.vscode/settings.json` for both the repository root and the
participant `workshop/` folder. The Julia environment
points to the scientific project one level above `workshop/`.

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

Open `01_OceanBioME/00_reference_column.jl` in the participant Explorer. With the Julia extension loaded, `Ctrl+Shift+P` offers `Julia: Run File in
New Process` and `Julia: Execute File in REPL`. Julia also contributes a
Run action for `.jl` editors. Python contributes `Python: Run Python File in
Terminal` for `.py` editors. Check both commands after the browser loads.

If a command is absent, inspect the installed extensions with the CLI above
and use `Developer: Show Running Extensions` from `Ctrl+Shift+P`.

For a full annual simulation, use **Terminal > New Terminal** from the
participant `workshop/` folder:

```bash
julia --project=../oceanbiome 01_OceanBioME/00_reference_column.jl
```

The script writes figures and diagnostics into `results/oceanbiome/`,
relative to the participant workspace; click the PNGs in Explorer to view them.

## First-login editor and scientific warm-up (PR3)

`MASTS_WARMUP_ON_START=1` is enabled by default. On each newly provisioned
workstation, the startup stage installs the bundled editor extensions, then
launches a **non-blocking, one-time warm-up** in the participant's persistent
home. Operators can start workstations before the session and check readiness.

Preparation runs sequentially, with a per-user lock:

1. Load the pinned Julia 1.11 language-server environment.
2. Load the Julia 1.10 VS Code terminal-server environment.
3. Run a **two-day** LOBSTER column and create one figure with the scientific
   Julia 1.10 sysimage. Results are written to
   `~/.cache/masts-workshop/reference-output/`.

The participant exercises stay at **365 days** and remain independently
editable. Only missing workspace files are seeded on subsequent starts;
existing scripts, participant edits and results are preserved. Fingerprinting
avoids repeated preparation once an environment is ready; new relevant
scientific code or dependencies invalidate the completion marker.

In the workstation's terminal, inspect step-by-step progress and recorded
timings:

```bash
python /opt/workshop/warmup_workstation.py status
tail -f ~/.cache/masts-workshop/warmup.log
```

`status.json` reports `running`, `ready` or `failed`, the active step and
completed-step timings. The `ready` marker is written only after all three
stages pass; a failed warm-up is retried at the next workstation startup.
Set `MASTS_WARMUP_ON_START=0` to disable automatic preparation for a specific
container. The existing extension's symbol indexing can still run when a
participant opens a Julia project; confirm language-server readiness in the
browser, in addition to the warm-up status.

For local fresh-home validation, launch the refreshed image with a distinct
Docker volume and the Google Code OSS entrypoint:

```bash
sudo docker run --privileged --rm --name masts-workshop-pr3 \
  -p 127.0.0.1:8081:80 \
  -v masts-workshop-pr3-home:/home/user \
  masts-asm-2026-modelling:pr3
```

Open `http://localhost:8081/?folder=/home/user/masts-asm-2026-modelling/workshop`,
confirm the README and Explorer are visible, then run a reference exercise
and inspect the Plot Pane. Test a Julia REPL restart and a second launch
with the **same** volume. Check per-stage warm-up times against the previous
cold-start observations: approximately 230–270 s for first-use language-server
precompilation, 493 s for reference/plots warm-up, and a subsecond
`VSCodeServer` import in one prior warm-up. These are historical observations,
not yet measured PR3 improvements.

### Optional shared science sysimage

To reduce compilation across separate Julia processes, test an image built
with PackageCompiler 2.2.5. It uses a stable import-only workload and builds
a portable generic x86-64 sysimage containing OceanBioME, Oceananigans and
CairoMakie. Model execution and figure generation use the tested workshop code
in `oceanbiome/test/` and `scripts/test_container.sh`. The editable `MASTSWorkshop` package
is loaded from the participant workspace, so students can change workshop
code. The compiler is in a separate build-only environment.

The optional build uses `JULIA_IMAGE_THREADS=1` for Julia's native image
code generation, independently of `JULIA_NUM_THREADS=1`. The final sysimage
stage also sets `JULIA_NUM_PRECOMPILE_TASKS=1`, `OMP_NUM_THREADS=1`, and
`MKL_NUM_THREADS=1`. This stage runs after the cached Python, Julia dependency,
and PackageCompiler installation layers; changes to these limits retain those
caches. The build prints the effective settings before starting compilation.
These limits constrain parallelism but do not cap total sysimage memory use.
The build also prints image-compilation timings and measures peak cgroup memory separately for
PackageCompiler installation and system-image compilation, including child
processes. Installation skips eager package precompilation to reduce memory
pressure.

**Run the first memory measurement on the 128 GB Linux workstation** from the
same source revision as the tested ordinary image. Save the complete plain-text
build log:

```bash
set -o pipefail
docker build --platform linux/amd64 --progress=plain \
  --build-arg BUILD_WORKSHOP_SYSIMAGE=1 \
  --build-arg SYSIMAGE_IMAGE_THREADS=1 \
  -f container/Dockerfile \
  -t masts-asm-2026-modelling:sysimage . 2>&1 | tee sysimage-build.log
grep '\[sysimage-memory\]' sysimage-build.log
```

The `[sysimage-memory]` lines identify the `packagecompiler-install` and
`create-sysimage` phases and report elapsed time, sampled peak cgroup usage,
Linux's lifetime cgroup peak, and any cgroup memory limit, in MiB. The sampled
peak covers each phase; the lifetime peak may include earlier commands from the
same Docker `RUN`. These measure the build container's total
memory, including subprocesses, unlike a single Julia process's maximum RSS.
If the builder does not expose cgroup memory accounting, the output says
`unavailable` explicitly. A successful 128 GB build establishes the memory
requirement before testing a constrained builder on smaller hardware.

After a successful build, verify cold-run speed and scientific outputs:

```bash
./scripts/benchmark_container_startup.sh masts-asm-2026-modelling:sysimage
./scripts/test_container.sh masts-asm-2026-modelling:sysimage
```

If PackageCompiler fails or uses excessive resources, use
`--build-arg COMPILE_WORKSHOP_SYSIMAGE=0` with the same existing build arguments.
This fallback preserves the cached Python/Julia layers and runs the same science
environment without a custom sysimage.

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

Build with `BUILD_WORKSHOP_SYSIMAGE=1` and then run the reference and grazing
smoke tests. The import-only workload keeps student-exercise edits independent
from the expensive PackageCompiler step.

## Participant links after each cloud deployment

When Terraform recreates the cluster, fresh workstation URLs appear in
`cloud-workshops` status output. From the `cloud-workshops` repository, generate
ready-to-share links with the helper in this repository:

```bash
./scripts/workshop.sh status masts-2026 \n  | python ../masts-asm-2026-modelling/scripts/workstation_links.py
```

Add `--csv` to produce a CSV with workstation, assigned account and launch URL.
Each link opens the `workshop/` folder. Share each account's link privately
with its assigned participant; Google Workstations enforces the workstation IAM
permissions on access. Link generation is local and makes no Cloud API calls.

### Validate the compiled sysimage before deploying

Build with `BUILD_WORKSHOP_SYSIMAGE=1` and `COMPILE_WORKSHOP_SYSIMAGE=1`,
then run the fast acceptance test:

```bash
sudo ./scripts/test_sysimage.sh masts-asm-2026-modelling:sysimage
```

The script confirms that the workshop Julia launcher selects the compiled
sysimage, runs both 2-day LOBSTER column variants from the Julia test suite,
and writes a real CairoMakie physics figure. It performs the same checks with
and without the sysimage in separately writable depots and prints elapsed
time and peak memory for both configurations. The full 365-day reference and
grazing exercises remain covered by `scripts/test_container.sh`.

The sysimage includes Oceananigans, OceanBioME and CairoMakie. Its import-only
precompile workload targets faster package loading; the measured 2-day
test shows how much it also reduces startup for the actual column. Workstation
warm-up runs the full annual example to prepare each participant's environment.
