#!/usr/bin/env python3
"""Turn cloud-workshops `status` output into participant-ready launch links."""

import argparse
import csv
import sys
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

WORKSHOP_FOLDER = "/home/user/masts-asm-2026-modelling/workshop"


def launch_url(url: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or not parsed.hostname.endswith(".cloudworkstations.dev"):
        raise ValueError(f"Not a Cloud Workstations URL: {url}")
    query = [(key, value) for key, value in parse_qsl(parsed.query, keep_blank_values=True)
             if key != "folder"]
    query.append(("folder", WORKSHOP_FOLDER))
    return urlunsplit(parsed._replace(query=urlencode(query)))


def parse_status(lines):
    """Extract assigned workstation rows from workshop.sh status text."""
    for line in lines:
        fields = line.split()
        if (len(fields) == 4 and fields[1].startswith("STATE_")
                and "@" in fields[2] and fields[3].startswith("https://")):
            yield fields[0], fields[2], launch_url(fields[3])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", action="store_true", help="Output CSV for private distribution")
    args = parser.parse_args()
    rows = list(parse_status(sys.stdin))
    if not rows:
        parser.error("No assigned workstations found; pipe in workshop.sh status output")
    if args.csv:
        writer = csv.writer(sys.stdout)
        writer.writerow(("workstation", "account", "launch_url"))
        writer.writerows(rows)
    else:
        print("| Workstation | Account | Launch link |")
        print("|---|---|---|")
        for workstation, account, url in rows:
            print(f"| {workstation} | {account} | [Open workstation]({url}) |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
