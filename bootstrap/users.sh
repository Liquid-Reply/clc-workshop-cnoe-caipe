#!/usr/bin/env bash
# Upsert the two realm users. Keycloak runs on embedded H2, so a Keycloak pod restart wipes them: re-run this.
set -euo pipefail
source "$(dirname "$0")/versions.env"
sget() { kubectl get secret "$1" -n "$NAMESPACE" -o jsonpath="{.data.$2}" | base64 -d; }
kubectl port-forward svc/caipe-keycloak -n "$NAMESPACE" 17080:8080 >/dev/null 2>&1 &
pf=$!; trap 'kill $pf 2>/dev/null || true' EXIT
kc=http://localhost:17080
for _ in $(seq 1 30); do curl -sf "$kc/realms/caipe" >/dev/null 2>&1 && break; sleep 2; done
tok=$(curl -s "$kc/realms/master/protocol/openid-connect/token" -d grant_type=password -d client_id=admin-cli \
  --data-urlencode username=admin --data-urlencode "password=$(sget keycloak-admin-bootstrap password)" \
  | python3 -I -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
for n in admin user; do
  email=$(sget "caipe-local-$n" email); pw=$(sget "caipe-local-$n" password)
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' \
    "$kc/admin/realms/caipe/users" -d "{\"username\":\"$email\",\"email\":\"$email\",\"emailVerified\":true,\"enabled\":true,\"firstName\":\"CAIPE\",\"lastName\":\"$n\",\"credentials\":[{\"type\":\"password\",\"value\":\"$pw\",\"temporary\":false}]}")
  case $code in 201) echo "created $email";; 409) echo "exists  $email";; *) echo "ERROR: $email -> HTTP $code" >&2; exit 1;; esac
done
