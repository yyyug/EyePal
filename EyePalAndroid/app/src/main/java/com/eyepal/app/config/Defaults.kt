package com.eyepal.app.config

import com.eyepal.app.models.AppFeature

object Defaults {
    const val MODEL_ID = "gpt-5.4-mini"
    const val LYRIC_LLM_PROVIDER = "CODEX"
    const val CAPTION_LENGTH = "normal"
    const val CONTINUOUS_INTERVAL_MS = 3000
    const val QUICK_TRIGGER_MODE = "time"
    const val TRANSLATION_TARGET = "zh"
    const val FACE_MATCH_THRESHOLD = 0.65f
    const val FACE_MATCH_MARGIN = 0.02f
    const val FACE_MATCH_FRAME_THRESHOLD = 1
    const val FACE_SPEECH_COOLDOWN = 2.5f
    const val FACE_DUPLICATE_WARNING_THRESHOLD = 0.60f
    const val SAME_IDENTITY_SIMILARITY = 0.95f
    const val SAMPLE_DISTINCT_SIMILARITY = 0.995f
    const val ENROLLMENT_MINIMUM_FACE_SIZE = 112
    const val BORDERLINE_KNOWN_THRESHOLD = 0.90f
    const val UNKNOWN_SUGGESTION_FRAME_THRESHOLD = 6
    const val UNKNOWN_SUGGESTION_MIN_INTERVAL_MS = 10_000L
    const val MINIMUM_ENROLLMENT_SAMPLES = 3
    const val READ_TEXT_SPEECH_COOLDOWN = 2.5f
    const val OCR_ENGINE = "mlkit"
    const val SUGGEST_UNKNOWN_FACES = true
    const val QUICK_ACTION_CONTROL_STYLE = "onScreenButtons"
    const val DETAILS_ACTION_CONTROL_STYLE = "singleAdjustableControl"
    const val LYRIC_ADVANCE_OFFSET = 0f
    const val CHAT_INTERPRETER_LANG_A = "en"
    const val CHAT_INTERPRETER_LANG_B = "ja"
    val FEATURE_ORDER: List<String> = AppFeature.defaultOrder.map { it.name }
}
