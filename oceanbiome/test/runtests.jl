using Test, Pkg
using OceanBioME, Oceananigans

@testset "Workshop Julia environment" begin
    @test v"1.10" <= VERSION < v"2"
    @test isfile(joinpath(@__DIR__, "..", "Manifest.toml"))
    @test Base.pkgversion(OceanBioME) == v"0.20.1"
    @test Base.pkgversion(Oceananigans) == v"0.114.1"
    @test only(p.version for p in values(Pkg.dependencies()) if p.name == "CairoMakie") == v"0.15.16"
end

include(joinpath(@__DIR__, "..", "src", "idealised_physics.jl"))
using .IdealisedPhysics: surface_PAR, mixed_layer_depth, vertical_diffusivity, initial_conditions
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
