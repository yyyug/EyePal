# Kotlin Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.eyepal.app.**$$serializer { *; }
-keepclassmembers class com.eyepal.app.** { *** Companion; }
-keepclasseswithmembers class com.eyepal.app.** { kotlinx.serialization.KSerializer serializer(...); }

# OkHttp — ships META-INF/proguard/okhttp3.pro consumer rules
-dontwarn okhttp3.**
-dontwarn okio.**

# ONNX Runtime — no consumer rules, JNI-backed
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# MLKit — reflection-based component registration
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# WebRTC — JNI bitcode, native callbacks back into Java
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Google Glasses / XR — no consumer rules
-keep class androidx.xr.** { *; }

# Kotlin Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }

# Gson / JSON
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.google.gson.**

# OpenCV (PaddleOCR Lite) — no consumer rules, JNI-backed
-keep class org.opencv.** { *; }
-dontwarn org.opencv.**

# PaddleOCR Lite SDK
-keep class com.paddle.ocr.** { *; }
-dontwarn com.paddle.ocr.**
