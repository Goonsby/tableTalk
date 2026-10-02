package org.tabletalk.models;

import android.content.Context;
import android.net.Uri;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;

/** Imports only official multilingual tiny/base files, preserving a previous good import. */
public final class ModelStore {
    private static final long MAX_BYTES = 170L * 1024 * 1024;
    private static final String TINY_SHA1 = "bd577a113a864445d4c299885e0cb97d4ba92b5f";
    private static final String BASE_SHA1 = "465707469ff3a37a2b9b8d8f89f2f99de7299dac";
    private final Context context;
    private final AtomicFile model;

    public ModelStore(Context context) {
        this.context = context.getApplicationContext();
        model = new AtomicFile(new File(context.getNoBackupFilesDir(), "whisper.bin"));
    }
    public File file() { return model.getBaseFile(); }
    public boolean exists() {
        // openRead also recovers an AtomicFile backup after an interrupted import.
        try (InputStream input = model.openRead()) {
            return file().length() > 0;
        } catch (IOException missing) { return false; }
    }

    public String importModel(Uri uri) throws IOException {
        FileOutputStream output = null;
        byte[] buffer = new byte[64 * 1024];
        try (InputStream input = context.getContentResolver().openInputStream(uri)) {
            if (input == null) throw new IOException("Could not open the selected file");
            MessageDigest digest = MessageDigest.getInstance("SHA-1");
            output = model.startWrite();
            long size = 0;
            int read;
            while ((read = input.read(buffer)) != -1) {
                size += read;
                if (size > MAX_BYTES) throw new IOException("Choose the official tiny or base multilingual model");
                output.write(buffer, 0, read);
                digest.update(buffer, 0, read);
            }
            StringBuilder hex = new StringBuilder();
            for (byte b : digest.digest()) hex.append(String.format(java.util.Locale.ROOT, "%02x", b & 255));
            String hash = hex.toString();
            String name;
            if (TINY_SHA1.equals(hash)) name = "tiny";
            else if (BASE_SHA1.equals(hash)) name = "base";
            else throw new IOException("File did not match the official multilingual tiny/base checksum");
            model.finishWrite(output);
            output = null;
            return name;
        } catch (NoSuchAlgorithmException impossible) {
            throw new IOException("Checksum verification is unavailable", impossible);
        } finally {
            Arrays.fill(buffer, (byte) 0);
            if (output != null) model.failWrite(output);
        }
    }
}
