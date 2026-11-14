"""Run every harness scenario (scenario.lua and *_scenario.lua) in the default and the
--combat profile and print one summary table. Also checks that every locale file in
ForeverDungeonMap/Locales translates every ns.L["..."] key used in the addon code.

Usage (from the repo root):
    python -I tools/harness/run_all.py [--addon DIR] [--jobs N] [--verbose] [extra run.py options]

Exit code: 0 only when every run has no Lua errors, no failed checks, no protected-call
violations, and every locale file is complete.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PROFILES = [("default", []), ("combat", ["--combat"])]
LOCALE_KEY = re.compile(r'\bL\["((?:[^"\\]|\\.)*)"\]')
TRANSLATION_KEY = re.compile(r'^\s*\["((?:[^"\\]|\\.)*)"\]\s*=', re.M)


def scenarios():
    names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(HERE, "*_scenario.lua")))
    return ["scenario.lua"] + names


def as_list(value):
    if isinstance(value, dict):
        return list(value.values())
    return value or []


def run_one(scenario, profile, options, extra):
    """Run one scenario in one profile; returns a result row."""
    handle, json_path = tempfile.mkstemp(suffix=".json")
    os.close(handle)
    command = [sys.executable, "-I", os.path.join(HERE, "run.py"), *options, *extra,
               "--json", json_path, os.path.join(HERE, scenario)]
    process = subprocess.run(command, cwd=REPO, capture_output=True, text=True, encoding="utf-8", errors="replace")
    row = {"scenario": scenario, "profile": profile, "exit": process.returncode, "output": process.stdout + process.stderr}
    try:
        with open(json_path, encoding="utf-8") as f:
            report = json.load(f)
        checks = as_list(report.get("checks"))
        row["passed"] = sum(1 for c in checks if c.get("ok"))
        row["failed"] = [c.get("name") for c in checks if not c.get("ok")]
        row["errors"] = [e.get("msg") for e in as_list(report.get("errors"))]
        row["violations"] = len(as_list(report.get("protected")))
    except (OSError, ValueError):
        row.update(passed=0, failed=[], errors=["no report (run.py crashed)"], violations=0)
    finally:
        if os.path.exists(json_path):
            os.remove(json_path)
    row["green"] = row["exit"] == 0 and not row["failed"] and not row["errors"] and row["violations"] == 0
    return row


def locale_rows(addon_dir):
    """One row per locale file: keys used in the code that the file does not translate."""
    used = set()
    for path in glob.glob(os.path.join(addon_dir, "**", "*.lua"), recursive=True):
        if os.sep + "Locales" + os.sep not in path:
            used.update(LOCALE_KEY.findall(open(path, encoding="utf-8").read()))
    rows = []
    for path in sorted(glob.glob(os.path.join(addon_dir, "Locales", "*.lua"))):
        if os.path.basename(path) == "Locale.lua":
            continue
        translated = set(TRANSLATION_KEY.findall(open(path, encoding="utf-8").read()))
        rows.append({"file": os.path.basename(path), "missing": sorted(used - translated),
                     "unused": sorted(translated - used), "used": len(used)})
    return rows


def print_table(rows):
    print("%-32s %-8s %7s %7s %7s %10s  %s" % ("scenario", "profile", "passed", "failed", "errors", "violations", "result"))
    print("-" * 84)
    for row in rows:
        print("%-32s %-8s %7d %7d %7d %10d  %s" % (row["scenario"], row["profile"], row["passed"], len(row["failed"]),
                                                len(row["errors"]), row["violations"], "ok" if row["green"] else "FAIL"))


def print_failures(rows, verbose):
    for row in rows:
        if row["green"] and not verbose:
            continue
        if not row["green"]:
            print("\n== %s (%s)" % (row["scenario"], row["profile"]))
            for name in row["failed"][:10]:
                print("  FAIL check: %s" % name)
            for message in row["errors"][:5]:
                print("  LUA ERROR: %s" % str(message).splitlines()[0][:200])
            if row["violations"]:
                print("  %d protected-call violations" % row["violations"])
        if verbose:
            print(row["output"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", default="ForeverDungeonMap")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    parser.add_argument("--verbose", action="store_true")
    args, extra = parser.parse_known_args()
    addon_dir = args.addon if os.path.isabs(args.addon) else os.path.join(REPO, args.addon)
    extra = ["--addon", addon_dir, *extra]

    jobs = [(scenario, profile, options) for scenario in scenarios() for profile, options in PROFILES]
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        rows = list(pool.map(lambda job: run_one(*job, extra), jobs))
    print_table(rows)
    print_failures(rows, args.verbose)

    locales = locale_rows(addon_dir)
    locales_green = all(not row["missing"] for row in locales)
    print("\nlocales (%d keys used in code):" % (locales[0]["used"] if locales else 0))
    for row in locales:
        print("  %-12s missing %d%s" % (row["file"], len(row["missing"]),
                                       (": " + "; ".join(row["missing"][:5])) if row["missing"] else ""))
        if row["unused"]:
            print("  %-12s unused  %d: %s" % ("", len(row["unused"]), "; ".join(row["unused"][:5])))

    green = all(row["green"] for row in rows) and locales_green
    print("\n%s: %d of %d runs green%s" % ("ALL GREEN" if green else "NOT GREEN", sum(r["green"] for r in rows), len(rows),
                                         "" if locales_green else ", locale files incomplete"))
    return 0 if green else 1


if __name__ == "__main__":
    sys.exit(main())
