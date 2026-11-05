# Fast synthetic tests; no NumericalEarth downloads or annual physics runs.
using Test
using MASTSWorkshop
using Oceananigans.Units: days
using TOML

include(joinpath(@__DIR__, "smooth_diffusivity_fit.jl"))
using .SmoothDiffusivityFit: fit_smooth_diffusivity, mixing_depth_from_profile

@testset "Smooth CATKE fit" begin
    times = collect(0:days:365days)
    faces = collect(-800.0:10.0:0.0)
    centres = (faces[1:end-1] .+ faces[2:end]) ./ 2
    expected_h = 70 .+ 20 .* cos.(2pi .* times ./ 365days)

    # Temperature is uniform: the fitted boundary must follow Kz, not T MLD.
    temperature = fill(18.0, length(centres), length(times))
    diffusivity = [(z >= -h ? 1e-2 : (z >= -300 ? 1e-7 : 1e-9))
                   for z in faces, h in expected_h]
    # Extreme surface and rare interior events, plus a weaker abyssal value,
    # must not bias medians from the intended upper/300m sampling regions.
    diffusivity[findfirst(==(-10.0), faces):end, :] .= 10.0
    diffusivity[findfirst(==(-40.0), faces), 1:20:end] .= 10.0
    diffusivity[findfirst(==(-250.0), faces), 1:10:end] .= 1e-2
    forcing = OfflineColumnForcing(faces, centres, times, diffusivity, temperature)
    fit = fit_smooth_diffusivity(forcing, :BATS)
    model = fit.model

    @test length(fit.daily_depths) == 365
    @test isapprox(smooth_mixed_layer_depth(model, 0), 90; atol = 10)
    @test isapprox(smooth_mixed_layer_depth(model, 182.5days), 50; atol = 10)
    @test isapprox(model.upper, 1e-2; rtol = 0.05)
    @test isapprox(model.deep, 1e-7; rtol = 1e-6)
    @test (fit.surface_exclusion_depth, fit.deep_fit_limit) == (20.0, 300.0)
    @test all(==(795.0), fit.raw_temperature_mld)
    @test model(-5, 0) == model.upper > model.deep == model(-150, 0)
    @test all(model(z, t) in (model.upper, model.deep)
              for z in -300:5:0, t in (0, 100days, 250days))
    h0 = smooth_mixed_layer_depth(model, 0)
    @test model(-h0, 0) == model.upper
    @test model(-h0 - 1e-6, 0) == model.deep
    @test model(-h0 + 1e-6, 0) == model.upper
    @test model(-5, 0) ≈ model(-5, 365days)
    @test_throws ArgumentError mixing_depth_from_profile(centres, ones(2))

    mktempdir() do dir
        file = joinpath(dir, "fit.toml")
        open(file, "w") do io
            TOML.print(io, Dict("fit_version" => 2, "station" => "BATS",
                                "mld_coefficients_m" => collect(model.coefficients),
                                "upper_diffusivity_m2_s" => model.upper,
                                "deep_diffusivity_m2_s" => model.deep,
                                "interface_type" => "binary_step",
                                "period_seconds" => model.period))
        end
        restored = load_smooth_physics(file; station = :BATS)
        @test restored(-5, 0) == model(-5, 0)
        @test restored(-150, 0) == model.deep
        @test MASTSWorkshop.column(:BATS; deep = true, smooth_physics = file).closure.κ isa Function
        @test_throws ArgumentError load_smooth_physics(file; station = :NABE)
        oldfit = joinpath(dir, "old_fit.toml")
        write(oldfit, replace(read(file, String), "fit_version = 2" => "fit_version = 1"))
        @test_throws ArgumentError load_smooth_physics(oldfit; station = :BATS)
        @test_throws ArgumentError MASTSWorkshop.column(:BATS; smooth_physics = file, offline_physics = forcing)
    end
end
