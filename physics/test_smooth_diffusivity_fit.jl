# Fast synthetic tests; no NumericalEarth downloads or annual physics runs.
using Test
using MASTSWorkshop
using Oceananigans.Units: days
using TOML

include(joinpath(@__DIR__, "smooth_diffusivity_fit.jl"))
using .SmoothDiffusivityFit: fit_smooth_diffusivity, mixing_depth_from_profile,
                             fit_mld_harmonics, rolling_mixing_depth_quantile

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

    @test (length(model.coefficients), length(fit.previous_model.coefficients)) == (7, 5)
    @test (model.upper, model.deep) == (fit.mean_model.upper, fit.mean_model.deep) ==
          (fit.previous_model.upper, fit.previous_model.deep)
    @test fit.mean_rmse <= fit.previous_rmse + 1e-8
    @test length(fit.daily_depths) == length(fit.envelope_depths) == 365
    @test (fit.envelope_probability, fit.envelope_window_days) == (0.75, 21)
    @test all(isfinite, (fit.mean_rmse, fit.envelope_rmse, fit.envelope_daily_rmse))
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

    # A known third-harmonic seasonal signal is captured by seven coefficients;
    # the five-coefficient reference necessarily misses the third harmonic.
    daily_t = (collect(0:364) .+ 0.5) .* days
    θ = 2pi .* daily_t ./ (365days)
    known_depth = 80 .+ 20 .* cos.(θ) .+ 10 .* sin.(2 .* θ) .+ 15 .* cos.(3 .* θ)
    c2 = fit_mld_harmonics(daily_t, known_depth; harmonics = 2)
    c3 = fit_mld_harmonics(daily_t, known_depth; harmonics = 3)
    old = SmoothDiffusivity(:BATS, c2, 1e-2, 1e-7)
    new = SmoothDiffusivity(:BATS, c3, 1e-2, 1e-7)
    error2 = maximum(abs, [smooth_mixed_layer_depth(old, t) - h for (t, h) in zip(daily_t, known_depth)])
    error3 = maximum(abs, [smooth_mixed_layer_depth(new, t) - h for (t, h) in zip(daily_t, known_depth)])
    @test error2 > 10
    @test error3 < 1e-10
    @test_throws ArgumentError fit_mld_harmonics(daily_t, known_depth; harmonics = 4)

    # The centred window wraps across New Year, retains a sustained winter
    # deepening and ignores an isolated extreme day.
    depth_signal = fill(40.0, 365)
    depth_signal[vcat(355:365, 1:11)] .= 120.0
    depth_signal[150] = 350.0
    envelope = rolling_mixing_depth_quantile(depth_signal)
    @test (envelope[1], envelope[365], envelope[150]) == (120.0, 120.0, 40.0)
    @test envelope[200] == 40.0
    @test_throws ArgumentError rolling_mixing_depth_quantile(depth_signal; probability = 1.0)
    @test_throws ArgumentError rolling_mixing_depth_quantile(depth_signal; window_days = 20)
    @test_throws ArgumentError rolling_mixing_depth_quantile(depth_signal; window_days = 367)

    mktempdir() do dir
        file = joinpath(dir, "fit.toml")
        open(file, "w") do io
            TOML.print(io, Dict("fit_version" => 4, "station" => "BATS",
                                "harmonic_count" => 3,
                                "mld_coefficients_m" => collect(model.coefficients),
                                "envelope_quantile" => fit.envelope_probability,
                                "envelope_window_days" => fit.envelope_window_days,
                                "upper_diffusivity_m2_s" => model.upper,
                                "deep_diffusivity_m2_s" => model.deep,
                                "interface_type" => "binary_step",
                                "period_seconds" => model.period))
        end
        restored = load_smooth_physics(file; station = :BATS)
        @test restored(-5, 0) == model(-5, 0)
        @test restored(-150, 0) == model.deep
        @test restored.coefficients == model.coefficients
        @test MASTSWorkshop.column(:BATS; deep = true, smooth_physics = file).closure.κ isa Function
        @test_throws ArgumentError load_smooth_physics(file; station = :NABE)
        for (version, coefficients) in ((2, fit.previous_model.coefficients),
                                        (3, fit.mean_model.coefficients))
            oldfit = joinpath(dir, "fit_v$version.toml")
            previous_config = TOML.parsefile(file)
            previous_config["fit_version"] = version
            previous_config["harmonic_count"] = (length(coefficients) - 1) ÷ 2
            previous_config["mld_coefficients_m"] = collect(coefficients)
            open(oldfit, "w") do io
                TOML.print(io, previous_config)
            end
            restored_old = load_smooth_physics(oldfit; station = :BATS)
            @test restored_old.coefficients == coefficients
            @test restored_old(-5, 0) == model.upper
        end
        bad = joinpath(dir, "bad_fit.toml")
        bad_config = TOML.parsefile(file)
        bad_config["fit_version"] = 1
        open(bad, "w") do io
            TOML.print(io, bad_config)
        end
        @test_throws ArgumentError load_smooth_physics(bad; station = :BATS)
        @test_throws ArgumentError MASTSWorkshop.column(:BATS; smooth_physics = file, offline_physics = forcing)
    end
end
