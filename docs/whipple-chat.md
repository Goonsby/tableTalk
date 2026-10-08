# Whipple Chat operator guide

One English-speaking operator holds or positions the phone. The Spanish viewer does not need to touch it. In portrait, the upper panel belongs to the viewer and the lower panel contains all operator controls. In landscape, the viewer is on the left and the operator is on the right. Start with both panels upright for a counter or plexiglass; **Flip Spanish view** is available when the physical position calls for it.

## Take turns

1. The operator chooses **Speak English** to speak or **Listen to Spanish** to invite the viewer. The viewer sees either a wait message or an instruction to speak slowly and clearly, one short sentence at a time.
2. The operator presses **Stop** when the sentence ends. Real capture is limited to 12 seconds. The panels show transcription and translation states while local processing finishes.
3. Read the captions and verify the meaning. Originals appear immediately; translations reveal in small groups while retaining the complete text's wrapping. Scrolling completes the reveal and lets the operator review older captions.
4. **Retry** records the latest selected language again. **Edit transcript** changes only the latest original and translates it again; earlier turns remain. Canceling the editor keeps the original. In sample mode, edited text receives an explicitly labeled fixed preview, not an actual translation.

Only the operator has Start, Stop, Retry, Edit, Clear, Flip and Setup controls. The Spanish display contains large instructions and Spanish captions, including explicit wait/listening/transcribing/translating states. Its caption area follows new turns automatically; text remains accessible to assistive technology even during visual reveal.

## Privacy and readiness

Conversation audio and captions stay in memory. Clear, setup and leaving the foreground cancel active work and clear history; late results cannot restore it. No conversation logging, analytics or upload is added. On Android, screenshots are blocked. iOS covers the app switcher but cannot prevent user screenshots. These behaviors are not a claim of forensic memory erasure.

Prepare local language assets while online, then test both directions in airplane mode with Wi-Fi off. Missing assets fail visibly. Android retains its existing Whisper/ML Kit path and network-free offline variant; iPhone requires on-device Speech and Apple Translation. See the platform setup guides. **Try sample layout** never opens the microphone and simulates the processing stages with fixed phrases.

## Test the actual counter

A phone on the operator's side may not hear a voice through plexiglass clearly. No software or simulator check establishes the actual microphone path. Test at the intended distance, background noise and speaking level with a consenting speaker, including the facility's permitted intercom or microphone arrangement if applicable. Check names, numbers, negation and corrections in both directions. If the other voice is too faint or distorted, change the permitted physical audio arrangement and retest.

The preview's automated visual checks exercise sample text, large type, portrait/landscape, repeated turns, retry/correction and interrupted processing. Physical microphone quality, installed language readiness, true offline inference and device-specific speed remain separate device checks.

## Build identity

Android preview: `0.2.2-whipple-preview`, version code `12`, POCO package `org.tabletalk.poco`. Use the existing private signing key for a compatible update; a fresh CI development key cannot update an earlier installation.

For a separate installation when the original signing key is unavailable, build
with `-PwhipplePreviewSuffix=.whipplepreview :app:assemblePocoRelease`.
This produces package `org.tabletalk.whipplepreview`, which installs alongside
the existing app and requires its own model downloads. Retain the preview's
private signing key for subsequent preview updates. The default POCO package
and its update signing requirements are unchanged.

iPhone preview: `0.2.2`, build `3`, bundle `org.tabletalk.ios`. CI produces an unsigned ARM64 device build, a simulator build and native source. Install through Xcode with the owner's Personal Team; no signed IPA or TestFlight distribution is provided. See [iPhone setup and installation](iphone.md).
