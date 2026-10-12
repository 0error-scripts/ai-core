#!/usr/bin/env python3
"""Push transformed repos to GitHub repos the user created manually.

Usage: push_existing.py <name> [<name> ...]
Assumes https://github.com/aicore-fivem/<name> already exists and is empty.
Records successes in rebrand_pushed.txt.
"""
import os
import subprocess
import sys
import urllib.request

BASE = os.path.expanduser("~/workspace/aicore")
WORK = os.path.join(BASE, "ecosystem")
ORG = "aicore-fivem"
PUSHED = os.path.join(BASE, "rebrand_pushed.txt")


def run(cmd, cwd):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                       timeout=300,
                       env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
    return r.returncode == 0, (r.stderr.strip() or r.stdout.strip())[:200]


def repo_exists(name):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{ORG}/{name}",
        headers={"Accept": "application/vnd.github.v3+json",
                 "User-Agent": "aicore-rebrand"})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status == 200
    except Exception:
        return False


def push_one(name):
    dst = os.path.join(WORK, name)
    if not os.path.isdir(dst):
        return False, "no local dir"
    if not repo_exists(name):
        return False, "github repo does not exist yet"
    steps = [
        ["git", "init", "-q"],
        ["git", "add", "-A"],
        ["git", "-c", "user.name=Aicore", "-c", "user.email=aicore@local",
         "commit", "-qm", f"Rebrand {name} from QBox (GPL-3.0) as Aicore"],
        ["git", "branch", "-M", "main"],
    ]
    for c in steps:
        ok, msg = run(c, dst)
        if not ok and "nothing to commit" not in msg:
            return False, f"{c[1]}: {msg}"
    # (re)point remote at the user-created repo, then push
    run(["git", "remote", "remove", "origin"], dst)
    ok, msg = run(["git", "remote", "add", "origin",
                   f"https://github.com/{ORG}/{name}.git"], dst)
    if not ok:
        return False, f"remote add: {msg}"
    ok, msg = run(["git", "push", "-u", "origin", "main"], dst)
    if not ok:
        return False, f"push: {msg}"
    with open(PUSHED, "a") as f:
        f.write(name + "\n")
    return True, f"https://github.com/{ORG}/{name}"


def main():
    for name in sys.argv[1:]:
        ok, msg = push_one(name)
        print(("OK   " if ok else "FAIL ") + f"{name}: {msg}", flush=True)


if __name__ == "__main__":
    main()
