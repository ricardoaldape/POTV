package com.potv.potv

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.cast.Cast
import androidx.media3.cast.CastPlayer
import androidx.media3.cast.MediaRouteButtonFactory
import androidx.media3.common.DeviceInfo
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
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
            ExoPlayer.Builder(context)
                .setMediaSourceFactory(
                    DefaultMediaSourceFactory(context).setDataSourceFactory(dataSourceFactory),
                )
                .build()

        castPlayer =
            CastPlayer.Builder(context)
                .setLocalPlayer(localPlayer)
                .build()

        mediaSession = MediaSession.Builder(context, castPlayer).build()

        playerView.player = castPlayer
        playerView.useController = true
        playerView.setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)

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
            val mediaItem =
                MediaItem.Builder()
                    .setUri(uri)
                    .setMediaMetadata(
                        MediaMetadata.Builder()
                            .setTitle(title)
                            .build(),
                    )
                    .build()

            castPlayer.setMediaItem(mediaItem)
            if (startPositionMs > 0L) {
                castPlayer.seekTo(startPositionMs)
            }
            castPlayer.prepare()
            castPlayer.playWhenReady = true
        }

        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = root

    private fun toggleCast() {
        routeButton.performClick()
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

            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        playerView.player = null
        mediaSession.release()
        castPlayer.release()
        localPlayer.release()
    }
}
