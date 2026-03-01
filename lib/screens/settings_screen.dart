import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/playlist_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, topPad + 20, 20, 0),
              child: ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                    colors: [kPrimary, kSecondary]).createShader(b),
                child: const Text('Réglages',
                    style: TextStyle(fontFamily: 'SuperWonder',
                        color: Colors.white, fontSize: 26)),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(children: [
                // Logo
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: kPrimary.withOpacity(0.4), blurRadius: 24)],
                  ),
                  child: ClipOval(child: Image.asset(
                      'assets/images/logo.png', fit: BoxFit.cover)),
                ),
                const SizedBox(height: 12),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                      colors: [kPrimary, kSecondary, kAccent]).createShader(b),
                  child: const Text('Calatube',
                      style: TextStyle(fontFamily: 'SuperWonder',
                          color: Colors.white, fontSize: 28, letterSpacing: 1.5)),
                ),
                const SizedBox(height: 4),
                Text('YouTube Music, sans pub',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3), fontSize: 13)),
                const SizedBox(height: 32),

                // Info comment ça marche
                _InfoCard(
                  icon: Icons.block,
                  color: kAccent,
                  title: 'Blocage des publicités',
                  description:
                      'Les pubs YouTube sont bloquées via injection JavaScript directe dans la WebView, exactement comme NouTube. Aucun serveur tiers requis.',
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.play_circle_outline,
                  color: kSecondary,
                  title: 'Lecture YouTube native',
                  description:
                      'Les vidéos jouent directement via le player YouTube mobile — qualité audio maximale, listes de lecture, historique.',
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.library_music,
                  color: kPrimary,
                  title: 'Bibliothèque locale',
                  description:
                      'Sauvegardez vos favoris dans des playlists locales. Les vidéos s\'ouvrent directement dans la WebView.',
                ),
                const SizedBox(height: 24),

                // Version
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kBgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline,
                        color: Colors.white.withOpacity(0.3), size: 18),
                    const SizedBox(width: 10),
                    Text('Calatube v1.0  •  Usage personnel',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.3), fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 120),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  const _InfoCard({required this.icon, required this.color,
      required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kBgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 5),
          Text(description, style: TextStyle(
              color: Colors.white.withOpacity(0.45), fontSize: 12, height: 1.4)),
        ])),
      ]),
    );
  }
}
