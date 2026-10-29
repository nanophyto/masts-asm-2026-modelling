using Test, Pkg
using OceanBioME, Oceananigans

@testset "Workshop Julia environment" begin
    @test v"1.10" <= VERSION < v"2"
    @test isfile(joinpath(@__DIR__, "..", "Manifest.toml"))
    @test Base.pkgversion(OceanBioME) == v"0.20.1"
    @test Base.pkgversion(Oceananigans) == v"0.114.1"
    @test only(p.version for p in values(Pkg.dependencies()) if p.name == "CairoMakie") == v"0.15.16"
end
