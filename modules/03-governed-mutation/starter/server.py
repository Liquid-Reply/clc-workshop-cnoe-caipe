"""Gitea MCP server (Module 3 starter: two safety checks are TODOs). The only write path agents get. It can read the workload repo and open pull requests; it cannot merge."""
import base64
import json
import os
import urllib.error
import urllib.request
from pathlib import Path

from fastmcp import FastMCP

GITEA = os.environ.get("GITEA_URL", "http://my-gitea-http.gitea.svc.cluster.local:3000")
REPO = os.environ.get("GITEA_REPO", "giteaAdmin/workload")
WEB = os.environ.get("GITEA_WEB_URL", "https://gitea.caipe.localtest.me:8443")  # browser URL; html_url from the API is the in-cluster one
TOKEN = Path("/var/run/gitea/token").read_text().strip()
mcp = FastMCP("gitea")


def api(method, path, body=None):
    req = urllib.request.Request(f"{GITEA}/api/v1{path}", method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"token {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"gitea {method} {path}: {e.code} {e.read().decode()[:300]}")


@mcp.tool()
def read_file(path: str) -> str:
    """Read a file from the workload repo (branch main), e.g. 'sample-app/app.yaml'."""
    return base64.b64decode(api("GET", f"/repos/{REPO}/contents/{path}?ref=main")["content"]).decode()


@mcp.tool()
def open_pull_request(path: str, old_text: str, new_text: str, title: str, description: str, reviewed_and_approved: bool = False) -> str:
    """Propose a change as a pull request against the workload repo. Never merges.
    Edit: replace old_text (must occur exactly once) with new_text in an existing file.
    Create: leave old_text empty and put the whole file in new_text; only allowed under 'environments/' (e.g. environments/team-payments.yaml).
    Set reviewed_and_approved=true ONLY after the human user has seen the exact change and said yes; with false this is a dry run that returns the diff."""
    create = old_text == ""
    if create:
        # TODO 1: new files may only be created under environments/ (no ".." in the path); otherwise return a "refused: ..." string.
        #         This guard is the tool's real limit: the model's prompt is not.
        try:
            api("GET", f"/repos/{REPO}/contents/{path}?ref=main")
            return f"refused: {path} already exists, edit it with old_text/new_text"
        except RuntimeError:
            cur, text = None, ""
    else:
        cur = api("GET", f"/repos/{REPO}/contents/{path}?ref=main")
        text = base64.b64decode(cur["content"]).decode()
        if text.count(old_text) != 1:
            return f"refused: old_text occurs {text.count(old_text)} times in {path}, it must occur exactly once"
    # TODO 2: unless reviewed_and_approved is true, return a DRY RUN message with the diff and change nothing.
    #         (Module 5 shows why this boolean is a UX gate, not a security boundary.)
    if False:
        diff = f"NEW FILE {path}:\n{new_text}" if create else f"--- {path}\n- {old_text}\n+ {new_text}"
        return f"DRY RUN, nothing changed. Show this to the user and ask for approval:\n{diff}"
    branch = "agent/" + "".join(c if c.isalnum() else "-" for c in title.lower())[:40].strip("-")
    api("POST", f"/repos/{REPO}/branches", {"new_branch_name": branch, "old_branch_name": "main"})
    body = {"branch": branch, "message": title, "content": base64.b64encode((new_text if create else text.replace(old_text, new_text)).encode()).decode()}
    api("POST" if create else "PUT", f"/repos/{REPO}/contents/{path}", body if create else {**body, "sha": cur["sha"]})
    pr = api("POST", f"/repos/{REPO}/pulls", {"head": branch, "base": "main", "title": title, "body": description})
    return f"opened PR #{pr['number']}: {WEB}/{REPO}/pulls/{pr['number']} (a human must review and merge it)"


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)
