# TableTalk

An Android starter for a pastor and a Spanish-speaking visitor to share one phone across a table. English and Spanish appear together; the Spanish half faces the other person with a 180° rotation.

**Current status:** both signed Android test APKs have been built and passed lint with no errors. The offline APK's permissions, both signatures, ARM64 native libraries, and JNI exports have been verified. The prototype has not been installed or tested on an LG G6/G7 and needs device validation before a visit. See [verification](docs/verification.md).

Follow [the APK installation guide](docs/apk-installation.md) for the setup APK, offline APK, and verified multilingual Whisper tiny model. The public GitHub Release contains both APKs and the verified speech model; downloads work without a GitHub account. Build tools, private signing keys, and downloaded dependencies are excluded from this source repository.

## Download onto the phone

Public downloads require no GitHub login:

1. [Setup APK](https://github.com/Goonsby/tableTalk/releases/download/v0.1.0-test/tabletalk-setup.apk) — install first.
2. [Whisper tiny speech model](https://github.com/Goonsby/tableTalk/releases/download/v0.1.0-test/ggml-tiny.bin) — import in TableTalk, then choose **Download Spanish over Wi-Fi**.
3. [Offline visit APK](https://github.com/Goonsby/tableTalk/releases/download/v0.1.0-test/tabletalk-offline.apk) — install over setup without uninstalling or clearing data.

See [the installation guide](docs/apk-installation.md). Test both speaking directions in airplane mode with Wi-Fi off before a visit. These are initial test builds, not yet validated on an LG handset.

## The first version

- Tap **Speak English** or **Hablar español**, speak a short sentence, and tap again to finish. Capture stops automatically at 12 seconds.
- Whisper transcribes locally in the selected language. The original appears first; ML Kit then translates locally into the other language.
- Both halves show both texts, with the reader's language larger. The opposite half, its controls, and its captions rotate together.
- The last 12 turns stay in memory. **Clear / Borrar**, switching to setup, leaving the foreground, and closing the app clear the displayed conversation and invalidate outstanding results.
- Audio buffers stay in RAM; the app writes no conversation files and adds no analytics. Screenshots and recent-app previews are blocked with `FLAG_SECURE`.
- A visibly labelled sample mode lets you try the layout without microphone access or model files.

This version produces captions **after each speaking turn**, not word-by-word live captions. That is deliberate for the older LG hardware. See [feasibility](docs/feasibility.md) for the tradeoffs and [the roadmap](docs/roadmap.md) for continuous listening.

## Build

Use a development computer with Android Studio, JDK 17, Python 3.11+, and Git. The phone itself needs Android 7.0+ and a 64-bit ARM OS. The G6 and G7 normally fit this requirement; verify the actual handset.

Install these SDK components through Android Studio's SDK Manager:

```text
Android SDK Platform 35
Android SDK Build-Tools 35.0.0
NDK (Side by side) 27.2.12479018
CMake 3.22.1
```

From the project directory:

```sh
python3 scripts/bootstrap.py
# Set ANDROID_HOME to your installed SDK, or set sdk.dir in local.properties.
sh gradlew :app:assembleSetupDebug :app:assembleOfflineDebug
```

Bootstrap fetches whisper.cpp **v1.7.6**, verifies commit `a8d002cfd879315632a579e73f0148d06959de36`, and prepares Gradle **8.11.1** with a checked distribution checksum. `gradlew` is a small launcher for that distribution; this starter does not include a wrapper JAR. Internet is required on the development computer to fetch source, SDK components, and Maven dependencies.

Native compilation uses the ARMv8-A baseline for G6 compatibility. Accelerated ARMv8.2 builds and GPU inference are not enabled. The initial APK supports `arm64-v8a` only, including ARM64 emulators.

Native code uses `-O3` even in these signed debug APKs, so debug compilation does not unnecessarily slow inference. On a managed Linux x64 workspace, `python3 scripts/build_android.py` can provision the JDK/SDK and build both APKs with Python 3.12+. Its output is placed in `artifacts/`. Preserve `.tooling/android-user/debug.keystore` privately to sign compatible future test updates; it is not included in downloads.

For Android Studio import, open this directory and select the local Gradle distribution at `.tooling/gradle-8.11.1` after bootstrap, with JDK 17. Alternatively, use the command-line build above.

## Prepare the phone before the visit

1. Build and install the **setup** APK:

   ```sh
   adb install -r app/build/outputs/apk/setup/debug/app-setup-debug.apk
   python3 scripts/download_model.py tiny
   adb push models/ggml-tiny.bin /sdcard/Download/ggml-tiny.bin
   ```

2. Open TableTalk, import `ggml-tiny.bin`, and choose **Download Spanish over Wi-Fi**. The tiny model is about 75 MiB. Both local translation directions are checked. No Google Cloud account, paid API, or server is needed.

3. Run **Check offline readiness**. Start a conversation and test English → Spanish and Spanish → English. The speech import accepts only the original, checksum-verified multilingual **tiny** or **base** model files. `.en` and quantized models are not accepted in this version.

4. Install the **offline** APK over the setup app:

   ```sh
   adb install -r app/build/outputs/apk/offline/debug/app-offline-debug.apk
   ```

   Both variants share application ID `org.tabletalk` and must use the same signing key. The offline variant has a higher version code. Use `-r`; **do not uninstall or clear app data**, which would remove models. Model retention across this update needs a real-device check.

5. Verify the installed offline APK's permissions, enable airplane mode, turn Wi-Fi off, force-stop the app, and reopen it. Test both speaking directions again. Follow the full [device test guide](docs/device-testing.md). A readiness check alone does not establish acceptable speech quality or latency.

The **setup** variant permits internet access for model provisioning. The **offline** variant removes `INTERNET`, including dependency manifest declarations. It retains passive `ACCESS_NETWORK_STATE` queries for SDK compatibility; that permission does not permit internet connections. Missing models fail visibly. Conversation processing never calls the model-download method.

To return from offline version code 2 to setup version code 1 for debug development, `adb install -r -d ...app-setup-debug.apk` may be needed. Production distribution would need a proper upgrade/version scheme and a consistent release signing key.

## Check the project

```sh
sh scripts/check_core.sh
python3 -m py_compile scripts/bootstrap.py scripts/download_model.py scripts/check_apk_permissions.py
sh gradlew :app:lintSetupDebug :app:lintOfflineDebug
python3 scripts/check_apk_permissions.py \
  --aapt "$ANDROID_HOME/build-tools/35.0.0/aapt" \
  app/build/outputs/apk/offline/debug/app-offline-debug.apk
```

The core checks cover language routing, preserving original text on failed translation, bounded capture/history, silence rejection, and preventing late results from restoring cleared conversations. A GitHub Actions workflow is included to build both APKs, run lint, and inspect offline permissions when the project is pushed to a repository.

Open [docs/ui-preview.html](docs/ui-preview.html) locally for a self-contained, interactive sample of the two-person layout. It never uses a microphone or performs inference.

## Project map

| Location | Purpose |
| --- | --- |
| `app/src/main/java/org/tabletalk/MainActivity.java` | Setup, permissions, lifecycle, opposing panels, and orchestration |
| `core/ConversationLedger.java` | Memory-only turns and cancellation epochs |
| `core/AudioSamples.java`, `audio/PcmRecorder.java` | Bounded 16 kHz mono capture and buffer cleanup |
| `inference/WhisperEngine.java`, `app/src/main/cpp/whisper_jni.cpp` | Serialized, cancellable Whisper JNI inference |
| `inference/TranslationEngine.java` | Local translation and explicit setup downloads |
| `models/ModelStore.java` | Atomic, checksum-verified speech-model import |
| `app/src/offline/AndroidManifest.xml` | Removes network permissions from the visit build |
| `docs/` | Research, architecture, pilot plan, and preview |

## Before using it in a visit

Confirm that the Whipple visit allows the phone **and microphone-based transcription**. This project's research could not verify the current facility-specific rules. Test with consenting Spanish speakers in a room similar to the visit setting; names, dates, negations, and emotionally important phrases deserve particular attention. Use a qualified interpreter for decisions where a mistranslation would matter, including legal or medical conversations.

Clearing the UI removes conversation references and cancels processing; it is not a promise of forensic erasure of Java strings or native model memory. Google ML Kit is a proprietary dependency, and its setup-time SDK data practices require review before broader distribution. The offline app cannot open network connections using its own UID. See [architecture](docs/architecture.md) for these boundaries.
