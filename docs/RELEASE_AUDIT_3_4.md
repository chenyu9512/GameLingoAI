# GameLingo Direct 3.4 — source review and release acceptance
Date: 2026-10-23. Code changes are committed. Actual Xcode iOS 27.1 compilation and SideStore testing have NOT been performed in this environment.

## Implemented
1. Latest-frame queue: ScreenCaptureKit callbacks retain only one newest pending CVPixelBuffer; dedicated OCR worker discards stale frames and uses revision checks before publishing results.
2. OCR quality: use up to three Vision candidates and filter Unicode replacement characters, control characters, punctuation-only noise and low-confidence results. Refine failed/uncertain fast OCR with accurate OCR when appropriate.
3. Removed fixed four-line extraction and 190-character rejection from realtime OCR. Multi-line offline texts use TranslationSession.translate(batch:) with client identifiers to maintain source/translation order.
4. PiP supports multiBilingual (three pairs), denseChinese (five lines), and menuPages (four blocks per page) while keeping the old layouts and original-above-Chinese mode.
5. PiP draws when subtitles change, menu translations change (300ms coalescing), pages advance or a rare heartbeat is needed instead of rebuilding the same 640x360 frame every 0.8s.
6. Menu translation cache reuses normalized OCR text blocks with nearby matching positions, scoped by game, language, orientation, translation provider and endpoint. UI shows cached versus newly translated counts.
7. App diagnostics show raw OCR, accepted OCR, rejected-line counts and translated Chinese. Exported diagnostics contain recent OCR text and should be shared only with consent.
8. Existing iOS 27 single-app SideStore, default offline Translation, optional online APIs, Dragon Quest one-tap dictionary and portrait/landscape geometry remain in place.

## Source preflight and automated checks
- tools/verify_direct_release.py runs after project generation and checks direct-target invariants.
- Codemagic will typecheck GameOCRQuality.swift using host Swift.
- Codemagic will compile and run tests/ocr_quality_smoke.swift for kana, kanji, UI numbers, damaged characters and candidate selection.
- Codemagic then runs its complete source parser check and native iOS xcodebuild. These steps have NOT been run in this response.

## Known unresolved or device-dependent issues
- Xcode Apple framework types and iOS 27 API availability require Codemagic's actual iOS compilation.
- Real game OCR correctness (stylized/small/animated glyphs) requires actual screenshots and physical-phone comparison.
- iOS background scheduling, PiP audio/video continuity and SideStore signing require real-device validation.
- Higher-density PiP cannot guarantee all recognized full-screen text is readable simultaneously: complete menu results are available in the App's scrollable catalog.
- Games may use capture-blocking content or draw rotated assets in a landscape-sized buffer; manual rotation is retained.
- FPS, end-to-end subtitle latency, energy and 30-minute stability are not measured; sampling interval should not be misrepresented as translation latency.
- The app cannot reliably distinguish every home screen or third-party app from a game, but avoids processing GameLingo itself while the app UI is active.

Release target: GameLingo Direct 3.4.0, Build 9. Workflow: ios-direct-unsigned. IPA: GameLingoAI-Direct-iOS27-unsigned.ipa.