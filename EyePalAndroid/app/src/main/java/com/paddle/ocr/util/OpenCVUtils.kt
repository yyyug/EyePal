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

package com.paddle.ocr.util

import android.content.Context
import android.os.Build
import android.system.Os
import android.system.OsConstants
import android.util.Log

object OpenCVUtils {

    @Volatile
    private var initialized = false

    @Volatile
    var lastError: String? = null
        private set

    private fun pageSize(): Long {
        return try { Os.sysconf(OsConstants._SC_PAGESIZE) } catch (_: Throwable) { 0L }
    }

    @Synchronized
    fun init(context: Context): Boolean {
        if (initialized) return true
        val candidates = listOf("opencv_java4", "opencv_android4")
        val causes = StringBuilder()
        for (name in candidates) {
            try {
                System.loadLibrary(name)
                initialized = true
                lastError = null
                Log.i("OpenCVUtils", "OpenCV native library loaded: $name")
                return true
            } catch (e: UnsatisfiedLinkError) {
                if (causes.isNotEmpty()) causes.append(" | ")
                causes.append("$name: ${e.message}")
                Log.w("OpenCVUtils", "Failed to load OpenCV library '$name': ${e.message}")
            }
        }
        lastError = "OpenCV load failed (ABI=${Build.SUPPORTED_ABIS.joinToString()}, API=${Build.VERSION.SDK_INT}, page=${pageSize()}) $causes"
        Log.e("OpenCVUtils", lastError!!)
        return false
    }

    fun isInitialized(): Boolean = initialized
}
