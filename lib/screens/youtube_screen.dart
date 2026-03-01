import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../main.dart';
import '../services/media_service.dart';
import '../services/now_playing_service.dart';

class YouTubeScreen extends StatefulWidget {
  final String? initialUrl;
  final String? initialQuery;
  const YouTubeScreen({super.key, this.initialUrl, this.initialQuery});
  @override
  State<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends State<YouTubeScreen>
    with AutomaticKeepAliveClientMixin {
  late final WebViewController _ctrl;
  bool   _loading    = true;
  bool   _canGoBack  = false;
  String _title      = '';
  String _currentUrl = '';
  bool   _ready      = false;

  @override bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final script = await rootBundle.loadString('assets/noutube_inject.js');

    // Activer les cookies tiers (requis pour music.youtube.com)
    final cookieManager = WebViewCookieManager();
    // Pré-autoriser les domaines YouTube
    await cookieManager.setCookie(const WebViewCookie(
      name: '__Secure-YEC', value: '1',
      domain: '.youtube.com', path: '/',
    ));

    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setOnConsoleMessage((_) {}) // supprimer les logs console inutiles
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel('CalatubeFlutter', onMessageReceived: (msg) {
        _handleBridgeMessage(msg.message);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) async {
          setState(() { _loading = true; _currentUrl = url; });
          await _ctrl.runJavaScript(script);
        },
        onPageFinished: (url) async {
          setState(() { _loading = false; _currentUrl = url; });
          await _ctrl.runJavaScript(script);
          _canGoBack = await _ctrl.canGoBack();
          final t = await _ctrl.getTitle();
          setState(() {
            _canGoBack = _canGoBack;
            _title = (t ?? '').replaceAll(' - YouTube', '').replaceAll(' - YouTube Music','');
          });
        },
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri == null) return NavigationDecision.prevent;
          // Bloquer ouverture app YouTube / trackers
          if (req.url.startsWith('vnd.youtube') ||
              req.url.startsWith('intent://') ||
              uri.host.contains('doubleclick') ||
              uri.host.contains('googletagmanager') ||
              uri.host.contains('googlesyndication')) {
            return NavigationDecision.prevent;
          }
          // Autoriser YouTube + Google auth
          if (uri.host.contains('youtube.com') ||
              uri.host.contains('youtu.be') ||
              uri.host.contains('google.com') ||
              uri.host.contains('googleapis.com') ||
              uri.host.contains('googlevideo.com') ||
              uri.host.contains('ytimg.com') ||
              uri.host.contains('lh3.googleusercontent.com') ||
              uri.host.contains('ggpht.com') ||
              uri.host.contains('accounts.google')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..setBackgroundColor(kBg);

    String url;
    if (widget.initialUrl != null) {
      url = widget.initialUrl!;
    } else if (widget.initialQuery != null) {
      url = 'https://music.youtube.com/search?q='
          '${Uri.encodeComponent(widget.initialQuery!)}';
    } else {
      url = 'https://music.youtube.com/';
    }

    // Marquer ready AVANT loadRequest pour que WebViewWidget soit dans le tree
    if (mounted) setState(() => _ready = true);
    await _ctrl.loadRequest(Uri.parse(url));
  }

  void _handleBridgeMessage(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'nowPlaying':
          final t = msg['title']   as String? ?? '';
          final a = msg['artist']  as String? ?? '';
          final th = msg['thumb']  as String? ?? '';
          final pl = msg['playing'] as bool?  ?? false;
          final dur = (msg['duration'] as num?)?.toInt() ?? 0;
          NowPlayingService.instance.update(
            title: t, artist: a, thumb: th, isPlaying: pl, duration: dur);
          MediaService.instance.updateNowPlaying(
            title: t, artist: a, thumb: th, playing: pl, duration: dur);
          break;
        case 'playState':
          final playing2 = msg['playing'] as bool? ?? false;
          final pos2 = (msg['pos'] as num?)?.toInt() ?? 0;
          NowPlayingService.instance.updateState(isPlaying: playing2, pos: pos2);
          MediaService.instance.updatePlayState(playing: playing2, pos: pos2);
          break;
        case 'progress':
          final playing3 = msg['playing'] as bool? ?? false;
          final pos3 = (msg['pos'] as num?)?.toInt() ?? 0;
          NowPlayingService.instance.updateState(isPlaying: playing3, pos: pos3);
          MediaService.instance.updatePlayState(playing: playing3, pos: pos3);
          break;
      }
    } catch (e) {
      debugPrint('Bridge error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: kBg,
      body: Column(children: [
        // ── Top bar ────────────────────────────────────────────
        _TopBar(
          topPad:    topPad,
          title:     _title,
          canGoBack: _canGoBack,
          loading:   _loading,
          onBack:    () => _ctrl.goBack(),
          onHome:    () => _ctrl.loadRequest(Uri.parse('https://music.youtube.com/')),
          onRefresh: () => _ctrl.reload(),
          onLogin:   () => _ctrl.loadRequest(
              Uri.parse('https://accounts.google.com/ServiceLogin'
                  '?service=youtube&uilel=3&passive=true&continue='
                  'https://www.youtube.com/signin?action_handle_signin=true')),
        ),

        Expanded(child: Stack(children: [
          // WebView TOUJOURS dans le tree (même pendant init)
          Opacity(
            opacity: _ready ? 1.0 : 0.0,
            child: _ready ? WebViewWidget(controller: _ctrl) : const SizedBox.expand(),
          ),

          // Splash de démarrage
          if (!_ready)
            Container(
              color: kBg,
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                      colors: [kPrimary, kSecondary, kAccent]).createShader(b),
                  child: const Text('Calatube',
                      style: TextStyle(fontFamily: 'SuperWonder',
                          color: Colors.white, fontSize: 34)),
                ),
                const SizedBox(height: 28),
                const SizedBox(width: 28, height: 28,
                    child: CircularProgressIndicator(
                        color: kPrimary, strokeWidth: 2)),
              ])),
            ),

          // Barre de progression
          if (_loading && _currentUrl.isNotEmpty)
            Positioned(top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation(kPrimary),
                minHeight: 2,
              )),
        ])),
      ]),
    );
  }
}

