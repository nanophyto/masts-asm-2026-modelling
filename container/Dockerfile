# syntax=docker/dockerfile:1
# Julia from the official image, editor lifecycle from Google Cloud Workstations.
FROM julia:1.10.12-bookworm AS julia-runtime

FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

ARG TARGETARCH
ARG SOURCE_REPOSITORY=""
ARG JULIA_EXTENSION_VERSION=1.245.0

LABEL org.opencontainers.image.title="MASTS ASM 2026 modelling workshop" \
      org.opencontainers.image.description="OceanBioME.jl and Abil.py with Code OSS for Cloud Workstations" \
      org.opencontainers.image.source="${SOURCE_REPOSITORY}"

ENV DEBIAN_FRONTEND=noninteractive \
    JULIA_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONNOUSERSITE=1 \
    JULIA_DEPOT_PATH=/home/user/.julia:/opt/workshop/julia-depot \
    PATH=/opt/workshop/python/bin:/opt/julia/bin:${PATH}

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

RUN curl -fL --retry 4 --retry-delay 2 \
      https://github.com/conda-forge/miniforge/releases/download/25.3.0-3/Miniforge3-25.3.0-3-Linux-x86_64.sh \
      -o /tmp/miniforge.sh \
    && echo '1b57f8cb991982063f79b56176881093abb1dc76d73fda32102afde60585b5a1  /tmp/miniforge.sh' | sha256sum -c - \
    && bash /tmp/miniforge.sh -b -p /opt/miniforge \
    && /opt/miniforge/bin/conda create -y -p /opt/workshop/python python=3.11 pip \
    && rm /tmp/miniforge.sh \
    && /opt/miniforge/bin/conda clean -afy

# Pre-install the Julia extension in Code OSS, so sessions don't require
# marketplace access or per-participant installation.
RUN curl -fL --retry 4 --retry-delay 2 \
      "https://open-vsx.org/api/julialang/language-julia/${JULIA_EXTENSION_VERSION}/file/julialang.language-julia-${JULIA_EXTENSION_VERSION}.vsix" \
      -o /tmp/julia-extension.vsix \
    && mkdir -p /tmp/julia-extension \
    && unzip -q /tmp/julia-extension.vsix 'extension/*' -d /tmp/julia-extension \
    && mv /tmp/julia-extension/extension /opt/code-oss/extensions/julia \
    && chmod -R a+rX /opt/code-oss/extensions/julia \
    && rm -rf /tmp/julia-extension /tmp/julia-extension.vsix

# Keep the runnable package environment and precompiled dependencies outside
# /home: Cloud Workstations mounts a persistent home volume at startup.
COPY . /opt/workshop/source
WORKDIR /opt/workshop/source

RUN /opt/workshop/python/bin/python -m pip install --no-cache-dir -r abil/requirements.txt \
    && /opt/workshop/python/bin/python -m unittest discover -s abil/tests -p 'test_*.py' -v

RUN mkdir -p /opt/workshop/julia-depot \
    && JULIA_DEPOT_PATH=/opt/workshop/julia-depot JULIA_PKG_PRECOMPILE_AUTO=0 \
       julia --threads=1 --startup-file=no --project=oceanbiome \
       -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()' \
    && JULIA_DEPOT_PATH=/opt/workshop/julia-depot \
       julia --threads=1 --startup-file=no --project=oceanbiome \
       -e 'using MASTSWorkshop, OceanBioME, Oceananigans, CairoMakie; @assert !isnothing(Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt))'

# Executed by Google's standard entrypoint after user creation and before
# Code OSS starts. The base entrypoint and editor scripts stay unchanged.
COPY container/100_seed-workshop.sh /etc/workstation-startup.d/100_seed-workshop.sh
COPY container/workspace-settings.json /opt/workshop/workspace-settings.json
RUN chmod +x /etc/workstation-startup.d/100_seed-workshop.sh

EXPOSE 80
