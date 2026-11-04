# Abil.py — BATS regressor example

This is the existing [Abil.py BATS regressor example](https://github.com/nanophyto/Abil/blob/v26.5.4-2/examples/regressor.py), using the example configuration and datasets from the same tagged release. It predicts *Gephyrocapsa huxleyi* abundance from temperature, nitrate, alkalinity, dissolved inorganic carbon and PAR at BATS.

Open `regressor.py` in Code OSS and select **Run Python File**, or in the terminal run:

```bash
python /home/user/masts-asm-2026-modelling/workshop/02_Abil/regressor.py
```

The example fits random forest, XGBoost and bagged k-nearest-neighbour models; predicts a BATS monthly depth grid; and plots predicted abundance, uncertainty intervals and observed-versus-modelled values. The four `BATS_*.png` figures and `ModelOutput/regressor/` outputs are saved alongside the script. Open PNGs from Explorer to inspect them.

The workshop Docker build installs Matplotlib and Seaborn and copies the original BATS input CSVs into `data/`. To prepare the input files in a local checkout, run `python abil/fetch_bats_data.py` once from the repository root. After the inputs are present, the example runs without network access.

This is the upstream **illustrative regressor** with its original configuration (including ten-fold cross-validation and three models); the workshop-specific, self-paced BATS/HOT exercises can build on it separately.

Source: [Abil v26.5.4-2 example](https://github.com/nanophyto/Abil/tree/v26.5.4-2/examples), MIT licence.
