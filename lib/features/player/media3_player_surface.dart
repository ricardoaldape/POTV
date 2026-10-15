import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/playback_session.dart';
import '../../domain/models/stream_candidate.dart';

class Media3PlayerState {
  final int positionMs;
  final int durationMs;
  final bool isPlaying;
  final bool isCasting;

  const Media3PlayerState({
    required this.positionMs,
    required this.durationMs,
    required this.isPlaying,
    required this.isCasting,
  });

  factory Media3PlayerState.fromMap(Map<Object?, Object?> raw) =>
      Media3PlayerState(
        positionMs: (raw['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
        isPlaying: raw['isPlaying'] == true,
        isCasting: raw['isCasting'] == true,
      );
}

class Media3Track {
  final int groupIndex;
  final int trackIndex;
  final String? language;
  final String? label;
  final bool selected;
  final bool supported;

  const Media3Track({
    required this.groupIndex,
    required this.trackIndex,
    this.language,
    this.label,
    required this.selected,
    required this.supported,
  });

  factory Media3Track.fromMap(Map<Object?, Object?> raw) => Media3Track(
        groupIndex: (raw['groupIndex'] as num?)?.toInt() ?? -1,
        trackIndex: (raw['trackIndex'] as num?)?.toInt() ?? -1,
        language: raw['language']?.toString(),
        label: raw['label']?.toString(),
        selected: raw['selected'] == true,
        supported: raw['supported'] == true,
      );

  String get displayName {
    final values = [
      label?.trim(),
      language?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).toSet();
    return values.isEmpty ? 'Pista ' + (trackIndex + 1).toString() : values.join(' · ');
  }
}

class Media3PlayerController {
  final MethodChannel _channel;

  Media3PlayerController(int viewId)
      : _channel = MethodChannel('potv/media3_cast/$viewId');

  void setHandlers({
    required ValueChanged<String> onLog,
    required ValueChanged<String> onError,
    required ValueChanged<int> onStarted,
    required VoidCallback onEnded,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'playerLog':
          onLog(call.arguments?.toString() ?? '');
          break;
        case 'playerError':
          onError(call.arguments?.toString() ?? 'Error de reproducción');
          break;
        case 'playbackStarted':
          onStarted((call.arguments as num?)?.toInt() ?? 0);
          break;
        case 'playbackEnded':
          onEnded();
          break;
      }
      return null;
    });
  }

  void dispose() => _channel.setMethodCallHandler(null);

  Future<void> toggleCast() => _channel.invokeMethod<void>('toggleCast');
  Future<void> playPause() => _channel.invokeMethod<void>('playPause');

  Future<void> seekTo(Duration position) => _channel.invokeMethod<void>(
        'seekTo',
        {'positionMs': position.inMilliseconds},
      );

  Future<Media3PlayerState?> state() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('getState');
    return raw == null ? null : Media3PlayerState.fromMap(raw);
  }

  Future<List<Media3Track>> audioTracks() => _tracks('getAudioTracks');
  Future<List<Media3Track>> subtitleTracks() => _tracks('getSubtitleTracks');

  Future<List<Media3Track>> _tracks(String method) async {
    final raw = await _channel.invokeListMethod<Object?>(method) ?? const [];
    return [
      for (final value in raw)
        if (value is Map)
          Media3Track.fromMap(Map<Object?, Object?>.from(value)),
    ];
  }

  Future<void> selectAudio(Media3Track track) =>
      _channel.invokeMethod<void>('selectAudioTrack', {
        'groupIndex': track.groupIndex,
        'trackIndex': track.trackIndex,
      });

  Future<void> selectSubtitle(Media3Track track) =>
      _channel.invokeMethod<void>('selectSubtitleTrack', {
        'groupIndex': track.groupIndex,
        'trackIndex': track.trackIndex,
      });

  Future<void> disableSubtitles() =>
      _channel.invokeMethod<void>('disableSubtitles');
}

class Media3PlayerSurface extends StatelessWidget {
  final StreamCandidate stream;
  final String title;
  final Duration? resumeAt;
  final String audioPreference;
  final String subtitlePreference;
  final List<PlaybackSubtitle> subtitles;
  final ValueChanged<Media3PlayerController> onController;

  const Media3PlayerSurface({
    super.key,
    required this.stream,
    required this.title,
    required this.resumeAt,
    required this.audioPreference,
    required this.subtitlePreference,
    required this.subtitles,
    required this.onController,
  });

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'potv/media3_cast_player',
      creationParams: <String, Object?>{
        'uri': stream.uri.toString(),
        'headers': stream.headers,
        'title': title,
        'startPositionMs': resumeAt?.inMilliseconds ?? 0,
        'audioPreference': audioPreference,
        'subtitlePreference': subtitlePreference,
        'autoplay': true,
        'subtitles': [
          for (final subtitle in subtitles)
            {
              'uri': subtitle.uri.toString(),
              'language': subtitle.language,
              'label': subtitle.label,
            },
        ],
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (viewId) {
        onController(Media3PlayerController(viewId));
      },
    );
  }
}
