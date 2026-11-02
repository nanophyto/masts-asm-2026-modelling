# Compare numerical choices against the original 365-day LOBSTER column.
# From the repository root:
#   julia --threads=1 --project=oceanbiome oceanbiome/benchmarks/compare_numerics.jl
# Add --quick for a two-day smoke run. The 30-minute intermediate cases
# isolate the solver, grid, and time-step changes, while 50 cells / 1 hour is
# the proposed fast configuration.

using OceanBioME, Oceananigans
using Oceananigans.Units
using Oceananigans.TurbulenceClosures: ExplicitTimeDiscretization, VerticallyImplicitTimeDiscretization
using Oceananigans.Fields: interior
using MASTSWorkshop: surface_PAR, vertical_diffusivity, initial_conditions,
                     column_numerics, sinking_courant, diagnose_column,
                     write_diagnostics, write_export_profile

quick = "--quick" in ARGS
names = (:reference, :implicit, :coarse, :fast)
output_root = get(ENV, "MASTS_NUMERICS_DIR",
                  joinpath(@__DIR__, "..", "..", "outputs", "oceanbiome", "numerics-comparison"))
output_root = joinpath(output_root, quick ? "quick" : "annual")
mkpath(output_root)
stop_time = quick ? 2days : 365days
schedule = TimeInterval(quick ? 6hours : 1day)

function run_configuration(name)
    config = column_numerics(["--numerics=$name"])
    grid = RectilinearGrid(size = config.nz, extent = 500meters,
                           topology = (Flat, Flat, Bounded))
    plankton = PhytoZoo(; nutrient_half_saturations = (nitrate = 0.7, ammonia = 0.001),
                         maximum_grazing_rate = 0.8 / day)
    biogeochemistry = LOBSTER(grid; plankton, surface_PAR, scale_negatives = true)
    time_discretization = config.implicit ? VerticallyImplicitTimeDiscretization() :
                                            ExplicitTimeDiscretization()
    model = NonhydrostaticModel(grid;
                                closure = ScalarDiffusivity(time_discretization;
                                                            ν = vertical_diffusivity,
                                                            κ = vertical_diffusivity),
                                biogeochemistry)
    set!(model; initial_conditions()...)

    courant = sinking_courant(model, config.dt)
    isfinite(courant) && courant < 1 ||
        error("$name: sinking Courant number $courant requires a shorter time step")

    directory = joinpath(output_root, string(name))
    mkpath(directory)
    filename = joinpath(directory, "profiles.jld2")
    simulation = Simulation(model; Δt = config.dt, stop_time)
    simulation.output_writers[:profiles] = JLD2Writer(model, model.tracers;
                                                       filename, schedule,
                                                       overwrite_files = true)
    start = time_ns()
    run_seconds = @elapsed run!(simulation)
    for tracer in values(model.tracers)
        all(isfinite, interior(tracer)) || error("$name: nonfinite tracer concentration")
        minimum(interior(tracer)) >= -1e-8 || error("$name: negative tracer concentration")
    end
    diagnostics = nothing
    diagnosis_seconds = @elapsed diagnostics = diagnose_column(filename, model)
    write_diagnostics(joinpath(directory, "diagnostics.csv"), diagnostics)
    write_export_profile(joinpath(directory, "export_profile.csv"), diagnostics)
    elapsed_seconds = (time_ns() - start) / 1e9
    budget_percent = 100 * last(diagnostics.budget_residual) /
                     first(diagnostics.nitrogen_inventory)
    max_budget_percent = 100 * maximum(abs, diagnostics.budget_residual) /
                         first(diagnostics.nitrogen_inventory)
    max_budget_percent <= 5 ||
        error("$name: maximum nitrogen-budget residual exceeds 5% of initial inventory")
    println("$name: grid=$(config.nz), dt=$(config.dt / minutes) min, ",
            "sinking CFL=$(round(courant; digits=3)), ",
            "integration=$(round(run_seconds; digits=2)) s, ",
            "total=$(round(elapsed_seconds; digits=2)) s, ",
            "N budget=$(round(budget_percent; digits=5))%")
    return (; config, diagnostics, courant, run_seconds, diagnosis_seconds,
              elapsed_seconds, budget_percent, max_budget_percent)
end

function diagnostic_series(d)
    return (surface_P = d.surface_P,
            surface_NO3 = d.surface_NO₃,
            export_100_daily = d.export_100.daily_mg_C,
            export_300_daily = d.export_300.daily_mg_C,
            export_100_cumulative = d.export_100.cumulative_g_C,
            export_300_cumulative = d.export_300.cumulative_g_C,
            nitrogen_inventory = d.nitrogen_inventory,
            nitrogen_budget_residual = d.budget_residual)
