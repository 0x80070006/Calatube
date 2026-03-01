import 'package:flutter/material.dart' show Color;

class TrackModel {
  final String id;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final String? album;
  final int? durationMs;
  final String source;

  const TrackModel({
    required this.id, required this.title, required this.artist,
    this.thumbnailUrl, this.album, this.durationMs, this.source = 'youtube',
  });

  String get displayImage => thumbnailUrl ?? '';

  String get durationFormatted {
    if (durationMs == null) return '';
    final s = durationMs! ~/ 1000;
    final m = s ~/ 60;
    final sec = s % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final min = m % 60;
      return '$h:${min.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
    }
    return '$m:${sec.toString().padLeft(2,'0')}';
  }

  String get youtubeUrl => 'https://m.youtube.com/watch?v=$id';

  TrackModel copyWith({String? title, String? artist, String? thumbnailUrl,
      String? album, int? durationMs, String? source}) => TrackModel(
    id: id, title: title ?? this.title, artist: artist ?? this.artist,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl, album: album ?? this.album,
    durationMs: durationMs ?? this.durationMs, source: source ?? this.source,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'artist': artist, 'thumbnailUrl': thumbnailUrl,
    'album': album, 'durationMs': durationMs, 'source': source,
  };

  factory TrackModel.fromJson(Map<String, dynamic> j) => TrackModel(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    artist: j['artist'] as String? ?? '',
    thumbnailUrl: j['thumbnailUrl'] as String?,
    album: j['album'] as String?,
    durationMs: j['durationMs'] as int?,
    source: j['source'] as String? ?? 'youtube',
  );
}

class PlaylistModel {
  final String id;
  String name;
  final String source;
  String? thumbnailUrl;
  List<TrackModel> tracks;
  Color? color;

  PlaylistModel({
    required this.id, required this.name, required this.source,
    this.thumbnailUrl, required this.tracks, this.color,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'source': source, 'thumbnailUrl': thumbnailUrl,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };

  factory PlaylistModel.fromJson(Map<String, dynamic> j) => PlaylistModel(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Playlist',
    source: j['source'] as String? ?? 'local',
    thumbnailUrl: j['thumbnailUrl'] as String?,
    tracks: ((j['tracks'] as List?) ?? [])
        .map((t) => TrackModel.fromJson(t as Map<String, dynamic>))
        .toList(),
  );
}
