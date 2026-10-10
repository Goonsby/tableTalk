package org.tabletalk.inference;

import com.google.android.gms.tasks.Tasks;
import com.google.android.gms.tasks.Task;
import java.util.concurrent.CancellationException;
import java.util.concurrent.TimeoutException;
import java.util.function.BooleanSupplier;
import com.google.mlkit.common.model.DownloadConditions;
import com.google.mlkit.common.model.RemoteModelManager;
import com.google.mlkit.nl.translate.TranslateLanguage;
import com.google.mlkit.nl.translate.TranslateRemoteModel;
import com.google.mlkit.nl.translate.Translation;
import com.google.mlkit.nl.translate.Translator;
import com.google.mlkit.nl.translate.TranslatorOptions;
import org.tabletalk.BuildConfig;
import org.tabletalk.core.Language;
import java.util.concurrent.TimeUnit;

/** Local text translation. Downloads are confined to the explicit setup action. */
public final class TranslationEngine implements AutoCloseable {
    private Translator englishToSpanish;
    private Translator spanishToEnglish;

    private Translator client(Language source) {
        if (source == Language.ENGLISH) {
            if (englishToSpanish == null) englishToSpanish = make("en", "es");
            return englishToSpanish;
        }
        if (spanishToEnglish == null) spanishToEnglish = make("es", "en");
        return spanishToEnglish;
    }
    private Translator make(String source, String target) {
        return Translation.getClient(new TranslatorOptions.Builder()
                .setSourceLanguage(source).setTargetLanguage(target).build());
    }
    public boolean modelsDownloaded() throws Exception {
        TranslateRemoteModel spanish = new TranslateRemoteModel.Builder(TranslateLanguage.SPANISH).build();
        return Tasks.await(RemoteModelManager.getInstance().isModelDownloaded(spanish), 30, TimeUnit.SECONDS);
    }
    public void prepareForSetup(boolean wifiOnly, BooleanSupplier cancelled) throws Exception {
        if (!BuildConfig.ALLOW_MODEL_DOWNLOAD) throw new IllegalStateException("Use the setup build to download models");
        DownloadConditions.Builder builder = new DownloadConditions.Builder();
        if (wifiOnly) builder.requireWifi();
        DownloadConditions conditions = builder.build();
        awaitDownload(client(Language.ENGLISH).downloadModelIfNeeded(conditions), cancelled);
        if (cancelled.getAsBoolean()) throw new CancellationException();
        awaitDownload(client(Language.SPANISH).downloadModelIfNeeded(conditions), cancelled);
        probeBothDirections();
    }
    private void awaitDownload(Task<Void> task, BooleanSupplier cancelled) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(5);
        while (true) {
            if (cancelled.getAsBoolean()) throw new CancellationException();
            try {
                Tasks.await(task, 1, TimeUnit.SECONDS);
                return;
            } catch (TimeoutException waiting) {
                if (System.nanoTime() >= deadline) throw waiting;
            }
        }
    }
    public void probeBothDirections() throws Exception {
        // No downloadModelIfNeeded here: failure leaves conversation unavailable.
        if (!modelsDownloaded()) throw new IllegalStateException("Spanish translation model is missing");
        if (translate("Hello", Language.ENGLISH).trim().isEmpty()
                || translate("Hola", Language.SPANISH).trim().isEmpty()) {
            throw new IllegalStateException("Offline translation check failed");
        }
    }
    public String translate(String text, Language source) throws Exception {
        return Tasks.await(client(source).translate(text), 60, TimeUnit.SECONDS);
    }
    @Override public void close() {
        if (englishToSpanish != null) englishToSpanish.close();
        if (spanishToEnglish != null) spanishToEnglish.close();
        englishToSpanish = null;
        spanishToEnglish = null;
    }
}
