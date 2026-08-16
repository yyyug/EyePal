package com.eyepal.app.viewmodels

import android.app.Application
import android.graphics.Bitmap
import androidx.camera.view.PreviewView
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.viewModelScope
import com.eyepal.app.EyePalApplication
import com.eyepal.app.R
import com.eyepal.app.services.GoogleGlassState
import com.eyepal.app.services.LanguageDetector
import com.eyepal.app.services.OAuthService
import com.eyepal.app.services.UnauthorizedException
import kotlinx.coroutines.launch
import java.util.Locale

class DetailsRecognitionViewModel(application: Application) : AndroidViewModel(application) {
    private fun str(resId: Int): String = getApplication<Application>().getString(resId)
    private fun str(resId: Int, vararg args: Any?): String = getApplication<Application>().getString(resId, *args)

    val statusText = mutableStateOf(str(R.string.instructions_scene))
    val descriptionText = mutableStateOf("")
    val followUpQuestion = mutableStateOf("")
    val isProcessing = mutableStateOf(false)
    val isSignedIn = mutableStateOf(false)
    val errorMessage = mutableStateOf<String?>(null)
    val showOAuthLogin = mutableStateOf(false)
    val capturedImage = mutableStateOf<Bitmap?>(null)

    private val container = (application as EyePalApplication).container
    val camera = container.cameraService
    private val openAI = container.openAIService
    private val glassService = container.glassService
    private val announcer = container.announcer
    private var lastImage: Bitmap? = null
    private var fullResImage: Bitmap? = null
    private val baseSystemPrompt = buildString {
        append("You are a concise visual assistant for a blind user. ")
        append("If visible text is present, read it exactly. ")
        append("Describe people, objects, layout, and orientation cues. ")
        append("Be concise and specific. ")
        append("Do not use markdown or double asterisks.")
    }
    private var lastPrompt = buildPromptWithLocale(baseSystemPrompt)
    private var storedLifecycleOwner: LifecycleOwner? = null
    private var storedPreview: PreviewView? = null
    private var cameraStarted = false
    private val conversationHistory = java.util.Collections.synchronizedList(mutableListOf<Map<String, Any>>())

    init {
        isSignedIn.value = OAuthService.isSignedIn(application)
    }

    fun startCamera(previewView: android.view.View) {
        if (GoogleGlassState.useGlassCamera.value || cameraStarted) return
        val lo = (previewView.context as? LifecycleOwner) ?: return
        storedLifecycleOwner = lo
        storedPreview = previewView as? PreviewView
        cameraStarted = true
        camera.startCamera(lo, storedPreview!!)
    }

    fun startCamera() {
        if (cameraStarted) return
        val lo = storedLifecycleOwner ?: return
        val pv = storedPreview ?: return
        if (GoogleGlassState.useGlassCamera.value) return
        cameraStarted = true
        camera.startCamera(lo, pv)
    }

    fun stopCamera() { cameraStarted = false; camera.stopCamera() }

    fun signIn() {
        showOAuthLogin.value = true
    }

    fun onOAuthSuccess() {
        val context = getApplication<Application>()
        isSignedIn.value = OAuthService.isSignedIn(context)
        showOAuthLogin.value = false
        errorMessage.value = null
    }

    fun onOAuthDismiss() {
        showOAuthLogin.value = false
    }

    fun capturePhoto() { lastPrompt = buildPromptWithLocale(baseSystemPrompt); doCapture() }

    fun capturePresetPhoto(prompt: String) { lastPrompt = buildPromptWithLocale("$baseSystemPrompt $prompt"); doCapture() }

    fun retakePhoto() {
        capturedImage.value = null
    }

