#!/usr/bin/env bash
# Port-forward the UI and Keycloak (the browser needs both at fixed localhost ports). Ctrl-C to stop.
# Each forward is retried: kubectl exits when its pod is replaced (e.g. after a re-run of up.sh).
set -euo pipefail
source "$(dirname "$0")/versions.env"
trap 'kill 0' EXIT
keep() { while true; do kubectl port-forward "$@" >/dev/null 2>&1 || true; sleep 2; done; }
keep svc/caipe-keycloak -n "$NAMESPACE" 7080:8080 &
keep svc/caipe-caipe-ui -n "$NAMESPACE" 3000:3000 &
echo "UI http://localhost:3000   Keycloak http://localhost:7080"
wait
