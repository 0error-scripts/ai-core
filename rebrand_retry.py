#!/usr/bin/env python3
"""Retry pushing rebranded Aicore repos that hit GitHub's creation rate limit.

- Skips repos already recorded in rebrand_pushed.txt
- Creates the GitHub repo (tolerates 'already exists'), pushes, records it
- Sleeps 60s between creations to stay under the rate limit
- Aborts the run on HTTP 403 so the next scheduled run retries later
- Writes ALL DONE marker when nothing remains
"""
import os
import sys
import time

sys.path.insert(0, os.path.expanduser("~/workspace/aicore"))
from rebrand_one import create_repo, push  # noqa: E402

BASE = os.path.expanduser("~/workspace/aicore")
WORK = os.path.join(BASE, "ecosystem")
PUSHED = os.path.join(BASE, "rebrand_pushed.txt")
DONE_MARKER = os.path.join(BASE, "rebrand_done.marker")
LOG = os.path.join(BASE, "rebrand_retry.log")


def log(msg):
    print(msg, flush=True)
    with open(LOG, "a") as f:
        f.write(msg + "\n")


def pushed_set():
    if not os.path.exists(PUSHED):
        return set()
    with open(PUSHED) as f:
        return {l.strip() for l in f if l.strip()}


def record(name):
    with open(PUSHED, "a") as f:
        f.write(name + "\n")


def main():
    if os.path.exists(DONE_MARKER):
        log("ALL DONE already - nothing to do")
        return

    done = pushed_set()
    pending = sorted(d for d in os.listdir(WORK)
                     if d.startswith("aicore_") and d not in done)
    if not pending:
        open(DONE_MARKER, "w").write("done\n")
        log("ALL DONE - every rebranded repo is pushed")
        return

    log(f"retry run: {len(pending)} pending")
    # One repo per run: GitHub allows slow creation but 403s rapid batches.
    for name in pending[:1]:
        dst = os.path.join(WORK, name)
        src = "qbx_" + name[len("aicore_"):]
        ok, msg = create_repo(name, f"Aicore rebrand of Qbox-project/{src} (GPL-3.0)")
        if not ok:
            if "403" in msg:
                log(f"RATE LIMITED on {name} - backing off until next run")
                return
            log(f"create failed {name}: {msg}")
            continue
        ok, msg = push(dst, name)
        if not ok:
            log(f"push failed {name}: {msg}")
            continue
        record(name)
        log(f"PUSHED {name} https://github.com/aicore-fivem/{name}")
        time.sleep(60)

    remaining = sorted(d for d in os.listdir(WORK)
                       if d.startswith("aicore_") and d not in pushed_set())
    if not remaining:
        open(DONE_MARKER, "w").write("done\n")
        log("ALL DONE - every rebranded repo is pushed")


if __name__ == "__main__":
    main()
