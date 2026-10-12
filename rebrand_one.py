#!/usr/bin/env python3
"""Rebrand one QBox satellite resource as Aicore.

Usage: rebrand_one.py <qbx_repo_name> [--push]

- Shallow-clones Qbox-project/<name> into ecosystem/aicore_<short>/
- Applies ordered renames (qbx_ -> aicore_, QBox -> Aicore, URLs, ...)
- Replaces brand logo SVGs with the Aicore mark (#49c59a)
- Appends GPL attribution footer to README
- Verification report printed; --push creates the GitHub repo and pushes.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

ORG_SRC = "Qbox-project"
ORG_DST = "aicore-fivem"
WORK = os.path.expanduser("~/workspace/aicore/ecosystem")
LOGO = os.path.expanduser("~/workspace/aicore/brand/aicore-logo.svg")

# Ordered literal replacements (most-specific first).
REPLACEMENTS = [
    ("https://github.com/Qbox-project/", "https://github.com/aicore-fivem/"),
    ("http://github.com/Qbox-project/", "https://github.com/aicore-fivem/"),
    ("Qbox-project", "aicore-fivem"),
    ("qbx_core", "aicore"),
    ("qbx-", "aicore-"),
    ("qbx_", "aicore_"),
    ("qbx:", "aicore:"),
    ("QBX", "AICORE"),
    ("Qbx", "Aicore"),
]
REGEX_REPLACEMENTS = [
    (re.compile(r"\bQBox\b"), "Aicore"),
    (re.compile(r"\bQbox\b"), "Aicore"),
    (re.compile(r"\bqbox\b"), "aicore"),
    (re.compile(r"\bqbx\b"), "aicore"),
]

BINARY_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".ico", ".ttf", ".otf",
    ".woff", ".woff2", ".eot", ".mp3", ".ogg", ".wav", ".mp4", ".webm",
    ".ytd", ".ydd", ".yft", ".ydr", ".zip", ".rar", ".7z", ".pdb", ".dll",
}
SKIP_DIRS = {".git"}
# LICENSE stays verbatim (GPL requires it).
SKIP_FILES = {"LICENSE"}


def is_text(path):
    try:
        with open(path, "rb") as f:
            chunk = f.read(65536)
        chunk.decode("utf-8")
        return True
    except (UnicodeDecodeError, OSError):
        return False


def transform_text(text, fname):
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    for pattern, new in REGEX_REPLACEMENTS:
        text = pattern.sub(new, text)
    # Normalize author line in fxmanifest.
    if fname == "fxmanifest.lua":
        text = re.sub(r"(?m)^author\s+['\"].*?['\"]", "author 'Aicore'", text)
    return text


def rebrand(src_name):
    short = src_name[4:] if src_name.startswith("qbx_") else src_name
    dst_name = "aicore_" + short
    dst = os.path.join(WORK, dst_name)
    if os.path.exists(dst):
        shutil.rmtree(dst)
    os.makedirs(WORK, exist_ok=True)

    r = subprocess.run(
        ["git", "clone", "--depth", "1", "-q",
         f"https://github.com/{ORG_SRC}/{src_name}.git", dst],
        capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        return None, f"clone failed: {r.stderr.strip()[:200]}"

    shutil.rmtree(os.path.join(dst, ".git"), ignore_errors=True)

    files_changed, logo_replaced = 0, 0
    for root, dirs, files in os.walk(dst):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            p = os.path.join(root, f)
            if f in SKIP_FILES:
                continue
            ext = os.path.splitext(f)[1].lower()
            if ext in BINARY_EXTS:
                continue
            # Brand logos -> Aicore mark.
            if "logo" in f.lower() and ext == ".svg":
                shutil.copy(LOGO, p)
                logo_replaced += 1
                continue
            if not is_text(p):
                continue
            with open(p, "r", encoding="utf-8") as fh:
                original = fh.read()
            new = transform_text(original, f)
            if new != original:
                with open(p, "w", encoding="utf-8") as fh:
                    fh.write(new)
                files_changed += 1

    # Attribution footer on README (after transforms so the URL stays intact).
    for readme in ("README.md", "readme.md"):
        rp = os.path.join(dst, readme)
        if os.path.exists(rp):
            with open(rp, "a", encoding="utf-8") as fh:
                fh.write(
                    f"\n> Rebranded from [{ORG_SRC}/{src_name}]"
                    f"(https://github.com/{ORG_SRC}/{src_name}) under GPL-3.0. "
                    f"Original work © QBox Project contributors.\n")
            break

    # Verification: any leftover branding?
    leftovers = []
    for root, dirs, files in os.walk(dst):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            p = os.path.join(root, f)
            if f in SKIP_FILES or os.path.splitext(f)[1].lower() in BINARY_EXTS:
                continue
            if not is_text(p):
                continue
            with open(p, "r", encoding="utf-8") as fh:
                content = fh.read()
            for pat in (r"qbx_", r"qbx-", r"qbx:", r"\bQbox\b", r"\bQBox\b",
                        r"Qbox-project", r"\bqbx\b"):
                if re.search(pat, content):
                    # qb-core / QBCore are handled by the compat bridge: keep.
                    lines = [ln for ln in content.splitlines()
                             if re.search(pat, ln) and "qb-core" not in ln.lower()
                             and "QBCore" not in ln]
                    if lines:
                        leftovers.append(
                            f"{os.path.relpath(p, dst)}:{lines[0].strip()[:90]}")
                    break

    return dst, {
        "files_changed": files_changed,
        "logo_replaced": logo_replaced,
        "leftovers": leftovers[:10],
    }


def get_token():
    with open(os.path.expanduser("~/.git-credentials")) as fh:
        lines = fh.read().strip().splitlines()
    for line in lines:
        if "github.com" not in line:
            continue
        m = re.search(r"https://[^:]+:([^@]+)@github\.com", line)
        if m:
            return m.group(1)
    raise RuntimeError("could not parse token from git-credentials")


def create_repo(name, description):
    token = get_token()
    data = json.dumps({
        "name": name,
        "description": description[:120],
        "private": False,
        "auto_init": False,
    }).encode()
    req = urllib.request.Request(
        "https://api.github.com/user/repos", data=data,
        headers={"Authorization": f"token {token}",
                 "Accept": "application/vnd.github.v3+json",
                 "User-Agent": "aicore-rebrand"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status in (200, 201), ""
    except Exception as e:
        body = getattr(e, "read", lambda: b"")()
        if "already exists" in str(body):
            return True, "exists"
        return False, str(e)[:200]


def push(dst, name):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    cmds = [
        ["git", "init", "-q"],
        ["git", "add", "-A"],
        ["git", "-c", "user.name=Aicore", "-c", "user.email=aicore@local",
         "commit", "-qm", f"Rebrand {name} from QBox (GPL-3.0) as Aicore"],
        ["git", "branch", "-M", "main"],
        ["git", "remote", "add", "origin",
         f"https://github.com/{ORG_DST}/{name}.git"],
        ["git", "push", "-q", "origin", "main"],
    ]
    for c in cmds:
        r = subprocess.run(c, cwd=dst, capture_output=True, text=True,
                           timeout=180, env=env)
        if r.returncode != 0:
            return False, f"{' '.join(c[:3])}: {r.stderr.strip()[:200]}"
    return True, ""


def main():
    if len(sys.argv) < 2:
        print("usage: rebrand_one.py <qbx_repo> [--push]")
        sys.exit(1)
    src = sys.argv[1]
    do_push = "--push" in sys.argv

    dst, info = rebrand(src)
    if dst is None:
        print(json.dumps({"repo": src, "ok": False, "error": info}))
        return
    result = {"repo": src, "ok": True, "dir": dst, **info}

    if do_push:
        short = src[4:] if src.startswith("qbx_") else src
        name = "aicore_" + short
        ok, msg = create_repo(
            name, f"Aicore rebrand of Qbox-project/{src} (GPL-3.0)")
        if not ok:
            result.update(ok=False, error=f"create_repo: {msg}")
            print(json.dumps(result))
            return
        ok, msg = push(dst, name)
        result.update(ok=ok, pushed=ok, push_error=msg,
                     url=f"https://github.com/{ORG_DST}/{name}")

    print(json.dumps(result))


if __name__ == "__main__":
    main()
