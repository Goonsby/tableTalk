import org.tabletalk.core.AudioSamples;
import org.tabletalk.core.ConversationLedger;
import org.tabletalk.core.Language;

public final class CoreTests {
    private static int checked;
    private static void check(boolean condition, String name) {
        if (!condition) throw new AssertionError(name);
        checked++;
    }
    public static void main(String[] args) throws Exception {
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
        byte[] model = "verified model fixture".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        byte[] hash = java.security.MessageDigest.getInstance("SHA-1").digest(model);
        StringBuilder hex = new StringBuilder();
        for (byte b : hash) hex.append(String.format("%02x", b & 255));
        java.util.Map<String, String> hashes = java.util.Map.of(hex.toString(), "fixture");
        java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream();
        String name = org.tabletalk.core.VerifiedModelCopy.copy(new java.io.ByteArrayInputStream(model),
                output, model.length, hashes, () -> false, n -> { });
        check(name.equals("fixture") && java.util.Arrays.equals(model, output.toByteArray()), "valid model streams and verifies");
        for (int mode = 0; mode < 4; mode++) {
            final int scenario = mode;
            try {
                byte[] data = scenario == 1 ? java.util.Arrays.copyOf(model, model.length - 1) : model;
                org.tabletalk.core.VerifiedModelCopy.copy(new java.io.ByteArrayInputStream(data),
                        new java.io.ByteArrayOutputStream(), scenario == 0 ? model.length - 1 : model.length,
                        scenario == 3 ? java.util.Map.of() : hashes, () -> scenario == 2, n -> { });
                throw new AssertionError("invalid transfer accepted: " + scenario);
            } catch (java.io.IOException | java.util.concurrent.CancellationException expected) {
                check(true, "reject oversized, truncated, cancelled, and corrupt transfers");
            }
        }
        java.util.concurrent.atomic.AtomicBoolean cancel = new java.util.concurrent.atomic.AtomicBoolean();
        try {
            org.tabletalk.core.VerifiedModelCopy.copy(new java.io.ByteArrayInputStream(model),
                    new java.io.ByteArrayOutputStream(), model.length, hashes, cancel::get, n -> cancel.set(true));
            throw new AssertionError("cancellation during copy accepted");
        } catch (java.util.concurrent.CancellationException expected) {
            check(true, "cancellation after final chunk rejects commit");
        }
        try {
            org.tabletalk.core.VerifiedModelCopy.copy(new java.io.ByteArrayInputStream(model),
                    new java.io.OutputStream() {
                        @Override public void write(int b) throws java.io.IOException {
                            throw new java.io.IOException("Disk full");
                        }
                    }, model.length, hashes, () -> false, n -> { });
            throw new AssertionError("write failure accepted");
        } catch (java.io.IOException expected) {
            check(true, "storage failures propagate before commit");
        }
        Thread.currentThread().interrupt();
        try {
            org.tabletalk.core.VerifiedModelCopy.copy(new java.io.ByteArrayInputStream(model),
                    new java.io.ByteArrayOutputStream(), model.length, hashes, () -> false, n -> { });
            throw new AssertionError("interrupted transfer accepted");
        } catch (java.util.concurrent.CancellationException expected) {
            check(true, "thread interruption rejects transfer");
        } finally { Thread.interrupted(); }
        byte[] large = new byte[150_000];
        new java.util.Random(42).nextBytes(large);
        hash = java.security.MessageDigest.getInstance("SHA-1").digest(large);
        hex = new StringBuilder();
        for (byte b : hash) hex.append(String.format("%02x", b & 255));
        final long[] progress = {0};
        output.reset();
        org.tabletalk.core.VerifiedModelCopy.copy(new java.io.ByteArrayInputStream(large), output, large.length,
                java.util.Map.of(hex.toString(), "large"), () -> false, n -> {
                    check(n > progress[0], "stream progress increases");
                    progress[0] = n;
                });
        check(progress[0] == large.length && java.util.Arrays.equals(large, output.toByteArray()),
                "multi-buffer copy preserves every byte");
        System.out.println("Passed " + checked + " core behavior checks.");
    }
}
