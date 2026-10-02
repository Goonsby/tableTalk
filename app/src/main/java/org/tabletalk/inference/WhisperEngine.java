package org.tabletalk.inference;

import org.tabletalk.core.Language;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CancellationException;
import java.util.function.BooleanSupplier;

/** open/transcribe/close run on one executor; cancellation can run on the UI thread. */
public final class WhisperEngine implements AutoCloseable {
    static { System.loadLibrary("tabletalk-whisper"); }
    private long handle;

    public void open(File file) {
        close();
        long created = nativeCreate(file.getAbsolutePath());
        if (created == 0) throw new IllegalStateException("The speech model could not be loaded");
        synchronized (this) { handle = created; }
    }
    public synchronized boolean isOpen() { return handle != 0; }
    public String transcribe(float[] samples, Language language, BooleanSupplier isCurrent) {
        long session;
        synchronized (this) {
            session = handle;
            if (session == 0) throw new IllegalStateException("Speech model is not loaded");
            nativeResetCancellation(session);
        }
        // Reset BEFORE the epoch check so an earlier cancellation cannot be lost.
        if (!isCurrent.getAsBoolean()) throw new CancellationException();
        byte[] utf8 = nativeTranscribe(session, samples, language.code,
                Math.max(1, Math.min(4, Runtime.getRuntime().availableProcessors())));
        if (!isCurrent.getAsBoolean()) throw new CancellationException();
        return new String(utf8, StandardCharsets.UTF_8).trim();
    }
    public synchronized void cancel() { if (handle != 0) nativeCancel(handle); }
    @Override public synchronized void close() {
        if (handle != 0) { nativeRelease(handle); handle = 0; }
    }
    private static native long nativeCreate(String path);
    private static native void nativeRelease(long session);
    private static native void nativeCancel(long session);
    private static native void nativeResetCancellation(long session);
    private static native byte[] nativeTranscribe(long session, float[] pcm, String language, int threads);
}
