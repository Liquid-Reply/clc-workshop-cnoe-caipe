#!/usr/bin/env bash
# Single-command workshop bootstrap: kind + ArgoCD + Gitea behind agentgateway + CAIPE (UI, Dynamic Agents,
# agentgateway, Keycloak, OpenFGA). Idempotent: safe to re-run.
#   LITELLM_URL=https://.../v1 LITELLM_API_KEY=... ./bootstrap/up.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source bootstrap/versions.env
LITELLM_MODEL="${LITELLM_MODEL:-claude-5.5-haiku}" # Claude 5.x rejects temperature=0 (CAIPE's default), so llm-secret sets OPENAI_TEMPERATURE=1
log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

log "Pre-flight"
[ -n "${LITELLM_URL:-}" ] && [ -n "${LITELLM_API_KEY:-}" ] || die "set LITELLM_URL (ending in /v1) and LITELLM_API_KEY"
LITELLM_MODEL=$LITELLM_MODEL bootstrap/preflight.sh || die "pre-flight failed; fix the lines marked x above (details: docs/platform-setup.md)"

# Images pre-pulled by prepull.sh are pushed into the new kind node before anything is installed, so pods never pull
# from a registry (conference Wi-Fi, Docker Hub rate limits). Loading in the background raced the installs and lost.
# ponytail: best-effort; anything not pre-pulled is simply pulled by the node as usual.
load_images() {
  local refs=() ref
  while read -r ref _; do
    case "$ref" in '#'*|'') continue ;; docker.io/kindest/node:*) continue ;; esac
    docker image inspect "$ref" >/dev/null 2>&1 && refs+=("$ref")
  done < bootstrap/images.lock
  [ "${#refs[@]}" -gt 0 ] || return 0
  echo "loading ${#refs[@]} pre-pulled images into the node"
  # not 'kind load docker-image': it imports --all-platforms, which fails on Docker's containerd image store (only this
  # machine's platform is stored). A single-platform archive loads on both image stores. One image per archive, because
  # 'docker save --platform' rejects some images (e.g. Crossplane packages) and would fail the whole batch.
  local plat=() dir failed=()
  docker save --help 2>/dev/null | grep -q -- '--platform' \
    && plat=(--platform "linux/$(docker info --format '{{.Architecture}}' | sed 's/x86_64/amd64/;s/aarch64/arm64/')")
  dir=$(mktemp -d)
  for ref in "${refs[@]}"; do
    { docker save ${plat[@]+"${plat[@]}"} -o "$dir/image.tar" "$ref" || docker save -o "$dir/image.tar" "$ref"; } >/dev/null 2>&1 \
      && kind load image-archive "$dir/image.tar" --name "$CLUSTER_NAME" >/dev/null 2>&1 || failed+=("$ref")
  done
  rm -rf "$dir"
  [ "${#failed[@]}" -eq 0 ] || echo "WARN: not preloaded, the node will pull: ${failed[*]}"
}
missing=0
for ref in $(grep -v '^#' bootstrap/images.lock | awk '{print $1}'); do docker image inspect "$ref" >/dev/null 2>&1 || missing=$((missing+1)); done
[ "$missing" -eq 0 ] || echo "WARN: $missing images not pre-pulled (run ./bootstrap/prepull.sh first; needed on slow networks)"

log "Cluster ($CLUSTER_NAME)"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  # a cluster from the idpbuilder-based bootstrap cannot be upgraded in place: its ArgoCD and Gitea are not Helm
  # releases (helm refuses to adopt them) and ingress-nginx holds port 8443
  ! kubectl --context "kind-$CLUSTER_NAME" get namespace ingress-nginx >/dev/null 2>&1 \
    || die "cluster '$CLUSTER_NAME' was built by the earlier idpbuilder-based up.sh; delete it first: ./bootstrap/down.sh"
  echo "cluster exists, reusing"
else
  kind create cluster --name "$CLUSTER_NAME" --image "$KIND_NODE_IMAGE" --config bootstrap/kind.yaml --wait 5m \
    || die "kind create cluster failed"
  load_images
fi
kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null

