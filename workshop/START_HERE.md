# MASTS ASM 2026 — Getting started with modelling

**Start with `01_OceanBioME/00_reference_column.jl`.** Open it in the editor and
choose **Julia: Execute File in REPL**. Each figure appears in the Julia
Plot Pane as it is created; use plot history to revisit earlier figures.
The first run may take longer while Julia initialises. Reuse the same REPL
for subsequent experiments.

The examples use real `PhytoZoo`, `LOBSTER`, `NonhydrostaticModel`, `Simulation`,
`JLD2Writer`, and `run!` calls. `MASTSWorkshop.column(:BATS)` prepares the
idealised BATS-like water column, so you can focus on biological processes.

Then open **`01_OceanBioME/01_grazing.jl`** to compare control and reduced grazing.
Both scripts simulate a complete 365-day seasonal cycle. Images, profiles and
CSV diagnostics are saved under **`results/oceanbiome/`**. Expand this folder
in Explorer and click any PNG to inspect the corresponding figure. Open a
CSV file to inspect its columns in the interactive table; if it opens as text,
right-click its tab and select **Reopen Editor With → CSV Table Viewer**.

The **`02_Abil/`** material will provide the afternoon Python/ML exercises.
For full explanations and example figures, see the workshop's
[documentation source](../docs/src/index.md) (published as Documenter pages).

In the terminal, from this folder, the reference can also be run with:

```bash
julia --project=../oceanbiome 01_OceanBioME/00_reference_column.jl
```
