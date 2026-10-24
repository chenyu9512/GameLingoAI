# Universal OCR (iOS 27, experimental)

Branch: `feature/universal-ocr-ui-language`. This branch does not change `main` or the former Japanese ML Kit experiment.

## Current implementation

- **Apple Vision** remains the default OCR engine for multilingual live text, bottom-of-screen OCR and full-page menus.
- **Hybrid mode** is selectable per game. Vision detects text boxes; the local **PP-OCRv6 Small** recognition ONNX model re-reads up to eight low-confidence lines, at most once per 1.2 seconds. The app compares candidates conservatively and falls back to Vision on errors. This is *not* a standalone Paddle text detection pipeline.
- Previous serialized `mlkitJapanese` profiles decode but resolve to Vision; no Google ML Kit code or Pods are built.
- Common language options include Japanese, Chinese (simplified/traditional), English, Korean, major European languages, Thai, Vietnamese, Arabic, Indonesian, and Dutch. Actual language support depends on the OCR engine and the iPhone's installed Vision revision. The selected *source language* can be fixed per game or set to automatic.
- OCR and translation are distinct. Apple Translation supports only a subset of OCR languages. The built-in language resource manager uses `LanguageAvailability` to report installed/supported/unsupported and `prepareTranslation()` to ask iOS to download translation resources. It does **not** display invented download percentages.
- Existing PiP display, glossary, diagnostics and translation retry logic remain intact.

## New Codemagic workflow

Select branch `feature/universal-ocr-ui-language` and workflow **`ios-universal-ocr-unsigned`**.

The build performs:
1. Generates the Direct iOS project with `GAMELINGO_ENABLE_PADDLE=1`, v3.7.0 (15).
2. Verifies static invariants and runs OCR/translation smoke tests.
3. Fetches the official PaddleOCR `PP-OCRv6_small_rec_onnx_infer` model and extracts its character dictionary. The model is downloaded at *build time* rather than committed to Git.
4. Installs `onnxruntime-objc` from CocoaPods and compiles the unsigned app.
5. Fails unless `PaddleModels/rec/inference.onnx` and `characters.txt` exist inside the IPA.

Artifact name: `GameLingoAI-Universal-OCR-unsigned.ipa`. Requires downstream device signing/sideloading (e.g. SideStore). An unsigned IPA does not establish App Store readiness.

## Model implementation and limitations

PaddleOCR model preset and URL originate from PaddleOCR's upstream `deploy/ios_demo/scripts/fetch_ios_demo_models.sh`. ONNX Runtime CocoaPods and Objective-C bridging follow the same upstream iOS demo. The package does not use a paid cloud OCR service.

Paddle currently performs **text-line recognition using Vision rectangles**. Because detection still depends on Vision, scripts unsupported by Vision may not be found; broader independent coverage requires integrating the Paddle detection model and DB post-processing, plus dedicated recognition language packs where PP-OCRv6 Small lacks support. Mixed-language output and unusual fonts need device-specific testing.

The model runs synchronously on the serialized OCR worker in balanced/battery mode only when a low-confidence frame is detected. It never runs on the main thread, but a slow inference can still increase latency: do not claim 200ms before on-device measurement. In fast mode, it is bypassed for latency safety.

The ONNX model uses 48px-high CHW BGR inputs and a greedy CTC decoder. Operator coverage, width scaling, box orientation, recognition accuracy, app size, heat and memory must be verified on an actual iPhone.

## Runtime checks

1. Open Game Configuration → OCR Engine. Select **Vision + PaddleOCR** and save. Choose a source language or auto.
2. On Home, verify the **Offline language resource** card shows the current pairing and reports actual installation state. If supported but not installed, request system download and inspect the iOS-owned dialog. The app cannot read exact download percentages.
3. Start capture, enter a game, verify translated subtitles and expanded full-screen menus.
4. Export JSONL diagnostics and look for `ocr_requested_backend = 2`, `ocr_paddle_available = 1`, and occasional `ocr_backend = 2` when Paddle results replace a low-confidence Vision result. Not every frame should use Paddle.
5. Compare P50/P95 capture-to-translation time, OCR errors, game footage readability, PiP playback and thermal behavior against the old Vision-only run.

## Status

Code and CI workflow are committed. **The new Codemagic job and iPhone runtime have not yet been executed/verified from this environment.** If the build fails, inspect `xcodebuild-universal.log`. Do not treat static verification as a successful compile.
