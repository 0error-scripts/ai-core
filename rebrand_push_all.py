#!/usr/bin/env python3
"""Push ALL remaining aicore_* repos to GitHub now.

- Iterates every pending repo (not just one per run)
- Sleeps 120s between repo creations to stay under the creation rate limit
- On 403: waits 300s and retries the same repo (max 3 tries), then moves on
- Records each success in rebrand_pushed.txt, writes done marker at the end
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

    log(f"PUSH-ALL run: {len(pending)} pending: {', '.join(pending)}")
    failures = []
    for name in pending:
        dst = os.path.join(WORK, name)
        src = "qbx_" + name[len("aicore_"):]
        pushed = False
        for attempt in range(1, 4):
            ok, msg = create_repo(name, f"Aicore rebrand of Qbox-project/{src} (GPL-3.0)")
            if not ok:
                if "403" in msg and attempt < 3:
                    log(f"403 on {name} (attempt {attempt}) - waiting 300s")
                    time.sleep(300)
                    continue
                log(f"create failed {name}: {msg}")
                break
            ok, msg = push(dst, name)
            if not ok:
                log(f"push failed {name}: {msg}")
                break
            record(name)
            log(f"PUSHED {name} https://github.com/0error-scripts/{name}")
            pushed = True
            break
        if not pushed:
            failures.append(name)
        time.sleep(120)

    remaining = sorted(d for d in os.listdir(WORK)
                       if d.startswith("aicore_") and d not in pushed_set())
    if not remaining:
        open(DONE_MARKER, "w").write("done\n")
        log("ALL DONE - every rebranded repo is pushed")
    else:
        log(f"PUSH-ALL finished with {len(remaining)} still pending: {', '.join(remaining)}"
            + (f" (failures: {', '.join(failures)})" if failures else ""))


if __name__ == "__main__":
    main()
