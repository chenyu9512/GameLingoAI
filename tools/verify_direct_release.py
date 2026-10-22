#!/usr/bin/env python3
"""Static release checks for the independent iOS 27 bilingual build.

This script verifies repository/project invariants, not runtime PiP behaviour.
Codemagic still performs the actual Swift build and device signing is separate.
"""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
read = lambda name: (root / name).read_text(encoding="utf-8")

generator = read("tools/build_xcodeproj.py")
project = read("GameLingoAI.xcodeproj/project.pbxproj")
app = read("ios/GameLingoAI/GameLingoAIApp.swift")
home = read("ios/GameLingoAI/DirectHomeView.swift")
capture = read("ios/GameLingoAI/DirectGameCapture.swift")
subtitle = read("ios/GameLingoAI/FloatingSubtitleController.swift")
models = read("ios/GameLingoAI/GameLingoStore.swift")
plist = plistlib.loads((root / "ios/GameLingoAI/InfoDirect.plist").read_bytes())

checks = {
    "direct Xcode build identity": "com.example.GameLingoAI.direct" in project
    or "DIRECT" in generator and "BUNDLE_ID += '.direct'" in generator,
    "separate SwiftUI entry point": "#if DIRECT_CAPTURE" in app and "DirectHomeView()" in app,
    "game settings target source": "GameLingoStore.swift" in generator
    and "GameLingoStore.swift" in project,
    "bilingual PiP original and translation": "setBilingual(original:" in subtitle
    and "drawCentered(page.original" in subtitle
    and "drawCentered(page.translated" in subtitle,
    "bilingual default": "subtitleMode = stored?.subtitleMode ?? .bilingual" in models,
    "latest-only translation revision": "translationRevision" in capture
    and "revision == translationRevision" in capture,
    "region-based OCR": "request.regionOfInterest = snapshot.roi" in capture,
    "local history only": "history.insert(line, at: 0)" in models,
    "no ReplayKit compiled in direct target": "src_app+([] if DIRECT else src_shared)" in generator,
    "no broadcast extension in direct target":
        "targets=[target_app] if DIRECT else [target_app,target_ext]" in generator,
    "no requested App Groups entitlement":
        "'CODE_SIGN_ENTITLEMENTS':'' if DIRECT" in generator,
    "full-display background capture declaration":
        "screen-capture" in plist.get("UIBackgroundModes", []),
    "v3 release version":
        "'MARKETING_VERSION':'3.0.0' if DIRECT" in generator,
    "direct PiP preview retained": "FloatingSubtitlePreview" in home,
    "offline Translation session": "TranslationSession(" in capture
    and "installedSource:" in capture,
}
for label, valid in checks.items():
    print(("OK  " if valid else "FAIL") + label)
if not all(checks.values()):
    raise SystemExit("Direct release preflight failed")
print("PASS: iOS 27 bilingual direct build source preflight")
