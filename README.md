# TPU Dev Bootstrap

Interactive setup for Google Cloud TPU VMs used by a research group. It creates
a reusable Python environment, installs PyTorch/XLA and notebook tooling,
registers a remote Jupyter kernel, and manages JupyterLab with user-level
systemd.

## Quick Start

From a TPU VM:

```bash
curl -fsSL https://raw.githubusercontent.com/zakhar-kogan/tpu-dev-bootstrap/main/bootstrap.sh | bash
```

With flags:

```bash
curl -fsSL https://raw.githubusercontent.com/zakhar-kogan/tpu-dev-bootstrap/main/bootstrap.sh | bash -s -- \
  --python 3.10 \
  --env-name cayley \
  --jupyter-port 8888 \
  --public-jupyter yes \
  --marimo yes \
  --public-marimo yes \
  --torch-version 2.9.0 \
  --torch-xla-version 2.9.0
```

Research group setup (public Jupyter + Marimo + SSH key for collaborators):

```bash
curl -fsSL https://raw.githubusercontent.com/zakhar-kogan/tpu-dev-bootstrap/main/bootstrap.sh | bash -s -- \
  --public-jupyter yes \
  --marimo yes \
  --public-marimo yes \
  --generate-share-ssh-key yes \
  --public-ssh-open yes \
  --yes
```

This will:
- Bind JupyterLab and Marimo to `0.0.0.0` (protected by generated tokens)
- Generate a shareable Ed25519 SSH key and print the `ssh` command for collaborators
- Print `gcloud compute firewall-rules` commands to open ports (run them from your laptop)
- Skip all interactive prompts (`--yes`)

With config:

```bash
curl -fsSL https://raw.githubusercontent.com/zakhar-kogan/tpu-dev-bootstrap/main/bootstrap.sh | bash -s -- \
  --config tpu-setup.example.env
```

If you already have the repo cloned:

```bash
./install.sh [options]
```

## Configuration

The installer accepts a `.env` file via `--config`:

```env
PYTHON_VERSION=3.10
ENV_NAME=tpu-dev
ENV_BASE=~/.local/share/tpu-dev/envs

JUPYTER_PORT=8888
PUBLIC_JUPYTER=yes

ENABLE_MARIMO=no
MARIMO_PORT=2718

PACKAGE_GROUPS=core,tpu,general-ds,graphs,nlp,cayley-graphs

TORCH_VERSION=2.9.0
TORCH_XLA_VERSION=2.9.0

EXTRA_PIP=einops,triton
```

CLI flags override config file values. See `./install.sh --help` for all options.

## Defaults

- Python `3.10`
- `uv` virtual environment under `~/.local/share/tpu-dev/envs/<name>`
- JupyterLab enabled by default
- Public Jupyter prompt defaults to yes, protected by a generated token
- Marimo disabled by default; when enabled its public-bind flag mirrors `--public-jupyter` unless `--public-marimo` is set explicitly
- TPU name, zone, project, and external IP are auto-detected from GCP metadata
- Kernel registered as `TPU Dev (<env-name>)`
- Cloudflare quick tunnel optional (print-only)
- No GCP firewall rules are created automatically
- Existing environments are reused unless `--recreate` is passed

## Access

### SSH

There are two ways to SSH into a TPU VM:

**Option A — gcloud (no key setup needed)**

```bash
gcloud compute tpus tpu-vm ssh <TPU_NAME> --zone=<ZONE> --project=<PROJECT>
```

This uses your Google Cloud IAM identity. Anyone with the right IAM roles on
the project can use this command.

**Option B — shared SSH key (for collaborators without gcloud)**

1. Run the installer with `--generate-share-ssh-key yes`:

   ```bash
   ./install.sh --generate-share-ssh-key yes
   ```

   The installer prints the private key path and a plain `ssh` command.

2. Copy the private key to the collaborator:

   ```bash
   cat ~/.ssh/tpu-dev-<env-name>   # copy-paste this output to collaborator
   ```

3. The collaborator saves it locally and connects:

   ```bash
   chmod 600 ~/Downloads/tpu-dev-key
   ssh -i ~/Downloads/tpu-dev-key -o IdentitiesOnly=yes <USER>@<TPU_EXTERNAL_IP>
   ```

4. To also open TCP/22 in GCP's firewall (needed for plain SSH from outside):

   ```bash
   ./install.sh --generate-share-ssh-key yes --public-ssh-open yes
   ```

   This prints the `gcloud compute firewall-rules create` command; run it from
   your laptop or Cloud Shell.

5. To revoke access, remove the matching line from `~/.ssh/authorized_keys` on
   the TPU VM.

**SSH tunnel (port-forward only, no public firewall)**

