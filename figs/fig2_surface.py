#!/usr/bin/env python3
"""
fig2_surface.py — render the paper's Figure 2 ("Expected return curves") surface.
Python port of the legacy Matlab Graphs/plots_code.m. Run from the PACKAGE ROOT:

    python3 figs/fig2_surface.py

Produces in out/figs/:
  fig2_published_inputs.(png|pdf)  — from reference/data_fig2_published.xlsx, the exact
                                     input file behind the printed JFE figure
  fig2_your_run.(png|pdf)          — from out/MedianParams_REPsampleall.csv (your own
                                     pipeline output; requires run_all.do to have finished)

Model per plots_code.m:  x = cbm*btm + croe*(lroe - mu);
  mut(t, i) = (var/2 + mu + ((1 - kappa^i)/(1 - kappa)) * (x/i)) * 4 * 100,  i = 1..120.
"""
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path

ROOT = Path(".").resolve()
OUTD = ROOT / "out/figs"
OUTD.mkdir(parents=True, exist_ok=True)
NHOR = 120


def curve_matrix(mu, kappa, cbm, croe, btm, lroe, var):
    x = cbm * btm + croe * (lroe - mu)
    mut = np.empty((len(mu), NHOR))
    for i in range(1, NHOR + 1):
        ann = (1.0 - kappa ** i) / (1.0 - kappa)
        mut[:, i - 1] = (var / 2.0 + mu + ann * (x / i)) * 4.0 * 100.0
    return mut


def render(dates, mut, title, stem):
    X, Y = np.meshgrid(dates, np.arange(1, NHOR + 1) / 4.0, indexing="ij")
    fig = plt.figure(figsize=(10, 7))
    ax = fig.add_subplot(111, projection="3d")
    ax.plot_surface(X, Y, mut, cmap="viridis", rstride=1, cstride=2, linewidth=0, antialiased=True)
    ax.view_init(elev=12, azim=-70)
    ax.set_xlabel("Date", labelpad=10)
    ax.set_ylabel("Years ahead", labelpad=10)
    ax.set_zlabel("Annualized E[r] (%)", labelpad=8)
    ax.set_yticks([0, 10, 20, 30])
    ax.set_title(title, pad=0)
    ax.set_box_aspect((2.2, 1.0, 0.7))
    for ext in ("png", "pdf"):
        fig.savefig(OUTD / f"{stem}.{ext}", dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(f"{stem}: T={mut.shape[0]}, range {mut.min():.2f}..{mut.max():.2f} %")


# 1. published inputs (the printed figure)
raw = pd.read_excel(ROOT / "reference/data_fig2_published.xlsx", sheet_name=0,
                    header=None, skiprows=1, nrows=111, usecols="A:S")
dates = (pd.to_datetime(raw[0]).dt.year + (pd.to_datetime(raw[0]).dt.quarter - 1) / 4.0).to_numpy()
mut = curve_matrix(raw[3].to_numpy(float), raw[4].to_numpy(float), raw[6].to_numpy(float),
                   raw[7].to_numpy(float), raw[1].to_numpy(float), raw[2].to_numpy(float),
                   raw[8].to_numpy(float))
render(dates, mut, "Expected return curves — published inputs (1986Q1–2013Q3)", "fig2_published_inputs")

# 2. your own pipeline output (exists after run_all.do)
mine = ROOT / "out/MedianParams_REPsampleall.csv"
if mine.exists():
    u = pd.read_csv(mine)
    d2 = (u["year"] + (u["quarter"] - 1) / 4.0).to_numpy()
    mut2 = curve_matrix(u["mu_pool2_w"].to_numpy(float), u["k_pool20_w"].to_numpy(float),
                        u["coeff_btm_pool2"].to_numpy(float), u["coeff_lroe_pool2"].to_numpy(float),
                        u["btm"].to_numpy(float), u["lroe"].to_numpy(float),
                        u["var_cum"].to_numpy(float))
    render(d2, mut2, "Expected return curves — your replication run", "fig2_your_run")
else:
    print("out/MedianParams_REPsampleall.csv not found — run run_all.do first for the second panel")
