#!/usr/bin/env python3
"""Update Abil.py workstation URLs by their nanophyto.org account names.

Examples:
  python3 scripts/update_landing_page.py --set cheerfulcrab 'https://example.cloudworkstations.dev'
  python3 scripts/update_landing_page.py --set 'Cheerful Crab' 'https://example.cloudworkstations.dev'
  python3 scripts/update_landing_page.py --csv /path/to/assigned-links.csv
  ./scripts/workshop.sh status masts-2026 | python3 /path/to/scripts/update_landing_page.py --from-status
  python3 scripts/update_landing_page.py --check

The CSV may contain account,launch_url; username,url; or
workstation,account,launch_url (the account column is preferred). No passwords,
email addresses, account mappings or participant roles are copied into the page.
"""

import argparse
import csv
import json
import re
import sys
from pathlib import Path

from workstation_links import ABIL_FOLDER, launch_url, parse_status

DATA_FILE = Path(__file__).resolve().parents[1] / "site" / "workstations.json"
DOMAIN = "@nanophyto.org"


def normalize_account(value: str, config) -> str:
    """Resolve a display name, username or nanophyto.org address to its username."""
    name = str(value).strip().lower()
    if "@" in name and not name.endswith(DOMAIN):
        raise ValueError(f"Not a nanophyto.org account: {value!r}")
    if name.endswith(DOMAIN):
        name = name[:-len(DOMAIN)]
    key = re.sub(r"[^a-z0-9]", "", name)
    lookup = {item["username"]: item["username"] for item in config["accounts"]}
    lookup.update({
        re.sub(r"[^a-z0-9]", "", item["name"].lower()): item["username"]
        for item in config["accounts"]
    })
    if key not in lookup:
        raise ValueError(f"Unknown workshop account {value!r}; check the Google account name")
    return lookup[key]


def load_config(path=DATA_FILE):
    config = json.loads(Path(path).read_text(encoding="utf-8"))
    accounts = config.get("accounts", [])
    if config.get("schemaVersion") != 2 or len(accounts) != 29:
        raise ValueError("Configuration must contain exactly 29 workshop accounts (schema version 2)")
    seen = set()
    for item in accounts:
        if set(item) != {"name", "username", "url"}:
            raise ValueError("Each account must contain only name, username and url")
        username = item["username"]
        if (not isinstance(username, str) or not re.fullmatch(r"[a-z0-9]+", username)
                or username == "admin" or username in seen):
            raise ValueError(f"Invalid, duplicate or administrative username {username!r}")
        seen.add(username)
        if (not isinstance(item["name"], str) or not item["name"].strip()
                or "@" in item["name"]):
            raise ValueError(f"Invalid display name for {username}")
        url = item["url"]
        if url is not None:
            if not isinstance(url, str):
                raise ValueError(f"Invalid URL type for {username}")
            try:
                launch_url(url, folder=ABIL_FOLDER)
            except ValueError as exc:
                raise ValueError(f"Invalid launch URL for {username}") from exc
    return config


def read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        headings = set(reader.fieldnames or [])
        account_col = next((c for c in (
            "account", "username", "email", "Email Address [Required]", "workstation", "name"
        ) if c in headings), None)
        url_col = next((c for c in ("launch_url", "url") if c in headings), None)
        if account_col is None or url_col is None:
            raise ValueError("CSV needs account,launch_url or username,url columns")
        for row in reader:
            if row.get(url_col, "") and row[url_col].strip():
                if not row.get(account_col, "").strip():
                    raise ValueError("CSV row has a URL but no account name")
                yield row[account_col], row[url_col].strip()


def updates_from_status(stream):
    """Use the *assigned Google account* column, never workstation numbering."""
    matches = list(parse_status(stream, folder=ABIL_FOLDER))
    if not matches:
        raise ValueError("No workstation URLs found in status output")
    return [(account, url) for _workstation, account, url in matches]


def apply_updates(config, updates, reset=False):
    """Merge London/Belgium updates, validate all, and return new config."""
    merged = {
        account["username"]: None if reset else account["url"]
        for account in config["accounts"]
    }
    seen = set()
    for raw_account, raw_url in updates:
        username = normalize_account(raw_account, config)
        if username in seen:
            raise ValueError(f"Account {username} appears twice in the input")
        seen.add(username)
        merged[username] = launch_url(raw_url, folder=ABIL_FOLDER)
    urls = [url for url in merged.values() if url]
    if len(urls) != len(set(urls)):
        raise ValueError("A workstation URL is assigned to more than one account")
    return {
        **config,
        "accounts": [{**item, "url": merged[item["username"]]} for item in config["accounts"]],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--set", nargs=2, metavar=("ACCOUNT", "URL"), help="Set one account's link")
    action.add_argument("--csv", metavar="PATH", help="Import an account,launch_url CSV")
    action.add_argument("--from-status", action="store_true", help="Read cloud-workshops status from stdin")
    action.add_argument("--check", action="store_true", help="Validate and count configured URLs")
    parser.add_argument("--reset", action="store_true", help="Clear old URLs before an import")
    args = parser.parse_args(argv)
    if args.reset and (args.set or args.check):
        parser.error("--reset is only available with --csv or --from-status")
    try:
        config = load_config()
        if args.set:
            updates = [tuple(args.set)]
        elif args.csv:
            updates = list(read_csv(args.csv))
            if not updates:
                raise ValueError("CSV contains no account URLs")
        elif args.from_status:
            updates = updates_from_status(sys.stdin)
        else:
            updates = []
        if not args.check:
            config = apply_updates(config, updates, reset=args.reset)
            DATA_FILE.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        configured = sum(bool(item["url"]) for item in config["accounts"])
        print(f"Landing page: {configured}/{len(config['accounts'])} account links configured.")
        if not args.check:
            print(f"Updated: {DATA_FILE}")
            print("Only account display names, usernames and workstation URLs are published.")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        parser.exit(1, f"Error: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
