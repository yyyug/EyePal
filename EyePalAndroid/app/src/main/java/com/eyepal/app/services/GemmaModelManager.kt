package com.eyepal.app.services

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLongArray

private const val CHUNK_SIZE = 64L * 1024 * 1024
private const val MAX_CONCURRENT_CHUNKS = 8

sealed class GemmaDownloadState {
    object NotDownloaded : GemmaDownloadState()
    data class Downloading(val fraction: Double) : GemmaDownloadState()
    data class Paused(val fraction: Double) : GemmaDownloadState()
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

    private val lock = Any()
    private val jobs = mutableMapOf<GemmaModelKind, Job>()
    private val activeCalls = mutableMapOf<GemmaModelKind, MutableList<Call>>()
    private var lastPublishMs = 0L

    private data class Chunk(val index: Int, val start: Long, val end: Long) {
        val length: Long get() = end - start + 1
    }

    private data class Probe(
        val url: String,
        val totalBytes: Long,
        val supportsRange: Boolean,
        val etag: String?
    )

    private fun baseDir(): File =
        File(context.getExternalFilesDir(null) ?: context.filesDir, "GemmaModels")

    private fun dirFor(kind: GemmaModelKind): File = File(baseDir(), kind.directoryName)

    fun fileFor(kind: GemmaModelKind): File = File(dirFor(kind), kind.fileName)

    private fun partFile(kind: GemmaModelKind, index: Int) = File(dirFor(kind), "part-$index.bin")

    private fun metaFile(kind: GemmaModelKind) = File(dirFor(kind), "download.meta")

    val isAnyModelDownloaded: Boolean
        get() = GemmaModelKind.entries.any { fileFor(it).exists() && fileFor(it).length() > 0 }

    fun downloadedModelFile(): File? {
        for (kind in GemmaModelKind.entries) {
            val f = fileFor(kind)
            if (f.exists() && f.length() > 0) return f
        }
        return null
    }

    fun modelFileFor(kind: GemmaModelKind? = null): File? {
        if (kind != null) {
            val f = fileFor(kind)
            if (f.exists() && f.length() > 0) return f
        }
        return downloadedModelFile()
    }

    fun refreshStates() {
        for (kind in GemmaModelKind.entries) {
            val current = _states.value[kind]
            val file = fileFor(kind)
            if (file.exists() && file.length() > 0) {
                update(kind, GemmaDownloadState.Downloaded)
            } else if (current is GemmaDownloadState.Downloading || current is GemmaDownloadState.Paused) {
                // keep progress
            } else {
                update(kind, GemmaDownloadState.NotDownloaded)
            }
        }
    }

    fun isDownloading(kind: GemmaModelKind): Boolean =
        _states.value[kind] is GemmaDownloadState.Downloading

    /** Starts or resumes a download; existing part files are reused. */
    fun download(kind: GemmaModelKind) {
        val file = fileFor(kind)
        if (file.exists() && file.length() > 0) {
            update(kind, GemmaDownloadState.Downloaded)
            return
        }
        synchronized(lock) {
            val existing = jobs[kind]
            if (existing != null && existing.isActive && _states.value[kind] is GemmaDownloadState.Downloading) return
            jobs[kind] = scope.launch { runDownload(kind) }
        }
    }

    fun pause(kind: GemmaModelKind) {
        val fraction = currentFraction(kind)
        synchronized(lock) {
            jobs.remove(kind)?.cancel()
            activeCalls.remove(kind)?.forEach { runCatching { it.cancel() } }
        }
        update(kind, GemmaDownloadState.Paused(fraction))
    }

    fun cancel(kind: GemmaModelKind) {
        synchronized(lock) {
            jobs.remove(kind)?.cancel()
            activeCalls.remove(kind)?.forEach { runCatching { it.cancel() } }
        }
        update(kind, GemmaDownloadState.NotDownloaded)
    }

    fun delete(kind: GemmaModelKind) {
        synchronized(lock) {
            jobs.remove(kind)?.cancel()
            activeCalls.remove(kind)?.forEach { runCatching { it.cancel() } }
        }
        runCatching { dirFor(kind).deleteRecursively() }
        update(kind, GemmaDownloadState.NotDownloaded)
    }

    fun onCleared() {
        scope.cancel()
    }

    // MARK: - Transfer

