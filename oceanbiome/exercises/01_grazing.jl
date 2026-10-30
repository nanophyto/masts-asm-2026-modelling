# MASTS ASM 2026: LOBSTER grazing experiment (Cycles 1.2-1.3).
# From the repository root:
#   julia --project=oceanbiome oceanbiome/exercises/01_grazing.jl
# Add --quick for a 2-day smoke run; --quick --plot also produces the figure.

using OceanBioME, Oceananigans
using Oceananigans.Units

include(joinpath(@__DIR__, "..", "src", "idealised_physics.jl"))
include(joinpath(@__DIR__, "..", "src", "column_diagnostics.jl"))
using .IdealisedPhysics: surface_PAR, vertical_diffusivity, initial_conditions
using .ColumnDiagnostics: diagnose_column, write_diagnostics

# Both experiments use identical idealised physics and initial conditions.
# A 400 m column places the 100 m and 300 m export horizons on grid faces.
grid = RectilinearGrid(size = 80, extent = 400meters,
                       topology = (Flat, Flat, Bounded))
initial = initial_conditions()
output_dir = joinpath(@__DIR__, "..", "..", "outputs", "oceanbiome")
mkpath(output_dir)
quick = "--quick" in ARGS

results = Dict{String, Any}()

# Grazing is a genuine PhytoZoo parameter (units 1/s).
for (label, grazing_rate) in (("control", 0.8 / day),
                              ("reduced_grazing", 0.4 / day))

    plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                         maximum_grazing_rate = grazing_rate)

    biogeochemistry = LOBSTER(grid; plankton, surface_PAR, scale_negatives = true)

    model = NonhydrostaticModel(grid;
                                closure = ScalarDiffusivity(ν = vertical_diffusivity,
                                                            κ = vertical_diffusivity),
                                biogeochemistry)

    set!(model; initial...)

    simulation = Simulation(model; Δt = 3minutes, stop_time = quick ? 2days : 120days)
    filename = joinpath(output_dir, "$(label).jld2")
    simulation.output_writers[:profiles] = JLD2Writer(model, model.tracers;
                                                       filename,
                                                       schedule = TimeInterval(quick ? 6hours : 1day),
                                                       overwrite_files = true)
    run!(simulation)

    d = diagnose_column(filename, model)
    results[label] = d
    write_diagnostics(joinpath(output_dir, "$(label)_diagnostics.csv"), d)

    println("$(label): final surface phytoplankton = ", last(d.surface_P), " mmol N/m³")
    println("$(label): cumulative export at 100 m = ", last(d.export_100.cumulative_g_C), " g C/m²")
    println("$(label): cumulative export at 300 m = ", last(d.export_300.cumulative_g_C), " g C/m²")
    println("$(label): nitrogen budget residual = ", last(d.budget_residual),
            " mmol N/m² (", 100 * last(d.budget_residual) / first(d.nitrogen_inventory),
            "% of sampled starting inventory)")
    println("Saved $filename and diagnostics CSV")
end

if !quick || "--plot" in ARGS
    include(joinpath(@__DIR__, "..", "src", "plot_grazing.jl"))
    filename = joinpath(output_dir, "grazing_comparison.png")
    plot_grazing(results["control"], results["reduced_grazing"], filename)
    println("Saved $filename")
end
