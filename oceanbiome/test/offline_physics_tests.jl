using Oceananigans.Fields: Field, set!
include(joinpath(@__DIR__, "..", "..", "physics", "mld_temperature_diagnostic.jl"))
using .TemperatureMLD: temperature_mld

@testset "Offline 1D physics" begin
    # Small, deterministic depth/time fixture checks bilinear interpolation
    # without requiring NumericalEarth, reanalysis downloads or extra tests.
    forcing = MASTSWorkshop.OfflineColumnForcing(
        [-30.0, -20.0, -10.0, 0.0], [-25.0, -15.0, -5.0],
        [0.0, 10.0], [0.01 0.02; 0.02 0.04; 0.03 0.06; 0.04 0.08],
        [10.0 12.0; 12.0 14.0; 14.0 16.0])
    @test MASTSWorkshop.offline_diffusivity(forcing, -15, 5) ≈ 0.0375
    @test MASTSWorkshop.offline_temperature(forcing, -15, 5) ≈ 13.0
    κ = MASTSWorkshop.OfflineDiffusivity(forcing)
    @test κ isa Function
    @test κ(-15, 5) ≈ κ(0, 0, -15, 5)
    @test_throws ArgumentError MASTSWorkshop.offline_diffusivity(forcing, -5, 11)
    @test_throws ArgumentError MASTSWorkshop.OfflineColumnForcing(
        forcing.faces, forcing.centres, forcing.seconds, -forcing.diffusivity, forcing.temperature)

    # Published 10 m / 0.2 °C MLD diagnostic for seasonal validation.
    @test temperature_mld([-100.0, -20.0, -10.0, -5.0],
                          [8.0, 12.0, 15.0, 15.0]) ≈ 10 + 10 * (0.2 / 3)
    @test temperature_mld([-100.0, -20.0, -10.0, -5.0], fill(15.0, 4)) == 100.0
    mktempdir() do dir
        # Native Oceananigans JLD2Writer format, matching NumericalEarth output.
        grid = MASTSWorkshop.column(:BATS; deep = true).grid
        physics = NonhydrostaticModel(grid; tracers = (:T, :S))
        set!(physics; T = 12.0, S = 35.0)
        κc = Field{Center, Center, Face}(grid)
        set!(κc, z -> 1e-3 * (1 + z / 1200))
        path = joinpath(dir, "one_d_fixture")
        simulation = Simulation(physics; Δt = 1hour, stop_time = 2hours)
        simulation.output_writers[:physics] = JLD2Writer(
            physics, (; κc, T = physics.tracers.T);
            filename = path, schedule = TimeInterval(2hours), overwrite_files = true)
        run!(simulation)
        delayed = joinpath(dir, "spinup_window")
        writer = JLD2Writer(physics, (; κc, T = physics.tracers.T);
                            filename = delayed, schedule = SpecifiedTimes([2hours, 3hours, 4hours]),
                            overwrite_files = true)
        simulation.output_writers[:delayed] = writer
        @test writer.schedule(physics)
        Oceananigans.write_output!(writer, physics)
        simulation.stop_time = 4hours
        run!(simulation)

        file = path * ".jld2"
        @test isfile(file)
        loaded = MASTSWorkshop.load_offline_physics(file)
        @test length(loaded.faces) == grid.Nz + 1
        @test length(loaded.seconds) >= 2
        @test first(loaded.seconds) == 0.0
        @test MASTSWorkshop.offline_temperature(loaded, -5, 0) ≈ 12.0
        # Offline input starts at the post-spinup time even though the native
        # JLD2 timestamps retain the continuous physics clock.
        window = MASTSWorkshop.load_offline_physics(delayed * ".jld2")
        @test first(window.seconds) == 0.0
        @test last(window.seconds) ≈ 2hours
        @test MASTSWorkshop.offline_temperature(window, -5, 0) ≈ 12.0
        @test_throws ArgumentError MASTSWorkshop.offline_diffusivity(window, -5, 3hours)
        @test isapprox(MASTSWorkshop.offline_diffusivity(loaded, -600, 0), 5e-4; rtol = 1e-6)
        for station in (:BATS, :NABE), deep in (false, true)
            configured = MASTSWorkshop.column(station; deep, offline_physics = file)
            @test configured.grid.Nz == (deep ? 60 : 30)
            @test configured.closure.κ isa Function
            @test keys(configured) == (:grid, :time_step, :initial, :closure, :surface_PAR)
        end

        # Exercise the complete offline transport path, not just loading.
        configured = MASTSWorkshop.column(:BATS; deep = true, offline_physics = file)
        biology = LOBSTER(configured.grid;
                          surface_PAR = configured.surface_PAR, scale_negatives = true)
        model = NonhydrostaticModel(configured.grid;
                                    closure = configured.closure, biogeochemistry = biology)
        set!(model; configured.initial...)
        run!(Simulation(model; Δt = configured.time_step, stop_time = 4hours))
        @test all(field -> all(isfinite, interior(field)), values(model.tracers))
    end
end
