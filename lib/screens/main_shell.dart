import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart';
import 'youtube_screen.dart';
import 'search_shell.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const YouTubeScreen(),
      const SearchShell(),
      const LibraryScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: kBg,
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: kBg.withOpacity(0.93),
              border: Border(top: BorderSide(
                  color: kPrimary.withOpacity(0.18), width: 0.5)),
            ),
            padding: EdgeInsets.only(top: 8, bottom: bottomPad + 8),
            child: Row(
              children: [
                _item(0, Icons.play_circle_fill, Icons.play_circle_outline, 'YouTube'),
                _item(1, Icons.search_rounded, Icons.search_outlined, 'Recherche'),
                _item(2, Icons.library_music, Icons.library_music_outlined, 'Biblio'),
                _item(3, Icons.settings_rounded, Icons.settings_outlined, 'Réglages'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int idx, IconData active, IconData inactive, String label) {
    final selected = _index == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _index = idx),
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (b) => selected
                ? const LinearGradient(colors: [kPrimary, kSecondary]).createShader(b)
                : const LinearGradient(colors: [Colors.white38, Colors.white38]).createShader(b),
            child: Icon(selected ? active : inactive, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
            color: selected ? kPrimary : Colors.white.withOpacity(0.3),
            fontSize: 9,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          )),
        ]),
      ),
    );
  }
}
