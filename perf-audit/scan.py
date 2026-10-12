#!/usr/bin/env python3
"""Perf hotspot scanner for aicore ecosystem (read-only)."""
import os, re, json, sys

ROOT = os.path.expanduser("~/workspace/aicore/ecosystem")

WAIT0 = re.compile(r'(?:Citizen\.)?Wait\(\s*0\s*\)')
WAIT_LOW = re.compile(r'(?:Citizen\.)?Wait\(\s*([0-9]+)\s*\)')
THREAD = re.compile(r'(?:Citizen\.)?CreateThread\s*\(')
MYSQL = re.compile(r'MySQL\.(?:Async\.(?:execute|insert|fetchAll|fetchScalar)|query(?:\.await)?|insert(?:\.await)?|update(?:\.await)?|execute(?:\.await)?|scalar(?:\.await)?|single(?:\.await)?)')
TRIG = re.compile(r'Trigger(?:Client|Server|LatentClient)Event\s*\(')
STATEBAG = re.compile(r'(?:Entity|Player|GlobalState|LocalPlayer)\s*\.state\s*:')
JSON_CALL = re.compile(r'json\.(?:encode|decode)\s*\(')
PLAYERS_ENUM = re.compile(r'GetActivePlayers\s*\(\s*\)|QBCore\.Functions\.GetQBPlayers\s*\(\s*\)')
ENTITY_ENUM = re.compile(r'GetGamePool\s*\(|EnumerateVehicles|EnumeratePeds|EnumerateObjects|GetAllVehicles|GetAllPeds')
DIST_CHECK = re.compile(r'#\s*\([^)]*-[^)]*\)|GetDistanceBetweenCoords|Vdist2?')
NUI = re.compile(r'SendNUIMessage\s*\(')
FOR_LOOP = re.compile(r'\bfor\b')

HEAVY = [PLAYERS_ENUM, ENTITY_ENUM, JSON_CALL, TRIG, STATEBAG, DIST_CHECK]

def loop_body(lines, start_idx):
    """Grab ~60 lines after thread start as loop body approximation."""
    return lines[start_idx:start_idx+60]

findings = []
repo_stats = {}

for repo in sorted(os.listdir(ROOT)):
    rdir = os.path.join(ROOT, repo)
    if not os.path.isdir(rdir):
        continue
    stats = {"wait0": 0, "wait_low": 0, "mysql_in_hot": 0, "trig_in_hot": 0,
             "players_enum_in_hot": 0, "json_in_hot": 0, "statebag_in_hot": 0,
             "nui_in_hot": 0, "files": 0}
    for dirpath, _, files in os.walk(rdir):
        for f in files:
            if not f.endswith(".lua"):
                continue
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, ROOT)
            try:
                with open(p, encoding="utf-8", errors="ignore") as fh:
                    lines = fh.readlines()
            except Exception:
                continue
            stats["files"] += 1
            text = "".join(lines)
            # find all CreateThread positions
            for m in THREAD.finditer(text):
                lineno = text[:m.start()].count("\n") + 1
                body = "".join(lines[lineno-1:lineno+59])
                waits = [int(w) for w in WAIT_LOW.findall(body)]
                is_hot = any(v <= 1 for v in waits) and ("while" in body or "Wait(0)" in body)
                if not is_hot:
                    continue
                heavy_hits = [pat.pattern for pat in HEAVY if pat.search(body)]
                mysql = bool(MYSQL.search(body))
                trig = len(TRIG.findall(body))
                if mysql:
                    stats["mysql_in_hot"] += 1
                    findings.append({"repo": repo, "file": rel, "line": lineno,
                        "pattern": "MySQL call inside per-tick thread",
                        "excerpt": body[:220].replace("\n", " \\n "),
                        "severity": "high",
                        "why": "DB write/query every frame/tick - blocks on network I/O per tick",
                        "fix": "coalesce into batch save every 5-30s or make event-driven"})
                if trig > 0:
                    stats["trig_in_hot"] += 1
                    findings.append({"repo": repo, "file": rel, "line": lineno,
                        "pattern": "TriggerEvent inside per-tick thread",
                        "excerpt": body[:220].replace("\n", " \\n "),
                        "severity": "high" if trig > 1 or any("Player" in h for h in heavy_hits) else "medium",
                        "why": f"{trig} event trigger(s) per tick - network event spam",
                        "fix": "send only on state change (diff), or at low tick rate"})
                if PLAYERS_ENUM.search(body) or ENTITY_ENUM.search(body):
                    stats["players_enum_in_hot"] += 1
                    findings.append({"repo": repo, "file": rel, "line": lineno,
                        "pattern": "player/entity enumeration inside per-tick thread",
                        "excerpt": body[:220].replace("\n", " \\n "),
                        "severity": "high" if DIST_CHECK.search(body) else "medium",
                        "why": "O(N) native enumeration every tick, often paired with distance checks",
                        "fix": "cache results, use zone enter/exit events, or raise tick interval"})
                if JSON_CALL.search(body):
                    stats["json_in_hot"] += 1
                    findings.append({"repo": repo, "file": rel, "line": lineno,
                        "pattern": "json.encode/decode inside per-tick thread",
                        "excerpt": body[:220].replace("\n", " \\n "),
                        "severity": "medium",
                        "why": "serialization cost every tick",
                        "fix": "serialize only on change / cache the string"})
                if STATEBAG.search(body):
                    stats["statebag_in_hot"] += 1
                    findings.append({"repo": repo, "file": rel, "line": lineno,
                        "pattern": "state bag write inside per-tick thread",
                        "excerpt": body[:220].replace("\n", " \\n "),
                        "severity": "medium",
                        "why": "state bag writes replicate to clients; per-tick = network churn",
                        "fix": "write only when value actually changes"})
                if NUI.search(body):
                    stats["nui_in_hot"] += 1
                    findings.append({"repo": repo, "file": rel, "line": lineno,
                        "pattern": "SendNUIMessage inside per-tick thread",
                        "excerpt": body[:220].replace("\n", " \\n "),
                        "severity": "medium",
                        "why": "NUI round-trips per tick are expensive",
                        "fix": "update UI on change or at 2-5 Hz"})
                if not any([mysql, trig, PLAYERS_ENUM.search(body), ENTITY_ENUM.search(body),
                            JSON_CALL.search(body), STATEBAG.search(body), NUI.search(body)]):
                    if DIST_CHECK.search(body):
                        stats["wait_low"] += 1
                        findings.append({"repo": repo, "file": rel, "line": lineno,
                            "pattern": "distance checks inside per-tick thread",
                            "excerpt": body[:220].replace("\n", " \\n "),
                            "severity": "medium",
                            "why": "per-frame distance polling that could be zone events",
                            "fix": "convert to ox_lib zones / enter-exit events"})
                stats["wait0"] += 1
            # bare Wait(0) outside threads (also count)
    repo_stats[repo] = stats

out = {"findings": findings, "repo_stats": repo_stats}
with open(os.path.expanduser("~/workspace/aicore/perf-audit/raw-findings.json"), "w") as fh:
    json.dump(out, fh, indent=1)
print("findings:", len(findings))
sev_rank = {}
for f in findings:
    sev_rank[f["repo"]] = sev_rank.get(f["repo"], 0) + (3 if f["severity"]=="high" else 1)
for repo, s in sorted(sev_rank.items(), key=lambda x: -x[1])[:20]:
    print(repo, s)
