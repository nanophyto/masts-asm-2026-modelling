using Test, Pkg
using OceanBioME, Oceananigans
import MASTSWorkshop
using MASTSWorkshop: surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions,
                     face_index, sinking_courant, downward_nitrogen_flux, cumulative_trapezoid,
                     carbon_flux_mg_per_day, carbon_export_g_per_m2,
                     martin_flux, fit_martin_exponent,
                     living_particulate_fraction, dissolved_organic_fraction, upper_nitrogen_partition

@testset "Workshop Julia environment" begin
    @test v"1.10" <= VERSION < v"2"
    @test isfile(joinpath(@__DIR__, "..", "Manifest.toml"))
    @test Base.pkgversion(OceanBioME) == v"0.20.1"
    @test Base.pkgversion(Oceananigans) == v"0.114.1"
    @test only(p.version for p in values(Pkg.dependencies()) if p.name == "CairoMakie") == v"0.15.16"
    @test Meta.parseall(read(joinpath(@__DIR__, "..", "ext", "MASTSWorkshopMakieExt.jl"), String)) isa Expr
    @test hasmethod(MASTSWorkshop.analyse_column_output, Tuple{String, Any})
    for name in ("02_sinking.jl", "03_remineralisation.jl", "04_light_affinity.jl",
                 "05_nutrient_affinity.jl", "06_phytoplankton_mortality.jl",
                 "07_bats_nabe.jl")
        path = joinpath(@__DIR__, "..", "..", "workshop", "01_OceanBioME", name)
        @test Meta.parseall(read(path, String)) isa Expr
    end
end

include("plot_preview.jl")

using Oceananigans.Fields: interior
using Oceananigans.Grids: znodes
using Oceananigans.Units

@testset "Idealised physical forcing" begin
    @test surface_PAR(0, 0, 180days) > surface_PAR(0, 0, 0)
    @test surface_PAR(180days) == surface_PAR(0, 0, 180days)
    @test mixed_layer_depth(0) < mixed_layer_depth(180days)
    @test vertical_diffusivity(-5, 0) > vertical_diffusivity(-190, 0)
    @test vertical_diffusivity(-5, 0) == vertical_diffusivity(0, 0, -5, 0)
    for (station, par, mld, mixing) in
        ((:BATS, surface_PAR, mixed_layer_depth, vertical_diffusivity),
         (:NABE, MASTSWorkshop.nabe_surface_PAR, MASTSWorkshop.nabe_mixed_layer_depth,
                 MASTSWorkshop.nabe_vertical_diffusivity))
        @test surface_PAR(station, 180days) == par(180days)
        @test mixed_layer_depth(station, 180days) == mld(180days)
        @test vertical_diffusivity(station, -5, 180days) == mixing(-5, 180days)
        for time in (0, 45, 90, 135, 180, 225, 270, 315) .* days
            @test isfinite(surface_PAR(station, time)) && surface_PAR(station, time) >= 0
            @test -1200 < mixed_layer_depth(station, time) < 0
            @test isfinite(vertical_diffusivity(station, -5, time)) &&
                  vertical_diffusivity(station, -5, time) > 0
        end
    end
    @test_throws ArgumentError mixed_layer_depth(:UNKNOWN, 0)
    @test all(-last(znodes(MASTSWorkshop.column(station; deep).grid, Center())) ≈ 5
              for station in (:BATS, :NABE), deep in (false, true))
    @test all(vertical_diffusivity(station, -100, 0) >
              vertical_diffusivity(station, -100, 180days)
              for station in (:BATS, :NABE))
end

@testset "Workshop output directory" begin
    mktempdir() do temp
        withenv("MASTS_OUTPUT_DIR" => joinpath(temp, "reference")) do
            @test MASTSWorkshop.results_directory("reference_column") == joinpath(temp, "reference")
            @test isdir(joinpath(temp, "reference"))
        end
    end
