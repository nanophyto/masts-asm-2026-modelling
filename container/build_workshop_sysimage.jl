using PackageCompiler

# MASTSWorkshop itself stays editable in the participant checkout. The baked
# dependencies are fixed by the workshop's Project/Manifest and its 1.10 Julia.
create_sysimage(["Oceananigans", "OceanBioME", "CairoMakie"];
    project = "/opt/workshop/source/oceanbiome",
    sysimage_path = "/opt/workshop/sysimages/masts-workshop.so",
    precompile_execution_file = joinpath(@__DIR__, "precompile_reference.jl"),
    cpu_target = "generic",
)
