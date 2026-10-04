package org.tabletalk;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Color;
import android.net.Uri;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.widget.CheckBox;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewTreeObserver;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
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
import org.tabletalk.ui.CaptionScrollView;
import org.tabletalk.ui.RevealingTextView;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicReference;

public final class MainActivity extends Activity {
    private static final int IMPORT_MODEL = 10;
    private static final int MICROPHONE_PERMISSION = 11;
    private static final int INK = Color.rgb(29, 46, 43);
    private static final int MUTED = Color.rgb(80, 98, 93);
    private static final int GREEN = Color.rgb(36, 103, 95);
    private static final int PAPER = Color.rgb(248, 246, 240);
    private final ConversationLedger ledger = new ConversationLedger();
    private final ExecutorService captureWorker = Executors.newSingleThreadExecutor();
    // Shared serialization prevents overlapping model imports during activity recreation.
    private static final ExecutorService inferenceWorker = Executors.newSingleThreadExecutor();
    private WhisperEngine whisper;
    private TranslationEngine translator;
    private ModelStore models;
    private LinearLayout root;
    private TextView setupStatus;
    private CheckBox mobileDownloads;
    private TextView centerStatus;
    private Panel spanishPanel;
    private Panel englishPanel;
    private final AtomicReference<PcmRecorder> recorder = new AtomicReference<>();
    private volatile boolean destroyed;
    private boolean foreground;
    private boolean ready;
    private boolean setupBusy;
    private boolean demo;
    private int demoStep;
    private Language speaking;
    private Language lastRequestedLanguage;
    private boolean spanishFlipped;
    private AlertDialog correctionDialog;
    private Runnable pendingSampleStep;
    private Button speakEnglishButton;
    private Button listenSpanishButton;
    private Button stopButton;
    private Button retryButton;
    private Button editButton;
    private Phase phase = Phase.READY;
    private String englishStatus = "Prepare the offline models";
    private String spanishStatus = "Prepare los modelos sin conexión";
    private enum Phase { READY, RECORDING, TRANSCRIBING, TRANSLATING }

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
        if (setupBusy) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (centerStatus != null) {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            setStatus(demo ? "Sample layout — microphone off. Choose a language to practise."
                            : "Ready. Choose Speak English or Listen to Spanish.",
                    "ESPERE. El operador dará la señal para hablar.");
        }
    }
    @Override public void onPause() {
        foreground = false;
        cancelAndClear();
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        super.onPause();
    }
    @Override public void onDestroy() {
        destroyed = true;
        cancelAndClear();
        captureWorker.shutdown();
        // Do not free a native context while a cancelled inference is still unwinding.
        inferenceWorker.execute(() -> { whisper.close(); translator.close(); });

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
        content.addView(text("Whipple Chat", 18, GREEN));
        content.addView(text("One operator.\nA shared conversation.", 32, INK));
        content.addView(text("English ↔ Español\nSet up once before the visit. Translate on the phone.", 18, MUTED));
        space(content, 20);
        setupStatus = text(ready ? "Models ready. Test both speaking directions in airplane mode."
                : "Prepare the offline models before starting.", 16, GREEN);
        content.addView(setupStatus);
        if (BuildConfig.ALLOW_MODEL_DOWNLOAD) {
            mobileDownloads = new CheckBox(this);
            mobileDownloads.setText("Allow mobile data for model downloads");
            content.addView(mobileDownloads);
            content.addView(button("Download speech + translation models", this::downloadAllModels));
            content.addView(text("Recommended for POCO F1: multilingual Whisper tiny (75 MiB), plus Spanish translation. Wi-Fi is the default. Keep this screen open until setup finishes.", 15, MUTED));
        }
        content.addView(button("Import speech model (.bin) instead", () -> {
            if (setupBusy) return;
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            startActivityForResult(intent, IMPORT_MODEL);
        }));
        content.addView(text("Whisper tiny uses less memory and processes short turns faster than base. Imported files are checked before replacing your model.", 15, MUTED));
        if (BuildConfig.ALLOW_MODEL_DOWNLOAD) {
            content.addView(button("Download translation model only", this::downloadTranslation));
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

    private void setSetupBusy(boolean busy) {
        setupBusy = busy;
        if (busy && foreground) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        else if (centerStatus == null) getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    private void checkReadiness() {
        if (setupBusy || destroyed) return;
        setSetupBusy(true);
        setupStatus.setText("Checking both translation directions…");
        inferenceWorker.execute(() -> {
            if (destroyed) return;
            boolean speechExists = models.exists();
            try {
                if (!speechExists) throw new IllegalStateException();
                if (!whisper.isOpen()) whisper.open(models.file());
                translator.probeBothDirections();
                onUi(() -> {
                    ready = true;
                    setSetupBusy(false);
                    setupStatus.setText("Models ready. Before a visit, test both speaking directions in airplane mode.");
                });
            } catch (Exception failure) {
                onUi(() -> {
                    ready = false;
                    setSetupBusy(false);
                    setupStatus.setText(speechExists
                            ? "Model check failed. Download Spanish translation or re-import the speech model, then retry."
                            : "Download both models, or import a speech model and download Spanish translation.");
                });
            }
        });
    }
    private void downloadTranslation() {
        if (setupBusy) return;
        setSetupBusy(true);
        ready = false;
        final boolean wifiOnly = !mobileDownloads.isChecked();
        setupStatus.setText("Downloading Spanish. Keep " + (wifiOnly ? "Wi-Fi" : "internet") + " connected; this can take a few minutes.");
        inferenceWorker.execute(() -> {
            try {
                translator.prepareForSetup(wifiOnly, () -> destroyed);
                onUi(() -> {
                    setSetupBusy(false);
                    setupStatus.setText("Spanish is prepared. Checking speech next…");
                    checkReadiness();
                });
            } catch (Exception failure) {
                onUi(() -> {
                    setSetupBusy(false);
                    setupStatus.setText("Download or translation check failed. Check Wi-Fi and free storage, then retry.");
                });
            }
        });
    }
    private void downloadAllModels() {
        if (setupBusy || destroyed) return;
        final boolean wifiOnly = !mobileDownloads.isChecked();
        ConnectivityManager connectivity = getSystemService(ConnectivityManager.class);
        final Network network = connectivity.getActiveNetwork();
        NetworkCapabilities capabilities = connectivity.getNetworkCapabilities(network);
        if (capabilities == null || !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                || (wifiOnly && !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI))) {
            setupStatus.setText(wifiOnly ? "Connect to Wi-Fi, or enable mobile data downloads above."
                    : "Connect to the internet, then retry.");
            return;
        }
        setSetupBusy(true);
        ready = false;
        setupStatus.setText("Downloading verified speech model (75 MiB)…");
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        inferenceWorker.execute(() -> {
            try {
                if (!models.exists()) {
                    whisper.close();
                    final long[] lastMiB = {-1};
                    models.downloadTiny(network, () -> destroyed, bytes -> {
                        long mib = bytes / (1024 * 1024);
                        if (mib != lastMiB[0]) {
                            lastMiB[0] = mib;
                            onUi(() -> setupStatus.setText("Downloading speech model: " + mib + " / 75 MiB…"));
                        }
                    });
                }
                if (destroyed) return;
                onUi(() -> setupStatus.setText("Speech model saved. Downloading Spanish translation…"));
                translator.prepareForSetup(wifiOnly, () -> destroyed);
                if (destroyed) return;
                onUi(() -> {
                    getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    setSetupBusy(false);
                    checkReadiness();
                });
            } catch (Exception failure) {
                onUi(() -> {
                    getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    setSetupBusy(false);
                    setupStatus.setText("Setup did not finish. Check your connection and storage, then retry. "
                            + "Verified models already saved will be reused. " + failure.getMessage());
                });
            }
        });
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != IMPORT_MODEL || result != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        setSetupBusy(true);
        ready = false;
        setupStatus.setText("Importing and checking the speech model…");
        inferenceWorker.execute(() -> {
            try {
                whisper.close();
                String name = models.importModel(uri, () -> destroyed);
                if (destroyed) return;
                whisper.open(models.file());
                onUi(() -> {
                    setSetupBusy(false);
                    setupStatus.setText("Imported multilingual " + name + ". Checking translation…");
                    checkReadiness();
                });
            } catch (Exception failure) {
                onUi(() -> {
                    setSetupBusy(false);
                    setupStatus.setText("Import failed. Choose the original ggml-tiny.bin or ggml-base.bin from the guide. English-only and quantized files are not accepted yet.");
                });
            }
        });
    }

    private void showConversation(boolean sample) {
        cancelAndClear();
        demo = sample;
        spanishFlipped = false;
        root.removeAllViews();
        spanishPanel = new Panel(Language.SPANISH);
        englishPanel = new Panel(Language.ENGLISH);
        centerStatus = text("", 12, GREEN);
        compactOperatorText(centerStatus, 12);
        centerStatus.setTag("operatorPhase");
        englishPanel.container.addView(centerStatus, 2);
        if (getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE) {
            LinearLayout panels = new LinearLayout(this);
            panels.addView(spanishPanel.container, new LinearLayout.LayoutParams(0, -1, 1));
            panels.addView(englishPanel.container, new LinearLayout.LayoutParams(0, -1, 1));
            root.addView(panels, new LinearLayout.LayoutParams(-1, 0, 1));
        } else {
            root.addView(spanishPanel.container, new LinearLayout.LayoutParams(-1, 0, 1));
            root.addView(englishPanel.container, new LinearLayout.LayoutParams(-1, 0, 1));
        }
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (demo) addDemo(Language.ENGLISH);
        setStatus(demo ? "Sample layout — microphone off. Choose a language to practise."
                        : "Ready. Choose Speak English or Listen to Spanish.",
                "ESPERE. El operador dará la señal para hablar.");
        render();
    }
    private Button operatorButton(String label, String tag, Runnable action) {
        Button control = button(label, action);
        control.setTag(tag);
        compactOperatorText(control, 14);
        control.setMinHeight(dp(48));
        return control;
    }
    private void operatorRow(LinearLayout target, Button first, Button second) {
        LinearLayout row = new LinearLayout(this);
        row.addView(first, new LinearLayout.LayoutParams(0, -2, 1));
        row.addView(second, new LinearLayout.LayoutParams(0, -2, 1));
        target.addView(row, new LinearLayout.LayoutParams(-1, -2));
    }
    private void compactOperatorText(TextView view, int size) {
        // Keep Stop reachable on short landscape screens while caption text follows the full accessibility font scale.
        view.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX,
                dp(size) * Math.min(1.3f, getResources().getConfiguration().fontScale));
    }
    private void addOperatorControls(LinearLayout target) {
        speakEnglishButton = operatorButton("Speak English", "operatorSpeakEnglish", () -> speak(Language.ENGLISH));
        listenSpanishButton = operatorButton("Listen to Spanish", "operatorListenSpanish", () -> speak(Language.SPANISH));
        stopButton = operatorButton("Stop current turn", "operatorStop", this::stopCurrentTurn);
        retryButton = operatorButton("Retry last capture", "operatorRetry", this::retryLastCapture);
        editButton = operatorButton("Edit last transcript", "operatorEdit", this::editLastTranscript);
        operatorRow(target, speakEnglishButton, listenSpanishButton);
        operatorRow(target, stopButton, retryButton);
        operatorRow(target, editButton, operatorButton("Flip Spanish view", "operatorFlip", () -> {
            spanishFlipped = !spanishFlipped;
            spanishPanel.container.setRotation(spanishFlipped ? 180 : 0);
        }));
        operatorRow(target, operatorButton("Clear", "operatorClear", () -> {
            cancelAndClear();
            setStatus(demo ? "Sample layout — microphone off. Conversation cleared." : "Conversation cleared. Choose a language.",
                    "ESPERE. El operador dará la señal para hablar.");
        }), operatorButton("Setup", "operatorSetup", this::showSetup));
        retryButton.setContentDescription("Record a new capture in the last requested language");
    }
    private void speak(Language language) {
        if (!foreground || phase != Phase.READY || setupBusy || (!demo && !ready)) return;
        // Retain the requested direction even if permission, capture, or recognition fails before a source exists.
        lastRequestedLanguage = language;
        if (demo) {
            cancelCurrentWork();
            prepareNextTurn();
            speaking = language;
            phase = Phase.RECORDING;
            setStatus("Sample listening — microphone off. Press Stop current turn.",
                    language == Language.SPANISH ? "HABLE AHORA. Una frase breve, por favor."
                            : "ESPERE. Escuche y lea la traducción cuando esté lista.");
            return;
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, MICROPHONE_PERMISSION);
            return;
        }
        startCapture(language);
    }
    private void stopCurrentTurn() {
        if (phase == Phase.READY) return;
        if (phase == Phase.RECORDING) {
            phase = Phase.TRANSCRIBING;
            setStatus(demo ? "Sample transcribing — microphone off." : "Transcribing on this phone.",
                    "ESPERE. Transcribiendo; no hable todavía.");
            if (demo) {
                final long epoch = ledger.epoch();
                final Language language = speaking;
                postSampleStep(epoch, 1200, () -> {
                    final String[] sample = sampleTurn(language);
                    final long turnId = ledger.addSource(epoch, language, sample[0]);
                    if (turnId == -1) return;
                    phase = Phase.TRANSLATING;
                    setStatus("Sample translating — microphone off.", "ESPERE. Traduciendo; no hable todavía.");
                    render();
                    postSampleStep(epoch, 800, () -> {
                        ledger.finish(epoch, turnId, sample[1], false);
                        finishStatus(epoch, "Sample complete — microphone off. Choose the next language.",
                                "ESPERE. El operador dará la señal para hablar.", false);
                    });
                });
            } else {
                PcmRecorder current = recorder.get();
                if (current != null) current.stop();
            }
            return;
        }
        cancelCurrentWork();
        List<ConversationLedger.Turn> history = ledger.snapshot();
        if (!history.isEmpty()) {
            ConversationLedger.Turn last = history.get(history.size() - 1);
            if (last.translation == null) ledger.finish(ledger.epoch(), last.id, null, true);
        }
        setStatus("Turn cancelled. Retry the capture or edit its transcript.", "ESPERE. El operador dará la señal para hablar.");
        render();
    }
    private void postSampleStep(long epoch, long delay, Runnable action) {
        if (pendingSampleStep != null) root.removeCallbacks(pendingSampleStep);
        pendingSampleStep = () -> {
            pendingSampleStep = null;
            if (foreground && demo && ledger.isCurrent(epoch)) action.run();
        };
        root.postDelayed(pendingSampleStep, delay);
    }
    private void retryLastCapture() {
        Language language = lastRequestedLanguage;
        if (language == null || !foreground) return;
        cancelCurrentWork();
        speak(language);
    }
    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        if (request != MICROPHONE_PERMISSION) return;
        if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
            // The permission dialog may have paused and cleared the activity. Ask for a deliberate operator action.
            setStatus("Microphone allowed. Choose Speak English or Listen to Spanish.",
                    "ESPERE. El operador dará la señal para hablar.");
        } else {
            setStatus("Allow microphone access in Android settings, then choose a language.",
                    "ESPERE. El operador está preparando el micrófono.");
            showAttentionStatus();
        }
    }
    private void startCapture(Language language) {
        cancelCurrentWork();
        prepareNextTurn();
        final long epoch = ledger.epoch();
        final PcmRecorder capture = new PcmRecorder();
        recorder.set(capture);
        speaking = language;
        phase = Phase.RECORDING;
        setStatus(language == Language.ENGLISH ? "Listening to English. Press Stop current turn when finished."
                        : "Listening to Spanish. Press Stop current turn when finished.",
                language == Language.SPANISH ? "HABLE AHORA. Una frase breve, por favor."
                        : "ESPERE. Escuche y lea la traducción cuando esté lista.");
        captureWorker.execute(() -> {
            try (AudioSamples samples = capture.capture(seconds -> onUi(() -> {
                if (ledger.isCurrent(epoch) && phase == Phase.RECORDING) {
                    setStatus("Listening to " + (language == Language.ENGLISH ? "English" : "Spanish") + " — "
                                    + (AudioSamples.MAX_SECONDS - seconds) + "s left. Press Stop when finished.",
                            language == Language.SPANISH ? "HABLE AHORA. Quedan " + (AudioSamples.MAX_SECONDS - seconds) + "s."
                                    : "ESPERE. El operador está hablando.");
                }
            }))) {
                if (!ledger.isCurrent(epoch)) return;
                if (!samples.worthDecoding()) {
                    finishStatus(epoch, "No clear speech. Retry last capture or choose a language.",
                            "ESPERE. No se oyó claramente; espere la señal del operador.");
                    return;
                }
                float[] pcm = samples.copy();
                onUi(() -> {
                    if (ledger.isCurrent(epoch)) {
                        phase = Phase.TRANSCRIBING;
                        setStatus("Transcribing on this phone.", "ESPERE. Transcribiendo; no hable todavía.");
                    }
                });
                try {
                    inferenceWorker.execute(() -> processTurn(epoch, language, pcm));
                } catch (RuntimeException unavailable) {
                    Arrays.fill(pcm, 0);
                    throw unavailable;
                }
            } catch (Exception failure) {
                finishStatus(epoch, "Microphone unavailable. Retry last capture or choose a language.",
                        "ESPERE. El micrófono no está disponible.");
            } finally {
                recorder.compareAndSet(capture, null);
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
                finishStatus(epoch, "No transcript. Retry last capture with a short sentence.",
                        "ESPERE. Repita una frase corta cuando el operador dé la señal.");
                return;
            }
            turnId = ledger.addSource(epoch, language, original);
            if (turnId == -1) return;
            onUi(() -> {
                if (ledger.isCurrent(epoch)) {
                    phase = Phase.TRANSLATING;
                    setStatus("Translating on this phone.", "ESPERE. Traduciendo; no hable todavía.");
                    render();
                }
            });
            String translated = translator.translate(original, language);
            if (translated.trim().isEmpty()) throw new IllegalStateException();
            ledger.finish(epoch, turnId, translated, false);
            double elapsed = (System.nanoTime() - started) / 1_000_000_000.0;
            finishStatus(epoch, String.format(Locale.ROOT, "Ready — processed in %.1fs. Choose the next language.", elapsed),
                    "ESPERE. El operador dará la señal para hablar.", false);
        } catch (CancellationException cancelled) {
            // Clear, correction, retry, or background invalidated this turn; never restore it.
        } catch (Exception failure) {
            if (turnId != -1) ledger.finish(epoch, turnId, null, true);
            finishStatus(epoch, "Could not translate. Edit the transcript, retry capture, or recheck models.",
                    "ESPERE. No se pudo traducir; el operador revisará el texto.");
        } finally { Arrays.fill(pcm, 0); }
    }
    private void editLastTranscript() {
        List<ConversationLedger.Turn> history = ledger.snapshot();
        if (history.isEmpty() || !foreground) return;
        cancelCurrentWork();
        prepareNextTurn();
        final ConversationLedger.Turn last = history.get(history.size() - 1);
        final long expected = ledger.epoch();
        setStatus("Edit the last " + (last.sourceLanguage == Language.ENGLISH ? "English" : "Spanish")
                        + " transcript, then translate again.", "ESPERE. El operador está corrigiendo el texto.");
        EditText input = new EditText(this);
        input.setTag("correctionTranscript");
        input.setText(last.source);
        input.setTextSize(20);
        input.setMinLines(3);
        input.setMaxLines(8);
        input.setSaveEnabled(false);
        input.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        correctionDialog = new AlertDialog.Builder(this)
                .setTitle("Edit last transcript")
                .setMessage("Correct the original " + (last.sourceLanguage == Language.ENGLISH ? "English" : "Spanish")
                        + " text. The old translation will be replaced.")
                .setView(input)
                .setNegativeButton("Cancel", (dialog, which) -> {
                    setStatus("Correction cancelled. Choose a language or edit again.", "ESPERE. El operador dará la señal para hablar.");
                })
                .setPositiveButton("Translate again", null)
                .create();
        correctionDialog.setOnDismissListener(dialog -> correctionDialog = null);
        correctionDialog.show();
        correctionDialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(view -> {
            String corrected = input.getText().toString();
            if (corrected.trim().isEmpty()) {
                input.setError("Enter a short transcript before translating.");
                return;
            }
            if (!correctLastTranscript(expected, last.id, corrected)) {
                input.setError("This turn changed. Close this editor and try again.");
                return;
            }
            correctionDialog.dismiss();
        });
    }
    private boolean correctLastTranscript(long expected, long turnId, String corrected) {
        long epoch = ledger.reviseLastSource(expected, turnId, corrected);
        if (epoch == -1) return false;
        cancelCaptureAndReveal();
        prepareNextTurn();
        List<ConversationLedger.Turn> history = ledger.snapshot();
        ConversationLedger.Turn last = history.get(history.size() - 1);
        phase = Phase.TRANSLATING;
        setStatus(demo ? "Sample translating corrected text — microphone off." : "Translating corrected text on this phone.",
                "ESPERE. Traduciendo el texto corregido.");
        render();
        if (demo) {
            postSampleStep(epoch, 800, () -> {
                ledger.finish(epoch, last.id, "Sample translation: " + last.source, false);
                finishStatus(epoch, "Sample correction complete — microphone off.", "ESPERE. El operador dará la señal para hablar.", false);
            });
        } else {
            inferenceWorker.execute(() -> {
                try {
                    if (!ledger.isCurrent(epoch)) return;
                    String translated = translator.translate(last.source, last.sourceLanguage);
                    if (translated.trim().isEmpty()) throw new IllegalStateException();
                    ledger.finish(epoch, last.id, translated, false);
                    finishStatus(epoch, "Corrected transcript translated. Choose the next language.",
                            "ESPERE. El operador dará la señal para hablar.", false);
                } catch (Exception failure) {
                    ledger.finish(epoch, last.id, null, true);
                    finishStatus(epoch, "Could not translate corrected text. Edit again or retry capture.",
                            "ESPERE. No se pudo traducir; el operador revisará el texto.");
                }
            });
        }
        return true;
    }
    private void finishStatus(long epoch, String english, String spanish) {
        finishStatus(epoch, english, spanish, true);
    }
    private void finishStatus(long epoch, String english, String spanish, boolean problem) {
        onUi(() -> {
            if (!ledger.isCurrent(epoch)) return;
            speaking = null;
            phase = Phase.READY;
            setStatus(english, spanish);
            if (problem) showAttentionStatus();
            render();
        });
    }
    private void cancelCaptureAndReveal() {
        if (pendingSampleStep != null) root.removeCallbacks(pendingSampleStep);
        pendingSampleStep = null;
        if (spanishPanel != null) spanishPanel.stopReveal();
        if (englishPanel != null) englishPanel.stopReveal();
        PcmRecorder current = recorder.getAndSet(null);
        if (current != null) current.stop();
        if (whisper != null) whisper.cancel();
        speaking = null;
        phase = Phase.READY;
    }
    private void cancelCurrentWork() {
        ledger.invalidate();
        cancelCaptureAndReveal();
        List<ConversationLedger.Turn> history = ledger.snapshot();
        if (!history.isEmpty()) {
            ConversationLedger.Turn last = history.get(history.size() - 1);
            if (last.translation == null) ledger.finish(ledger.epoch(), last.id, null, true);
        }
    }
    private void cancelAndClear() {
        ledger.clear();
        cancelCaptureAndReveal();
        lastRequestedLanguage = null;
        if (correctionDialog != null) correctionDialog.dismiss();
        if (spanishPanel != null && englishPanel != null) render();
    }
    private void prepareNextTurn() {
        for (Panel panel : new Panel[]{spanishPanel, englishPanel}) {
            if (panel == null) continue;
            panel.stopReveal();
            panel.followLatest = true;
            panel.scroll.scrollTo(0, 0);
        }
    }
    private void setStatus(String english, String spanish) {
        englishStatus = english;
        spanishStatus = spanish;
        if (centerStatus != null) centerStatus.setText(demo ? "SAMPLE — MICROPHONE OFF · " + phase.name()
                : phase == Phase.RECORDING ? "LISTENING" : phase.name());
        if (englishPanel != null) englishPanel.status.setText(english);
        if (spanishPanel != null) spanishPanel.status.setText(spanish);
        updateButtons();
    }
    private void showAttentionStatus() {
        if (centerStatus != null && !demo) centerStatus.setText("WAITING — operator review needed");
    }
    private void updateButtons() {
        if (englishPanel == null || spanishPanel == null || speakEnglishButton == null) return;
        boolean idle = phase == Phase.READY;
        speakEnglishButton.setEnabled(idle);
        listenSpanishButton.setEnabled(idle);
        stopButton.setEnabled(!idle);
        retryButton.setEnabled(lastRequestedLanguage != null);
        editButton.setEnabled(!ledger.snapshot().isEmpty());
    }
    private void render() {
        if (spanishPanel == null || englishPanel == null) return;
        List<ConversationLedger.Turn> history = ledger.snapshot();
        spanishPanel.render(history);
        englishPanel.render(history);
        updateButtons();
    }
    private String[] sampleTurn(Language language) {
        String original;
        String translated;
        if (language == Language.ENGLISH) {
            original = demoStep++ % 2 == 0 ? "How are you feeling today?" : "Would you like me to pray with you?";
            translated = original.startsWith("How") ? "¿Cómo se siente hoy?" : "¿Le gustaría que orara con usted?";
        } else {
            original = "Estoy preocupado por mi familia.";
            translated = "I am worried about my family.";
        }
        return new String[]{original, translated};
    }
    private void addDemo(Language language) {
        String[] sample = sampleTurn(language);
        long epoch = ledger.epoch();
        long id = ledger.addSource(epoch, language, sample[0]);
        ledger.finish(epoch, id, sample[1], false);
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
        final CaptionScrollView scroll = new CaptionScrollView(MainActivity.this);
        final LinearLayout reading = column();
        final List<RevealingTextView> reveals = new ArrayList<>();
        List<ConversationLedger.Turn> renderedHistory = new ArrayList<>();
        boolean followLatest = true;
        boolean rendered;
        int renderVersion;
        Runnable pendingPosition;
        ViewTreeObserver.OnPreDrawListener pendingLayout;
        Panel(Language language) {
            this.language = language;
            boolean viewer = language == Language.SPANISH;
            container.setTag(viewer ? "viewerPanel" : "operatorPanel");
            container.setPadding(dp(14), dp(8), dp(14), dp(8));
            container.setSaveEnabled(false);
            if (viewer) container.setBackgroundColor(Color.rgb(235, 240, 231));
            TextView heading = text(viewer ? "ESPAÑOL · PARA LEER" : "WHIPPLE CHAT · OPERATOR", 14, GREEN);
            heading.setLetterSpacing(0.08f);
            if (!viewer) compactOperatorText(heading, 14);
            container.addView(heading);
            status = text(viewer ? spanishStatus : englishStatus, viewer ? 24 : 15, viewer ? GREEN : MUTED);
            status.setTag(viewer ? "viewerStatus" : "operatorStatus");
            if (!viewer) compactOperatorText(status, 15);
            container.addView(status);
            if (viewer) {
                if (demo) reading.addView(text("EJEMPLO — MICRÓFONO APAGADO", 12, GREEN));
                TextView instructions = text("Hable despacio y con claridad.\nUna frase breve a la vez.\nEspere la señal del operador.", 22, INK);
                instructions.setTag("viewerInstructions");
                reading.addView(instructions);
                // This is a passive reading surface. All capture, editing and orientation controls belong to the operator.
                scroll.setFocusable(false);
                scroll.setFocusableInTouchMode(false);
                scroll.setClickable(false);
                scroll.setLongClickable(false);
                scroll.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
                scroll.setOnTouchListener((view, event) -> true);
                scroll.setOnGenericMotionListener((view, event) -> true);
            } else {
                addOperatorControls(reading);
            }
            captions.setTag(viewer ? "viewerCaptions" : "operatorCaptions");
            reading.addView(captions, new LinearLayout.LayoutParams(-1, -2));
            reading.addView(text(viewer ? "La traducción puede contener errores." : "Translation can make mistakes. Scroll to review both languages.", 11, MUTED));
            scroll.addView(reading, new ScrollView.LayoutParams(-1, -2));
            scroll.setContentDescription(viewer ? "Texto para leer en español" : "English operator controls and conversation");
            if (!viewer) scroll.setOnUserInteraction(() -> {
                followLatest = false;
                stopReveal();
            });
            container.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        }
        void stopReveal() {
            renderVersion++;
            if (pendingPosition != null) scroll.removeCallbacks(pendingPosition);
            if (pendingLayout != null && scroll.getViewTreeObserver().isAlive()) {
                scroll.getViewTreeObserver().removeOnPreDrawListener(pendingLayout);
            }
            pendingPosition = null;
            pendingLayout = null;
            for (RevealingTextView view : reveals) view.finishReveal();
        }
        RevealingTextView caption(String value, int size, int color) {
            RevealingTextView view = new RevealingTextView(MainActivity.this);
            view.setText(value);
            view.setTextSize(size);
            view.setTextColor(color);
            view.setPadding(0, dp(4), 0, dp(4));
            captions.addView(view, new LinearLayout.LayoutParams(-1, -2));
            return view;
        }
        void render(List<ConversationLedger.Turn> history) {
            if (rendered && renderedHistory.equals(history)) return;
            stopReveal();
            final int version = renderVersion;
            rendered = true;
            renderedHistory = new ArrayList<>(history);
            reveals.clear();
            captions.removeAllViews();
            if (history.isEmpty()) {
                followLatest = true;
                scroll.scrollTo(0, 0);
                captions.addView(text(language == Language.SPANISH
                        ? "La traducción aparecerá aquí."
                        : "English and Spanish captions will appear here. Use the operator controls above.", 24, INK));
                return;
            }
            TextView newestLabel = null;
            RevealingTextView newestTranslation = null;
            long newestId = history.get(history.size() - 1).id;
            List<ConversationLedger.Turn> visibleHistory = language == Language.SPANISH
                    ? java.util.Collections.singletonList(history.get(history.size() - 1)) : history;
            for (ConversationLedger.Turn turn : visibleHistory) {
                String primary = turn.textFor(language);
                String secondary = turn.textFor(language.other());
                TextView label = text(language == Language.SPANISH
                        ? (turn.sourceLanguage == Language.SPANISH ? "USTED DIJO" : "TRADUCCIÓN PARA USTED")
                        : (turn.sourceLanguage == Language.ENGLISH ? "English original" : "English translation"), 12, GREEN);
                captions.addView(label);
                if (primary == null) primary = turn.translationFailed
                        ? (language == Language.SPANISH ? "Traducción no disponible. Espere al operador." : "Translation unavailable. Edit the transcript or retry capture.")
                        : (language == Language.SPANISH ? "Traduciendo…" : "Translating…");
                RevealingTextView primaryView = caption(primary, language == Language.SPANISH ? 30 : 24, INK);
                RevealingTextView secondaryView = null;
                if (language == Language.ENGLISH && secondary != null) {
                    captions.addView(text(turn.sourceLanguage == Language.SPANISH ? "Spanish original" : "Spanish translation", 12, GREEN));
                    secondaryView = caption(secondary, 20, MUTED);
                }
                if (turn.id == newestId) {
                    newestLabel = label;
                    if (turn.translation != null && !turn.translationFailed) {
                        newestTranslation = turn.sourceLanguage == language ? secondaryView : primaryView;
                        if (newestTranslation != null) reveals.add(newestTranslation);
                    }
                }
                space(captions, 10);
            }
            final TextView anchor = newestLabel;
            final RevealingTextView translation = newestTranslation;
            final boolean receiving = history.get(history.size() - 1).sourceLanguage != language;
            pendingPosition = () -> {
                pendingPosition = null;
                if (version != renderVersion || !foreground || !followLatest) return;
                // Start at the beginning of the newest turn, never the end of a long translation.
                scroll.scrollTo(0, captions.getTop() + anchor.getTop());
                if (translation == null) return;
                translation.startReveal(() -> {
                    if (version != renderVersion || !followLatest || !foreground || !receiving) return;
                    int bottom = captions.getTop() + translation.getTop() + translation.revealedLineBottom();
                    int viewport = scroll.getHeight() - scroll.getPaddingTop() - scroll.getPaddingBottom();
                    if (viewport > 0 && bottom > scroll.getScrollY() + viewport) {
                        scroll.scrollTo(0, bottom - viewport);
                    }
                });
            };
            pendingLayout = () -> {
                scroll.getViewTreeObserver().removeOnPreDrawListener(pendingLayout);
                pendingLayout = null;
                Runnable position = pendingPosition;
                if (position != null) position.run();
                return true;
            };
            scroll.getViewTreeObserver().addOnPreDrawListener(pendingLayout);
        }
    }
}
