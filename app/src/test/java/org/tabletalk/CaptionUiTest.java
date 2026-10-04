package org.tabletalk;

import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

import android.app.AlertDialog;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.Looper;
import android.provider.Settings;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;
import java.util.function.IntConsumer;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.Implements;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowAlertDialog;
import org.tabletalk.audio.PcmRecorder;
import org.tabletalk.core.AudioSamples;
import org.tabletalk.core.ConversationLedger;
import org.tabletalk.core.Language;
import org.tabletalk.inference.TranslationEngine;
import org.tabletalk.inference.WhisperEngine;
import org.tabletalk.ui.CaptionScrollView;
import org.tabletalk.ui.RevealingTextView;

/** Actual native UI/sample interactions; real microphone and inference remain outside this suite. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35, qualifiers = "w360dp-h640dp-port", shadows = {
        CaptionUiTest.ShadowWhisper.class, CaptionUiTest.ShadowCapture.class,
        CaptionUiTest.ShadowTranslation.class},
        instrumentedPackages = {"org.tabletalk.inference", "org.tabletalk.audio"})
@LooperMode(LooperMode.Mode.PAUSED)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class CaptionUiTest {
    private static final AtomicInteger captureCalls = new AtomicInteger();
    private static final AtomicInteger speechCalls = new AtomicInteger();
    private static final AtomicInteger translationCalls = new AtomicInteger();
    private static final String[] CONTROLS = {"operatorSpeakEnglish", "operatorListenSpanish", "operatorStop",
            "operatorRetry", "operatorEdit", "operatorClear", "operatorSetup", "operatorFlip"};
    private ActivityController<MainActivity> controller;
    private MainActivity activity;

    @Implements(value = WhisperEngine.class, isInAndroidSdk = false)
    public static class ShadowWhisper {
        @Implementation protected static void __staticInitializer__() {}
        @Implementation protected void cancel() {}
        @Implementation protected void close() {}
        @Implementation protected String transcribe(float[] samples, Language language, BooleanSupplier current) {
            speechCalls.incrementAndGet();
            throw new IllegalStateException("Sample UI must not invoke speech inference");
        }
    }
    @Implements(value = PcmRecorder.class, isInAndroidSdk = false)
    public static class ShadowCapture {
        @Implementation protected AudioSamples capture(IntConsumer seconds) {
            captureCalls.incrementAndGet();
            throw new IllegalStateException("Sample UI must not open the microphone");
        }
        @Implementation protected void stop() {}
    }
    @Implements(value = TranslationEngine.class, isInAndroidSdk = false)
    public static class ShadowTranslation {
        @Implementation protected boolean modelsDownloaded() { return false; }
        @Implementation protected void close() {}
        @Implementation protected String translate(String source, Language language) {
            translationCalls.incrementAndGet();
            throw new IllegalStateException("Sample UI must not invoke translation inference");
        }
    }
    @Before public void openSample() throws Exception {
        captureCalls.set(0); speechCalls.set(0); translationCalls.set(0);
        RuntimeEnvironment.setFontScale(1f);
        controller = Robolectric.buildActivity(MainActivity.class).setup().visible();
        activity = controller.get();
        Settings.Global.putFloat(activity.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
        shadowOf(activity.getSystemService(AccessibilityManager.class)).setEnabled(false);
        sample();
        layout(360, 640);
    }
    @After public void closeActivity() {
        if (controller != null) controller.pause().stop().destroy();
        RuntimeEnvironment.setFontScale(1f);
        assertEquals("Sample must never record audio", 0, captureCalls.get());
        assertEquals("Sample must never run speech inference", 0, speechCalls.get());
        assertEquals("Sample must never run translation inference", 0, translationCalls.get());
    }

    @Test public void englishOperatorOwnsEveryControlAndSpanishViewerIsPassive() throws Exception {
        View operator = tagged("operatorPanel"), viewer = tagged("viewerPanel");
        for (String tag : CONTROLS) {
            assertTrue(tag + " belongs on the English operator side", within(control(tag), operator));
            assertFalse(within(control(tag), viewer));
        }
        assertPassiveViewer();
        assertTrue(allText().toLowerCase().contains("whipple chat"));
        assertTrue("Sample must disclose microphone off", allText().toLowerCase().contains("microphone off"));
        assertEquals(Language.ENGLISH, last().sourceLanguage);
        assertTrue(textWithin(viewer).contains(last().translation));
        assertFalse(textWithin(viewer).contains(last().source));
        assertEquals(0f, viewer.getRotation(), 0f);
        control("operatorFlip").performClick();
        assertEquals(180f, viewer.getRotation(), 0f);
        assertEquals(0f, operator.getRotation(), 0f);
        assertPassiveViewer();
        control("operatorFlip").performClick();
        assertEquals(0f, viewer.getRotation(), 0f);
        assertTrue((activity.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_SECURE) != 0);
        screenshot("whipple-portrait-ready-font100.png");
    }
    @Test public void actualSampleButtonsShowListeningTranscribingAndTranslating() throws Exception {
        int before = ledger().snapshot().size();
        control("operatorListenSpanish").performClick();
        phase("RECORDING");
        assertTrue(control("operatorStop").isEnabled());
        for (String tag : new String[]{"operatorSpeakEnglish", "operatorListenSpanish"})
            assertFalse(tag + " must be disabled during capture", control(tag).isEnabled());
        assertTrue(textWithin(tagged("viewerPanel")).toLowerCase().contains("hable"));
        assertPassiveViewer();
        layout(360, 640); screenshot("whipple-portrait-listening-spanish.png");
        control("operatorStop").performClick();
        phase("TRANSCRIBING");
        assertTrue("Operator can cancel processing", control("operatorStop").isEnabled());
        assertTrue(textWithin(tagged("viewerPanel")).toLowerCase().contains("espere"));
        layout(360, 640); screenshot("whipple-portrait-transcribing.png");
        idle(1200); phase("TRANSLATING");
        assertEquals(before + 1, ledger().snapshot().size());
        assertEquals(Language.SPANISH, last().sourceLanguage);
        assertNull(last().translation);
        assertTrue(textWithin(tagged("operatorPanel")).contains(last().source));
        layout(360, 640); screenshot("whipple-portrait-translating.png");
        idle(800); phase("READY");
        assertNotNull(last().translation);
        assertTrue(control("operatorEdit").isEnabled());
        assertTrue(control("operatorRetry").isEnabled());
        assertFalse(control("operatorStop").isEnabled());
        assertTrue(textWithin(tagged("viewerPanel")).contains(last().source));
        assertFalse(textWithin(tagged("viewerPanel")).contains(last().translation));
    }
    @Test public void repeatAndRetryUseTheOperatorAndKeepBoundedHistory() throws Exception {
        complete("operatorListenSpanish");
        long oldId = last().id;
        control("operatorRetry").performClick(); phase("RECORDING"); finishSample();
        assertEquals(Language.SPANISH, last().sourceLanguage);
        assertTrue(last().id > oldId);
        for (int index = 0; index < ConversationLedger.MAX_TURNS + 2; index++) {
            Language expected = index % 2 == 0 ? Language.ENGLISH : Language.SPANISH;
            complete(expected == Language.ENGLISH ? "operatorSpeakEnglish" : "operatorListenSpanish");
            assertEquals(expected, last().sourceLanguage);
            assertNotNull(last().translation);
            assertFalse(last().translationFailed);
            assertTrue(ledger().snapshot().size() <= ConversationLedger.MAX_TURNS);
        }
        assertEquals(ConversationLedger.MAX_TURNS, ledger().snapshot().size());
        idle(13000); layout(360, 640); assertPassiveViewer();
        screenshot("whipple-portrait-repeated-turns.png");
    }
    @Test public void operatorCorrectionReplacesLatestTurnAndRejectsBlankText() throws Exception {
        complete("operatorSpeakEnglish");
        ConversationLedger.Turn original = last();
        int count = ledger().snapshot().size();
        long oldEpoch = ledger().epoch();
        control("operatorEdit").performClick();
        AlertDialog dialog = ShadowAlertDialog.getLatestAlertDialog();
        assertNotNull(dialog);
        EditText input = dialog.getWindow().getDecorView().findViewWithTag("correctionTranscript");
        assertNotNull(input);
        assertEquals(original.source, input.getText().toString());
        input.setText("   "); dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick();
        assertTrue("Blank correction keeps the dialog open", dialog.isShowing());
        assertEquals(original.source, last().source);
        String corrected = "I would like to call my family tomorrow, after lunch.";
        input.setText(corrected); dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick();
        assertFalse(dialog.isShowing()); phase("TRANSLATING");
        assertEquals(count, ledger().snapshot().size()); assertEquals(original.id, last().id);
        assertEquals(corrected, last().source); assertNull(last().translation);
        assertFalse(ledger().finish(oldEpoch, original.id, "A stale translation", false));
        idle(800); phase("READY");
        assertTrue(last().translation.contains(corrected));
        assertTrue(allText().contains(corrected)); assertFalse(allText().contains("A stale translation"));
        layout(360, 640); screenshot("whipple-portrait-corrected-sample.png");
    }
    @Test public void retryDuringProcessingCancelsOldSampleBeforeStartingNewCapture() throws Exception {
        int count = ledger().snapshot().size();
        control("operatorListenSpanish").performClick(); control("operatorStop").performClick();
        phase("TRANSCRIBING");
        control("operatorRetry").performClick(); phase("RECORDING");
        idle(2200);
        assertEquals("The cancelled sample must not add a turn", count, ledger().snapshot().size());
        phase("RECORDING");
        finishSample();
        assertEquals(count + 1, ledger().snapshot().size());
        assertEquals(Language.SPANISH, last().sourceLanguage);
    }
    @Test public void backgroundCancelsPendingCorrectionTranslation() throws Exception {
        control("operatorEdit").performClick();
        AlertDialog dialog = ShadowAlertDialog.getLatestAlertDialog();
        EditText input = dialog.getWindow().getDecorView().findViewWithTag("correctionTranscript");
        input.setText("This private corrected source must not return after backgrounding.");
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick(); phase("TRANSLATING");
        controller.pause(); idle(15000);
        assertTrue(ledger().snapshot().isEmpty());
        assertFalse(allText().contains("private corrected source"));
        controller.resume(); assertTrue(ledger().snapshot().isEmpty());
    }
    @Test public void retryRemainsAvailableAfterCaptureFailsBeforeAnyTranscript() throws Exception {
        control("operatorClear").performClick();
        assertTrue(ledger().snapshot().isEmpty());
        // Simulate recognition returning no source; actual microphone quality is a device-only check.
        Field requested = activity.getClass().getDeclaredField("lastRequestedLanguage");
        requested.setAccessible(true); requested.set(activity, Language.SPANISH);
        invoke(activity, "setStatus", new Class<?>[]{String.class, String.class},
                "No transcript. Retry last capture with a short sentence.", "ESPERE. Espere la señal del operador.");
        assertTrue(control("operatorRetry").isEnabled());
        assertFalse(control("operatorEdit").isEnabled());
        control("operatorRetry").performClick(); phase("RECORDING"); finishSample();
        assertEquals(1, ledger().snapshot().size());
        assertEquals(Language.SPANISH, last().sourceLanguage);
    }
    @Test public void correctingPendingTranslationCancelsItsOldCompletion() throws Exception {
        control("operatorSpeakEnglish").performClick(); control("operatorStop").performClick();
        idle(1200); phase("TRANSLATING");
        long oldEpoch = ledger().epoch(), turnId = last().id;
        control("operatorEdit").performClick();
        AlertDialog dialog = ShadowAlertDialog.getLatestAlertDialog();
        EditText input = dialog.getWindow().getDecorView().findViewWithTag("correctionTranscript");
        String corrected = "Correct the pending original before its first translation arrives.";
        input.setText(corrected); dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick();
        phase("TRANSLATING");
        assertFalse(ledger().finish(oldEpoch, turnId, "Obsolete original translation", false));
        idle(2000); phase("READY");
        assertEquals(turnId, last().id); assertEquals(corrected, last().source);
        assertEquals("Sample translation: " + corrected, last().translation);
        assertFalse(allText().contains("Obsolete original translation"));
    }
    @Test public void clearingCancelsEveryPendingSampleStageAndLateTranslation() throws Exception {
        for (String stage : new String[]{"RECORDING", "TRANSCRIBING", "TRANSLATING"}) {
            sample(); control("operatorSpeakEnglish").performClick();
            if (!stage.equals("RECORDING")) control("operatorStop").performClick();
            if (stage.equals("TRANSLATING")) idle(1200);
            phase(stage);
            long epoch = ledger().epoch();
            long id = ledger().addSource(epoch, Language.ENGLISH, "Pending private turn must stay cleared.");
            control("operatorClear").performClick();
            assertFalse(ledger().finish(epoch, id, "Esta frase debe permanecer borrada.", false));
            idle(15000); phase("READY"); assertTrue(ledger().snapshot().isEmpty());
            assertFalse(allText().contains("Pending private turn"));
            assertFalse(allText().contains("permanecer borrada"));
            assertFalse(control("operatorEdit").isEnabled()); assertPassiveViewer();
        }
        layout(360, 640); screenshot("whipple-portrait-cleared.png");
    }
    @Test public void backgroundAndSetupCancelPendingSamplesWithoutRestoringCaptions() throws Exception {
        control("operatorListenSpanish").performClick(); control("operatorStop").performClick();
        idle(1200); phase("TRANSLATING"); controller.pause(); idle(15000);
        assertTrue(ledger().snapshot().isEmpty());
        assertFalse(allText().contains("How are you feeling today?"));
        controller.resume(); assertTrue(ledger().snapshot().isEmpty());
        sample(); control("operatorSpeakEnglish").performClick(); control("operatorStop").performClick();
        control("operatorSetup").performClick(); idle(15000);
        assertTrue(ledger().snapshot().isEmpty()); assertNull(root().findViewWithTag("viewerPanel"));
        assertFalse(allText().contains("How are you feeling today?"));
    }
    @Test public void translationFailureKeepsOriginalForCorrectionOffTheSpanishViewer() throws Exception {
        String source = "Keep the operator's original transcript when translation fails.";
        invoke(activity, "prepareNextTurn"); long epoch = ledger().epoch();
        long id = ledger().addSource(epoch, Language.ENGLISH, source);
        assertTrue(ledger().finish(epoch, id, null, true)); invoke(activity, "render");
        assertTrue(textWithin(tagged("operatorPanel")).contains(source));
        assertFalse(textWithin(tagged("viewerPanel")).contains(source));
        assertTrue(control("operatorEdit").isEnabled()); assertTrue(last().translationFailed);
    }
    @Test public void longTranslationWrapsCompletelyAndStatusKeepsItsView() throws Exception {
        String full = "I am concerned about my family and want time to explain everything carefully. ".repeat(12);
        addTurn(Language.SPANISH, "Me preocupa mi familia.", full); layout(360, 800);
        RevealingTextView caption = revealing(full); assertNotNull(caption); assertTrue(caption.getLineCount() > 10);
        assertNull(caption.getEllipsize());
        assertEquals(full.length(), caption.getLayout().getLineEnd(caption.getLineCount() - 1));
        CaptionScrollView scroll = (CaptionScrollView) field(panel("englishPanel"), "scroll");
        assertTrue(scroll.getChildAt(0).getHeight() > scroll.getHeight());
        invoke(activity, "setStatus", new Class<?>[]{String.class, String.class}, "Ready", "Listo"); invoke(activity, "render");
        assertSame(caption, revealing(full)); screenshot("whipple-portrait-long-caption-partial.png");
        idle(13000); assertEquals(full.length(), caption.getRevealedEnd());
        screenshot("whipple-portrait-long-caption-complete.png");
    }
    @Test public void newTurnCancelsPreviousRevealWithoutLosingOperatorTranscript() throws Exception {
        String first = "This older translation remains after another person starts speaking. ".repeat(5);
        addTurn(Language.SPANISH, "Primera frase.", first); layout(360, 800);
        RevealingTextView old = revealing(first); assertRevealing(old);
        String second = "Esta nueva traducción aparece sin restaurar la animación anterior.";
        addTurn(Language.ENGLISH, "A new turn.", second); layout(360, 800);
        assertFalse(old.isRevealing()); idle(13000);
        assertTrue(allText().contains(first)); assertTrue(allText().contains(second));
        for (RevealingTextView text : descendants(root(), RevealingTextView.class)) assertFalse(text.isRevealing());
    }
    @Test public void operatorTouchAndKeyboardStopRevealAndAutomaticFollowing() throws Exception {
        for (boolean keyboard : new boolean[]{false, true}) {
            String full = (keyboard ? "Keyboard " : "Touch ") + "lets the operator read a long translation at any time. ".repeat(15);
            addTurn(Language.SPANISH, "Quiero leer a mi propio ritmo.", full); layout(360, 800);
            RevealingTextView caption = revealing(full); assertRevealing(caption);
            CaptionScrollView scroll = (CaptionScrollView) field(panel("englishPanel"), "scroll");
            if (keyboard) scroll.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_UP));
            else {
                MotionEvent touch = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 10, 10, 0);
                scroll.dispatchTouchEvent(touch); touch.recycle();
            }
            assertFalse(caption.isRevealing()); assertEquals(full.length(), caption.getRevealedEnd());
            scroll.scrollTo(0, 0); idle(13000); assertEquals(0, scroll.getScrollY());
        }
    }
    @Test public void portraitLandscapeAndLargeFontsKeepCaptionsAndControlsUsable() throws Exception {
        for (int[] size : new int[][]{{360, 800, 100}, {640, 360, 100}, {360, 800, 200}, {800, 480, 200}}) {
            RuntimeEnvironment.setQualifiers("w" + size[0] + "dp-h" + size[1] + "dp-" + (size[0] > size[1] ? "land" : "port"));
            RuntimeEnvironment.setFontScale(size[2] / 100f); controller.configurationChange(); activity = controller.get();
            sample(); layout(size[0], size[1]); float density = activity.getResources().getDisplayMetrics().density;
            for (String name : new String[]{"englishPanel", "spanishPanel"}) {
                View scroll = (View) field(panel(name), "scroll");
                assertTrue(name + " needs a useful caption height", scroll.getHeight() >= 64 * density);
                assertTrue(name + " needs a useful caption width", scroll.getWidth() >= 120 * density);
            }
            for (String tag : CONTROLS) {
                Button button = control(tag); assertTrue(tag + " needs a 48dp target", button.getHeight() >= 48 * density);
                assertNotNull(button.getLayout());
                assertTrue(tag + " label must wrap without clipping at this font scale",
                        button.getLayout().getHeight() <= button.getHeight() - button.getCompoundPaddingTop() - button.getCompoundPaddingBottom());
            }
            assertPassiveViewer(); View operator = tagged("operatorPanel"), viewer = tagged("viewerPanel");
            if (size[0] > size[1]) assertEquals(operator.getTop(), viewer.getTop());
            else assertTrue(viewer.getBottom() <= operator.getTop());
            screenshot("whipple-panels-" + size[0] + "x" + size[1] + "-font" + size[2] + ".png");
        }
    }
    @Test public void recreationCancelsRevealAndNeverRestoresPrivateCaptions() throws Exception {
        String full = "A private translation must not return after rotating the device. ".repeat(10);
        addTurn(Language.SPANISH, "Una frase privada.", full); layout(360, 800);
        RevealingTextView old = revealing(full); assertRevealing(old);
        controller.recreate(); activity = controller.get(); idle(13000);
        assertFalse(old.isRevealing()); assertTrue(ledger().snapshot().isEmpty()); assertFalse(allText().contains(full));
    }

    private void sample() throws Exception { invoke(activity, "showConversation", new Class<?>[]{boolean.class}, true); }
    private void complete(String tag) throws Exception {
        assertTrue(control(tag).isEnabled()); control(tag).performClick(); phase("RECORDING"); finishSample();
    }
    private void finishSample() throws Exception {
        control("operatorStop").performClick(); phase("TRANSCRIBING"); idle(1200); phase("TRANSLATING"); idle(800); phase("READY");
    }
    private void phase(String expected) throws Exception { assertEquals(expected, field(activity, "phase").toString()); }
    private void idle(long milliseconds) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(milliseconds)); }
    private ConversationLedger ledger() throws Exception { return (ConversationLedger) field(activity, "ledger"); }
    private ConversationLedger.Turn last() throws Exception {
        List<ConversationLedger.Turn> turns = ledger().snapshot(); assertFalse(turns.isEmpty()); return turns.get(turns.size() - 1);
    }
    private View root() throws Exception { return (View) field(activity, "root"); }
    private View tagged(String tag) throws Exception {
        View view = root().findViewWithTag(tag); assertNotNull("Missing native view tag " + tag, view); return view;
    }
    private Button control(String tag) throws Exception { View view = tagged(tag); assertTrue(view instanceof Button); return (Button) view; }
    private void assertPassiveViewer() throws Exception {
        View viewer = tagged("viewerPanel"); assertTrue(descendants(viewer, Button.class).isEmpty()); assertTrue(descendants(viewer, EditText.class).isEmpty());
        for (View view : descendants(viewer, View.class)) {
            assertFalse("Viewer click action " + view.getTag(), view.isClickable());
            assertFalse("Viewer long-click action " + view.getTag(), view.isLongClickable());
            assertFalse("Viewer focusable control " + view.getTag(), view.isFocusable());
        }
    }
    private boolean within(View child, View parent) {
        for (View view = child; view != null; view = view.getParent() instanceof View ? (View) view.getParent() : null) if (view == parent) return true;
        return false;
    }
    private void addTurn(Language language, String source, String translation) throws Exception {
        invoke(activity, "prepareNextTurn"); long epoch = ledger().epoch(); long id = ledger().addSource(epoch, language, source);
        assertTrue(ledger().finish(epoch, id, translation, false)); invoke(activity, "render");
    }
    private RevealingTextView revealing(String text) throws Exception {
        for (RevealingTextView view : descendants(root(), RevealingTextView.class)) if (view.getText().toString().equals(text)) return view;
        return null;
    }
    private Object panel(String name) throws Exception { return field(activity, name); }
    private void assertRevealing(RevealingTextView caption) { assertNotNull(caption); assertTrue(caption.isRevealing()); assertTrue(caption.getRevealedEnd() < caption.length()); }
    private void layout(int widthDp, int heightDp) throws Exception {
        View root = root(); float density = activity.getResources().getDisplayMetrics().density;
        int width = Math.round(widthDp * density), height = Math.round(heightDp * density);
        root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
        root.layout(0, 0, width, height); root.getViewTreeObserver().dispatchOnPreDraw();
        for (CaptionScrollView scroll : descendants(root, CaptionScrollView.class)) scroll.getViewTreeObserver().dispatchOnPreDraw();
        assertEquals(width, root.getWidth()); assertEquals(height, root.getHeight());
    }
    private void screenshot(String name) throws Exception {
        View root = root(); Bitmap bitmap = Bitmap.createBitmap(root.getWidth(), root.getHeight(), Bitmap.Config.ARGB_8888); root.draw(new Canvas(bitmap));
        File directory = new File("build/reports/caption-screenshots"); assertTrue(directory.isDirectory() || directory.mkdirs());
        try (FileOutputStream output = new FileOutputStream(new File(directory, name))) { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)); }
        bitmap.recycle();
    }
    private String allText() throws Exception { return textWithin(root()); }
    private String textWithin(View root) {
        StringBuilder result = new StringBuilder(); for (TextView text : descendants(root, TextView.class)) result.append(text.getText()).append('\n'); return result.toString();
    }
    private static <T> List<T> descendants(View view, Class<T> type) {
        List<T> result = new ArrayList<>(); if (type.isInstance(view)) result.add(type.cast(view));
        if (view instanceof ViewGroup) { ViewGroup group = (ViewGroup) view; for (int index = 0; index < group.getChildCount(); index++) result.addAll(descendants(group.getChildAt(index), type)); }
        return result;
    }
    private static Object field(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name); field.setAccessible(true); return field.get(target);
    }
    private static void invoke(Object target, String name) throws Exception { invoke(target, name, new Class<?>[0]); }
    private static void invoke(Object target, String name, Class<?>[] types, Object... arguments) throws Exception {
        Method method = target.getClass().getDeclaredMethod(name, types); method.setAccessible(true); method.invoke(target, arguments);
    }
}
