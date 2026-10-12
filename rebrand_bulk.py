#!/usr/bin/env python3
"""Bulk rebrand: all maintained QBox satellites -> Aicore, pushed to GitHub."""
import json
import subprocess
import sys

REPOS = """qbx_adminmenu qbx_ambulancejob qbx_bankrobbery qbx_binoculars qbx_busjob
qbx_carwash qbx_chat_theme qbx_cityhall qbx_crypto qbx_customs qbx_density
qbx_divegear qbx_diving qbx_drugs qbx_dutyblips qbx_evidence qbx_fireworks
qbx_garages qbx_garbagejob qbx_helicam qbx_houserobbery qbx_idcard qbx_jewelery
qbx_lapraces qbx_management qbx_mechanicjob qbx_medical qbx_newsjob qbx_nitro
qbx_pawnshop qbx_phone qbx_playerstates qbx_police qbx_properties qbx_radialmenu
qbx_radio qbx_recyclejob qbx_scoreboard qbx_scrapyard qbx_seatbelt qbx_skillbar
qbx_smallresources qbx_spawn qbx_storerobbery qbx_streetraces qbx_taxijob
qbx_towjob qbx_traphouse qbx_truckerjob qbx_truckrobbery qbx_tunerchip
qbx_vehiclefailure qbx_vehiclekeys qbx_vehicles qbx_vehiclesales qbx_vehicleshop
qbx_vineyard qbx_weathersync qbx_weed""".split()

LOG = "/home/hatch/workspace/aicore/rebrand_bulk.log"

def log(msg):
    line = msg
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")

def main():
    done, failed = [], []
    for repo in REPOS:
        r = subprocess.run(
            [sys.executable, "/home/hatch/workspace/aicore/rebrand_one.py",
             repo, "--push"],
            capture_output=True, text=True, timeout=600)
        try:
            d = json.loads(r.stdout.strip().splitlines()[-1])
        except Exception:
            d = {"ok": False, "error": f"bad output: {r.stdout[-200:]} {r.stderr[-200:]}"}
        if d.get("ok"):
            done.append(repo)
            lo = len(d.get("leftovers", []))
            log(f"OK   {repo} -> {d.get('url')} (files:{d.get('files_changed')} logos:{d.get('logo_replaced')} leftovers:{lo})")
        else:
            failed.append(repo)
            log(f"FAIL {repo}: {d.get('error') or d.get('push_error')}")
    log(f"DONE: {len(done)} ok, {len(failed)} failed: {failed}")

if __name__ == "__main__":
    main()
