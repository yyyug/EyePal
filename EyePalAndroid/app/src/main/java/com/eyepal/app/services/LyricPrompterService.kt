package com.eyepal.app.services

import com.eyepal.app.models.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.URLEncoder

class LyricPrompterService(private val client: OkHttpClient = OkHttpClient()) {

    suspend fun searchAllSources(searchText: String): List<LyricSearchResult> = coroutineScope {
        val (title, artist) = parseSearchInput(searchText)
        val lrclib = async { searchLRCLIB(title, artist) }
        val qq = async { searchQQMusic(title, artist) }
        val all = lrclib.await() + qq.await()
        val seen = mutableSetOf<String>()
        all.filter { result ->
            val key = "${result.trackName.lowercase()}-${result.artistName.lowercase()}"
            seen.add(key)
        }
    }

    private fun parseSearchInput(input: String): Pair<String, String> {
        for (sep in listOf(" - ", " – ", " — ", " by ", " / ")) {
            val idx = input.indexOf(sep)
            if (idx >= 0) {
                val title = input.substring(0, idx).trim()
                val artist = input.substring(idx + sep.length).trim()
                if (title.isNotEmpty() && artist.isNotEmpty()) return title to artist
                if (title.isNotEmpty()) return title to ""
            }
        }
        return input to ""
    }

    private suspend fun searchLRCLIB(title: String, artist: String): List<LyricSearchResult> = withContext(Dispatchers.IO) {
        try {
            val encodedTitle = URLEncoder.encode(title, "UTF-8")
            val url = if (artist.isNotEmpty()) {
                "https://lrclib.net/api/search?track_name=$encodedTitle&artist_name=${URLEncoder.encode(artist, "UTF-8")}"
            } else {
                "https://lrclib.net/api/search?track_name=$encodedTitle"
            }
            val request = Request.Builder().url(url).header("User-Agent", "LyricPrompter-EyePal/1.0").build()
            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return@withContext emptyList()
            val json = Json.parseToJsonElement(body).jsonArray
            json.mapNotNull { element ->
                val obj = element.jsonObject
                val trackName = obj["trackName"]?.jsonPrimitive?.content ?: return@mapNotNull null
                val artistName = obj["artistName"]?.jsonPrimitive?.content ?: return@mapNotNull null
                val synced = obj["syncedLyrics"]?.jsonPrimitive?.contentOrNull
                val plain = obj["plainLyrics"]?.jsonPrimitive?.contentOrNull
                LyricSearchResult(
                    source = "LRCLIB", trackName = trackName, artistName = artistName,
                    albumName = obj["albumName"]?.jsonPrimitive?.contentOrNull,
                    hasSyncedLyrics = !synced.isNullOrBlank(), syncedLyrics = synced, plainLyrics = plain
                )
            }
        } catch (e: Exception) { emptyList() }
    }

    private suspend fun searchQQMusic(title: String, artist: String): List<LyricSearchResult> = withContext(Dispatchers.IO) {
        try {
            val keyword = if (artist.isNotEmpty()) "$title $artist" else title
            val payload = buildJsonObject {
                putJsonObject("req_1") {
                    put("method", "DoSearchForQQMusicDesktop")
                    put("module", "music.search.SearchCgiService")
                    putJsonObject("param") {
                        put("num_per_page", "5")
                        put("page_num", "1")
                        put("query", keyword)
                        put("search_type", 0)
                    }
                }
            }
            val body = payload.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder().url("https://u.y.qq.com/cgi-bin/musicu.fcg")
                .header("Referer", "https://c.y.qq.com/").post(body).build()
            val response = client.newCall(request).execute()
            val responseBody = response.body?.string() ?: return@withContext emptyList()
            val json = Json.parseToJsonElement(responseBody).jsonObject
            val songList = json["req_1"]?.jsonObject?.get("data")?.jsonObject
                ?.get("body")?.jsonObject?.get("song_list")?.jsonArray ?: return@withContext emptyList()

            songList.take(5).mapNotNull { element ->
                val song = element.jsonObject
                val mid = song["mid"]?.jsonPrimitive?.content ?: return@mapNotNull null
                val name = song["name"]?.jsonPrimitive?.content ?: return@mapNotNull null
                val singers = song["singer"]?.jsonArray?.mapNotNull { it.jsonObject["name"]?.jsonPrimitive?.content } ?: emptyList()
                val artistName = singers.joinToString(", ")
                val lyrics = fetchQQMusicLyrics(mid)
                if (lyrics != null) {
                    LyricSearchResult(
                        source = "QQ Music", trackName = name, artistName = artistName,
                        hasSyncedLyrics = lyrics.first, syncedLyrics = lyrics.second, plainLyrics = lyrics.third
                    )
                } else null
            }
        } catch (e: Exception) { emptyList() }
    }

