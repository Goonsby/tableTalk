# Whipple Chat for iPhone

The `ios/` directory contains a native SwiftUI application for **iOS 18 or later**, alongside Android. One English-speaking operator controls both language turns, Start/Stop, Retry and transcript corrections; the Spanish viewer has readable instructions and captions with no buttons. Portrait places the viewer above the operator; landscape places it beside the operator. Both start upright for a counter or glass, with an operator-controlled viewer flip. See the [operator guide](whipple-chat.md).

Version **0.2.2, build 3** retains accessible, cancellable translated-caption reveal and stable full-text wrapping. Original captions remain immediate. Scrolling completes reveal and takes over following; a new turn, clear, setup or backgrounding cancels pending work. Reduce Motion and VoiceOver show full translations immediately. Corrections revise the latest source turn and retranslate it without changing older turns.

Sample mode keeps the microphone off and uses fixed text. Start/Stop simulates transcription and translation; corrected sample text receives a labeled fixed preview. Simulator results do not establish physical speech recognition, language readiness, true offline inference or microphone performance through glass. CI deliberately produces unsigned builds; no signed IPA or TestFlight distribution is included.

## Requirements and architecture

- An iPhone running iOS 18 or later that supports on-device speech recognition for the selected languages. OS version alone does not establish asset readiness.
- A Mac with Xcode 16 or later and an iOS SDK supporting the phone's OS; use a newer Xcode if the connected phone requires it. XcodeGen generates the project from the checked-in specification.
- Internet access during initial language provisioning. Conversation testing must also succeed with all network connectivity disabled.

The app uses `SFSpeechRecognizer` with English (United States), `en-US`, and Spanish (Spain), `es-ES`. It checks `supportsOnDeviceRecognition` and sets `requiresOnDeviceRecognition = true` on every request. Recognition fails visibly when local recognition is unavailable; app code never enables a server fallback. Spanish accent suitability needs testing with the intended speakers. See Apple's [on-device recognition request](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition) and [recognizer capability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition) documentation.

Apple's Translation framework handles English-to-Spanish and Spanish-to-English text translation with local language models. Sessions are attached to SwiftUI views, and translation assets are shared with the system and other apps. The app uses explicit language preparation and checks installed availability before conversation translation. It does not import Android's Whisper model or use ML Kit. See Apple's [Translation API introduction](https://developer.apple.com/videos/play/wwdc2024/10117/).

## Build and install

