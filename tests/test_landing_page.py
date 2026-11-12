"""Dependency-free tests for account-based workshop landing page."""

import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from update_landing_page import (  # noqa: E402
    ABIL_FOLDER,
    apply_updates,
    load_config,
    normalize_account,
    read_csv,
    updates_from_status,
)


class LandingPageTests(unittest.TestCase):
    def setUp(self):
        self.config = load_config()

    def test_roster_is_exactly_29_non_admin_names_without_roles(self):
        accounts = self.config["accounts"]
        self.assertEqual(len(accounts), 29)
        self.assertEqual(len({a["username"] for a in accounts}), 29)
        self.assertTrue(all(set(a) == {"name", "username", "url"} for a in accounts))
        self.assertTrue(any(a["name"] == "Cheerful Crab" and a["username"] == "cheerfulcrab" for a in accounts))
        self.assertEqual(accounts[-1]["username"], "zestyzebrafish")
        self.assertNotIn("admin", [a["username"] for a in accounts])
        self.assertIn("eagereel", [a["username"] for a in accounts])
        self.assertNotIn("admin" + "@nanophyto.org", json.dumps(self.config))
        self.assertFalse(any("@" in a["name"] or "@" in a["username"] for a in accounts))

    def test_friendly_name_username_and_email_map_to_same_workstation(self):
        for name in ("Cheerful Crab", "cheerfulcrab", "CheErFuLcRaB", "cheerfulcrab@nanophyto.org"):
            with self.subTest(name=name):
                self.assertEqual(normalize_account(name, self.config), "cheerfulcrab")
        for invalid in ("07", "mast-07", "admin", "admin" + "@nanophyto.org", "cheerfulcrab@example.com"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                normalize_account(invalid, self.config)

    def test_csv_prefers_account_column_over_workstation_number(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "private.csv"
            with path.open("w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(("workstation", "account", "launch_url"))
                writer.writerow(("mast-27", "cheerfulcrab@nanophyto.org", "https://one.cloudworkstations.dev"))
                writer.writerow(("mast-01", "wise walrus", "https://two.cloudworkstations.dev"))
            updated = apply_updates(self.config, list(read_csv(path)), reset=True)
        by_name = {a["username"]: a["url"] for a in updated["accounts"]}
        self.assertEqual(sum(bool(v) for v in by_name.values()), 2)
        self.assertIn("one.cloudworkstations.dev", by_name["cheerfulcrab"])
        self.assertIn("two.cloudworkstations.dev", by_name["wisewalrus"])
        self.assertIn("02_Abil", by_name["cheerfulcrab"])
        self.assertNotIn("@nanophyto.org", json.dumps(updated))

    def test_status_import_uses_account_even_if_numeric_workstation_differs(self):
        lines = [
            "mast-01 STATE_STOPPED cheerfulcrab@nanophyto.org https://london.cloudworkstations.dev\n",
            "mast-29 STATE_RUNNING zestyZebrafish@nanophyto.org https://belgium.cloudworkstations.dev\n",
        ]
        updates = updates_from_status(lines)
        self.assertEqual(updates[0][0], "cheerfulcrab@nanophyto.org")
        updated = apply_updates(self.config, updates)
        urls = {a["username"]: a["url"] for a in updated["accounts"]}
        self.assertIn("london.cloudworkstations.dev", urls["cheerfulcrab"])
        self.assertIn("belgium.cloudworkstations.dev", urls["zestyzebrafish"])
        self.assertIn("02_Abil", urls["zestyzebrafish"])

    def test_regions_merge_without_losing_previous_urls(self):
        london = apply_updates(self.config, [("cheerfulcrab", "https://london.cloudworkstations.dev")], reset=True)
        both = apply_updates(london, [("zestyzebrafish", "https://belgium.cloudworkstations.dev")])
        self.assertEqual(sum(bool(a["url"]) for a in both["accounts"]), 2)

    def test_bad_links_duplicate_account_and_duplicate_url_are_rejected(self):
        for url in ("http://one.cloudworkstations.dev", "https://example.com", "https://cloudworkstations.dev", "https://user@one.cloudworkstations.dev"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                apply_updates(self.config, [("cheerfulcrab", url)])
        with self.assertRaises(ValueError):
            apply_updates(self.config, [("cheerfulcrab", "https://one.cloudworkstations.dev"), ("Cheerful Crab", "https://two.cloudworkstations.dev")])
        with self.assertRaises(ValueError):
            apply_updates(self.config, [("cheerfulcrab", "https://one.cloudworkstations.dev"), ("wisewalrus", "https://one.cloudworkstations.dev")])
        self.assertEqual(len(self.config["accounts"]), 29)

    def test_config_rejects_admin_and_duplicate_usernames(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "workstations.json"
            path.write_text(json.dumps(self.config))
            self.assertEqual(len(load_config(path)["accounts"]), 29)
            self.config["accounts"][0]["username"] = "admin"
            path.write_text(json.dumps(self.config))
            with self.assertRaises(ValueError):
                load_config(path)
            self.config["accounts"][0]["username"] = "cheerfulcrab"
            path.write_text(json.dumps(self.config))
            with self.assertRaises(ValueError):
                load_config(path)

    def test_page_shows_full_email_and_no_explanatory_panels(self):
        index = (ROOT / "site" / "index.html").read_text(encoding="utf-8")
        app = (ROOT / "site" / "app.js").read_text(encoding="utf-8")
        style = (ROOT / "site" / "style.css").read_text(encoding="utf-8")
        self.assertIn('username.textContent = `${account.username}@nanophyto.org`', app)
        self.assertIn('amazinganemone@nanophyto.org', index)
        for removed in ('class="help-section"', 'class="support-note"',
                        'A smooth start', 'Need a hand?'):
            self.assertNotIn(removed, index)
        self.assertNotIn('.help-section', style)
        self.assertNotIn('.support-note', style)

    def test_public_site_publishes_vm_selector_instead_of_julia_docs(self):
        workflow = (ROOT / '.github/workflows/documentation.yml').read_text()
        page = (ROOT / 'site/index.html').read_text()
        app = (ROOT / 'site/app.js').read_text()
        self.assertIn('path: site/', workflow)
        self.assertNotIn('docs/build', workflow)
        self.assertNotIn('docs/make.jl', workflow)
        self.assertIn('Find your workstation', page)
        self.assertIn('29 accounts', page)
        self.assertIn('config.accounts.length !== 29', app)
        self.assertIn('Open workstation', app)

    def test_page_has_no_hero_and_no_role_split(self):
        index = (ROOT / "site" / "index.html").read_text(encoding="utf-8")
        app = (ROOT / "site" / "app.js").read_text(encoding="utf-8")
        self.assertNotIn('class="hero"', index)
        self.assertNotIn("Participant workstations", index + app)
        self.assertNotIn("Organiser workstations", index + app)
        self.assertNotIn("station number", index.lower())
        self.assertIn("Find your workstation", index)


if __name__ == "__main__":
    unittest.main()
