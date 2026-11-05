# Lightweight physical-project checks; no reanalysis downloads.
# julia --threads=1 --project=physics physics/test_spinup_schedule.jl
using Test
using Oceananigans
using Oceananigans.Units: hours, days
include(joinpath(@__DIR__, "generate_column.jl"))

@testset "1D physics spin-up schedule" begin
    times = output_times(365, 365, 3)
    @test (first(times), last(times), length(times)) == (365days, 730days, 365 * 8 + 1)
    @test_throws ArgumentError output_times(-1, 365, 3)
    @test_throws ArgumentError output_times(0, 365, 5)

    # Regression: Oceananigans otherwise writes an unwanted iteration-zero
    # record even for a delayed SpecifiedTimes schedule. Attach the writer at
    # the spin-up boundary, record that boundary once, then resume the model.
    mktempdir() do directory
        grid = RectilinearGrid(size = 3, z = (-30, 0), topology = (Flat, Flat, Bounded))
        model = NonhydrostaticModel(grid; tracers = :T)
        simulation = Simulation(model; Δt = 1hours, stop_time = 2hours)
        run!(simulation)
        @test model.clock.time ≈ 2hours
        path = joinpath(directory, "delayed")
        writer = JLD2Writer(model, (; T = model.tracers.T);
                            filename = path,
                            schedule = SpecifiedTimes([2hours, 3hours, 4hours, 5hours]),
                            overwrite_files = true)
        simulation.output_writers[:late] = writer
        @test writer.schedule(model)
        Oceananigans.write_output!(writer, model)
        simulation.stop_time = 5hours
        run!(simulation)
        @test collect(FieldTimeSeries(path * ".jld2", "T").times) ≈
              [2hours, 3hours, 4hours, 5hours]
    end

end
