using Test
using OceanBioME, Oceananigans, CairoMakie

@testset "Workshop Julia environment" begin
    @test VERSION.major == 1 && VERSION.minor == 13
    @test isfile(joinpath(@__DIR__, "..", "Manifest.toml"))
    @test Base.pkgversion(OceanBioME) == v"0.20.1"
    @test Base.pkgversion(Oceananigans) == v"0.114.1"
    @test Base.pkgversion(CairoMakie) == v"0.15.16"
end
