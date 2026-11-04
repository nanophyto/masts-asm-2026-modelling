# Instructor draft: MASTS ASM 2026

Participants use the same cloud workstation for both exercises. All environmental fields for the mechanistic model will be preloaded; biology is the main editable component.

## Abil exercise

1. Run the example script and read the test score and prediction plot.
2. Choose a predictor to leave out. How do the predictions change?
3. Consider why variable importance does not necessarily imply a causal relationship.

## OceanBioME exercise

1. Walk through the [reference column](../docs/src/index.md): model construction, initial conditions, the simulation and its plots.
2. Inspect six-tracer evolution, carbon export at 100 m and 300 m, and the depth-dependent export profile.
3. Predict how reducing grazing should affect phytoplankton biomass.
4. Choose from [light affinity](../workshop/01_OceanBioME/04_light_affinity.jl),
   [nutrient affinity](../workshop/01_OceanBioME/05_nutrient_affinity.jl),
   [grazing](../workshop/01_OceanBioME/01_grazing.jl),
   [sinking](../workshop/01_OceanBioME/02_sinking.jl),
   [remineralisation](../workshop/01_OceanBioME/03_remineralisation.jl), or
   [phytoplankton mortality](../workshop/01_OceanBioME/06_phytoplankton_mortality.jl).
5. Ask participants to predict the direction and timing of the change before
   running the second column, then compare biomass, nutrient recycling and export.
6. Discuss virus-like mortality as a bulk loss parameter, distinct from explicit
   viruses or infection dynamics.

For later independent use, point participants to **Running the examples on your own system** in the documentation. The physical-forcing appendix explains the reference light and mixing inputs and will include the four station columns.

**Key concept:** Predictive models learn patterns in observations; mechanistic models encode hypothesised processes and predict their consequences.
