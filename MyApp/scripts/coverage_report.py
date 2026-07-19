#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path


DEFAULT_EXCLUDED_SUFFIXES = (
    "View.swift",
    "Views.swift",
    "Styles.swift",
    "ThemeEngine.swift",
    "Themes.swift",
    "ThemedComponents.swift",
    "ComicTheme.swift",
    "AdaptiveColours.swift",
    "PlayerScoreBarChart.swift",
    "CardDealAnimationView.swift",
    "SplashView.swift",
    "SettingsView.swift",
    "TVGameView.swift",
    "QRScannerView.swift",
)


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: scripts/coverage_report.py /path/to/Test-*.xcresult", file=sys.stderr)
        return 2

    result_bundle = Path(sys.argv[1]).expanduser()
    if not result_bundle.exists():
        print(f"Result bundle not found: {result_bundle}", file=sys.stderr)
        return 2

    payload = subprocess.check_output([
        "xcrun",
        "xccov",
        "view",
        "--report",
        "--json",
        str(result_bundle),
    ])
    report = json.loads(payload)
    app_target = next((target for target in report["targets"] if target["name"] == "MyApp.app"), None)
    if app_target is None:
        print("MyApp.app target not found in coverage report", file=sys.stderr)
        return 1

    app_files = [
        file for file in app_target["files"]
        if "/MyApp/MyApp/" in file["path"] and file["executableLines"] > 0
    ]
    logic_files = [
        file for file in app_files
        if not file["name"].endswith(DEFAULT_EXCLUDED_SUFFIXES)
    ]

    def summary(files):
        covered = sum(file["coveredLines"] for file in files)
        executable = sum(file["executableLines"] for file in files)
        percent = (covered / executable * 100) if executable else 0
        return covered, executable, percent

    raw_covered, raw_executable, raw_percent = summary(app_files)
    logic_covered, logic_executable, logic_percent = summary(logic_files)

    print(f"Raw app coverage: {raw_percent:.2f}% ({raw_covered}/{raw_executable})")
    print(
        "Logic-focused coverage: "
        f"{logic_percent:.2f}% ({logic_covered}/{logic_executable})"
    )
    print()
    print("Top uncovered app files:")
    for file in sorted(app_files, key=lambda item: item["executableLines"] - item["coveredLines"], reverse=True)[:30]:
        uncovered = file["executableLines"] - file["coveredLines"]
        percent = file["lineCoverage"] * 100
        print(f"{uncovered:5d} uncovered  {percent:6.2f}%  {file['name']}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
