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
pip_renderer = read("ios/GameLingoAI/GamePiPFrameRenderer.swift")
models = read("ios/GameLingoAI/GameLingoStore.swift")
geometry = read("ios/GameLingoAI/GameCaptureGeometry.swift")
menu = read("ios/GameLingoAI/GameMenuCatalog.swift")
online = read("ios/GameLingoAI/GameOnlineTranslation.swift")
languages = read("ios/GameLingoAI/GameLanguageSupport.swift")
quality = read("ios/GameLingoAI/GameOCRQuality.swift")
safety = read("ios/GameLingoAI/GameTranslationSafety.swift")
diagnostic_log = read("ios/GameLingoAI/GameDiagnosticLog.swift")
txt_parser = read("ios/GameLingoAI/GameGlossaryTXTParser.swift")
txt_library = read("ios/GameLingoAI/GameGlossaryLibrary.swift")
txt_view = read("ios/GameLingoAI/GameGlossaryLibraryView.swift")
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
    "3.5 TXT glossary files in direct target":
        all(name in generator and name in project for name in [
            "GameGlossaryTXTParser.swift", "GameGlossaryLibrary.swift",
            "GameGlossaryLibraryView.swift"]),
    "TXT encoding, format and duplicate validation":
        "String(data: data, encoding: .utf16)" in txt_parser
        and "ordered.compactMap" in txt_parser
        and "ParseError.tooLarge" in txt_parser
        and "duplicates += 1" in txt_parser,
    "multi-pack one-tap and private persistence":
        "applicationSupportDirectory" in txt_library
        and "func setAll(" in txt_library
        and "func activeDictionary(" in txt_library
        and ".fileImporter(" in txt_view,
    "imported terminology used in same live translator pipeline":
        "GameGlossaryLibrary.shared.activeDictionary(game: profile.id)" in rpg
        and "GameRPGDictionary.glossary(for: profile)" in capture,
    "bottom-screen OCR and UI":
        "private func recognizeBottom(" in capture
        and "request.minimumTextHeight = 0.003" in capture
        and "profile.bottomScanEnabled" in capture
        and "屏幕底部强化识别" in home,
    "Swift 27 TTS entries mapped with explicit closure":
        "entries.map { $0.translated }" in subtitle
        and "entries.map(.translated)" not in subtitle
        and 'playbackPage = "\\(pageIndex + 1) / \\(pageCount)"' in subtitle,
    "automatic subtitle paging, optional speech and user controls":
        "func configurePlayback(" in subtitle
        and "func togglePlayback()" in subtitle
        and "AVSpeechSynthesizer()" in subtitle
        and "overlay.nextPage()" in home
        and "$store.playbackSeconds" in home,
    "new key-only provider adapters":
        "case .azure:" in online and "Ocp-Apim-Subscription-Key" in online
        and "case .deepL:" in online and "DeepL-Auth-Key" in online
        and "case .google:" in online and "translation.googleapis.com" in online,
    "provider quota protection and test-before-enable":
        "dailyCharacterLimit" in online and "func reserve(" in online
        and "await tester.test(" in translation_settings
        and "store.provider = choice" in translation_settings,
    "cleaner consumer UI and settings navigation":
        "private var statusDashboard:" in home
        and "ConfigSection.allCases" in home
        and "DIRECT 3.5" in home,
    "off-main CoreText PiP worker built in direct target":
        "GamePiPFrameRenderer.swift" in generator
        and "GamePiPFrameRenderer.swift" in project
        and "GamePiPFrameRenderer.swift" in Path("codemagic.yaml").read_text(encoding="utf-8")
        and "GameLingo.PiP.CoreText" in pip_renderer
        and "CVPixelBufferPoolCreatePixelBuffer" in pip_renderer
        and "UIGraphicsImageRenderer" not in subtitle,
    "latest pending PiP frame and renderer readiness":
        "pendingSample = buffer" in subtitle
        and "requestMediaDataWhenReady" in subtitle
        and "stopRequestingMediaData()" in subtitle,
    "real time dialogue is not blocked by bottom OCR":
        "GameLingo.secondary.ocr" in capture
        and "self.recognizeBottom(buffer" in capture
        and "self.ocrQueue.async" in capture
        and "recentlyDetectedDialogue" in capture,
    "latency breakdown and rolling percentiles":
        "queueWaitMs" in capture
        and "discardedCaptureFrames" in capture
        and "captureToTranslationMs" in capture
        and "p50CaptureToPiPMs" in subtitle
        and "p95CaptureToPiPMs" in subtitle
        and "captureToPiPMs" in home,
    "quality filter included in target": "GameOCRQuality.swift" in generator
        and "GameOCRQuality.swift" in project
        and "GameOCRQuality.best(" in capture,
    "latest-frame producer does not run OCR":
        "GameLingo.frames" in capture
        and "GameLingo.latestFrameOCR" in capture
        and "pendingFrame = CapturedFrame(" in capture
        and "private func drainLatestFrames()" in capture
        and "pendingFrame = nil" in capture,
    "no fixed four-line or 190-character rejection":
        "sorted.prefix(4)" not in capture
        and "text.count <= 190" not in capture
        and "let merged = sorted.map" in capture,
    "three additional PiP layout choices":
        "multiBilingual" in models and "denseChinese" in models
        and "menuPages" in models
        and "isGroupedLayout" in subtitle and "setMenuEntries(" in subtitle,
    "PiP coalesces and heartbeats sparingly":
        "withTimeInterval: 0.3" in subtitle
        and "lastDrawAt >= 3.0" in subtitle
        and "withTimeInterval: 0.8" not in subtitle,
    "offline OCR-line translations remain paired":
        "session.translate(batch: group)" in capture
        and "translated[index] = response.targetText" in capture
        and "recentPairs.append(SubtitlePage(original: source, translated: target))" in subtitle,
    "static menu caches normalized blocks":
        "lastCacheHits" in menu and "changedBlocks" in menu
        and "private func normalized(" in menu
        and "self.translatedCount % 12" in menu,
    "OCR raw-versus-validated diagnostics":
        "lastOCRRaw" in capture and "lastOCRAccepted" in capture
        and "lastOCRRaw.prefix" in home and "lastOCRAccepted.prefix" in home,
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
    "per-game override glossary first": "GameRPGDictionary.glossary(for: profile)" in capture
        and "result.merge(GameLingoStore.glossaryMap(profile.glossary))" in rpg,
    "one-tap all Dragon Quest terms": "一键启用整套勇者斗恶龙术语" in home
        and "一键停用整套勇者斗恶龙术语" in home
        and "setDragonQuestPackEnabled(newValue, for: profileDraft.id)" in home
        and "profiles[index].useDragonQuestLexicon = enabled" in models
        and "dragonQuestTermCount" in rpg,
    "pack does not copy terms into editable glossary":
        "GameRPGDictionaryView()" in home
        and "onInsert" not in rpg_settings
        and "profileDraft.glossary += line" not in home,
    "one-tap lexicon used across live and screenshot OCR":
        "glossary: GameRPGDictionary.glossary(for: store.activeProfile)" in home
        and "GameRPGDictionary.glossary(for: profile)" in capture,
    "OCR custom words respect disabled pack":
        "snapshot.glossary[$0.japanese] != nil" in capture,
    "offline and online cache separated": "profile.provider.rawValue + \"|\"" in capture
        and "provider: provider" in menu and "endpointID: endpointID" in menu,
    "screenshot imports never trigger online API":
        "overrideProvider: .offline" in home
        and "overrideProvider ?? GameLingoStore.shared.provider" in menu,
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
        and "entry.original" in pip_renderer
        and "entry.translated" in pip_renderer
        and "frameRenderer.render(" in subtitle,
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
    "v3.5.3 release version and build":
        "'MARKETING_VERSION':'3.5.3' if DIRECT" in generator
        and "'CURRENT_PROJECT_VERSION':'14' if DIRECT" in generator,
    "default game auto source and legacy migration":
        'var language: String = "auto"' in models
        and 'direct.autoSource.migrated.3_5_2' in models,
    "Vision auto source and NaturalLanguage detection":
        "request.automaticallyDetectsLanguage = true" in languages
        and "NLLanguageRecognizer()" in languages
        and "GameLanguageSupport.resolvedSource(" in capture,
    "stable OCR candidate can bypass static-scene throttle":
        "confirmationDue" in capture
        and "pendingConfirmation" in capture,
    "fast OCR accurate fallback on critically poor OCR only":
        "snapshot.performance == .fast ? 0.42 : 0.66" in capture,
    "iOS-compatible software capture sampling (no macOS-only API)":
        "configuration.minimumFrameInterval" not in capture
        and "lastIngressRevision" in capture
        and "ProcessInfo.processInfo.systemUptime" in capture
        and "uptime - lastIngressAt < 1.0 / fps" in capture
        and "config.performance == .fast ? 10" in capture
        and "sampledOutFrames += 1" in capture,
    "stale bottom OCR blocked":
        "lastBottomFingerprint" in capture
        and "currentBottomFingerprint == lastBottomFingerprint" in capture,
    "menu auto source guarded":
        'configured: language) ?? "und"' in menu
        and 'if language == "und"' in menu,
    "language-source tracker and failure policy compiled":
        "GameTranslationSafety.swift" in generator
        and "GameSourceLanguageTracker" in safety
        and "GameTranslationRetryPolicy" in safety,
    "automatic source is stabilized per OCR worker":
        "sourceTracker.resolve(" in capture
        and "sourceTracker.reset()" in capture,
    "offline language status checks only before model invocation":
        "LanguageAvailability().status(" in capture
        and "translationNeedsModel(text, profile: profile, key: key)" in capture
        and "case .supported:" in capture and "case .unsupported:" in capture,
    "per-language failures stop retry storms":
        "translationRetry.canAttempt(" in capture
        and "translationRetry.recordFailure(" in capture
        and "translationRetry.recordSuccess(" in capture,
    "translation diagnostics classify failure without saving content":
        '"translation_language_status"' in diagnostic_log
        and '"translation_error_kind"' in diagnostic_log
        and '"translation_retry_delay_sec"' in diagnostic_log
        and '"source_language_id"' in diagnostic_log,
    "language pack preparation refreshes after app foreground":
        "capture.refreshOfflineAvailability()" in home,
    "original PiP and translation providers retained":
        "FloatingSubtitlePreview" in home
        and "session.translate(batch: group)" in capture
        and "GameOnlineTranslator.shared.translate(" in capture
        and "case .myMemory" in online,
    "main direct build does not pull experimental ML Kit":
        "MLKIT_OCR" not in generator
        and "GoogleMLKit" not in generator,
    "direct PiP preview retained": "FloatingSubtitlePreview" in home,
    "offline Translation session": "TranslationSession(" in online
    and "installedSource:" in online
    and "session.translate(batch: requests)" in menu,
}
for label, valid in checks.items():
    print(("OK  " if valid else "FAIL") + label)
if not all(checks.values()):
    raise SystemExit("Direct release preflight failed")
print("PASS: GameLingo Direct 3.5.3 translation safety, auto-source and PiP preflight")
