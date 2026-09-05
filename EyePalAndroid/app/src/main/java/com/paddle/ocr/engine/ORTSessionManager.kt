// Copyright (c) 2026 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package com.paddle.ocr.engine

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.model.OCRError
import java.nio.FloatBuffer

class ORTSessionManager(
    private val context: Context,
    private val config: EngineConfig,
) {
    private var env: OrtEnvironment? = null
    private var detSession: OrtSession? = null
    private var recSession: OrtSession? = null
    private var detInputName: String = "x"
    private var recInputName: String = "x"
    var coldLoadTimeMs: Long = 0
        private set

    fun loadModels(detAssetPath: String, recAssetPath: String) {
        val loadStart = System.currentTimeMillis()
        env = OrtEnvironment.getEnvironment()
        val ortEnv = env ?: throw OCRError.ModelLoadFailed("OCR", Exception("Environment not initialized"))
        val detBytes = readModelAsset(detAssetPath)
        val recBytes = readModelAsset(recAssetPath)

        // Try loading with different configurations (ALL_OPT may fail on some models/devices)
        val configs = listOf(
            { opts: OrtSession.SessionOptions -> opts.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT) },
            { _: OrtSession.SessionOptions -> /* no optimization */ }
        )
        var lastError: Throwable? = null
        for ((index, cfg) in configs.withIndex()) {
            val opts = OrtSession.SessionOptions().apply {
                cfg(this)
                setIntraOpNumThreads(config.numThreads)
            }
            try {
                detSession = ortEnv.createSession(detBytes, opts)
                recSession = ortEnv.createSession(recBytes, opts)
                android.util.Log.i("ORTSessionManager", "Models loaded with config #$index")
                loadInputNames()
                coldLoadTimeMs = System.currentTimeMillis() - loadStart
                return
            } catch (t: Throwable) {
                lastError = t
                android.util.Log.w("ORTSessionManager", "Failed with config #$index: ${t.message}")
                detSession?.close()
                detSession = null
                recSession?.close()
                recSession = null
            }
        }
        throw OCRError.ModelLoadFailed("detection", lastError ?: Exception("Unknown error"))
    }

    private fun loadInputNames() {
        val detErr = try {
            detInputName = detSession!!.inputNames.iterator().next()
            null
        } catch (t: Throwable) { t }
        val recErr = try {
            recInputName = recSession!!.inputNames.iterator().next()
            null
        } catch (t: Throwable) { t }
        if (detErr != null) throw OCRError.ModelLoadFailed("detection", detErr)
        if (recErr != null) throw OCRError.ModelLoadFailed("recognition", recErr)
    }

    fun runDetection(input: FloatArray, shape: LongArray): Pair<FloatArray, LongArray> {
        val session = detSession
            ?: throw OCRError.ModelLoadFailed("detection", Exception("Session not initialized"))
        val ortEnv = env
            ?: throw OCRError.ModelLoadFailed("detection", Exception("Environment not initialized"))
        return runSession(ortEnv, session, detInputName, input, shape, "detection")
    }

    fun runRecognition(input: FloatArray, shape: LongArray): Pair<FloatArray, LongArray> {
        val session = recSession
            ?: throw OCRError.ModelLoadFailed("recognition", Exception("Session not initialized"))
        val ortEnv = env
            ?: throw OCRError.ModelLoadFailed("recognition", Exception("Environment not initialized"))
        return runSession(ortEnv, session, recInputName, input, shape, "recognition")
    }

    fun release() {
        try {
            detSession?.close()
        } finally {
            detSession = null
            try {
                recSession?.close()
            } finally {
                recSession = null
                env = null
            }
        }
    }

    private fun readModelAsset(assetPath: String): ByteArray {
        return try {
            context.assets.open(assetPath).use { it.readBytes() }
        } catch (t: Throwable) {
            throw OCRError.ModelNotFound(assetPath, t)
        }
    }

    private fun runSession(
        ortEnv: OrtEnvironment,
        session: OrtSession,
        inputName: String,
        input: FloatArray,
        shape: LongArray,
        modelName: String,
    ): Pair<FloatArray, LongArray> {
        val tensor = try {
            OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(input), shape)
        } catch (t: Throwable) {
            throw OCRError.InferenceFailed(modelName, t)
        }
        val result = try {
            try {
                session.run(mapOf(inputName to tensor))
            } catch (t: Throwable) {
                throw OCRError.InferenceFailed(modelName, t)
            }
        } finally {
            tensor.close()
        }

        return try {
            try {
                val outputName = session.outputNames.iterator().next()
                val ortValue = result.get(outputName)
                    .orElseThrow { Exception("No output tensor found") }
                val outputTensor = ortValue as? OnnxTensor
                    ?: throw Exception("Output is not an ONNX tensor")
                Pair(copyFloatBuffer(outputTensor.floatBuffer), outputTensor.info.shape)
            } catch (t: Throwable) {
                throw OCRError.InferenceFailed(modelName, t)
            }
        } finally {
            result.close()
        }
    }

    private fun copyFloatBuffer(buffer: FloatBuffer): FloatArray {
        val duplicate = buffer.duplicate()
        duplicate.rewind()
        val output = FloatArray(duplicate.remaining())
        duplicate.get(output)
        return output
    }
}