end

results = Dict(name => run_configuration(name) for name in names)

summary_file = joinpath(output_root, "runtime_summary.csv")
open(summary_file, "w") do io
    println(io, "preset,nz,step_minutes,implicit,sinking_cfl,simulation_seconds,diagnostics_seconds,total_seconds,final_surface_P,final_surface_NO3,cumulative_export_100,cumulative_export_300,final_budget_residual,budget_residual_percent,max_budget_residual_percent")
    for name in names
        r = results[name]
        d = r.diagnostics
        println(io, join((name, r.config.nz, r.config.dt / minutes,
                          r.config.implicit, r.courant, r.run_seconds,
                          r.diagnosis_seconds, r.elapsed_seconds,
                          last(d.surface_P), last(d.surface_NO₃),
                          last(d.export_100.cumulative_g_C),
                          last(d.export_300.cumulative_g_C),
                          last(d.budget_residual), r.budget_percent, r.max_budget_percent), ','))
    end
end

# Compare solver/time-step changes separately from grid-resolution changes.
# For the 50-cell grid, average adjacent 5 m reference cells to 10 m before
# comparing vertical fields; this preserves the layer-mean concentration.
function common_grid(a, nz)
    original_nz, nt = size(a)
    original_nz % nz == 0 || error("cannot coarsen $original_nz cells to $nz")
    factor = original_nz ÷ nz
    return dropdims(sum(reshape(a, factor, nz, nt); dims = 1); dims = 1) ./ factor
end

function vertical_series(d)
    return (profile_P = d.vertical_P,
            profile_Z = d.vertical_Z,
            profile_NO3 = d.vertical_NO₃,
            profile_sPOM = d.vertical_sPOM,
            profile_bPOM = d.vertical_bPOM,
            profile_DOM = d.vertical_DOM)
end

comparisons = [(:reference, :implicit), (:implicit, :coarse),
               (:coarse, :fast), (:reference, :fast)]
differences_file = joinpath(output_root, "numerics_differences.csv")
open(differences_file, "w") do io
    println(io, "baseline,trial,metric,comparison_nz,baseline_final,trial_final,final_error,rms_error,normalized_final_error,normalized_rms_error")
    for (baseline_name, trial_name) in comparisons
        baseline_d = results[baseline_name].diagnostics
        trial_d = results[trial_name].diagnostics
        length(baseline_d.times) == length(trial_d.times) &&
            all(isapprox.(baseline_d.times, trial_d.times; atol = 1e-6, rtol = 1e-10)) ||
            error("$trial_name: output sample times do not match $baseline_name")
        baseline_series = diagnostic_series(baseline_d)
        trial_series = diagnostic_series(trial_d)
        base_vertical = vertical_series(baseline_d)
        trial_vertical = vertical_series(trial_d)
        nz = min(size(baseline_d.vertical_P, 1), size(trial_d.vertical_P, 1))

        for (metric, original) in pairs(merge(baseline_series, base_vertical))
            trial = hasproperty(trial_series, metric) ? trial_series[metric] : trial_vertical[metric]
            if ndims(original) == 2
                baseline = common_grid(original, nz)
                trial = common_grid(trial, nz)
                baseline_final = sum(baseline[:, end]) / nz
                trial_final = sum(trial[:, end]) / nz
                differences = trial .- baseline
                final_error = sqrt(sum(abs2, differences[:, end]) / nz)
                comparison_nz = nz
            else
                baseline = original
                differences = trial .- baseline
                baseline_final = last(baseline)
                trial_final = last(trial)
                final_error = abs(last(differences))
                comparison_nz = 1
            end
            all(isfinite, baseline) && all(isfinite, trial) ||
                error("$trial_name: nonfinite diagnostic in $metric")
            rms = sqrt(sum(abs2, differences) / length(differences))
            scale = metric == :nitrogen_budget_residual ?
                    first(baseline_d.nitrogen_inventory) : maximum(abs, baseline)
            scale = max(abs(scale), eps(Float64))
            println(io, join((baseline_name, trial_name, metric, comparison_nz,
                              baseline_final, trial_final, final_error, rms,
                              final_error / scale, rms / scale), ','))
        end
    end
end

println("Saved $summary_file")
println("Saved $differences_file")
println("Compare implicit with reference for the solver/time step, ",
        "coarse with implicit for grid resolution, and fast with coarse for hourly stepping.")
