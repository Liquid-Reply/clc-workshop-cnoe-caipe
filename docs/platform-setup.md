# Laptop setup: macOS, Linux and Windows (WSL2)

Everything runs in a local kind cluster in Docker, driven by bash scripts. So the platform question is only: *can this laptop run Docker with 12 GB, and run bash?*

After installing the tools, one command tells you whether you are ready (and what to fix):

```bash
./bootstrap/preflight.sh
```

## What is verified

| Platform | Status |
|---|---|
| macOS arm64 (Apple silicon), Colima or Docker Desktop | **Tested end to end**: fresh install, all five labs, `smoke.sh --guardrails` (Colima, 6 CPU, 12.5 GB). |
| Linux amd64 | **Partly verified.** All 33 registry images have `linux/amd64` (the 34th, `workshop/mcp-base`, is built locally); the install commands below run on amd64; `preflight.sh` runs on amd64 Ubuntu 24.04. A full cluster run is done by the `linux-amd64` GitHub workflow (see "Sign-off"). |
| macOS Intel | Same images and scripts as Linux amd64; **not tested** on hardware. |
| Windows 10/11 with WSL2 (Ubuntu) | **Documented, not tested.** It is Linux amd64 inside a VM; the risks are memory, Windows-side name resolution and line endings, handled below. |
| Linux arm64, Windows on ARM (WSL2) | Images are multi-arch; **not tested**. |
| Podman, Rancher Desktop | Best effort, not supported. |
| WSL1, native Windows (cmd/PowerShell) | **Not supported.** |

## Common requirements

- Docker with **12 GB RAM** and 4+ CPUs for the Docker VM (a laptop with 16 GB total is the practical floor), 30 GB free disk.
- Tools: `docker kind kubectl helm curl openssl python3` (kind `v0.33.0`; see `bootstrap/versions.env`).
- Free ports 8443, 3000, 7080 on localhost.
- Either DNS that resolves `*.localtest.me` (public DNS points it to 127.0.0.1) or a `/etc/hosts` entry (below).
- Run everything from the repo root, in a terminal that has bash.

## macOS

```bash
brew install kind helm kubectl
```

