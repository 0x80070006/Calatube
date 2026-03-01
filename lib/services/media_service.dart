import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Pont Flutter → Android CalatubeMediaService
/// Envoie les infos de lecture pour la notification et le lockscreen
class MediaService {
  static final MediaService instance = MediaService._();
  MediaService._();

  static const _channel = MethodChannel('com.calatube.app/media');

  Future<void> updateNowPlaying({
    required String title,
    required String artist,
    required String thumb,
    required bool playing,
    required int duration,
  }) async {
    try {
      await _channel.invokeMethod('updateNowPlaying', {
        'title':    title,
        'artist':   artist,
        'thumb':    thumb,
        'playing':  playing,
        'duration': duration,
      });
    } catch (e) {
      debugPrint('MediaService.updateNowPlaying: $e');
    }
  }

  Future<void> updatePlayState({
    required bool playing,
    required int pos,
  }) async {
    try {
      await _channel.invokeMethod('updatePlayState', {
        'playing': playing,
        'pos':     pos,
      });
    } catch (e) {
      debugPrint('MediaService.updatePlayState: $e');
    }
  }
}
