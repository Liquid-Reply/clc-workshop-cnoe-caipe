#!/usr/bin/env bash
# Ingest runbooks/*.md into the CAIPE RAG store (datasource "runbooks"). Idempotent: same document ids are overwritten.
set -euo pipefail
cd "$(dirname "$0")/.."
kubectl port-forward -n caipe svc/rag-server 19446:9446 >/dev/null 2>&1 & pf1=$!
# issuer must read http://localhost:7080 (KC_HOSTNAME), so the forward must use that port
kubectl port-forward -n caipe svc/caipe-keycloak 7080:8080 >/dev/null 2>&1 & pf2=$!
trap 'kill $pf1 $pf2 2>/dev/null' EXIT
until curl -sf -o /dev/null localhost:19446/healthz && curl -sf -o /dev/null localhost:7080/realms/caipe; do sleep 1; done

python3 - <<'PY'
import glob, json, os, time, urllib.parse, urllib.request

def call(url, body=None, headers=None, method=None, form=False):
    data = urllib.parse.urlencode(body).encode() if form else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/x-www-form-urlencoded" if form else "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{url}: {e.code} {e.read().decode()[:600]}")

# caipe-platform is a trusted ingestor; "caipe-platform-dev-secret" is the public dev-realm default
tok = call("http://localhost:7080/realms/caipe/protocol/openid-connect/token",
           {"grant_type": "client_credentials", "client_id": "caipe-platform", "client_secret": "caipe-platform-dev-secret"}, form=True)["access_token"]
h, rag = {"Authorization": f"Bearer {tok}", "X-Ingestor-Type": "runbooks", "X-Ingestor-Name": "runbook-loader"}, "http://localhost:19446"
ds = "runbooks"

hb = call(f"{rag}/v1/ingestor/heartbeat", {"ingestor_type": "runbooks", "ingestor_name": "runbook-loader", "description": "Workshop runbooks"}, h)
ing = hb["ingestor_id"]
call(f"{rag}/v1/datasource", {"datasource_id": ds, "ingestor_id": ing, "source_type": "runbooks", "name": "Runbooks",
                              "description": "Operational runbooks", "last_updated": int(time.time())}, h)
docs = [{"id": os.path.basename(p), "page_content": open(p).read(),
         "metadata": {"document_id": os.path.basename(p), "datasource_id": ds, "ingestor_id": ing, "title": os.path.basename(p),
                      "document_type": "runbook", "document_ingested_at": int(time.time()), "fresh_until": 4102444800, "is_graph_entity": False, "metadata": {}}}
        for p in sorted(glob.glob("runbooks/*.md"))]
job = call(f"{rag}/v1/job?datasource_id={ds}&job_status=in_progress&total={len(docs)}", None, h, method="POST")["job_id"]
print(call(f"{rag}/v1/ingest", {"documents": docs, "ingestor_id": ing, "datasource_id": ds, "job_id": job}, h))
call(f"{rag}/v1/job/{job}?job_status=completed", None, h, method="PATCH")
print(call(f"{rag}/v1/job/{job}", None, h))
PY
