# Android translation reveal preview

This UI refinement is based on the published `v0.2.0-poco` source at `3fd0c0492b8860eaf34e10dd335f959b6fe11eb2`. The user reported that Android build works well on their phone. This preview keeps its speech capture, Whisper/ML Kit processing, model setup, opposing panels, and memory-only twelve-turn history.

## Reading a translation

The newest translation appears a word at a time, typically about 110 ms per word, with a total reveal of 0.6–12 seconds before Android's animation-speed setting is applied. The complete text is laid out from the start, so wrapping does not move as words appear. Long translations wrap within the panel and remain available by scrolling; no ellipsis or per-caption length limit is added.

The receiving panel starts at the beginning of the newest turn and follows the revealed line only when necessary. Touch the caption panel, use a keyboard or mouse to scroll, or use an accessibility action to reveal the rest immediately and take control of scrolling. Starting another speaking turn cancels the previous reveal and enables following for the next turn. Older turns remain fully readable within the existing twelve-turn history limit.

Clear, returning to Setup, leaving the app, or activity recreation cancels pending animations and removes conversation text. Rotation retains the existing privacy behavior: Android recreates the activity and clears the conversation.

When system animations are disabled or an accessibility service is active, captions appear in full immediately. Accessibility receives the complete translation once; reveal frames do not replace text or produce character-by-character announcements. Text uses the system font scale. Panel content scrolls independently, and speaking/clear/setup buttons expand to fit their labels. A compact bilingual status stays visible above the controls. Landscape puts the opposing panels side by side below those controls, leaving more vertical reading space; the Spanish panel remains rotated for the other reader.

## Installing the preview

The preview uses package `org.tabletalk.poco`, version `0.2.1-poco-preview`, code **11**. The review APK must be signed with the original POCO development certificate so it can update code 10 without uninstalling or deleting downloaded models. Do not replace the known-good APK or substitute an independently signed CI artifact. No new GitHub release is published by this change.

## Verification

Core behavior checks: `sh scripts/check_core.sh`.

Android UI tests: `sh gradlew :app:testPocoDebugUnitTest`. These use Robolectric with native graphics; speech inference is shadowed out. They exercise the actual activity and views, not microphone recognition or translation quality. CI also builds and lints all three Android variants and checks the offline APK's permissions.

Physical acceptance for this refinement remains separate from the user's successful test of the previous build:

1. Update the installed POCO app without uninstalling. Confirm existing models remain ready.
2. Speak longer English and Spanish sentences. Check wrapping, reveal speed, and scrolling in both opposing panels.
3. Start another turn during reveal; tap Clear during processing/reveal; background and reopen. No stale words should return.
4. Drag either caption panel during reveal. It should show the complete text and stop following automatically.
5. Try the largest comfortable system font, landscape, disabled animations, and TalkBack. Each panel should remain scrollable and TalkBack should read complete captions.

No new physical-phone, microphone, cold-offline, or TalkBack-device result is implied by the automated UI tests.
