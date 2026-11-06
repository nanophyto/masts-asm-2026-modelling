using Pkg
Pkg.instantiate()
using Documenter, Literate

root = normpath(joinpath(@__DIR__, ".."))
scientific_project = joinpath(root, "oceanbiome")
exercise_dir = joinpath(root, "workshop", "01_OceanBioME")
assets_dir = joinpath(@__DIR__, "src", "assets")
generated_dir = joinpath(@__DIR__, "src", "generated")
output_base = joinpath(root, "outputs", "oceanbiome", "reference_docs")

# The source tree contains inputs and code. Figures, reports, tutorial pages and
# experiment results are regenerated for every build (including local builds).
for directory in (assets_dir, generated_dir, output_base)
    rm(directory; force = true, recursive = true)
    mkpath(directory)
end

function check_png(filename)
    isfile(filename) && filesize(filename) > 8 || error("Missing or empty figure: $filename")
    open(filename) do io
        read(io, 8) == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] ||
            error("Invalid PNG header in $filename")
    end
end

# Render the location map from the retained numerical CAFE dataset. The plot
# script needs only Python, numpy, scipy and matplotlib; HDF4 downloads are not
# part of the published documentation build.
map_input = joinpath(root, "data", "maps", "north_atlantic_cafe_npp_2023.nc")
map_output = joinpath(root, "data", "maps", "north_atlantic_cafe_npp_2023.png")
isfile(map_input) || error("Missing numerical NPP input: $map_input")
python = get(ENV, "MASTS_MAP_PYTHON", get(ENV, "PYTHON", "python3"))
run(`$python $(joinpath(root, "scripts", "plot_satellite_npp_map.py")) --input $map_input --output $map_output`)
check_png(map_output)

# The workshop examples use a separate, pinned Julia environment.
instantiate_cmd = `$(Base.julia_cmd()) --threads=1 --startup-file=no --project=$scientific_project -e $("using Pkg; Pkg.instantiate()")`
run(addenv(instantiate_cmd, "JULIA_PKG_PRECOMPILE_AUTO" => "0"))
plot_check = "using MASTSWorkshop, CairoMakie; " *
             "isnothing(Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt)) && " *
             "error(\"Workshop plotting extension did not load\")"
run(`$(Base.julia_cmd()) --threads=1 --startup-file=no --project=$scientific_project -e $plot_check`)

function run_exercise(name, directory)
    command = `$(Base.julia_cmd()) --threads=1 --startup-file=no --project=$scientific_project $(joinpath(exercise_dir, name))`
    output = cd(root) do
        read(addenv(command, "MASTS_OUTPUT_DIR" => directory), String)
    end
    return strip(replace(output, root * "/" => ""))
end

function budget_summary(label, filename)
    lines = readlines(filename)
    length(lines) >= 3 || error("Expected multiple diagnostic samples in $filename")
    columns = split(first(lines), ',')
    rows = [parse.(Float64, split(line, ',')) for line in lines[2:end]]
    all(row -> length(row) == length(columns) && all(isfinite, row), rows) ||
        error("Invalid diagnostic values in $filename")

    inventory = getindex.(rows, only(findall(==("nitrogen_inventory_mmol_N_m2"), columns)))
    residual = getindex.(rows, only(findall(==("nitrogen_budget_residual_mmol_N_m2"), columns)))
    first(inventory) > 0 || error("Non-positive nitrogen inventory in $filename")
    max_percent = 100 * maximum(abs, residual) / first(inventory)
    final_percent = 100 * last(residual) / first(inventory)
    max_percent <= 5 || error("$label nitrogen-budget residual exceeds 5%: $(round(max_percent; digits=2))%")
    return "| $label | $(round(final_percent; digits=2))% | $(round(max_percent; digits=2))% |"
end

reference_dir = joinpath(output_base, "reference_column")
grazing_dir = joinpath(output_base, "grazing")
station_dir = joinpath(output_base, "bats_nabe")
parameter_exercises = (("02_sinking.jl", "sinking", "slow_sinking"),
                       ("03_remineralisation.jl", "remineralisation", "fast_remineralisation"),
                       ("04_light_affinity.jl", "light_affinity", "higher_light_affinity"),
                       ("05_nutrient_affinity.jl", "nutrient_affinity", "higher_nutrient_affinity"),
                       ("06_phytoplankton_mortality.jl", "phytoplankton_mortality", "higher_mortality"))

