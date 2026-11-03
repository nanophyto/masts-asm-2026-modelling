# Exercise the same constructor, time stepping, JLD2 diagnostics, and CairoMakie
# figures that a participant uses. PackageCompiler records executed methods.
# The output is temporary and the workload runs the annual reference example.
mktempdir() do output_dir
    ENV["MASTS_OUTPUT_DIR"] = output_dir
    include(joinpath(@__DIR__, "..", "workshop", "01_OceanBioME", "00_reference_column.jl"))
end
