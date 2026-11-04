import tempfile
import unittest
from pathlib import Path

from check_documentation_images import FIGURES, PNG_SIGNATURE, check


class DocumentationImageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "index.html").write_text("<html></html>")
        assets = self.root / "assets"
        assets.mkdir()
        for page, names in FIGURES.items():
            html = self.root / "generated" / page / "index.html"
            html.parent.mkdir(parents=True)
            html.write_text("".join(f'<img src="../../assets/{name}">' for name in names))
            for name in names:
                (assets / name).write_bytes(PNG_SIGNATURE + b"DATA")

    def test_all_figures_present(self):
        self.assertEqual(check(self.root), [])

    def test_broken_relative_url(self):
        page = self.root / "generated" / "01_grazing" / "index.html"
        page.write_text(page.read_text().replace("../../assets/", "../assets/"))
        self.assertTrue(any("broken image URL" in error for error in check(self.root)))

    def test_missing_figure_embed(self):
        page = self.root / "generated" / "02_sinking" / "index.html"
        page.write_text(page.read_text().replace('<img src="../../assets/sinking_export.png">', ""))
        self.assertTrue(any("image not embedded" in error for error in check(self.root)))

    def test_missing_asset(self):
        (self.root / "assets" / "sinking_response.png").unlink()
        self.assertTrue(any("Missing or invalid PNG" in error for error in check(self.root)))


if __name__ == "__main__":
    unittest.main()