reference_output = run_exercise("00_reference_column.jl", reference_dir)
grazing_output = run_exercise("01_grazing.jl", grazing_dir)
parameter_outputs = Dict(experiment => run_exercise(script, joinpath(output_base, experiment))
                         for (script, experiment, _) in parameter_exercises)
run_exercise("07_bats_nabe.jl", station_dir)

figures = (
    (reference_dir, "reference_vertical_evolution.png"),
    (reference_dir, "reference_nitrogen_partition.png"),
    (reference_dir, "reference_living_fraction.png"),
    (reference_dir, "reference_carbon_export.png"),
    (reference_dir, "reference_martin_curve.png"),
    (grazing_dir, "grazing_response.png"),
    (grazing_dir, "grazing_plankton_balance.png"),
    (grazing_dir, "carbon_export.png"),
)
parameter_figures = Tuple((joinpath(output_base, experiment), "$(experiment)_$(kind).png")
                          for (_, experiment, _) in parameter_exercises for kind in ("response", "export"))
station_figures = ((station_dir, "station_map.png"),
                   (station_dir, "station_forcing.png"),
                   (station_dir, "station_diffusivity.png"))
all_figures = (figures..., parameter_figures..., station_figures...)
for (directory, filename) in all_figures
    source = joinpath(directory, filename)
    check_png(source)
    cp(source, joinpath(assets_dir, filename); force = true)
end

function write_result_assets(prefix, output, checks)
    figure_names = last.(all_figures)
    log_lines = filter(line -> !any(name -> occursin(name, line), figure_names), split(output, '\n'))
    write(joinpath(assets_dir, "$(prefix)_console.md"),
          "**365-day simulation — console output**\n\n````text\n" * join(log_lines, "\n") * "\n````\n")
    write(joinpath(assets_dir, "$(prefix)_budget.md"), """
        ### Nitrogen-budget check

        The budget compares the seven-tracer nitrogen inventory with sinking
        loss through the open bottom boundary. The residual is relative to
        the first saved inventory.

        | Experiment | Final residual | Maximum absolute residual |
        |:-----------|---------------:|--------------------------:|
        $(join(checks, "\n"))

        The acceptance threshold is 5% of the starting inventory. The
        diagnostic uses saved profiles and an upwind estimate of sinking flux.
        """)
end

write_result_assets("reference_column", reference_output,
                    [budget_summary("Reference", joinpath(reference_dir, "reference_diagnostics.csv"))])
write_result_assets("grazing", grazing_output,
                    [budget_summary(label, joinpath(grazing_dir, "$(name)_diagnostics.csv"))
                     for (label, name) in (("Control", "control"), ("Reduced grazing", "reduced_grazing"))])
for (_, experiment, modified) in parameter_exercises
    directory = joinpath(output_base, experiment)
    checks = [budget_summary(label, joinpath(directory, "$(name)_diagnostics.csv"))
              for (label, name) in (("Control", "control"), ("Modified", modified))]
    write_result_assets(experiment, parameter_outputs[experiment], checks)
end

asset_text(name) = read(joinpath(assets_dir, name), String)
function figure_block(filename, caption)
    check_png(joinpath(assets_dir, filename))
    return "![$caption](../assets/$filename)"
end

function make_tutorial(filename, replacements)
    Literate.markdown(joinpath(exercise_dir, filename), generated_dir;
                      flavor = Literate.DocumenterFlavor(),
                      codefence = "````julia" => "````",
                      execute = false, credit = false, edit_commit = "main",
                      postprocess = content -> replace(content, replacements...))
end

make_tutorial("00_reference_column.jl", (
    "WORKSHOP_REFERENCE_OUTPUT" => asset_text("reference_column_console.md"),
    "WORKSHOP_REFERENCE_VERTICAL_FIGURE" => figure_block("reference_vertical_evolution.png", "Reference evolution of six LOBSTER tracers"),
    "WORKSHOP_REFERENCE_PARTITION_FIGURE" => figure_block("reference_nitrogen_partition.png", "Upper 100 m nitrogen inventories and fractions"),
    "WORKSHOP_REFERENCE_LIVING_FIGURE" => figure_block("reference_living_fraction.png", "Living particulate and dissolved-organic nitrogen fractions"),
    "WORKSHOP_REFERENCE_EXPORT_FIGURE" => figure_block("reference_carbon_export.png", "Daily and cumulative carbon export from the reference column"),
    "WORKSHOP_REFERENCE_MARTIN_FIGURE" => figure_block("reference_martin_curve.png", "Export profiles at 50–300 m and Martin-curve comparison"),
    "WORKSHOP_REFERENCE_BUDGET_CHECK" => asset_text("reference_column_budget.md"),
))

