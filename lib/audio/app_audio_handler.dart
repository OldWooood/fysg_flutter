import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  Future<void> setNowPlaying(Song? song) async {
    if (song == null) return;
    mediaItem.add(
      MediaItem(
        id: '${song.id}',
        title: song.name,
        artist: song.artist ?? 'Unknown Artist',
        album: song.album,
        artUri: song.cover == null ? null : Uri.tryParse(song.cover!),
      ),
    );
  }

  void setPlayback({
    required bool isPlaying,
    required Duration position,
    required Duration bufferedPosition,
    required double speed,
    required ProcessingState processingState,
  }) {
    playbackState.add(
      PlaybackState(
        controls: const [],
        systemActions: const {},
        androidCompactActionIndices: const [],
        processingState: _mapState(processingState),
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: speed,
      ),
    );
  }

  AudioProcessingState _mapState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}

class AppAudioService {
  static AppAudioHandler? _handler;

  static Future<void> init() async {
    if (_handler != null) return;
    _handler = await AudioService.init(
      builder: () => AppAudioHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.fysg.flutter.fysg_flutter.audio',
        androidNotificationChannelName: 'Music Playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
  }

  static AppAudioHandler? get handler => _handler;
}
