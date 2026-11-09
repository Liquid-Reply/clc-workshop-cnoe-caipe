# Building Agentic IDPs: AI-Driven Platform Engineering with CNOE and MCP

Full-day hands-on workshop (CLC conference). You build a Kubernetes-native agentic Internal Developer Platform on your
laptop, where AI agents don't just suggest code: they diagnose, provision and tune systems, and every change they make
goes through a Git pull request that a human reviews.

## What you will build

```
Alert (Prometheus) -> Diagnostics agent --read-only MCP tools: metrics, pod state, runbooks (RAG)--> diagnosis
                   -> Remediation agent --Gitea MCP tool: open a pull request only--------------> PR
                   -> you review and merge in Gitea -> ArgoCD syncs (Crossplane builds environments)
                   -> Diagnostics agent verifies the metric recovered
```

Agents never get `kubectl apply`. Every tool call goes through agentgateway, which checks per agent and per tool
whether the call is allowed.

What you take home:

- The architecture of an agentic IDP with CNOE and CAIPE (the Governed Action Loop).
- How to write and deploy an MCP server (FastMCP) that exposes live Kubernetes and Prometheus state to agents.
- Multi-agent incident resolution with privilege-split agents, and the guardrails that hold when the model does not.

## Before the workshop

Do this at home, at least 48 hours before; the image download alone is about 3 GB.

1. Read [what you need to prepare](docs/attendee-prerequisites.md): a laptop that can give Docker 12 GB of RAM, and your
   own LLM provider (BYOP) serving a chat model and `text-embedding-3-small`. No proxy yet? The guide shows how to run
   LiteLLM on your laptop.
2. Install the tools for your OS: [platform setup](docs/platform-setup.md) (macOS, Linux, Windows with WSL2).
3. Clone this repository and run `./bootstrap/preflight.sh`; it must end with `Ready.`.
4. Run `./bootstrap/prepull.sh` to download every image and chart in advance.

## Workshop steps

Follow the steps in order: each lab builds on the cluster state the previous one left. Every lab page has links to the
previous and next step.

1. [**Architecture: CNOE, CAIPE and Governed Action Loops**](docs/architecture.md) (10:00, 30 min, talk, Hossein; working alone? read the page)
    - What an agentic IDP is, the Governed Action Loop, and where CNOE and CAIPE fit
2. [**Install the platform**](modules/01-install/lab.md) (10:30, 60 min, Jagdeep)
    - Pre-flight check, one-command install, log in to CAIPE, Gitea and ArgoCD
    - Smoke test: your first prompt to an agent
3. *Break and catch-up buffer* (11:30, 15 min)
4. [**Context and Memory: write an MCP server, search runbooks**](modules/02-mcp-rag/lab.md) (11:45, 75 min, Hossein)
    - Add two tools to a FastMCP server and publish it through GitOps
    - How an agent reaches your server: agentgateway route and per-tool allow-list
    - Ask a read-only Diagnostics agent why `shop-api` is throttled
5. *Lunch* (13:00, 60 min)
6. [**Governed Mutation: GitOps and Crossplane via MCP**](modules/03-governed-mutation/lab.md) (14:00, 75 min, Marcel)
    - Finish the safety checks in the only write tool agents get: open a pull request
    - A workload change and a Crossplane team environment, each through a reviewed PR
7. *Break* (15:15, 15 min)
8. [**Multi-agent incident resolution**](modules/04-multi-agent/lab.md) (15:30, 65 min, Jagdeep)
    - An Incident Commander delegates to Diagnostics and Remediation
    - Alert to diagnosis to PR to your merge to verified recovery
9. [**Guardrails, failure modes and teardown**](modules/05-guardrails/lab.md) (16:35, 25 min, Marcel)
    - Prompt injection through a log line, and the boundaries that hold when the model obeys it
    - Tear down the cluster

## How each lab works

Every lab page has the same parts: a **goal**, numbered **parts** with timings, a **Done when** line, and an
**If it does not work** table with recovery commands.

- **Stuck on code?** Each lab says how to publish the finished version (for example `SOLUTION=1 ./bootstrap/apps.sh`),
  so you can continue with the next part. Try first: the labs are short on purpose.
- **Agent answers differ from your neighbour's?** That is expected: models choose their own tool calls. Compare what
  they called, not the wording.
- **Something broken that the table does not cover?** Re-run `./bootstrap/up.sh` (safe to repeat), then ask a
  facilitator.

## Quick reference

| What | Where | Login |
|---|---|---|
| CAIPE UI (agents, chat) | <http://localhost:3000> (needs `./bootstrap/forward.sh` running) | **Sign in with SSO**, `admin@caipe.local`, password: `kubectl get secret caipe-local-admin -n caipe -o jsonpath='{.data.password}' \| base64 -d` |
| Gitea (Git, pull requests) | <https://gitea.caipe.localtest.me:8443> | `giteaAdmin`, password: `kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' \| base64 -d` |
| ArgoCD (deployments) | <https://argocd.caipe.localtest.me:8443> | `admin`, password: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' \| base64 -d` |

Gitea and ArgoCD use a self-signed certificate: accept the browser warning.

```bash
export LITELLM_URL=https://<your-endpoint>/v1   # your own OpenAI-compatible endpoint (BYOP); must end in /v1
export LITELLM_API_KEY=<your key>
export LITELLM_MODEL=claude-5.5-haiku           # must accept temperature=1; verified end to end: claude-5.5-haiku, claude-haiku-4-5
./bootstrap/up.sh        # build or repair the whole stack (safe to re-run)
./bootstrap/forward.sh   # leave running: UI on :3000, Keycloak on :7080
./bootstrap/down.sh      # delete the cluster
```

If `*.caipe.localtest.me` does not resolve (corporate DNS, VPN, Tailscale), run once:
`echo '127.0.0.1 gitea.caipe.localtest.me argocd.caipe.localtest.me' | sudo tee -a /etc/hosts`

## For maintainers

- Pinned versions: `bootstrap/versions.env`. Headless checks: `./bootstrap/smoke.sh [--guardrails]` (whole stack) and
  `./bootstrap/check-docs.sh` (every path in the guides exists).
- If Keycloak restarts, its users are lost: run `./bootstrap/users.sh`.

```
bootstrap/      single-command cluster bootstrap, pre-flight, pre-pull, smoke test
platform/       ArgoCD/Gitea values, CAIPE values, agentgateway config, agent and MCP server registrations
apps/           sample app + load generator, Prometheus and alert rules, MCP servers (published to Gitea)
crossplane/     Team Environment XRD + composition
modules/        01..05: lab.md, plus starter/ and solution/ where a lab has code
runbooks/       operational runbooks indexed into the RAG store
docs/           architecture, attendee prerequisites, platform setup
```

## Upstream projects

- CNOE: https://cnoe.io/docs/overview/cnoe
- CAIPE: https://caipe.io

## License

Apache License 2.0, see [LICENSE](LICENSE).
