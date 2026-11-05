using Pkg
Pkg.instantiate()
using Documenter, Literate

root = normpath(joinpath(@__DIR__, ".."))
scientific_project = joinpath(root, "oceanbiome")
exercise_dir = joinpath(root, "workshop", "01_OceanBioME")
assets_dir = joinpath(@__DIR__, "src", "assets")
generated_dir = joinpath(@__DIR__, "src", "generated")
mkpath(assets_dir)
mkpath(generated_dir)

# PR builds validate plotting using isolated output paths; full builds also
# publish reference figures and console assets.
quick = get(ENV, "DOCS_QUICK", "false") == "true"
content_only = get(ENV, "DOCS_CONTENT_ONLY", "false") == "true"
reuse_results = get(ENV, "DOCS_REUSE_RESULTS", "false") == "true"
quick && reuse_results && error("DOCS_REUSE_RESULTS requires full-run reference outputs")
output_base = joinpath(root, "outputs", "oceanbiome", quick ? "docs_smoke" : "reference_docs")

function run_exercise(name, output_dir)
    exercise = joinpath(exercise_dir, name)
    command = `$(Base.julia_cmd()) --threads=1 --startup-file=no --project=$scientific_project $exercise`
    output = cd(root) do
        read(addenv(command, "MASTS_OUTPUT_DIR" => output_dir), String)
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
    initial_inventory = first(inventory)
    initial_inventory > 0 || error("Non-positive nitrogen inventory in $filename")
    max_percent = 100 * maximum(abs, residual) / initial_inventory
    final_percent = 100 * last(residual) / initial_inventory

    max_percent <= 5 || error("$label nitrogen-budget residual exceeds 5%: $(round(max_percent; digits=2))%")
    return "| $label | $(round(final_percent; digits=2))% | $(round(max_percent; digits=2))% |"
end

function check_png(filename)
    isfile(filename) && filesize(filename) > 8 || error("Missing or empty figure: $filename")
    open(filename) do io
        read(io, 8) == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] ||
            error("Invalid PNG header in $filename")
    end
end

reference_dir = joinpath(output_base, "reference_column")
grazing_dir = joinpath(output_base, "grazing")
station_dir = joinpath(output_base, "bats_nabe")
parameter_exercises = (("02_sinking.jl", "sinking", "slow_sinking"),
                       ("03_remineralisation.jl", "remineralisation", "fast_remineralisation"),
                       ("04_light_affinity.jl", "light_affinity", "higher_light_affinity"),
                       ("05_nutrient_affinity.jl", "nutrient_affinity", "higher_nutrient_affinity"),
                       ("06_phytoplankton_mortality.jl", "phytoplankton_mortality", "higher_mortality"))
parameter_outputs = Dict{String, Union{String, Nothing}}()
# For documentation-only fixes, reuse the previously generated annual
# profiles, CSV diagnostics, and figures without repeating the simulations.
reference_output, grazing_output = if content_only
    @info "Building documentation using committed scientific figures"
    (nothing, nothing)
elseif reuse_results
    @info "Reusing existing annual simulation results"
    (nothing, nothing)
else
    # The documentation and scientific exercises have separate Julia environments.
    # Set up the scientific environment before checking its plotting extension.
    instantiate_cmd = `$(Base.julia_cmd()) --threads=1 --startup-file=no --project=$scientific_project -e $("using Pkg; Pkg.instantiate()")`
    run(addenv(instantiate_cmd, "JULIA_PKG_PRECOMPILE_AUTO" => "0"))
    # Catch plotting-extension failures before starting annual simulations.
    plot_check = "using MASTSWorkshop, CairoMakie; " *
                 "isnothing(Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt)) && " *
                 "error(\"Workshop plotting extension did not load\")"
    run(`$(Base.julia_cmd()) --threads=1 --startup-file=no --project=$scientific_project -e $plot_check`)
    (run_exercise("00_reference_column.jl", reference_dir),
     run_exercise("01_grazing.jl", grazing_dir))
end

# Full documentation builds run all parameter experiments; DOCS_QUICK
# remains available as a local smoke-test option.
for (script, experiment, _) in parameter_exercises
    parameter_outputs[experiment] = (quick || reuse_results || content_only) ? nothing : run_exercise(script, joinpath(output_base, experiment))
end

# The deep BATS-NABE station exercise runs both annual baselines and
# generates fresh figures during every full scientific documentation build.
station_output = (quick || reuse_results || content_only) ? nothing :
                 run_exercise("07_bats_nabe.jl", station_dir)

