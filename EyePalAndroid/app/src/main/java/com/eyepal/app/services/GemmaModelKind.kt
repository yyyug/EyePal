package com.eyepal.app.services

enum class GemmaModelKind(
    val code: String,
    val displayName: String,
    val fileName: String,
    val directoryName: String,
    val downloadUrl: String
) {
    E2B(
        code = "e2b",
        displayName = "Gemma 4 2B",
        fileName = "gemma-4-E2B-it.litertlm",
        directoryName = "gemma-4-E2B-it-litert-lm",
        downloadUrl = "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm"
    ),
    E4B(
        code = "e4b",
        displayName = "Gemma 4 4B",
        fileName = "gemma-4-E4B-it.litertlm",
        directoryName = "gemma-4-E4B-it-litert-lm",
        downloadUrl = "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm"
    );

    companion object {
        fun fromCode(code: String): GemmaModelKind? = entries.find { it.code == code }
    }
}
