package org.tabletalk;

import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

import android.os.Looper;
import android.provider.Settings;
import android.view.accessibility.AccessibilityManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.io.File;
import java.io.FileOutputStream;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.Implements;
import org.robolectric.annotation.LooperMode;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.android.controller.ActivityController;
import org.tabletalk.core.ConversationLedger;
import org.tabletalk.core.Language;
import org.tabletalk.inference.WhisperEngine;
import org.tabletalk.ui.CaptionScrollView;
import org.tabletalk.ui.RevealingTextView;

/** Actual Activity/view integration; speech inference is deliberately outside this UI suite. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35, shadows = CaptionUiTest.ShadowWhisper.class,
        instrumentedPackages = "org.tabletalk.inference")
@LooperMode(LooperMode.Mode.PAUSED)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class CaptionUiTest {
    private ActivityController<MainActivity> controller;
    private MainActivity activity;

    @Implements(value = WhisperEngine.class, isInAndroidSdk = false)
    public static class ShadowWhisper {
        @Implementation protected static void __staticInitializer__() {}
        @Implementation protected void cancel() {}
        @Implementation protected void close() {}
    }

    @Before public void openSample() throws Exception {
        controller = Robolectric.buildActivity(MainActivity.class).setup().visible();
        activity = controller.get();
        Settings.Global.putFloat(activity.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
        shadowOf(activity.getSystemService(AccessibilityManager.class)).setEnabled(false);
        invoke(activity, "showConversation", new Class<?>[]{boolean.class}, true);
        layout(360, 640);
    }

    @After public void closeActivity() {
        if (controller != null) controller.pause().stop().destroy();
    }

    @Test public void sampleKeepsBothLanguagesAndOpposingOrientation() throws Exception {
        assertTrue(allText().contains("How are you feeling today?"));
        assertTrue(allText().contains("¿Cómo se siente hoy?"));
        View spanish = (View) field(panel("spanishPanel"), "container");
        View english = (View) field(panel("englishPanel"), "container");
        assertEquals(180f, spanish.getRotation(), 0f);
        assertEquals(0f, english.getRotation(), 0f);
    }

    @Test public void clearingInvalidatesPendingTranslationAndLeavesNoCaptions() throws Exception {
        ConversationLedger ledger = (ConversationLedger) field(activity, "ledger");
        long epoch = ledger.epoch();
        long id = ledger.addSource(epoch, Language.ENGLISH, "This unfinished turn must stay cleared.");
        invoke(activity, "render");
        invoke(activity, "cancelAndClear");
        assertFalse(ledger.finish(epoch, id, "Esta frase debe permanecer borrada.", false));
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13));
        assertTrue(ledger.snapshot().isEmpty());
        assertFalse(allText().contains("unfinished turn"));
        assertFalse(allText().contains("permanecer borrada"));
    }

    @Test public void backgroundingClearsPrivateConversation() throws Exception {
        controller.pause();
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13));
        assertTrue(((ConversationLedger) field(activity, "ledger")).snapshot().isEmpty());
        assertFalse(allText().contains("How are you feeling today?"));
        controller.resume();
    }

    @Test public void longTranslationIsScrollableAndStatusRenderKeepsItsView() throws Exception {
        String full = "I am concerned about my family and would like time to explain everything carefully. ".repeat(12);
        addTranslatedTurn(Language.SPANISH, "Me preocupa mi familia.", full);
        layout(320, 480);
        RevealingTextView translation = revealingText(full);
        assertNotNull(translation);
        assertTrue(translation.getLineCount() > 10);
        CaptionScrollView scroll = (CaptionScrollView) field(panel("englishPanel"), "scroll");
        assertTrue(scroll.getChildAt(0).getHeight() > scroll.getHeight());
        invoke(activity, "setStatus", new Class<?>[]{String.class, String.class}, "Ready", "Listo");
        invoke(activity, "render");
        assertSame("Status updates must not restart or rebuild the caption", translation, revealingText(full));
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13));
        assertEquals(full.length(), translation.getRevealedEnd());
        assertTrue("Long translations must remain manually scrollable", scroll.getChildAt(0).getHeight() > scroll.getHeight());
    }

    @Test public void rapidNewTurnCancelsPreviousRevealWithoutLosingTranscript() throws Exception {
        String first = "This older translated turn should remain in the conversation after another person starts speaking. ".repeat(5);
        addTranslatedTurn(Language.SPANISH, "Primera frase.", first);
        layout(360, 640);
        RevealingTextView old = revealingText(first);
        assertRevealing(old);
        String second = "Esta es una nueva traducción que debe aparecer sin restaurar la animación anterior.";
        addTranslatedTurn(Language.ENGLISH, "A new turn.", second);
        layout(360, 640);
        assertFalse(old.isRevealing());
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13));
        assertTrue(allText().contains(first));
        assertTrue(allText().contains(second));
        for (RevealingTextView text : descendants((View) field(activity, "root"), RevealingTextView.class)) {
            assertFalse(text.isRevealing());
        }
    }

    @Test public void touchAndKeyboardStopRevealAndAutomaticFollowing() throws Exception {
        for (boolean keyboard : new boolean[]{false, true}) {
            String full = (keyboard ? "Keyboard " : "Touch ") + "can take over reading this long translation at any time. ".repeat(15);
            addTranslatedTurn(Language.SPANISH, "Quiero leer a mi propio ritmo.", full);
            layout(320, 480);
            RevealingTextView translation = revealingText(full);
            CaptionScrollView scroll = (CaptionScrollView) field(panel("englishPanel"), "scroll");
            assertRevealing(translation);
            if (keyboard) {
                scroll.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_UP));
            } else {
                MotionEvent touch = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 10, 10, 0);
                scroll.dispatchTouchEvent(touch);
                touch.recycle();
            }
            assertFalse(translation.isRevealing());
            assertEquals(full.length(), translation.getRevealedEnd());
            scroll.scrollTo(0, 0);
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13));
            assertEquals("User reading position must not be overridden", 0, scroll.getScrollY());
        }
    }

    @Test public void smallScreenAndLandscapeKeepBothScrollRegionsAndTalkButtonsUsable() throws Exception {
        for (int[] size : new int[][]{{320, 480}, {640, 320}, {640, 280}}) {
            RuntimeEnvironment.setQualifiers("w" + size[0] + "dp-h" + size[1] + "dp-" + (size[0] > size[1] ? "land" : "port"));
            RuntimeEnvironment.setFontScale(2f);
            controller.configurationChange();
            activity = controller.get();
            invoke(activity, "showConversation", new Class<?>[]{boolean.class}, true);
            layout(size[0], size[1]);
            for (String panelName : new String[]{"englishPanel", "spanishPanel"}) {
                Object panel = panel(panelName);
                View container = (View) field(panel, "container");
                View scroll = (View) field(panel, "scroll");
                Button talk = (Button) field(panel, "talk");
                float density = activity.getResources().getDisplayMetrics().density;
                assertTrue(panelName + " needs a useful caption viewport", scroll.getHeight() >= 64 * density);
                assertTrue(panelName + " needs a 48dp touch target", talk.getHeight() >= 48 * density);
                assertTrue(panelName + " talk button extends outside its panel", talk.getBottom() <= container.getHeight());
                assertTrue(panelName + " label is clipped at large font size",
                        talk.getLayout().getHeight() <= talk.getHeight() - talk.getCompoundPaddingTop() - talk.getCompoundPaddingBottom());
            }
            saveScreenshot("panels-" + size[0] + "x" + size[1] + "-font200.png");
        }
    }

    @Test public void recreationCancelsOldRevealAndDoesNotRestorePrivateCaptions() throws Exception {
        String full = "A private translation must not return after rotating the device. ".repeat(10);
        addTranslatedTurn(Language.SPANISH, "Una frase privada.", full);
        layout(360, 640);
        RevealingTextView old = revealingText(full);
        assertRevealing(old);
        controller.recreate();
        activity = controller.get();
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13));
        assertFalse(old.isRevealing());
        assertTrue(((ConversationLedger) field(activity, "ledger")).snapshot().isEmpty());
        assertFalse(allText().contains(full));
    }

    private void addTranslatedTurn(Language language, String source, String translation) throws Exception {
        invoke(activity, "prepareNextTurn");
        ConversationLedger ledger = (ConversationLedger) field(activity, "ledger");
        long epoch = ledger.epoch();
        long id = ledger.addSource(epoch, language, source);
        assertTrue(ledger.finish(epoch, id, translation, false));
        invoke(activity, "render");
    }

    private RevealingTextView revealingText(String text) throws Exception {
        for (RevealingTextView view : descendants((View) field(panel("englishPanel"), "captions"), RevealingTextView.class)) {
            if (view.getText().toString().equals(text)) return view;
        }
        return null;
    }

    private Object panel(String name) throws Exception { return field(activity, name); }

    private void assertRevealing(RevealingTextView text) throws Exception {
        assertTrue("canAnimate=" + text.canAnimate() + ", foreground=" + field(activity, "foreground")
                + ", follow=" + field(panel("englishPanel"), "followLatest")
                + ", pending=" + field(panel("englishPanel"), "pendingPosition")
                + ", shown=" + text.getRevealedEnd() + "/" + text.length(), text.isRevealing());
    }

    private void layout(int widthDp, int heightDp) throws Exception {
        View root = (View) field(activity, "root");
        float density = activity.getResources().getDisplayMetrics().density;
        int width = Math.round(widthDp * density);
        int height = Math.round(heightDp * density);
        root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
        root.layout(0, 0, width, height);
        root.getViewTreeObserver().dispatchOnPreDraw();
        for (CaptionScrollView scroll : descendants(root, CaptionScrollView.class)) {
            scroll.getViewTreeObserver().dispatchOnPreDraw();
        }
        assertEquals("The test must use the requested physical viewport width", width, root.getWidth());
        assertEquals("The test must use the requested physical viewport height", height, root.getHeight());
    }

    private void saveScreenshot(String name) throws Exception {
        View root = (View) field(activity, "root");
        Bitmap bitmap = Bitmap.createBitmap(root.getWidth(), root.getHeight(), Bitmap.Config.ARGB_8888);
        root.draw(new Canvas(bitmap));
        File directory = new File("build/reports/caption-screenshots");
        assertTrue(directory.isDirectory() || directory.mkdirs());
        try (FileOutputStream stream = new FileOutputStream(new File(directory, name))) {
            assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream));
        }
        bitmap.recycle();
    }

    private String allText() throws Exception {
        StringBuilder result = new StringBuilder();
        for (TextView text : descendants((View) field(activity, "root"), TextView.class)) {
            result.append(text.getText()).append('\n');
        }
        return result.toString();
    }

    private static <T> List<T> descendants(View view, Class<T> type) {
        List<T> result = new ArrayList<>();
        if (type.isInstance(view)) result.add(type.cast(view));
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) result.addAll(descendants(group.getChildAt(i), type));
        }
        return result;
    }

    private static Object field(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(target);
    }

    private static void invoke(Object target, String name) throws Exception {
        invoke(target, name, new Class<?>[0]);
    }

    private static void invoke(Object target, String name, Class<?>[] types, Object... arguments) throws Exception {
        Method method = target.getClass().getDeclaredMethod(name, types);
        method.setAccessible(true);
        method.invoke(target, arguments);
    }
}
