"""Gitea MCP server: the only write path agents get. It can read the workload repo and open pull requests; it cannot merge."""
import base64
import json
import os
import re
import secrets
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
    Never write reviewed_and_approved: true into a file: the human reviewer flips that field in the PR.
    Set the reviewed_and_approved argument to true ONLY after the human user has seen the exact change and said yes; with false this is a dry run that returns the diff."""
    create = old_text == ""
    if re.search(r"reviewed_and_approved:\s*true", new_text, re.IGNORECASE):
        return "refused: only the human reviewer may set reviewed_and_approved: true in a file; propose it as false"
    if create:
        if not path.startswith("environments/") or ".." in path:
            return "refused: new files may only be created under environments/"
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
    if not reviewed_and_approved:
        diff = f"NEW FILE {path}:\n{new_text}" if create else f"--- {path}\n- {old_text}\n+ {new_text}"
        return f"DRY RUN, nothing changed. Show this to the user and ask for approval:\n{diff}"
    # random suffix: titles that differ only after the cut, or a retried title, must not reuse a branch (Gitea 409)
    branch = "agent/" + "".join(c if c.isalnum() else "-" for c in title.lower())[:40].strip("-") + "-" + secrets.token_hex(3)
    api("POST", f"/repos/{REPO}/branches", {"new_branch_name": branch, "old_branch_name": "main"})
    body = {"branch": branch, "message": title, "content": base64.b64encode((new_text if create else text.replace(old_text, new_text)).encode()).decode()}
    api("POST" if create else "PUT", f"/repos/{REPO}/contents/{path}", body if create else {**body, "sha": cur["sha"]})
    # the model forgets to tell the reviewer about the flag (seen in rehearsal), so the tool says it every time
    note = "\n\nReviewer: Crossplane builds nothing until reviewed_and_approved is true in this file. Set it on this PR's branch BEFORE merging." if create else ""
    pr = api("POST", f"/repos/{REPO}/pulls", {"head": branch, "base": "main", "title": title, "body": description + note})
    return f"opened PR #{pr['number']}: {WEB}/{REPO}/pulls/{pr['number']} (a human must review and merge it){note}"


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)
