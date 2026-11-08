#!/usr/bin/env bash
# Pre-pull every image (and chart) the workshop needs, so the cluster never waits on conference Wi-Fi.
#   ./bootstrap/prepull.sh                 pull images by locked digest + cache charts (run 48 h before)
#   ./bootstrap/prepull.sh --save FILE     also write a tarball for stragglers (arch-specific: build on the same CPU type)
#   ./bootstrap/prepull.sh --load FILE     load such a tarball (no network needed)
# up.sh loads these images into the kind node automatically.
set -euo pipefail
cd "$(dirname "$0")"
source versions.env
case "${1:-}" in
  --load) docker load -i "${2:?usage: --load FILE}"; exit 0 ;;
esac
docker info >/dev/null 2>&1 || { echo "Docker is not running" >&2; exit 1; }
imgs=()
while read -r ref digest; do
  case "$ref" in '#'*|'') continue ;; esac
  echo "pull $ref"
  docker pull -q "${ref%:*}@$digest" >/dev/null   # by digest: exactly what was tested
  docker tag "${ref%:*}@$digest" "$ref"           # tag name = what the pod specs use
  imgs+=("$ref")
done < images.lock
echo "build workshop/mcp-base:1"
docker build -q -t workshop/mcp-base:1 ../platform/images/mcp-base >/dev/null
imgs+=(workshop/mcp-base:1)
mkdir -p ../.cache
echo "cache helm charts + CRDs"
helm pull "$CAIPE_CHART" --version "$CAIPE_CHART_VERSION" -d ../.cache >/dev/null
helm pull "$AGENTGATEWAY_CHARTS/agentgateway-crds" --version "$AGENTGATEWAY_VERSION" -d ../.cache >/dev/null
helm pull "$AGENTGATEWAY_CHARTS/agentgateway" --version "$AGENTGATEWAY_VERSION" -d ../.cache >/dev/null
HELM_REPOSITORY_CONFIG=/dev/null helm pull "$ARGOCD_CHART" --repo "$ARGOCD_CHART_REPO" --version "$ARGOCD_CHART_VERSION" -d ../.cache >/dev/null
HELM_REPOSITORY_CONFIG=/dev/null helm pull "$GITEA_CHART" --repo "$GITEA_CHART_REPO" --version "$GITEA_CHART_VERSION" -d ../.cache >/dev/null
curl -fsSL -o ../.cache/gateway-api.yaml "https://github.com/kubernetes-sigs/gateway-api/releases/download/$GATEWAY_API_VERSION/standard-install.yaml"
if [ "${1:-}" = --save ]; then
  docker save -o "${2:?usage: --save FILE}" "${imgs[@]}"
  echo "wrote $2 ($(du -h "$2" | cut -f1))"
fi
echo "done: ${#imgs[@]} images"
