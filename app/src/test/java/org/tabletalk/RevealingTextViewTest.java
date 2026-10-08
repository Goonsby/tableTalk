package org.tabletalk;

import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.Looper;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.view.accessibility.AccessibilityManager;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.LinearLayout;
import java.time.Duration;
import java.io.File;
import java.io.FileOutputStream;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.android.controller.ActivityController;
import org.tabletalk.ui.RevealingTextView;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
@LooperMode(LooperMode.Mode.PAUSED)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class RevealingTextViewTest {
    private ActivityController<Activity> controller;
    private Activity activity;
    private LinearLayout container;
    private RevealingTextView caption;

    @Before public void createView() {
        controller = Robolectric.buildActivity(Activity.class).setup().visible();
        activity = controller.get();
        Settings.Global.putFloat(activity.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
        shadowOf(activity.getSystemService(AccessibilityManager.class)).setEnabled(false);
        container = new LinearLayout(activity);
        container.setOrientation(LinearLayout.VERTICAL);
        caption = new RevealingTextView(activity);
        caption.setTextSize(24);
        container.addView(caption);
        activity.setContentView(container);
    }

    @After public void destroyView() {
        controller.pause().stop().destroy();
        RuntimeEnvironment.setFontScale(1f);
    }

    @Test public void largeFontCaptionsKeepCompleteWrappingAndStableRevealInNarrowAndWideViews() throws Exception {
        RuntimeEnvironment.setFontScale(2f);
        caption.setTextSize(24);
        for (int widthDp : new int[]{240, 560}) {
            String full = "Me gustaría explicar lo que pasó ayer sin perder ninguna palabra. "
                    + "We can talk about your family, your health, and everything that matters.\n\n"
                    + "Anticonstitucionalmente: una palabra larga también debe caber. ".repeat(5);
            caption.setText(full);
            measureCaption(widthDp);
            int height = caption.getHeight();
            int lines = caption.getLineCount();
            assertTrue("Two-times font size must wrap into multiple lines", lines > 6);
            assertEquals("The final word must have a line in the layout", full.length(),
                    caption.getLayout().getLineEnd(lines - 1));
            assertNull("Long captions must never use ellipsis", caption.getEllipsize());
            caption.startReveal(null);
            assertTrue(caption.isRevealing());
            saveCaptionScreenshot("caption-font200-width" + widthDp + "-partial.png");
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13));
            measureCaption(widthDp);
            assertEquals("Reveal must keep the complete caption height", height, caption.getHeight());
            assertEquals("Reveal must keep line wrapping stable", lines, caption.getLineCount());
            assertEquals(full.length(), caption.getRevealedEnd());
            AccessibilityNodeInfo node = caption.createAccessibilityNodeInfo();
            assertEquals(full, node.getText().toString());
            node.recycle();
            saveCaptionScreenshot("caption-font200-width" + widthDp + "-complete.png");
        }
    }

    @Test public void englishAndSpanishWrapCompletelyWithoutChangingLayoutDuringReveal() {
        for (String sentence : new String[]{
                "I have been worried about my family, and I would like some time to talk about what happened yesterday. ",
                "Me preocupa mi familia y me gustaría hablar con usted acerca de lo que sucedió ayer por la tarde. "}) {
            String full = sentence.repeat(8);
            caption.setText(full);
            measureCaption(240);
            int height = caption.getMeasuredHeight();
            int lines = caption.getLineCount();
            assertTrue("Long captions need multiple lines", lines > 8);
            assertNull(caption.getEllipsize());
            caption.startReveal(null);
            assertTrue(caption.isRevealing());
            assertTrue(caption.getRevealedEnd() < full.length());
            assertEquals(full, caption.getText().toString());
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(250));
            measureCaption(240);
            assertEquals(height, caption.getMeasuredHeight());
            assertEquals(lines, caption.getLineCount());
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(13));
            assertFalse(caption.isRevealing());
            assertEquals(full.length(), caption.getRevealedEnd());
            assertEquals(height, caption.getMeasuredHeight());
        }
    }

    @Test public void accessibilityAndTextObserversAlwaysReceiveCompleteText() {
        String full = "¿Le gustaría hablar con su familia hoy? We can take all the time you need.";
        AtomicInteger textChanges = new AtomicInteger();
        caption.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            public void onTextChanged(CharSequence s, int start, int before, int count) { textChanges.incrementAndGet(); }
            public void afterTextChanged(Editable s) {}
        });
        caption.setText(full);
        measureCaption(240);
        caption.startReveal(null);
        for (int frame = 0; frame < 20; frame++) {
            AccessibilityNodeInfo node = caption.createAccessibilityNodeInfo();
            assertEquals(full, node.getText().toString());
            assertEquals(View.ACCESSIBILITY_LIVE_REGION_NONE, caption.getAccessibilityLiveRegion());
            node.recycle();
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50));
        }
        assertEquals("Animation must never mutate accessible text", 1, textChanges.get());
    }

    @Test public void replacingTextCancelsOldAnimationAndCallbacks() {
        caption.setText("This older translation should stop its callbacks immediately after replacement.");
        measureCaption(240);
        AtomicInteger updates = new AtomicInteger();
        caption.startReveal(updates::incrementAndGet);
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(150));
        caption.setText("A new completed translation.");
        int stoppedAt = updates.get();
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(8));
        assertEquals(stoppedAt, updates.get());
        assertFalse(caption.isRevealing());
        assertEquals(caption.length(), caption.getRevealedEnd());
        assertEquals("A new completed translation.", caption.getText().toString());
    }

    @Test public void detachingCancelsAnimationAndCallbacks() {
        caption.setText("A long translation can be interrupted when its activity leaves the foreground.");
        measureCaption(240);
        AtomicInteger updates = new AtomicInteger();
        caption.startReveal(updates::incrementAndGet);
        container.removeView(caption);
        int stoppedAt = updates.get();
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(8));
        assertFalse(caption.isRevealing());
        assertEquals(stoppedAt, updates.get());
        assertEquals(caption.length(), caption.getRevealedEnd());
    }

    @Test public void disabledMotionDisplaysEverythingImmediately() {
        Settings.Global.putFloat(activity.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 0f);
        caption.setText("This complete translation must remain immediately readable with animations disabled.");
        caption.startReveal(null);
        assertFalse(caption.canAnimate());
        assertFalse(caption.isRevealing());
        assertEquals(caption.length(), caption.getRevealedEnd());
    }

    @Test public void enablingReducedMotionMidRevealFinishesWithoutWaiting() {
        caption.setText("This complete translation should appear as soon as reduced motion is enabled.");
        measureCaption(240);
        caption.startReveal(null);
        assertTrue(caption.isRevealing());
        Settings.Global.putFloat(activity.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 0f);
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(40));
        assertFalse(caption.isRevealing());
        assertEquals(caption.length(), caption.getRevealedEnd());
    }

    @Test public void screenReaderModeDisplaysEverythingImmediately() {
        shadowOf(activity.getSystemService(AccessibilityManager.class)).setEnabled(true);
        caption.setText("Screen reader users receive this complete translation in one semantic update.");
        caption.startReveal(null);
        assertFalse(caption.isRevealing());
        assertEquals(caption.length(), caption.getRevealedEnd());
    }

    @Test public void canvasMaskPaintsOnlyRevealedWordsWhilePreservingCompleteLayout() throws Exception {
        caption.setTextColor(android.graphics.Color.BLACK);
        caption.setText("Podemos hablar con calma sobre su familia. We can take time to talk about everything that matters today.");
        measureCaption(240);
        caption.startReveal(null);
        assertTrue(caption.isRevealing());
        Bitmap partial = drawCaption();
        int partialPixels = paintedPixels(partial);
        int height = caption.getHeight();
        caption.finishReveal();
        Bitmap complete = drawCaption();
        int fullPixels = paintedPixels(complete);
        assertTrue("The first revealed word must actually be painted", partialPixels > 0);
        assertTrue("The mask must withhold later words", fullPixels > partialPixels * 3);
        assertEquals(height, caption.getHeight());
        partial = onWhite(partial);
        complete = onWhite(complete);
        File directory = new File("build/reports/caption-screenshots");
        assertTrue(directory.isDirectory() || directory.mkdirs());
        try (FileOutputStream stream = new FileOutputStream(new File(directory, "caption-partial.png"))) {
            assertTrue(partial.compress(Bitmap.CompressFormat.PNG, 100, stream));
        }
        try (FileOutputStream stream = new FileOutputStream(new File(directory, "caption-complete.png"))) {
            assertTrue(complete.compress(Bitmap.CompressFormat.PNG, 100, stream));
        }
        partial.recycle();
        complete.recycle();
    }

    private Bitmap drawCaption() {
        Bitmap bitmap = Bitmap.createBitmap(caption.getWidth(), caption.getHeight(), Bitmap.Config.ARGB_8888);
        caption.draw(new Canvas(bitmap));
        return bitmap;
    }

    private void saveCaptionScreenshot(String name) throws Exception {
        Bitmap bitmap = onWhite(drawCaption());
        File directory = new File("build/reports/caption-screenshots");
        assertTrue(directory.isDirectory() || directory.mkdirs());
        try (FileOutputStream stream = new FileOutputStream(new File(directory, name))) {
            assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream));
        }
        bitmap.recycle();
    }

    private Bitmap onWhite(Bitmap original) {
        Bitmap result = Bitmap.createBitmap(original.getWidth(), original.getHeight(), Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(result);
        canvas.drawColor(android.graphics.Color.WHITE);
        canvas.drawBitmap(original, 0, 0, null);
        original.recycle();
        return result;
    }

    private int paintedPixels(Bitmap bitmap) {
        int count = 0;
        for (int y = 0; y < bitmap.getHeight(); y++) {
            for (int x = 0; x < bitmap.getWidth(); x++) {
                if ((bitmap.getPixel(x, y) >>> 24) != 0) count++;
            }
        }
        return count;
    }

    private void measureCaption(int widthDp) {
        int width = Math.round(widthDp * activity.getResources().getDisplayMetrics().density);
        caption.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
        caption.layout(0, 0, width, caption.getMeasuredHeight());
    }
}
