# TableTalk for iPhone

The `ios/` directory contains a native SwiftUI application for **iOS 18 or later**, alongside the existing Android apps. It is designed for two people sharing one phone across a table: English and Spanish captions appear on both halves, and the Spanish half faces the other person with a 180-degree rotation.

Version **0.2.1, build 2** adds a gentle, cancellable reveal for translated captions. The complete translation is laid out immediately, so lines do not move as words appear. Original captions remain immediate. Manual scrolling takes over from automatic following and completes the reveal; clearing, a new turn, setup or backgrounding cancels it. Reduce Motion and VoiceOver display the complete translation immediately. Landscape uses side-by-side opposing panels, with scrollable captions at large text sizes; compact controls remain reachable.

A successful build or simulator test does not verify real microphone recognition, installed language assets, translation quality, or offline operation. There is no signed IPA, TestFlight distribution, or App Store release from this work.

## Requirements and architecture

- An iPhone running iOS 18 or later that supports on-device speech recognition for the selected languages. OS version alone does not establish asset readiness.
- A Mac with Xcode 16 or later and an iOS SDK supporting the phone's OS; use a newer Xcode if the connected phone requires it. XcodeGen generates the project from the checked-in specification.
- Internet access during initial language provisioning. Conversation testing must also succeed with all network connectivity disabled.

The app uses `SFSpeechRecognizer` with English (United States), `en-US`, and Spanish (Spain), `es-ES`. It checks `supportsOnDeviceRecognition` and sets `requiresOnDeviceRecognition = true` on every request. Recognition fails visibly when local recognition is unavailable; app code never enables a server fallback. Spanish accent suitability needs testing with the intended speakers. See Apple's [on-device recognition request](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition) and [recognizer capability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition) documentation.

Apple's Translation framework handles English-to-Spanish and Spanish-to-English text translation with local language models. Sessions are attached to SwiftUI views, and translation assets are shared with the system and other apps. The app uses explicit language preparation and checks installed availability before conversation translation. It does not import Android's Whisper model or use ML Kit. See Apple's [Translation API introduction](https://developer.apple.com/videos/play/wwdc2024/10117/).

## Build and install

