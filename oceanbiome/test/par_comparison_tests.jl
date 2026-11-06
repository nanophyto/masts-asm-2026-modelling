# Compact offline fixtures exercise the full CSV -> metrics -> Markdown path.
function write_par_fixture(filename)
    open(filename, "w") do io
        println(io, "station,month,latitude,longitude,par_w_m2")
        for (station, lat, lon) in ((:BATS, 31.67, -64.17), (:NABE, 47.0, -20.0)), month in 1:12
            println(io, "$station,$month,$lat,$lon,$(30 + 60 * sinpi((month - 1) / 12)^2)")
        end
    end
    return filename
end

@testset "NASA POWER PAR comparison" begin
    mktempdir() do directory
        csv = write_par_fixture(joinpath(directory, "par.csv"))
        comparison = MASTSWorkshop.compare_par_climatology(csv)
        for station in (:BATS, :NABE)
            result = getproperty(comparison, station)
            @test length(result.observed_mean) == 12 && length(result.model_daily) == 366
            @test all(isfinite, result.model_monthly) && result.metrics.rmse >= 0
        end
        markdown = MASTSWorkshop.write_par_summary(joinpath(directory, "summary.md"), comparison)
        @test occursin("winter", read(markdown, String))
        @test_throws ArgumentError MASTSWorkshop.read_power_par(joinpath(directory, "absent.csv"))
        invalid = joinpath(directory, "invalid.csv")
        write(invalid, replace(read(csv, String), "BATS,1," => "BATS,13,"))
        @test_throws ArgumentError MASTSWorkshop.read_power_par(invalid)
    end
end
