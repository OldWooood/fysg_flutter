import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../api/image_cache_service.dart';
import '../models/song.dart';

/// PlayerNotifier 通过此抽象接口响应来自
/// 通知栏 / 锁屏 / 耳机线控 的播放控制指令。
abstract class AppAudioHandlerDelegate {
  void onPlay();
  void onPause();
  void onSkipToNext();
  void onSkipToPrevious();
  void onSeek(Duration position);
  void onStop();
}

class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  AppAudioHandlerDelegate? _delegate;

  /// PlayerNotifier 初始化后挂载自己，接收媒体控制回调。
  void attachDelegate(AppAudioHandlerDelegate delegate) {
    _delegate = delegate;
  }

  @override
  Future<void> play() async => _delegate?.onPlay();

  @override
  Future<void> pause() async => _delegate?.onPause();

  @override
  Future<void> skipToNext() async => _delegate?.onSkipToNext();

  @override
  Future<void> skipToPrevious() async => _delegate?.onSkipToPrevious();

  @override
  Future<void> seek(Duration position) async => _delegate?.onSeek(position);

  @override
  Future<void> stop() async => _delegate?.onStop();

  Future<void> setNowPlaying(Song? song) async {
    if (song == null) return;
    mediaItem.add(
      MediaItem(
        id: '${song.id}',
        title: song.name,
        artist: song.artist ?? 'Unknown Artist',
        album: song.album,
        artUri: song.cover == null ? null : Uri.tryParse(song.cover!),
        // 封面 CDN 需要带请求头才能加载
        artHeaders: ImageCacheService.headers,
      ),
    );
  }

  void setPlayback({
    required bool isPlaying,
    required bool hasCurrentSong,
    required Duration position,
    required Duration bufferedPosition,
    required double speed,
    required ProcessingState processingState,
  }) {
    if (!hasCurrentSong) {
      playbackState.add(
        PlaybackState(
          controls: const [],
          systemActions: const {},
          androidCompactActionIndices: const [],
          processingState: AudioProcessingState.idle,
          playing: false,
          updatePosition: position,
          bufferedPosition: bufferedPosition,
          speed: speed,
        ),
      );
      return;
    }

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
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
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  }

  static AppAudioHandler? get handler => _handler;
}
