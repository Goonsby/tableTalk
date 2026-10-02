package org.tabletalk.inference;

import com.google.android.gms.tasks.Tasks;
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
    public void prepareForSetup() throws Exception {
        if (!BuildConfig.ALLOW_MODEL_DOWNLOAD) throw new IllegalStateException("Use the setup build to download models");
        DownloadConditions conditions = new DownloadConditions.Builder().requireWifi().build();
        Tasks.await(client(Language.ENGLISH).downloadModelIfNeeded(conditions), 3, TimeUnit.MINUTES);
        Tasks.await(client(Language.SPANISH).downloadModelIfNeeded(conditions), 3, TimeUnit.MINUTES);
        probeBothDirections();
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
