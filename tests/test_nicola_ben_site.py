"""Preserve existing site links while adding Ben's Eager Eel account."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from add_eager_eel import update
from update_landing_page import load_config, apply_updates


class SiteReassignmentTests(unittest.TestCase):
    def test_add_eager_eel_preserves_existing_urls_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "workstations.json"
            baseline = json.loads((ROOT / "site/workstations.json").read_text())
            baseline["accounts"] = [x for x in baseline["accounts"] if x["username"] != "eagereel"]
            baseline["accounts"][0]["url"] = "https://one.cluster.cloudworkstations.dev"
            file.write_text(json.dumps(baseline))
            update(file)
            update(file)
            new = load_config(file)
            self.assertEqual(len(new["accounts"]), 29)
            self.assertIn("eagereel", [x["username"] for x in new["accounts"]])
            self.assertEqual(next(x["url"] for x in new["accounts"] if x["username"] == baseline["accounts"][0]["username"]), "https://one.cluster.cloudworkstations.dev")
            updated = apply_updates(new, [("amazinganemone@nanophyto.org", "https://admin.cluster.cloudworkstations.dev"),
                                          ("eagereel@nanophyto.org", "https://eagereel.cluster.cloudworkstations.dev")], reset=False)
            links = {x["username"]: x["url"] for x in updated["accounts"]}
            self.assertIn("admin.cluster", links["amazinganemone"])
            self.assertIn("eagereel.cluster", links["eagereel"])


if __name__ == "__main__":
    unittest.main()
