package com.eyepal.app.services

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

sealed class GemmaDownloadState {
    object NotDownloaded : GemmaDownloadState()
    data class Downloading(val fraction: Double) : GemmaDownloadState()
    object Downloaded : GemmaDownloadState()
    data class Failed(val message: String) : GemmaDownloadState()
}

class GemmaModelManager(private val context: Context) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private val _states = MutableStateFlow<Map<GemmaModelKind, GemmaDownloadState>>(
        GemmaModelKind.entries.associateWith { GemmaDownloadState.NotDownloaded }
    )
    val states: StateFlow<Map<GemmaModelKind, GemmaDownloadState>> = _states.asStateFlow()

    private val jobs = mutableMapOf<GemmaModelKind, Job>()

    val isAnyModelDownloaded: Boolean
        get() = GemmaModelKind.entries.any { fileFor(it).exists() }

    private fun baseDir(): File =
        File(context.getExternalFilesDir(null) ?: context.filesDir, "GemmaModels")

    private fun dirFor(kind: GemmaModelKind): File = File(baseDir(), kind.directoryName)

    fun fileFor(kind: GemmaModelKind): File = File(dirFor(kind), kind.fileName)

    fun downloadedModelFile(): File? {
        for (kind in GemmaModelKind.entries) {
            val f = fileFor(kind)
            if (f.exists() && f.length() > 0) return f
        }
        return null
    }

    fun refreshStates() {
        for (kind in GemmaModelKind.entries) {
            val current = _states.value[kind]
            if (fileFor(kind).exists() && fileFor(kind).length() > 0) {
                _states.value = _states.value + (kind to GemmaDownloadState.Downloaded)
            } else if (current is GemmaDownloadState.Downloading) {
                // keep progress
            } else {
                _states.value = _states.value + (kind to GemmaDownloadState.NotDownloaded)
            }
        }
    }

    fun isDownloading(kind: GemmaModelKind): Boolean =
        _states.value[kind] is GemmaDownloadState.Downloading

    fun download(kind: GemmaModelKind) {
        if (fileFor(kind).exists() && fileFor(kind).length() > 0) {
            _states.value = _states.value + (kind to GemmaDownloadState.Downloaded)
            return
        }
        if (jobs[kind] != null) return

        _states.value = _states.value + (kind to GemmaDownloadState.Downloading(0.0))
        jobs[kind] = scope.launch {
            var tmp: File? = null
            try {
                val dir = dirFor(kind)
                dir.mkdirs()
                val dest = fileFor(kind)
                tmp = File(dir, dest.name + ".part")
                val request = Request.Builder().url(kind.downloadUrl).build()
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) throw IOException("HTTP ${response.code}")
                    val body = response.body ?: throw IOException("Empty body")
                    val contentLength = body.contentLength()
                    tmp!!.outputStream().use { out ->
                        val buffer = ByteArray(64 * 1024)
                        var total: Long = 0
                        body.byteStream().use { input ->
                            var read: Int
                            while (input.read(buffer).also { read = it } != -1) {
                                out.write(buffer, 0, read)
                                total += read
                                val expected = if (contentLength > 0) contentLength else total
                                val fraction = expected.toDouble().let { e -> (total.toDouble() / e).coerceIn(0.0, 1.0) }
                                _states.value = _states.value + (kind to GemmaDownloadState.Downloading(fraction))
                            }
                        }
                    }
                }
                if (dest.exists()) dest.delete()
                tmp!!.renameTo(dest)
                jobs.remove(kind)
                refreshStates()
            } catch (e: Exception) {
                try { tmp?.delete() } catch (_: Exception) {}
                jobs.remove(kind)
                _states.value = _states.value + (kind to GemmaDownloadState.Failed(e.message ?: "Download failed"))
            }
        }
    }

    fun cancel(kind: GemmaModelKind) {
        jobs[kind]?.cancel()
        jobs.remove(kind)
        try { File(dirFor(kind), fileFor(kind).name + ".part").delete() } catch (_: Exception) {}
        _states.value = _states.value + (kind to GemmaDownloadState.NotDownloaded)
    }

    fun delete(kind: GemmaModelKind) {
        cancel(kind)
        try { dirFor(kind).deleteRecursively() } catch (_: Exception) {}
        _states.value = _states.value + (kind to GemmaDownloadState.NotDownloaded)
    }

    fun onCleared() {
        scope.cancel()
    }
}