The current preview is on **`codex/whipple-chat`** and has not been merged. The earlier native branch remains in [draft PR #2](https://github.com/Goonsby/tableTalk/pull/2). On a Mac, use that branch:

```sh
git clone --branch codex/whipple-chat https://github.com/Goonsby/tableTalk.git
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

Open the successful **iPhone checks** run for the exact PR head commit and download **`whipple-chat-iphone-checks`** from its Artifacts section. The bundle includes:

- `WhippleChat-iPhone-Source.zip`: the native source and this guide. Extract on a Mac, run `xcodegen generate --spec ios/project.yml`, then open `ios/TableTalk.xcodeproj` and follow the Personal Team/device steps above. Install XcodeGen first if needed.
- `WhippleChat-iPhone-Unsigned.zip`: a compiled ARM64 Release `.app`, built with signing disabled. It is compilation evidence and **cannot be installed directly on a phone**.
- `WhippleChat-iPhone-Simulator.zip`: the Debug simulator `.app`; **cannot run on a physical iPhone**.
- `build-info.json`: exact workflow and source-head commits, version/build, file sizes/checksums and signing limits. PR workflows test their synthetic merge commit; `head_commit` identifies the matching PR head. Logs, screenshots and `.xcresult` record the checks.

The checked-in project uses automatic signing but does not specify Henry's development team, and CI deliberately disables signing. Downloading either compiled ZIP does not install the app. The next owner step is **select Personal Team and Product > Run on the connected iPhone in Xcode**. If no Mac with Xcode is available, phone installation remains blocked by an authorized signing/distribution route; this task does not create credentials or upload to TestFlight.

## Prepare the phone while online

1. Open Whipple Chat's setup screen. Use the microphone and Speech permission button and accept both system prompts. If previously denied, enable the permissions for Whipple Chat in iOS Settings, then return and check again.
2. Choose **Prepare languages** and approve Apple's language download prompt when needed. Wait for downloads to complete. The preparation flow probes both translation directions with fixed, nonsensitive sample phrases.
3. If local speech is unavailable, open **Settings > General > Keyboard**. Add English (US) and Spanish (Spain) keyboards, enable Dictation, and enable those Dictation languages where that setting is offered. Leave the phone online while iOS prepares its language assets. Setting names can vary with iOS version. Follow Apple's [Dictation setup guide](https://support.apple.com/guide/iphone/dictate-text-iph2c0651d2/ios).
4. Return to Whipple Chat and choose **Check offline readiness**. Resolve missing languages or permissions before starting a real conversation.
5. Turn on **airplane mode**, explicitly turn **Wi-Fi off**, close Whipple Chat, and reopen it. Check readiness and test real English-to-Spanish and Spanish-to-English turns. Keep these network settings for an offline visit.

Whipple Chat cannot directly download or import the legacy Speech framework's Dictation assets. Their installation and availability are controlled by iOS. A capability check is not proof that a real utterance will succeed, so the two-direction airplane-mode test is mandatory. Apple's [Speech framework overview](https://developer.apple.com/videos/play/wwdc2025/277/) describes the legacy recognizer's reliance on user-enabled languages.

Translation preparation can return when downloads are already in progress; it is not by itself an installation guarantee. Check readiness again after downloads complete. System-managed assets can change outside the app, so recheck before each visit. Missing assets should produce a visible setup or translation failure rather than invented captions. See [`prepareTranslation()`](https://developer.apple.com/documentation/translation/translationsession/preparetranslation()) and [`LanguageAvailability`](https://developer.apple.com/documentation/translation/languageavailability).

## Conversation and privacy

The operator chooses **Speak English** or **Listen to Spanish**, then **Stop**. Capture stops at 12 seconds. The Spanish viewer reads Spanish captions and instructions; the English operator sees the English captions and the Spanish counterpart. The original remains visible if translation fails. **Retry** captures the latest selected language again. **Edit transcript** revises only the latest source and translates it again. History is limited to 12 turns. **Clear**, setup or leaving the foreground clears conversation and invalidates late results. Sample mode simulates these states without microphone access or real inference.

App code keeps audio and transcripts in memory and does not write conversation files, log conversation content, or add analytics. It stops capture and clears the displayed conversation on loss of foreground activity. This is not forensic memory erasure: Swift strings, framework buffers, and system-managed processing are outside such a guarantee.

iOS does not give this app Android's removable `INTERNET` permission or `FLAG_SECURE` screenshot protection. **Screenshots are possible.** Covering the interface when inactive reduces exposure in app switching; it does not prevent a person from photographing or recording the display. Whipple Chat's local-processing choices are also not a device-wide network block. Airplane mode with Wi-Fi off provides the operational offline boundary; Apple controls its system services and language-asset management.

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
- **Layout and accessibility:** inspect the passive Spanish viewer and all English operator controls in portrait/landscape, try the optional viewer flip, large Dynamic Type, long-caption scrolling and VoiceOver. Check operator access to Stop, Retry, Edit, Clear and Setup. The Spanish viewer must not require a touch.
- **Counter audio:** test the real phone placement and permitted microphone/intercom arrangement through plexiglass. Confirm intelligible Spanish capture at the intended distance and noise level. Simulator evidence cannot verify this path.
- **Correction and retry:** correct the latest source in each language and confirm older turns remain. Retry after recognition and translation failures. Cancel the editor and background it; private text must not persist on return.
- **Caption reveal:** translate a longer turn in each direction. Check stable line wrapping, manual-scroll takeover, cancellation by a new turn/clear/background, and immediate complete captions with Reduce Motion or VoiceOver enabled.
- **Privacy:** inspect the app switcher after backgrounding; confirm captions are gone on return. Verify that screenshots remain possible and communicate that limitation to participants.

Facility permission for microphone-based transcription and device use still needs confirmation before a visit. This prototype is not a substitute for a qualified interpreter for legal, medical, or other consequential decisions.
