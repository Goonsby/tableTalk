package org.tabletalk.core;

import java.util.Arrays;

/** PCM stays in RAM; fixed duration prevents an unbounded recording. */
public final class AudioSamples implements AutoCloseable {
    public static final int SAMPLE_RATE = 16000;
    public static final int MAX_SECONDS = 12;
    private final float[] storage = new float[SAMPLE_RATE * MAX_SECONDS];
    private int size;
    private double sumSquares;

    public void append(short[] pcm, int count) {
        if (count < 0 || count > pcm.length) throw new IllegalArgumentException("Invalid sample count");
        int accepted = Math.min(count, storage.length - size);
        for (int i = 0; i < accepted; i++) {
            float value = pcm[i] / 32768.0f;
            storage[size++] = value;
            sumSquares += value * value;
        }
    }
    public boolean full() { return size == storage.length; }
    public int size() { return size; }
    public double seconds() { return size / (double) SAMPLE_RATE; }
    public double rms() { return size == 0 ? 0 : Math.sqrt(sumSquares / size); }
    // A conservative silence/very-short-input gate, NOT speech detection or confidence.
    public boolean worthDecoding() { return size >= SAMPLE_RATE / 2 && rms() >= 0.002; }
    public float[] copy() { return Arrays.copyOf(storage, size); }
    @Override public void close() { Arrays.fill(storage, 0); size = 0; sumSquares = 0; }
}
