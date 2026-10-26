#!/usr/bin/env python3
"""The screen tests' pictures (App/ScreenTests, `make screenshots`, App/README.md "Screenshots").

  screenshots.py pick-iphone                 the UDID of an iPhone simulator to test on:
                                             the newest iOS, an "iPhone NN Pro" if there is one
  screenshots.py pick-ipad                   the UDID of an iPad simulator to test on:
                                             the newest iOS, a 13-inch iPad Pro if there is one
  screenshots.py print OUT                   each screenshot as a small JPEG in base64,
                                             between "=== screenshot NAME ===" and
                                             "=== end ===", for reading them from the log
  screenshots.py failures RESULTS            each result bundle's failed tests and why,
                                             and the app's crash reports, at the end of
                                             the log
"""

import base64
import json
import pathlib
import re
import subprocess
import sys
import tempfile


def pick_simulator(family: str) -> None:
    listing = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                             check=True, capture_output=True, text=True).stdout
    candidates = []
    for runtime, devices in json.loads(listing)["devices"].items():
        version = re.search(r"iOS-(\d+)-(\d+)", runtime)
        if not version:
            continue
        for device in devices:
            name = device["name"]
            if not name.startswith(family):
                continue
            if family == "iPhone":
                preferred = (re.fullmatch(r"iPhone \d+( Pro)?", name) is not None, name.endswith(" Pro"))
            else:
                preferred = (name.startswith("iPad Pro"), "13-inch" in name)
            candidates.append(((int(version[1]), int(version[2])), preferred, name, device["udid"]))
    if not candidates:
        sys.exit(f"No {family} simulator available.")
    chosen = max(candidates)
    print(f"{chosen[2]}, iOS {chosen[0][0]}.{chosen[0][1]}", file=sys.stderr)
    print(chosen[3])


def print_screenshots(out: pathlib.Path) -> None:
    for image in sorted(out.glob("*.png")):
        with tempfile.TemporaryDirectory() as scratch:
            small = pathlib.Path(scratch) / "small.jpg"
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "50", "-Z", "1000", str(image),
                            "--out", str(small)], check=True, capture_output=True)
            encoded = base64.b64encode(small.read_bytes()).decode()
        # Few, long lines: a log is read from its end, a number of lines at a time.
        print(f"=== screenshot {image.stem} ===")
        for start in range(0, len(encoded), 8000):
            print(encoded[start:start + 8000])
        print("=== end ===")


def failures(results: pathlib.Path) -> None:
    for bundle in sorted(results.glob("*.xcresult")):
        summary = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)],
                                 capture_output=True, text=True)
        print(f"=== {bundle.stem} ===")
        if summary.returncode != 0:
            print(summary.stderr.strip())
            continue
        result = json.loads(summary.stdout)
        print(f"{result.get('result')}: {result.get('passedTests')} passed, {result.get('failedTests')} failed")
        for failure in result.get("testFailures", []):
            print(f"- {failure.get('testName')}: {failure.get('failureText')}")
    crash_reports()


def crash_reports() -> None:
    """The app's newest crash reports: why it stopped and the crashed thread's frames, since a
    result bundle's summary says only "Test crashed with signal trap"."""
    folder = pathlib.Path.home() / "Library/Logs/DiagnosticReports"
    reports = sorted(folder.glob("CanIRetireYet*.ips"), key=lambda report: report.stat().st_mtime)
    for report in reports[-6:]:
        print(f"=== crash {report.name} ===")
        try:
            body = json.loads(report.read_text().split("\n", 1)[1])
        except (IndexError, ValueError, OSError) as error:
            print(f"Unreadable: {error}")
            continue
        print(json.dumps(body.get("exception", {})))
        for key, value in body.get("asi", {}).items():
            print(f"{key}: {' '.join(value) if isinstance(value, list) else value}")
        images = body.get("usedImages", [])
        for thread in body.get("threads", []):
            if not thread.get("triggered"):
                continue
            for frame in thread.get("frames", [])[:30]:
                index = frame.get("imageIndex", -1)
                image = images[index].get("name", "?") if 0 <= index < len(images) else "?"
                place = f" {frame['sourceFile']}:{frame.get('sourceLine', '')}" if "sourceFile" in frame else ""
                print(f"  {image}  {frame.get('symbol', '?')}{place}")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "pick-iphone":
        pick_simulator("iPhone")
    elif command == "pick-ipad":
        pick_simulator("iPad")
    elif command == "print" and len(sys.argv) == 3:
        print_screenshots(pathlib.Path(sys.argv[2]))
    elif command == "failures" and len(sys.argv) == 3:
        failures(pathlib.Path(sys.argv[2]))
    else:
        sys.exit(__doc__)
