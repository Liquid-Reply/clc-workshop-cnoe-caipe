# Module 2: Context & Memory (55 min lab)

Previous: [Module 1B: Install the platform](../01-install/lab.md) · [Workshop home](../../README.md) · Next: [Module 3: Governed Mutation](../03-governed-mutation/lab.md)

Goal: give an agent **eyes** (live cluster state through an MCP server you write) and **memory** (runbooks it can search), then watch a read-only Diagnostics agent answer "why is shop-api throttled?".

## What is already running

- `shop-api` (limit 100m CPU) plus a load generator in namespace `sample-app`. About 2-3 minutes after the pods start, Prometheus fires `HighCPUThrottling`.
- A Prometheus MCP server in `mcp-servers`, deployed by ArgoCD from the `workload` repo in Gitea. **Its code is yours to finish.**
- The runbooks in `runbooks/` are already indexed into the RAG store (datasource `runbooks`).

## Part A: write the MCP server (25 min)

Open `apps/prometheus-mcp/server.py` (identical to `modules/02-mcp-rag/starter/server.py`). It has one tool, `prometheus_query`, and two TODOs. An MCP tool is a Python function with type hints and a docstring: the model reads the docstring to decide when to call it.

1. **TODO 1**: add `list_firing_alerts()` returning alerts whose state is `firing` (hint: `prom("alerts")["alerts"]`; keep `alertname`, `labels`, `summary`, `activeAt`).
2. **TODO 2**: add `get_pod_resources(namespace, pod)` returning each container's `requests` and `limits` (hint: the Kubernetes API with the pod's service-account token; see the `SA` constant).

`get_pod_logs` is already there: read it, note its docstring says log text is *untrusted data*. You will need that in Module 5.

Publish, then check the tools are served. ArgoCD syncs and the pod rolls in about a minute, so repeat the check until your two new tools appear (`rollout status` can return before the sync starts):

```bash
./bootstrap/apps.sh
kubectl exec -n mcp-servers deploy/prometheus-mcp -- python -W ignore -c "
import asyncio
from fastmcp import Client
async def m():
    async with Client('http://localhost:8000/mcp') as c: print([t.name for t in await c.list_tools()])
asyncio.run(m())"
```

Stuck? `SOLUTION=1 ./bootstrap/apps.sh` publishes the finished server (`modules/02-mcp-rag/solution/server.py`).

## Part B: how the agent reaches your server (10 min)

Your server is not called directly. Read `platform/agents/prometheus-mcp.json` and `platform/agents/diagnostics.json`:

- the MCP server is registered with a route on **agentgateway** (`/mcp/prometheus-mcp`);
- the Diagnostics agent lists exactly which tools it may call (`allowed_tools`), and `bootstrap/agents.sh` turned each one into an OpenFGA tuple `agent:diagnostics caller tool:<server>/<tool>`. The gateway checks that on every call.

Question to discuss: why is the allow-list enforced at the gateway and not only in the agent?

## Part C: ask the agent (20 min)

Open <http://localhost:3000>, choose **Diagnostics Agent**, and ask:

> Why is shop-api throttled?

Watch the tool calls in the transcript. A good answer calls `list_firing_alerts`, `get_pod_resources`, a couple of `prometheus_query`, searches the knowledge base and fetches `cpu-throttling.md`, then reports: the throttle ratio, usage vs the 100m limit, the runbook it used, and a recommended new limit. It must say a PR is needed (it cannot change anything).

Try also: *"What does the runbook say about OOMKilled pods?"* (answered from RAG, no cluster call).

**Done when:** the Diagnostics agent answers with numbers from Prometheus and cites `cpu-throttling.md`.

## If it does not work

| Symptom | Try |
|---|---|
| Agent says it has no such tool | Your server is still the starter or has a typo: `kubectl logs deploy/prometheus-mcp -n mcp-servers` |
| Agent answers without calling tools | Ask it explicitly to use its tools; check the alert is firing: `HighCPUThrottling` in the UI or Prometheus |
| "403" from a tool | The agent's tuples are gone: `./bootstrap/agents.sh` |
| Knowledge base returns nothing | `./bootstrap/runbooks.sh` re-indexes (needs rag-server Available) |

---

Previous: [Module 1B: Install the platform](../01-install/lab.md) · [Workshop home](../../README.md) · Next: [Module 3: Governed Mutation](../03-governed-mutation/lab.md)
