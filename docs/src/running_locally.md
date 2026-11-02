# Running the examples on your own system

The same Julia and Python scripts used during the workshop can run on a laptop
or workstation after the cloud teaching environment has been shut down. The
repository includes the scientific package definitions and the complete
participant exercises.

## Get the code

Open the **MASTS ASM 2026 modelling** repository on GitHub. Choose **Code →
Download ZIP**, extract the archive, and open a terminal in the extracted
`masts-asm-2026-modelling` directory. Alternatively, choose **Code → HTTPS**
and use the displayed URL with `git clone`.

All commands below run from the repository root.

## Install Julia and Python

Install [Julia 1.10](https://julialang.org/downloads/) (the Julia package
manager will install the OceanBioME, Oceananigans and CairoMakie versions
specified by the repository). For the Python exercises, install
[Miniconda](https://www.anaconda.com/docs/getting-started/miniconda/main) or
Anaconda and create a dedicated Python 3.11 environment:

```bash
conda create -n masts-2026 python=3.11 pip
conda activate masts-2026
```

Check the active interpreters:

```bash
julia --version
python --version
```

## Set up the workshop environments

On Linux or macOS, the supplied setup and test scripts install the Python
packages and instantiate the Julia project:

```bash
./scripts/setup_local.sh
./scripts/test_local.sh
```

The Julia environment is `oceanbiome/` and the Python requirements are in
`abil/requirements.txt`. The `MASTSWorkshop` helper package is part of the
Julia project. Each environment uses the pinned versions supplied with the
repository.

On Windows PowerShell, use the same environments with the commands directly:

```powershell
python -m pip install -r abil/requirements.txt
julia --threads=1 --project=oceanbiome -e 'using Pkg; Pkg.instantiate()'
python -m unittest discover -s abil/tests -p 'test_*.py' -v
julia --threads=1 --project=oceanbiome oceanbiome/test/runtests.jl
```

## Run the examples

First run the reference column:

```bash
julia --threads=1 --project=oceanbiome oceanbiome/exercises/00_reference_column.jl
```

Then change grazing and compare two columns:

```bash
julia --threads=1 --project=oceanbiome oceanbiome/exercises/01_grazing.jl
```

Both scripts generate JLD2 tracer profiles, diagnostic CSVs and PNG figures
under `outputs/oceanbiome/`. The reference outputs are in its
`reference_column/` subdirectory. Experiment results are saved in the
main `outputs/oceanbiome/` directory.

For a short two-day check, append `--quick --plot` to either command. This
also tests CairoMakie figure generation. Initial plotting compilation may
take longer than later runs.

Both Julia exercises use 50 vertical cells over 500 m, a 30-minute time step,
and vertically implicit mixing. The same configuration is used for the full
365-day run and the two-day check.

## Run the workshop image with Docker

A combined Julia/Python environment with browser-based Code OSS is also
available as a container image. Once the workshop image is published, use
`ghcr.io/<owner>/masts-asm-2026-modelling:latest` in the following command,
replacing `<owner>` with the organisation or account hosting the repository:

```bash
docker run --privileged --rm -p 127.0.0.1:8080:80 \
  -v masts-workshop-home:/home/user \
  ghcr.io/<owner>/masts-asm-2026-modelling:latest
```

Open `http://localhost:8080` and then
`/home/user/masts-asm-2026-modelling`. The named volume retains edits and
output files between sessions. See the repository's `container/README.md`
for local image building and verification.

## Workshop tutorials and reference plots

The published GitHub Pages documentation contains the reference-column walkthrough,
the parameter experiments and their validated figures. Use the scripts above to
reproduce the simulations and generate your own plots.

Continue with the [reference column](generated/00_reference_column.md),
the [grazing experiment](generated/01_grazing.md), or the
[physical-forcing appendix](generated/physical_forcing.md).
