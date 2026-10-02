# First milestones

## 1. Establish the baseline on the actual phone

- Build both APKs and pass lint and offline permission inspection.
- Identify G6/G7 OS version, RAM variant, storage, and battery health.
- Import tiny, provision Spanish, then replace setup with offline without losing models.
- Complete both directions after force-stop and reboot in airplane mode.
- Measure memory, latency, meaning accuracy, and thermal behavior with a bilingual volunteer. Use nonsensitive recordings and obtain permission before retaining test audio.

**Decision:** If tiny is accurate enough but slow, compare a newer device and Vosk. If tiny is fast enough but misses important wording, compare base. If both fall short, do not move directly to continuous listening.

## 2. Make the table layout usable with the mother's workflow

- Test large text, upside-down panel controls, TalkBack focus, screen rotation, and small displays.
- Add adjustable caption text size and an optional display of only the latest turn if the phone is cramped.
- Consider manual correction of the original before retranslation; display corrected text transparently.
- Review consent wording in Spanish and English with a bilingual person and the visiting organization.

## 3. Explore hands-free captions

- Evaluate VAD segmentation with short-sentence limits and silence handling.
- Keep an explicit active-language control initially; decide whether automatic detection actually helps.
- Add stable partials only if measured decoding can keep up without unbounded backlog.
- Make interim versus final captions clear, and ensure interruptions/overlap do not silently merge meanings.

## 4. Prepare wider use

- Review translation SDK terms/data disclosures and optional fully sideloaded translation engines.
- Add a reliable model-pack/update/versioning workflow, offline storage recovery, and user-facing readiness diagnostics.
- Recheck native/dependency versions and repeat device quality evaluation before release.
- Establish signed release builds and distribution. No publishing is part of the starter project.
