# Build verification

Checked October 2, 2026. Both Android test APKs were successfully built in this workspace. No physical phone or Android emulator was used.

## Completed

- Full Android Java compilation, native ARM64 compilation/linking, packaging, and signing for `setupDebug` and `offlineDebug`.
- Android lint for both variants: **0 errors, 13 warnings** each. Remaining warnings concern intentionally omitted ChromeOS/x86 support and inline UI strings rather than Android resource localization.
- Offline APK permission inspection using Android `aapt`: `RECORD_AUDIO` present, `INTERNET` absent. Passive `ACCESS_NETWORK_STATE` remains allowed.
- Signature verification using `apksigner`; both APKs share the same signing certificate, enabling an in-place update from setup to offline.
- Package `org.tabletalk`, minimum Android API 24, target API 35, version codes 1/setup and 2/offline checked in the packaged APKs.
- Packaged native libraries verified as AArch64 ELF files; all five `WhisperEngine` JNI entry points are exported.
- Actual generated native build flags checked for `-O3` and the ARMv8-A baseline. Optimizations remain enabled in signed debug builds.
- Downloaded the original multilingual tiny model and verified published upstream SHA-1 `bd577a113a864445d4c299885e0cb97d4ba92b5f`.
- Previously compiled and ran 18 core behavior assertions covering language routing, pending/failed translation, bounded history/capture, silence filtering, and late-result rejection after clearing.

The compiler/toolchain used JDK 17, Gradle 8.11.1, Android Gradle Plugin 8.9.2, Android Platform 35, NDK 27.2.12479018, and CMake 3.22.1. APK SHA-256 checksums and signing-certificate fingerprints are in `artifacts/build-info.json`.

An upstream ggml ARM-feature display probe emits a nonfatal host-target diagnostic during cross-compilation. That probe only reports features; native compilation/linking succeeds, and packaged ELF architecture and compiler flags were inspected independently. SDK XML-version and unwritable build-metrics settings also emit nonfatal warnings.

## Still required on the phone

- Installation/launch, real model loading, microphone capture, model-download completion, recognition/translation quality, and timing on the actual G6/G7.
- Preserving downloaded models when replacing setup with offline, including cold-start use after force-stop/reboot in airplane mode with Wi-Fi off.
- Android permissions, lifecycle transitions, screenshot blocking, and physical table accessibility.
- Confirmation of the building's device and microphone rules.

See [device-testing.md](device-testing.md). These are development test builds, not a validated interpreter or a published release. No remote repository or store listing was created.
