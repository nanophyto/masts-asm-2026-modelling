# Small offline GOSML-like fixture; observations are synthetic and used only by tests.
function write_mld_fixture(filename)
    open(filename, "w") do io
        println(io, "station,lat_requested,lon_requested,lat_selected,lon_selected,distance_km,month,mld_mean_m,mld_p05_m,mld_p50_m,mld_p95_m,n_profiles,sum_mapping_weights")
        for (station, requested_lat, requested_lon, selected_lat, selected_lon, base) in
            (("BATS", 31.7, -64.2, 31.5, -64.5, 80.0),
             ("NABE", 47.0, -20.0, 47.5, -20.5, 220.0))
            for month in 1:12
                depth = base + 15cos(2pi * (month - 1) / 12)
                println(io, join((station, requested_lat, requested_lon, selected_lat,
                                  selected_lon, 30, month, depth, depth - 20,
                                  depth - 5, depth + 40, 100, 90.0), ','))
            end
        end
    end
    return filename
end

@testset "GOSML forcing comparison" begin
    mktempdir() do directory
        csv = write_mld_fixture(joinpath(directory, "fixture.csv"))
        observed = MASTSWorkshop.read_gosml_mld(csv)
        result = MASTSWorkshop.compare_mld_climatology(csv)
        for station in (:BATS, :NABE)
            data = getproperty(result, station)
            @test getproperty(observed, station).months == collect(1:12)
            @test length(data.model_daily) == length(data.month_x) == 366
            @test data.month_x[1] == 0.5 && data.month_x[end] == 12.5
            @test data.model_daily[1] ≈ -mixed_layer_depth(station, 0)
            @test data.model_monthly[1] ≈ sum(-mixed_layer_depth(station, (day + 0.5) * days)
                                              for day in 0:30) / 31
            @test isfinite(data.metrics.rmse_m) && data.metrics.rmse_m >= 0
            @test data.metrics.bias_m ≈ sum(data.model_monthly .- data.observed_mean) / 12
            @test all(data.observed_p05 .<= data.observed_p50) &&
                  all(data.observed_p50 .<= data.observed_p95)
        end
        summary = joinpath(directory, "summary.md")
        @test MASTSWorkshop.write_mld_summary(summary, result) == summary
        @test all(s -> occursin(s, read(summary, String)), ("BATS", "NABE", "RMSE", "winter"))

        rows = readlines(csv)
        for (label, corrupt) in
            (("missing December", rows[1:end-1]),
             ("duplicate month", [rows[1:end-1]; rows[13]]),
             ("unknown station", [rows[1]; replace(rows[2], "BATS" => "UNKNOWN"); rows[3:end]]),
             ("invalid percentile", [rows[1]; replace(rows[2], ",75.0," => ",-25.0,"); rows[3:end]]))
            filename = joinpath(directory, "invalid.csv")
            write(filename, join(corrupt, "\n") * "\n")
            @test_throws ArgumentError MASTSWorkshop.read_gosml_mld(filename)
        end
        @test_throws ArgumentError MASTSWorkshop.read_gosml_mld(joinpath(directory, "missing.csv"))
    end
end
