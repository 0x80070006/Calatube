import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/track_model.dart';
import '../services/playlist_service.dart';

class PlaylistAddScreen extends StatelessWidget {
  final TrackModel track;
  const PlaylistAddScreen({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PlaylistService>();
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Ajouter à une playlist',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: ps.playlists.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.playlist_add, color: kPrimary.withOpacity(0.4), size: 56),
              const SizedBox(height: 12),
              Text('Créez d\'abord une playlist dans la bibliothèque',
                  style: TextStyle(color: Colors.white.withOpacity(0.4)),
                  textAlign: TextAlign.center),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: ps.playlists.length,
              itemBuilder: (ctx, i) {
                final pl = ps.playlists[i];
                final hasTrack = pl.tracks.any((t) => t.id == track.id);
                return ListTile(
                  leading: Container(width: 40, height: 40,
                      decoration: BoxDecoration(
                          color: kBgCard,
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                              colors: [kPrimary.withOpacity(0.4), kAccent.withOpacity(0.2)])),
                      child: const Icon(Icons.queue_music, color: Colors.white, size: 20)),
                  title: Text(pl.name, style: const TextStyle(color: Colors.white)),
                  subtitle: Text('${pl.tracks.length} vidéos',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                  trailing: hasTrack
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : Icon(Icons.add_circle_outline, color: kPrimary),
                  onTap: hasTrack ? null : () {
                    ps.addTrackToPlaylist(pl.id, track);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('Ajouté à "${pl.name}"'),
                        backgroundColor: kPrimary));
                  },
                );
              },
            ),
    );
  }
}
