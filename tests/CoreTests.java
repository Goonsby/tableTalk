import org.tabletalk.core.AudioSamples;
import org.tabletalk.core.ConversationLedger;
import org.tabletalk.core.Language;

public final class CoreTests {
    private static int checked;
    private static void check(boolean condition, String name) {
        if (!condition) throw new AssertionError(name);
        checked++;
    }
    public static void main(String[] args) {
        ConversationLedger ledger = new ConversationLedger();
        long epoch = ledger.epoch();
        long id = ledger.addSource(epoch, Language.SPANISH, "Estoy preocupado por mi familia.");
        check(ledger.snapshot().get(0).textFor(Language.ENGLISH) == null, "translation stays pending until completed");
        check(ledger.finish(epoch, id, "I am worried about my family.", false), "translation completes");
        check(ledger.snapshot().get(0).textFor(Language.SPANISH).startsWith("Estoy"), "Spanish panel keeps Spanish source");
        check(ledger.snapshot().get(0).textFor(Language.ENGLISH).startsWith("I am"), "English panel receives English translation");
        ledger.clear();
        check(!ledger.finish(epoch, id, "stale sensitive response", false), "clear rejects in-flight translation");
        check(ledger.addSource(epoch, Language.ENGLISH, "stale recognition") == -1, "clear rejects in-flight recognition");
        check(ledger.snapshot().isEmpty(), "cleared conversation remains empty");
        epoch = ledger.epoch();
        id = ledger.addSource(epoch, Language.ENGLISH, "How are you feeling?");
        ledger.finish(epoch, id, "¿Cómo se siente?", false);
        check(ledger.snapshot().get(0).textFor(Language.SPANISH).equals("¿Cómo se siente?"), "reverse direction reaches Spanish panel");
        long failed = ledger.addSource(epoch, Language.SPANISH, "Original survives failure");
        ledger.finish(epoch, failed, null, true);
        check(ledger.snapshot().get(1).source.equals("Original survives failure")
                && ledger.snapshot().get(1).translationFailed, "failed translation preserves the original");
        for (int i = 0; i < 50; i++) ledger.addSource(epoch, Language.ENGLISH, "turn " + i);
        check(ledger.snapshot().size() == ConversationLedger.MAX_TURNS, "history is bounded");
        check(ledger.snapshot().get(0).source.equals("turn 38"), "oldest turns are discarded");
        check(ledger.addSource(epoch, Language.SPANISH, "   ") == -1, "empty recognition is ignored");

        try (AudioSamples samples = new AudioSamples()) {
            short[] silence = new short[8000];
            samples.append(silence, silence.length);
            check(!samples.worthDecoding(), "silence does not enter Whisper");
            samples.close();
            check(samples.size() == 0 && samples.rms() == 0, "closing resets sample state");
            short[] voice = new short[8000];
            java.util.Arrays.fill(voice, Short.MIN_VALUE);
            samples.append(voice, voice.length);
            float[] copy = samples.copy();
            check(copy[0] == -1f, "negative PCM normalizes without overflow");
            check(samples.worthDecoding(), "sufficient audible input enters decoding");
            samples.close();
            check(samples.copy().length == 0, "closed buffer exposes no old audio");
            short[] longInput = new short[AudioSamples.SAMPLE_RATE * 15];
            samples.append(longInput, longInput.length);
            check(samples.full() && samples.seconds() == 12, "capture is capped at twelve seconds");
        }
        System.out.println("Passed " + checked + " core behavior checks.");
    }
}
