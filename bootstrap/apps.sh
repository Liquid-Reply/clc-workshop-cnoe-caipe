#!/usr/bin/env bash
# Publish apps/ to Gitea (giteaAdmin/workload, branch main) via the contents API and register the ArgoCD Applications.
# SOLUTION=1 deploys the Module 2 solution server; STARTER3=1 the Module 3 starter. Idempotent; it resets files under apps/ to their repo state, so don't re-run it mid-workshop after PRs were merged.
set -euo pipefail
cd "$(dirname "$0")/.."
export GITEA=https://gitea.caipe.localtest.me:8443

# credentials stay in this script's environment; never echoed
GITEA_USER=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.username}' | base64 -d)
GITEA_PASS=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' | base64 -d)
export GITEA_USER GITEA_PASS

python3 - <<'PY'
import base64, json, os, pathlib, ssl, urllib.error, urllib.request

base, user = os.environ["GITEA"] + "/api/v1", os.environ["GITEA_USER"]
auth = "Basic " + base64.b64encode(f"{user}:{os.environ['GITEA_PASS']}".encode()).decode()
ctx = ssl._create_unverified_context()  # up.sh's self-signed gateway cert

def call(method, path, body=None):
    req = urllib.request.Request(base + path, method=method, headers={"Authorization": auth, "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, context=ctx) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404 and method == "GET":
            return None
        raise SystemExit(f"{method} {path}: {e.code} {e.read().decode()}")

if call("GET", f"/repos/{user}/workload") is None:
    call("POST", "/user/repos", {"name": "workload", "default_branch": "main", "auto_init": True})

# SOLUTION=1 publishes the Module 2 solution instead of the starter (facilitator fallback)
overrides = {"prometheus-mcp/server.py": "modules/02-mcp-rag/solution/server.py"} if os.environ.get("SOLUTION") else {}
# STARTER3=1 publishes the Module 3 starter (two safety checks left as TODOs); the solution is apps/gitea-mcp/server.py itself
if os.environ.get("STARTER3"):
    overrides["gitea-mcp/server.py"] = "modules/03-governed-mutation/starter/server.py"
files = []
for p in sorted(pathlib.Path("apps").rglob("*")):
    if not p.is_file():
        continue
    path = p.relative_to("apps").as_posix()
    if path in overrides:
        p = pathlib.Path(overrides[path])
    cur = call("GET", f"/repos/{user}/workload/contents/{path}?ref=main")
    f = {"path": path, "content": base64.b64encode(p.read_bytes()).decode(), "operation": "update" if cur else "create"}
    if cur:
        f["sha"] = cur["sha"]
    files.append(f)
call("POST", f"/repos/{user}/workload/contents", {"branch": "main", "message": "Workshop workload", "files": files})
PY

# ArgoCD needs credentials: Gitea requires sign-in to read repos
kubectl create secret generic workload-repo -n argocd --dry-run=client -o yaml \
  --from-literal=type=git --from-literal=url="http://my-gitea-http.gitea.svc.cluster.local:3000/$GITEA_USER/workload.git" \
  --from-literal=username="$GITEA_USER" --from-literal=password="$GITEA_PASS" \
  | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f bootstrap/argocd-apps.yaml >/dev/null
# do not wait for ArgoCD's Git poll interval (~3 min): ask every app to refresh now
for a in observability sample-app prometheus-mcp gitea-mcp environments; do
  kubectl annotate application "$a" -n argocd argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
done
echo "workload published; ArgoCD apps: observability, sample-app, prometheus-mcp, gitea-mcp, environments"
