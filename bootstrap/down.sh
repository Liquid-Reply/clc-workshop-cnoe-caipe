#!/usr/bin/env bash
# Delete the whole workshop cluster (agenda module 5: "kind delete cluster localdev").
set -euo pipefail
source "$(dirname "$0")/versions.env"
kind delete cluster --name "$CLUSTER_NAME"
