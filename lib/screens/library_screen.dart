import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/track_model.dart';
import '../services/playlist_service.dart';
import 'youtube_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PlaylistService>();
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, topPad + 20, 20, 8),
            child: Row(children: [
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                    colors: [kPrimary, kSecondary]).createShader(b),
                child: const Text('Ma Biblio',
                    style: TextStyle(fontFamily: 'SuperWonder',
                        color: Colors.white, fontSize: 26)),
              ),
              const Spacer(),
              // Bouton nouvelle playlist locale
              GestureDetector(
                onTap: () => _newLocalPlaylist(context, ps),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPrimary, kAccent]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('Nouvelle', style: TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
          ),
        ),

        // ── Playlists YouTube Music (via WebView) ──────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              const Icon(Icons.cloud_outlined, color: Color(0xFFFF0000), size: 14),
              const SizedBox(width: 6),
              Text('YouTube Music', style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(delegate: SliverChildListDelegate([
            // Playlists sauvegardées
            _YTTile(
              icon: Icons.favorite_rounded,
              color: const Color(0xFFFF0000),
              title: 'Titres aimés',
              subtitle: 'Vos likes YouTube Music',
              url: 'https://music.youtube.com/playlist?list=LM',
            ),
            _YTTile(
              icon: Icons.playlist_play_rounded,
              color: kPrimary,
              title: 'Mes playlists',
              subtitle: 'Toutes vos playlists YouTube',
              url: 'https://music.youtube.com/library/playlists',
            ),
            _YTTile(
              icon: Icons.history_rounded,
              color: kSecondary,
              title: 'Historique',
              subtitle: 'Titres récemment écoutés',
              url: 'https://music.youtube.com/history',
            ),
            _YTTile(
              icon: Icons.album_rounded,
              color: kAccent,
              title: 'Albums sauvegardés',
              subtitle: 'Vos albums YouTube Music',
              url: 'https://music.youtube.com/library/albums',
            ),
            _YTTile(
              icon: Icons.person_rounded,
              color: const Color(0xFF22C55E),
              title: 'Artistes suivis',
              subtitle: 'Artistes que vous suivez',
              url: 'https://music.youtube.com/library/artists',
            ),
            // Créer une playlist directement sur YouTube Music
            _YTCreateTile(),
          ])),
        ),

        // ── Playlists locales ──────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(children: [
              Icon(Icons.phone_android, color: Colors.white.withOpacity(0.3), size: 14),
              const SizedBox(width: 6),
              Text('Sur cet appareil', style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ]),
          ),
        ),

        if (ps.playlists.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text('Aucune playlist locale. Appuie sur + Nouvelle pour en créer une.',
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
              (ctx, i) => _LocalPlaylistTile(
                playlist: ps.playlists[i],
                onDelete: () => ps.deletePlaylist(ps.playlists[i].id),
              ),
              childCount: ps.playlists.length,
            )),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ]),
    );
  }

  void _newLocalPlaylist(BuildContext ctx, PlaylistService ps) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: kBgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nouvelle playlist',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nom de la playlist',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: kPrimary.withOpacity(0.4))),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: kPrimary)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Annuler',
                  style: TextStyle(color: Colors.white.withOpacity(0.4)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Créer',
                  style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) ps.createPlaylist(name);
  }
}

// ── Tile YouTube Music ────────────────────────────────────────────
class _YTTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle, url;
  const _YTTile({required this.icon, required this.color,
      required this.title, required this.subtitle, required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => YouTubeScreen(initialUrl: url))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kBgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.12)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 12)),
          ])),
          Icon(Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.2), size: 20),
        ]),
      ),
    );
  }
}

// ── Tile créer une playlist YouTube ──────────────────────────────
class _YTCreateTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const YouTubeScreen(
              initialUrl: 'https://music.youtube.com/library/playlists'))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            kPrimary.withOpacity(0.15),
            kAccent.withOpacity(0.1),
          ]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPrimary.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPrimary, kAccent]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Créer une playlist',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text('Directement sur YouTube Music',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
          ])),
          Icon(Icons.open_in_new_rounded,
              color: kPrimary.withOpacity(0.6), size: 18),
        ]),
      ),
    );
  }
}

// ── Tile locale ───────────────────────────────────────────────────
class _LocalPlaylistTile extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback onDelete;
  const _LocalPlaylistTile({required this.playlist, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => _LocalPlaylistDetail(playlist: playlist))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kBgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                kPrimary.withOpacity(0.6), kAccent.withOpacity(0.4)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.queue_music, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(playlist.name, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 3),
            Text('${playlist.tracks.length} titre${playlist.tracks.length != 1 ? "s" : ""}',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
          ])),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context, backgroundColor: kBgSurface,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
              builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 8),
                Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: Colors.white24,
                        borderRadius: BorderRadius.circular(2))),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('Supprimer',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () { Navigator.pop(context); onDelete(); },
                ),
                const SizedBox(height: 16),
              ]),
            ),
            child: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.3)),
          ),
        ]),
      ),
    );
  }
}

class _LocalPlaylistDetail extends StatelessWidget {
  final PlaylistModel playlist;
  const _LocalPlaylistDetail({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(playlist.name, style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: playlist.tracks.isEmpty
          ? Center(child: Text('Playlist vide',
              style: TextStyle(color: Colors.white.withOpacity(0.4))))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: playlist.tracks.length,
              itemBuilder: (ctx, i) {
                final t = playlist.tracks[i];
                return GestureDetector(
                  onTap: () => Navigator.push(ctx, MaterialPageRoute(
                      builder: (_) => YouTubeScreen(
                          initialUrl: 'https://music.youtube.com/watch?v=${t.id}'))),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: kBgCard,
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: kBgSurface,
                            borderRadius: BorderRadius.circular(6)),
                        child: Icon(Icons.music_note, color: kPrimary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(t.title, style: const TextStyle(
                            color: Colors.white, fontSize: 13,
                            fontWeight: FontWeight.w600),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text(t.artist, style: TextStyle(
                            color: Colors.white.withOpacity(0.4), fontSize: 11)),
                      ])),
                      Icon(Icons.play_circle_outline, color: kPrimary, size: 24),
                    ]),
                  ),
                );
              }),
    );
  }
}
