package com.eyepal.app.di

import android.content.Context
import com.eyepal.app.data.SettingsRepository
import com.eyepal.app.services.AccessibilityAnnouncer
import com.eyepal.app.services.ArcFaceEmbeddingEngine
import com.eyepal.app.services.CameraService
import com.eyepal.app.services.FaceRecognitionService
import com.eyepal.app.services.FloorDetectionService
import com.eyepal.app.services.GlassTouchpadHandler
import com.eyepal.app.services.GoogleGlassService
import com.eyepal.app.services.LyricPrompterService
import com.eyepal.app.services.MoondreamService
import com.eyepal.app.services.OCRService
import com.eyepal.app.services.OpenAIService
import com.eyepal.app.services.RealtimeWebRTCService
import com.eyepal.app.services.TranslationService
import okhttp3.OkHttpClient

class AppContainer(private val context: Context) {
    val settingsRepository by lazy { SettingsRepository(context) }
    val cameraService by lazy { CameraService(context) }
    val openAIService by lazy { OpenAIService(networkClient) }
    val moondreamService by lazy { MoondreamService(networkClient) }
    val ocrService by lazy { OCRService(context, settingsRepository) }
    val faceRecognitionService by lazy { FaceRecognitionService(context) }
    val arcFaceEmbeddingEngine by lazy { ArcFaceEmbeddingEngine(context) }
    val glassService by lazy { GoogleGlassService(context) }
    val glassTouchpadHandler by lazy { GlassTouchpadHandler() }
    val announcer by lazy { AccessibilityAnnouncer(context) }
    val translationService by lazy { TranslationService() }
    val realtimeWebRTCService by lazy { RealtimeWebRTCService(context) }
    val floorDetectionService by lazy { FloorDetectionService(context) }
    val lyricPrompterService by lazy { LyricPrompterService(networkClient) }

    val networkClient: OkHttpClient by lazy {
        NetworkModule.createPinnedClient()
    }
}