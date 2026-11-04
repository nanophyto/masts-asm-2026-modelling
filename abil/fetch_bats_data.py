"""Install the small original Abil BATS sample datasets into the workshop.

Data are pinned to the Abil v26.5.4-2 release matching the installed package.
Run from the repository root: python abil/fetch_bats_data.py
"""

import argparse
import csv
import io
from pathlib import Path
import time
from urllib.request import urlopen

SOURCE = "https://raw.githubusercontent.com/nanophyto/Abil/v26.5.4-2/examples/data"
DATASETS = {
    "bats_training.csv": (80, {"time", "depth", "Gephyrocapsa huxleyi", "temperature", "no3", "TA", "DIC", "PAR"}),
    "bats_prediction.csv": (100, {"time", "depth", "temperature", "no3", "TA", "DIC", "PAR"}),
    "targets.csv": (1, {"Target", "pg poc", "pg pic", "n"}),
}


def validate_csv(content, minimum_rows, columns):
    reader = csv.DictReader(io.StringIO(content.decode("utf-8-sig")))
    if not reader.fieldnames or not columns.issubset(reader.fieldnames):
        raise ValueError(f"Unexpected Abil BATS CSV columns: {reader.fieldnames}")
    if sum(1 for _ in reader) < minimum_rows:
        raise ValueError("Abil BATS CSV is incomplete")


def fetch(destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    for name, (minimum_rows, columns) in DATASETS.items():
        target = destination / name
        if target.is_file():
            try:
                validate_csv(target.read_bytes(), minimum_rows, columns)
                print(f"Verified {target}")
                continue
            except ValueError:
                pass
        for attempt in range(3):
            try:
                with urlopen(f"{SOURCE}/{name}", timeout=40) as response:
                    content = response.read()
                validate_csv(content, minimum_rows, columns)
                target.write_bytes(content)
                print(f"Downloaded {target} ({len(content)} bytes)")
                break
            except (OSError, ValueError) as error:
                if attempt == 2:
                    raise RuntimeError(f"Unable to retrieve {name} from pinned Abil release") from error
                time.sleep(2 ** attempt)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, default=Path(__file__).resolve().parents[1] / "workshop/02_Abil/data")
    fetch(parser.parse_args().dest)
