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

Without these checks the starter opens a PR for *any* path on the first call, with no dry run. So **don't chat with the agent until you have published your version**.

Publish your version:

```bash
STARTER3=1 SOLUTION=1 ./bootstrap/apps.sh      # SOLUTION=1 keeps the finished Module 2 server
kubectl get pods -n mcp-servers -l app=gitea-mcp -w
```

ArgoCD needs 10-30 seconds to pick up the change. Wait until a **new** `gitea-mcp` pod is `Running` (AGE in seconds), then press Ctrl-C. (`kubectl rollout status` right after `apps.sh` can still report the old pod.)

Test your path guard: in the UI choose **Remediation Agent** and ask:

> Create the file sample-app/notes.yaml containing 'hello'.

Expect the tool to answer `refused: ...` and the agent to tell you so. Part B tests the dry run.

Stuck? `SOLUTION=1 ./bootstrap/apps.sh` publishes the finished Gitea server.

## Part B: a workload change through a PR (15 min)

Start a new chat, choose **Remediation Agent** again (the picker resets to Diagnostics Agent for every new chat) and ask:

> Raise the CPU limit of the shop-api container in sample-app to 250m.

Expect: it reads `sample-app/app.yaml`, shows you the exact diff (a **dry run**), asks for approval; after you say yes it opens a PR as the `platform-bot` user.

Don't worry about these, they are normal:

- The first `open_pull_request` call often **fails with validation errors** (the model writes `old_string` instead of `old_text`). It reads the error and corrects itself: the tool schema is the contract.
- You may see tools without the `gitea-mcp_` prefix (`read_file`, `write_file`, `ls`). They are CAIPE's built-in scratch space for this chat, not the repo. Only `gitea-mcp_*` tools touch Git.

Open the PR in Gitea (<https://gitea.caipe.localtest.me:8443/giteaAdmin/workload/pulls>) and read the diff. **Do not merge it**: we need the alert for Module 4. Close the PR.

## Part C: a Crossplane environment through a PR (20 min)

Crossplane exposes a `TeamEnvironment` API (`crossplane/xrd.yaml`): namespace + quota + limit range, sized small, medium or large. The repo already has one, `environments/team-checkout.yaml`; the agent uses it as its template.

> **Same name, two gates.** `reviewed_and_approved` shows up twice:
> - as the **tool argument** of `open_pull_request` (Part A): the *model* sets it after your "yes" in chat, and it only switches off the dry run;
> - as a **field in the YAML file**: Crossplane builds nothing until it is `true`, and only the *reviewer* sets it, in the PR. The tool refuses to write `true` into a file.

Ask the Remediation Agent:

> Provision an environment for team payments, size medium.

It proposes `environments/team-payments.yaml` with `reviewed_and_approved: false` and opens a PR after your yes. Now be the human reviewer:

1. In the PR, edit the file and change `reviewed_and_approved` to **true**. Do this on the PR branch *before* merging. A merge with `false` builds nothing.
2. Merge the PR.
3. Watch it land. ArgoCD polls Git, so this takes **1-3 minutes**. To speed it up, open the `environments` app in ArgoCD and click **Refresh**.

```bash
kubectl get teamenvironment          # payments next to the seed checkout
kubectl get ns team-payments
kubectl get resourcequota -n team-payments
```

**Done when:** you saw a PR from `platform-bot` for the CPU change (closed, not merged) and a merged environment PR produced a namespace with a quota.

**Bonus (if time):** ask for `team-test`, size small, and merge it with the flag still `false`. `kubectl get teamenvironment` shows `test` as READY True, but `kubectl get ns team-test` finds nothing: Crossplane is happy, it was told to build nothing. The gate works because the *reviewer* sets it, not the model.

## Questions for the debrief

- The agent called the tool with `reviewed_and_approved=true`. Who decided that was safe? (The model, after you said yes in chat.) Keep that question for Module 5.
- Which of the two checks you wrote actually limits what the agent can do, and which only changes the UX?
- The path guard only covers *new* files. Which existing files can the agent still propose edits to? (Any of them, including `gitea-mcp/server.py`, its own guardrails. What stops that from landing?)
- What does `platform-bot` have on the repo? (Write on `giteaAdmin/workload` only; no admin, no merge bypass.)

## If it does not work

| Symptom | Try |
|---|---|
| Agent says it created or changed a file, but there is no PR | It used the built-in `write_file` (scratch space, not Git). Tell it to use `open_pull_request` |
| Agent invents a file path | Runbooks and prompts state the layout: manifests live at `<namespace>/app.yaml`. Tell it to `read_file sample-app/app.yaml` first |
| Second PR with the same title fails | Branch names come from the title; use a different title |
| `team-payments` is not created after 3 minutes | Click Refresh on the `environments` app in ArgoCD. Still nothing: the flag was `false` at merge time. Set it to true in a new commit on main (or another PR) |
| ArgoCD shows `environments` OutOfSync | Click Refresh; it reads the whole `environments/` folder |

---

Previous: [Module 2: Context and Memory](../02-mcp-rag/lab.md) · [Workshop home](../../README.md) · Next: [Module 4: Multi-agent incident resolution](../04-multi-agent/lab.md)