end

@testset "LOBSTER column and grazing response" begin
    configuration = MASTSWorkshop.column(:BATS)
    grid, time_step, initial, closure, light = configuration
    @test time_step == 30minutes
    @test keys(configuration) == (:grid, :time_step, :initial, :closure, :surface_PAR)
    @test light === surface_PAR
    @test grid.Nz == 30 && grid.Lz == 300
    @test initial.NO₃(-5) ≈ MASTSWorkshop.deep_bats_initial_conditions().NO₃(-5)
    @test_throws ArgumentError MASTSWorkshop.column(:UNKNOWN)

    # Exercise the same native constructors and forcing as the teaching example.
    function column(grazing_rate)
        plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                             maximum_grazing_rate = grazing_rate)
        biogeochemistry = LOBSTER(grid; plankton, surface_PAR = light, scale_negatives = true)
        model = NonhydrostaticModel(grid; closure, biogeochemistry)
        set!(model; initial...)
        return model
    end

    control = column(0.8 / day)
    reduced = column(0.4 / day)

    @test control.biogeochemistry.underlying_biogeochemistry.plankton.maximum_grazing_rate ≈ 0.8 / day
    @test reduced.biogeochemistry.underlying_biogeochemistry.plankton.maximum_grazing_rate ≈ 0.4 / day
    @test all(interior(control.tracers.P) .== interior(reduced.tracers.P))

    for model in (control, reduced)
        @test 0 <= sinking_courant(model, time_step) < 1
        run!(Simulation(model; Δt = time_step, stop_time = 2days))
        for tracer in values(model.tracers)
            @test all(isfinite, interior(tracer))
            @test all(x -> x >= -1e-8, interior(tracer))
        end
    end

    @test any(interior(control.tracers.P) .!= interior(reduced.tracers.P))
end


@testset "Carbon export and nitrogen budget diagnostics" begin
    grid = RectilinearGrid(size = 50, extent = 500meters,
                           topology = (Flat, Flat, Bounded))
    @test (face_index(grid, 100), face_index(grid, 300), face_index(grid, 500)) ==
          (41, 21, 1)
    @test_throws ArgumentError face_index(grid, 105)
    @test_throws ArgumentError face_index(grid, 550)

    @test downward_nitrogen_flux(0.1, 0.2, -2 / day, -50 / day) ≈ 10.2 / day
    @test downward_nitrogen_flux(0.1, 0.2, 2 / day, 50 / day) == 0

    # A constant 1 mmol N/(m² day) corresponds to 106/16 mmol C per day.
    rate = 1 / day
    times = [0.0, 1day, 2days]
    expected_mg_C = 12.011 * 106 / 16
    @test carbon_flux_mg_per_day(rate) ≈ expected_mg_C
    @test carbon_export_g_per_m2(times, fill(rate, 3)) ≈
          [0, 1, 2] .* expected_mg_C ./ 1000
    @test cumulative_trapezoid(times, fill(rate, 3)) ≈ [0, 1, 2]
    @test_throws DimensionMismatch cumulative_trapezoid(times, [rate])
    @test_throws ArgumentError cumulative_trapezoid([0.0, 0.0], [rate, rate])

    # The fitted exponent recovers a known power law, anchored at 100 m.
    depths = [100, 200, 300, 500]
    @test fit_martin_exponent(depths, martin_flux.(depths, 10.0, 0.858)) ≈ 0.858
    @test isnothing(fit_martin_exponent(depths, [10.0, 5.0, 0.0, 1.0]))
end

