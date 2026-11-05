using Oceananigans.Fields: Field, set!

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

    mktempdir() do dir
        # Native Oceananigans JLD2Writer format, matching NumericalEarth output.
        grid = MASTSWorkshop.column(:BATS; deep = true).grid
        physics = NonhydrostaticModel(grid; tracers = (:T, :S))
        set!(physics; T = 12.0, S = 35.0)
        κc = Field{Center, Center, Face}(grid)
        set!(κc, z -> 1e-3 * (1 + z / 1200))
        path = joinpath(dir, "one_d_fixture")
        simulation = Simulation(physics; Δt = 1hour, stop_time = 4hours)
        simulation.output_writers[:physics] = JLD2Writer(
            physics, (; κc, T = physics.tracers.T);
            filename = path, schedule = TimeInterval(2hours), overwrite_files = true)
        run!(simulation)

        file = path * ".jld2"
        @test isfile(file)
        loaded = MASTSWorkshop.load_offline_physics(file)
        @test length(loaded.faces) == grid.Nz + 1
        @test length(loaded.seconds) >= 2
        @test MASTSWorkshop.offline_temperature(loaded, -5, 0) ≈ 12.0
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
