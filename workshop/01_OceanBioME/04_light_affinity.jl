# # Experiment: How does phytoplankton light affinity affect the seasonal bloom?
#
# Light limits photosynthesis in the upper ocean. Change the light half-saturation
# constant while keeping the incident light, nutrient affinity, grazing and physics the
# same.
#
# From the repository root:
#
# ```bash
# julia --project=oceanbiome workshop/01_OceanBioME/04_light_affinity.jl
# ```
#
# Both columns simulate one full 365-day seasonal cycle, using identical
# 500 m grids, 30-minute time steps, light forcing and mixing. Results are
# saved as JLD2 profiles, CSV summaries and PNG figures.

# ## Load the packages and prepare the reference water column

using OceanBioME, Oceananigans, CairoMakie
using Oceananigans.Units
import MASTSWorkshop
using MASTSWorkshop: results_directory, analyse_column_output, write_diagnostics, write_export_profile,
                     plot_parameter_response, plot_parameter_export

grid, time_step, initial, closure, surface_PAR = MASTSWorkshop.column(:BATS)
output_dir = results_directory("light_affinity")

# ## The biological question
#
# The light half-saturation constant is the irradiance at which the light response
# reaches half of its maximum. A smaller value means higher light affinity:
# phytoplankton can grow more effectively under dimmer conditions.
#
# light_half_saturation uses W/m2. Lower K_light means greater affinity, not more
# incident sunlight.

# ## Control: reference biology
#
# Use the reference light half-saturation constant of 33 W/m2.

control_plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                             light_half_saturation = 33.0,
                             maximum_grazing_rate = 0.8 / day)
control_biogeochemistry = LOBSTER(grid; plankton = control_plankton,
                                  surface_PAR, scale_negatives = true)
control_model = NonhydrostaticModel(grid; closure, biogeochemistry = control_biogeochemistry)
set!(control_model; initial...)

control_simulation = Simulation(control_model; Δt = time_step, stop_time = 365days)
control_file = joinpath(output_dir, "control.jld2")
control_simulation.output_writers[:profiles] = JLD2Writer(control_model, control_model.tracers;
    filename = control_file, schedule = TimeInterval(1day), overwrite_files = true)
run!(control_simulation)

control_results = analyse_column_output(control_file, control_model)
write_diagnostics(joinpath(output_dir, "control_diagnostics.csv"), control_results)
write_export_profile(joinpath(output_dir, "control_export_profile.csv"), control_results)
println("Control: final surface P = ", last(control_results.surface_P), " mmol N/m3")
println("Control: export at 100 m = ", last(control_results.export_100.cumulative_g_C), " g C/m2")
println("Control: export at 300 m = ", last(control_results.export_300.cumulative_g_C), " g C/m2")
println("Control: budget residual = ", last(control_results.budget_residual), " mmol N/m2")

# ## Modified biology: higher light affinity
#
# Reduce the light half-saturation constant from 33 to 15 W/m2. Seasonal incoming light
# and attenuation remain identical.

modified_plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                              light_half_saturation = 15.0,
                              maximum_grazing_rate = 0.8 / day)
modified_biogeochemistry = LOBSTER(grid; plankton = modified_plankton,
                                   surface_PAR, scale_negatives = true)
modified_model = NonhydrostaticModel(grid; closure, biogeochemistry = modified_biogeochemistry)
set!(modified_model; initial...)

modified_simulation = Simulation(modified_model; Δt = time_step, stop_time = 365days)
modified_file = joinpath(output_dir, "higher_light_affinity.jld2")
modified_simulation.output_writers[:profiles] = JLD2Writer(modified_model, modified_model.tracers;
    filename = modified_file, schedule = TimeInterval(1day), overwrite_files = true)
run!(modified_simulation)

modified_results = analyse_column_output(modified_file, modified_model)
write_diagnostics(joinpath(output_dir, "higher_light_affinity_diagnostics.csv"), modified_results)
write_export_profile(joinpath(output_dir, "higher_light_affinity_export_profile.csv"), modified_results)
println("Modified: final surface P = ", last(modified_results.surface_P), " mmol N/m3")
println("Modified: export at 100 m = ", last(modified_results.export_100.cumulative_g_C), " g C/m2")
println("Modified: export at 300 m = ", last(modified_results.export_300.cumulative_g_C), " g C/m2")
println("Modified: budget residual = ", last(modified_results.budget_residual), " mmol N/m2")

# ## Compare the ecosystem trajectories
#
# The left panels show both treatments, and the right panels show
# modified minus control. All curves use the same daily output times.
#md # WORKSHOP_PARAMETER_OUTPUT

response_figure = joinpath(output_dir, "light_affinity_response.png")
plot_parameter_response(control_results, modified_results, response_figure;
                        label = "Higher light affinity")
println("Saved $response_figure")

#md # WORKSHOP_PARAMETER_RESPONSE_FIGURE

# ## Compare particulate carbon export
#
# Compare daily and cumulative export at both 100 m and 300 m. The
# first days also reflect adjustment of initially prescribed particles.

export_figure = joinpath(output_dir, "light_affinity_export.png")
plot_parameter_export(control_results, modified_results, export_figure;
                      label = "Higher light affinity")
println("Saved $export_figure")

#md # WORKSHOP_PARAMETER_EXPORT_FIGURE

# ## Questions to explore
#
# Does higher light affinity change the timing or depth of the seasonal bloom? Compare
# surface phytoplankton and nitrate, then inspect export at 100 m and 300 m. Is growth
# limited more strongly by nutrients or light at different times of year?
#
# The nitrogen budget also tracks loss through the open bottom boundary.
#md # WORKSHOP_PARAMETER_BUDGET_CHECK
