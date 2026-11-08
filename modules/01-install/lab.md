# Module 1B: Install the platform (60 min)

[Workshop home](../../README.md) · Next: [Module 2: Context and Memory](../02-mcp-rag/lab.md)

You will build the whole stack with one command, then prove it works with a smoke-test prompt.

## 1. Pre-flight (10 min)

Install the tools for your OS first: [docs/platform-setup.md](../../docs/platform-setup.md) (macOS, Linux, Windows with WSL2; Windows users work **inside the WSL terminal**). Then check the laptop:

```bash
./bootstrap/preflight.sh      # Docker memory, tools, DNS, ports, disk; prints the fix for anything wrong
```

It must end with `Ready.`. If it says the name `gitea.caipe.localtest.me` does not resolve (some corporate DNS, Tailscale and routers block answers that point at 127.0.0.1), add the hosts line it prints:

```bash
echo '127.0.0.1 gitea.caipe.localtest.me argocd.caipe.localtest.me' | sudo tee -a /etc/hosts
```

Stragglers without network: load the tarball you were handed instead of pulling.

```bash
./bootstrap/prepull.sh --load images.tar
```

## 2. Start the cluster (kick off, then read while it builds)

```bash
export LITELLM_URL=https://<your-endpoint>/v1     # your own provider (BYOP); must end in /v1
export LITELLM_API_KEY=<your key>
export LITELLM_MODEL=claude-haiku-4-5             # must accept temperature=0
./bootstrap/up.sh                                  # ~6 min with images pre-pulled, ~12 min without; safe to re-run
```

## 3. While it builds: read the manifests (20 min)

| Look at | What it tells you |
|---|---|
| `bootstrap/versions.env` | Everything is pinned (kind node, ArgoCD and Gitea charts, agentgateway, CAIPE chart, Crossplane). |
| `bootstrap/up.sh` | The order: kind -> agentgateway -> ArgoCD + Gitea (upstream charts) -> gateway routes -> CAIPE -> Keycloak users -> Crossplane -> workload. |
| `platform/caipe/values.yaml` | CAIPE chart values: Keycloak, OpenFGA, agentgateway, how the LLM is reached. |
| `platform/caipe/rag.yaml` | A deliberately slim RAG stack so the whole thing fits in 12 GB. |
| `bootstrap/argocd-apps.yaml` | ArgoCD Applications that deploy `apps/` from Gitea. GitOps starts here. |

## 4. Verify and log in (30 min)

```bash
kubectl get pods -A | grep -v -E 'Running|Completed'     # should print nothing when settled
./bootstrap/forward.sh                                   # leave it running (UI :3000, Keycloak :7080)
```

1. Open <http://localhost:3000>, click **Sign in with SSO**.
2. Username `admin@caipe.local`. Password:
   `kubectl get secret caipe-local-admin -n caipe -o jsonpath='{.data.password}' | base64 -d`
   (copy it with `| pbcopy` on macOS, `| clip.exe` on WSL, `| xclip -selection clipboard` on Linux, or print it with `; echo`, so a trailing `%` is not included).
3. Gitea: <https://gitea.caipe.localtest.me:8443>, user `giteaAdmin`, password from `kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' | base64 -d`. You will see the `workload` repo. The browser warns about the certificate: it is the self-signed one `up.sh` made for the gateway, accept it.
4. ArgoCD: <https://argocd.caipe.localtest.me:8443>, user `admin`, password from `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`; applications `observability`, `sample-app`, `prometheus-mcp`, `gitea-mcp`, `environments` should be Synced.

## 5. Smoke test

In the UI pick **Hello World** (or **Diagnostics Agent**) and send: `Say hello and tell me which model you are.`
A reply means the whole chain works: browser -> CAIPE -> your endpoint -> model.

**Done when:** all pods are Running, you are logged in, and the smoke-test prompt got an answer.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `up.sh` stops at pre-flight | Read the lines marked `x`: each one says how to fix it (`docs/platform-setup.md`) |
| Login says invalid username or password | Re-copy the password (see above); if Keycloak restarted its users are gone: `./bootstrap/users.sh` |
| Pods stuck `ContainerCreating` for minutes | Slow image pulls: wait, or `./bootstrap/prepull.sh --load images.tar` |
| Smoke test fails with a 400 about the model | Your endpoint does not serve that model or it rejects `temperature=0` (default is `claude-haiku-4-5`); check the name with `curl $LITELLM_URL/models -H "Authorization: Bearer $LITELLM_API_KEY"`, then `LITELLM_MODEL=<name> ./bootstrap/up.sh` |
| UI or Keycloak page stops loading after you re-ran `up.sh` | Pods were replaced; `forward.sh` reconnects by itself within a few seconds, or restart it |
| Anything else | Re-run `./bootstrap/up.sh`; it is idempotent |

---

[Workshop home](../../README.md) · Next: [Module 2: Context and Memory](../02-mcp-rag/lab.md)
