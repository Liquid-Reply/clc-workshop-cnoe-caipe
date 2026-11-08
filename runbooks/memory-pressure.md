# Runbook: container OOMKilled / memory pressure

**Signals:** pod restarts with `OOMKilled` as the last termination reason; `container_memory_working_set_bytes` close to `resources.limits.memory`.

## Diagnose
1. `container_memory_working_set_bytes{namespace="NS",container="C"}` against the limit.
2. Steady growth means a leak; a step at start-up means the limit is just too low.

## Fix
Raise `resources.limits.memory` through a pull request (keep requests equal to the typical working set). If memory grows without bound, open a ticket for the owning team instead of only raising the limit.
