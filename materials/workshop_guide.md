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
4. Run the [grazing experiment](../oceanbiome/exercises/01_grazing.jl) and compare the two simulations.
5. Discuss why a biomass increase does not automatically imply a proportional export increase.

For later independent use, point participants to **Running the examples on your own system** in the documentation. The physical-forcing appendix explains the reference light and mixing inputs and will include the four station columns.

**Key concept:** Predictive models learn patterns in observations; mechanistic models encode hypothesised processes and predict their consequences.
