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

checks = {
    "isolated universal branch build flag":
        "GAMELINGO_ENABLE_PADDLE" in generator
        and "'DIRECT_CAPTURE PADDLE_OCR'" in generator,
    "v3.7 build 15": "'CURRENT_PROJECT_VERSION':'15'" in generator,
    "Google ML Kit removed":
        "GoogleMLKit" not in podfile and "MLKIT_OCR" not in generator
        and not Path("ios/GameLingoAI/GameMLKitJapaneseOCR.swift").exists(),
    "Apple Vision still default and saved Google profiles migrate":
        "experimentalOCR == .mlkitJapanese ? .vision" in store,
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
    "Paddle diagnostic latency is snapshotted before main queue closure":
        "let paddleDurationMs = lastPaddleMs" in capture
        and '"paddle_ms": paddleDurationMs' in capture
        and '"paddle_ms": lastPaddleMs' not in capture,
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
        and "GameLingoAI-Universal-OCR-unsigned.ipa" in workflow,
}
for key, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + key)
if not all(checks.values()):
    raise SystemExit("Universal OCR static verification failed")
print(f"PASS: {len(checks)} Universal OCR audit items")
