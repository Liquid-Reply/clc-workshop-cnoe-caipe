#!/usr/bin/env bash
# Register the workshop MCP servers and agents (platform/agents/*.json) in CAIPE's MongoDB, and grant each agent
# exactly the tools in its allow-list as OpenFGA tuples (agentgateway enforces those; allowed_tools alone is only an
# app-level filter). Idempotent. OpenFGA is in memory here, so re-run after an OpenFGA restart.
set -euo pipefail
cd "$(dirname "$0")/.."
NS=caipe
mongo() { kubectl exec -i -n "$NS" caipe-mongodb-0 -- mongosh -u admin -p changeme --authenticationDatabase admin --quiet caipe; } # dev password from platform/caipe/values.yaml

for f in platform/agents/*.json; do
  coll=$(python3 -c 'import json,sys; print("dynamic_agents" if "system_prompt" in json.load(open(sys.argv[1])) else "mcp_servers")' "$f")
  python3 - "$f" "$coll" <<'PY' | mongo >/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
print(f"""const d = {json.dumps(d)}; const now = new Date().toISOString();
const old = db.{sys.argv[2]}.findOne({{_id: d._id}});
d.created_at = old ? old.created_at : now; d.updated_at = now;
db.{sys.argv[2]}.replaceOne({{_id: d._id}}, d, {{upsert: true}});""")
PY
  echo "registered $coll/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["_id"])' "$f")"
done

kubectl port-forward -n "$NS" svc/caipe-openfga 18080:8080 >/dev/null 2>&1 & pf=$!
trap 'kill $pf 2>/dev/null' EXIT
until curl -sf -o /dev/null localhost:18080/healthz; do sleep 1; done
python3 - <<'PY'
import glob, json, urllib.request, urllib.error
fga = "http://localhost:18080"
def call(path, body=None):
    req = urllib.request.Request(fga + path, data=json.dumps(body).encode() if body else None, headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))
store = next(s["id"] for s in call("/stores")["stores"] if s["name"] == "caipe-openfga")
n = 0
for f in glob.glob("platform/agents/*.json"):
    d = json.load(open(f))
    for server, tools in d.get("allowed_tools", {}).items():
        for tool in tools:
            key = {"user": f"agent:{d['_id']}", "relation": "caller", "object": f"tool:{server}/{tool}"}
            try:
                call(f"/stores/{store}/write", {"writes": {"tuple_keys": [key]}})
                n += 1
            except urllib.error.HTTPError as e:
                if b"already exist" not in e.read():
                    raise
print(f"granted {n} new agent->tool tuples")
PY
