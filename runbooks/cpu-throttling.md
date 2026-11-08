# Runbook: HighCPUThrottling

**Alert:** `HighCPUThrottling` fires when a container is CPU-throttled in more than 50% of its scheduling periods for 1 minute.

## What it means
The container wants more CPU than its `resources.limits.cpu`. The kernel (CFS) pauses it for the rest of each 100 ms period, so latency rises even though node CPU may be idle. High throttling with low average CPU usage is the signature of a limit that is too low.

## Diagnose
1. Throttle ratio: `sum(rate(container_cpu_cfs_throttled_periods_total{namespace="NS",container="C"}[1m])) / sum(rate(container_cpu_cfs_periods_total{namespace="NS",container="C"}[1m]))`
2. Usage vs limit: `rate(container_cpu_usage_seconds_total{namespace="NS",container="C"}[1m])` against the configured `resources.limits.cpu`.
3. If usage sits at the limit (for example 0.1 cores with a 100m limit), the limit is the bottleneck.

## Fix
Raise `resources.limits.cpu` in the workload's manifest through a pull request. Target 2-3x the observed steady usage, and keep `requests.cpu` at or below the new limit. Do not edit the live Deployment: ArgoCD will revert it. In the GitOps repo (workload) a namespace's manifests live in `<namespace>/app.yaml`, for example `sample-app/app.yaml`; read the file to get the exact current limit line before proposing a change.

## Verify
After ArgoCD syncs, the throttle ratio should fall below 0.1 within 2 minutes and `HighCPUThrottling` should resolve. The rollout replaces the pod, so a pod name from before the merge returns 404: query by namespace and container with the `rate(...[1m])` expressions above, take the new pod name from the result, and check its `resources.limits.cpu`.
