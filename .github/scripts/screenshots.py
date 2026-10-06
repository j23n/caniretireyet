#!/usr/bin/env python3
"""The UI tests' screenshots in CI (App/UITests, ci.yml "UI tests and screenshots").

  screenshots.py pick-iphone                 the UDID of an iPhone simulator to test on:
                                             the newest iOS, an "iPhone NN Pro" if there is one
  screenshots.py collect RESULTS OUT         each result bundle's screenshots, as
                                             OUT/<bundle>-<name>.png
  screenshots.py print OUT                   each screenshot as a small JPEG in base64,
                                             between "=== screenshot NAME ===" and
                                             "=== end ===", for reading them from the log
"""

import base64
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile


def pick_iphone() -> None:
    listing = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                             check=True, capture_output=True, text=True).stdout
    candidates = []
    for runtime, devices in json.loads(listing)["devices"].items():
        version = re.search(r"iOS-(\d+)-(\d+)", runtime)
        if not version:
            continue
        for device in devices:
            name = device["name"]
            if name.startswith("iPhone"):
                plain = re.fullmatch(r"iPhone \d+( Pro)?", name) is not None
                candidates.append(((int(version[1]), int(version[2])), plain, name.endswith(" Pro"), name,
                                   device["udid"]))
    if not candidates:
        sys.exit("No iPhone simulator available.")
    chosen = max(candidates)
    print(f"{chosen[3]}, iOS {chosen[0][0]}.{chosen[0][1]}", file=sys.stderr)
    print(chosen[4])


def attachments(manifest: object):
    """Every attachment entry in an exported manifest, wherever it's nested."""
    if isinstance(manifest, dict):
        if "exportedFileName" in manifest:
            yield manifest
        for value in manifest.values():
            yield from attachments(value)
    elif isinstance(manifest, list):
        for value in manifest:
            yield from attachments(value)


def collect(results: pathlib.Path, out: pathlib.Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for bundle in sorted(results.glob("*.xcresult")):
        with tempfile.TemporaryDirectory() as exported:
            subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                            "--output-path", exported], check=True)
            manifest = json.loads((pathlib.Path(exported) / "manifest.json").read_text())
            for entry in attachments(manifest):
                source = pathlib.Path(exported) / entry["exportedFileName"]
                suggested = entry.get("suggestedHumanReadableName") or source.name
                # "plan_0_1F2E….png" → "plan".
                name = re.sub(r"_\d+_[0-9A-Fa-f-]+$", "", pathlib.Path(suggested).stem)
                target = out / f"{bundle.stem}-{name}{source.suffix}"
                shutil.copyfile(source, target)
                print(target.name)


def print_screenshots(out: pathlib.Path) -> None:
    for image in sorted(out.glob("*.png")):
        with tempfile.TemporaryDirectory() as scratch:
            small = pathlib.Path(scratch) / "small.jpg"
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "50", "-Z", "1000", str(image),
                            "--out", str(small)], check=True, capture_output=True)
            encoded = base64.encodebytes(small.read_bytes()).decode()
        print(f"=== screenshot {image.stem} ===")
        print(encoded, end="")
        print("=== end ===")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "pick-iphone":
        pick_iphone()
    elif command == "collect" and len(sys.argv) == 4:
        collect(pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]))
    elif command == "print" and len(sys.argv) == 3:
        print_screenshots(pathlib.Path(sys.argv[2]))
    else:
        sys.exit(__doc__)
