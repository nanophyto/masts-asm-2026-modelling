module ColumnDiagnostics

using Oceananigans: FieldTimeSeries
using Oceananigans.Biogeochemistry: biogeochemical_drift_velocity
using Oceananigans.Units: days

export face_index, downward_nitrogen_flux, cumulative_trapezoid,
       carbon_flux_mg_per_day, carbon_export_g_per_m2,
       martin_flux, fit_martin_exponent, diagnose_column, write_diagnostics, write_export_profile

const carbon_to_nitrogen = 106 / 16  # mol C per mol N (fixed Redfield ratio)
const carbon_molar_mass = 12.011     # mg C per mmol C
const tracers = (:NO₃, :NH₄, :P, :Z, :DOM, :sPOM, :bPOM)

# The 1D teaching grid is uniform, with its surface at z = 0.
# A downward flux at face k uses the concentration in cell k immediately above it.
function face_index(grid, depth)
    Δz = grid.Lz / grid.Nz
    depth > 0 && depth <= grid.Lz || throw(ArgumentError("depth must be inside the column"))
    steps = round(Int, depth / Δz)
    isapprox(steps * Δz, depth; atol = 1e-8) ||
        throw(ArgumentError("export depth $depth m must coincide with a grid face"))
    return grid.Nz + 1 - steps
end

# Concentrations in mmol N/m³, face velocities in m/s (negative is downward).
# Result: downward-positive mmol N/(m² s).
downward_nitrogen_flux(sPOM, bPOM, w_small, w_large) =
    max(-w_small, 0) * sPOM + max(-w_large, 0) * bPOM

# Convert a flux from mmol N/(m² s) to mg C/(m² day).
carbon_flux_mg_per_day(nitrogen_flux) = nitrogen_flux * carbon_to_nitrogen * carbon_molar_mass * days

# Integrate a flux in mmol N/(m² s) and convert to g C/m².
carbon_export_g_per_m2(times, nitrogen_flux) =
    cumulative_trapezoid(times, nitrogen_flux) .* (carbon_to_nitrogen * carbon_molar_mass / 1000)

# Integrate a rate in seconds; preserve its native units times seconds.
function cumulative_trapezoid(times, rate)
    length(times) == length(rate) || throw(DimensionMismatch("time and rate lengths differ"))
    isempty(times) && throw(ArgumentError("at least one sample is required"))
    cumulative = zeros(Float64, length(times))
    for i in 2:length(times)
        Δt = times[i] - times[i - 1]
        Δt > 0 || throw(ArgumentError("times must be strictly increasing"))
        cumulative[i] = cumulative[i - 1] + Δt * (rate[i - 1] + rate[i]) / 2
    end
    return cumulative
end

# Martin et al. (1987): F(z) = F(z₀) × (z/z₀)^(-b), conventionally z₀ = 100 m.
martin_flux(depth, reference_flux, b = 0.858; reference_depth = 100) =
    reference_flux * (depth / reference_depth)^(-b)

# Fit b with F(100) fixed to the modelled flux at 100 m.
# A power law cannot be fitted if any flux below 100 m is non-positive.
function fit_martin_exponent(depths, fluxes; reference_depth = 100)
    length(depths) == length(fluxes) || throw(DimensionMismatch("depth and flux lengths differ"))
    index = findfirst(==(reference_depth), depths)
    isnothing(index) && throw(ArgumentError("reference depth must be present"))
    indices = findall(>(reference_depth), depths)
    isempty(indices) && throw(ArgumentError("at least one deeper flux is required"))
    reference_flux = fluxes[index]
    all(i -> isfinite(fluxes[i]) && fluxes[i] > 0, [index; indices]) || return nothing
    x = log.(depths[indices] ./ reference_depth)
    y = log.(fluxes[indices] ./ reference_flux)
    return -sum(x .* y) / sum(abs2, x)
end

