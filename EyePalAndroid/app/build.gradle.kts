plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

tasks.withType<KotlinCompile> {
    compilerOptions {
        freeCompilerArgs.add("-opt-in=androidx.xr.projected.experimental.ExperimentalProjectedApi")
    }
}

android {
    namespace = "com.eyepal.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.eyepal.app"
        minSdk = 28
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"
        ndk { abiFilters += listOf("arm64-v8a") }
        resConfigs("en", "zh")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    // Compose
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.navigation:navigation-compose:2.9.8")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")

    // CameraX
    implementation("androidx.camera:camera-core:1.6.1")
    implementation("androidx.camera:camera-camera2:1.6.1")
    implementation("androidx.camera:camera-lifecycle:1.6.1")
    implementation("androidx.camera:camera-view:1.6.1")

    // ML Kit
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")

    // ML Kit Face Detection
    implementation("com.google.mlkit:face-detection:16.1.7")

    // ML Kit Translation (on-device)
    implementation("com.google.mlkit:translate:17.0.3")

    // ONNX Runtime
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.19.0")

    // OpenCV (PaddleOCR Lite post-processing)
    // Swapped from com.quickbirdstudios:opencv:4.5.3 (broken: dlopen "cannot locate
    // symbol __sfp_handle_exceptions" on modern Android/bionic) to the official AAR.
    implementation("org.opencv:opencv:4.14.0")

    // DataStore
    implementation("androidx.datastore:datastore-preferences:1.2.1")

    // LiteRT-LM (on-device Gemma, multimodal)
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.16.1")

    // Kotlin Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // OkHttp
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Encrypted SharedPreferences
    implementation("androidx.security:security-crypto:1.1.0")

    // WebRTC
    implementation("io.github.webrtc-sdk:android:125.6422.07")

    // Google Glass (XR SDK) - AI Glasses dependencies per official docs
    implementation("androidx.xr.runtime:runtime:1.0.0-beta01")
    implementation("androidx.xr.glimmer:glimmer:1.0.0-alpha16")
    implementation("androidx.xr.glimmer:glimmer-google-fonts:1.0.0-alpha16")
    implementation("androidx.xr.projected:projected:1.0.0-alpha08")
    implementation("androidx.xr.arcore:arcore:1.0.0-alpha14")

    // Accompanist Permissions
    implementation("com.google.accompanist:accompanist-permissions:0.36.0")

    // Material Components (required for Material3 themes in XML)
    implementation("com.google.android.material:material:1.12.0")
}
