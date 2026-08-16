package com.eyepal.app.services

object LanguageDetector {
    fun detectLanguage(text: String): String {
        if (text.isBlank()) return "en"

        var cjk = 0
        var hangul = 0
        var latin = 0
        var cyrillic = 0
        var thai = 0
        var arabic = 0
        var devanagari = 0
        var latinExt = 0

        for (c in text) {
            val code = c.code
            when {
                // CJK Unified Ideographs
                (code in 0x4E00..0x9FFF) || (code in 0x3400..0x4DBF) ||
                        (code in 0xF900..0xFAFF) -> cjk++

                // Hiragana + Katakana (Japanese indicators)
                (code in 0x3040..0x309F) || (code in 0x30A0..0x30FF) -> cjk++

                // Hangul Jamo + Syllables
                (code in 0xAC00..0xD7AF) || (code in 0x1100..0x11FF) ||
                        (code in 0x3130..0x318F) -> hangul++

                // Thai script
                (code in 0x0E00..0x0E7F) -> thai++

                // Arabic script
                (code in 0x0600..0x06FF) || (code in 0xFB50..0xFDFF) ||
                        (code in 0xFE70..0xFEFF) -> arabic++

                // Devanagari (Hindi)
                (code in 0x0900..0x097F) -> devanagari++

                // Cyrillic
                (code in 0x0400..0x04FF) || (code in 0x0500..0x052F) -> cyrillic++

                // Basic Latin
                (code in 0x0041..0x005A) || (code in 0x0061..0x007A) -> latin++

                // Latin Extended (accented characters common in European languages)
                (code in 0x00C0..0x024F) || (code in 0x1E00..0x1EFF) ||
                        (code in 0x0100..0x017F) -> latinExt++
            }
        }

        val total = cjk + hangul + latin + cyrillic + thai + arabic + devanagari + latinExt
        if (total == 0) return "en"

        // Japanese: CJK + kana
        val hasKana = text.any { it.code in 0x3040..0x30FF }
        if (cjk > 0 && hasKana) return "ja"
        if (cjk > 0) return "zh"
        if (hangul > 0) return "ko"
        if (thai > 0) return "th"
        if (arabic > 0) return "ar"
        if (devanagari > 0) return "hi"
        if (cyrillic > 0) return "ru"
        if (latin + latinExt > 0) return "en"

        return "en"
    }

    fun languageName(code: String): String = when (code) {
        "en" -> "English"
        "zh" -> "Chinese"
        "ja" -> "Japanese"
        "ko" -> "Korean"
        "es" -> "Spanish"
        "fr" -> "French"
        "de" -> "German"
        "it" -> "Italian"
        "pt" -> "Portuguese"
        "ru" -> "Russian"
        "ar" -> "Arabic"
        "hi" -> "Hindi"
        "th" -> "Thai"
        "tr" -> "Turkish"
        "nl" -> "Dutch"
        "pl" -> "Polish"
        "sv" -> "Swedish"
        "vi" -> "Vietnamese"
        else -> code
    }
}
