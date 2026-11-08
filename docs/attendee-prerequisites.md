# Building Agentic IDPs workshop: what attendees need to prepare

Bring a laptop that can give Docker 12 GB of RAM, and your own LLM provider access (BYOP): an OpenAI-compatible endpoint, an API key and a compatible model. Set up and test both at least 48 hours before the workshop; the workshop does not provide model access.

## Laptop requirements

The whole platform runs locally in a Kubernetes (kind) cluster inside Docker, so the laptop must be able to give Docker 12 GB of RAM.

| Item | Minimum | Notes |
| --- | --- | --- |
| RAM | 16 GB total | Docker itself needs 12 GB; an 8 GB laptop cannot run the stack |
| CPU | 4 cores for Docker | Fewer works but a cold build is slow |
| Free disk | 30 GB | Images and the cluster use about 25 GB |
| Operating system | macOS, Linux, or Windows 10/11 with WSL2 | See Supported systems |
| Admin rights | Required | To install Docker, edit the hosts file, and (Windows) configure WSL2 |
| Browser | Any current browser | Used for the CAIPE UI, Gitea and Argo CD |

## Supported systems

macOS on Apple silicon is tested end to end; other platforms use the same multi-arch images and scripts but are not yet fully tested.

| Platform | Status |
| --- | --- |
| macOS, Apple silicon (Docker Desktop or Colima) | Tested end to end, all labs |
| Linux amd64 (Docker Engine) | Partly verified; full run pending |
| macOS Intel | Expected to work, not tested |
| Windows 10/11 with WSL2 (Ubuntu) | Documented, not tested |
| Linux arm64, Windows on ARM | Expected to work, not tested |
| Podman, Rancher Desktop | Best effort, not supported |
| WSL1, native Windows without WSL2 | Not supported |

## AI provider: bring your own (BYOP)

Attendees bring their own model access, and the model must accept `temperature=1`: `up.sh` makes CAIPE send it (`OPENAI_TEMPERATURE=1`), because Claude 5.x rejects CAIPE's default of 0. The only model verified end to end is `claude-5.5-haiku`.

| You need | Detail |
| --- | --- |
| Endpoint | An OpenAI-compatible Chat Completions API; base URL ending in `/v1`, set as `LITELLM_URL` |
| API key | For that endpoint, set as `LITELLM_API_KEY` |
| Model | Supports tool calling and accepts `temperature=1`, set as `LITELLM_MODEL` (default `claude-5.5-haiku`) |
| Budget | Usage is billed to the attendee's own account; set a spend limit |

- **Tested path:** a LiteLLM proxy (your own or your company's) in front of Anthropic, serving `claude-5.5-haiku`.
- **Other OpenAI-compatible endpoints** (OpenAI, other providers, a local model server): may work, not tested. A local model also competes for the laptop's RAM.
- **A native, non-OpenAI API key alone does not work:** CAIPE talks the OpenAI API format only; put a LiteLLM proxy in front of it.
- **What is sent:** chat prompts plus what the agents read from the local cluster (metrics, logs and runbooks of a sample app) go to the attendee's provider. Follow your employer's AI policy.

Test the provider at home, before the day. A reply containing `choices` means the model accepts `temperature=1`:

```bash
export LITELLM_URL=https://<your-endpoint>/v1 LITELLM_API_KEY=<your-key> LITELLM_MODEL=claude-5.5-haiku
curl -s "$LITELLM_URL/chat/completions" -H "Authorization: Bearer $LITELLM_API_KEY" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$LITELLM_MODEL\",\"temperature\":1,\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"Say ok\"}]}"
```

With the three variables set, `./bootstrap/preflight.sh` also checks that the endpoint lists the model.

## Before the day

Do all of this at home or in the office, at least 48 hours before the workshop: the image download alone is about 3 GB and the venue Wi-Fi is shared. Exact install commands per OS are in [docs/platform-setup.md](platform-setup.md).

- [ ] **Docker** installed and given 12 GB RAM and 4 CPUs (Docker Desktop, Colima or OrbStack on macOS; Docker Engine on Linux).
- [ ] **Windows only:** WSL2 with Ubuntu set up (needs admin rights and a reboot), WSL memory raised to 14 GB, and everything done inside the Ubuntu terminal.
- [ ] **Tools** on the PATH: `kind` (v0.33.0), `kubectl`, `helm`, `git`, plus `curl`, `openssl` and `python3`, which most systems already have.
- [ ] **Linux only:** inotify limits raised, as described in the setup guide.
- [ ] **LLM provider:** endpoint, key and model ready, a spend limit set, and the test call from the AI provider section returns `choices`.
- [ ] **Repository** cloned.
- [ ] **Readiness check:** `./bootstrap/preflight.sh` ends with `Ready.`. If it says `gitea.caipe.localtest.me` does not resolve, add the hosts line it prints.
- [ ] **Optional:** `docker login` with a free Docker Hub account, to avoid anonymous pull limits during the download.
- [ ] **Pre-pull:** `./bootstrap/prepull.sh` downloads every image and chart (about 3 GB). Do not prune Docker images afterwards.

## Corporate laptops and networks

A locked-down company laptop is the most common reason the stack cannot run; attendees should check these points with their IT team beforehand.

| Restriction | Effect | What to do |
| --- | --- | --- |
| No admin rights | Docker, the hosts file and WSL2 cannot be set up | Bring a personal laptop, or tell the organiser in advance |
| Docker Desktop licence | Some companies require a paid licence | Use Colima or OrbStack (macOS) or Docker Engine (Linux/WSL2) |
| Company AI policy | Sending workshop data to an external model may need approval | Check the policy, or use a personal provider account |
| VPN, Tailscale or corporate DNS | `*.caipe.localtest.me` may not resolve to 127.0.0.1 | Disconnect the VPN for the day, or add the hosts line from the readiness check |
| HTTPS proxy | Image downloads hang | Set the proxy in Docker too; see the setup guide |
| Blocked registries (ghcr.io, Docker Hub, quay.io) | Images cannot be pulled | Pre-pull at home, or load the image tarball from the organiser |
| Ports 8443, 3000, 7080 in use | The local services cannot start | Stop whatever listens on them; the readiness check reports it |

## Skills expected

Attendees should be comfortable in a terminal and with basic Kubernetes and Git; the labs include writing small Python functions.

- **Terminal and bash:** running scripts, setting environment variables, reading command output.
- **Kubernetes basics:** `kubectl get`, `logs` and `exec`, and what pods, deployments and secrets are.
- **Git and pull requests:** reviewing a diff and merging a pull request in a web UI (Gitea).
- **Python:** reading and completing a short function (Module 2 adds two MCP tools; Module 3 finishes two safety checks).
- **Not required:** prior experience with CNOE, CAIPE, MCP, Argo CD or Crossplane; the labs introduce them.
