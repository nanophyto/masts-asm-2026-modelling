# Reproduce the observed versus idealised BATS/NABE PAR comparison offline.
# Run: julia --threads=1 --project=oceanbiome scripts/plot_par_comparison.jl
using MASTSWorkshop, CairoMakie

MASTSWorkshop.par_calibrated() || error("NASA POWER PAR coefficients not generated. " *
    "Run `conda run -n masts-gosml python scripts/prepare_par_climatology.py` first.")

root = normpath(joinpath(@__DIR__, ".."))
csv = length(ARGS) >= 1 ? ARGS[1] : joinpath(root, "data", "observations", "nasa_power_par_bats_nabe.csv")
figure = length(ARGS) >= 2 ? ARGS[2] : joinpath(root, "outputs", "oceanbiome", "par_comparison", "nasa_power_par_comparison.png")
summary = length(ARGS) >= 3 ? ARGS[3] : joinpath(dirname(figure), "nasa_power_par_summary.md")

comparison = compare_par_climatology(csv)
mkpath(dirname(figure))
plot_par_comparison(comparison, figure; preview = false)
write_par_summary(summary, comparison)
println("Wrote PAR comparison figure: $figure")
println("Wrote PAR monthly-fit summary: $summary")
