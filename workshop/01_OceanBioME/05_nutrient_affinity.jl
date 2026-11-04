# # Experiment: How does nitrate affinity affect phytoplankton growth?
#
# Phytoplankton uptake is constrained by available nutrients. Here we change the nitrate
# half-saturation concentration while preserving the light response, ammonia affinity,
# grazing and physics.
#
# Both simulations run a full 365-day seasonal cycle.

# ## Load OceanBioME, Oceananigans, and the workshop utilities

using OceanBioME, Oceananigans, CairoMakie
using Oceananigans.Units
import MASTSWorkshop
using MASTSWorkshop: results_directory, analyse_column_output, write_diagnostics, write_export_profile,
                     plot_parameter_response, plot_parameter_export

# ## Define the water column
#
# The prepared BATS-like environment supplies a 500 m column with 50 cells,
# a 30-minute time step, initial tracer concentrations, seasonal light,
# and vertically implicit mixing. Both experiments use the same physics.

grid, time_step, initial, closure, surface_PAR = MASTSWorkshop.column(:BATS)
output_dir = results_directory("nutrient_affinity")

# ## Choose the biological experiment
#
# The nitrate half-saturation constant sets the concentration scale for nitrate
# limitation. A smaller value means higher nitrate affinity: growth is less limited when
# nitrate is scarce. Ammonium uptake remains unchanged.
#
# Nitrate half-saturation is in mmol N/m³. Lower K_NO3 means greater uptake affinity,
# not a higher initial nutrient concentration.

# ## Control experiment: reference biology
#
# The default nitrate half-saturation is 0.7 mmol N/m³; the ammonium
# half-saturation is 0.001 mmol N/m³ ([LOBSTER defaults](https://oceanbiome.github.io/OceanBioME.jl/stable/generated/LOBSTER_parameters/)).

# `LOBSTER` constructs the default `PhytoZoo` plankton, nutrient and detritus
# components; [LOBSTER's parameters](https://oceanbiome.github.io/OceanBioME.jl/stable/generated/LOBSTER_parameters/)
# provide the reference values. `NonhydrostaticModel` couples all seven
# tracers to the physical column, where the closure mixes them vertically.

control_biogeochemistry = LOBSTER(grid; surface_PAR)
control_model = NonhydrostaticModel(grid; closure, biogeochemistry = control_biogeochemistry)
set!(control_model; initial...)

# ## Run and save the control simulation
#
# We evolve the seven tracers for 365 days and save daily JLD2 profiles.

control_simulation = Simulation(control_model; Δt = time_step, stop_time = 365days)
control_file = joinpath(output_dir, "control.jld2")
control_simulation.output_writers[:profiles] = JLD2Writer(control_model, control_model.tracers;
    filename = control_file, schedule = TimeInterval(1day), overwrite_files = true)
run!(control_simulation)

# The saved profiles are analysed to calculate the nitrogen budget, tracer
# evolution, and cumulative organic-carbon export at 100 m and 300 m.

control_results = analyse_column_output(control_file, control_model)

# Export the diagnostic summary and depth-dependent carbon fluxes:
write_diagnostics(joinpath(output_dir, "control_diagnostics.csv"), control_results)
write_export_profile(joinpath(output_dir, "control_export_profile.csv"), control_results)

# Print a few key results to the Julia REPL:
println("Control: final surface phytoplankton = ", last(control_results.surface_P), " mmol N/m³")
println("Control: cumulative export at 100 m = ", last(control_results.export_100.cumulative_g_C), " g C/m²")
println("Control: cumulative export at 300 m = ", last(control_results.export_300.cumulative_g_C), " g C/m²")
println("Control: nitrogen budget residual = ", last(control_results.budget_residual), " mmol N/m²")

# ## Modified biology: higher nitrate affinity
#
# Reduce the nitrate half-saturation concentration from 0.7 to 0.35 mmol N/m³; retain
# the 0.001 mmol N/m³ ammonia constant.

modified_plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.35, ammonia = 0.001))
modified_biogeochemistry = LOBSTER(grid; plankton = modified_plankton,
                                   surface_PAR)
modified_model = NonhydrostaticModel(grid; closure, biogeochemistry = modified_biogeochemistry)
set!(modified_model; initial...)

# ## Run and save the modified simulation
#
# We repeat the 365-day seasonal cycle, retaining the same daily output schedule.

modified_simulation = Simulation(modified_model; Δt = time_step, stop_time = 365days)
modified_file = joinpath(output_dir, "higher_nutrient_affinity.jld2")
modified_simulation.output_writers[:profiles] = JLD2Writer(modified_model, modified_model.tracers;
    filename = modified_file, schedule = TimeInterval(1day), overwrite_files = true)
run!(modified_simulation)

# Analyse the second run in the same way so the two results are comparable.

modified_results = analyse_column_output(modified_file, modified_model)

# Export the corresponding diagnostic summary and carbon fluxes:
write_diagnostics(joinpath(output_dir, "higher_nutrient_affinity_diagnostics.csv"), modified_results)
write_export_profile(joinpath(output_dir, "higher_nutrient_affinity_export_profile.csv"), modified_results)

# Print the modified-run results for comparison:
println("Modified: final surface phytoplankton = ", last(modified_results.surface_P), " mmol N/m³")
println("Modified: cumulative export at 100 m = ", last(modified_results.export_100.cumulative_g_C), " g C/m²")
println("Modified: cumulative export at 300 m = ", last(modified_results.export_300.cumulative_g_C), " g C/m²")
println("Modified: nitrogen budget residual = ", last(modified_results.budget_residual), " mmol N/m²")

# ## Inspect the two simulation outputs
#
# The left panels show both treatments, and the right panels show
# modified minus control. All curves use the same daily output times.
#md # WORKSHOP_PARAMETER_OUTPUT

response_figure_path = joinpath(output_dir, "nutrient_affinity_response.png")
plot_parameter_response(control_results, modified_results, response_figure_path;
                        label = "Higher nitrate affinity",
                        figure_title = "Nutrient affinity — surface response and detritus")
println("Saved $response_figure_path")

#md # WORKSHOP_PARAMETER_RESPONSE_FIGURE

# ## Compare particulate carbon export
#
# Compare daily and cumulative export at both 100 m and 300 m. The
# first days also reflect adjustment of initially prescribed particles.

export_figure_path = joinpath(output_dir, "nutrient_affinity_export.png")
plot_parameter_export(control_results, modified_results, export_figure_path;
                      label = "Higher nitrate affinity",
                      figure_title = "Nutrient affinity — carbon export")
println("Saved $export_figure_path")

#md # WORKSHOP_PARAMETER_EXPORT_FIGURE

# ## What to look for
#
# When does increased nitrate affinity matter most? Look at the surface nitrate
# concentration and phytoplankton bloom. Does the model use more nitrate during
# low-nutrient conditions? How does the response propagate to carbon export?
#
