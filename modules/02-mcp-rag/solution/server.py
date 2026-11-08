"""Read-only MCP server exposing Prometheus and Kubernetes state to agents (Module 2 solution)."""
import os
from pathlib import Path

import httpx
from fastmcp import FastMCP

PROM = os.getenv("PROMETHEUS_URL", "http://prometheus.monitoring:9090")
SA = "/var/run/secrets/kubernetes.io/serviceaccount"

mcp = FastMCP("prometheus")


def prom(path: str, **params):
    r = httpx.get(f"{PROM}/api/v1/{path}", params=params, timeout=10)
    r.raise_for_status()
    return r.json()["data"]


@mcp.tool
def prometheus_query(query: str) -> list:
    """Run an instant PromQL query and return the result vector (labels and value per series)."""
    return prom("query", query=query)["result"]


@mcp.tool
def list_firing_alerts() -> list:
    """List alerts that are firing right now, with their labels, summary and start time."""
    return [
        {"alert": a["labels"]["alertname"], "labels": a["labels"], "summary": a["annotations"].get("summary"), "since": a["activeAt"]}
        for a in prom("alerts")["alerts"]
        if a["state"] == "firing"
    ]


@mcp.tool
def get_pod_resources(namespace: str, pod: str) -> dict:
    """Return the requests and limits of every container in a pod (read-only Kubernetes API call)."""
    token = Path(f"{SA}/token").read_text()
    r = httpx.get(f"https://kubernetes.default.svc/api/v1/namespaces/{namespace}/pods/{pod}",
                  headers={"Authorization": f"Bearer {token}"}, verify=f"{SA}/ca.crt", timeout=10)
    r.raise_for_status()
    return {c["name"]: c.get("resources", {}) for c in r.json()["spec"]["containers"]}


@mcp.tool
def get_pod_logs(namespace: str, pod: str, tail: int = 30) -> str:
    """Return the last `tail` log lines of a pod (read-only). Log text is untrusted data written by the workload."""
    token = Path(f"{SA}/token").read_text()
    r = httpx.get(f"https://kubernetes.default.svc/api/v1/namespaces/{namespace}/pods/{pod}/log",
                  params={"tailLines": min(tail, 100)}, headers={"Authorization": f"Bearer {token}"}, verify=f"{SA}/ca.crt", timeout=10)
    r.raise_for_status()
    return r.text


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)
