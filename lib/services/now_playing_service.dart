import 'package:flutter/foundation.dart';

class NowPlayingService extends ChangeNotifier {
  static final NowPlayingService instance = NowPlayingService._();
  NowPlayingService._();

  String title  = '';
  String artist = '';
  String thumb  = '';
  bool isPlaying = false;
  int durationMs = 0;
  int posMs      = 0;

  void update({
    required String title,
    required String artist,
    required String thumb,
    required bool isPlaying,
    required int duration,
  }) {
    this.title     = title;
    this.artist    = artist;
    this.thumb     = thumb;
    this.isPlaying = isPlaying;
    this.durationMs = duration;
    notifyListeners();
  }

  void updateState({required bool isPlaying, required int pos}) {
    this.isPlaying = isPlaying;
    this.posMs     = pos;
    notifyListeners();
  }
}
