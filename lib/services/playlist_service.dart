import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track_model.dart';

class PlaylistService extends ChangeNotifier {
  List<PlaylistModel> _playlists = [];
  List<PlaylistModel> get playlists => _playlists;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('playlists_v2');
    if (saved != null) {
      try {
        final list = jsonDecode(saved) as List;
        _playlists = list
            .map((e) => PlaylistModel.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playlists_v2',
        jsonEncode(_playlists.map((p) => p.toJson()).toList()));
  }

  PlaylistModel createPlaylist(String name, {String? thumbnailUrl}) {
    final pl = PlaylistModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name, source: 'local',
      thumbnailUrl: thumbnailUrl, tracks: [],
    );
    _playlists.insert(0, pl);
    _save();
    notifyListeners();
    return pl;
  }

  void addTrackToPlaylist(String playlistId, TrackModel track) {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    if (_playlists[idx].tracks.any((t) => t.id == track.id)) return;
    _playlists[idx].tracks.insert(0, track);
    _save();
    notifyListeners();
  }

  void removeTrackFromPlaylist(String playlistId, String trackId) {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    _playlists[idx].tracks.removeWhere((t) => t.id == trackId);
    _save();
    notifyListeners();
  }

  void deletePlaylist(String id) {
    _playlists.removeWhere((p) => p.id == id);
    _save();
    notifyListeners();
  }

  void renamePlaylist(String id, String newName) {
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final pl = _playlists[idx];
    _playlists[idx] = PlaylistModel(
      id: pl.id, name: newName, source: pl.source,
      thumbnailUrl: pl.thumbnailUrl, tracks: pl.tracks,
    );
    _save();
    notifyListeners();
  }
}
