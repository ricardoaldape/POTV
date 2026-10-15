package com.potv.potv

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.preload.DefaultPreloadManager
import androidx.media3.exoplayer.source.preload.TargetPreloadStatusControl

@OptIn(UnstableApi::class)
object PotvMedia3Preload {
    private class Target :
        TargetPreloadStatusControl<Int, DefaultPreloadManager.PreloadStatus> {
        override fun getTargetPreloadStatus(
            index: Int,
        ): DefaultPreloadManager.PreloadStatus {
            return if (index == 1) {
                DefaultPreloadManager.PreloadStatus.specifiedRangeLoaded(3000L)
            } else {
                DefaultPreloadManager.PreloadStatus.PRELOAD_STATUS_NOT_PRELOADED
            }
        }
    }

    private var builder: DefaultPreloadManager.Builder? = null
    private var manager: DefaultPreloadManager? = null
    private var current: MediaItem? = null

    @Synchronized
    fun ensure(context: Context) {
        if (manager != null) return
        val nextBuilder =
            DefaultPreloadManager.Builder(
                context.applicationContext,
                Target(),
            )
        builder = nextBuilder
        manager = nextBuilder.build()
    }

    // ExoPlayer selects HlsMediaSource by the MediaItem MIME or by the URL
    // extension, not by the HTTP Content-Type it will receive later.
    // POTV's signed proxy is extensionless even when its body is an M3U8
    // master playlist. Without this declaration it is opened as progressive
    // media, producing SOURCE/UNRECOGNIZED errors before video starts.
    internal fun mimeForSource(uri: Uri): String? {
        val path = uri.path.orEmpty().lowercase()
        val format = uri.getQueryParameter("format")?.lowercase()
        if (format == "ts" || format == "mp4" || format == "progressive") {
            return null
        }
        if (format == "hls" || format == "m3u8" ||
            path.endsWith(".m3u8")) {
            return MimeTypes.APPLICATION_M3U8
        }
        if (format == "dash" || format == "mpd" ||
            path.endsWith(".mpd")) {
            return MimeTypes.APPLICATION_MPD
        }
        // Existing gateway catalogs already expose HLS through signed,
        // extensionless stream URLs. An explicit format=ts overrides this
        // default for future licensed Xtream transport-stream providers.
        if (uri.scheme == "https" &&
            uri.host.equals("potv.fxqubit.com", ignoreCase = true) &&
            path.startsWith("/api/v1/content/stream/")) {
            return MimeTypes.APPLICATION_M3U8
        }
        return null
    }

    fun mediaItem(
        uri: String,
        title: String,
        subtitles: Any? = null,
    ): MediaItem {
        val parsed = Uri.parse(uri)
        val mediaBuilder =
            MediaItem.Builder()
                .setMediaId(uri)
                .setUri(parsed)
                .apply {
                    mimeForSource(parsed)?.let { setMimeType(it) }
                }
                .setMediaMetadata(
                    androidx.media3.common.MediaMetadata.Builder()
                        .setTitle(title)
                        .build(),
                )

        val subtitleConfigurations = subtitleConfigurations(subtitles)
        if (subtitleConfigurations.isNotEmpty()) {
            mediaBuilder.setSubtitleConfigurations(subtitleConfigurations)
        }
        return mediaBuilder.build()
    }

    @Synchronized
    fun preload(
        context: Context,
        uri: String,
        title: String,
        subtitles: Any? = null,
    ): Boolean {
        val parsed = runCatching { Uri.parse(uri) }.getOrNull() ?: return false
        if (parsed.scheme !in setOf("http", "https") || parsed.host.isNullOrBlank()) {
            return false
        }
        ensure(context)
        val next = mediaItem(uri, title, subtitles)
        val preloadManager = manager ?: return false
        preloadManager.reset()
        preloadManager.addMediaItems(listOf(next), listOf(1))
        current = next
        return true
    }

    @Synchronized
    fun mediaSource(mediaItem: MediaItem): MediaSource? {
        val preloadManager = manager ?: return null
        if (current != mediaItem) return null
        return preloadManager.getMediaSource(mediaItem)
    }

    @Synchronized
    fun buildPlayer(context: Context): ExoPlayer {
        ensure(context)
        return requireNotNull(builder).buildExoPlayer()
    }

    @Synchronized
    fun markPlaying() {
        manager?.setCurrentPlayingIndex(1)
    }

    private fun subtitleConfigurations(
        raw: Any?,
    ): List<MediaItem.SubtitleConfiguration> {
        if (raw !is List<*>) return emptyList()
        return raw.mapNotNull { item ->
            if (item !is Map<*, *>) return@mapNotNull null
            val rawUrl = item["uri"]?.toString()?.trim().orEmpty()
            if (rawUrl.isEmpty()) return@mapNotNull null
            val uri = runCatching { Uri.parse(rawUrl) }.getOrNull() ?: return@mapNotNull null
            val language = item["language"]?.toString()?.takeIf { it.isNotBlank() }
            val label = item["label"]?.toString()?.takeIf { it.isNotBlank() }
            val path = uri.path.orEmpty().lowercase()
            val mimeType =
                when {
                    path.endsWith(".srt") -> MimeTypes.APPLICATION_SUBRIP
                    else -> MimeTypes.TEXT_VTT
                }
            MediaItem.SubtitleConfiguration.Builder(uri)
                .setMimeType(mimeType)
                .apply {
                    if (language != null) setLanguage(language)
                    if (label != null) setLabel(label)
                }
                .build()
        }
    }
}
