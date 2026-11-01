# Combined scientific image (Cycle 1.4)

This image extends Google's Code OSS for Cloud Workstations base and includes
Julia 1.10, Oceananigans, OceanBioME, CairoMakie, Python 3.11, Abil.py and the
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

Open `http://localhost:8080`, then open
`/home/user/masts-asm-2026-modelling` in the editor. Files copied there
are writable and persist on the named Docker volume. The startup script
initialises each new participant home once; it preserves later edits.

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
OSS startup scripts are retained. The startup script only seeds the user
workspace and default editor configuration.

For reproducibility, commit the resolved `oceanbiome/Manifest.toml` after
successful scientific testing. The Dockerfile uses pinned direct package
versions and reproduces the installation into a fresh image.