@testset "Nitrogen partitions and living fraction" begin
    fields = (; NO₃ = fill(2.0, 4, 3), NH₄ = fill(1.0, 4, 3),
               P = fill(0.5, 4, 3), Z = fill(0.25, 4, 3),
               sPOM = fill(0.75, 4, 3), bPOM = fill(1.0, 4, 3),
               DOM = fill(0.25, 4, 3))
    # Integrate the top two 5 m cells: 10 m multiplied by each concentration.
    n = upper_nitrogen_partition(fields, 5.0, 3)
    @test n.inorganic == fill(30.0, 3)
    @test n.living == fill(7.5, 3)
    @test n.detrital == fill(17.5, 3)
    @test n.dissolved_organic == fill(2.5, 3)
    @test n.total == fill(57.5, 3)
    @test n.zoo_fraction ≈ fill(1 / 3, 3)

    fractions = living_particulate_fraction([1.0, 0.0], [1.0, 0.0],
                                            [1.0, 0.0], [1.0, 0.0])
    @test fractions[1] == 0.5
    @test isnan(fractions[2])  # Undefined when particulate nitrogen is absent.
    organic = dissolved_organic_fraction([1.0, 0.0], [1.0, 0.0],
                                          [0.0, 0.0], [0.0, 0.0], [0.0, 0.0])
    @test organic[1] == 0.5
    @test isnan(organic[2])
end

@testset "Biological parameter experiments" begin
    grid, time_step, initial, closure, light = MASTSWorkshop.column(:BATS)
    plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                         maximum_grazing_rate = 0.8 / day)
    function make_model(; detritus = DissolvedParticulate(grid), phyto = plankton)
        bgc = LOBSTER(grid; plankton = phyto, detritus, surface_PAR = light, scale_negatives = true)
        model = NonhydrostaticModel(grid; closure, biogeochemistry = bgc)
        set!(model; initial...)
        return model
    end

    low_light = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                         light_half_saturation = 15.0, maximum_grazing_rate = 0.8 / day)
    low_nutrients = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.35, ammonia = 0.001),
                             maximum_grazing_rate = 0.8 / day)
    mortality = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                         phytoplankton_mortality_rate = 1.16e-6,
                         maximum_grazing_rate = 0.8 / day)
    @test low_light.light_half_saturation == 15.0 < plankton.light_half_saturation
    @test low_nutrients.nutrient_half_saturations.nitrate == 0.35 < plankton.nutrient_half_saturations.nitrate
    @test mortality.phytoplankton_mortality_rate == 2 * plankton.phytoplankton_mortality_rate

    reference = make_model()
    slow = make_model(detritus = DissolvedParticulate(grid;
                           sinking_speeds = (3 / day, 100 / day)))
    fast = make_model(detritus = DissolvedParticulate(grid;
                           particulate_remineralisation_rate = (0.10 / day, 0.10 / day)))

    @test sinking_courant(slow, time_step) < sinking_courant(reference, time_step) < 1
    @test fast.biogeochemistry.underlying_biogeochemistry.detritus.particulate_remineralisation_rate == (0.10 / day, 0.10 / day)

    for model in (reference, slow, fast, make_model(phyto = low_light),
                  make_model(phyto = low_nutrients), make_model(phyto = mortality))
        run!(Simulation(model; Δt = time_step, stop_time = 2days))
        @test all(tracer -> all(isfinite, interior(tracer)), values(model.tracers))
    end
end

