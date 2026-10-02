package org.tabletalk;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import org.tabletalk.audio.PcmRecorder;
import org.tabletalk.core.AudioSamples;
import org.tabletalk.core.ConversationLedger;
import org.tabletalk.core.Language;
import org.tabletalk.inference.TranslationEngine;
import org.tabletalk.inference.WhisperEngine;
import org.tabletalk.models.ModelStore;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final int IMPORT_MODEL = 10;
    private static final int MICROPHONE_PERMISSION = 11;
    private static final int INK = Color.rgb(29, 46, 43);
    private static final int MUTED = Color.rgb(80, 98, 93);
    private static final int GREEN = Color.rgb(36, 103, 95);
    private static final int PAPER = Color.rgb(248, 246, 240);
    private final ConversationLedger ledger = new ConversationLedger();
    private final ExecutorService captureWorker = Executors.newSingleThreadExecutor();
    private final ExecutorService inferenceWorker = Executors.newSingleThreadExecutor();
    private WhisperEngine whisper;
    private TranslationEngine translator;
    private ModelStore models;
    private LinearLayout root;
    private TextView setupStatus;
    private TextView centerStatus;
    private Panel spanishPanel;
    private Panel englishPanel;
    private volatile PcmRecorder recorder;
    private volatile boolean destroyed;
    private boolean foreground;
    private boolean ready;
    private boolean setupBusy;
    private boolean demo;
    private int demoStep;
    private Language speaking;
    private Language permissionLanguage;
    private Phase phase = Phase.READY;
    private String englishStatus = "Prepare the offline models";
    private String spanishStatus = "Prepare los modelos sin conexión";
    private enum Phase { READY, RECORDING, PROCESSING }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        whisper = new WhisperEngine();
        translator = new TranslationEngine();
        models = new ModelStore(this);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(PAPER);
        root.setSaveEnabled(false);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                    insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        setContentView(root);
        showSetup();
        checkReadiness();
    }
    @Override public void onResume() {
        super.onResume();
        foreground = true;
        if (centerStatus != null) {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            setStatus(demo ? "Sample layout · microphone off" : "Tap your side to speak",
                    demo ? "Ejemplo · micrófono apagado" : "Toque su lado para hablar");
        }
    }
    @Override public void onPause() {
        foreground = false;
        cancelAndClear();
        permissionLanguage = null;
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        super.onPause();
    }
    @Override public void onDestroy() {
        destroyed = true;
        cancelAndClear();
        captureWorker.shutdown();
        // Do not free a native context while a cancelled inference is still unwinding.
        inferenceWorker.execute(() -> { whisper.close(); translator.close(); });
        inferenceWorker.shutdown();
        super.onDestroy();
    }

    private void showSetup() {
        cancelAndClear();
        demo = false;
        centerStatus = null;
        spanishPanel = null;
        englishPanel = null;
        root.removeAllViews();
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        ScrollView scroll = new ScrollView(this);
        LinearLayout content = column();
        content.setPadding(dp(24), dp(24), dp(24), dp(24));
        scroll.addView(content);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, -1));
        content.addView(text("TableTalk", 18, GREEN));
        content.addView(text("A conversation,\nacross languages.", 32, INK));
        content.addView(text("English ↔ Español\nSet up once before the visit. Translate on the phone.", 18, MUTED));
        space(content, 20);
        setupStatus = text(ready ? "Models ready. Test both speaking directions in airplane mode."
                : "Prepare the offline models before starting.", 16, GREEN);
        content.addView(setupStatus);
        content.addView(button("1. Import speech model (.bin)", () -> {
            if (setupBusy) return;
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            startActivityForResult(intent, IMPORT_MODEL);
        }));
        content.addView(text("Use ggml-tiny.bin (75 MiB) for an LG G6 or G7. The project guide links the model file.", 15, MUTED));
        if (BuildConfig.ALLOW_MODEL_DOWNLOAD) {
            content.addView(button("2. Download Spanish over Wi-Fi", this::downloadTranslation));
        } else {
            content.addView(text("This visit build has no internet permission. Translation models must already be installed by the setup build.", 16, MUTED));
        }
        content.addView(button("Check offline readiness", this::checkReadiness));
        content.addView(button("Start conversation", () -> {
            if (ready && !setupBusy) showConversation(false);
            else setupStatus.setText("Finish model setup and the readiness check first.");
        }));
        content.addView(button("Try the sample layout", () -> { if (!setupBusy) showConversation(true); }));
        space(content, 12);
        content.addView(text("Conversations stay in memory and clear when you leave the app. Translation can make mistakes; ask for clarification.", 15, MUTED));
    }

    private void checkReadiness() {
        if (setupBusy || destroyed) return;
        setupBusy = true;
        setupStatus.setText("Checking both translation directions…");
        inferenceWorker.execute(() -> {
            try {
                if (!models.exists()) throw new IllegalStateException();
                if (!whisper.isOpen()) whisper.open(models.file());
                translator.probeBothDirections();
                onUi(() -> {
                    ready = true;
                    setupBusy = false;
                    setupStatus.setText("Models ready. Before a visit, test both speaking directions in airplane mode.");
                });
            } catch (Exception failure) {
                onUi(() -> {
                    ready = false;
                    setupBusy = false;
                    setupStatus.setText(models.exists()
                            ? "Translation or speech check failed. Prepare Spanish over Wi-Fi in the setup build, then retry."
                            : "Import the speech model, then prepare Spanish translation.");
                });
            }
        });
    }
    private void downloadTranslation() {
        if (setupBusy) return;
        setupBusy = true;
        ready = false;
        setupStatus.setText("Downloading Spanish. Keep Wi-Fi connected; this can take a few minutes.");
        inferenceWorker.execute(() -> {
            try {
                translator.prepareForSetup();
                onUi(() -> {
                    setupBusy = false;
                    setupStatus.setText("Spanish is prepared. Checking speech next…");
                    checkReadiness();
                });
            } catch (Exception failure) {
                onUi(() -> {
                    setupBusy = false;
                    setupStatus.setText("Download or translation check failed. Check Wi-Fi and free storage, then retry.");
                });
            }
        });
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != IMPORT_MODEL || result != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        setupBusy = true;
        ready = false;
        setupStatus.setText("Importing and checking the speech model…");
        inferenceWorker.execute(() -> {
            try {
                whisper.close();
                String name = models.importModel(uri);
                whisper.open(models.file());
                onUi(() -> {
                    setupBusy = false;
                    setupStatus.setText("Imported multilingual " + name + ". Checking translation…");
                    checkReadiness();
                });
            } catch (Exception failure) {
                onUi(() -> {
                    setupBusy = false;
                    setupStatus.setText("Import failed. Choose the original ggml-tiny.bin or ggml-base.bin from the guide. English-only and quantized files are not accepted yet.");
                });
            }
        });
    }

    private void showConversation(boolean sample) {
        cancelAndClear();
        demo = sample;
        root.removeAllViews();
        spanishPanel = new Panel(Language.SPANISH);
        // Rotates the WHOLE panel, including buttons and scroll gestures.
        spanishPanel.container.setRotation(180);
        root.addView(spanishPanel.container, new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout divider = column();
        divider.setPadding(dp(12), dp(5), dp(12), dp(5));
        divider.setBackgroundColor(Color.rgb(229, 236, 228));
        centerStatus = text("", 12, INK);
        centerStatus.setGravity(Gravity.CENTER);
        divider.addView(centerStatus);
        LinearLayout actions = new LinearLayout(this);
        actions.setGravity(Gravity.CENTER);
        Button clear = button("Clear / Borrar", () -> {
            cancelAndClear();
            setStatus(demo ? "Sample layout · microphone off" : "Conversation cleared",
                    demo ? "Ejemplo · micrófono apagado" : "Conversación borrada");
        });
        Button setup = button("Setup", this::showSetup);
        actions.addView(clear, new LinearLayout.LayoutParams(0, dp(48), 1));
        actions.addView(setup, new LinearLayout.LayoutParams(0, dp(48), 1));
        divider.addView(actions);
        root.addView(divider);
        englishPanel = new Panel(Language.ENGLISH);
        root.addView(englishPanel.container, new LinearLayout.LayoutParams(-1, 0, 1));
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (demo) addDemo(Language.ENGLISH);
        setStatus(demo ? "Sample layout · microphone off" : "Tap your side to speak",
                demo ? "Ejemplo · micrófono apagado" : "Toque su lado para hablar");
        render();
    }
    private void speak(Language language) {
        if (!foreground) return;
        if (demo) { addDemo(language); return; }
        if (phase == Phase.RECORDING && speaking == language) {
            phase = Phase.PROCESSING;
            PcmRecorder current = recorder;
            if (current != null) current.stop();
            setStatus("Processing…", "Procesando…");
            return;
        }
        if (!ready || phase != Phase.READY || setupBusy) return;
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            permissionLanguage = language;
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, MICROPHONE_PERMISSION);
            return;
        }
        startCapture(language);
    }
    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        if (request != MICROPHONE_PERMISSION) return;
        permissionLanguage = null;
        if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
            // Tap again: the permission dialog may have paused the activity.
            setStatus("Microphone allowed. Tap your side to speak.", "Micrófono permitido. Toque su lado para hablar.");
        } else {
            setStatus("Allow microphone access in Android settings.", "Permita el micrófono en ajustes de Android.");
        }
    }
    private void startCapture(Language language) {
        final long epoch = ledger.epoch();
        final PcmRecorder capture = new PcmRecorder();
        recorder = capture;
        speaking = language;
        phase = Phase.RECORDING;
        setStatus("Listening · tap again to finish", "Escuchando · toque otra vez para terminar");
        captureWorker.execute(() -> {
            try (AudioSamples samples = capture.capture(seconds -> onUi(() -> {
                if (ledger.isCurrent(epoch) && phase == Phase.RECORDING) {
                    setStatus("Listening · " + (AudioSamples.MAX_SECONDS - seconds) + "s left",
                            "Escuchando · quedan " + (AudioSamples.MAX_SECONDS - seconds) + "s");
                }
            }))) {
                if (!ledger.isCurrent(epoch)) return;
                if (!samples.worthDecoding()) {
                    finishStatus(epoch, "No clear speech. Please try again.", "No se oyó claramente. Intente de nuevo.");
                    return;
                }
                float[] pcm = samples.copy();
                onUi(() -> {
                    if (ledger.isCurrent(epoch)) {
                        phase = Phase.PROCESSING;
                        setStatus("Transcribing on this phone…", "Transcribiendo en este teléfono…");
                    }
                });
                try {
                    inferenceWorker.execute(() -> processTurn(epoch, language, pcm));
                } catch (RuntimeException unavailable) {
                    Arrays.fill(pcm, 0);
                    throw unavailable;
                }
            } catch (Exception failure) {
                finishStatus(epoch, "Microphone unavailable. Please try again.", "Micrófono no disponible. Intente de nuevo.");
            } finally {
                if (recorder == capture) recorder = null;
            }
        });
    }
    private void processTurn(long epoch, Language language, float[] pcm) {
        long turnId = -1;
        long started = System.nanoTime();
        try {
            if (!ledger.isCurrent(epoch)) return;
            String original = whisper.transcribe(pcm, language, () -> ledger.isCurrent(epoch));
            Arrays.fill(pcm, 0);
            if (original.isEmpty()) {
                finishStatus(epoch, "Please repeat a short sentence.", "Repita una frase corta, por favor.");
                return;
            }
            turnId = ledger.addSource(epoch, language, original);
            if (turnId == -1) return;
            onUi(() -> {
                if (ledger.isCurrent(epoch)) {
                    setStatus("Translating on this phone…", "Traduciendo en este teléfono…");
                    render();
                }
            });
            String translated = translator.translate(original, language);
            if (translated.trim().isEmpty()) throw new IllegalStateException();
            ledger.finish(epoch, turnId, translated, false);
            double elapsed = (System.nanoTime() - started) / 1_000_000_000.0;
            finishStatus(epoch, String.format(Locale.ROOT, "Ready · processed in %.1fs", elapsed),
                    String.format(Locale.ROOT, "Listo · procesado en %.1fs", elapsed));
        } catch (CancellationException cancelled) {
            // Clear/background already invalidated this turn; never restore it.
        } catch (Exception failure) {
            if (turnId != -1) ledger.finish(epoch, turnId, null, true);
            finishStatus(epoch, "Could not translate. Please repeat or recheck models.",
                    "No se pudo traducir. Repita o revise los modelos.");
        } finally { Arrays.fill(pcm, 0); }
    }
    private void finishStatus(long epoch, String english, String spanish) {
        onUi(() -> {
            if (!ledger.isCurrent(epoch)) return;
            speaking = null;
            phase = Phase.READY;
            setStatus(english, spanish);
            render();
        });
    }
    private void cancelAndClear() {
        ledger.clear();
        PcmRecorder current = recorder;
        if (current != null) current.stop();
        if (whisper != null) whisper.cancel();
        speaking = null;
        phase = Phase.READY;
        if (spanishPanel != null) render();
    }
    private void setStatus(String english, String spanish) {
        englishStatus = english;
        spanishStatus = spanish;
        if (centerStatus != null) centerStatus.setText((demo ? "SAMPLE / EJEMPLO · " : "")
                + (BuildConfig.ALLOW_MODEL_DOWNLOAD ? "Setup build" : "No internet permission"));
        if (englishPanel != null) englishPanel.status.setText(english);
        if (spanishPanel != null) spanishPanel.status.setText(spanish);
        updateButtons();
    }
    private void updateButtons() {
        if (englishPanel == null || spanishPanel == null) return;
        for (Panel panel : new Panel[]{englishPanel, spanishPanel}) {
            boolean active = phase == Phase.RECORDING && speaking == panel.language;
            panel.talk.setEnabled(demo || phase == Phase.READY || active);
            panel.talk.setText(active ? (panel.language == Language.ENGLISH ? "Finish speaking" : "Terminar")
                    : (panel.language == Language.ENGLISH ? "Speak English" : "Hablar español"));
        }
    }
    private void render() {
        if (spanishPanel == null || englishPanel == null) return;
        List<ConversationLedger.Turn> history = ledger.snapshot();
        spanishPanel.render(history);
        englishPanel.render(history);
        updateButtons();
    }
    private void addDemo(Language language) {
        String original;
        String translated;
        if (language == Language.ENGLISH) {
            original = demoStep++ % 2 == 0 ? "How are you feeling today?" : "Would you like me to pray with you?";
            translated = original.startsWith("How") ? "¿Cómo se siente hoy?" : "¿Le gustaría que orara con usted?";
        } else {
            original = "Estoy preocupado por mi familia.";
            translated = "I am worried about my family.";
        }
        long epoch = ledger.epoch();
        long id = ledger.addSource(epoch, language, original);
        ledger.finish(epoch, id, translated, false);
        render();
    }
    private void onUi(Runnable action) {
        runOnUiThread(() -> { if (!destroyed) action.run(); });
    }
    private LinearLayout column() {
        LinearLayout view = new LinearLayout(this);
        view.setOrientation(LinearLayout.VERTICAL);
        return view;
    }
    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setPadding(0, dp(4), 0, dp(4));
        view.setSaveEnabled(false);
        return view;
    }
    private Button button(String label, Runnable action) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setTextSize(16);
        button.setMinHeight(dp(56));
        button.setTextColor(Color.WHITE);
        button.setBackgroundTintList(ColorStateList.valueOf(GREEN));
        button.setOnClickListener(view -> action.run());
        return button;
    }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private void space(LinearLayout container, int height) {
        container.addView(new View(this), new LinearLayout.LayoutParams(1, dp(height)));
    }
    private final class Panel {
        final Language language;
        final LinearLayout container = column();
        final TextView status;
        final LinearLayout captions = column();
        final ScrollView scroll = new ScrollView(MainActivity.this);
        final Button talk;
        Panel(Language language) {
            this.language = language;
            container.setPadding(dp(18), dp(10), dp(18), dp(10));
            TextView heading = text(language == Language.SPANISH ? "ESPAÑOL" : "ENGLISH", 15, GREEN);
            heading.setLetterSpacing(0.12f);
            container.addView(heading);
            status = text(language == Language.SPANISH ? spanishStatus : englishStatus, 13, MUTED);
            container.addView(status);
            scroll.addView(captions);
            container.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
            talk = button(language == Language.SPANISH ? "Hablar español" : "Speak English", () -> speak(language));
            container.addView(talk, new LinearLayout.LayoutParams(-1, dp(56)));
            container.addView(text(language == Language.SPANISH
                    ? "Puede haber errores. Pida aclaración."
                    : "Translation can make mistakes. Ask for clarification.", 11, MUTED));
        }
        void render(List<ConversationLedger.Turn> history) {
            captions.removeAllViews();
            if (history.isEmpty()) {
                captions.addView(text(language == Language.SPANISH
                        ? "Hable por turnos, con frases cortas."
                        : "Take turns speaking in short sentences.", 24, INK));
                return;
            }
            for (ConversationLedger.Turn turn : history) {
                String primary = turn.textFor(language);
                String secondary = turn.textFor(language.other());
                captions.addView(text(turn.sourceLanguage == language
                        ? (language == Language.SPANISH ? "Usted dijo" : "You said")
                        : (language == Language.SPANISH ? "Traducción" : "Translation"), 12, GREEN));
                if (primary == null) primary = turn.translationFailed
                        ? (language == Language.SPANISH ? "No se pudo traducir. Pida que repita." : "Translation unavailable. Please ask them to repeat.")
                        : (language == Language.SPANISH ? "Traduciendo…" : "Translating…");
                captions.addView(text(primary, 24, INK));
                if (secondary != null) captions.addView(text(secondary, 15, MUTED));
                space(captions, 10);
            }
            scroll.post(() -> scroll.fullScroll(View.FOCUS_DOWN));
        }
    }
}
