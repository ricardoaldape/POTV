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

    fun mediaItem(
        uri: String,
        title: String,
        subtitles: Any? = null,
    ): MediaItem {
        val mediaBuilder =
            MediaItem.Builder()
                .setMediaId(uri)
                .setUri(Uri.parse(uri))
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
