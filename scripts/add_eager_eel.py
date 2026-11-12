#!/usr/bin/env python3
"""Add Eager Eel to the live public roster without erasing existing links.

Run after applying the site patch. After Cloud Terraform deploy, pipe the two
regional workshop.sh status outputs into update_landing_page.py --from-status
--reset to refresh Nicola's admin VM URL and Ben's Eager Eel VM URL.
"""
import json
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "site/workstations.json"


def update(path=DATA):
    path = Path(path)
    cfg = json.loads(path.read_text(encoding="utf-8"))
    if cfg.get("schemaVersion") != 2:
        raise ValueError("Unexpected account schema")
    accounts = cfg["accounts"]
    names = [x["username"] for x in accounts]
    if "admin" in names or len(names) not in (28, 29):
        raise ValueError("Expected 28 or 29 public accounts with admin hidden")
    if "amazinganemone" not in names:
        raise ValueError("Nicola's Amazing Anenome account is missing")
    if "eagereel" not in names:
        accounts.append({"name": "Eager Eel", "username": "eagereel", "url": None})
    elif len(accounts) != 29:
        raise ValueError("Unexpected Eager Eel configuration")
    accounts.sort(key=lambda x: x["username"])
    if len(accounts) != 29 or len(set(x["username"] for x in accounts)) != 29:
        raise ValueError("Expected 29 distinct public account entries")
    path.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("Public directory: 29 attendees; no admin account displayed")


if __name__ == "__main__":
    update()
