# Stable PackageCompiler workload. Exercise and MASTSWorkshop source changes
# are copied after the scientific sysimage, so they do not invalidate it.
using OceanBioME, Oceananigans, CairoMakie
using Oceananigans.Units: meters, minutes, days, day
using Oceananigans.TurbulenceClosures: ScalarDiffusivity, VerticallyImplicitTimeDiscretization

const annual_cycle = 365days
reference_light(x, y, t) = 2 + 60 * (1 - cos(2pi * t / annual_cycle))
seasonal_depth(t) = -(15 + 125 * (1 + cos(2pi * t / annual_cycle)) / 2)
reference_mixing(x, y, z, t) = 1e-4 + 5e-3 * (1 + tanh((z - seasonal_depth(t)) / 10)) / 2

grid = RectilinearGrid(size = 50, extent = 500meters, topology = (Flat, Flat, Bounded))
closure = ScalarDiffusivity(VerticallyImplicitTimeDiscretization(); ν = reference_mixing, κ = reference_mixing)
plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                     maximum_grazing_rate = 0.8 / day)
biogeochemistry = LOBSTER(grid; plankton, surface_PAR = reference_light, scale_negatives = true)
model = NonhydrostaticModel(grid; closure, biogeochemistry)
set!(model; P = 0.03, Z = 0.03, NO₃ = 4.0, NH₄ = 0.05,
             DOM = 0.02, sPOM = 0.01, bPOM = 0.005)

mktempdir() do output_dir
    simulation = Simulation(model; Δt = 30minutes, stop_time = 2days)
    simulation.output_writers[:profiles] = JLD2Writer(model, model.tracers;
        filename = joinpath(output_dir, "reference.jld2"),
        schedule = TimeInterval(1day), overwrite_files = true)
    run!(simulation)

    fig = Figure(size = (360, 240))
    axis = Axis(fig[1, 1])
    lines!(axis, 1:5, [1, 2, 3, 2, 1])
    save(joinpath(output_dir, "reference.png"), fig)
end
