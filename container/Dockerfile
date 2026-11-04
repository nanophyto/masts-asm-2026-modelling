# syntax=docker/dockerfile:1
# Julia from the official image, editor lifecycle from Google Cloud Workstations.
FROM julia:1.10.12-bookworm AS julia-runtime

# The Julia extension 1.250.2 requires Julia >=1.11 for its language server.
# Use a separate editor-only binary while workshop science remains on 1.10.
FROM julia:1.11.9-bookworm AS julia-language-server

FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

ARG TARGETARCH
ARG SOURCE_REPOSITORY=""
ARG JULIA_EXTENSION_VERSION=1.250.2
ARG PYTHON_EXTENSION_VERSION=2026.4.0
# Set to 1 for an experimental, portable scientific sysimage benchmark.
ARG BUILD_WORKSHOP_SYSIMAGE=0
# Image-codegen threads differ from JULIA_NUM_THREADS; 1 reduces peak RAM.
ARG SYSIMAGE_IMAGE_THREADS=1

LABEL org.opencontainers.image.title="MASTS ASM 2026 modelling workshop" \
      org.opencontainers.image.description="OceanBioME.jl and Abil.py with Code OSS for Cloud Workstations" \
      org.opencontainers.image.source="${SOURCE_REPOSITORY}"

ENV DEBIAN_FRONTEND=noninteractive \
    JULIA_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONNOUSERSITE=1 \
    JULIA_DEPOT_PATH=/home/user/.julia:/opt/workshop/julia-depot \
    PATH=/opt/workshop/python/bin:/opt/workshop/bin:/opt/julia/bin:${PATH}