    private fun fetchQQMusicLyrics(songMid: String): Triple<Boolean, String?, String?>? {
        return try {
            val ts = System.currentTimeMillis()
            val url = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?callback=MusicJsonCallback_lrc&pcachetime=$ts&songmid=$songMid&g_tk=5381&jsonpCallback=MusicJsonCallback_lrc&loginUin=0&hostUin=0&format=jsonp&inCharset=utf8&outCharset=utf8&notice=0&platform=yqq&needNewCode=0"
            val request = Request.Builder().url(url).header("Referer", "https://c.y.qq.com/").build()
            val response = client.newCall(request).execute()
            val raw = response.body?.string() ?: return null
            val jsonStr = raw.removePrefix("MusicJsonCallback_lrc(").removeSuffix(")")
            val json = Json.parseToJsonElement(jsonStr).jsonObject
            val lyricBase64 = json["lyric"]?.jsonPrimitive?.content ?: return null
            if (lyricBase64.isEmpty()) return null
            val lyricBytes = android.util.Base64.decode(lyricBase64, android.util.Base64.DEFAULT)
            val lrc = String(lyricBytes)
            val hasSynced = lrc.contains("[0")
            Triple(hasSynced, if (hasSynced) lrc else null, if (hasSynced) extractPlainFromLRC(lrc) else lrc)
        } catch (e: Exception) { null }
    }

    private fun extractPlainFromLRC(lrc: String): String {
        return lrc.lines().mapNotNull { line ->
            val idx = line.indexOf(']')
            if (idx >= 0) line.substring(idx + 1).trim().ifEmpty { null } else null
        }.joinToString("\n")
    }

    fun loadLyrics(result: LyricSearchResult): LyricSong {
        if (result.hasSyncedLyrics && result.syncedLyrics != null) {
            val lines = parseLRC(result.syncedLyrics)
            return LyricSong(id = "", title = result.trackName, artist = result.artistName, lines = lines, hasTimestamps = true)
        } else if (result.plainLyrics != null) {
            val lines = result.plainLyrics.lines().filter { it.isNotBlank() }.map { LyricLine(text = it) }
            return LyricSong(id = "", title = result.trackName, artist = result.artistName, lines = lines, hasTimestamps = false)
        }
        return LyricSong(id = "", title = result.trackName, artist = result.artistName, lines = emptyList(), hasTimestamps = false)
    }

    private fun parseLRC(lrc: String): List<LyricLine> {
        return lrc.lines().mapNotNull { line ->
            val trimmed = line.trim()
            if (!trimmed.startsWith("[")) return@mapNotNull null
            val closeBracket = trimmed.indexOf(']')
            if (closeBracket < 0) return@mapNotNull null
            val timeStr = trimmed.substring(1, closeBracket)
            val text = trimmed.substring(closeBracket + 1).trim()
            if (text.isEmpty()) return@mapNotNull null
            val time = parseLRCTime(timeStr) ?: return@mapNotNull null
            LyricLine(text = text, startTime = time)
        }
    }

    private fun parseLRCTime(str: String): Double? {
        val parts = str.split(":")
        if (parts.size != 2) return null
        val mins = parts[0].toDoubleOrNull() ?: return null
        val secs = parts[1].toDoubleOrNull() ?: return null
        return mins * 60 + secs
    }
}
