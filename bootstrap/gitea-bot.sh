#!/usr/bin/env bash
# Least-privilege Git identity for agents: user 'platform-bot' with write access to giteaAdmin/workload only (it opens PRs, a human merges).
# Its token lands in Secret mcp-servers/gitea-mcp-token, mounted by the Gitea MCP server. Idempotent; never prints credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
export GITEA=https://gitea.caipe.localtest.me:8443
GITEA_USER=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.username}' | base64 -d)
GITEA_PASS=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' | base64 -d)
BOT_PASS=$(kubectl get secret gitea-mcp-token -n mcp-servers -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
[ -n "$BOT_PASS" ] || BOT_PASS=$(openssl rand -hex 16)
export GITEA_USER GITEA_PASS BOT_PASS
kubectl create namespace mcp-servers --dry-run=client -o yaml | kubectl apply -f - >/dev/null

python3 - <<'PY' | kubectl create secret generic gitea-mcp-token -n mcp-servers --dry-run=client -o yaml --from-file=token=/dev/stdin --from-literal=password="$BOT_PASS" | kubectl apply -f - >/dev/null
import base64, json, os, ssl, sys, urllib.error, urllib.request
base, ctx = os.environ["GITEA"] + "/api/v1", ssl._create_unverified_context()
def call(user, pw, method, path, body=None, ok=()):
    h = {"Authorization": "Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode(), "Content-Type": "application/json"}
    req = urllib.request.Request(base + path, method=method, headers=h, data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, context=ctx) as r:
            return json.load(r) if r.length != 0 else None
    except urllib.error.HTTPError as e:
        if e.code in ok:
            return None
        raise SystemExit(f"{method} {path}: {e.code} {e.read().decode()}")
admin, apw, bot, bpw = os.environ["GITEA_USER"], os.environ["GITEA_PASS"], "platform-bot", os.environ["BOT_PASS"]
call(admin, apw, "POST", "/admin/users", {"username": bot, "email": "platform-bot@caipe.localtest.me", "password": bpw, "must_change_password": False}, ok=(409, 422))
call(admin, apw, "PUT", f"/repos/{admin}/workload/collaborators/{bot}", {"permission": "write"})
call(bot, bpw, "DELETE", f"/users/{bot}/tokens/mcp", ok=(404,))
print(call(bot, bpw, "POST", f"/users/{bot}/tokens", {"name": "mcp", "scopes": ["write:repository"]})["sha1"], end="")
PY
echo "platform-bot ready; token in mcp-servers/gitea-mcp-token"
