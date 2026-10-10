package org.tabletalk.models;

import android.content.Context;
import android.net.Uri;
import android.net.Network;
import android.util.AtomicFile;
import org.tabletalk.BuildConfig;
import org.tabletalk.core.VerifiedModelCopy;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.util.HashMap;
import java.util.Map;
import java.util.function.BooleanSupplier;
import java.util.function.LongConsumer;
import javax.net.ssl.HttpsURLConnection;

/** Serial worker only. Failed or interrupted transfers preserve the last verified model. */
public final class ModelStore {
    private static final long MAX_BYTES = 170L * 1024 * 1024;
    private static final String TINY_SHA1 = "bd577a113a864445d4c299885e0cb97d4ba92b5f";
    private static final String BASE_SHA1 = "465707469ff3a37a2b9b8d8f89f2f99de7299dac";
    private static final String TINY_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin";
    private final Context context;
    private final AtomicFile model;

    public ModelStore(Context context) {
        this.context = context.getApplicationContext();
        model = new AtomicFile(new File(context.getNoBackupFilesDir(), "whisper.bin"));
    }
    public File file() { return model.getBaseFile(); }
    public boolean exists() {
        try (InputStream input = model.openRead()) {
            return file().length() > 0;
        } catch (IOException missing) { return false; }
    }
    public String importModel(Uri uri, BooleanSupplier cancelled) throws IOException {
        try (InputStream input = context.getContentResolver().openInputStream(uri)) {
            if (input == null) throw new IOException("Could not open the selected file");
            Map<String, String> hashes = new HashMap<>();
            hashes.put(TINY_SHA1, "tiny");
            hashes.put(BASE_SHA1, "base");
            return save(input, hashes, cancelled, bytes -> { });
        }
    }
    public void downloadTiny(Network network, BooleanSupplier cancelled, LongConsumer progress) throws IOException {
        if (!BuildConfig.ALLOW_MODEL_DOWNLOAD) throw new IOException("This build cannot download models");
        // Allow room for the staged download alongside any existing model.
        if (context.getNoBackupFilesDir().getUsableSpace() < 100L * 1024 * 1024) {
            throw new IOException("Free at least 100 MiB of storage for the speech model");
        }
        URL url = new URL(TINY_URL);
        // Hugging Face redirects to its CDN. Explicitly reject HTTPS downgrades and loops.
        for (int redirects = 0; redirects <= 5; redirects++) {
            if (!"https".equalsIgnoreCase(url.getProtocol())) throw new IOException("An insecure model URL was rejected");
            HttpsURLConnection connection = (HttpsURLConnection) network.openConnection(url);
            connection.setConnectTimeout(20_000);
            connection.setReadTimeout(30_000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("Accept-Encoding", "identity");
            try {
                if (cancelled.getAsBoolean()) throw new java.util.concurrent.CancellationException();
                int status = connection.getResponseCode();
                if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
                    String location = connection.getHeaderField("Location");
                    if (location == null) throw new IOException("Missing model download redirect");
                    url = new URL(url, location);
                    continue;
                }
                if (status != 200) throw new IOException("Speech download returned HTTP " + status);
                Map<String, String> hashes = new HashMap<>();
                hashes.put(TINY_SHA1, "tiny");
                try (InputStream input = connection.getInputStream()) {
                    save(input, hashes, cancelled, progress);
                }
                return;
            } finally { connection.disconnect(); }
        }
        throw new IOException("Too many model download redirects");
    }
    private String save(InputStream input, Map<String, String> hashes,
            BooleanSupplier cancelled, LongConsumer progress) throws IOException {
        FileOutputStream output = model.startWrite();
        try {
            String name = VerifiedModelCopy.copy(input, output, MAX_BYTES, hashes, cancelled, progress);
            model.finishWrite(output);
            output = null;
            return name;
        } finally {
            if (output != null) model.failWrite(output);
        }
    }
}
