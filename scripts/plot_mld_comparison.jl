# Reproduce the observed versus idealised BATS/NABE MLD comparison offline.
# Run: julia --threads=1 --project=oceanbiome scripts/plot_mld_comparison.jl
using MASTSWorkshop, CairoMakie

root = normpath(joinpath(@__DIR__, ".."))
csv = length(ARGS) >= 1 ? ARGS[1] : joinpath(root, "data", "observations", "gosml_mld_bats_nabe.csv")
figure = length(ARGS) >= 2 ? ARGS[2] : joinpath(root, "outputs", "oceanbiome", "mld_comparison", "gosml_mld_comparison.png")
summary = length(ARGS) >= 3 ? ARGS[3] : joinpath(dirname(figure), "gosml_mld_summary.md")

comparison = compare_mld_climatology(csv)
mkpath(dirname(figure))
plot_mld_comparison(comparison, figure; preview = false)
write_mld_summary(summary, comparison)
println("Wrote MLD comparison figure: $figure")
println("Wrote MLD monthly-fit summary: $summary")
