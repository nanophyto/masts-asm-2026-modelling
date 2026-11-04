#!/usr/bin/env python3
"""Ensure every published workshop figure is embedded and resolves to a PNG."""

from html.parser import HTMLParser
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit


FIGURES = {
    "00_reference_column": (
        "reference_vertical_evolution.png",
        "reference_nitrogen_partition.png",
        "reference_living_fraction.png",
        "reference_carbon_export.png",
        "reference_martin_curve.png",
    ),
    "01_grazing": (
        "grazing_response.png", "grazing_plankton_balance.png", "carbon_export.png"
    ),
    "02_sinking": ("sinking_response.png", "sinking_export.png"),
    "03_remineralisation": (
        "remineralisation_response.png", "remineralisation_export.png"
    ),
    "04_light_affinity": (
        "light_affinity_response.png", "light_affinity_export.png"
    ),
    "05_nutrient_affinity": (
        "nutrient_affinity_response.png", "nutrient_affinity_export.png"
    ),
    "06_phytoplankton_mortality": (
        "phytoplankton_mortality_response.png", "phytoplankton_mortality_export.png"
    ),
    "physical_forcing": ("reference_physics.png",),
}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class Images(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sources = []

    def handle_starttag(self, tag, attrs):
        if tag == "img":
            self.sources.extend(value for name, value in attrs if name == "src" and value)


def check(build):
    build = Path(build).resolve()
    errors = []
    if not (build / "index.html").is_file():
        errors.append("Missing documentation home page")

    for page_name, expected in FIGURES.items():
        page = build / "generated" / page_name / "index.html"
        if not page.is_file():
            page = build / "generated" / f"{page_name}.html"
        if not page.is_file():
            errors.append(f"Missing documentation page: {page_name}")
            continue
        parser = Images()
        parser.feed(page.read_text(encoding="utf-8"))
        for filename in expected:
            asset = build / "assets" / filename
            if not asset.is_file() or asset.stat().st_size <= 8 or asset.read_bytes()[:8] != PNG_SIGNATURE:
                errors.append(f"Missing or invalid PNG: {asset}")
            references = [src for src in parser.sources if Path(unquote(urlsplit(src).path)).name == filename]
            if not references:
                errors.append(f"{page_name}: image not embedded: {filename}")
                continue
            for src in references:
                url = urlsplit(src)
                if url.scheme or url.netloc or url.path.startswith("/"):
                    errors.append(f"{page_name}: image must be a relative asset: {src}")
                elif (page.parent / unquote(url.path)).resolve() != asset.resolve():
                    errors.append(f"{page_name}: broken image URL: {src}")
    return errors


if __name__ == "__main__":
    errors = check(sys.argv[1] if len(sys.argv) > 1 else "docs/build")
    if errors:
        print("Documentation image validation failed:", *errors, sep="\n  - ", file=sys.stderr)
        sys.exit(1)
    print(f"Validated {sum(map(len, FIGURES.values()))} embedded workshop figures in the generated documentation.")