make_tutorial("01_grazing.jl", (
    "WORKSHOP_RUN_OUTPUT" => asset_text("grazing_console.md"),
    "WORKSHOP_GRAZING_FIGURE" => figure_block("grazing_response.png", "Response to reduced grazing"),
    "WORKSHOP_PLANKTON_BALANCE_FIGURE" => figure_block("grazing_plankton_balance.png", "Phytoplankton and zooplankton inventories and grazing response"),
    "WORKSHOP_EXPORT_FIGURE" => figure_block("carbon_export.png", "Control and reduced-grazing carbon export"),
    "WORKSHOP_BUDGET_CHECK" => asset_text("grazing_budget.md"),
))

for (script, experiment, _) in parameter_exercises
    make_tutorial(script, (
        "WORKSHOP_PARAMETER_OUTPUT" => asset_text("$(experiment)_console.md"),
        "WORKSHOP_PARAMETER_RESPONSE_FIGURE" => figure_block("$(experiment)_response.png", "Annual response to $(replace(experiment, '_' => ' '))"),
        "WORKSHOP_PARAMETER_EXPORT_FIGURE" => figure_block("$(experiment)_export.png", "Carbon export response to $(replace(experiment, '_' => ' '))"),
        "WORKSHOP_PARAMETER_BUDGET_CHECK" => asset_text("$(experiment)_budget.md"),
    ))
end

station_page = joinpath(@__DIR__, "src", "comparison.md.in")
station_credit = "<small>Annual-mean VIIRS CAFE satellite NPP, 2023, masked to water deeper than 200 m. " *
                 "[Ocean Productivity](https://orca.science.oregonstate.edu/npp_products.php), " *
                 "[Silsbe et al. (2016)](https://doi.org/10.1002/2016GB005521), " *
                 "and [Natural Earth](https://www.naturalearthdata.com/downloads/10m-physical-vectors/) bathymetry. " *
                 "Plotted from numerical data/maps/north_atlantic_cafe_npp_2023.nc.</small>"
write(joinpath(generated_dir, "07_bats_nabe.md"),
      replace(read(station_page, String),
              "WORKSHOP_STATION_MAP_CREDIT" => station_credit,
              "WORKSHOP_STATION_MAP_FIGURE" =>
                  figure_block("station_map.png", "BATS and NABE on the 2023 CAFE satellite NPP map"),
              "WORKSHOP_STATION_FORCING_FIGURE" =>
                  figure_block("station_forcing.png", "Prescribed PAR and seasonal mixing depth"),
              "WORKSHOP_STATION_DIFFUSIVITY_FIGURE" =>
                  figure_block("station_diffusivity.png", "Idealised diffusivity in the upper 300 m")))

# The publicly documented appendix uses figures generated directly from the
# classroom forcing. Instructor CATKE runs require additional JLD2 source data
# and can be explored separately in physics/.
physics_src = joinpath(@__DIR__, "src", "appendix", "physical_forcing.md.in")
write(joinpath(generated_dir, "physical_forcing.md"),
      replace(read(physics_src, String),
              "WORKSHOP_STATION_FORCING_FIGURE" =>
                  figure_block("station_forcing.png", "Idealised seasonal light and mixing depth"),
              "WORKSHOP_STATION_DIFFUSIVITY_FIGURE" =>
                  figure_block("station_diffusivity.png", "Idealised seasonal tracer diffusivity")))

makedocs(
    sitename = "MASTS ASM 2026 — Modelling for biogeochemists",
    modules = Module[],
    format = Documenter.HTML(prettyurls = get(ENV, "CI", "false") == "true",
                             edit_link = "main", inventory_version = ""),
    pages = [
        "Home" => "index.md",
        "Getting started" => "getting_started.md",
        "Reference column" => "generated/00_reference_column.md",
        "BATS and NABE comparison" => "generated/07_bats_nabe.md",
        "Parameter experiments" => [
            "Light affinity" => "generated/04_light_affinity.md",
            "Nutrient affinity" => "generated/05_nutrient_affinity.md",
            "Grazing" => "generated/01_grazing.md",
            "Particle sinking" => "generated/02_sinking.md",
            "Remineralisation" => "generated/03_remineralisation.md",
            "Phytoplankton mortality" => "generated/06_phytoplankton_mortality.md",
        ],
        "Running on your own system" => "running_locally.md",
        "Appendix" => ["Physical forcing" => "generated/physical_forcing.md"],
    ],
)
