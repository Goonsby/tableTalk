package org.tabletalk.ui;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.content.Context;
import android.database.ContentObserver;
import android.graphics.Canvas;
import android.graphics.Path;
import android.graphics.text.LineBreaker;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.Layout;
import android.view.Gravity;
import android.view.accessibility.AccessibilityManager;
import android.view.animation.LinearInterpolator;
import android.widget.TextView;
import org.tabletalk.core.TranslationReveal;

/** Full text and stable wrapping from the outset; only painting is revealed word by word. */
public final class RevealingTextView extends TextView {
    private final Path revealedPath = new Path();
    private ValueAnimator animator;
    private int revealedEnd;
    private final AccessibilityManager accessibility;
    private final AccessibilityManager.AccessibilityStateChangeListener accessibilityListener = enabled -> {
        if (enabled) finishReveal();
    };
    private final ContentObserver motionObserver = new ContentObserver(new Handler(Looper.getMainLooper())) {
        @Override public void onChange(boolean selfChange) {
            if (!canAnimate()) finishReveal();
        }
    };

    public RevealingTextView(Context context) {
        super(context);
        accessibility = context.getSystemService(AccessibilityManager.class);
        setGravity(Gravity.TOP | Gravity.START);
        setHorizontallyScrolling(false);
        setSingleLine(false);
        setEllipsize(null);
        // These compile-time constants are also the values supported by TextView on API 23+.
        setBreakStrategy(LineBreaker.BREAK_STRATEGY_SIMPLE);
        setHyphenationFrequency(LineBreaker.HYPHENATION_FREQUENCY_NONE);
        setSaveEnabled(false);
        // Accessibility always reads the complete translation, never animation fragments.
        setAccessibilityLiveRegion(ACCESSIBILITY_LIVE_REGION_NONE);
    }

    public boolean canAnimate() {
        return (accessibility == null || !accessibility.isEnabled())
                && Settings.Global.getFloat(getContext().getContentResolver(),
                    Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
                && (Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled());
    }

    public void startReveal(Runnable progress) {
        finishReveal();
        int[] ends = TranslationReveal.wordEnds(getText().toString());
        if (ends.length < 2 || !canAnimate()) return;
        revealedEnd = ends[0];
        ValueAnimator next = ValueAnimator.ofInt(1, ends.length);
        animator = next;
        next.setDuration(TranslationReveal.durationMillis(ends.length));
        next.setInterpolator(new LinearInterpolator());
        next.addUpdateListener(value -> {
            if (animator != next) return;
            if (!canAnimate()) { finishReveal(); return; }
            int end = ends[(int) value.getAnimatedValue() - 1];
            if (end != revealedEnd) {
                revealedEnd = end;
                invalidate();
                if (progress != null) progress.run();
            }
        });
        next.addListener(new AnimatorListenerAdapter() {
            @Override public void onAnimationEnd(Animator animation) {
                if (animator == next) { animator = null; revealedEnd = length(); invalidate(); }
            }
        });
        invalidate();
        next.start();
    }

    /** Cancel callbacks, expose the complete transcript, and leave the scroll position alone. */
    public void finishReveal() {
        ValueAnimator previous = animator;
        animator = null;
        if (previous != null) {
            previous.removeAllUpdateListeners();
            previous.removeAllListeners();
            previous.cancel();
        }
        revealedEnd = length();
        invalidate();
    }

    public boolean isRevealing() { return animator != null; }
    public int getRevealedEnd() { return revealedEnd; }
    public int revealedLineBottom() {
        Layout layout = getLayout();
        if (layout == null) return 0;
        int offset = Math.max(0, Math.min(length(), revealedEnd) - 1);
        return getExtendedPaddingTop() + layout.getLineBottom(layout.getLineForOffset(offset));
    }

    @Override protected void onTextChanged(CharSequence text, int start, int before, int count) {
        finishReveal();
        super.onTextChanged(text, start, before, count);
    }

    @Override protected void onDraw(Canvas canvas) {
        Layout layout = getLayout();
        if (animator == null || revealedEnd >= length() || layout == null) {
            super.onDraw(canvas);
            return;
        }
        revealedPath.reset();
        layout.getSelectionPath(0, revealedEnd, revealedPath);
        revealedPath.offset(getTotalPaddingLeft(), getExtendedPaddingTop());
        int save = canvas.save();
        canvas.clipPath(revealedPath);
        super.onDraw(canvas);
        canvas.restoreToCount(save);
    }

    @Override protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        if (accessibility != null) accessibility.addAccessibilityStateChangeListener(accessibilityListener);
        getContext().getContentResolver().registerContentObserver(
                Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, motionObserver);
    }

    @Override protected void onDetachedFromWindow() {
        finishReveal();
        if (accessibility != null) accessibility.removeAccessibilityStateChangeListener(accessibilityListener);
        getContext().getContentResolver().unregisterContentObserver(motionObserver);
        super.onDetachedFromWindow();
    }
}
