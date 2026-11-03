"""Tests for the participant link generator."""

import unittest
from urllib.parse import parse_qs, urlsplit

from workstation_links import WORKSHOP_FOLDER, launch_url, parse_status


class ParticipantLinksTests(unittest.TestCase):
    def test_link_opens_only_the_participant_workspace(self):
        url = launch_url("https://masts-01.cluster-abc.cloudworkstations.dev/")
        self.assertEqual(parse_qs(urlsplit(url).query)["folder"], [WORKSHOP_FOLDER])

    def test_existing_query_parameters_are_preserved(self):
        url = launch_url("https://masts-01.cluster-abc.cloudworkstations.dev/?foo=bar&folder=/old")
        self.assertEqual(parse_qs(urlsplit(url).query),
                         {"foo": ["bar"], "folder": [WORKSHOP_FOLDER]})

    def test_status_extracts_assigned_workstations(self):
        log = """Project: masts-modelling-workshops
WORKSTATION  STATE          ACCOUNT                         URL
masts-01     STATE_RUNNING  admin@nanophyto.org              https://masts-01.cluster-abc.cloudworkstations.dev
masts-02     STATE_STOPPED  bouncybarnacle@nanophyto.org     https://masts-02.cluster-abc.cloudworkstations.dev
"""
        rows = list(parse_status(log.splitlines()))
        self.assertEqual([(station, account) for station, account, _ in rows],
                         [("masts-01", "admin@nanophyto.org"),
                          ("masts-02", "bouncybarnacle@nanophyto.org")])
        self.assertTrue(all(parse_qs(urlsplit(url).query)["folder"] == [WORKSHOP_FOLDER]
                            for _, _, url in rows))


if __name__ == "__main__":
    unittest.main()
