# Install the TableTalk test APKs

For an LG G6/G7 with Android 7.0 or newer and a 64-bit ARM OS. The builds have passed compilation, lint, native packaging checks, and signature checks. They have not yet been run on either handset.

## Download these files onto the phone

These public links work without signing in to GitHub:

- [Setup APK](https://github.com/Goonsby/tableTalk/releases/download/v0.1.0-test/tabletalk-setup.apk)
- [Whisper tiny speech model](https://github.com/Goonsby/tableTalk/releases/download/v0.1.0-test/ggml-tiny.bin)
- [Offline visit APK](https://github.com/Goonsby/tableTalk/releases/download/v0.1.0-test/tabletalk-offline.apk)

| File | Purpose |
| --- | --- |
| `tabletalk-setup.apk` | Install first; permits initial translation-model downloads. About 23.3 MiB. |
| `ggml-tiny.bin` | The verified multilingual speech-recognition model. About 74 MiB. |
| `tabletalk-offline.apk` | Install after setup, as an update; has no internet permission. About 23.3 MiB. |

## Prepare it on Wi-Fi

1. Open `tabletalk-setup.apk` and install it. Android may ask you to allow app installation from the browser or file manager you are using.
2. Open **TableTalk**. Choose **Import speech model (.bin)** and select `ggml-tiny.bin` from Downloads.
3. Choose **Download Spanish over Wi-Fi**. Wait for the model check to finish. Then choose **Check offline readiness** if needed.
4. Choose **Start conversation** and tap **Speak English**. Grant microphone access when asked, then tap again to begin. Speak a short sentence and tap **Finish speaking**. Test **Hablar español** from the opposite side too.
5. Open `tabletalk-offline.apk` and install it over TableTalk as an update. **Do not uninstall TableTalk or clear app data**; those actions remove the prepared models. Both APKs share the same package and signing certificate, and the offline APK has a higher version code.
6. Enable airplane mode, explicitly turn Wi-Fi off, force-stop TableTalk, and reopen it. Test real speech in both directions again. Repeat after a reboot before relying on it.

The setup APK also performs local inference; its internet permission supports preparation. The offline APK removes that permission entirely. There is no account or paid API to configure.

## Using the conversation screen

- Place the phone between both people. English faces the English speaker; the Spanish half and its controls face the person opposite.
- Tap your language's button, speak, and tap again to finish. Each turn is capped at 12 seconds. These are captions after speaking turns rather than continuous word-by-word captions.
- Original text appears before the translated text. Both panels show both languages.
- **Clear / Borrar** clears the displayed conversation. Leaving the foreground also clears it and stops capture.
- **Try the sample layout** uses fixed example sentences and never starts the microphone.

If an installation reports that the signatures do not match, a TableTalk build signed with another developer key may already be installed. Do not assume an in-place update will preserve data across different signing keys. Keep using matching APKs from the same build.

Follow [device-testing.md](device-testing.md) for meaning accuracy, delays, and sustained use. Confirm phone and microphone-transcription permission with the visiting organization before bringing it into a visit.
