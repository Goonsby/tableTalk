package org.tabletalk.core;

import java.util.ArrayList;
import java.util.List;

/** Bounded, memory-only history. Epochs prevent cleared/cancelled work reappearing. */
public final class ConversationLedger {
    public static final int MAX_TURNS = 12;
    private final List<Turn> turns = new ArrayList<>();
    private long epoch;
    private long nextId;

    public synchronized long epoch() { return epoch; }
    public synchronized long invalidate() { return ++epoch; }
    public synchronized void clear() { ++epoch; turns.clear(); }
    public synchronized boolean isCurrent(long expected) { return epoch == expected; }

    public synchronized long addSource(long expected, Language language, String source) {
        if (!isCurrent(expected) || source == null || source.trim().isEmpty()) return -1;
        Turn turn = new Turn(++nextId, language, source.trim(), null, false);
        turns.add(turn);
        if (turns.size() > MAX_TURNS) turns.remove(0);
        return turn.id;
    }
    public synchronized boolean finish(long expected, long id, String translation, boolean failed) {
        if (!isCurrent(expected)) return false;
        for (int i = 0; i < turns.size(); i++) {
            Turn old = turns.get(i);
            if (old.id == id) {
                turns.set(i, new Turn(id, old.sourceLanguage, old.source, translation, failed));
                return true;
            }
        }
        return false;
    }
    public synchronized List<Turn> snapshot() { return new ArrayList<>(turns); }

    public static final class Turn {
        public final long id;
        public final Language sourceLanguage;
        public final String source;
        public final String translation;
        public final boolean translationFailed;
        private Turn(long id, Language sourceLanguage, String source, String translation, boolean failed) {
            this.id = id;
            this.sourceLanguage = sourceLanguage;
            this.source = source;
            this.translation = translation;
            this.translationFailed = failed;
        }
        public String textFor(Language language) {
            return language == sourceLanguage ? source : translation;
        }
    }
}
