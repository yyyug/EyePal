package com.eyepal.app.services

enum class GemmaModelKind(
    val code: String,
    val displayName: String,
    val fileName: String,
    val directoryName: String,
    val repoPath: String
) {
    E2B(
        code = "e2b",
        displayName = "Gemma 4 2B ~2.6GB",
        fileName = "gemma-4-E2B-it.litertlm",
        directoryName = "gemma-4-E2B-it-litert-lm",
        repoPath = "litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm"
    ),
    E4B(
        code = "e4b",
        displayName = "Gemma 4 4B ~3.5GB",
        fileName = "gemma-4-E4B-it.litertlm",
        directoryName = "gemma-4-E4B-it-litert-lm",
        repoPath = "litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm"
    );

    /**
     * Candidate sources, fastest-first. `hf-mirror.com` is a drop-in Hugging Face
     * mirror that is typically much faster from China / parts of Taiwan and
     * South-East Asia; the official host is the fallback.
     */
    val downloadUrls: List<String>
        get() = listOf(
            "https://hf-mirror.com/$repoPath",
            "https://huggingface.co/$repoPath"
        )

    companion object {
        fun fromCode(code: String): GemmaModelKind? = entries.find { it.code == code }
    }
}
