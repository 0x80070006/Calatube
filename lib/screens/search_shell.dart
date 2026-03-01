import 'package:flutter/material.dart';
import '../main.dart';
import 'youtube_screen.dart';

class SearchShell extends StatefulWidget {
  const SearchShell({super.key});
  @override
  State<SearchShell> createState() => _SearchShellState();
}

class _SearchShellState extends State<SearchShell> {
  final _ctrl = TextEditingController();
  String? _query;

  final _suggestions = [
    '🔥 Top hits 2025', '🎵 Rap français', '💜 R&B Soul',
    '🎸 Rock classique', '🎹 Lofi beats', '🌍 Afrobeats',
    '🎤 Pop internationale', '🥁 Electronic', '🎺 Jazz', '🎻 Classique',
  ];

  void _search(String q) {
    if (q.trim().isEmpty) return;
    setState(() => _query = q.trim());
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    if (_query != null) {
      return Column(children: [
        // Barre de retour
        Container(
          padding: EdgeInsets.only(top: topPad + 6, bottom: 8, left: 8, right: 16),
          decoration: BoxDecoration(
            color: kBg,
            border: Border(bottom: BorderSide(color: kPrimary.withOpacity(0.15), width: 0.5)),
          ),
          child: Row(children: [
            GestureDetector(
              onTap: () => setState(() { _query = null; _ctrl.clear(); }),
              child: Container(
                width: 36, height: 36, margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: kBgSurface, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white.withOpacity(0.7), size: 18),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() { _query = null; }),
                child: Container(
                  height: 38, alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: kBgSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kPrimary.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Icon(Icons.search, color: kPrimary.withOpacity(0.6), size: 16),
                    const SizedBox(width: 6),
                    Text(_query!, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        Expanded(child: YouTubeScreen(
          initialUrl: 'https://music.youtube.com/search?q=${Uri.encodeComponent(_query!)}',
        )),
      ]);
    }

    // Écran de recherche
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, topPad + 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                        colors: [kPrimary, kSecondary]).createShader(b),
                    child: const Text('Rechercher',
                        style: TextStyle(fontFamily: 'SuperWonder',
                            color: Colors.white, fontSize: 26, letterSpacing: 1)),
                  ),
                  const SizedBox(height: 16),
                  // Barre de recherche
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: kBgSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kPrimary.withOpacity(0.25)),
                      boxShadow: [BoxShadow(
                          color: kPrimary.withOpacity(0.1), blurRadius: 20)],
                    ),
                    child: Row(children: [
                      const SizedBox(width: 14),
                      Icon(Icons.search, color: kPrimary.withOpacity(0.7), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Artiste, titre, album...',
                            hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.25), fontSize: 14),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: _search,
                          textInputAction: TextInputAction.search,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _search(_ctrl.text),
                        child: Container(
                          width: 42, height: 42, margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [kPrimary, kAccent]),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(Icons.arrow_forward_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 28),
                  Text('Suggestions',
                      style: TextStyle(color: Colors.white.withOpacity(0.4),
                          fontSize: 11, fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 10,
                mainAxisSpacing: 10, childAspectRatio: 3.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final s = _suggestions[i].replaceFirst(RegExp(r'^. '), '');
                  final emoji = _suggestions[i].split(' ').first;
                  return GestureDetector(
                    onTap: () => _search(s),
                    child: Container(
                      decoration: BoxDecoration(
                        color: kBgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kPrimary.withOpacity(0.12)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        Text(emoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 12, fontWeight: FontWeight.w500),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                  );
                },
                childCount: _suggestions.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}
