using CairoMakie

@testset "Scientific plot previews" begin
    @test !isnothing(Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt))
    day = [0.0, 1.0, 2.0]
    z = [-20.0, -10.0, 0.0]
    values = fill(0.1, 3, 3)
    upper_100m = (; inorganic = fill(10.0, 3), living = fill(5.0, 3),
                    detrital = fill(3.0, 3), dissolved_organic = fill(2.0, 3),
                    phytoplankton = fill(3.0, 3), zooplankton = fill(2.0, 3),
                    total = fill(20.0, 3), zoo_fraction = fill(0.4, 3))
    export_100 = (; daily_mg_C = [1.0, 1.5, 1.2], cumulative_g_C = [0.0, 0.1, 0.2])
    export_300 = (; daily_mg_C = [0.7, 0.8, 0.6], cumulative_g_C = [0.0, 0.06, 0.1])
    export_profile = (; depths = [100, 200, 300, 500],
                       mean_daily_mg_C = [1.5, 1.0, 0.8, 0.5],
                       integrated_g_C = [0.2, 0.15, 0.1, 0.06],
                       window_days = 2.0, martin_b = 0.85)
    control = (; day, z, vertical_Z = values, vertical_P = values, vertical_NO₃ = values,
               vertical_sPOM = values, vertical_bPOM = values, vertical_DOM = values,
               surface_P = [0.1, 0.2, 0.3], surface_NO₃ = [1.0, 0.9, 0.8],
               upper_100m, living_fraction = fill(0.5, 3, 3),
               dissolved_fraction = fill(0.25, 3, 3),
               export_100, export_300, export_profile)
    reduced = merge(control, (; surface_P = [0.2, 0.3, 0.4],
                              surface_NO₃ = [0.9, 0.8, 0.7]))

    deep_profile = (; depths = [100, 200, 300, 500, 600, 800, 1000, 1200],
                     mean_daily_mg_C = [1.5, 1.2, 1.0, 0.8, 0.7, 0.6, 0.5, 0.4],
                     integrated_g_C = [0.2, 0.18, 0.16, 0.14, 0.12, 0.1, 0.08, 0.06],
                     window_days = 2.0, martin_b = 0.7)
    export_1000 = (; daily_mg_C = [0.4, 0.5, 0.6],
                     cumulative_g_C = [0.0, 0.02, 0.04])
    deep_bats = merge(control, (; export_1000, export_profile = deep_profile))
    deep_nabe = merge(reduced, (; export_1000, export_profile = deep_profile))

    # Same sequence as the workshop exercises.
    plots = ((MASTSWorkshop.plot_vertical_evolution, (control,), "reference_vertical_evolution.png"),
             (MASTSWorkshop.plot_nitrogen_partition, (control,), "reference_nitrogen_partition.png"),
             (MASTSWorkshop.plot_living_fraction, (control,), "reference_living_fraction.png"),
             (MASTSWorkshop.plot_reference_export, (control,), "reference_carbon_export.png"),
             (MASTSWorkshop.plot_export_profile, (control,), "reference_martin_curve.png"),
             (MASTSWorkshop.plot_idealised_physics, (), "reference_physics.png"),
             (MASTSWorkshop.plot_grazing_response, (control, reduced), "grazing_response.png"),
             (MASTSWorkshop.plot_plankton_balance, (control, reduced), "grazing_plankton_balance.png"),
             (MASTSWorkshop.plot_carbon_export, (control, reduced), "carbon_export.png"),
             (MASTSWorkshop.plot_parameter_response, (control, reduced), "parameter_response.png"),
             (MASTSWorkshop.plot_parameter_export, (control, reduced), "parameter_export.png"),
             (MASTSWorkshop.plot_station_map, (), "station_map.png"),
             (MASTSWorkshop.plot_station_forcing, (), "station_forcing.png"),
             (MASTSWorkshop.plot_station_diffusivity, (), "station_diffusivity.png"),
             (MASTSWorkshop.plot_station_comparison, (deep_bats, deep_nabe), "station_comparison.png"))

    mktempdir() do dir
        for (plot, args, name) in plots
            filename = joinpath(dir, name)
            for preview in (false, true)
                @test plot(args..., filename; preview) == filename
                @test isfile(filename) && filesize(filename) > 1000
            end
        end
        par_csv = write_par_fixture(joinpath(dir, "par_fixture.csv"))
        par_comparison = MASTSWorkshop.compare_par_climatology(par_csv)
        par_png = joinpath(dir, "nasa_power_par_comparison.png")
        @test MASTSWorkshop.plot_par_comparison(par_comparison, par_png; preview = false) == par_png
        @test isfile(par_png) && filesize(par_png) > 1000
        csv = write_mld_fixture(joinpath(dir, "gosml_fixture.csv"))
        comparison = MASTSWorkshop.compare_mld_climatology(csv)
        filename = joinpath(dir, "gosml_mld_comparison.png")
        for preview in (false, true)
            @test MASTSWorkshop.plot_mld_comparison(comparison, filename; preview) == filename
            @test isfile(filename) && filesize(filename) > 1000
        end
    end
end
