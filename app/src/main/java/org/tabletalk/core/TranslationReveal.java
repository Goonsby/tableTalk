package org.tabletalk.core;

import java.util.ArrayList;
import java.util.List;

/** Text boundaries and timing shared by translation reveal views. */
public final class TranslationReveal {
    private TranslationReveal() { }

    /**
     * Returns increasing UTF-16 offsets after each whitespace-delimited word and
     * its trailing whitespace. The last offset always includes the entire text.
     * Punctuation, contractions, and unbroken tokens stay together. Scanning code
     * points and retaining whole tokens also preserves emoji sequences and
     * combining marks without depending on the platform's Unicode word iterator.
     */
    public static int[] wordEnds(String text) {
        if (text == null || text.isEmpty()) return new int[0];
        List<Integer> ends = new ArrayList<>();
        boolean hasWord = false;
        boolean afterSpace = false;
        for (int offset = 0; offset < text.length();) {
            int codePoint = text.codePointAt(offset);
            boolean space = Character.isWhitespace(codePoint) || Character.isSpaceChar(codePoint);
            if (!space) {
                // A combining mark can extend even a space; never reveal it alone.
                if (hasWord && afterSpace && !continuesGrapheme(codePoint)) ends.add(offset);
                hasWord = true;
                afterSpace = false;
            } else if (hasWord) {
                afterSpace = true;
            }
            offset += Character.charCount(codePoint);
        }
        ends.add(text.length());
        int[] result = new int[ends.size()];
        for (int index = 0; index < result.length; index++) result[index] = ends.get(index);
        return result;
    }

    /** A gentle cadence with a short minimum and a bounded wait for long text. */
    public static long durationMillis(int wordCount) {
        if (wordCount <= 0) return 0L;
        return Math.max(600L, Math.min(12_000L, wordCount * 110L));
    }

    private static boolean continuesGrapheme(int codePoint) {
        int type = Character.getType(codePoint);
        return type == Character.NON_SPACING_MARK
                || type == Character.COMBINING_SPACING_MARK
                || type == Character.ENCLOSING_MARK
                || codePoint == 0x200D
                || (codePoint >= 0x1F3FB && codePoint <= 0x1F3FF)
                || (codePoint >= 0xE0020 && codePoint <= 0xE007F);
    }
}
