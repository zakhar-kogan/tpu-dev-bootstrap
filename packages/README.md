# Package Groups

`install.sh` currently defines package groups inline so the one-file installer
works when piped from GitHub.

These files are documentation anchors for the defaults and can be promoted into
machine-read constraints once a tested TPU image/runtime matrix is established.

Default groups:

- `core`: JupyterLab, Jupyter Server, IPython kernel, packaging basics.
- `tpu`: `torch`, `torch_xla[tpu]`, `numpy`.
- `research`: pandas, scipy, numba, transformers, datasets, graph helpers.
- `viz`: matplotlib, seaborn.

Optional groups:

- `marimo`
- `ui-demos`: streamlit, plotly, dash, panel, bokeh, holoviews, hvplot.
- `jax`
- `dev`: ruff, pytest, black, pre-commit.