```bash
gcloud compute tpus tpu-vm ssh <TPU_NAME> --zone=<ZONE> -- \
  -L 8888:127.0.0.1:8888
```

Then open the URL printed by the installer.

## Extra Packages

### Extra pip packages

Use `--extra-pip` (repeatable) for one-off Python packages on top of the
standard groups:

```bash
./install.sh --extra-pip einops --extra-pip triton
```

Or in the `.env` config:

```env
EXTRA_PIP=einops,triton
```

### Extra apt/system packages

Use `--apt-packages` (repeatable) to install additional system packages during
the `apt-get` step:

```bash
./install.sh --apt-packages htop --apt-packages nvtop
```

### Marimo public access

Marimo's bind address is controlled independently from Jupyter:

```bash
./install.sh --marimo yes --public-marimo yes
```

If `--public-marimo` is not set, it defaults to the same value as
`--public-jupyter`. A common mistake is enabling a GCP firewall rule for the
Marimo port but forgetting `--public-marimo yes` — the service will still only
listen on `127.0.0.1` and refuse external connections.

### Public Jupyter

The installer can bind JupyterLab to `0.0.0.0` with a generated token. It prints
firewall commands to run from your laptop or Cloud Shell. Prefer restricting
`--source-ranges` to your current IP/CIDR.

```bash
./install.sh --firewall-source 203.0.113.10/32
```

To let the installer create/update the firewall rule instead of only printing
the command:

```bash
./install.sh --apply-firewall yes --firewall-source 203.0.113.10/32
```

For a research group where the token URL should be reachable from anywhere:

```bash
./install.sh --public-jupyter yes --public-jupyter-open yes
```

This prints a firewall command with `--source-ranges 0.0.0.0/0`. It is public
internet exposure, so rotate the token or stop the service when done.

## Package Groups

Default groups:

- `core`: JupyterLab, Jupyter Server, IPython kernel, packaging basics.
- `tpu`: PyTorch/XLA and TPU runtime support.
- `general-ds`: pandas, scikit-learn, numba, scipy.
- `graphs`: networkx, python-louvain, graphviz.
- `nlp`: gensim, spacy.
- `cayley-graphs`: cayleypy.

Optional groups:

- `llms`: transformers, accelerate, datasets, unsloth.
- `graphml`: torch-geometric, pyg.
- `uis`: streamlit, panel.
- `dev`: ruff, pytest, black, pre-commit.

Example:

```bash
./install.sh --package-groups core,tpu,general-ds,llms,dev
```

PyTorch and PyTorch/XLA are pinned by default and should stay aligned:

```env
TORCH_VERSION=2.9.0
TORCH_XLA_VERSION=2.9.0
```

## Service Commands

```bash
systemctl --user status tpu-jupyter.service
journalctl --user -u tpu-jupyter.service -f
systemctl --user restart tpu-jupyter.service
tpu-status
tpu-workspace
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

## Docker (unsupported)

Docker is not a supported installation path. If you need a container, run
JupyterLab manually:

```bash
docker run --rm -it --privileged --net=host \
  -v "$PWD:/workspace" \
  python:3.10-slim \
  bash -c "pip install jupyterlab torch 'torch_xla[tpu]' -f https://storage.googleapis.com/libtpu-releases/index.html && jupyter lab --ip=0.0.0.0 --no-browser"
```

## Project Structure

```
tpu-dev-bootstrap/
├── bootstrap.sh              # Thin curl|bash entry point
├── install.sh                # Main installer (sources lib/*.sh)
├── tpu-setup.example.env     # Example configuration
├── lib/
│   ├── ui.sh                 # Logging, prompts, parse helpers
│   ├── config.sh             # Config loading (.env)
│   ├── env.sh                # System deps, uv, venv creation
│   ├── packages.sh           # Package group loading and install
│   ├── services.sh           # Systemd service templating
│   ├── firewall.sh           # GCP firewall rule helpers
│   ├── ssh.sh                # SSH key generation
│   └── summary.sh            # Final status output
├── packages/                 # Package group definitions (.txt)
├── scripts/
│   ├── tpu-workspace         # tmux workspace launcher
│   ├── tpu-status            # System/service status dashboard
│   ├── tpu-banner.sh         # Login banner (sourced from .bashrc)
│   └── tpu-smoke.py          # TPU verification script
└── systemd/                  # Service unit templates
```

## Security Notes

- No hardcoded notebook password or token.
- No wildcard CORS configuration.
- Public Jupyter is token-protected, but still should be exposed only to trusted
  IP ranges.
- Firewall rules are printed, not applied (unless `--apply-firewall yes`).
- Re-running the installer reuses the environment; destructive rebuild requires
  `--recreate`.
