# Internal two-day smoke workload for each participant's Julia 1.10 environment.
# Participant exercises continue to run the full 365-day seasonal cycle.
using OceanBioME, Oceananigans, CairoMakie
using Oceananigans.Units
using MASTSWorkshop

(; grid, time_step, initial, closure, surface_PAR) = MASTSWorkshop.column(:BATS)
plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                     maximum_grazing_rate = 0.8 / day)
biogeochemistry = LOBSTER(grid; plankton, surface_PAR, scale_negatives = true)
model = NonhydrostaticModel(grid; closure, biogeochemistry)
set!(model; initial...)

output = MASTSWorkshop.results_directory("warmup")
filename = joinpath(output, "warmup.jld2")
simulation = Simulation(model; Δt = time_step, stop_time = 2days)
simulation.output_writers[:profiles] = JLD2Writer(model, model.tracers;
                                                   filename,
                                                   schedule = TimeInterval(1day),
                                                   overwrite_files = true)
run!(simulation)
results = MASTSWorkshop.analyse_column_output(filename, model)
figure = joinpath(output, "warmup.png")
MASTSWorkshop.plot_vertical_evolution(results, figure; preview = false)
@assert isfile(figure) && filesize(figure) > 1000
println("Science warm-up ready: ", figure)