    private suspend fun runDownload(kind: GemmaModelKind) {
        try {
            val dir = dirFor(kind)
            dir.mkdirs()

            val probe = probe(kind) ?: throw IOException("No reachable model source")
            applyEtag(kind, probe)

            val chunks = buildChunks(probe)
            val progress = AtomicLongArray(chunks.size)
            chunks.forEachIndexed { index, chunk ->
                val part = partFile(kind, chunk.index)
                progress.set(index, if (part.exists()) part.length() else 0L)
            }

            update(kind, GemmaDownloadState.Downloading(fraction(progress, probe.totalBytes)))

            val semaphore = Semaphore(MAX_CONCURRENT_CHUNKS)
            coroutineScope {
                chunks.indices.map { index ->
                    async {
                        semaphore.withPermit { downloadChunk(kind, probe, chunks[index], progress) }
                    }
                }.awaitAll()
            }

            merge(kind, chunks)
            deleteParts(kind)
            runCatching { metaFile(kind).delete() }
            update(kind, GemmaDownloadState.Downloaded)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!currentCoroutineContext().isActive) throw CancellationException()
            update(kind, GemmaDownloadState.Failed(e.message ?: "Download failed"))
        }
    }

    private suspend fun downloadChunk(
        kind: GemmaModelKind,
        probe: Probe,
        chunk: Chunk,
        progress: AtomicLongArray
    ) {
        val part = partFile(kind, chunk.index)
        var received = if (part.exists()) part.length() else 0L
        if (received >= chunk.length) {
            progress.set(chunk.index, received)
            return
        }

        val builder = Request.Builder().url(probe.url)
        if (probe.supportsRange) {
            builder.header("Range", "bytes=${chunk.start + received}-${chunk.end}")
        }
        val call = client.newCall(builder.build())
        synchronized(lock) {
            activeCalls.getOrPut(kind) { mutableListOf() }.add(call)
        }

        try {
            call.execute().use { response ->
                if (!response.isSuccessful) throw IOException("HTTP ${response.code}")
                val body = response.body ?: throw IOException("Empty body")
                RandomAccessFile(part, "rw").use { raf ->
                    raf.seek(received)
                    body.byteStream().use { input ->
                        val buffer = ByteArray(256 * 1024)
                        while (true) {
                            if (!currentCoroutineContext().isActive) throw CancellationException()
                            val read = input.read(buffer)
                            if (read == -1) break
                            raf.write(buffer, 0, read)
                            received += read
                            progress.set(chunk.index, received)
                            publishProgress(kind, progress, probe.totalBytes)
                        }
                    }
                }
            }
        } finally {
            synchronized(lock) { activeCalls[kind]?.remove(call) }
        }
    }

    private fun probe(kind: GemmaModelKind): Probe? {
        for (url in kind.downloadUrls) {
            try {
                val request = Request.Builder()
                    .url(url)
                    .header("Range", "bytes=0-0")
                    .build()
                client.newCall(request).execute().use { response ->
                    val etag = response.header("ETag")
                    val contentRange = response.header("Content-Range")
                    if (response.code == 206 && contentRange != null) {
                        val total = contentRange.substringAfter('/').trim().toLongOrNull()
                        if (total != null && total > 0) return Probe(url, total, true, etag)
                    }
                    val length = response.header("Content-Length")?.toLongOrNull()
                    if (length != null && length > 0) {
                        val acceptRanges = response.header("Accept-Ranges")
                        return Probe(url, length, acceptRanges?.lowercase()?.contains("bytes") == true, etag)
                    }
                }
            } catch (_: Exception) {
                // try the next source
            }
        }
        return null
    }

    private fun applyEtag(kind: GemmaModelKind, probe: Probe) {
        val meta = metaFile(kind)
        val previous = if (meta.exists()) meta.readText().trim() else ""
        val previousEtag = previous.substringBefore('|')
        if (previousEtag.isNotEmpty() && probe.etag != null && previousEtag != probe.etag) {
            deleteParts(kind)
        }
        if (probe.etag != null) {
            runCatching { meta.writeText("${probe.etag}|${probe.totalBytes}") }
        }
    }

    private fun buildChunks(probe: Probe): List<Chunk> {
        if (!probe.supportsRange) return listOf(Chunk(0, 0, probe.totalBytes - 1))
        val chunks = mutableListOf<Chunk>()
        var start = 0L
        var index = 0
        while (start < probe.totalBytes) {
            val end = minOf(start + CHUNK_SIZE, probe.totalBytes) - 1
            chunks.add(Chunk(index, start, end))
            start = end + 1
            index++
        }
        return chunks
    }

    private fun merge(kind: GemmaModelKind, chunks: List<Chunk>) {
        val destination = fileFor(kind)
        val temp = File(dirFor(kind), destination.name + ".merged")
        if (temp.exists()) temp.delete()
        temp.outputStream().use { out ->
            chunks.sortedBy { it.index }.forEach { chunk ->
                partFile(kind, chunk.index).inputStream().use { it.copyTo(out, 256 * 1024) }
            }
        }
        if (destination.exists()) destination.delete()
        if (!temp.renameTo(destination)) {
            temp.copyTo(destination, overwrite = true)
            temp.delete()
        }
    }

    private fun deleteParts(kind: GemmaModelKind) {
        runCatching {
            dirFor(kind).listFiles()
                ?.filter { it.name.startsWith("part-") }
                ?.forEach { it.delete() }
        }
    }

    private fun fraction(progress: AtomicLongArray, total: Long): Double {
        if (total <= 0) return 0.0
        var sum = 0L
        for (i in 0 until progress.length()) sum += progress.get(i)
        return (sum.toDouble() / total.toDouble()).coerceIn(0.0, 1.0)
    }

    private fun currentFraction(kind: GemmaModelKind): Double =
        (_states.value[kind] as? GemmaDownloadState.Downloading)?.fraction
            ?: (_states.value[kind] as? GemmaDownloadState.Paused)?.fraction
            ?: 0.0

    private fun publishProgress(kind: GemmaModelKind, progress: AtomicLongArray, total: Long) {
        val now = System.currentTimeMillis()
        if (now - lastPublishMs < 250) return
        lastPublishMs = now
        update(kind, GemmaDownloadState.Downloading(fraction(progress, total)))
    }

    private fun update(kind: GemmaModelKind, state: GemmaDownloadState) {
        _states.update { it + (kind to state) }
    }
}
