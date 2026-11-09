# Module 4: Multi-Agent Incident Resolution (50 min lab)

Previous: [Module 3: Governed Mutation](../03-governed-mutation/lab.md) · [Workshop home](../../README.md) · Next: [Module 5: Guardrails and teardown](../05-guardrails/lab.md)

Goal: run the whole Governed Action Loop hands-off except for **your approval**.

```
HighCPUThrottling -> Diagnostics (read-only) -> Remediation (PR only) -> you review + merge in Gitea
                  -> ArgoCD syncs -> Diagnostics verifies the metric recovered
```

## Setup (5 min)

Start from a clean incident: the finished servers and the original 100m limit.

```bash
SOLUTION=1 ./bootstrap/apps.sh
```

The alert needs about 2.5 minutes after `shop-api` restarts. Check it is firing (UI > Diagnostics Agent: "what alerts are firing?") before you start.

## Part A: look at the split (10 min)

Read the three agents in `platform/agents/`:

| Agent | Can do | Cannot do |
|---|---|---|
| `diagnostics` | alerts, Prometheus, pod resources, pod logs, runbook search | any write |
| `remediation` | `read_file`, `open_pull_request` on the workload repo | metrics, merge, the cluster |
| `incident-commander` | delegates with the `task` tool to the two above | any tool of its own |

Each sub-agent keeps **its own** allow-list; the commander cannot lend one agent the other's tools.

## Part B: run the loop (35 min)

In the UI choose **Incident Commander** and send:

> There is an alert firing in the platform. Investigate and fix it.

1. **Diagnose (2-3 min).** The commander delegates to Diagnostics. You get a 3-line summary: throttle ratio, usage vs limit, the runbook, a proposed new `limits.cpu`. Do you agree with the number? (Runbook rule: 2-3x observed usage. See the gotcha below.)
2. **Steer.** Tell it to go ahead, or ask for a different value. You are the decision maker.
3. **PR (about 1 min).** The commander delegates to Remediation, which reads `sample-app/app.yaml` and shows a **dry-run diff**. Check the diff yourself; say yes. It opens a PR as `platform-bot`.
4. **Review and merge** in Gitea: <https://gitea.caipe.localtest.me:8443/giteaAdmin/workload/pulls>. Read the diff, merge.
5. **Verify (2 min).** ArgoCD syncs (`argocd.caipe.localtest.me:8443`, app `sample-app`) and replaces the `shop-api` pod; this takes 1-3 minutes after the merge. Wait until `kubectl get pods -n sample-app` shows a new `shop-api` pod (young AGE) Running, **then** tell the commander "it is merged". It asks Diagnostics again and reports the throttle ratio now. (If you say it too early it will correctly report the old 100m pod and a firing alert: just ask it to verify again.)

```bash
kubectl get deploy shop-api -n sample-app -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}'
```

**Done when:** the PR is merged, `shop-api` runs with the new limit, the alert has cleared and the commander reports the before/after numbers.

The commander may still call it **not resolved**: with the runbook's 2-3x rule the new limit can leave 20-30% throttling. The alert clears (it fires above 50%), but the runbook's target is below 10%. That is not a failure of your lab; it is the second question below.

## Questions

- Where exactly did a human sit in this loop, and what could they have caught?
- Once the pod is no longer throttled, its real CPU demand shows (about 170m). Was "2-3x of 83m" right? What would you change in the runbook?
- The agents sometimes pick `prometheus_query` over `get_pod_resources`. The allow-list permits both; why can't it force one?

## If it does not work

| Symptom | Try |
|---|---|
| "No alerts firing" | Wait 2.5 min after `apps.sh`; check `kubectl get pods -n sample-app` |
| Remediation guesses a file path | Tell it: read `sample-app/app.yaml` first |
| It proposes 500m | Ask it to apply the runbook rule (2-3x observed usage) |
| Response fails to complete | Rate limit or model error; `kubectl logs deploy/caipe-dynamic-agents -n caipe --since=5m`, then retry |

---

Previous: [Module 3: Governed Mutation](../03-governed-mutation/lab.md) · [Workshop home](../../README.md) · Next: [Module 5: Guardrails and teardown](../05-guardrails/lab.md)
