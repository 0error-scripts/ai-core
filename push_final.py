#!/usr/bin/env python3
"""Push all remaining rebranded repos now that GitHub's limit is lifted.

Stops on 403 (rate limit back) so the cron can resume later.
"""
import os
import sys
import time

sys.path.insert(0, os.path.expanduser("~/workspace/aicore"))
from rebrand_one import create_repo, push  # noqa: E402

BASE = os.path.expanduser("~/workspace/aicore")
WORK = os.path.join(BASE, "ecosystem")
PUSHED = os.path.join(BASE, "rebrand_pushed.txt")
LOG = os.path.join(BASE, "rebrand_final.log")


def log(msg):
    print(msg, flush=True)
    with open(LOG, "a") as f:
        f.write(msg + "\n")


def pushed_set():
    with open(PUSHED) as f:
        return {l.strip() for l in f if l.strip()}


def main():
    done = pushed_set()
    pending = sorted(d for d in os.listdir(WORK)
                     if d.startswith("aicore_") and d not in done)
    log(f"final push: {len(pending)} pending")
    for name in pending:
        src = "qbx_" + name[len("aicore_"):]
        ok, msg = create_repo(name, f"Aicore rebrand of Qbox-project/{src} (GPL-3.0)")
        if not ok:
            if "403" in msg:
                log(f"RATE LIMITED again on {name} - stopping, cron resumes")
                return
            if "exists" not in msg:
                log(f"create failed {name}: {msg}")
                continue
        ok, msg = push(os.path.join(WORK, name), name)
        # push() is not idempotent when a commit already exists; ensure remote + push
        if not ok:
            import subprocess
            d = os.path.join(WORK, name)
            env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
            subprocess.run(["git", "remote", "remove", "origin"], cwd=d,
                           capture_output=True, env=env)
            subprocess.run(["git", "remote", "add", "origin",
                            f"https://github.com/aicore-fivem/{name}.git"],
                           cwd=d, capture_output=True, env=env)
            r = subprocess.run(["git", "push", "-u", "origin", "main"], cwd=d,
                               capture_output=True, text=True, timeout=300, env=env)
            # "Everything up-to-date" still means the content is live
            ok = r.returncode == 0
            msg = r.stderr.strip()[:200] if not ok else "pushed"
        if ok:
            done.add(name)
            with open(PUSHED, "a") as f:
                f.write(name + "\n")
            log(f"PUSHED {name}")
        else:
            log(f"push failed {name}: {msg}")
        time.sleep(15)
    log(f"FINAL: {len(done)}/60 pushed")


if __name__ == "__main__":
    main()