@testset "BATS/NABE shallow and stretched deep columns" begin
    faces = MASTSWorkshop.deep_grid_faces()
    @test length(faces) == 61
    @test first(faces) == -1200.0 && last(faces) == 0.0
    @test all(diff(faces) .> 0)
    @test extrema(diff(faces)) == (10.0, 40.0)
    @test all(depth -> -depth in faces, (100, 300, 1000))

    for (station, expected_light) in ((:BATS, surface_PAR),
                                      (:NABE, MASTSWorkshop.nabe_surface_PAR))
        shallow = MASTSWorkshop.column(station)
        deep = MASTSWorkshop.column(station; deep = true)
        @test shallow.grid.Nz == 30 && shallow.grid.Lz == 300
        @test deep.grid.Nz == 60 && deep.grid.Lz == 1200
        @test shallow.time_step == deep.time_step == 30minutes
        @test shallow.surface_PAR === deep.surface_PAR === expected_light
        @test (face_index(shallow.grid, 100), face_index(shallow.grid, 300)) == (21, 1)
        @test (face_index(deep.grid, 100), face_index(deep.grid, 300),
               face_index(deep.grid, 1000)) == (51, 31, 6)
        @test_throws ArgumentError face_index(deep.grid, 350)
        @test_throws ArgumentError face_index(deep.grid, 1250)
        @test_throws ArgumentError face_index(shallow.grid, 1000)

        # Oceananigans calls each initial profile with only z for Flat/Flat grids.
        for name in (:NO₃, :NH₄, :P, :Z, :DOM, :sPOM, :bPOM)
            @test all(z -> isfinite(shallow.initial[name](z)) &&
                           shallow.initial[name](z) >= 0, (-299.0, -150.0, -5.0))
            @test deep.initial[name](-5.0) ≈ shallow.initial[name](-5.0)
        end
        @test shallow.initial.NO₃(-280) > shallow.initial.NO₃(-5)
        @test shallow.initial.NO₃(0, 0, -5) == shallow.initial.NO₃(-5)
        @test deep.initial.P(-1000) < deep.initial.P(-5)
    end
    @test MASTSWorkshop.nabe_mixed_layer_depth(0) < -300
    @test MASTSWorkshop.nabe_mixed_layer_depth(180days) > -35
    @test MASTSWorkshop.nabe_mixed_layer_depth(0) < mixed_layer_depth(0)
    @test MASTSWorkshop.nabe_surface_PAR(180days) > MASTSWorkshop.nabe_surface_PAR(0)
    @test MASTSWorkshop.column(:NABE).initial.NO₃(-5) > MASTSWorkshop.column(:BATS).initial.NO₃(-5)

    # Nonuniform inventories use local cell thickness, not Lz/Nz.
    synthetic = (; (name => fill(2.0, 60, 3) for name in
                     (:NO₃, :NH₄, :P, :Z, :DOM, :sPOM, :bPOM))...)
    widths = diff(faces)
    partition = upper_nitrogen_partition(synthetic, widths, 51)
    @test partition.total == fill(1400.0, 3)  # 7 pools * 2 mmol/m3 * 100 m
    @test_throws DimensionMismatch upper_nitrogen_partition(synthetic, [10.0], 51)

    # Run every station/depth combination, including the shallow NABE winter.
    for station in (:BATS, :NABE), deep in (false, true)
        grid, dt, initial, closure, light = MASTSWorkshop.column(station; deep)
        bgc = LOBSTER(grid; surface_PAR = light, scale_negatives = true)
        model = NonhydrostaticModel(grid; closure, biogeochemistry = bgc)
        set!(model; initial...)
        @test sinking_courant(model, dt) < 1
        mktempdir() do dir
            filename = joinpath(dir, "$(station)_$(deep ? "deep" : "shallow").jld2")
            sim = Simulation(model; Δt = dt, stop_time = 2days)
            sim.output_writers[:profiles] = JLD2Writer(model, model.tracers;
                filename, schedule = TimeInterval(1day), overwrite_files = true)
            run!(sim)
            @test all(tracer -> all(isfinite, interior(tracer)), values(model.tracers))
            result = MASTSWorkshop.analyse_column_output(filename, model)
            @test length(result.z) == grid.Nz
            @test isnothing(result.export_1000) == !deep
            @test (100 in result.export_profile.depths) && (300 in result.export_profile.depths)
            @test !deep || (1000 in result.export_profile.depths)
            @test all(isfinite, result.nitrogen_inventory)
            @test isapprox(first(result.export_profile.depths), 50; atol = 1e-8)
            @test maximum(abs, result.budget_residual) / first(result.nitrogen_inventory) < 0.05
        end
    end
end
