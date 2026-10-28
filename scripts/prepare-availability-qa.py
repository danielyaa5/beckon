#!/usr/bin/env python3
"""Prepare a separate fictional-device QA project; never modifies the live app."""
import pathlib
import shutil
import subprocess
import sys

repo = pathlib.Path(__file__).resolve().parents[1]
if len(sys.argv) != 2:
    raise SystemExit("Usage: prepare-availability-qa.py /absolute/new-output-folder")
out = pathlib.Path(sys.argv[1])
if not out.is_absolute() or out.exists():
    raise SystemExit("Choose a new absolute output folder.")
out.mkdir(parents=True)
for name in ["App", "Shared", "Widget", "Sources", "Tests", "Icon"]:
    shutil.copytree(repo / name, out / name)
for name in ["Package.swift", "Package.resolved", "project.yml"]:
    if (repo / name).exists():
        shutil.copy2(repo / name, out / name)
p = out / "project.yml"
s = p.read_text().replace("com.danielyakobian.findmy-ring", "com.danielyakobian.findmy-ring.availabilityQA")
s = s.replace("PRODUCT_NAME: Beckon", "PRODUCT_NAME: Beckon QA").replace("CFBundleDisplayName: Beckon", "CFBundleDisplayName: Beckon QA")
s = s.replace('SWIFT_VERSION: "6.0"', 'SWIFT_VERSION: "6.0"\n    SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) BECKON_QA')
s = s.replace("$(inherited) WIDGET_EXTENSION", "$(inherited) WIDGET_EXTENSION BECKON_QA")
p.write_text(s)
for name in ["App/FindMyRing.entitlements", "Widget/RingWidget.entitlements"]:
    p = out / name
    p.write_text(p.read_text().replace("com.danielyakobian.findmy-ring", "com.danielyakobian.beckon-availability-qa"))
subprocess.run([str(repo / ".tools/xcodegen/bin/xcodegen"), "generate", "--spec", str(out / "project.yml")], check=True)
print(f"Prepared fictional-device project: {out}")
