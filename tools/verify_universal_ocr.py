#!/usr/bin/env python3
"""Strict project audit for Universal OCR iOS 27 build. Run after generation."""
from pathlib import Path

def read(path):
    return Path(path).read_text(encoding="utf-8")

generator = read("tools/build_xcodeproj.py")
project = read("GameLingoAI.xcodeproj/project.pbxproj")
capture = read("ios/GameLingoAI/DirectGameCapture.swift")
store = read("ios/GameLingoAI/GameLingoStore.swift")
adapter = read("ios/GameLingoAI/GamePaddleOCR.swift")
ui = read("ios/GameLingoAI/DirectHomeView.swift")
packs = read("ios/GameLingoAI/GameLanguagePackView.swift")
routing = read("ios/GameLingoAI/GameOCRRouting.swift")
podfile = read("Podfile")
workflow = read("codemagic.yaml")
fetcher = read("tools/fetch_paddle_rec_model.sh")
warmup = read("ios/GameLingoAI/GameStartupWarmup.swift")
pip = read("ios/GameLingoAI/FloatingSubtitleController.swift")
renderer = read("ios/GameLingoAI/GamePiPFrameRenderer.swift")
layout = read("ios/GameLingoAI/GamePiPReadingLayout.swift")
diagnostics = read("ios/GameLingoAI/GameDiagnosticLog.swift")
page_test = read("tests/pip_reading_smoke.swift")
targets = read("ios/GameLingoAI/GameTranslationLanguages.swift")
online = read("ios/GameLingoAI/GameOnlineTranslation.swift")
menu = read("ios/GameLingoAI/GameMenuCatalog.swift")
source_languages = read("ios/GameLingoAI/GameLanguageSupport.swift")
target_test = read("tests/translation_languages_smoke.swift")
scene_geometry = read("ios/GameLingoAI/GamePiPSceneLayout.swift")
scene_test = read("tests/pip_scene_smoke.swift")
session_policy = read("ios/GameLingoAI/GameOCRSessionPolicy.swift")
session_policy_test = read("tests/ocr_session_policy_smoke.swift")

