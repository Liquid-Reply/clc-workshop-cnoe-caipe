#!/usr/bin/env bash
# Headless health check of a running workshop stack (no browser). Used by CI and for rehearsals on any laptop.
#   ./bootstrap/smoke.sh               pods, ArgoCD apps, model call, MCP tools, Gitea
#   ./bootstrap/smoke.sh --guardrails  also Module 5: soft mode ALLOWED, hardened mode DENIED, branch protection (leaves soft mode on)
# Needs LITELLM_URL / LITELLM_API_KEY for the model call (skipped with a note if unset).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
source bootstrap/versions.env

pass=0; failed=0
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; failed=$((failed+1)); }
until_ok() { # until_ok <seconds> <cmd...>: retry every 5 s
  local end=$((SECONDS+$1)); shift
  until "$@" >/dev/null 2>&1; do [ "$SECONDS" -ge "$end" ] && return 1; sleep 5; done
}

printf '\033[1m==> Smoke test\033[0m\n'

pods_settled() { [ -z "$(kubectl get pods -A --no-headers | grep -v -E ' (Running|Completed) ')" ]; }
if until_ok 300 pods_settled; then ok "all pods Running/Completed ($(kubectl get pods -A --no-headers | wc -l | tr -d ' '))"
else bad "pods not settled: $(kubectl get pods -A --no-headers | grep -v -E ' (Running|Completed) ' | awk '{print $2"="$4}' | tr '\n' ' ')"; fi

apps_ready() { [ "$(kubectl get applications -n argocd --no-headers -o custom-columns=S:.status.sync.status,H:.status.health.status | grep -c -x 'Synced *Healthy')" -ge 5 ]; }
if until_ok 300 apps_ready; then ok "ArgoCD: 5 apps Synced and Healthy"
else bad "ArgoCD apps not ready: $(kubectl get applications -n argocd --no-headers -o custom-columns=N:.metadata.name,S:.status.sync.status,H:.status.health.status | tr '\n' ';')"; fi

if [ -n "${LITELLM_URL:-}" ] && [ -n "${LITELLM_API_KEY:-}" ]; then
  model="${LITELLM_MODEL:-claude-5.5-haiku}"
  # temperature=1 on purpose: CAIPE sends it (OPENAI_TEMPERATURE in llm-secret); Claude 5.x rejects 0
  out=$(curl -s -m 60 "${LITELLM_URL%/}/chat/completions" -H "Authorization: Bearer $LITELLM_API_KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$model\",\"temperature\":1,\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"Say ok\"}]}")
  if echo "$out" | python3 -c "import sys,json;sys.exit(0 if json.load(sys.stdin).get('choices') else 1)" 2>/dev/null; then ok "model call ($model, temperature=1)"
  else bad "model call failed: $(echo "$out" | cut -c1-200)"; fi
else
  echo "  - model call skipped (LITELLM_URL / LITELLM_API_KEY not set)"
fi

tools=$(kubectl exec -n mcp-servers deploy/prometheus-mcp -- python -W ignore -c "
import asyncio
from fastmcp import Client
async def m():
    async with Client('http://localhost:8000/mcp') as c: print(' '.join(sorted(t.name for t in await c.list_tools())))
asyncio.run(m())" 2>/dev/null | tail -1)
case "$tools" in *prometheus_query*get_pod_logs*|*get_pod_logs*prometheus_query*) ok "prometheus-mcp serves: $tools" ;; *) bad "prometheus-mcp tools: '${tools:-none}'" ;; esac

GITEA_USER=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.username}' | base64 -d)
GITEA_PASS=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' | base64 -d)
GITEA_API="https://gitea.caipe.localtest.me:8443/api/v1/repos/$GITEA_USER/workload"
gitea() { curl -sk -m 20 -u "$GITEA_USER:$GITEA_PASS" "$@"; }
[ "$(gitea -o /dev/null -w '%{http_code}' "$GITEA_API")" = 200 ] && ok "Gitea workload repo reachable" || bad "Gitea workload repo not reachable"

if [ "${1:-}" = --guardrails ]; then
  printf '\033[1m==> Guardrails (Module 5)\033[0m\n'
  modules/05-guardrails/mode.sh soft >/dev/null 2>&1
  out=$(modules/05-guardrails/worst-case.sh 2>&1 | tail -3)
  pr=$(echo "$out" | sed -n 's/.*opened PR #\([0-9]*\).*/\1/p')
  if echo "$out" | grep -q ALLOWED && [ -n "$pr" ]; then
    ok "soft: worst-case ALLOWED (PR #$pr)"
    branch=$(gitea "$GITEA_API/pulls/$pr" | python3 -c "import sys,json;print(json.load(sys.stdin)['head']['ref'])")
    gitea -X PATCH -H 'Content-Type: application/json' -d '{"state":"closed"}' -o /dev/null "$GITEA_API/pulls/$pr"
    gitea -X DELETE -o /dev/null "$GITEA_API/branches/$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$branch")"
  else bad "soft: worst-case did not report ALLOWED: $out"; fi

  modules/05-guardrails/mode.sh hardened >/dev/null 2>&1
  out=$(modules/05-guardrails/worst-case.sh 2>&1)
  if echo "$out" | grep -q 'DENIED.*403'; then ok "hardened: worst-case DENIED (403)"; else bad "hardened: worst-case not denied: $(echo "$out" | tail -2)"; fi
  kubectl logs -n caipe deploy/caipe-openfga-authz-bridge --since=3m 2>/dev/null | grep -q DENY_AGENT_TOOL && ok "audit log has DENY_AGENT_TOOL" || bad "no DENY_AGENT_TOOL audit line"
  gitea "$GITEA_API/branch_protections" | grep -q '"branch_name":"main"' && ok "main is branch-protected" || bad "main is not branch-protected"
  modules/05-guardrails/mode.sh soft >/dev/null 2>&1   # back to the default state so apps.sh/up.sh can push to main
fi

echo
if [ "$failed" -eq 0 ]; then printf '\033[32mSmoke test passed (%d checks).\033[0m\n' "$pass"; else printf '\033[31m%d failed, %d passed.\033[0m\n' "$failed" "$pass"; fi
exit "$failed"
