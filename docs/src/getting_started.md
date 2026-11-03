# Getting started

## On a workshop Cloud Workstation

Open the individual launch link provided by your instructor and sign in with
**your assigned `nanophyto.org` account**. The link opens the participant
`workshop/` folder directly, with a short README, the OceanBioME exercises,
Abil.py material and a `results/` folder.

In the File Explorer, open **`01_OceanBioME/00_reference_column.jl`** and choose
**Julia: Execute File in REPL** from the Command Palette (`Ctrl+Shift+P`).
The first REPL launch may compile its editor integration; keep it open as you
move between exercises. Run **`01_OceanBioME/01_grazing.jl`** next to explore
biological responses. Saved PNGs appear in `results/oceanbiome/` and open
with a click in Explorer. Use `Ctrl+B` and `Ctrl+Shift+E` to restore the Explorer
if it was hidden in a previous session.

## Scientific walkthrough

The [reference LOBSTER column](generated/00_reference_column.md) introduces
Oceananigans and OceanBioME model construction, coupling and simulation, with
plots of vertical ecology and export. The [grazing experiment](generated/01_grazing.md)
compares two biological parameter choices. The
[physics appendix](generated/physical_forcing.md) explains the prepared light
and mixing conditions used by both exercises.

For local installations, Python and Julia setup, and independent figures,
follow [Running the examples on your own system](running_locally.md).
