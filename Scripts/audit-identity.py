#!/usr/bin/env python3
"""Audit prospective source tree without staging files or inspecting Git history."""
import os
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
raw = subprocess.check_output(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
)
# Assemble prohibited token so audit source itself retains no forbidden identity.
stem = "clip" + "board"
tail = "his" + "tory"
pattern = re.compile(stem + r"[\W_]*" + tail, re.IGNORECASE)
files = sorted({os.fsdecode(p) for p in raw.split(b"\0") if p and (root / os.fsdecode(p)).is_file()})
matches = []
for name in files:
    if pattern.search(name):
        matches.append((name, "filename"))
    data = (root / name).read_bytes()
    text = data.decode("utf-8", errors="replace")
    if pattern.search(text):
        matches.append((name, "content"))
for name, kind in matches:
    print(f"{kind}: {name}")
print(f"Identity audit: {len(files)} existing source files; {len(matches)} matches.")
sys.exit(bool(matches))
