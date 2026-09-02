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

    suspend fun generateCaption(image: Bitmap, length: QuickCaptionLength, kind: GemmaModelKind? = null): String {
        val prompt = when (length) {
            QuickCaptionLength.SHORT -> "Describe this image in one short sentence."
            QuickCaptionLength.NORMAL -> "Describe this image in 1 or 2 concise sentences."
            QuickCaptionLength.DETAILED -> "Describe this image in detail, in a few sentences."
        }
        return run(prompt, image, kind)
    }

    suspend fun queryImage(image: Bitmap, question: String, enforceSingleSentenceResponse: Boolean, kind: GemmaModelKind? = null): String {
        val prompt = if (enforceSingleSentenceResponse) "$question Respond with one sentence." else question
        return run(prompt, image, kind)
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
