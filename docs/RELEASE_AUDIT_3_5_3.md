# GameLingo Direct 3.5.3 (Build 14) — stable translation repair

Date: 2026-10-24. Branch: `main`. This is a patch to the original Direct build, **not** the `experiment/mlkit-japanese-ocr` branch.

## Evidence and scope

The 2026-10-24 follow-up diagnostic log contained 74 events: 23 OCR samples, 40 translation completions, 10 translation failures, and a capture-start event. Its later phase included increased translation latency and repeated failures, but the old schema did **not** record underlying Translation errors or language-pack availability. A missing language pack or rapidly changing auto-detected language is a plausible **hypothesis**, not a proven root cause.

The repair is intentionally narrow: preserve iOS 27 ScreenCaptureKit capture, existing Apple Vision OCR, PiP, historical translations, glossary precedence, online-provider opt-in, and menu/screenshot OCR.

## Changes

1. **Conservative game-level source-language tracker:** a strong Japanese kana or Korean Hangul signal can switch immediately. Ambiguous Latin/Han text must be observed in two *distinct* strings before changing a previously stable source language; repeated frames containing the same HUD are not sufficient. Number-only HUD strings remain untranslatable. The tracker resets when the game/configuration or screen geometry changes.
2. **Availability preflight:** before an uncached offline model translation, `LanguageAvailability.status(from:to:)` checks the exact selected source against `zh-Hans`. Status `installed` continues into the existing TranslationSession; `supported` displays a missing-pack prompt; `unsupported` displays a language-pair warning. No network provider is activated without explicit user choice.
3. **No overhead for local results:** passthrough Chinese, exact glossary matches, complete cache hits and fully cached multiline source are returned without language-availability lookup.
4. **Per-provider/source backoff:** missing pack 20 seconds, unsupported pair 90 seconds, empty translations exponential 2–30 seconds, other execution errors exponential 3–60 seconds. A failed language doesn't block another language. A successful translation resets that language's cooldown. Last visible subtitles are preserved on failure.
5. **Revalidation:** cached installed-pack status has a 90-second TTL; uninstalled status has a short TTL. The App entering foreground clears the lookup/cache suppression so it can recover after the user prepares new offline languages. Failed offline sessions invalidate availability cache.
6. **Privacy-safe diagnosis:** additional `translation_language_status` event and numeric `translation_error_kind` (1=missing pack, 2=unsupported, 3=empty, 4=other), `translation_retry_delay_sec`, and `source_language_id` (predeclared language numbers only). Actual translated text, image frames and error strings are never stored in the JSONL event log.
7. **Regression protection:** Foundation-only `GameTranslationSafety.swift` tests, `translation_safety_smoke.swift` included in `ios-direct-unsigned`; release preflight asserts new source files, Apple availability checks, cooldown logic and unchanged PiP/translation providers.

## Next device test

- Run Codemagic `ios-direct-unsigned` from **main** and confirm native Xcode compile succeeds. No local Mac/Xcode build was available during this repair.
- Install Build 14 and repeat the same game's dialogue for at least 15 minutes with automatic language and a downloaded language pack. Include a separate missing-language-pack test (expect one classified error followed by suppressed repeats).
- Compare OCR and translation P50/P95, end-to-end capture→PiP times, failures per minute and OCR text accuracy; maintain or improve PiP smoothness and thermals.
- Export new JSONL and inspect `translation_error_kind` and `language_status`. A smaller number of logged failures alone does *not* prove faster translations; independently verify latency and output accuracy.

Apple source: https://developer.apple.com/documentation/translation/languageavailability/status and https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:).
