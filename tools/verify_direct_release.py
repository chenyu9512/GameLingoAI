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
online = read("ios/GameLingoAI/GameOnlineTranslation.swift")
languages = read("ios/GameLingoAI/GameLanguageSupport.swift")
rpg = read("ios/GameLingoAI/GameRPGDictionary.swift")
translation_settings = read("ios/GameLingoAI/GameTranslationSettingsView.swift")
rpg_settings = read("ios/GameLingoAI/GameRPGDictionaryView.swift")
plist = plistlib.loads((root / "ios/GameLingoAI/InfoDirect.plist").read_bytes())

checks = {
    "direct Xcode build identity": "com.example.GameLingoAI.direct" in project
    or "DIRECT" in generator and "BUNDLE_ID += '.direct'" in generator,
    "separate SwiftUI entry point": "#if DIRECT_CAPTURE" in app and "DirectHomeView()" in app,
    "game settings target source": "GameLingoStore.swift" in generator
    and "GameLingoStore.swift" in project,
    "orientation geometry compiled": "GameCaptureGeometry.swift" in generator
    and "GameCaptureGeometry.swift" in project,
    "all new components included in iOS direct target":
        all(name in generator and name in project for name in [
            "GameOnlineTranslation.swift", "GameLanguageSupport.swift",
            "GameRPGDictionary.swift", "GameRPGDictionaryView.swift",
            "GameTranslationSettingsView.swift"]),
    "offline is persisted default": "provider = stored?.provider ?? .offline" in models
        and "provider: GameTranslationProvider?" in models,
    "HTTPS only and secrets in Keychain": "value.scheme?.lowercased() == \"https\"" in online
        and "SecItemAdd(" in online and "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in online,
    "online API explicit test before enabling":
        "await tester.test(provider: choice" in translation_settings
        and "store.provider = choice" in translation_settings
        and "store.provider = .offline" in translation_settings,
    "MyMemory quotas and size capped":
        "anonymousDailyLimit = 4900" in online
        and "splitUTF8(value, maxBytes: 440)" in online
        and "https://api.mymemory.translated.net/get" in online,
    "custom HTTPS JSON API": "case .customJSON:" in online
        and "resultAtPath(json, path: path)" in online
        and "request.setValue(endpoint.apiKeyPrefix + key" in online,
    "LibreTranslate compatible": "case .libreTranslate, .customJSON" in online
        and "body[\"api_key\"] = key" in online,
    "offline languages downloaded as needed":
        "try await session.prepareTranslation()" in home
        and "downloadSourceLanguage" in home,
    "Vision OCR language mapping": "supportedRecognitionLanguages()" in languages
        and "GameLanguageSupport.setup(request" in capture,
    "curated RPG dictionary and DQ terminology":
        rpg.count("RPGGameTerm(category:") >= 400
        and "勇者斗恶龙专用" in rpg
        and "GameRPGDictionaryView" in home,
    "per-game override glossary first": "mergedTerms.merge(GameLingoStore.glossaryMap" in capture
        and "profile.dragonQuestEnabled" in capture,
    "offline and online cache separated": "profile.provider.rawValue + \"|\"" in capture
        and "provider: provider" in menu,
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
    "region-based OCR":
        "let region = geometry.layout == .portrait" in capture
        and "snapshot.portraitROI : snapshot.landscapeROI" in capture
        and "geometry.rawRegion(for: region)" in capture
        and "geometry: geometry, region: region" in capture
        and "request.regionOfInterest = region" in capture,
    "local history only": "history.insert(line, at: 0)" in models,
    "no ReplayKit compiled in direct target": "src_app+([] if DIRECT else src_shared)" in generator,
    "no broadcast extension in direct target":
        "targets=[target_app] if DIRECT else [target_app,target_ext]" in generator,
    "no requested App Groups entitlement":
        "'CODE_SIGN_ENTITLEMENTS':'' if DIRECT" in generator,
    "full-display background capture declaration":
        "screen-capture" in plist.get("UIBackgroundModes", []),
    "v3.3 release version":
        "'MARKETING_VERSION':'3.3.0' if DIRECT" in generator,
    "direct PiP preview retained": "FloatingSubtitlePreview" in home,
    "offline Translation session": "TranslationSession(" in online
    and "installedSource:" in online
    and "session.translate(batch: requests)" in menu,
}
for label, valid in checks.items():
    print(("OK  " if valid else "FAIL") + label)
if not all(checks.values()):
    raise SystemExit("Direct release preflight failed")
print("PASS: GameLingo Direct 3.3 offline-by-default, online opt-in, RPG lexicon and orientation preflight")
