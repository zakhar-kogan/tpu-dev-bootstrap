# TPU Dev Bootstrap

Interactive setup for Google Cloud TPU VMs used by a research group. It creates
a reusable Python environment, installs PyTorch/XLA and notebook tooling,
registers a remote Jupyter kernel, and manages JupyterLab with user-level
systemd.

## Quick Start

From a TPU VM:

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/install.sh | bash
```

With flags:

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/install.sh | bash -s -- \
  --python 3.10 \
  --env-name cayley \
  --jupyter-port 8888 \
  --public-jupyter yes \
  --torch-version 2.9.0 \
  --torch-xla-version 2.9.0
```

With config:

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/install.sh | bash -s -- \
  --config https://raw.githubusercontent.com/<org>/<repo>/main/tpu-setup.example.yaml
```

## Defaults

- Python `3.10`
- `uv` virtual environment under `~/.local/share/tpu-dev/envs/<name>`
- JupyterLab enabled by default
- Public Jupyter prompt defaults to yes, protected by a generated token
- Kernel registered as `TPU Dev (<env-name>)`
- Marimo disabled by default
- Cloudflare quick tunnel optional
- No GCP firewall rules are created automatically
- Existing environments are reused unless `--recreate` is passed

## Access

SSH tunnel:

```bash
gcloud compute tpus tpu-vm ssh <TPU_NAME> --zone=<ZONE> -- \
  -L 8888:127.0.0.1:8888
```

Then open the URL printed by the installer.

Public Jupyter:

The installer can bind JupyterLab to `0.0.0.0` with a generated token. It prints
a firewall command but does not run it. Prefer restricting `--source-ranges` to
your current IP/CIDR.

Remote kernel:

Use the printed Jupyter URL and token from VS Code, JupyterLab, or another
Jupyter client, then select the `TPU Dev (<env-name>)` kernel.

## Package Groups

Default groups:

- `core`: JupyterLab and kernel basics.
- `tpu`: PyTorch/XLA and TPU runtime support.
- `research`: pandas, scipy, numba, transformers, datasets, graph helpers.
- `viz`: matplotlib and seaborn.

Optional groups:

- `marimo`
- `ui-demos`
- `jax`
- `dev`

Example:

```bash
./install.sh --package-groups core,tpu,research,viz,marimo,ui-demos
```

`cayleypy` defaults to GitHub install:

```yaml
cayleypy_source: git
cayleypy_git: "git+https://github.com/cayleypy/cayleypy/"
```

Set `cayleypy_source: pip` to install from PyPI, or `none` to skip.

PyTorch and PyTorch/XLA are pinned by default and should stay aligned:

```yaml
torch_version: "2.9.0"
torch_xla_version: "2.9.0"
```

## Service Commands

```bash
systemctl --user status tpu-jupyter.service
journalctl --user -u tpu-jupyter.service -f
systemctl --user restart tpu-jupyter.service
scripts/status.sh
```

Token and env metadata are stored in:

```bash
~/.config/tpu-dev/secrets.env
```

## TPU Smoke Test

Run this inside the installed environment:

```bash
python scripts/tpu-smoke.py
```

## Docker

Docker is optional. It is useful for isolated workloads, but the host installer
is the main supported path for Jupyter/systemd.

```bash
docker build -t tpu-dev-bootstrap:latest docker
docker/run-tpu-container.sh
```

TPU containers generally need host networking and privileged access:

```bash
docker run --privileged --net=host ...
```

## Security Notes

- No hardcoded notebook password or token.
- No wildcard CORS configuration.
- Public Jupyter is token-protected, but still should be exposed only to trusted
  IP ranges.
- Firewall rules are printed, not applied.
- Re-running the installer reuses the environment; destructive rebuild requires
  `--recreate`.
