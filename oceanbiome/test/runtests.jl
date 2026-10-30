using Test, Pkg
using OceanBioME, Oceananigans
using MASTSWorkshop: surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions,
                     face_index, downward_nitrogen_flux, cumulative_trapezoid,
                     carbon_flux_mg_per_day, carbon_export_g_per_m2

@testset "Workshop Julia environment" begin
    @test v"1.10" <= VERSION < v"2"
    @test isfile(joinpath(@__DIR__, "..", "Manifest.toml"))
    @test Base.pkgversion(OceanBioME) == v"0.20.1"
    @test Base.pkgversion(Oceananigans) == v"0.114.1"
    @test only(p.version for p in values(Pkg.dependencies()) if p.name == "CairoMakie") == v"0.15.16"
    @test Meta.parseall(read(joinpath(@__DIR__, "..", "ext", "MASTSWorkshopMakieExt.jl"), String)) isa Expr
end

using Oceananigans.Fields: interior
using Oceananigans.Units

@testset "Idealised physical forcing" begin
    @test surface_PAR(0, 0, 180days) > surface_PAR(0, 0, 0)
    @test surface_PAR(180days) == surface_PAR(0, 0, 180days)
    @test mixed_layer_depth(0) < mixed_layer_depth(180days)
    @test vertical_diffusivity(-5, 0) > vertical_diffusivity(-190, 0)
    @test vertical_diffusivity(-5, 0) == vertical_diffusivity(0, 0, -5, 0)
end

@testset "LOBSTER column and grazing response" begin
    grid = RectilinearGrid(size = 20, extent = 200meters,
                           topology = (Flat, Flat, Bounded))
    initial = initial_conditions()

    # Exercise the same native constructors and forcing as the teaching example.
    function column(grazing_rate)
        plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                             maximum_grazing_rate = grazing_rate)
        biogeochemistry = LOBSTER(grid; plankton, surface_PAR, scale_negatives = true)
        model = NonhydrostaticModel(grid;
                                    closure = ScalarDiffusivity(ν = vertical_diffusivity,
                                                                κ = vertical_diffusivity),
                                    biogeochemistry)
        set!(model; initial...)
        return model
    end

    control = column(0.8 / day)
    reduced = column(0.4 / day)

    @test control.biogeochemistry.underlying_biogeochemistry.plankton.maximum_grazing_rate ≈ 0.8 / day
    @test reduced.biogeochemistry.underlying_biogeochemistry.plankton.maximum_grazing_rate ≈ 0.4 / day
    @test all(interior(control.tracers.P) .== interior(reduced.tracers.P))

    for model in (control, reduced)
        run!(Simulation(model; Δt = 3minutes, stop_time = 2days))
        for tracer in values(model.tracers)
            @test all(isfinite, interior(tracer))
            @test all(x -> x >= -1e-8, interior(tracer))
        end
    end

    @test any(interior(control.tracers.P) .!= interior(reduced.tracers.P))
end


@testset "Carbon export and nitrogen budget diagnostics" begin
    grid = RectilinearGrid(size = 40, extent = 400meters,
                           topology = (Flat, Flat, Bounded))
    @test (face_index(grid, 100), face_index(grid, 300), face_index(grid, 400)) == (31, 11, 1)
    @test_throws ArgumentError face_index(grid, 105)
    @test_throws ArgumentError face_index(grid, 450)

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
end