    fun resendFullRes() {
        val fullRes = fullResImage ?: return
        if (isProcessing.value) return
        val context = getApplication<Application>()
        val accessToken = OAuthService.getStoredAccessToken(context)
        if (accessToken.isEmpty()) {
            errorMessage.value = str(R.string.status_please_sign_in_first)
            return
        }
        isProcessing.value = true
        statusText.value = str(R.string.status_resending_full_res)
        viewModelScope.launch {
            try {
                val accountID = OAuthService.getAccountID(context)
                val result = try {
                    openAI.describeImageCodexWithHistory(fullRes, accessToken, accountID, lastPrompt, conversationHistory)
                } catch (e: UnauthorizedException) {
                    if (OAuthService.refreshToken(context)) {
                        val newToken = OAuthService.getStoredAccessToken(context)
                        openAI.describeImageCodexWithHistory(fullRes, newToken, accountID, lastPrompt, conversationHistory)
                    } else {
                        throw Exception(str(R.string.error_auth_expired))
                    }
                }
                conversationHistory.add(mapOf("role" to "user", "content" to lastPrompt))
                conversationHistory.add(mapOf("role" to "assistant", "content" to result))
                descriptionText.value = result
                statusText.value = str(R.string.status_full_res_ready)
                announcer.announce(result)
            } catch (e: Exception) { errorMessage.value = e.message; statusText.value = str(R.string.status_failed, e.message) }
            isProcessing.value = false
        }
    }

    private fun buildPromptWithLocale(basePrompt: String): String {
        val langCode = Locale.getDefault().language
        val languageName = LanguageDetector.languageName(langCode)
        return "$basePrompt Respond in $languageName."
    }

    private fun doCapture() {
        if (isProcessing.value) return
        val context = getApplication<Application>()
        val accessToken = OAuthService.getStoredAccessToken(context)
        if (accessToken.isEmpty()) {
            errorMessage.value = str(R.string.status_please_sign_in_first)
            return
        }
        isProcessing.value = true
        statusText.value = str(R.string.status_describing_photo)
        viewModelScope.launch {
            try {
                var bitmap: android.graphics.Bitmap? = null
                for (attempt in 1..3) {
                    bitmap = if (GoogleGlassState.useGlassCamera.value) glassService.capturePhotoFromGlasses() else camera.capturePhoto()
                    if (bitmap != null) break
                    kotlinx.coroutines.delay(500)
                }
                if (bitmap == null) throw Exception(str(R.string.error_camera_not_ready))
                fullResImage = bitmap
                lastImage = bitmap
                capturedImage.value = bitmap
                val accountID = OAuthService.getAccountID(context)
                val result = try {
                    openAI.describeImageCodexWithHistory(bitmap, accessToken, accountID, lastPrompt, conversationHistory)
                } catch (e: UnauthorizedException) {
                    if (OAuthService.refreshToken(context)) {
                        val newToken = OAuthService.getStoredAccessToken(context)
                        openAI.describeImageCodexWithHistory(bitmap, newToken, accountID, lastPrompt, conversationHistory)
                    } else {
                        throw Exception(str(R.string.error_auth_expired))
                    }
                }
                conversationHistory.add(mapOf("role" to "user", "content" to lastPrompt))
                conversationHistory.add(mapOf("role" to "assistant", "content" to result))
                descriptionText.value = result
                statusText.value = str(R.string.status_details_ready)
                announcer.announce(result)
            } catch (e: Exception) { errorMessage.value = e.message; statusText.value = str(R.string.status_failed, e.message) }
            isProcessing.value = false
        }
    }

    fun submitFollowUp() {
        val question = followUpQuestion.value.trim()
        if (question.isEmpty() || isProcessing.value) return
        isProcessing.value = true
        followUpQuestion.value = ""
        val context = getApplication<Application>()
        viewModelScope.launch {
            try {
                val image = lastImage ?: throw Exception(str(R.string.error_take_photo_first))
                val accessToken = OAuthService.getStoredAccessToken(context)
                if (accessToken.isEmpty()) { throw Exception(str(R.string.status_please_sign_in_first)) }
                val accountID = OAuthService.getAccountID(context)
                val localisedQuestion = buildPromptWithLocale(question)
                val result = try {
                    openAI.describeImageCodexWithHistory(image, accessToken, accountID, localisedQuestion, conversationHistory)
                } catch (e: UnauthorizedException) {
                    if (OAuthService.refreshToken(context)) {
                        val newToken = OAuthService.getStoredAccessToken(context)
                        openAI.describeImageCodexWithHistory(image, newToken, accountID, localisedQuestion, conversationHistory)
                    } else {
                        throw Exception(str(R.string.error_auth_expired))
                    }
                }
                conversationHistory.add(mapOf("role" to "user", "content" to question))
                conversationHistory.add(mapOf("role" to "assistant", "content" to result))
                descriptionText.value = result
                statusText.value = str(R.string.status_follow_up_ready)
                announcer.announce(result)
            } catch (e: Exception) { errorMessage.value = e.message }
            isProcessing.value = false
        }
    }
}