# Runbook: pods restarting (CrashLoopBackOff)

__Signals:__ `kube_pod_container_status_restarts_total` increasing; pod in `CrashLoopBackOff`.

## Diagnose

1. Last termination reason: `OOMKilled` means see the memory-pressure runbook; `Error` means application crash, read the logs; `Completed` with a liveness failure means the probe is too strict.
2. Recent change: compare with the last ArgoCD sync; a bad image tag or config is the usual cause.

## Fix

Roll back by reverting the offending commit in Git (pull request). Never patch the live resource.

```sh

```
