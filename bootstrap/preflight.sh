#!/usr/bin/env bash
# Is this laptop ready for the workshop?   ./bootstrap/preflight.sh      (up.sh runs it too)
# Works on macOS (arm64/Intel), Linux (amd64/arm64) and Windows WSL2. Blockers (x) exit 1; warnings (!) never do.
# Optional: set LITELLM_URL (ending in /v1), LITELLM_API_KEY, LITELLM_MODEL to also check the model proxy.
# Written for bash 3.2 (macOS default): no associative arrays, no ${var,,}.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source bootstrap/versions.env

fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=1; }

# --- platform -------------------------------------------------------------------------------------------------
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) arch=unknown ;;
esac
case "$(uname -s)" in
  Darwin) plat=macos; os=darwin ;;
  Linux)
    os=linux
    if grep -qi microsoft /proc/version 2>/dev/null; then
      if uname -r | grep -qi 'wsl2'; then plat=wsl2; else plat=wsl1; fi
    else plat=linux; fi ;;
  *) plat=unsupported; os=unknown ;;
esac
printf '\033[1m==> Pre-flight (%s, %s)\033[0m\n' "$plat" "$arch"
case "$plat" in
  macos|linux|wsl2) ok "platform $plat/$arch" ;;
  wsl1) bad "this is WSL1, which cannot run Docker/kind. Convert: wsl --set-version <distro> 2 (run in Windows PowerShell)" ;;
  *) bad "unsupported OS $(uname -s). Use macOS, Linux or Windows with WSL2 (docs/platform-setup.md)" ;;
esac
[ "$arch" != unknown ] || bad "unsupported CPU $(uname -m)"

# --- tools ----------------------------------------------------------------------------------------------------
hint() {
  case "$1" in
    kind)       echo "curl -fsSLo ~/.local/bin/kind https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-$os-$arch && chmod +x ~/.local/bin/kind   (mkdir -p ~/.local/bin; add it to PATH)" ;;
    docker)     echo "Docker Desktop, Colima/OrbStack (macOS), or Docker Engine (Linux/WSL2): see docs/platform-setup.md" ;;
    *)          echo "see docs/platform-setup.md" ;;
  esac
}
for c in docker kind kubectl helm curl openssl python3; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c"; else bad "missing '$c': $(hint "$c")"; fi
done
if command -v kind >/dev/null 2>&1; then
  # the node image ($KIND_NODE_IMAGE) is built for this kind release
  v=$(kind version 2>&1 | head -1)
  case "$v" in *"$KIND_VERSION "*) ;; *) warn "kind is '$v', the workshop is tested with $KIND_VERSION" ;; esac
fi

# --- Docker ---------------------------------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  if ! docker info >/dev/null 2>&1; then
    bad "Docker is installed but not running (or your user cannot reach it: Linux needs 'sudo usermod -aG docker \$USER' then a new login)"
  else
    ok "Docker is running"
    docker info 2>/dev/null | grep -qi podman && warn "Podman detected: best-effort only, not tested (docs/platform-setup.md)"
    mem_gib=$(docker info --format '{{.MemTotal}}' | awk '{printf "%d", $1/1073741824}')
    if [ "$mem_gib" -ge 11 ]; then ok "Docker memory ${mem_gib} GiB"; else
      msg="Docker has ~${mem_gib} GiB, the stack needs 12 GB."
      case "$plat" in
        wsl2) msg="$msg Create %UserProfile%\\.wslconfig on Windows with [wsl2] memory=14GB, then run 'wsl --shutdown'." ;;
        macos) msg="$msg Docker Desktop > Settings > Resources (Colima: colima start --memory 14)." ;;
      esac
      bad "$msg"
    fi
    cpus=$(docker info --format '{{.NCPU}}'); [ "$cpus" -ge 4 ] && ok "Docker CPUs $cpus" || warn "Docker has $cpus CPUs; 4+ recommended (a cold build will be slow)"
    darch=$(docker info --format '{{.Architecture}}')
    case "$darch" in
      x86_64) darch=amd64 ;;
      aarch64) darch=arm64 ;;
    esac
    [ "$darch" = "$arch" ] || [ "$arch" = unknown ] || warn "Docker runs $darch but this machine is $arch: everything is emulated and will be very slow"
  fi
