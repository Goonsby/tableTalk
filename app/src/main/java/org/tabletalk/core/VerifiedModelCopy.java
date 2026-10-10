package org.tabletalk.core;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.Map;
import java.util.concurrent.CancellationException;
import java.util.function.BooleanSupplier;
import java.util.function.LongConsumer;

/** Bounded streaming verification shared by imports and HTTPS downloads. */
public final class VerifiedModelCopy {
    private VerifiedModelCopy() { }

    public static String copy(InputStream input, OutputStream output, long limit,
            Map<String, String> acceptedHashes, BooleanSupplier cancelled, LongConsumer progress)
            throws IOException {
        byte[] buffer = new byte[64 * 1024];
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-1");
            long size = 0;
            while (true) {
                if (cancelled.getAsBoolean() || Thread.currentThread().isInterrupted()) {
                    throw new CancellationException("Model transfer cancelled");
                }
                int read = input.read(buffer);
                if (read == -1) break;
                size += read;
                if (size > limit) throw new IOException("Speech model is too large");
                output.write(buffer, 0, read);
                digest.update(buffer, 0, read);
                progress.accept(size);
            }
            StringBuilder hex = new StringBuilder();
            for (byte b : digest.digest()) hex.append(String.format(java.util.Locale.ROOT, "%02x", b & 255));
            String name = acceptedHashes.get(hex.toString());
            if (name == null) throw new IOException("Speech model checksum did not match; please retry");
            if (cancelled.getAsBoolean() || Thread.currentThread().isInterrupted()) {
                throw new CancellationException("Model transfer cancelled");
            }
            return name;
        } catch (NoSuchAlgorithmException impossible) {
            throw new IOException("Checksum verification is unavailable", impossible);
        } finally { Arrays.fill(buffer, (byte) 0); }
    }
}
