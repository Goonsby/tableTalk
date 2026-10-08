package org.tabletalk.ui;

import android.content.Context;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.widget.ScrollView;

/** Let native touch, keyboard, wheel and accessibility scrolling take over from reveal following. */
public final class CaptionScrollView extends ScrollView {
    private Runnable interaction;

    public CaptionScrollView(Context context) {
        super(context);
        setFillViewport(true);
        setSaveEnabled(false);
        setSmoothScrollingEnabled(false);
    }

    public void setOnUserInteraction(Runnable action) { interaction = action; }
    private void userInteraction() { if (interaction != null) interaction.run(); }

    @Override public boolean dispatchTouchEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) userInteraction();
        return super.dispatchTouchEvent(event);
    }

    @Override public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getAction() == KeyEvent.ACTION_DOWN) userInteraction();
        return super.dispatchKeyEvent(event);
    }

    @Override public boolean onGenericMotionEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_SCROLL) userInteraction();
        return super.onGenericMotionEvent(event);
    }

    @Override public boolean performAccessibilityAction(int action, Bundle arguments) {
        userInteraction();
        return super.performAccessibilityAction(action, arguments);
    }
}