# Miniforge's bundled Python is independent of the base editor's Python.
# This installer is pinned and checksum-verified.
RUN test "$TARGETARCH" = "amd64" \
    && /google/scripts/refresh-preinstalled-apt-keys.sh \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git unzip fontconfig fonts-dejavu-core \
       libgl1 libegl1 libxrender1 libxext6 libglib2.0-0 time \
    && rm -rf /var/lib/apt/lists/*

COPY --from=julia-runtime /usr/local/julia /opt/julia
COPY --from=julia-language-server /usr/local/julia /opt/julia-ls

# Verify both runtimes at build time and keep Julia 1.10 first on PATH.
RUN /opt/julia/bin/julia --startup-file=no -e '@assert VERSION == v"1.10.12"' \
    && /opt/julia-ls/bin/julia --startup-file=no -e '@assert VERSION == v"1.11.9"'

RUN curl -fL --retry 4 --retry-delay 2 \
      https://github.com/conda-forge/miniforge/releases/download/25.3.0-3/Miniforge3-25.3.0-3-Linux-x86_64.sh \
      -o /tmp/miniforge.sh \
    && echo '1b57f8cb991982063f79b56176881093abb1dc76d73fda32102afde60585b5a1  /tmp/miniforge.sh' | sha256sum -c - \
    && bash /tmp/miniforge.sh -b -p /opt/miniforge \
    && /opt/miniforge/bin/conda create -y -p /opt/workshop/python python=3.11 pip \
    && rm /tmp/miniforge.sh \
    && /opt/miniforge/bin/conda clean -afy

# Install the scientific environment from its dependency files first. An
# existing Manifest.toml is honoured; an absent one is resolved at build time.
# Keep the editable package code and exercises out of this cached layer.
COPY oceanbiome/*.toml /opt/workshop/source/oceanbiome/
RUN mkdir -p /opt/workshop/source/oceanbiome/src \
    && printf 'module MASTSWorkshop\nend\n' > /opt/workshop/source/oceanbiome/src/MASTSWorkshop.jl
COPY abil/requirements.txt /opt/workshop/source/abil/requirements.txt
COPY container/workshop-julia /opt/workshop/bin/julia
COPY container/ensure_language_extensions.py container/configure_editor.py \
     /opt/workshop/source/container/
RUN chmod +x /opt/workshop/bin/julia
WORKDIR /opt/workshop/source

# Pin the language extensions and store the archives in the image. The user's
# persistent /home/user volume hides anything installed there at build time,
# so the 120_ startup task installs these from the local files using the Code
# OSS CLI. This requires no marketplace connection at participant login.
RUN mkdir -p /opt/workshop/vsix \
    && curl -fL --retry 4 --retry-delay 2 \
      "https://open-vsx.org/api/julialang/language-julia/${JULIA_EXTENSION_VERSION}/file/julialang.language-julia-${JULIA_EXTENSION_VERSION}.vsix" \
      -o /opt/workshop/vsix/julia.vsix \
    && curl -fL --retry 4 --retry-delay 2 \
      "https://open-vsx.org/api/ms-python/python/${PYTHON_EXTENSION_VERSION}/file/ms-python.python-${PYTHON_EXTENSION_VERSION}.vsix" \
      -o /opt/workshop/vsix/python.vsix \
    && /opt/workshop/python/bin/python container/ensure_language_extensions.py verify-language /opt/workshop/vsix


# The Google base includes Cloud Code (and hence Gemini); workshop users
# need the editor, terminal and Julia language extension, not cloud AI tools.
RUN /opt/workshop/python/bin/python container/configure_editor.py remove-google-ai /opt/code-oss/extensions \
    && /opt/workshop/python/bin/python container/configure_editor.py remove-google-ai /opt/code-oss/resources/app/extensions

RUN /opt/workshop/python/bin/python -m pip install --no-cache-dir -r abil/requirements.txt

# The workshop Project.toml declares this Makie extension. Provide its minimal
# entry point for dependency precompilation; the actual plotting source is
# copied with the other editable workshop code near the end of the build.
# This comes after pip so an extension fix reuses the expensive Python layer.
RUN mkdir -p /opt/workshop/source/oceanbiome/ext \
    && printf 'module MASTSWorkshopMakieExt\nend\n' \
       > /opt/workshop/source/oceanbiome/ext/MASTSWorkshopMakieExt.jl

# Precompile third-party science dependencies separately from frequently
# edited workshop helpers, plotting methods and exercises. Instantiation is
# cached independently, so a later compile failure retains downloaded packages.
RUN mkdir -p /opt/workshop/julia-depot \
    && JULIA_DEPOT_PATH=/opt/workshop/julia-depot JULIA_PKG_PRECOMPILE_AUTO=0 \
       julia --threads=1 --startup-file=no --project=oceanbiome \
       -e 'using Pkg; Pkg.instantiate()'

RUN JULIA_DEPOT_PATH=/opt/workshop/julia-depot JULIA_PKG_PRECOMPILE_AUTO=0 \
      julia --threads=1 --startup-file=no --project=oceanbiome \
      -e 'using Pkg; Pkg.precompile()' \
    && JULIA_DEPOT_PATH=/opt/workshop/julia-depot \
       julia --threads=1 --startup-file=no --project=oceanbiome \
       -e 'using OceanBioME, Oceananigans, CairoMakie'

# Cache the optional PackageCompiler installation independently of workload
# edits. Keep its memory measurements and the scientific Julia 1.10 project.
COPY container/measure_sysimage_memory.py /opt/workshop/source/container/
RUN set -eu; \
    if [ "$BUILD_WORKSHOP_SYSIMAGE" = "1" ]; then \
      apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*; \
      mkdir -p /opt/workshop/sysimages /opt/workshop/sysimage-build; \
      MASTS_MEMORY_PHASE=packagecompiler-install JULIA_PKG_PRECOMPILE_AUTO=0 \
      JULIA_DEPOT_PATH=/opt/workshop/julia-depot \
        /opt/workshop/python/bin/python container/measure_sysimage_memory.py -- \
        /opt/julia/bin/julia --startup-file=no \
        -e 'using Pkg; Pkg.activate("/opt/workshop/sysimage-build"); Pkg.add(Pkg.PackageSpec(name="PackageCompiler", version="2.2.5"))'; \
    fi

# Changes to the precompile workload now reuse cached Python, Julia packages,
# scientific precompilation and the PackageCompiler installation.
COPY container/build_workshop_sysimage.jl container/precompile_reference.jl \
     /opt/workshop/source/container/

# Fallback control is deliberately declared after all costly dependency layers.
# The default builds the sysimage; 0 keeps the fully precompiled regular Julia environment.
ARG COMPILE_WORKSHOP_SYSIMAGE=1

# Bound concurrent package-precompilation and native-library workers in the
# sysimage build and runtime. Keep this ENV after dependency installation so
# changing these limits never invalidates cached Python/Julia package layers.
ENV JULIA_NUM_PRECOMPILE_TASKS=1 \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1

# Check package imports before producing the scientific sysimage.
RUN set -eu; \
    if [ "$BUILD_WORKSHOP_SYSIMAGE" = "1" ] && [ "$COMPILE_WORKSHOP_SYSIMAGE" = "1" ]; then \
      printf 'Sysimage concurrency: JULIA_NUM_THREADS=%s, JULIA_NUM_PRECOMPILE_TASKS=%s, JULIA_IMAGE_THREADS=%s, OPENBLAS_NUM_THREADS=%s, OMP_NUM_THREADS=%s, MKL_NUM_THREADS=%s\n' \
        "$JULIA_NUM_THREADS" "$JULIA_NUM_PRECOMPILE_TASKS" "$SYSIMAGE_IMAGE_THREADS" "$OPENBLAS_NUM_THREADS" "$OMP_NUM_THREADS" "$MKL_NUM_THREADS"; \
      JULIA_DEPOT_PATH=/opt/workshop/julia-depot \
        /opt/julia/bin/julia --threads=1 --startup-file=no \
        --project=oceanbiome container/precompile_reference.jl; \
      MASTS_MEMORY_PHASE=create-sysimage \
      JULIA_IMAGE_THREADS="$SYSIMAGE_IMAGE_THREADS" JULIA_IMAGE_TIMINGS=1 \
      JULIA_DEPOT_PATH=/opt/workshop/julia-depot \
        /opt/workshop/python/bin/python container/measure_sysimage_memory.py -- \
        /opt/julia/bin/julia --threads=1 --startup-file=no \
        --project=/opt/workshop/sysimage-build container/build_workshop_sysimage.jl; \
      test -s /opt/workshop/sysimages/masts-workshop.so; \
      JULIA_DEPOT_PATH=/opt/workshop/julia-depot /opt/workshop/bin/julia \
        --startup-file=no --project=oceanbiome \
        -e 'using OceanBioME, Oceananigans, CairoMakie'; \
    fi

# Source-only edits begin here: Docker reuses the Julia/Python dependency and
# sysimage layers above. Compiling MASTSWorkshop itself is intentionally late
# so new helper/plot code is loaded from the actual participant checkout.
# The upstream BATS regressor additionally uses Matplotlib and Seaborn.
# Keep these layers separate from Julia/PackageCompiler and changing exercises.
COPY abil/requirements-bats.txt /tmp/requirements-bats.txt
RUN /opt/workshop/python/bin/python -m pip install --no-cache-dir -r /tmp/requirements-bats.txt \
    && /opt/workshop/python/bin/python -c 'import matplotlib, seaborn; from abil.tune import ModelTuner; from abil.predict import ModelPredictor; from abil.post import AbilPostProcessor'

# Include pinned upstream BATS CSVs in the image so participants work offline.
COPY abil/fetch_bats_data.py /tmp/fetch_bats_data.py
RUN /opt/workshop/python/bin/python /tmp/fetch_bats_data.py \
      --dest /opt/workshop/source/workshop/02_Abil/data
ENV MPLBACKEND=Agg

COPY . /opt/workshop/source

# Small editor-only addon: download after PackageCompiler so it never
# invalidates the expensive Julia sysimage layers.
ARG CSV_EXTENSION_VERSION=0.1.5
RUN curl -fL --retry 4 --retry-delay 2 \
      "https://open-vsx.org/api/devyas319/csv-interactive-table-viewer/${CSV_EXTENSION_VERSION}/file/devyas319.csv-interactive-table-viewer-${CSV_EXTENSION_VERSION}.vsix" \
      -o /opt/workshop/vsix/csv.vsix \
    && /opt/workshop/python/bin/python container/ensure_language_extensions.py verify /opt/workshop/vsix

RUN /opt/workshop/python/bin/python -m unittest discover -s abil/tests -p 'test_*.py' -v \
    && JULIA_DEPOT_PATH=/opt/workshop/julia-depot \
       julia --threads=1 --startup-file=no --project=oceanbiome \
       -e 'using MASTSWorkshop, CairoMakie; @assert !isnothing(Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt)); @assert !isempty(methods(MASTSWorkshop.plot_reference_export)); @assert !isempty(methods(MASTSWorkshop.plot_grazing_response))'

# Warm the editable participant checkout at its eventual absolute path. This
# cache is source-dependent; the third-party sysimage above is not.
RUN mkdir -p /home/user/masts-asm-2026-modelling \
    && cp -R --preserve=mode,timestamps /opt/workshop/source/. \
       /home/user/masts-asm-2026-modelling/ \
    && JULIA_DEPOT_PATH=/opt/workshop/julia-depot \
       julia --threads=1 --startup-file=no \
       --project=/home/user/masts-asm-2026-modelling/oceanbiome \
       -e 'using MASTSWorkshop, CairoMakie; @assert !isnothing(Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt)); @assert !isempty(methods(MASTSWorkshop.plot_reference_export)); @assert !isempty(methods(MASTSWorkshop.plot_grazing_response))' \
    && rm -rf /home/user/masts-asm-2026-modelling

# Executed by Google's standard entrypoint after user creation and before
# Code OSS starts. The base entrypoint and editor scripts stay unchanged.
COPY container/100_seed-workshop.sh /etc/workstation-startup.d/100_seed-workshop.sh
COPY container/120_install_language_extensions.sh /etc/workstation-startup.d/120_install_language_extensions.sh
COPY container/210_warmup_workstation.sh /etc/workstation-startup.d/210_warmup_workstation.sh
COPY container/warmup_workstation.py /opt/workshop/warmup_workstation.py
COPY container/workspace-settings.json /opt/workshop/workspace-settings.json
COPY container/machine-settings.json /opt/workshop/machine-settings.json
COPY container/configure_editor.py /opt/workshop/configure_editor.py
COPY container/ensure_language_extensions.py /opt/workshop/ensure_language_extensions.py
# Warm per-user editor caches during operator-started workstation preparation.
ENV MASTS_WARMUP_ON_START=1
RUN chmod +x /etc/workstation-startup.d/100_seed-workshop.sh /etc/workstation-startup.d/120_install_language_extensions.sh /etc/workstation-startup.d/210_warmup_workstation.sh

EXPOSE 80
