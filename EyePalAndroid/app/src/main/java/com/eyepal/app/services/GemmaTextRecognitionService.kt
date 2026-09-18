package com.eyepal.app.services

import android.content.Context
import android.graphics.Bitmap
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.eyepal.app.viewmodels.QuickCaptionLength
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

class GemmaTextRecognitionService(private val context: Context) {

    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var currentModelPath: String? = null

    fun canRun(selectedKind: GemmaModelKind? = null): Boolean = modelManager.modelFileFor(selectedKind) != null

    private val modelManager: GemmaModelManager
        get() = context.applicationContext.let { app ->
            (app as? com.eyepal.app.EyePalApplication)?.container?.gemmaModelManager
                ?: GemmaModelManager(context.applicationContext)
        }

    /** True when the app's UI locale is Chinese (zh-Hans, zh-Hant, zh-HK, zh-TW, ...). */
    private val prefersChinese: Boolean
        get() {
            val locales = context.resources.configuration.locales
            val language = if (locales.isEmpty) "en" else locales[0].language
            return language.startsWith("zh", ignoreCase = true)
        }

    suspend fun generateCaption(image: Bitmap, length: QuickCaptionLength, kind: GemmaModelKind? = null): String {
        val prompt = if (prefersChinese) {
            when (length) {
                QuickCaptionLength.SHORT -> "請用一至兩句中文描述這張圖片。"
                QuickCaptionLength.NORMAL -> "請用三至五句中文描述這張圖片。"
                QuickCaptionLength.DETAILED -> "請用六句或以上中文詳細描述這張圖片，內容越詳細越好。"
            }
        } else {
            when (length) {
                QuickCaptionLength.SHORT -> "Describe this image in 1 to 2 sentences."
                QuickCaptionLength.NORMAL -> "Describe this image in 3 to 5 sentences."
                QuickCaptionLength.DETAILED -> "Describe this image in 6 or more sentences with as much detail as possible."
            }
        }
        return run(prompt, image, kind)
    }

    suspend fun queryImage(image: Bitmap, question: String, enforceSingleSentenceResponse: Boolean, kind: GemmaModelKind? = null): String {
        val localized = localizePrompt(question)
        val prompt = if (enforceSingleSentenceResponse) "$localized Respond with one sentence." else localized
        return run(prompt, image, kind)
    }

    /** The built-in presets are English; on a Chinese UI send Chinese to Gemma. */
    private fun localizePrompt(question: String): String {
        if (!prefersChinese) return question
        return when (question) {
            "Describe the main product with brand, name and function",
            "Describe the main product in this image with 1 or 2 sentences, including its brand, name and primary function" ->
                "請用一至兩句描述圖片中的主要產品，包括品牌、名稱和主要功能。"
            "Describe the food layout on the plate using clock positions",
            "Describe the layout of the food on the plate or tray. Use clock positions or spatial terms" ->
                "請描述食物在盤子或托盤上的擺放位置，使用時鐘方向或空間詞語。"
            "Read the visible text in the image",
            "Describe the alphanumeric text visible in the image" ->
                "請描述圖片中可見的英數字文字。"
            else -> question
        }
    }

    private suspend fun run(prompt: String, image: Bitmap, kind: GemmaModelKind? = null): String = withContext(Dispatchers.Default) {
        val modelFile = modelManager.modelFileFor(kind)
            ?: throw Exception(context.getString(com.eyepal.app.R.string.gemma_error_no_model))
        if (currentModelPath != modelFile.absolutePath) close()
        val conversation = readyConversation(modelFile.absolutePath)
        val imagePath = writeImageToCache(image)

        val message = conversation.sendMessage(
            Contents.of(
                Content.ImageFile(imagePath),
                Content.Text(prompt)
            )
        )
        val text = message.toString().trim()
        if (text.isEmpty()) {
            throw Exception(context.getString(com.eyepal.app.R.string.gemma_error_empty_response))
        }
        text
    }

    private suspend fun readyConversation(modelPath: String): Conversation = withContext(Dispatchers.Default) {
        val existing = conversation
        if (existing != null && engine != null) return@withContext existing

        if (engine == null) {
            val config = EngineConfig(
                modelPath = modelPath,
                backend = Backend.GPU(),
                visionBackend = Backend.CPU(),
                cacheDir = context.cacheDir.path
            )
            Engine(config).also { it.initialize() }.also { engine = it }
            currentModelPath = modelPath
        }
        val conv = engine!!.createConversation()
        conversation = conv
        conv
    }

    private fun writeImageToCache(image: Bitmap): String {
        val file = File(context.cacheDir, "gemma_${System.nanoTime()}.jpg")
        FileOutputStream(file).use { out ->
            image.compress(Bitmap.CompressFormat.JPEG, 90, out)
        }
        return file.absolutePath
    }

    fun close() {
        try { conversation?.close() } catch (_: Exception) {}
        try { engine?.close() } catch (_: Exception) {}
        conversation = null
        engine = null
        currentModelPath = null
    }
}