Docker: Docker Desktop (Settings > Resources > Memory 12 GB+) **or** Colima: `brew install colima docker && colima start --cpu 6 --memory 14 --disk 60`.
Copy the Keycloak password with `... | base64 -d | pbcopy` (prevents zsh's trailing `%`).

## Linux (amd64 or arm64)

```bash
ARCH=$(uname -m | sed -e s/x86_64/amd64/ -e s/aarch64/arm64/)
mkdir -p ~/.local/bin && export PATH=$HOME/.local/bin:$PATH      # add to ~/.bashrc
curl -fsSLo ~/.local/bin/kind    https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-$ARCH && chmod +x ~/.local/bin/kind
curl -fsSLo ~/.local/bin/kubectl https://dl.k8s.io/release/v1.37.0/bin/linux/$ARCH/kubectl && chmod +x ~/.local/bin/kubectl
curl -fsSL https://get.helm.sh/helm-v4.2.3-linux-$ARCH.tar.gz | tar xz -C /tmp && mv /tmp/linux-$ARCH/helm ~/.local/bin/
```

Docker Engine (not rootless): follow <https://docs.docker.com/engine/install/>, then `sudo usermod -aG docker $USER` and log in again.
**Raise the inotify limits** or pods fail with "too many open files" (Ubuntu's default is 128 instances):

```bash
printf 'fs.inotify.max_user_instances=1024\nfs.inotify.max_user_watches=524288\n' | sudo tee /etc/sysctl.d/99-workshop.conf && sudo sysctl --system
```

Copy the password with `... | base64 -d | xclip -selection clipboard` or just print it: `... | base64 -d; echo`.

## Windows 11/10 with WSL2

Do **everything inside the WSL Ubuntu terminal**; only the browser runs on Windows.

1. In an admin PowerShell: `wsl --install -d Ubuntu-24.04`, reboot, create the Linux user.
2. Give WSL enough memory: create `%UserProfile%\.wslconfig` on Windows:
   ```
   [wsl2]
   memory=14GB
   processors=4
   swap=4GB
   ```
   then `wsl --shutdown` in PowerShell and reopen Ubuntu. (WSL defaults to half your RAM; a 16 GB laptop gets only 8 GB and fails preflight.)
3. Docker, pick one:
   - **Docker Desktop** with Settings > Resources > WSL integration enabled for Ubuntu (needs a Docker licence at some companies);
   - **Docker Engine inside WSL**: add `[boot]\nsystemd=true` to `/etc/wsl.conf`, `wsl --shutdown`, then follow the Linux steps above (`curl -fsSL https://get.docker.com | sh`).
4. Install the tools with the **Linux** commands above (including the inotify setting).
5. **Clone into your WSL home** (`cd ~ && git clone ...`), never under `/mnt/c`: it is very slow and breaks file permissions. This repo forces LF line endings (`.gitattributes`); if you cloned with Windows git anyway, delete the folder and clone again inside WSL.
6. Open <http://localhost:3000> in your **Windows** browser: WSL2 forwards localhost ports to Windows by default.
7. If `*.localtest.me` does not resolve (corporate DNS), add the `/etc/hosts` line below **in WSL** (also set `[network]\ngenerateHosts=false` in `/etc/wsl.conf` so it survives restarts) **and** in `C:\Windows\System32\drivers\etc\hosts` (admin editor) for the browser.
8. Copy the password with `... | base64 -d | clip.exe`.

## The `/etc/hosts` line (any OS, only if preflight says the name does not resolve)

```bash
echo '127.0.0.1 gitea.caipe.localtest.me argocd.caipe.localtest.me' | sudo tee -a /etc/hosts
```

## Kinds of attendee and what to do

| Attendee | Plan |
|---|---|
| Mac or Linux laptop, 16 GB+, admin rights | Steps above, then `preflight.sh`, then Module 1. |
| Windows laptop | WSL2 section. Ask them to run the WSL steps **before** the day; it needs a reboot and admin rights. |
| No admin rights (cannot install Docker, edit hosts, set `.wslconfig`) | Cannot run the stack locally. **Open decision**: facilitator provides a shared cloud VM or a pair-up with a neighbour (see PLAN section 7). |
| 8 GB RAM, or a laptop that cannot give Docker 12 GB | Same as above; do not attempt it, a half-starved stack fails in confusing ways. |
| Corporate proxy / restricted network | Set the proxy on the **Docker daemon** too (Docker Desktop > Resources > Proxies, or a systemd drop-in on Linux) and `export NO_PROXY=localhost,127.0.0.1,.localtest.me,.svc,.cluster.local`. Untested here. If `ghcr.io` is blocked: load the pre-pull tarball. |
| Slow or no internet at the venue | `./bootstrap/prepull.sh` 48 h ahead, or `./bootstrap/prepull.sh --load images.tar` from a USB stick. **The tarball is per CPU type**: build one on an arm64 machine and one on amd64 (`--save`). |
| Apple silicon / Intel Mac / Linux / WSL2 mix in one room | Fine: images are multi-arch and pinned by digest; only the tarball differs. |
| Podman or Rancher Desktop | Best effort, not supported. Switch to Docker Desktop, Colima or Docker Engine. |

## Sign-off per platform (run once per platform, record the result)

```bash
./bootstrap/preflight.sh
LITELLM_URL=https://<host>/v1 LITELLM_API_KEY=<key> ./bootstrap/up.sh     # note the time
LITELLM_URL=... LITELLM_API_KEY=... ./bootstrap/smoke.sh --guardrails     # headless checks, no browser
# then the UI smoke test from modules/01-install/lab.md section 5, and ./bootstrap/down.sh
```

Linux amd64 can be signed off without a machine: GitHub > Actions > **linux-amd64** > Run workflow (needs the `LITELLM_URL` and `LITELLM_API_KEY` repository secrets and a runner with 16 GB RAM; set the repository variable `E2E_RUNNER` to a larger runner label if `ubuntu-latest` has less).

| Platform | Date | Result | up.sh time |
|---|---|---|---|
| macOS arm64 (Colima, 6 CPU / 12.5 GB) | 2026-11-05 | pass, all labs | 686 s cold (no pre-pull), 54 s re-run |
| Linux amd64 | pending | | |
| Windows 11 + WSL2 | pending | | |
| macOS Intel | pending | | |
