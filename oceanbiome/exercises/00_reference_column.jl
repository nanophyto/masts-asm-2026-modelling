# # Run a reference LOBSTER column
#
# We begin with one idealised ocean column. This is the reference simulation
# for the workshop: we construct a LOBSTER ecosystem, provide seasonal light
# and mixing, and examine phytoplankton, nitrate and particulate carbon export.
#
# From the repository root:
#
# ```bash
# julia --project=oceanbiome oceanbiome/exercises/00_reference_column.jl
# ```
#
# The default run is 365 days. Use `--quick` for a two-day check or
# `--quick --plot` to exercise the plotting code.

# ## Load OceanBioME and Oceananigans

using OceanBioME, Oceananigans
using Oceananigans.Units
using MASTSWorkshop: surface_PAR, vertical_diffusivity, initial_conditions,
                     diagnose_column, write_diagnostics,
                     plot_vertical_evolution, plot_reference_export,
                     plot_idealised_physics

# ## Define the water column
#
# This 400 m column uses 80 equally spaced vertical cells. The idealised
# physical forcing is supplied by the `MASTSWorkshop` package. The appendix
# explains the annual light and mixing cycles.

grid = RectilinearGrid(size = 80, extent = 400meters,
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
make_plots = !quick || "--plot" in ARGS
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

println("Reference: final surface phytoplankton = ", last(diagnostics.surface_P), " mmol N/m³")
println("Reference: cumulative export at 100 m = ", last(diagnostics.export_100.cumulative_g_C), " g C/m²")
println("Reference: cumulative export at 300 m = ", last(diagnostics.export_300.cumulative_g_C), " g C/m²")
println("Reference: nitrogen budget residual = ", last(diagnostics.budget_residual),
        " mmol N/m² (", 100 * last(diagnostics.budget_residual) / first(diagnostics.nitrogen_inventory),
        "% of sampled starting inventory)")
println("Saved $filename and diagnostics CSV")

# ## Inspect the reference output
#
# The annual simulation results are summarised below.
#md # WORKSHOP_REFERENCE_OUTPUT

# ## Plot vertical phytoplankton and nitrate
#
# These depth-time sections show how the initially uniform ecosystem responds
# to light, mixing and biological processes. Compare the surface and deep
# layers as the simulation develops.

if make_plots
    @eval using CairoMakie  # Activates MASTSWorkshop's plotting extension.
    vertical_figure = joinpath(output_dir, "reference_vertical_evolution.png")
    plot_vertical_evolution(diagnostics, vertical_figure)
    println("Saved $vertical_figure")
end

#md # WORKSHOP_REFERENCE_VERTICAL_FIGURE

# ## Examine carbon export
#
# LOBSTER's small and large particulate pools sink at different speeds. The
# fixed C:N conversion of 106:16 gives a carbon-equivalent export at 100 m
# and 300 m. These fluxes include the adjustment of initially prescribed
# particulate matter, particularly early in the simulation.

if make_plots
    export_figure = joinpath(output_dir, "reference_carbon_export.png")
    plot_reference_export(diagnostics, export_figure)
    println("Saved $export_figure")

    # The physics diagram is shown in the appendix.
    physics_figure = joinpath(output_dir, "reference_physics.png")
    plot_idealised_physics(physics_figure)
    println("Saved $physics_figure")
end

#md # WORKSHOP_REFERENCE_EXPORT_FIGURE

# ## What to look for
#
# How does the vertical phytoplankton structure evolve? Why might the
# instantaneous export at 100 m differ from that at 300 m? What do the
# cumulative fluxes tell us that an individual day's flux cannot?
#
# The [physical-forcing appendix](physical_forcing.md) explains the light
# and mixing environment. Continue with the [grazing experiment](01_grazing.md)
# to modify one biological parameter and compare otherwise identical columns.
#md # WORKSHOP_REFERENCE_BUDGET_CHECK
