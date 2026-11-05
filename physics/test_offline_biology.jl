# Smoke-run the offline 1D diffusivity in an Oceananigans + LOBSTER model.
# Run from the oceanbiome environment (not the NumericalEarth environment):
# julia --threads=1 --project=oceanbiome physics/test_offline_biology.jl BATS outputs/physics/bats_catke_2d.jld2

using Oceananigans, OceanBioME, MASTSWorkshop
using Oceananigans.Units: days
using Oceananigans.Fields: interior

length(ARGS) == 2 || error("Usage: test_offline_biology.jl BATS|NABE <physics.jld2>")
station = Symbol(uppercase(ARGS[1]))
physics_path = ARGS[2]
config = MASTSWorkshop.column(station; deep = true, offline_physics = physics_path)
forcing = MASTSWorkshop.load_offline_physics(physics_path)
stop_time = min(2days, last(forcing.seconds))
stop_time > 0 || error("Offline physics must cover a positive duration")

biogeochemistry = LOBSTER(config.grid; surface_PAR = config.surface_PAR, scale_negatives = true)
model = NonhydrostaticModel(config.grid; closure = config.closure, biogeochemistry)
set!(model; config.initial...)
run!(Simulation(model; Δt = config.time_step, stop_time))
for tracer in values(model.tracers)
    all(isfinite, interior(tracer)) || error("Non-finite biological tracer")
end
println("Passed 1D offline biology smoke: $station, $(stop_time / days) days")
