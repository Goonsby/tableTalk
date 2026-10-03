# TableTalk for Xiaomi POCOPHONE F1

Install [tabletalk-poco.apk](https://github.com/Goonsby/tableTalk/releases/download/v0.2.0-poco/tabletalk-poco.apk), then open TableTalk and tap **Download speech + translation models**. Wi-Fi is the default; check **Allow mobile data for model downloads** if desired. The multilingual Whisper tiny model is approximately 75 MiB; Spanish translation is a separate download. Leave the setup screen open until both directions pass the readiness check. If interrupted, retry: completed models are reused, while incomplete speech downloads restart safely.

The app records and transcribes speech and translates English ↔ Spanish on the phone. Internet access is retained for model setup; no second APK is necessary. Test both directions in airplane mode with Wi-Fi off. The Google ML Kit SDK may use its own networking for model management and diagnostics when online; this build does not enforce the network isolation of the old offline variant.

## Device tuning

- ARM64 only, Android 8.0/API 26 or later.
- Snapdragon 845 ARMv8.2-A with FP16 CPU kernels, optimized with `-O3`. No dot-product instructions or GPU dependency.
- Tiny multilingual model recommended; verified base-model import remains available but uses more memory and computation.
- At most four inference threads, one inference at a time, and twelve-second maximum recordings.
- System-bar insets protect the two opposing caption panels; keep the phone in portrait for the best layout.
- Release build with debugging disabled. Signed with a locally retained development certificate; this is a test distribution, not a Play Store release.

Hardware reference: [Xiaomi's POCOPHONE F1 specifications](https://www.mi.com/uk/poco-f1/specs/). Download behavior follows [ML Kit's Android translation API](https://developers.google.com/ml-kit/language/translation/android).

## Installation and updates

The package is `org.tabletalk.poco`, version code 10. It installs alongside the older `org.tabletalk` test APKs because their original private signing key is not in this checkout. Models from the old app are not shared; the POCO app downloads its own copies. Future POCO updates must use the same signing key and a higher version code. Do not uninstall or clear storage when updating if you want to retain models.

The private key is retained locally at `.tooling/android-user/debug.keystore` and excluded from Git. Keep a private backup for compatible future updates. CI builds use a different development key unless explicitly provisioned with this one; do not substitute a CI APK for a published update.

## Verification and remaining device checks

Automated validation covers core conversation behavior and model transfer integrity; build/lint and APK inspection results are recorded in the release notes. No Pocophone F1 was attached to the build computer, so speech quality, latency, temperature, microphone behavior, and MIUI download behavior still require a handset test. No performance multiplier is claimed.

On the phone:

1. Complete downloads on Wi-Fi; confirm the progress and readiness messages.
2. In airplane mode, say a short sentence in each language. Confirm original and translated captions appear on both sides.
3. Tap Clear during processing; ensure late results do not reappear. Background and reopen the app; captions must be cleared.
4. Test microphone permission denial and then granting it in Android settings.
5. Interrupt the speech download, reopen, and retry. Try mobile-data setup only after explicitly enabling it.
6. Rotate or close the app during setup and retry after reopening. Repeated short conversations should remain usable without excessive heating.

## Build

`python3 scripts/build_android.py` provisions the toolchain, builds all three variants and runs lint. The POCO APK is placed at `artifacts/tabletalk-poco.apk`. For a prepared environment, use `--rebuild-only`.

Direct Gradle tasks: `:app:assemblePocoRelease :app:lintPocoRelease`. The POCO flavor uses the configured development signing key even for its non-debuggable release build. Set `TABLETALK_DEBUG_KEYSTORE` to the preserved key for reproducible update signing.
