package org.tabletalk.audio;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import org.tabletalk.core.AudioSamples;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.IntConsumer;

/** One foreground capture at a time. stop() also unblocks a pending read. */
public final class PcmRecorder {
    private final AtomicBoolean stopped = new AtomicBoolean();
    private AudioRecord active;

    public AudioSamples capture(IntConsumer onSeconds) {
        AudioSamples samples = new AudioSamples();
        short[] frame = new short[1024];
        AudioRecord record = null;
        try {
            int minimum = AudioRecord.getMinBufferSize(AudioSamples.SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
            if (minimum <= 0) throw new IllegalStateException("16 kHz recording is unavailable");
            record = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    AudioSamples.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, Math.max(minimum, frame.length * 4));
            if (record.getState() != AudioRecord.STATE_INITIALIZED) {
                throw new IllegalStateException("The microphone is unavailable");
            }
            synchronized (this) {
                if (stopped.get()) return samples;
                active = record;
                record.startRecording();
                if (record.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING) {
                    throw new IllegalStateException("The microphone did not start");
                }
            }
            int lastSecond = -1;
            while (!stopped.get() && !samples.full()) {
                int read = record.read(frame, 0, frame.length, AudioRecord.READ_BLOCKING);
                if (stopped.get()) break;
                if (read < 0) throw new IllegalStateException("The microphone stopped unexpectedly");
                if (read == 0) continue;
                samples.append(frame, read);
                Arrays.fill(frame, (short) 0);
                int second = (int) samples.seconds();
                if (second != lastSecond) { lastSecond = second; onSeconds.accept(second); }
            }
            return samples;
        } catch (RuntimeException failure) {
            samples.close();
            throw failure;
        } finally {
            Arrays.fill(frame, (short) 0);
            synchronized (this) {
                active = null;
                if (record != null) {
                    try { record.stop(); } catch (IllegalStateException ignored) { }
                    record.release();
                }
            }
        }
    }

    public synchronized void stop() {
        stopped.set(true);
        if (active != null) {
            try { active.stop(); } catch (IllegalStateException ignored) { }
        }
    }
}
