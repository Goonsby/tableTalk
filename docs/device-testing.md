# G6/G7 pilot test

The code is not visit-ready until these checks pass on the actual handset. Use a consenting bilingual volunteer and nonsensitive test speech. The test script checks technical behavior; a fluent speaker must judge meaning.

## Record the device, not the conversation

Record model/variant, Android version, RAM, available storage, battery condition, tiny/base choice, APK version, and whether airplane mode and Wi-Fi were off. These are needed to interpret measurements. Do not retain names, real detainee stories, audio, or personal transcripts as benchmark records.

## Build and offline setup

1. Assemble both debug variants and run both lint tasks. Inspect the offline APK using `scripts/check_apk_permissions.py`; it must have `RECORD_AUDIO` and no `INTERNET` permission. `ACCESS_NETWORK_STATE` is permitted for passive SDK checks.
2. Install setup, import tiny, and download Spanish on Wi-Fi. Confirm both readiness translation probes pass.
3. Install offline over setup using `adb install -r`, with the same signing key. Verify model files still load. Do not uninstall between variants.
4. Enable airplane mode, explicitly turn Wi-Fi off, force-stop TableTalk, and reopen it. Do both real speech directions, including the first turn. Reboot and repeat. Model readiness without successful microphone inference is not a pass.
5. Grant microphone permission when asked. The first grant requires another tap to begin; no capture starts behind the permission dialog. Deny it once and verify the app explains how to allow it.
6. Try a wrong `.en` model and a truncated file. Import should fail visibly and the prior good file should still work after a readiness check.

## Layout and conversation behavior

- Place the phone on a table. Read the Spanish side from the opposite chair. Its text and controls must face that person, including its status messages.
- Tap each language, speak, finish, and verify source language selection. Both texts must appear in both panels, with each reader's language larger.
- Check small fonts, long sentences, scrolling, screen rotation, TalkBack, and accidental taps. Rotation clears the conversation because it backgrounds/recreates the activity; that behavior is intentional in this prototype.
- During capture, try the other speaker's button. It should be disabled. Finish on the active side. At 12 seconds capture must stop automatically.
- Speak extremely softly and sit farther from the microphone. Check whether the silence gate incorrectly suppresses meaningful speech. A threshold change requires repeating silence/hallucination checks.
- In complete silence and background noise, check that the app does not routinely invent captions. The existing gates do not guarantee that.

## Cancellation and privacy

- Clear while recording, while Whisper decodes, and while translation runs. No late caption should restore cleared text.
- Immediately start a new turn after Clear. A previous turn must not replace its captions or status.
- Press Home, lock the screen, open the permission dialog, and return. The mic must stop and the old conversation must be absent. Readiness/model setup can continue outside the conversation screen.
- Check that screenshots/recent-app previews are blocked, and that no transcript/audio files appear in app storage. Model files are expected.
- Test an unavailable microphone and a translation-model failure. Original text should remain visible when translation fails; no fabricated translated text should appear.

## Timing and sustained use

Use at least 20 short English and 20 short Spanish utterances, then a 15-minute alternating conversation. Include both warm and cold first turns. For each, record utterance duration, time from Finish to source caption, time from Finish to completed translation, and meaning-pass/fail. Report median, p95, failures, and deterioration during sustained use. The UI's processing timer excludes capture and may exclude executor wait, so use an external stopwatch for the first benchmark.

```sh
adb shell dumpsys meminfo org.tabletalk
adb shell dumpsys battery
```

Inspect native/PSS memory before and after sustained use, responsiveness, OS process kills, heat, and battery use. As an initial usability goal, aim for both texts within 5 seconds after a 5-second utterance ends. This is an acceptance target, not an expected measurement. Decide the final tolerated delay with the mother after she tries it.

If G7/tiny misses the target, compare a newer handset and Vosk before adding continuous mode. If meaning quality is poor, test base or another recognizer/translator with the same phrase set. Do not assume larger models or quantization will automatically solve both problems.

## Meaning test examples

These are prompts for human review, not exact-string translation tests. Accept natural synonyms but reject changes in speaker, negation, relationship, number, or intent.

| Spoken phrase | Meaning that must survive |
| --- | --- |
| ¿Cómo se siente hoy? | How the person feels today |
| Estoy preocupado por mi familia. | Worried about one's family |
| No quiero hablar de eso ahora. | Does **not** want to talk about it now |
| Tengo dos hijos y una hija. | Two sons and one daughter |
| Mi hermana me llamó ayer. | Sister called yesterday |
| No pude dormir anoche. | Could **not** sleep last night |
| Quiero hablar con un intérprete. | Wants an interpreter |
| ¿Puede repetir más despacio? | Requests slower repetition |
| How are you feeling today? | Question about today's feelings |
| Would you like me to pray with you? | Offer of prayer; no assumed consent |
| You do not have to answer that. | No requirement to answer |
| I can listen if you would like to talk. | Optional invitation to talk |
| I did not understand. Please say that again. | Lack of understanding and request to repeat |
| Your brother called on Tuesday. | Brother; past call; Tuesday |
| Please tell me if the translation is wrong. | Invitation to correct the translation |

Add locally relevant names and pastoral phrases with the bilingual reviewer. Have the visiting organization confirm the phone/microphone rules separately; this test does not establish access permission.
