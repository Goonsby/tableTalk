# Offline feasibility for the LG G6 and G7 ThinQ

Research checked October 1–2, 2026. Hardware timing below is a **test target**, not a measured result.

## Finding

The proposed pipeline is technically feasible: Android microphone → local Whisper → local text translation → opposing bilingual captions. The practical uncertainty is how quickly and accurately it works on the actual LG phone. A turn-based first version is realistic to investigate; smooth, continuous bilingual captions should not be promised on this hardware.

The G6 commonly has a Snapdragon 821 and 4 GB RAM. The G7 ThinQ commonly has a Snapdragon 845 and 4 GB RAM, with 6 GB variants in some markets. Both are older CPUs, and Android, Google services, and other apps share that RAM. Start with the **G7**, if available, and confirm the OS version, free storage, and variant in Settings. Its larger screen also helps, though each half still has little room for large text.

## Why Whisper plus a separate translator

Whisper's multilingual models transcribe Spanish and English. Whisper's speech-translation task translates speech **into English**; it is not an English-to-Spanish translator. A separate translation model is needed for the mother's English speech. Transcribing both directions first also preserves the original wording beside the translation.

The starter fixes the source language using the speaker's button. It avoids language detection overhead and ambiguity when voices overlap or someone uses a name from the other language. It does not identify speakers or separate simultaneous speech.

## Model choices

| Component | Choice | Reason and limitation |
| --- | --- | --- |
| Speech, first trial | whisper.cpp multilingual `tiny` | Upstream reports 75 MiB disk and roughly 273 MB model memory. Smallest multilingual Whisper; accuracy needs Spanish-speaker review. |
| Speech, optional comparison | multilingual `base` | Upstream reports 142 MiB disk and roughly 388 MB model memory. Potential accuracy improvement with more computation. Benchmark before selecting it on either LG. |
| Translation, starter | ML Kit on-device English ↔ Spanish | Google's sample exposes downloadable local models and local translation clients. Fits a two-language prototype without a server. Closed-source SDK; quality, SDK data practices, and download retention must be reviewed. |
| Streaming fallback | Vosk | Designed for offline streaming recognition. If tiny Whisper is too slow, compare small Spanish and English Vosk models on the same recordings. Accuracy may differ substantially. Not implemented here. |
| More control later | A licensed English/Spanish Marian or Bergamot pair | Could permit completely sideloaded translation packs. Conversion, tokenizer integration, licensing, and phone performance add work. Not selected or benchmarked yet. |

Whisper memory figures are upstream reference figures, not total Android app memory. Peak app RAM includes decoder buffers, translation engines, UI, and the operating system. Quantization may reduce size and sometimes improve speed, but does not prove real-time performance. This starter uses original model files to keep imports verifiable against published upstream checksums; quantized support is a later experiment.

Avoid English-only `.en` checkpoints: they do not meet the Spanish requirement. Larger Whisper and multilingual LLM translators are a poor starting choice for 4 GB handsets.

## Existing application worth knowing about

[RTranslator](https://github.com/niedev/RTranslator/tree/v3.00) already provides offline Android speech translation, including a single-phone walkie-talkie mode. Its README documents a 1.2 GB initial download for the described Whisper/NLLB configuration and at least **6 GB RAM** to avoid crashes. That makes it a questionable fit for typical G6/G7 handsets. A 6 GB G7 variant could be tried, but this is not a device compatibility claim.

The current README also announces a 3.0 beta with new translation models. Its prose mixes older configuration details with beta changes, so the 6 GB statement and download figure should not be treated as measurements of every 3.0 model. We have not installed or benchmarked RTranslator. Its described single-phone mode does not establish the requested opposing-screen layout.

## Offline boundary

Model setup requires internet **before** entering the building. Speech files can be downloaded on a computer and copied to the phone. ML Kit downloads are initiated explicitly in the setup APK over Wi-Fi. The second APK uses the same package/signature, preserves app data with an in-place update, and removes internet permission. Passive network-state queries remain allowed for SDK compatibility.

Real speech and translations must pass a cold-start test in airplane mode, with Wi-Fi off, after replacing the setup APK. Verify permission removal on the actual APK; inspecting source manifests is not sufficient. Test reboot, process death, and low-storage recovery. Removing app data or uninstalling removes prepared models.

## What "live" can mean on these phones

The implemented baseline is tap → speak up to 12 seconds → tap → original text → translated text. The displayed processing time excludes capture duration. It is also not yet a reliable Whisper-only benchmark.

Suggested pilot goal: for a 5-second utterance, complete both captions within **5 seconds after the turn ends**, with acceptable meaning accuracy. This is a chosen usability target, not a forecast. Measure median and p95 over repeated English and Spanish turns. Sustained use may slow down as the phone heats up.

Only investigate continuous mode after measuring whether processing consistently keeps up with audio. A later mode needs voice activity detection, stable sentence boundaries, cancellation, limited queues, language/speaker controls, and careful handling of provisional captions. Whisper works on audio windows rather than providing a native per-word streaming decoder. Its default encoder window can incur substantial work even for a short turn; shortening speech does not guarantee proportionally shorter processing. Re-decoding overlapping windows can be expensive on these devices.

## Visit setting and quality

Facility-specific permission for devices and transient microphone capture remains **unverified**. Phone placement, a partition, room noise, masks, quiet voices, accents, and overlapping speech can all change performance. No persistent recording does not automatically establish permission to use a microphone.

Evaluate meaning preservation with a bilingual reviewer: negation, names, dates, numbers, family relationships, distress, and pastoral vocabulary matter more than a polished-looking caption. Audio-energy gating and Whisper's no-speech score are heuristics; they do not prove transcription accuracy or eliminate hallucinated speech. The app does not present a made-up confidence percentage.

## Sources

- [whisper.cpp platform support and memory figures](https://github.com/ggml-org/whisper.cpp#memory-usage), and [pinned Android native example](https://github.com/ggml-org/whisper.cpp/blob/v1.7.6/examples/whisper.android/lib/src/main/jni/whisper/CMakeLists.txt).
- [Pinned model sizes, multilingual naming, and checksums](https://github.com/ggml-org/whisper.cpp/blob/v1.7.6/models/README.md).
- [OpenAI Whisper translation direction and model licenses](https://github.com/openai/whisper#command-line-usage).
- [Google's actual Android translation sample](https://github.com/googlesamples/mlkit/blob/master/android/translate/app/src/main/java/com/google/mlkit/samples/nl/translate/kotlin/TranslateViewModel.kt) and [dependency configuration](https://github.com/googlesamples/mlkit/blob/master/android/translate/app/build.gradle). These were read directly. The sample links [ML Kit's Android guide](https://developers.google.com/ml-kit/language/translation/android); that external page could not be retrieved in this session.
- [RTranslator current README](https://github.com/niedev/RTranslator/blob/v3.00/README.md), read directly. Model and performance claims above are attributed to its authors, not independently validated.
- [Vosk](https://github.com/alphacep/vosk-api), for the later streaming alternative.

No LG-specific inference benchmarks, facility policy, or physical-device results were obtained in this workspace.
