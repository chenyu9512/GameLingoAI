#!/usr/bin/env python3
"""Validate source paths before cloud build. No network, no secrets."""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parents[1]
for path in sorted(root.glob('ios/**/*.plist')) + sorted(root.glob('ios/**/*.entitlements')):
    plistlib.loads(path.read_bytes())
print('Info.plist and entitlements are valid XML plists.')
