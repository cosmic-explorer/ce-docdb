#!/usr/bin/env python3
"""Validate the user-facing recent-documents link without contacting the site."""
from html.parser import HTMLParser
import os
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
import unittest


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.hrefs.extend(value for key, value in attrs if key == "href")


class DiscoveryLinkTest(unittest.TestCase):
    def test_recent_documents_link(self):
        root = Path(os.environ.get("DOCDB_TEST_ROOT", Path(__file__).resolve().parents[1]))
        links = Links()
        links.feed((root / "etc/shibboleth-ds/index.html").read_text())
        recent = [urlsplit(url) for url in links.hrefs if urlsplit(url).path.endswith("/ListBy")]
        self.assertEqual(len(recent), 1)
        self.assertEqual(recent[0].netloc, "dcc.cosmicexplorer.org")
        self.assertEqual(parse_qs(recent[0].query), {
            ".submit": ["Changes"], "maxdocs": ["50"], "days": ["180"],
        })


if __name__ == "__main__":
    unittest.main()
