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
  --marimo yes \
  --public-marimo yes \
  --torch-version 2.9.0 \
  --torch-xla-version 2.9.0
```

Research group setup (public Jupyter + Marimo + SSH key for collaborators):

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/install.sh | bash -s -- \
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
curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/install.sh | bash -s -- \
  --config https://raw.githubusercontent.com/<org>/<repo>/main/tpu-setup.example.yaml
```

## Defaults

- Python `3.10`
- `uv` virtual environment under `~/.local/share/tpu-dev/envs/<name>`
- JupyterLab enabled by default
- Public Jupyter prompt defaults to yes, protected by a generated token
- Marimo disabled by default; when enabled its public-bind flag mirrors `--public-jupyter` unless `--public-marimo` is set explicitly
- TPU name, zone, project, and external IP are auto-detected from GCP metadata
- Kernel registered as `TPU Dev (<env-name>)`
- Cloudflare quick tunnel optional
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

**Shared SSH key (legacy flag reference)**

```bash
./install.sh --generate-share-ssh-key yes
```

The installer creates an Ed25519 keypair and automatically adds the public key
to the current VM's `~/.ssh/authorized_keys`. It prints the private key path,
plain `ssh -i ... user@host` command for collaborators without `gcloud`, and an
easy `cat <private-key>` command for copy/paste sharing. Share the private key
only with trusted collaborators and remove the public key from `authorized_keys`
to revoke access.

If collaborators should use plain SSH from anywhere, also open SSH publicly:

```bash
./install.sh --generate-share-ssh-key yes --public-ssh-open yes --ssh-port 22
```

This prints a `gcloud compute firewall-rules create ... --allow tcp:<port>` command
with `--source-ranges 0.0.0.0/0`. Use a narrower CIDR when you know the group IP
ranges.

## Extra packages

### Extra pip packages

Use `--extra-pip` (repeatable) for one-off Python packages on top of the
standard groups:

```bash
./install.sh --extra-pip einops --extra-pip triton
```

Or in the YAML config:

```yaml
extra_pip:
  - einops
  - triton
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

Public Jupyter:

The installer can bind JupyterLab to `0.0.0.0` with a generated token. It prints
firewall commands to run from your laptop or Cloud Shell. Prefer restricting
`--source-ranges` to your current IP/CIDR.

`--source-ranges` means "which client IPs are allowed to connect." When the
installer runs on the TPU VM, automatic detection may see the TPU VM's outbound
IP, not your laptop IP. Prefer passing your local IP explicitly:

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

If Marimo is enabled, the installer also prints a concrete public Marimo URL and
a separate Marimo firewall command for the Marimo port.

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
