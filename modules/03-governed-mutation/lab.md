# Module 3: Governed Mutation (55 min lab)

Previous: [Module 2: Context and Memory](../02-mcp-rag/lab.md) · [Workshop home](../../README.md) · Next: [Module 4: Multi-agent incident resolution](../04-multi-agent/lab.md)

Goal: let an agent **change** things without ever giving it `kubectl apply`. The only write path is a Gitea MCP tool that opens a pull request. A human merges, ArgoCD applies.

```
Remediation agent --open_pull_request--> PR in Gitea --human review + merge--> ArgoCD --> cluster (Crossplane reconciles claims)
```

## Part A: finish the safety checks in the write tool (20 min)

The Gitea MCP server (`apps/gitea-mcp/server.py` is the finished one) has two tools: `read_file` and `open_pull_request`. There is **no merge tool** and no way to push to `main`.

Open `modules/03-governed-mutation/starter/server.py`. In `open_pull_request` two checks are TODOs:

1. **Path guard**: creating a new file is only allowed under `environments/` (reject `..`). Return a string starting with `refused:`.
2. **Dry run**: unless `reviewed_and_approved` is true, return the diff and change nothing.

Until you fill them in, this starter will happily open a PR for *any* path on the first call. That is the point: see what the checks are protecting.

Publish your version and wait for the rollout:

```bash
STARTER3=1 SOLUTION=1 ./bootstrap/apps.sh      # SOLUTION=1 keeps the finished Module 2 server
kubectl rollout status deploy/gitea-mcp -n mcp-servers
```

Stuck? `SOLUTION=1 ./bootstrap/apps.sh` publishes the finished Gitea server.

## Part B: a workload change through a PR (15 min)

In the UI choose **Remediation Agent** and ask:

> Raise the CPU limit of the shop-api container in sample-app to 250m.

Expect: it reads `sample-app/app.yaml`, shows you the exact diff (a **dry run**), asks for approval; after you say yes it opens a PR as the `platform-bot` user.

Open the PR in Gitea (<https://gitea.caipe.localtest.me:8443/giteaAdmin/workload/pulls>) and read the diff. **Do not merge it**: we need the alert for Module 4. Close the PR.

## Part C: a Crossplane environment through a PR (20 min)

Crossplane exposes a `TeamEnvironment` API (`crossplane/xrd.yaml`): namespace + quota + limit range, sized small, medium or large. It builds nothing until `reviewed_and_approved: true` is set in the resource.

Ask the Remediation Agent:

> Provision an environment for team payments, size medium.

It proposes `environments/team-payments.yaml` with `reviewed_and_approved: false` and opens a PR after your yes. Now be the human reviewer:

1. In the PR, edit the file and change `reviewed_and_approved` to **true** (flip it *before* merging).
2. Merge the PR.
3. Watch it land:

```bash
kubectl get teamenvironment
kubectl get ns team-payments
kubectl get resourcequota -n team-payments
```

Merge it with the flag still `false` in a second experiment (`team-test`): nothing is built. The gate works, because the *reviewer* sets it, not the model.

**Done when:** you saw a PR from `platform-bot` for the CPU change (closed, not merged) and a merged environment PR produced a namespace with a quota.

## Questions for the debrief

- The agent set `reviewed_and_approved=false` first. Who decided it was safe to set `true`? (The model, after you said yes in chat.) Keep that question for Module 5.
- Which of the two checks you wrote actually limits what the agent can do, and which only changes the UX?
- What does `platform-bot` have on the repo? (Write on `giteaAdmin/workload` only; no admin, no merge bypass.)

## If it does not work

| Symptom | Try |
|---|---|
| Agent invents a file path | Runbooks and prompts state the layout: manifests live at `<namespace>/app.yaml`. Tell it to `read_file sample-app/app.yaml` first |
| Second PR with the same title fails | Branch names come from the title; use a different title |
| `team-payments` is not created | The flag was still `false` at merge time. Set it to true in a new commit on main (or another PR) |
| ArgoCD shows `environments` OutOfSync | Click Refresh; it reads the whole `environments/` folder |

---

Previous: [Module 2: Context and Memory](../02-mcp-rag/lab.md) · [Workshop home](../../README.md) · Next: [Module 4: Multi-agent incident resolution](../04-multi-agent/lab.md)
