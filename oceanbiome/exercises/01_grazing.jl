# MASTS ASM 2026: first OceanBioME column (Cycle 1.2).
# Run from the repository root:
# julia --project=oceanbiome oceanbiome/exercises/01_grazing.jl
# Add --quick for a 2-day smoke run.

using OceanBioME, Oceananigans
using Oceananigans.Units

include(joinpath(@__DIR__, "..", "src", "idealised_physics.jl"))
using .IdealisedPhysics: surface_PAR, vertical_diffusivity, initial_conditions

# Both experiments use exactly the same idealised physics and initial state.
grid = RectilinearGrid(size = 40, extent = 200meters,
                       topology = (Flat, Flat, Bounded))
initial = initial_conditions()
output_dir = joinpath(@__DIR__, "..", "..", "outputs", "oceanbiome")
mkpath(output_dir)
quick = "--quick" in ARGS

# Grazing is a genuine PhytoZoo parameter (units 1/s).
# Explore the control and a 50% reduction in zooplankton grazing.
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
                                                       schedule = TimeInterval(quick ? 1day : 5days),
                                                       overwrite_files = true)

    run!(simulation)

    # FieldTimeSeries is Oceananigans' standard interface to stored results.
    P = FieldTimeSeries(filename, "P")
    println("$(label): final surface phytoplankton = ",
            P[end][1, 1, grid.Nz], " mmol N / m^3")
    println("Saved $filename")
end