class _TopBar extends StatelessWidget {
  final double topPad;
  final String title;
  final bool canGoBack, loading;
  final VoidCallback onBack, onHome, onRefresh, onLogin;

  const _TopBar({
    required this.topPad, required this.title,
    required this.canGoBack, required this.loading,
    required this.onBack, required this.onHome,
    required this.onRefresh, required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: topPad + 6, bottom: 8, left: 8, right: 8),
      decoration: BoxDecoration(
        color: kBg,
        border: Border(bottom: BorderSide(
            color: kPrimary.withOpacity(0.15), width: 0.5)),
      ),
      child: Row(children: [
        if (canGoBack)
          _btn(Icons.arrow_back_ios_new_rounded, onBack)
        else
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 4),
            child: ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                  colors: [kPrimary, kSecondary]).createShader(b),
              child: const Text('Calatube',
                  style: TextStyle(fontFamily: 'SuperWonder',
                      color: Colors.white, fontSize: 17, letterSpacing: 0.5)),
            ),
          ),
        const Spacer(),
        if (title.isNotEmpty)
          Flexible(child: Text(title,
              style: TextStyle(color: Colors.white.withOpacity(0.5),
                  fontSize: 11, fontWeight: FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
        const Spacer(),
        _btn(Icons.person_outline_rounded, onLogin, tooltip: 'Se connecter'),
        _btn(Icons.refresh_rounded, onRefresh, size: 20),
        _btn(Icons.home_rounded, onHome),
      ]),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap,
      {double size = 22, String? tooltip}) {
    final w = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: kBgSurface, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: Colors.white.withOpacity(0.7), size: size),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: w) : w;
  }
}
