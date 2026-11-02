# Exercise the same constructor, time stepping, JLD2 diagnostics, and CairoMakie
# figures that a participant uses. PackageCompiler records executed methods.
# The output is temporary and the workload always runs the two-day example.
mktempdir() do output_dir
    ENV["MASTS_OUTPUT_DIR"] = output_dir
    empty!(ARGS)
    push!(ARGS, "--quick")
    include(joinpath(@__DIR__, "..", "oceanbiome", "exercises", "00_reference_column.jl"))
end
