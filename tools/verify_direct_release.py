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
geometry = read("ios/GameLingoAI/GameCaptureGeometry.swift")
menu = read("ios/GameLingoAI/GameMenuCatalog.swift")
plist = plistlib.loads((root / "ios/GameLingoAI/InfoDirect.plist").read_bytes())

checks = {
    "direct Xcode build identity": "com.example.GameLingoAI.direct" in project
    or "DIRECT" in generator and "BUNDLE_ID += '.direct'" in generator,
    "separate SwiftUI entry point": "#if DIRECT_CAPTURE" in app and "DirectHomeView()" in app,
    "game settings target source": "GameLingoStore.swift" in generator
    and "GameLingoStore.swift" in project,
    "orientation geometry compiled": "GameCaptureGeometry.swift" in generator
    and "GameCaptureGeometry.swift" in project,
    "automatic portrait and landscape frame detection":
        "renderedWidth >= renderedHeight" in geometry
        and "GameCaptureGeometry(" in capture
        and "CVPixelBufferGetWidth(buffer)" in capture,
    "manual rotations with correct Vision handler orientation":
        "case .left: return .left" in geometry
        and "case .right: return .right" in geometry
        and "orientation: geometry.imageOrientation" in capture,
    "distinct portrait/landscape OCR regions":
        "var landscapeRegion: GameOCRBox?" in models
        and "snapshot.portraitROI : snapshot.landscapeROI" in capture
        and "regionBinding(" in home,
    "correctly oriented photo OCR":
        "bitmap.imageOrientation.gameVisionOrientation" in home
        and "VNImageRequestHandler(cgImage: image, orientation: orientation)" in home,
    "rotation reset protects stale OCR results":
        "menuGeometryRevision" in capture
        and "guard current else { return }" in capture,
    "app supports portrait and landscape":
        {"UIInterfaceOrientationPortrait",
         "UIInterfaceOrientationLandscapeLeft",
         "UIInterfaceOrientationLandscapeRight"}.issubset(
             set(plist.get("UISupportedInterfaceOrientations", []))),
    "menu translation is compiled": "GameMenuCatalog.swift" in generator
    and "GameMenuCatalog.swift" in project,
    "full screen OCR retains detected blocks":
        "private func recognizeFullScreen" in capture
        and "sorted.enumerated()" in capture
        and "request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)" in capture,
    "streamed batch menu translation":
        "session.translate(batch: requests)" in menu
        and "response.clientIdentifier" in menu
        and "GameMenuBlock" in menu,
    "persistent complete menu results": "Saved(pages: savedPages" in menu
        and "GameLingo.Direct.MenuPages.v1" in menu,
    "separate menu and dialogue lanes": "menuQueue" in capture
        and "scheduleMenuScan(" in capture
        and "private func recognize(_ buffer:" in capture,
    "only scan game when host app is not visible":
        "hostAppForeground" in capture and "guard !visible" in capture
        and "scenePhase" in home,
    "manual scan permits time to return to game":
        "manualMenuReadyAt = Date().timeIntervalSince1970 + 2.5" in capture,
    "menu results are not arbitrarily limited to seven lines":
        "return sorted.enumerated().map" in capture
        and "sorted.prefix(7)" not in capture,
    "manual menu scan and scrollable results":
        "capture.requestFullScreenScan()" in home
        and "ForEach(page.blocks)" in home,
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
    "v3.2 release version":
        "'MARKETING_VERSION':'3.2.0' if DIRECT" in generator,
    "direct PiP preview retained": "FloatingSubtitlePreview" in home,
    "offline Translation session": "TranslationSession(" in capture
    and "installedSource:" in capture,
}
for label, valid in checks.items():
    print(("OK  " if valid else "FAIL") + label)
if not all(checks.values()):
    raise SystemExit("Direct release preflight failed")
print("PASS: GameLingo Direct 3.2 portrait/landscape bilingual/menu build source preflight")
