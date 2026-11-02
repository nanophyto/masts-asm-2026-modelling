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

# Keep the runnable package environment and precompiled dependencies outside
# /home: Cloud Workstations mounts a persistent home volume at startup.
COPY . /opt/workshop/source
COPY container/workshop-julia /opt/workshop/bin/julia
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
    && /opt/workshop/python/bin/python container/ensure_language_extensions.py verify /opt/workshop/vsix


# The Google base includes Cloud Code (and hence Gemini); workshop users
# need the editor, terminal and Julia language extension, not cloud AI tools.
RUN /opt/workshop/python/bin/python container/configure_editor.py remove-google-ai /opt/code-oss/extensions \
    && /opt/workshop/python/bin/python container/configure_editor.py remove-google-ai /opt/code-oss/resources/app/extensions

RUN /opt/workshop/python/bin/python -m pip install --no-cache-dir -r abil/requirements.txt \
    && /opt/workshop/python/bin/python -m unittest discover -s abil/tests -p 'test_*.py' -v

RUN mkdir -p /opt/workshop/julia-depot \
    && JULIA_DEPOT_PATH=/opt/workshop/julia-depot JULIA_PKG_PRECOMPILE_AUTO=0 \
       julia --threads=1 --startup-file=no --project=oceanbiome \
       -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()' \
    && JULIA_DEPOT_PATH=/opt/workshop/julia-depot \
       julia --threads=1 --startup-file=no --project=oceanbiome \
       -e 'using MASTSWorkshop, OceanBioME, Oceananigans, CairoMakie; @assert !isnothing(Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt))'

# Also warm the editable participant checkout at its eventual absolute path.
# Julia's compiled cache tracks source paths; the first workspace copy at
# startup preserves source timestamps, so this cache can be reused. Keep the
# built image's /home clean for Google Workstations' persistent home mount.
RUN mkdir -p /home/user/masts-asm-2026-modelling \
    && cp -R --preserve=mode,timestamps /opt/workshop/source/. \
       /home/user/masts-asm-2026-modelling/ \
    && JULIA_DEPOT_PATH=/opt/workshop/julia-depot \
       julia --threads=1 --startup-file=no \
       --project=/home/user/masts-asm-2026-modelling/oceanbiome \
       -e 'using MASTSWorkshop, CairoMakie; @assert !isnothing(Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt))' \
    && rm -rf /home/user/masts-asm-2026-modelling

# Build-time JIT optimisation is opt-in until it has been timed and validated
# on the actual amd64 workstation machine type. PackageCompiler is isolated
# from the scientific Project/Manifest, which remain Julia 1.10 and editable.
RUN if [ "$BUILD_WORKSHOP_SYSIMAGE" = "1" ]; then \
      apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*; \
      mkdir -p /opt/workshop/sysimages /opt/workshop/sysimage-build; \
      JULIA_DEPOT_PATH=/opt/workshop/julia-depot /opt/julia/bin/julia --startup-file=no \
        -e 'using Pkg; Pkg.activate("/opt/workshop/sysimage-build"); Pkg.add(Pkg.PackageSpec(name="PackageCompiler", version="2.2.5"))'; \
      JULIA_DEPOT_PATH=/opt/workshop/julia-depot /opt/julia/bin/julia \
        --threads=1 --startup-file=no --project=/opt/workshop/sysimage-build \
        container/build_workshop_sysimage.jl; \
      JULIA_DEPOT_PATH=/opt/workshop/julia-depot /opt/workshop/bin/julia \
        --startup-file=no --project=oceanbiome \
        -e 'using OceanBioME, Oceananigans, CairoMakie'; \
    fi

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
RUN chmod +x /etc/workstation-startup.d/100_seed-workshop.sh /etc/workstation-startup.d/120_install_language_extensions.sh /etc/workstation-startup.d/210_warmup_workstation.sh

EXPOSE 80