fi

# --- disk, filesystem, kernel limits -----------------------------------------------------------------------------
free_gb=$(df -Pk . | awk 'NR==2{printf "%d", $4/1048576}')
[ "$free_gb" -ge 30 ] && ok "free disk ${free_gb} GB" || warn "only ${free_gb} GB free here; images and the cluster need ~25 GB"
case "$PWD" in /mnt/[a-z]/*) warn "repo is on the Windows drive ($PWD): very slow and file permissions break. Clone into your WSL home (~/) instead" ;; esac
if [ "$plat" = linux ] || [ "$plat" = wsl2 ]; then
  inst=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)
  [ "$inst" -ge 512 ] && ok "inotify instances $inst" ||
    warn "fs.inotify.max_user_instances=$inst; pods fail with 'too many open files'. Fix: sudo sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_user_watches=524288"
fi

# --- names and ports ------------------------------------------------------------------------------------------------
resolved=$(python3 -c "import socket;print(socket.gethostbyname('gitea.caipe.localtest.me'))" 2>/dev/null || true)
if [ "$resolved" = 127.0.0.1 ]; then ok "gitea.caipe.localtest.me -> 127.0.0.1"; else
  bad "gitea.caipe.localtest.me does not resolve to 127.0.0.1 (got '${resolved:-nothing}'). Corporate DNS, Tailscale and routers block this. Fix once: echo '127.0.0.1 gitea.caipe.localtest.me argocd.caipe.localtest.me' | sudo tee -a /etc/hosts$([ "$plat" = wsl2 ] && echo '   (and the same line in C:\Windows\System32\drivers\etc\hosts from an admin editor, for your Windows browser)')"
fi
if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  ok "cluster '$CLUSTER_NAME' already exists (ports are in use by it)"
else
  for p in 8443 3000 7080; do
    if python3 -c "import socket,sys;s=socket.socket();s.settimeout(1);sys.exit(0 if s.connect_ex(('127.0.0.1',$p))==0 else 1)"; then
      bad "port $p is already in use on this machine; stop whatever listens on it"
    fi
  done
  ok "ports 8443, 3000, 7080 are free"
fi

# --- network ------------------------------------------------------------------------------------------------------
[ -n "${HTTPS_PROXY:-}${https_proxy:-}" ] && warn "an HTTPS proxy is set: the Docker daemon needs its own proxy setting too, or image pulls hang (docs/platform-setup.md)"
case "$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://ghcr.io/v2/)" in
  200|401) ok "can reach ghcr.io" ;;
  *) warn "cannot reach ghcr.io (needed for the CAIPE chart and images). Use a pre-pull tarball: ./bootstrap/prepull.sh --load images.tar" ;;
esac

# --- model proxy ---------------------------------------------------------------------------------------------------
if [ -n "${LITELLM_URL:-}" ] && [ -n "${LITELLM_API_KEY:-}" ]; then
  want="${LITELLM_MODEL:-claude-5.5-haiku}"
  tmp=$(mktemp)
  code=$(curl -s -m 15 -o "$tmp" -w '%{http_code}' -H "Authorization: Bearer $LITELLM_API_KEY" "${LITELLM_URL%/}/models")
  if [ "$code" != 200 ]; then bad "model proxy answered HTTP $code on ${LITELLM_URL%/}/models (URL must end in /v1; check the key)"
  else
    for m in "$want" text-embedding-3-small; do # the embeddings model is fixed in platform/caipe/rag.yaml (runbook search)
      if python3 -c "import sys,json;sys.exit(0 if '$m' in [x['id'] for x in json.load(open('$tmp'))['data']] else 1)"; then ok "model proxy serves $m"
      else bad "model proxy does not serve '$m' (docs/attendee-prerequisites.md)"; fi
    done
  fi
  rm -f "$tmp"
else
  warn "LITELLM_URL / LITELLM_API_KEY not set (up.sh needs them; set them to also check the model here)"
fi

echo
if [ "$fail" -eq 0 ]; then printf '\033[32mReady.\033[0m\n'; else printf '\033[31mNot ready: fix the lines marked x, then run this again.\033[0m\n'; fi
exit "$fail"
