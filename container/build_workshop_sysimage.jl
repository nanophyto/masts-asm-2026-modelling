using PackageCompiler

# MASTSWorkshop stays editable in the participant checkout. Compile only the
# scientific dependencies from the pinned Julia 1.10 project environment.
create_sysimage(["Oceananigans", "OceanBioME", "CairoMakie"];
    project = "/opt/workshop/source/oceanbiome",
    sysimage_path = "/opt/workshop/sysimages/masts-workshop.so",
    precompile_execution_file = joinpath(@__DIR__, "precompile_reference.jl"),
    cpu_target = "generic",
)
