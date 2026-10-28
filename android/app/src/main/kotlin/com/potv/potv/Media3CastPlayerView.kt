package com.potv.potv

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.cast.Cast
import androidx.media3.cast.CastPlayer
import androidx.media3.cast.MediaRouteButtonFactory
import androidx.media3.common.C
import androidx.media3.common.DeviceInfo
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import androidx.media3.ui.PlayerView
import androidx.mediarouter.app.MediaRouteButton
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

@OptIn(UnstableApi::class)
class Media3CastPlayerFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return Media3CastPlayerView(context, messenger, viewId, params)
    }
}

@OptIn(UnstableApi::class)
private class Media3CastPlayerView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    params: Map<String, Any?>,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val root = FrameLayout(context)
    private val playerView = PlayerView(context)
    private val routeButton = MediaRouteButton(context)
    private val localPlayer: ExoPlayer
    private val castPlayer: CastPlayer
    private val mediaSession: MediaSession
    private val channel = MethodChannel(messenger, "potv/media3_cast/$viewId")
    private val stallHandler = Handler(Looper.getMainLooper())
    private var stalledTask: Runnable? = null

    private fun cancelStallWatchdog() {
        stalledTask?.let { stallHandler.removeCallbacks(it) }
        stalledTask = null
    }

    private val audioPreference = params["audioPreference"]?.toString() ?: "spanish"
    private val subtitlePreference =
        params["subtitlePreference"]?.toString() ?: "whenNoSpanishAudio"
    private val autoplay = params["autoplay"] != false
    private var automaticSelectionApplied = false

    init {
        val headers =
            (params["headers"] as? Map<*, *>)
                ?.entries
                ?.associate { it.key.toString() to it.value.toString() }
                ?: emptyMap()

        val dataSourceFactory =
            DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .apply {
                    if (headers.isNotEmpty()) {
                        setDefaultRequestProperties(headers)
                    }
                }

        Cast.getSingletonInstance(context.applicationContext).initialize()

        localPlayer =
            if (headers.isEmpty()) {
                PotvMedia3Preload.buildPlayer(context)
            } else {
                ExoPlayer.Builder(context)
                    .setMediaSourceFactory(
                        DefaultMediaSourceFactory(context)
                            .setDataSourceFactory(dataSourceFactory),
                    )
                    .build()
            }

        applyLanguageConstraints(localPlayer)

        castPlayer =
            CastPlayer.Builder(context)
                .setLocalPlayer(localPlayer)
                .build()

        val openedAt = android.os.SystemClock.elapsedRealtime()
        var startupReported = false

        // Media3 can signal isPlaying for audio while video has not produced
        // a single frame. Do not mark a live TV channel as healthy yet.
        fun reportFirstVideoFrame() {
            if (startupReported) return
            startupReported = true
            val startupMs = android.os.SystemClock.elapsedRealtime() - openedAt
            channel.invokeMethod("bufferingChanged", false)
            channel.invokeMethod("playbackStarted", startupMs)
        }

        castPlayer.addListener(
            object : Player.Listener {
                override fun onTracksChanged(tracks: Tracks) {
                    if (!automaticSelectionApplied && !tracks.isEmpty) {
                        automaticSelectionApplied = true
                        applyAutomaticTracks(tracks)
                    }
                    logSelectedTracks(castPlayer.currentTracks)
                }

                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    // Remote Chromecast playback has no local first-frame callback.
                    if (
                        isPlaying &&
                        castPlayer.deviceInfo.playbackType == DeviceInfo.PLAYBACK_TYPE_REMOTE
                    ) {
                        reportFirstVideoFrame()
                    }
                }

                override fun onRenderedFirstFrame() {
                    // Only real decoded video cancels POTV's startup watchdog.
                    reportFirstVideoFrame()
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    channel.invokeMethod(
                        "bufferingChanged",
                        playbackState == Player.STATE_BUFFERING ||
                            (!startupReported && playbackState != Player.STATE_ENDED),
                    )
                    // Following the first real video frame, a live CDN can
                    // enter BUFFERING forever without reporting an error.
                    // Wait 18 seconds of *continuous* buffering, then let the
                    // Flutter failover policy retry or switch sources.
                    val isLocal = castPlayer.deviceInfo.playbackType !=
                        DeviceInfo.PLAYBACK_TYPE_REMOTE
                    if (
                        playbackState == Player.STATE_BUFFERING &&
                        startupReported &&
                        isLocal
                    ) {
                        if (stalledTask == null) {
                            val timeoutTask = Runnable {
                                stalledTask = null
                                if (castPlayer.playbackState == Player.STATE_BUFFERING) {
                                    val reason = "[Player] Video detenido: buffering agotado"
                                    emitLog(reason)
                                    channel.invokeMethod("playerError", reason)
                                }
                            }
                            stalledTask = timeoutTask
                            stallHandler.postDelayed(timeoutTask, 18000L)
                        }
                    } else {
                        cancelStallWatchdog()
                    }
                    if (playbackState == Player.STATE_ENDED) {
                        channel.invokeMethod("playbackEnded", null)
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    cancelStallWatchdog()
                    // Do not expose signed stream URLs or provider metadata
                    // through exception messages into Flutter debug logs.
                    val message = "[Player] Error Media3: ${error.errorCodeName}"
                    emitLog(message)
                    channel.invokeMethod("playerError", message)
                }
            },
        )

        mediaSession = MediaSession.Builder(context, castPlayer).build()

        playerView.player = castPlayer
        playerView.useController = false
        playerView.setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)

        root.addView(
            playerView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        routeButton.alpha = 0.01f
        routeButton.isClickable = true
        root.addView(routeButton, FrameLayout.LayoutParams(1, 1))
        MediaRouteButtonFactory.setUpMediaRouteButton(context, routeButton)

        val uri = params["uri"]?.toString().orEmpty()
        val title = params["title"]?.toString().orEmpty()
        val startPositionMs = (params["startPositionMs"] as? Number)?.toLong() ?: 0L

        if (uri.isNotBlank()) {
            val subtitleConfigurations = subtitleConfigurations(params["subtitles"])
            subtitleConfigurations.forEach { subtitle ->
                emitLog(
                    "[Player] Subtítulos cargados: ${subtitle.language ?: "sin idioma"} " +
                        "(URL externa)",
                )
            }
            val mediaItem = PotvMedia3Preload.mediaItem(
                uri,
                title,
                params["subtitles"],
            )
            val preloaded =
                if (headers.isEmpty()) PotvMedia3Preload.mediaSource(mediaItem) else null
            if (preloaded != null) {
                localPlayer.setMediaSource(preloaded)
            } else {
                castPlayer.setMediaItem(mediaItem)
            }
            if (startPositionMs > 0L) {
                castPlayer.seekTo(startPositionMs)
            }
            castPlayer.prepare()
            PotvMedia3Preload.markPlaying()
            castPlayer.playWhenReady = autoplay
        }

        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = root

    private fun applyLanguageConstraints(player: ExoPlayer) {
        val builder = player.trackSelectionParameters.buildUpon()

        when (audioPreference) {
            "spanish" -> builder.setPreferredAudioLanguage("es")
            "english" -> builder.setPreferredAudioLanguage("en")
        }

        when (subtitlePreference) {
            "disabled" -> builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            else -> {
                builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                builder.setPreferredTextLanguage("es")
            }
        }

        player.trackSelectionParameters = builder.build()
    }

    private fun applyAutomaticTracks(tracks: Tracks) {
        val audio =
            when (audioPreference) {
                "spanish" ->
                    findTrack(tracks, C.TRACK_TYPE_AUDIO, ::isLatinoSpanish)
                        ?: findTrack(tracks, C.TRACK_TYPE_AUDIO, ::isSpanish)
                        ?: findTrack(tracks, C.TRACK_TYPE_AUDIO, ::isEnglish)
                "english" ->
                    findTrack(tracks, C.TRACK_TYPE_AUDIO, ::isEnglish)
                        ?: findTrack(tracks, C.TRACK_TYPE_AUDIO, ::isLatinoSpanish)
                        ?: findTrack(tracks, C.TRACK_TYPE_AUDIO, ::isSpanish)
                else -> null
            }

        if (audio != null) {
            selectTrack(audio.groupIndex, audio.trackIndex)
        }

        val spanishAudioSelected =
            audio?.let {
                val format =
                    tracks.groups[it.groupIndex].getTrackFormat(it.trackIndex)
                isSpanish(format.language, format.label)
            } ?: selectedAudioIsSpanish(tracks)

        when (subtitlePreference) {
            "disabled" -> setSubtitlesDisabled(true)
            "enabled" -> {
                val spanishSubtitle =
                    findTrack(tracks, C.TRACK_TYPE_TEXT, ::isSpanish)
                if (spanishSubtitle != null) {
                    selectTrack(spanishSubtitle.groupIndex, spanishSubtitle.trackIndex)
                }
            }
            else -> {
                if (spanishAudioSelected) {
                    setSubtitlesDisabled(true)
                } else {
                    val spanishSubtitle =
                        findTrack(tracks, C.TRACK_TYPE_TEXT, ::isSpanish)
                    if (spanishSubtitle != null) {
                        selectTrack(
                            spanishSubtitle.groupIndex,
                            spanishSubtitle.trackIndex,
                        )
                    }
                }
            }
        }
    }

    private fun findTrack(
        tracks: Tracks,
        trackType: Int,
        predicate: (String?, String?) -> Boolean,
    ): TrackRef? {
        tracks.groups.forEachIndexed { groupIndex, group ->
            if (group.type != trackType) return@forEachIndexed
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                if (predicate(format.language, format.label)) {
                    return TrackRef(groupIndex, trackIndex)
                }
            }
        }
        return null
    }

    private fun selectedAudioIsSpanish(tracks: Tracks): Boolean {
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_AUDIO) continue
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSelected(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                return isSpanish(format.language, format.label)
            }
        }
        return false
    }

    private fun selectTrack(groupIndex: Int, trackIndex: Int) {
        val groups = castPlayer.currentTracks.groups
        if (groupIndex !in groups.indices) return
        val group = groups[groupIndex]
        if (trackIndex !in 0 until group.length) return

        castPlayer.trackSelectionParameters =
            castPlayer.trackSelectionParameters
                .buildUpon()
                .setTrackTypeDisabled(group.type, false)
                .setOverrideForType(
                    TrackSelectionOverride(group.mediaTrackGroup, trackIndex),
                )
                .build()
    }

    private fun setSubtitlesDisabled(disabled: Boolean) {
        castPlayer.trackSelectionParameters =
            castPlayer.trackSelectionParameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, disabled)
                .build()
    }

    private fun trackList(trackType: Int): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        castPlayer.currentTracks.groups.forEachIndexed { groupIndex, group ->
            if (group.type != trackType) return@forEachIndexed
            for (trackIndex in 0 until group.length) {
                val format = group.getTrackFormat(trackIndex)
                result.add(
                    mapOf(
                        "groupIndex" to groupIndex,
                        "trackIndex" to trackIndex,
                        "language" to format.language,
                        "label" to format.label,
                        "sampleMimeType" to format.sampleMimeType,
                        "selected" to group.isTrackSelected(trackIndex),
                        "supported" to group.isTrackSupported(trackIndex),
                    ),
                )
            }
        }
        return result
    }

    private fun logSelectedTracks(tracks: Tracks) {
        tracks.groups.forEachIndexed { groupIndex, group ->
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSelected(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                if (group.type == C.TRACK_TYPE_AUDIO) {
                    val language = displayLanguage(format.language, format.label)
                    emitLog(
                        "[Player] Pista de audio seleccionada: $language " +
                            "(index $trackIndex, grupo $groupIndex)",
                    )
                } else if (group.type == C.TRACK_TYPE_TEXT) {
                    val language = displayLanguage(format.language, format.label)
                    emitLog(
                        "[Player] Subtítulo seleccionado: $language " +
                            "(index $trackIndex, grupo $groupIndex)",
                    )
                }
            }
        }
    }

    private fun subtitleConfigurations(raw: Any?): List<MediaItem.SubtitleConfiguration> {
        if (raw !is List<*>) return emptyList()

        return raw.mapNotNull { item ->
            if (item !is Map<*, *>) return@mapNotNull null
            val url = item["uri"]?.toString()?.trim().orEmpty()
            if (url.isEmpty()) return@mapNotNull null
            val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return@mapNotNull null
            val language = item["language"]?.toString()?.takeIf { it.isNotBlank() }
            val explicitMime = item["mimeType"]?.toString()?.takeIf { it.isNotBlank() }
            val path = uri.path.orEmpty().lowercase()
            val mimeType =
                explicitMime ?: when {
                    path.endsWith(".vtt") -> MimeTypes.TEXT_VTT
                    path.endsWith(".srt") -> MimeTypes.APPLICATION_SUBRIP
                    else -> MimeTypes.TEXT_VTT
                }

            MediaItem.SubtitleConfiguration.Builder(uri)
                .setMimeType(mimeType)
                .apply {
                    if (language != null) setLanguage(language)
                }
                .build()
        }
    }

    private fun toggleCast() {
        routeButton.performClick()
    }

    private fun isLatinoSpanish(language: String?, label: String?): Boolean {
        val value = "${language ?: ""} ${label ?: ""}".lowercase().trim()
        return value.contains("es-mx") ||
            value.contains("es-419") ||
            value.contains("latino") ||
            value.contains("latin spanish")
    }

    private fun isSpanish(language: String?, label: String?): Boolean {
        val value = "${language ?: ""} ${label ?: ""}".lowercase().trim()
        return value == "es" ||
            value.contains("es-") ||
            value.contains("spa") ||
            value.contains("spanish") ||
            value.contains("español") ||
            value.contains("latino") ||
            value.contains("castellano")
    }

    private fun isEnglish(language: String?, label: String?): Boolean {
        val value = "${language ?: ""} ${label ?: ""}".lowercase().trim()
        return value == "en" ||
            value.contains("en-") ||
            value.contains("eng") ||
            value.contains("english")
    }

    private fun displayLanguage(language: String?, label: String?): String {
        return when {
            isLatinoSpanish(language, label) -> "español latino"
            isSpanish(language, label) -> "español"
            isEnglish(language, label) -> "inglés"
            !label.isNullOrBlank() -> label
            !language.isNullOrBlank() -> language
            else -> "desconocido"
        }
    }

    private fun emitLog(message: String) {
        channel.invokeMethod("playerLog", message)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "toggleCast" -> {
                toggleCast()
                result.success(null)
            }

            "playPause" -> {
                if (castPlayer.isPlaying) {
                    castPlayer.pause()
                } else {
                    castPlayer.play()
                }
                result.success(null)
            }

            "seekTo" -> {
                val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                castPlayer.seekTo(positionMs.coerceAtLeast(0L))
                result.success(null)
            }

            "getState" -> {
                result.success(
                    mapOf(
                        "positionMs" to castPlayer.currentPosition,
                        "durationMs" to castPlayer.duration.coerceAtLeast(0L),
                        "isPlaying" to castPlayer.isPlaying,
                        "isCasting" to
                            (castPlayer.deviceInfo.playbackType ==
                                DeviceInfo.PLAYBACK_TYPE_REMOTE),
                    ),
                )
            }

            "getAudioTracks" -> result.success(trackList(C.TRACK_TYPE_AUDIO))
            "getSubtitleTracks" -> result.success(trackList(C.TRACK_TYPE_TEXT))

            "selectAudioTrack" -> {
                val groupIndex = call.argument<Number>("groupIndex")?.toInt() ?: -1
                val trackIndex = call.argument<Number>("trackIndex")?.toInt() ?: -1
                selectTrack(groupIndex, trackIndex)
                logSelectedTracks(castPlayer.currentTracks)
                result.success(null)
            }

            "selectSubtitleTrack" -> {
                val groupIndex = call.argument<Number>("groupIndex")?.toInt() ?: -1
                val trackIndex = call.argument<Number>("trackIndex")?.toInt() ?: -1
                selectTrack(groupIndex, trackIndex)
                logSelectedTracks(castPlayer.currentTracks)
                result.success(null)
            }

            "disableSubtitles" -> {
                setSubtitlesDisabled(true)
                emitLog("[Player] Subtítulos desactivados manualmente")
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        cancelStallWatchdog()
        channel.setMethodCallHandler(null)
        playerView.player = null
        mediaSession.release()
        castPlayer.release()
        localPlayer.release()
    }

    private data class TrackRef(
        val groupIndex: Int,
        val trackIndex: Int,
    )
}