# chart source: the tarball prepull.sh cached in .cache/ (no network), else the upstream repo
# (--repo installs run with HELM_REPOSITORY_CONFIG=/dev/null, see Crossplane below)
chart_src() { # name version repo (https URL or oci:// base); sets $chart
  if [ -f ".cache/$1-$2.tgz" ]; then chart=(".cache/$1-$2.tgz")
  elif [[ "$3" == oci://* ]]; then chart=("$3/$1" --version "$2")
  else chart=("$1" --repo "$3" --version "$2"); fi
}

log "Gateway API + agentgateway $AGENTGATEWAY_VERSION"
if [ -f .cache/gateway-api.yaml ]; then kubectl apply -f .cache/gateway-api.yaml >/dev/null
else kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/$GATEWAY_API_VERSION/standard-install.yaml" >/dev/null; fi
chart_src agentgateway-crds "$AGENTGATEWAY_VERSION" "$AGENTGATEWAY_CHARTS"
helm upgrade -i agentgateway-crds "${chart[@]}" --create-namespace -n agentgateway-system >/dev/null
chart_src agentgateway "$AGENTGATEWAY_VERSION" "$AGENTGATEWAY_CHARTS"
helm upgrade -i agentgateway "${chart[@]}" -n agentgateway-system --wait --timeout 5m >/dev/null

log "Argo CD + Gitea $GITEA_VERSION"
chart_src "$ARGOCD_CHART" "$ARGOCD_CHART_VERSION" "$ARGOCD_CHART_REPO"
HELM_REPOSITORY_CONFIG=/dev/null helm upgrade -i argocd "${chart[@]}" -n argocd --create-namespace -f platform/argocd/values.yaml --wait --timeout 10m >/dev/null
kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# create once, never overwrite: re-runs keep the same admin password
kubectl get secret gitea-credential -n gitea >/dev/null 2>&1 || kubectl create secret generic gitea-credential -n gitea \
  --from-literal=username=giteaAdmin --from-literal=password="$(openssl rand -hex 16)" >/dev/null
chart_src "$GITEA_CHART" "$GITEA_CHART_VERSION" "$GITEA_CHART_REPO"
HELM_REPOSITORY_CONFIG=/dev/null helm upgrade -i my-gitea "${chart[@]}" -n gitea -f platform/gitea/values.yaml --set image.tag="$GITEA_VERSION" --wait --timeout 10m >/dev/null

log "Platform gateway (https://gitea.caipe.localtest.me:8443, https://argocd.caipe.localtest.me:8443)"
if ! kubectl get secret platform-tls -n agentgateway-system >/dev/null 2>&1; then
  tls=$(mktemp -d)
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj '/CN=caipe.localtest.me' \
    -addext 'subjectAltName=DNS:caipe.localtest.me,DNS:*.caipe.localtest.me' -keyout "$tls/tls.key" -out "$tls/tls.crt" 2>/dev/null
  kubectl create secret tls platform-tls -n agentgateway-system --cert "$tls/tls.crt" --key "$tls/tls.key" >/dev/null
  rm -rf "$tls"
fi
kubectl apply -f platform/gateway.yaml >/dev/null
kubectl wait --for=condition=Programmed gateway/platform -n agentgateway-system --timeout=300s >/dev/null
until curl -skf -o /dev/null https://gitea.caipe.localtest.me:8443/api/healthz; do sleep 2; done

log "Secrets"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# create once, never overwrite: re-runs keep the same passwords
ensure_secret() { # name, then key=value args; key=@gen means random hex
  local name=$1; shift
  kubectl get secret "$name" -n "$NAMESPACE" >/dev/null 2>&1 && return 0
  local args=() kv
  for kv in "$@"; do args+=("--from-literal=${kv%%=*}=$([ "${kv#*=}" = "@gen" ] && openssl rand -hex 16 || echo "${kv#*=}")"); done
  kubectl create secret generic "$name" -n "$NAMESPACE" "${args[@]}" >/dev/null
}
# LLM secret always refreshed (key/model may change between runs)
# values go through a pipe (--from-env-file), not argv, so the key never shows up in `ps`
kubectl create secret generic llm-secret -n "$NAMESPACE" --from-env-file=<(printf '%s\n' \
  LLM_PROVIDER=openai "OPENAI_API_KEY=$LITELLM_API_KEY" "OPENAI_ENDPOINT=$LITELLM_URL" "OPENAI_API_BASE=$LITELLM_URL" "OPENAI_BASE_URL=$LITELLM_URL" "OPENAI_MODEL_NAME=$LITELLM_MODEL" OPENAI_TEMPERATURE=1) \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ensure_secret caipe-platform-secret OIDC_CLIENT_SECRET=@gen
ensure_secret caipe-ui-secret NEXTAUTH_SECRET=@gen OIDC_CLIENT_ID=caipe-ui OIDC_CLIENT_SECRET=caipe-ui-dev-secret \
  AGENTGATEWAY_TARGETS_TOKEN=@gen CAIPE_AGENT_CONTEXT_HMAC_SECRET=@gen # ponytail: caipe-ui-dev-secret is the public dev-realm default for the caipe-ui client
ensure_secret keycloak-admin-bootstrap password=@gen
ensure_secret caipe-local-admin email=admin@caipe.local password=@gen
ensure_secret caipe-local-user email=user@caipe.local password=@gen
sget() { kubectl get secret "$1" -n "$NAMESPACE" -o jsonpath="{.data.$2}" | base64 -d; }

log "CAIPE $CAIPE_CHART_VERSION"
caipe_chart=$(ls .cache/ai-platform-engineering-*.tgz 2>/dev/null | head -1 || true)
if [ -n "$caipe_chart" ]; then chart_args=("$caipe_chart"); else chart_args=("$CAIPE_CHART" --version "$CAIPE_CHART_VERSION"); fi
helm upgrade -i caipe "${chart_args[@]}" -n "$NAMESPACE" \
  -f platform/caipe/values.yaml -f platform/caipe/rag.yaml --set "keycloak.admin.password=$(sget keycloak-admin-bootstrap password)" --timeout 10m >/dev/null
kubectl wait --for=condition=Available deploy --all -n "$NAMESPACE" --timeout=600s
# env/secret changes only reach pods on restart (envFrom is read at start)
kubectl rollout restart deploy/caipe-dynamic-agents deploy/caipe-caipe-ui -n "$NAMESPACE" >/dev/null
kubectl rollout status deploy/caipe-dynamic-agents -n "$NAMESPACE" --timeout=300s >/dev/null
kubectl rollout status deploy/caipe-caipe-ui -n "$NAMESPACE" --timeout=300s >/dev/null

log "Keycloak users"
bootstrap/users.sh

# MCP base image (Python + FastMCP): built locally, code arrives from Git via ConfigMap
docker image inspect workshop/mcp-base:1 >/dev/null 2>&1 || docker build -q -t workshop/mcp-base:1 platform/images/mcp-base >/dev/null
docker exec "$CLUSTER_NAME-control-plane" crictl images 2>/dev/null | grep -q mcp-base || kind load docker-image workshop/mcp-base:1 --name "$CLUSTER_NAME" >/dev/null

log "Crossplane $CROSSPLANE_CHART_VERSION"
# empty repo config: a stale personal ~/.config/helm/repositories.yaml (repos never cached) otherwise breaks --repo installs
HELM_REPOSITORY_CONFIG=/dev/null helm upgrade -i crossplane crossplane --repo https://charts.crossplane.io/stable --version "$CROSSPLANE_CHART_VERSION" \
  -n crossplane-system --create-namespace --wait --timeout 5m >/dev/null
kubectl apply -f crossplane/function.yaml >/dev/null
kubectl wait --for=condition=Healthy function/function-go-templating --timeout=300s >/dev/null
kubectl apply -f crossplane/xrd.yaml >/dev/null
kubectl wait --for=condition=Established xrd/teamenvironments.platform.workshop.io --timeout=60s >/dev/null
kubectl apply -f crossplane/composition.yaml -f crossplane/rbac.yaml >/dev/null

log "Workload (Gitea repo, ArgoCD apps: Prometheus, sample app)"
bootstrap/apps.sh
bootstrap/gitea-bot.sh

log "Runbooks (RAG)"
kubectl wait --for=condition=Available deploy/rag-server -n "$NAMESPACE" --timeout=600s
bootstrap/runbooks.sh

log "Agents and MCP servers"
bootstrap/agents.sh

log "Done"
cat <<MSG
Next:   ./bootstrap/forward.sh            # keeps port-forwards to the UI (3000) and Keycloak (7080) running
Open:   http://localhost:3000   (Sign in with SSO)
Login:  admin@caipe.local / user@caipe.local
        kubectl get secret caipe-local-admin -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d
Gitea:  https://gitea.caipe.localtest.me:8443   giteaAdmin / kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' | base64 -d
ArgoCD: https://argocd.caipe.localtest.me:8443  admin / kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
        (self-signed certificate: accept the browser warning)
Tear down: ./bootstrap/down.sh
MSG
