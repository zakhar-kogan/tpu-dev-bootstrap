# Package Groups

Each `.txt` file defines a package group that `install.sh` installs via `uv pip install`.
Lines starting with `#` are comments. Variable references (`$TORCH_VERSION`) are
expanded by the installer using explicit substitution.

Default groups (installed unless overridden via `--package-groups`):

- `core`: JupyterLab, Jupyter Server, IPython kernel, packaging basics.
- `tpu`: `torch`, `torch_xla[tpu]`, `numpy`.
- `general-ds`: pandas, scikit-learn, numba, scipy.
- `graphs`: networkx, python-louvain, graphviz.
- `nlp`: gensim, spacy.
- `cayley-graphs`: cayleypy.

Optional groups (add via `--package-groups core,tpu,...,llms`):

- `llms`: transformers, accelerate, datasets, unsloth.
- `graphml`: torch-geometric, pyg.
- `uis`: streamlit, panel.
- `dev`: ruff, pytest, black, pre-commit.
