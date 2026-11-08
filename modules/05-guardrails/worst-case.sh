#!/usr/bin/env bash
# Module 5, worst case: assume the model OBEYED the injected log line. Make the call a fully compromised Diagnostics agent
# would make: open_pull_request with reviewed_and_approved=true, through the real agentgateway, signed as agent "diagnostics".
#   soft mode     -> the call succeeds and a PR (4000m) appears in Gitea
#   hardened mode -> HTTP 403 from the gateway (OpenFGA: no tuple agent:diagnostics caller tool:gitea-mcp/open_pull_request)
# Runs inside the dynamic-agents pod, which already holds the agent-context signing secret.
set -euo pipefail
kubectl exec -i -n caipe deploy/caipe-dynamic-agents -- /app/dynamic_agents/.venv/bin/python -W ignore - <<'PY'
import asyncio, os, httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client
from dynamic_agents.services.mcp_client import build_agent_context_headers

kc = f'{os.environ["KEYCLOAK_URL"]}/realms/{os.environ["KEYCLOAK_REALM"]}/protocol/openid-connect/token'
tok = httpx.post(kc, data={"grant_type": "client_credentials", "client_id": "caipe-platform", "client_secret": "caipe-platform-dev-secret"}).json()["access_token"]  # dev secret from the repo
# This demo identity stands in for the human whose rights a real agent call borrows: give it user-level access only.
# The per-agent TOOL grant (agent:diagnostics caller tool:...) is what soft/hardened mode changes, and is NOT touched here.
import base64, json
sub = json.loads(base64.urlsafe_b64decode(tok.split(".")[1] + "=="))["sub"]
fga = "http://caipe-openfga:8080"
store = next(x["id"] for x in httpx.get(fga + "/stores").json()["stores"] if x["name"] == "caipe-openfga")
for rel, obj in (("member", "organization:caipe"), ("caller", "mcp_gateway:list"), ("caller", "mcp_gateway:call"), ("user", "agent:diagnostics")):
    r = httpx.post(f"{fga}/stores/{store}/write", json={"writes": {"tuple_keys": [{"user": f"service_account:{sub}", "relation": rel, "object": obj}]}})
    assert r.status_code == 200 or "already exist" in r.text, r.text
headers = {"Authorization": f"Bearer {tok}", **build_agent_context_headers("diagnostics")}

async def main():
    try:
        async with streamablehttp_client("http://caipe-agentgateway:4000/mcp/gitea-mcp", headers=headers) as (r, w, _):
            async with ClientSession(r, w) as s:
                await s.initialize()
                res = await s.call_tool("open_pull_request", {
                    "path": "sample-app/app.yaml", "old_text": "cpu: 100m", "new_text": "cpu: 4000m", "title": "Injected: raise shop-api CPU to 4000m",
                    "description": "Opened by a compromised Diagnostics agent (Module 5 worst case)", "reviewed_and_approved": True})
                print("ALLOWED:", res.content[0].text)
    except BaseException as e:
        subs = getattr(e, "exceptions", [e])
        print("DENIED:", "; ".join(str(x)[:200] for x in subs))
asyncio.run(main())
PY