# The physics diagram belongs to the appendix; the reference exercise
# concentrates on simulation results and its five scientific figures.
physics_figure = joinpath(reference_dir, "reference_physics.png")
if !content_only && !isfile(physics_figure)
    mkpath(reference_dir)
    code = "using MASTSWorkshop, CairoMakie; MASTSWorkshop.plot_idealised_physics(ARGS[1]; preview=false)"
    run(`$(Base.julia_cmd()) --threads=1 --startup-file=no --project=$scientific_project -e $code $physics_figure`)
end

figures = (
    (reference_dir, "reference_vertical_evolution.png"),
    (reference_dir, "reference_nitrogen_partition.png"),
    (reference_dir, "reference_living_fraction.png"),
    (reference_dir, "reference_carbon_export.png"),
    (reference_dir, "reference_martin_curve.png"),
    (reference_dir, "reference_physics.png"),
    (grazing_dir, "grazing_response.png"),
    (grazing_dir, "grazing_plankton_balance.png"),
    (grazing_dir, "carbon_export.png"),
)
parameter_figures = Tuple((joinpath(output_base, experiment), "$(experiment)_$(kind).png")
                          for (_, experiment, _) in parameter_exercises for kind in ("response", "export"))
station_figures = ((station_dir, "station_forcing.png"),
                   (station_dir, "station_comparison.png"))
if !content_only
    for (directory, filename) in (quick ? figures : (figures..., parameter_figures..., station_figures...))
        check_png(joinpath(directory, filename))
        if !quick
            cp(joinpath(directory, filename), joinpath(assets_dir, filename); force = true)
        end
    end
end

function write_result_assets(prefix, output, checks)
    (quick || content_only) && return
    figure_names = last.((figures..., parameter_figures..., station_figures...))
    if !isnothing(output)
        log_lines = filter(line -> !any(name -> occursin(name, line), figure_names),
                           split(output, '\n'))
        write(joinpath(assets_dir, "$(prefix)_console.md"),
              "**365-day simulation — console output**\n\n````text\n" *
              join(log_lines, "\n") * "\n````\n")
    end
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

if !content_only
    reference_checks = [budget_summary("Reference", joinpath(reference_dir, "reference_diagnostics.csv"))]
    grazing_checks = [budget_summary(label, joinpath(grazing_dir, "$(name)_diagnostics.csv"))
                      for (label, name) in (("Control", "control"), ("Reduced grazing", "reduced_grazing"))]
    write_result_assets("reference_column", reference_output, reference_checks)
    write_result_assets("grazing", grazing_output, grazing_checks)
    if !quick
        for (_, experiment, modified) in parameter_exercises
            directory = joinpath(output_base, experiment)
            checks = [budget_summary(label, joinpath(directory, "$(name)_diagnostics.csv"))
                      for (label, name) in (("Control", "control"), ("Modified", modified))]
            write_result_assets(experiment, parameter_outputs[experiment], checks)
        end
        station_checks = [budget_summary(string(station),
                          joinpath(station_dir, "$(lowercase(string(station)))_diagnostics.csv"))
                          for station in (:BATS, :NABE)]
        write_result_assets("bats_nabe", station_output, station_checks)
    end

end

reference_note = "Reference results and figures are provided in the published workshop documentation."
function asset_text(filename)
    path = joinpath(assets_dir, filename)
    isfile(path) ? read(path, String) : reference_note
end
function figure_block(filename, caption)
    path = joinpath(assets_dir, filename)
    if !isfile(path) && !quick && !content_only
        error("Missing documentation figure: $(path). Run a full documentation build to generate it.")
    end
    isfile(path) ? "![$caption](../assets/$filename)" : "**$caption:** $reference_note"
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

make_tutorial("07_bats_nabe.jl", (
    "WORKSHOP_STATION_FORCING_FIGURE" =>
        figure_block("station_forcing.png", "Contrasting idealised BATS and NABE physical forcing"),
    "WORKSHOP_STATION_COMPARISON_FIGURE" =>
        figure_block("station_comparison.png", "Annual BATS-NABE ecosystem and deep-export comparison"),
))

# The appendix is a template: Documenter should process only its generated
# copy, where the relative links to both tutorials are correct.
physics_src = joinpath(@__DIR__, "src", "appendix", "physical_forcing.md.in")
write(joinpath(generated_dir, "physical_forcing.md"),
      replace(read(physics_src, String),
              "WORKSHOP_PHYSICS_FIGURE" => figure_block("reference_physics.png", "Annual surface light, mixed-layer depth and vertical diffusivity")))

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

if get(ENV, "GITHUB_ACTIONS", "false") == "true" &&
   get(ENV, "GITHUB_REF", "") == "refs/heads/main"
    repository = ENV["GITHUB_REPOSITORY"]
    deploydocs(repo = "github.com/$(repository).git", devbranch = "main", versions = nothing)
end
