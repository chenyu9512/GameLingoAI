#!/usr/bin/env python3
"""Static guards for the opt-in ML Kit Japanese OCR branch, run after generation."""
from pathlib import Path

def read(path):
    return Path(path).read_text(encoding="utf-8")

generator = read("tools/build_xcodeproj.py")
project = read("GameLingoAI.xcodeproj/project.pbxproj")
adapter = read("ios/GameLingoAI/GameMLKitJapaneseOCR.swift")
capture = read("ios/GameLingoAI/DirectGameCapture.swift")
ui = read("ios/GameLingoAI/DirectHomeView.swift")
store = read("ios/GameLingoAI/GameLingoStore.swift")
podfile = read("Podfile")
ci = read("codemagic.yaml")

checks = {
    "ML Kit experiment enabled only via separate environment flag":
        "GAMELINGO_EXPERIMENTAL_MLKIT" in generator and "MLKIT = DIRECT and" in generator,
    "ML Kit adapter added to direct app target":
        "GameMLKitJapaneseOCR.swift" in generator and "GameMLKitJapaneseOCR.swift" in project,
    "experimental build has explicit Swift compilation flag":
        "'DIRECT_CAPTURE MLKIT_OCR'" in generator and "MLKIT_OCR" in project,
    "build 13 separated from stable build 12":
        "'MARKETING_VERSION':'3.6.0'" in generator
        and "'CURRENT_PROJECT_VERSION':'13'" in generator,
    "Google model pinned for reproducible installation":
        "GoogleMLKit/TextRecognitionJapanese', '9.0.0'" in podfile,
    "dedicated CocoaPods experimental workflow":
        "ios-direct-mlkit-unsigned:" in ci and "pod install --repo-update" in ci
        and "-workspace" in ci,
    "retains Vision as default":
        "experimentalOCR ?? .vision" in store
        and "profile.selectedOCR" in capture,
    "existing multilingual automatic OCR never forced to Japanese ML Kit":
        'snapshot.language.hasPrefix("ja")' in capture
        and "GameLanguageSupport.isAvailable" not in capture,
    "no vision confidence fabricated from ML Kit":
        "ocrConfidenceEstimated" in capture
        and "ML Kit v2 doesn't publish comparable confidence scores" in capture
        and "confidence_available" in capture,
    "ROI crop and ignored HUD exclusion":
        "context.createCGImage(oriented, from: crop)" in adapter
        and "excludedRegion?.contains(center)" in adapter,
    "ML Kit synchronous OCR never invoked on main":
        "precondition(!Thread.isMainThread" in adapter
        and "self?.drainLatestFrames()" in capture,
    "offline image processing":
        "VisionImage(image:" in adapter
        and "TextRecognizer.textRecognizer" in adapter
        and "URLSession" not in adapter,
    "rollback to Vision when detector throws":
        'self.lastError = "ML Kit OCR： "' in capture
        and "let first = pass(.fast)" in capture,
    "legacy OCR menu and bottom paths intact":
        "private func recognizeBottom(" in capture
        and "private func recognizeFullScreen(" in capture,
    "original main-line mode still available without ML Kit imports":
        "#if MLKIT_OCR" in adapter and "#else" in adapter
        and "return false" in adapter,
}
for name, result in checks.items():
    print(("PASS " if result else "FAIL ") + name)
if not all(checks.values()):
    raise SystemExit("ML Kit experiment static preflight failed")
print(f"PASS: {len(checks)} experiment compatibility guards")