function diagnose_column(filename, model)
    grid = model.grid
    profiles = (; (name => FieldTimeSeries(filename, string(name)) for name in tracers)...)
    times = collect(profiles.P.times)
    isempty(times) && throw(ArgumentError("no profile samples in $filename"))

    ws = biogeochemical_drift_velocity(model.biogeochemistry, Val(:sPOM)).w
    wb = biogeochemical_drift_velocity(model.biogeochemistry, Val(:bPOM)).w

    surface_tracer(name) = [profiles[name][n][1, 1, grid.Nz] for n in eachindex(times)]
    vertical_tracer(name) = [profiles[name][n][1, 1, k] for k in 1:grid.Nz, n in eachindex(times)]

    surface_P = surface_tracer(:P)
    surface_NO₃ = surface_tracer(:NO₃)

    # Area-normalised total nitrogen inventory (mmol N/m²), all seven pools.
    Δz = grid.Lz / grid.Nz
    z = [-grid.Lz + (k - 0.5) * Δz for k in 1:grid.Nz]
    vertical_P = vertical_tracer(:P)
    vertical_Z = vertical_tracer(:Z)
    vertical_NO₃ = vertical_tracer(:NO₃)
    vertical_sPOM = vertical_tracer(:sPOM)
    vertical_bPOM = vertical_tracer(:bPOM)
    vertical_DOM = vertical_tracer(:DOM)
    nitrogen_inventory = [Δz * sum(profiles[name][n][1, 1, k]
                                      for name in tracers for k in 1:grid.Nz)
                          for n in eachindex(times)]

    function export_at(depth)
        k = face_index(grid, depth)
        nitrogen_flux = [downward_nitrogen_flux(profiles.sPOM[n][1, 1, k],
                                                profiles.bPOM[n][1, 1, k],
                                                ws[1, 1, k], wb[1, 1, k])
                         for n in eachindex(times)]
        return (nitrogen_flux = nitrogen_flux,
                daily_mg_C = carbon_flux_mg_per_day.(nitrogen_flux),
                cumulative_g_C = carbon_export_g_per_m2(times, nitrogen_flux))
    end

    export_100 = export_at(100)
    export_300 = export_at(300)
    bottom = export_at(grid.Lz)
    bottom_loss = cumulative_trapezoid(times, bottom.nitrogen_flux)

    # Export at every 50 m down to the bottom, using the same face-flux diagnostic.
    depths = collect(50:50:floor(Int, grid.Lz))
    fluxes = [depth == 100 ? export_100 : depth == 300 ? export_300 :
              depth == grid.Lz ? bottom : export_at(depth) for depth in depths]

    # A late-year average reduces the impact of the prescribed initial POM stock.
    # The short smoke run uses its entire available duration.
    start = findfirst(>=(last(times) - 90days), times)
    window_days = (last(times) - times[start]) / days
    window_days > 0 || throw(ArgumentError("need at least two different output times"))
    mean_daily_mg_C = [1000 * (last(f.cumulative_g_C) - f.cumulative_g_C[start]) /
                       window_days for f in fluxes]
    integrated_g_C = [last(f.cumulative_g_C) for f in fluxes]
    export_profile = (; depths, mean_daily_mg_C, integrated_g_C, window_days,
                       martin_b = fit_martin_exponent(depths, mean_daily_mg_C))

    # No external nitrogen sources or restoring in this idealised column.
    # Numerical/sampling error is the residual of inventory + lost-through-bottom.
    budget_residual = nitrogen_inventory .+ bottom_loss .- first(nitrogen_inventory)

    return (; times, day = times ./ days, z,
              vertical_P, vertical_Z, vertical_NO₃,
              vertical_sPOM, vertical_bPOM, vertical_DOM,
              surface_P, surface_NO₃, export_100, export_300, export_profile,
              nitrogen_inventory, bottom_loss, budget_residual)
end

function write_diagnostics(filename, d)
    mkpath(dirname(filename))
    open(filename, "w") do io
        println(io, join(("day", "surface_P_mmol_N_m3", "surface_NO3_mmol_N_m3",
                          "export_100_m_mg_C_m2_day", "export_300_m_mg_C_m2_day",
                          "cumulative_100_m_g_C_m2", "cumulative_300_m_g_C_m2",
                          "nitrogen_inventory_mmol_N_m2", "bottom_loss_mmol_N_m2",
                          "nitrogen_budget_residual_mmol_N_m2"), ','))
        for i in eachindex(d.times)
            println(io, join((d.day[i], d.surface_P[i], d.surface_NO₃[i],
                              d.export_100.daily_mg_C[i], d.export_300.daily_mg_C[i],
                              d.export_100.cumulative_g_C[i], d.export_300.cumulative_g_C[i],
                              d.nitrogen_inventory[i], d.bottom_loss[i],
                              d.budget_residual[i]), ','))
        end
    end
    return filename
end

# Save the diagnosed depth profile for inspection and subsequent comparisons.
function write_export_profile(filename, d)
    mkpath(dirname(filename))
    profile = d.export_profile
    open(filename, "w") do io
        println(io, "depth_m,averaging_days,mean_export_mg_C_m2_day,integrated_export_g_C_m2")
        for i in eachindex(profile.depths)
            println(io, join((profile.depths[i], profile.window_days,
                              profile.mean_daily_mg_C[i], profile.integrated_g_C[i]), ','))
        end
    end
    return filename
end

end