The iPhone code is on **`codex/iphone-native`**, in [draft PR #2](https://github.com/Goonsby/tableTalk/pull/2); it has not been merged into `main`. On a Mac, use that branch:

```sh
git clone --branch codex/iphone-native https://github.com/Goonsby/tableTalk.git
cd tableTalk
brew install xcodegen
cd ios
xcodegen generate
open TableTalk.xcodeproj
```

Select the **TableTalk** scheme. For a personal iPhone:

1. Sign in to your Apple Account in Xcode's Settings, then select your **Personal Team** in the TableTalk target's **Signing & Capabilities** settings. Enable automatic signing. If Xcode requires a unique bundle identifier, choose one for your personal build.
2. Connect and unlock the iPhone, trust the Mac, and enable Developer Mode if Xcode/iOS requests it.
3. Select that iPhone as the run destination, then choose **Product > Run**. Follow any signing or trust instructions shown by Xcode and the phone.

A free Personal Team supports installing and testing your own app through Xcode; purchasing membership is not required just to test this app. Personal Team provisioning is temporary, so rebuild/reinstall when it expires. TestFlight and App Store distribution require the appropriate Apple Developer Program membership and signing setup. These credentials and distribution actions are left to the owner; none are included in the repository. See Apple's [account and Personal Team guide](https://developer.apple.com/help/account/basics/about-your-developer-account) and [running on devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

An unsigned device build checks compilation without installing or creating a distributable IPA. From the repository root, after generating the project:

```sh
xcodebuild -project ios/TableTalk.xcodeproj -scheme TableTalk \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

The Windows checkout can be used to edit sources, but Apple's iOS SDK, Xcode build, and simulator require macOS. The repository's macOS CI is the automated path for Apple-platform build checks.

### GitHub build downloads

Open the successful **iPhone checks** run for the exact PR head commit and download **`tabletalk-iphone-checks`** from its Artifacts section. The bundle includes:

- `TableTalk-iPhone-Source.zip`: the native source and this guide. Extract on a Mac, run `xcodegen generate --spec ios/project.yml`, then open `ios/TableTalk.xcodeproj` and follow the Personal Team/device steps above. Install XcodeGen first if needed.
- `TableTalk-iPhone-Unsigned.zip`: a compiled ARM64 Release `.app`, built with signing disabled. It is compilation evidence and **cannot be installed directly on a phone**.
- `TableTalk-iPhone-Simulator.zip`: the Debug simulator `.app`; **cannot run on a physical iPhone**.
- `build-info.json`: exact workflow and source-head commits, version/build, file sizes/checksums and signing limits. PR workflows test their synthetic merge commit; `head_commit` identifies the matching PR head. Logs, screenshots and `.xcresult` record the checks.

The checked-in project uses automatic signing but does not specify Henry's development team, and CI deliberately disables signing. Downloading either compiled ZIP does not install the app. The next owner step is **select Personal Team and Product > Run on the connected iPhone in Xcode**. If no Mac with Xcode is available, phone installation remains blocked by an authorized signing/distribution route; this task does not create credentials or upload to TestFlight.

## Prepare the phone while online

1. Open TableTalk's setup screen. Use the microphone and Speech permission button and accept both system prompts. If previously denied, enable the permissions for TableTalk in iOS Settings, then return and check again.
2. Choose **Prepare languages** and approve Apple's language download prompt when needed. Wait for downloads to complete. The preparation flow probes both translation directions with fixed, nonsensitive sample phrases.
3. If local speech is unavailable, open **Settings > General > Keyboard**. Add English (US) and Spanish (Spain) keyboards, enable Dictation, and enable those Dictation languages where that setting is offered. Leave the phone online while iOS prepares its language assets. Setting names can vary with iOS version. Follow Apple's [Dictation setup guide](https://support.apple.com/guide/iphone/dictate-text-iph2c0651d2/ios).
4. Return to TableTalk and choose **Check offline readiness**. Resolve missing languages or permissions before starting a real conversation.
5. Turn on **airplane mode**, explicitly turn **Wi-Fi off**, close TableTalk, and reopen it. Check readiness and test real English-to-Spanish and Spanish-to-English turns. Keep these network settings for an offline visit.

TableTalk cannot directly download or import the legacy Speech framework's Dictation assets. Their installation and availability are controlled by iOS. A capability check is not proof that a real utterance will succeed, so the two-direction airplane-mode test is mandatory. Apple's [Speech framework overview](https://developer.apple.com/videos/play/wwdc2025/277/) describes the legacy recognizer's reliance on user-enabled languages.

Translation preparation can return when downloads are already in progress; it is not by itself an installation guarantee. Check readiness again after downloads complete. System-managed assets can change outside the app, so recheck before each visit. Missing assets should produce a visible setup or translation failure rather than invented captions. See [`prepareTranslation()`](https://developer.apple.com/documentation/translation/translationsession/preparetranslation()) and [`LanguageAvailability`](https://developer.apple.com/documentation/translation/languageavailability).

## Conversation and privacy

Tap the speaker's language, speak a short sentence, and tap again to finish. Capture stops at 12 seconds. Both readers see the original and translated text, with their own language emphasized. The original remains visible if translation fails. The history is limited to 12 turns. **Clear / Borrar**, returning to setup, or leaving the foreground clears the conversation and invalidates late results. The labelled sample mode demonstrates the layout without microphone access or real inference.

App code keeps audio and transcripts in memory and does not write conversation files, log conversation content, or add analytics. It stops capture and clears the displayed conversation on loss of foreground activity. This is not forensic memory erasure: Swift strings, framework buffers, and system-managed processing are outside such a guarantee.

iOS does not give this app Android's removable `INTERNET` permission or `FLAG_SECURE` screenshot protection. **Screenshots are possible.** Covering the interface when inactive reduces exposure in app switching; it does not prevent a person from photographing or recording the display. TableTalk's local-processing choices are also not a device-wide network block. Airplane mode with Wi-Fi off provides the operational offline boundary; Apple controls its system services and language-asset management.

## Automated checks and verification status

Run the platform-independent Swift package tests from the repository root:

```sh
swift test --package-path ios
```

The initial [iPhone validation run](https://github.com/Goonsby/tableTalk/actions/runs/37143862798) passed 15 Swift core tests, an unsigned ARM64 iPhone Release build, and six UI tests on an iPhone SE (3rd generation) simulator running iOS 18.6, using Xcode 16.4. Core coverage includes language routing, bounded history/capture policy, silence rejection, preservation of originals when translation fails, and rejection of late results after clearing. UI tests cover both sample directions, clearing, returning to setup, initial readiness, and background clearing. The streaming microphone gate shares the tested capture thresholds; actual microphone input and framework callbacks still require device testing. Consult the exact commit's [GitHub Actions results](https://github.com/Goonsby/tableTalk/actions) for subsequent checks. CI artifacts contain the simulator app, test results, logs, and screenshots; the simulator app cannot be installed on an iPhone.

Apple's Translation framework does not perform inference in the iOS simulator. Simulator/sample tests verify application behavior and layout, not translation or microphone accuracy. No physical iPhone inference or offline test has yet been recorded for this implementation.

## Physical iPhone checklist

Record the commit, iPhone model, iOS version, language setup, elapsed response times, and pass/fail outcomes without recording private conversation content.

- **Cold offline start:** after online preparation, enable airplane mode and turn Wi-Fi off; close/reopen the app and pass readiness plus real turns in both directions.
- **Speech quality:** test names, numbers, dates, negations, Spanish accents, and quiet versus realistic room noise with consenting speakers. Confirm the original caption before relying on its translation.
- **Capture bounds:** finish a short turn manually, speak beyond 12 seconds, try a very brief tap, and remain silent. Confirm recording stops and no fabricated sample answer appears.
- **Clear and interruption:** clear while recording, recognizing, and translating; switch to setup, lock the phone, and background the app. Confirm microphone use stops, history clears, and delayed results never restore it.
- **Missing assets:** before setup, or after removing a downloaded translation language through system controls, check readiness offline. Confirm a visible failure. Restore assets and repeat both-direction testing.
- **Declined permissions:** decline microphone and Speech access separately. Confirm useful feedback and that sample mode remains available. Re-enable permissions and retry.
- **Layout and accessibility:** inspect both opposing panels and rotated controls, rotate the phone, use larger Dynamic Type settings, scroll long captions, and navigate with VoiceOver. Check that neither reader loses access to speaking or clearing controls.
- **Caption reveal:** translate a longer turn in each direction. Check stable line wrapping, manual-scroll takeover, cancellation by a new turn/clear/background, and immediate complete captions with Reduce Motion or VoiceOver enabled.
- **Privacy:** inspect the app switcher after backgrounding; confirm captions are gone on return. Verify that screenshots remain possible and communicate that limitation to participants.

Facility permission for microphone-based transcription and device use still needs confirmation before a visit. This prototype is not a substitute for a qualified interpreter for legal, medical, or other consequential decisions.
