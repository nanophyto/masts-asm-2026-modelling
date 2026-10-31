# # Run a reference LOBSTER column
#
# We begin with one idealised ocean column. This is the reference simulation
# for the workshop: we construct a LOBSTER ecosystem, provide seasonal light
# and mixing, and examine the evolving tracer structure and particulate
# carbon export.
#
# From the repository root:
#
# ```bash
# julia --project=oceanbiome oceanbiome/exercises/00_reference_column.jl
# ```
#
# The default run is 365 days. Use `--quick` for a two-day check.

# ## Load OceanBioME and Oceananigans

using OceanBioME, Oceananigans, CairoMakie
using Oceananigans.Units
using MASTSWorkshop: surface_PAR, vertical_diffusivity, initial_conditions,
                     diagnose_column, write_diagnostics, write_export_profile,
                     plot_vertical_evolution, plot_reference_export, plot_export_profile,
                     plot_idealised_physics

# ## Define the water column
#
# This 500 m column uses 100 equally spaced vertical cells. The idealised
# physical forcing is supplied by the `MASTSWorkshop` package. The appendix
# explains the annual light and mixing cycles.

grid = RectilinearGrid(size = 100, extent = 500meters,
                       topology = (Flat, Flat, Bounded))
initial = initial_conditions()

# ## Construct the biological model
#
# `PhytoZoo` defines phytoplankton and zooplankton processes. The seven-tracer
# `LOBSTER` model then combines them with nutrients and dissolved/particulate
# organic matter. The grazing rate is our reference value of 0.8 per day.

plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                     maximum_grazing_rate = 0.8 / day)

biogeochemistry = LOBSTER(grid; plankton, surface_PAR, scale_negatives = true)

# ## Couple biology to the water column
#
# `NonhydrostaticModel` is an Oceananigans constructor. The prescribed
# vertical diffusivity mixes the seven tracers through the water column.

model = NonhydrostaticModel(grid;
                            closure = ScalarDiffusivity(ν = vertical_diffusivity,
                                                        κ = vertical_diffusivity),
                            biogeochemistry)
set!(model; initial...)

# ## Run and save the simulation
#
# The output includes daily tracer profiles and diagnostics of sinking
# organic-carbon export at 100 m and 300 m. Both depths coincide with grid
# faces. The two-day option saves a profile every six hours.

quick = "--quick" in ARGS
output_dir = get(ENV, "MASTS_OUTPUT_DIR",
                 joinpath(@__DIR__, "..", "..", "outputs", "oceanbiome", "reference_column"))
mkpath(output_dir)

simulation = Simulation(model; Δt = 3minutes, stop_time = quick ? 2days : 365days)
filename = joinpath(output_dir, "reference_column.jld2")
simulation.output_writers[:profiles] = JLD2Writer(model, model.tracers;
                                                   filename,
                                                   schedule = TimeInterval(quick ? 6hours : 1day),
                                                   overwrite_files = true)
run!(simulation)

diagnostics = diagnose_column(filename, model)
write_diagnostics(joinpath(output_dir, "reference_diagnostics.csv"), diagnostics)
write_export_profile(joinpath(output_dir, "reference_export_profile.csv"), diagnostics)

println("Reference: final surface phytoplankton = ", last(diagnostics.surface_P), " mmol N/m³")
println("Reference: cumulative export at 100 m = ", last(diagnostics.export_100.cumulative_g_C), " g C/m²")
println("Reference: cumulative export at 300 m = ", last(diagnostics.export_300.cumulative_g_C), " g C/m²")
println("Reference: fitted Martin b = ", diagnostics.export_profile.martin_b)
println("Reference: nitrogen budget residual = ", last(diagnostics.budget_residual),
        " mmol N/m² (", 100 * last(diagnostics.budget_residual) / first(diagnostics.nitrogen_inventory),
        "% of sampled starting inventory)")
println("Saved $filename and diagnostics CSV")

# ## Inspect the reference output
#
# The annual simulation results are summarised below.
#md # WORKSHOP_REFERENCE_OUTPUT

# ## Plot the vertical tracer evolution
#
# These depth-time sections show the major LOBSTER tracers in the annual
# reference simulation: zooplankton, phytoplankton, nitrate, small POM,
# large POM and DOM. Together they show how the initially uniform ecosystem
# responds to light, mixing and biological processes.

vertical_figure = joinpath(output_dir, "reference_vertical_evolution.png")
plot_vertical_evolution(diagnostics, vertical_figure)
println("Saved $vertical_figure")

#md # WORKSHOP_REFERENCE_VERTICAL_FIGURE

# ## Examine carbon export
#
# LOBSTER's small and large particulate pools sink at different speeds. The
# fixed C:N conversion of 106:16 gives a carbon-equivalent export at 100 m
# and 300 m. These fluxes include the adjustment of initially prescribed
# particulate matter, particularly early in the simulation.

export_figure = joinpath(output_dir, "reference_carbon_export.png")
plot_reference_export(diagnostics, export_figure)
println("Saved $export_figure")

#md # WORKSHOP_REFERENCE_EXPORT_FIGURE

# ## Compare export attenuation with the Martin curve
#
# Diagnose particle flux every 50 m down to 500 m. The first panel compares
# LOBSTER's final 90-day mean flux against the [Martin et al. (1987)](https://doi.org/10.1016/0198-0149(87)90086-0) empirical
# curve, normalized to the simulated flux at 100 m. It also fits a power-law
# exponent to the model values below 100 m. A negative b indicates that
# the flux increases with depth over the fitted range. The second panel shows export
# integrated over the full 365-day run, which includes the initial POM
# adjustment. The power-law comparison summarizes attenuation; LOBSTER's
# biological transformations and particle sinking generate the model profile.

profile_figure = joinpath(output_dir, "reference_martin_curve.png")
plot_export_profile(diagnostics, profile_figure)
println("Saved $profile_figure")

#md # WORKSHOP_REFERENCE_MARTIN_FIGURE

# The physics diagram is shown in the appendix.
physics_figure = joinpath(output_dir, "reference_physics.png")
plot_idealised_physics(physics_figure)
println("Saved $physics_figure")

# ## What to look for
#
# How does the vertical tracer structure evolve? Why might the
# instantaneous export at 100 m differ from that at 300 m? How does
# the flux attenuation compare with the empirical Martin curve, and what
# might explain differences? What do the cumulative fluxes tell us that an
# individual day's flux cannot?
#
# The [physical-forcing appendix](physical_forcing.md) explains the light
# and mixing environment. Continue with the [grazing experiment](01_grazing.md)
# to modify one biological parameter and compare otherwise identical columns.
#md # WORKSHOP_REFERENCE_BUDGET_CHECK
