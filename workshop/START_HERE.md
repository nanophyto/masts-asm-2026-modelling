# MASTS ASM 2026 — Getting started with modelling

**Start with `01_OceanBioME/00_reference_column.jl`.** Open it in the editor and
choose **Julia: Execute File in REPL**. The first run may take longer while Julia
initialises. Subsequent experiments can use the same REPL.

The examples use real `PhytoZoo`, `LOBSTER`, `NonhydrostaticModel`, `Simulation`,
`JLD2Writer`, and `run!` calls. `MASTSWorkshop.column(:BATS)` prepares the
idealised BATS-like water column, so you can focus on biological processes.

Then open **`01_OceanBioME/01_grazing.jl`** to compare control and reduced grazing.
Both scripts simulate a complete 365-day seasonal cycle. Images, profiles and
CSV diagnostics are saved under **`results/oceanbiome/`**.

The **`02_Abil/`** material will provide the afternoon Python/ML exercises.
For full explanations, questions and example figures, follow the workshop's
[online documentation](../docs/src/index.md).

In the terminal, from this folder, the reference can also be run with:

```bash
julia --project=../oceanbiome 01_OceanBioME/00_reference_column.jl
```