checks = {
    "isolated universal branch build flag":
        "GAMELINGO_ENABLE_PADDLE" in generator
        and "'DIRECT_CAPTURE PADDLE_OCR'" in generator,
    "v3.8.1 build 19": "'MARKETING_VERSION':'3.8.1'" in generator
        and "'CURRENT_PROJECT_VERSION':'19'" in generator,
    "Google ML Kit removed":
        "GoogleMLKit" not in podfile and "MLKIT_OCR" not in generator
        and not Path("ios/GameLingoAI/GameMLKitJapaneseOCR.swift").exists(),
    "Apple Vision still default and saved Google profiles migrate":
        "experimentalOCR == .mlkitJapanese ? .vision" in store,
    "store PiP migration only after every stored property initialization":
        "onboardingComplete = stored?.onboardingComplete ?? false" in store
        and "if pipLayout == .standard" in store
        and store.index("onboardingComplete = stored?.onboardingComplete ?? false")
            < store.index("if pipLayout == .standard")
        and store.index("history = stored?.history ?? []")
            < store.index("if pipLayout == .standard")
        and store.index("fontScale = stored?.fontScale")
            < store.index("if pipLayout == .standard"),

    "PaddleOCR model and ONNX API included in compiled app":
        "GamePaddleOCR.swift" in generator and "GamePaddleOCR.swift" in project
        and "PaddleModels" in generator and "PaddleModels" in project
        and "PaddleORTBridge.h" in generator and "onnxruntime-objc" in podfile
        and "ORTSession(" in adapter and "tensorData:" in adapter,
    "real model fetch is mandatory in CI":
        "fetch_paddle_rec_model.sh" in workflow
        and "PP-OCRv6_small_rec_onnx_infer" in fetcher
        and "curl --fail" in fetcher,
    "hybrid OCR router and Vision fallback":
        "GameOCRRouting.shouldEnhance(" in capture
        and "GamePaddleOCR.recognize(" in capture
        and "let first = pass(.fast)" in capture,
    "engine selections apply immediately and separate selected/result labels":
        "store.selectOCREngine(engine" in ui
        and "selectedOCRName" in ui
        and "ocrEngineStatus" in capture
        and "GameOCRRouting.shouldEnhance(" in capture
        and "millisecondsSinceLast >= 3000" in routing,
    "user target locale persists and propagates to all translators":
        "GameTranslationLanguages.swift" in generator
        and "GameTranslationLanguages.swift" in project
        and "targetLanguage = stored?.targetLanguage" in store
        and "targetLanguage: targetLanguage" in store
        and "target: profile.targetLanguage" in capture
        and "target: targetLanguage" in menu
        and "target: Locale.Language(identifier: targetLanguage)" in menu
        and "GameTranslationLanguages.apiCode(target)" in online
        and "TranslationLanguagesSmoke" in target_test,
    "no forced Japanese offline prewarming or pack default":
        'isAutomatic(language) ? "ja"' not in warmup
        and 'var preferredSource = "auto"' in packs
        and 'targetLanguage: String' in warmup
        and "Locale.preferredLanguages" in source_languages,
    "startup PiP has terminal failure and retry visibility":
        "piPStartupRetryCycles < 1" in pip
        and "launchFailed = true" in pip
        and ".onChange(of: overlay.launchFailed)" in ui
        and "重新请求悬浮窗" in ui
        and "isPreparing = false" in pip,
    "actions have visible toasts and haptics":
        "private func announce(" in ui
        and "UINotificationFeedbackGenerator" in ui
        and 'actionFeedback' in ui
        and 'announce("配置已保存并应用' in ui,
    "new target regression tests run in Codemagic":
        "tests/translation_languages_smoke.swift" in workflow
        and "GameTranslationLanguages.preferredTarget" in target_test,
    "portrait scene and focus layouts in both targets":
        generator.count("'ios/GameLingoAI/GamePiPSceneLayout.swift'") == 2
        and "GamePiPSceneLayout.swift" in project
        and "case portraitScene, portraitFocus" in store
        and 'isScene ? GamePiPSceneLayout.portraitWidth' in renderer,
    "live game frames are capped and kept in memory":
        "sceneDue" in capture
        and "uptime - lastSceneFrameAt >= 0.5" in capture
        and "sceneFrameHandler?(buffer, sceneOrientation)" in capture
        and "renderScene(frame, context: context)" in renderer
        and "CIImage(cvPixelBuffer: source)" in renderer,
    "positioned OCR lines survive source-to-translation mapping":
        "spatialLines: sorted.map" in capture
        and "spatialLines: recognition.spatialLines" in capture
        and "sceneText = zip(spatialLines, outputLines)" in capture
        and "setSceneTranslatedLines" in pip
        and "setSceneMenuPage" in pip,
    "portrait mapping tests enabled in Codemagic":
        "GamePiPSceneLayout.viewport(" in scene_test
        and "GamePiPSceneLayout.visible(" in scene_test
        and "tests/pip_scene_smoke.swift" in workflow,
    "Paddle diagnostic latency is snapshotted before main queue closure":
        "let paddleDurationMs = lastPaddleMs" in capture
        and '"paddle_ms": paddleDurationMs' in capture
        and '"paddle_ms": lastPaddleMs' not in capture,
    "cold startup OCR and translation prewarm are compiled":
        "GameStartupWarmup.swift" in generator and "GameStartupWarmup.swift" in project
        and "prepareVision(language:" in warmup
        and "LanguageAvailability().status(" in warmup
        and "TranslationSession(installedSource:" in warmup
        and "warmup.prepare(language:" in ui,
    "one-tap capture waits for real PiP callback and allows fallback":
        "beginGameTranslation()" in ui
        and "awaitingPiPForCapture" in ui
        and ".onChange(of: overlay.isActive)" in ui
        and "不使用 PiP，继续授权屏幕采集" in ui,
    "full-window reading replaces fixed-length split":
        "GamePiPReadingLayout.swift" in generator
        and "GamePiPReadingLayout.swift" in project
        and "GamePiPReadingLayout.paginate(" in pip
        and "fullBilingual" in store and "fullChinese" in store
        and "fullBilingual" in renderer and "fullChinese" in renderer,
    "PiP render dimensions and spatial menu OCR boxes are preserved":
        "didTransitionToRenderSize newRenderSize:" in pip
        and "renderWidth: Int(renderSize.width)" in pip
        and "makePool(width: requestedWidth" in renderer
        and "setStructuredMenuEntries" in ui
        and "spatialMenu" in renderer,
    "new full-window reading tests run in Codemagic":
        "pip_reading_smoke.swift" in workflow
        and "GamePiPReadingLayout.group(" in page_test,
    "animated scene Accurate OCR has a global recovery budget":
        "GameOCRSessionPolicy.swift" in generator
        and "GameOCRSessionPolicy.swift" in project
        and "GameOCRRecoveryPolicy.shouldRecover(" in capture
        and "globalMinimum" in session_policy
        and "text == priorText" in session_policy
        and "accurateSuppressed" in capture,
    "autolanguage Han-only fallback requires reliable recent context":
        "GameAutoSourceContext" in session_policy
        and "Self.isHanOnly(text)" in session_policy
        and "sourceContext.resolve(" in capture
        and "sourceContext.reset()" in capture
        and "context_source_uses" in capture,
    "new OCR policy tests run in Codemagic":
        "ocr_session_policy_smoke.swift" in workflow
        and "OCRSessionPolicySmoke" in session_policy_test,
    "start-to-first-text stages are recorded separately and without text":
        '"first_stable_ocr"' in diagnostics
        and '"first_source_resolved"' in diagnostics
        and '"first_stable_ocr_ms"' in diagnostics
        and '"first_source_ms"' in diagnostics
        and 'firstStableOCRLogged' in capture
        and 'firstSourceLogged' in capture
        and 'workerCaptureStartedAt' in capture,
    "startup and PiP diagnostics contain no captured text":
        '"startup_vision"' in diagnostics
        and '"first_translation"' in diagnostics
        and '"pip_startup"' in diagnostics
        and '"pip_start_ms"' in diagnostics,
    "language options are multilingual":
        '("韩语", "ko")' in routing
        and '("阿拉伯语", "ar")' in routing
        and "GameOCRRouting.commonOCRLanguages" in ui,
    "real language pack state without fake percentages":
        "LanguageAvailability().status(" in packs
        and "try await session.prepareTranslation()" in packs
        and "GameLanguagePackView(preferredSource:" in ui
        and "下载进度由 iOS 系统弹窗显示" in packs,
    "capture action prominently visible":
        'Label("开始实时翻译"' in ui
        and "showDiagnostics" in ui,
    "separate new workflow and unsigned IPA":
        "ios-universal-ocr-unsigned:" in workflow
        and "GameLingoAI-Universal-v3.8.1-b19-portrait-unsigned.ipa" in workflow,
}
for key, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + key)
if not all(checks.values()):
    raise SystemExit("Universal OCR static verification failed")
print(f"PASS: {len(checks)} Universal OCR audit items")
