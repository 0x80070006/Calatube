import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../main.dart';

// MethodChannel vers le service Android natif
const _kMediaChannel = MethodChannel('com.calatube.app/media');

// ─────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────

const _kHomeUrl    = 'https://music.youtube.com/';
const _kLoginUrl   = 'https://accounts.google.com/ServiceLogin'
    '?service=youtube&continue=https://music.youtube.com/';

/// Domaines bloqués au niveau NavigationDelegate (avant tout fetch réseau).
const _kBlockedHosts = <String>[
  'doubleclick.net',
  'googleadservices.com',
  'googlesyndication.com',
  'google-analytics.com',
  'googletagmanager.com',
  'amazon-adsystem.com',
  'scorecardresearch.com',
  'omtrdc.net',
  'adnxs.com',
  'casalemedia.com',
  'pubmatic.com',
  'openx.net',
  'rubiconproject.com',
  'outbrain.com',
  'taboola.com',
  'criteo.com',
  'hotjar.com',
  'chartbeat.com',
  'advertising.com',
  'adform.net',
  'smartadserver.com',
  'sizmek.com',
  'adsrvr.org',
];

/// Schémas non-web à bloquer.
const _kBlockedSchemes = <String>[
  'vnd.youtube',
  'intent://',
  'market://',
  'tel:',
  'sms:',
  'mailto:',
];

// ─────────────────────────────────────────────────────────────────
// MAIN SHELL
// ─────────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {

  // ── WebView ──────────────────────────────────────────────────────
  WebViewController? _wvc;          // nullable : non-initialisé tant que async pas fini
  bool   _webReady    = false;      // true seulement après onPageFinished
  bool   _webLoading  = false;
  bool   _canGoBack   = false;
  bool   _webError    = false;      // true si erreur de chargement
  String _webErrorMsg = '';
  String _injectScript = '';        // cache du script JS

  // ── Now Playing ──────────────────────────────────────────────────
  String _npTitle    = '';
  String _npArtist   = '';
  String _npThumb    = '';
  bool   _npPlay     = false;
  int    _npPosSec   = 0;    // position en secondes (pour le service Android)
  int    _npDurSec   = 0;    // durée en secondes

  // ── Tab ──────────────────────────────────────────────────────────
  int _tab = 0; // 0=Home 1=Search 2=Library 3=Settings

  // ── Search ───────────────────────────────────────────────────────
  final _searchCtrl  = TextEditingController();
  final _searchFocus = FocusNode();

  // ── Lifecycle ────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _setupMediaChannel();
    _initWebView();
  }

  @override
  void dispose() {
    // Déréférencer le handler du MethodChannel
    _kMediaChannel.setMethodCallHandler(null);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // METHODCHANNEL — Android ↔ Dart
  // ─────────────────────────────────────────────────────────────────

  void _setupMediaChannel() {
    // Réception des commandes venant du service Android
    // (boutons de la notification : play/pause/next/prev/seek)
    _kMediaChannel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method != 'mediaCommand') return;
      try {
        final args = call.arguments as Map?;
        if (args == null) return;
        final cmd = args['cmd'] as String? ?? '';
        final arg = (args['arg'] as num?)?.toInt() ?? 0;
        _handleMediaCommand(cmd, arg);
      } catch (e) {
        debugPrint('[Calatube] mediaCommand erreur : $e');
      }
    });
  }

  /// Relaie une commande du service Android vers la WebView JS.
  void _handleMediaCommand(String cmd, int arg) {
    debugPrint('[Calatube] mediaCommand: $cmd arg=$arg');
    switch (cmd) {
      case 'play':
        _jsCmd('play');
        if (mounted) setState(() => _npPlay = true);
        break;
      case 'pause':
        _jsCmd('pause');
        if (mounted) setState(() => _npPlay = false);
        break;
      case 'next':
        _jsCmd('next');
        break;
      case 'prev':
        _jsCmd('prev');
        break;
      case 'seek':
        // arg est en millisecondes (depuis Android), on convertit en secondes pour JS
        final posSec = (arg / 1000).round();
        _jsCmd('seek', posSec.toString());
        if (mounted) setState(() => _npPosSec = posSec);
        break;
    }
  }

  /// Envoie les métadonnées de lecture au service Android.
  Future<void> _notifyNowPlaying() async {
    try {
      await _kMediaChannel.invokeMethod('updateNowPlaying', {
        'title':    _npTitle,
        'artist':   _npArtist,
        'thumb':    _npThumb,
        'playing':  _npPlay,
        'duration': _npDurSec,   // en secondes — le service convertit en ms
      });
    } on PlatformException catch (e) {
      debugPrint('[Calatube] updateNowPlaying PlatformException: ${e.message}');
    } catch (e) {
      debugPrint('[Calatube] updateNowPlaying erreur : $e');
    }
  }

  /// Envoie la position de lecture au service Android.
  Future<void> _notifyProgress() async {
    try {
      await _kMediaChannel.invokeMethod('updateProgress', {
        'playing': _npPlay,
        'pos':     _npPosSec,    // en secondes — le service convertit en ms
      });
    } on PlatformException catch (e) {
      debugPrint('[Calatube] updateProgress PlatformException: ${e.message}');
    } catch (e) {
      debugPrint('[Calatube] updateProgress erreur : $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // WEBVIEW INIT
  // ─────────────────────────────────────────────────────────────────
  Future<void> _initWebView() async {
    // 1. Charger le script JS (une seule fois, mis en cache)
    try {
      _injectScript = await rootBundle.loadString('assets/noutube_inject.js');
    } catch (e) {
      debugPrint('[Calatube] Impossible de charger le script d\'injection : $e');
      _injectScript = ''; // Continue sans script plutôt que de crasher
    }

    final wvc = WebViewController();

    try {
      await wvc.setJavaScriptMode(JavaScriptMode.unrestricted);

      await wvc.setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
      );

      await wvc.addJavaScriptChannel(
        'CalatubeFlutter',
        onMessageReceived: _onBridgeMessage,
      );

      await wvc.setNavigationDelegate(NavigationDelegate(
        onPageStarted:    _onPageStarted,
        onPageFinished:   _onPageFinished,
        onWebResourceError: _onWebError,
        onNavigationRequest: _onNavigationRequest,
      ));

      await wvc.setBackgroundColor(kBg);
      await wvc.loadRequest(Uri.parse(_kHomeUrl));

      // Assigner seulement si tout s'est bien passé
      if (mounted) setState(() => _wvc = wvc);

    } catch (e) {
      debugPrint('[Calatube] Erreur init WebView : $e');
      if (mounted) {
        setState(() {
          _webError    = true;
          _webErrorMsg = 'Impossible d\'initialiser le navigateur.';
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // NAVIGATION DELEGATE CALLBACKS
  // ─────────────────────────────────────────────────────────────────
  void _onPageStarted(String url) {
    if (!mounted) return;
    setState(() {
      _webLoading = true;
      _webError   = false;
    });
    // Injecter le script dès le début (avant que la page soit parsée)
    _runScript();
  }

  Future<void> _onPageFinished(String url) async {
    if (!mounted) return;
    // Re-injecter en fin de page pour les SPAs (YouTube Music est une SPA)
    await _runScript();

    bool back = false;
    try {
      back = await _wvc!.canGoBack();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _webLoading = false;
        _canGoBack  = back;
        _webReady   = true;  // Marquer prêt seulement après le 1er chargement réel
        _webError   = false;
      });
    }
  }

  void _onWebError(WebResourceError error) {
    // Ignorer les erreurs sur les sous-ressources bloquées (trackers)
    // On ne montre une erreur que si c'est la page principale
    if (error.isForMainFrame == true) {
      debugPrint('[Calatube] WebView error: ${error.description} (${error.errorCode})');
      if (mounted) {
        setState(() {
          _webLoading  = false;
          _webError    = true;
          _webErrorMsg = _friendlyError(error.errorCode);
        });
      }
    }
  }

  NavigationDecision _onNavigationRequest(NavigationRequest req) {
    final url = req.url;

    // Bloquer les schémas non-web
    for (final scheme in _kBlockedSchemes) {
      if (url.startsWith(scheme)) return NavigationDecision.prevent;
    }

    // Parser l'URL de façon sûre
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return NavigationDecision.prevent;

    // Bloquer les trackers / ad-networks par domaine
    final host = uri.host.toLowerCase();
    for (final blocked in _kBlockedHosts) {
      if (host == blocked || host.endsWith('.$blocked')) {
        debugPrint('[Calatube] Blocked host: $host');
        return NavigationDecision.prevent;
      }
    }

    // Bloquer les endpoints pub sur youtube.com lui-même (par chemin)
    final fullUrl = uri.toString();
    const blockedPaths = <String>[
      '/pagead/',
      '/ptracking',
      '/api/stats/ads',
      '/videogoodput',
      '/generate_204',
      '/gen_204',
      '/log_event',
      '/adview',
      '/aclk',
    ];
    final path = uri.path;
    for (final p in blockedPaths) {
      if (path.startsWith(p) || fullUrl.contains(p)) {
        debugPrint('[Calatube] Blocked path: $path');
        return NavigationDecision.prevent;
      }
    }

    return NavigationDecision.navigate;
  }

  // ─────────────────────────────────────────────────────────────────
  // JS BRIDGE
  // ─────────────────────────────────────────────────────────────────
  void _onBridgeMessage(JavaScriptMessage msg) {
    if (!mounted) return;
    try {
      final raw = msg.message;
      if (raw.isEmpty) return;

      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return;

      final type = data['type'] as String?;
      switch (type) {
        case 'nowPlaying':
          final title   = _safeStr(data['title']);
          final artist  = _safeStr(data['artist']);
          final thumb   = _safeStr(data['thumb']);
          final playing = data['playing'] == true;
          final durSec  = (data['duration'] as num?)?.toInt() ?? 0;

          setState(() {
            _npTitle  = title;
            _npArtist = artist;
            _npThumb  = thumb;
            _npPlay   = playing;
            _npDurSec = durSec;
          });

          // Relayer au service Android (notification)
          _notifyNowPlaying();
          break;

        case 'progress':
          final playing = data['playing'] == true;
          final posSec  = (data['pos'] as num?)?.toInt() ?? 0;

          setState(() {
            _npPlay   = playing;
            _npPosSec = posSec;
          });

          // Relayer au service Android (mise à jour position)
          _notifyProgress();
          break;
      }
    } on FormatException catch (e) {
      debugPrint('[Calatube] Bridge JSON invalide : $e');
    } catch (e) {
      debugPrint('[Calatube] Bridge erreur : $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────

  /// Exécute le script JS injecté, silencieusement.
  Future<void> _runScript() async {
    if (_injectScript.isEmpty) return;
    try {
      await _wvc?.runJavaScript(_injectScript);
    } catch (e) {
      debugPrint('[Calatube] runJavaScript erreur : $e');
    }
  }

  /// Envoie une commande JS à la WebView de façon sécurisée.
  /// Échappe le paramètre pour éviter toute injection JS.
  void _jsCmd(String cmd, [String arg = '']) {
    // Valider cmd (alphanumérique uniquement)
    if (!RegExp(r'^[a-zA-Z]+$').hasMatch(cmd)) return;
    // Échapper arg pour l'intégrer dans une string JS
    final safeArg = arg
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\x00', '');
    try {
      _wvc?.runJavaScript(
          'if(typeof window.__calaCommand==="function")'
          '{window.__calaCommand("$cmd","$safeArg");}');
    } catch (e) {
      debugPrint('[Calatube] jsCmd erreur : $e');
    }
  }

  /// Charge une URL après validation.
  void _loadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('https') && !uri.isScheme('http'))) {
      debugPrint('[Calatube] URL invalide ignorée : $url');
      return;
    }
    try {
      _wvc?.loadRequest(uri);
    } catch (e) {
      debugPrint('[Calatube] loadRequest erreur : $e');
    }
  }

  /// Convertit un code d'erreur WebView en message lisible.
  String _friendlyError(int? code) {
    switch (code) {
      case -2:  return 'Impossible de se connecter au serveur.';
      case -6:  return 'Connexion internet introuvable.';
      case -8:  return 'Le chargement a pris trop longtemps.';
      case -101: return 'Connexion refusée.';
      default:  return 'Une erreur est survenue. Vérifiez votre connexion.';
    }
  }

  /// Extrait une String de façon sûre depuis un dynamic.
  static String _safeStr(dynamic v) =>
      (v is String) ? v.trim() : '';

  // ─────────────────────────────────────────────────────────────────
  // ACTIONS
  // ─────────────────────────────────────────────────────────────────
  void _goHome()  => _loadUrl(_kHomeUrl);
  void _goLogin() => _loadUrl(_kLoginUrl);

  void _doSearch(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    _searchCtrl.text = trimmed;
    _loadUrl('https://music.youtube.com/search?q=${Uri.encodeComponent(trimmed)}');
    if (mounted) setState(() => _tab = 0);
  }

  void _goLibraryUrl(String url) {
    _loadUrl(url);
    if (mounted) setState(() => _tab = 0);
  }

  // ─────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq     = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final botPad = mq.padding.bottom;
    final wvc    = _wvc;

    // Hauteur réservée pour le mini-player (0 si rien ne joue)
    final miniPlayerH = _npTitle.isNotEmpty ? 76.0 : 0.0;
    final navH        = 60.0 + botPad;
    final webBottom   = navH + miniPlayerH;

    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: false,
      body: Stack(children: [

        // ── WebView ────────────────────────────────────────────────
        Positioned.fill(
          bottom: webBottom,
          child: _buildWebArea(wvc, topPad),
        ),

        // ── Overlay natif (Search / Library / Settings) ────────────
        if (_tab == 1)
          Positioned.fill(
            bottom: webBottom,
            child: _SearchOverlay(
              topPad:   topPad,
              ctrl:     _searchCtrl,
              focus:    _searchFocus,
              onSearch: _doSearch,
            ),
          ),
        if (_tab == 2)
          Positioned.fill(
            bottom: webBottom,
            child: _LibraryOverlay(
              topPad: topPad,
              onTap:  _goLibraryUrl,
            ),
          ),
        if (_tab == 3)
          Positioned.fill(
            bottom: webBottom,
            child: _SettingsOverlay(
              topPad:  topPad,
              onLogin: _goLogin,
            ),
          ),

        // ── Top bar (Home uniquement) ──────────────────────────────
        if (_tab == 0)
          Positioned(top: 0, left: 0, right: 0,
            child: _TopBar(
              topPad:    topPad,
              loading:   _webLoading,
              canGoBack: _canGoBack,
              onBack:    () { try { _wvc?.goBack(); } catch (_) {} },
              onHome:    _goHome,
              onRefresh: () { try { _wvc?.reload(); } catch (_) {} },
              onLogin:   _goLogin,
            ),
          ),

        // ── Mini player ────────────────────────────────────────────
        if (_npTitle.isNotEmpty)
          Positioned(
            bottom: navH,
            left: 0, right: 0,
            height: miniPlayerH,
            child: _MiniPlayer(
              title:   _npTitle,
              artist:  _npArtist,
              thumb:   _npThumb,
              playing: _npPlay,
              onPlay:  () => _jsCmd('play'),
              onPause: () => _jsCmd('pause'),
              onTap:   () => setState(() => _tab = 0),
            ),
          ),

        // ── Bottom nav ─────────────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _BottomNav(
            current: _tab,
            botPad:  botPad,
            onTap: (i) {
              if (i == _tab) return; // Ignorer le tap sur l'onglet actif
              setState(() => _tab = i);
              if (i == 0) _goHome();
            },
          ),
        ),
      ]),
    );
  }

  // ── Web area (WebView, splash, erreur) ───────────────────────────
  Widget _buildWebArea(WebViewController? wvc, double topPad) {
    // Cas 1 : erreur de chargement
    if (_webError) return _ErrorView(
      topPad:  topPad,
      message: _webErrorMsg,
      onRetry: () {
        setState(() { _webError = false; _webLoading = true; });
        _loadUrl(_kHomeUrl);
      },
    );

    // Cas 2 : WebView pas encore créée → splash
    if (wvc == null) return _SplashView(topPad: topPad);

    // Cas 3 : WebView créée mais page pas encore chargée → splash + WebView invisible
    if (!_webReady) {
      return Stack(children: [
        Opacity(opacity: 0, child: WebViewWidget(controller: wvc)),
        _SplashView(topPad: topPad),
      ]);
    }

    // Cas 4 : normal
    return WebViewWidget(controller: wvc);
  }
}

// ─────────────────────────────────────────────────────────────────
// SPLASH
// ─────────────────────────────────────────────────────────────────
class _SplashView extends StatelessWidget {
  final double topPad;
  const _SplashView({required this.topPad});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      padding: EdgeInsets.only(top: topPad),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
              colors: [kPrimary, kSecondary, kAccent]).createShader(b),
          child: const Text('Calatube',
              style: TextStyle(fontFamily: 'SuperWonder',
                  color: Colors.white, fontSize: 36, letterSpacing: 1)),
        ),
        const SizedBox(height: 32),
        const SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(
                color: kPrimary, strokeWidth: 2)),
      ])),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// ERROR VIEW
// ─────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final double topPad;
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.topPad, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      padding: EdgeInsets.only(top: topPad),
      child: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, color: kPrimary.withOpacity(0.5), size: 56),
          const SizedBox(height: 20),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final double topPad;
  final bool loading, canGoBack;
  final VoidCallback onBack, onHome, onRefresh, onLogin;

  const _TopBar({
    required this.topPad,   required this.loading,
    required this.canGoBack,
    required this.onBack,   required this.onHome,
    required this.onRefresh, required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: kBg.withOpacity(0.88),
            padding: EdgeInsets.only(top: topPad + 4, bottom: 8, left: 8, right: 8),
            child: Row(children: [
              if (canGoBack)
                _NavBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack)
              else
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                        colors: [kPrimary, kSecondary]).createShader(b),
                    child: const Text('Calatube',
                        style: TextStyle(fontFamily: 'SuperWonder',
                            color: Colors.white, fontSize: 18)),
                  ),
                ),
              const Spacer(),
              _NavBtn(icon: Icons.person_outline_rounded, onTap: onLogin,
                  tooltip: 'Se connecter'),
              _NavBtn(icon: Icons.refresh_rounded, onTap: onRefresh),
              _NavBtn(icon: Icons.home_rounded,    onTap: onHome),
            ]),
          ),
        ),
      ),
      if (loading)
        LinearProgressIndicator(
          backgroundColor: Colors.transparent,
          valueColor: const AlwaysStoppedAnimation(kPrimary),
          minHeight: 2,
        ),
    ]);
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const _NavBtn({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 38, height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
            color: kBgSurface,
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: Colors.white.withOpacity(0.75), size: 20),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

// ─────────────────────────────────────────────────────────────────
// SEARCH OVERLAY
// ─────────────────────────────────────────────────────────────────
class _SearchOverlay extends StatelessWidget {
  final double topPad;
  final TextEditingController ctrl;
  final FocusNode focus;
  final void Function(String) onSearch;

  const _SearchOverlay({
    required this.topPad, required this.ctrl,
    required this.focus,  required this.onSearch,
  });

  static const _genres = <(String, String, String)>[
    ('Rap',       '🎤', 'rap'),
    ('R&B',       '🎷', 'r&b soul'),
    ('Jazz',      '🎺', 'jazz'),
    ('Techno',    '🎧', 'techno electronic'),
    ('Classique', '🎻', 'classical music'),
    ('Chill',     '🌊', 'chill lofi'),
    ('Sleep',     '🌙', 'sleep music'),
    ('Pop',       '🌟', 'pop hits'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      padding: EdgeInsets.only(top: topPad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Barre de recherche ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: kBgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kPrimary.withOpacity(0.3)),
                ),
                child: TextField(
                  controller: ctrl,
                  focusNode:  focus,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Artiste, titre, album…',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: kPrimary.withOpacity(0.7)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: onSearch,
                  // Limiter la longueur pour éviter les URLs trop longues
                  maxLength: 200,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: () => onSearch(ctrl.text),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPrimary, kSecondary]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.search_rounded, color: Colors.white),
              ),
            ),
          ]),
        ),

        // ── Label genres ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Text('GENRES',
              style: TextStyle(color: Colors.white.withOpacity(0.45),
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
        ),

        // ── Grille genres ─────────────────────────────────────────
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.8,
            children: _genres.map((g) => _GenreChip(
              emoji: g.$2,
              label: g.$1,
              onTap: () {
                ctrl.text = g.$1; // Afficher le label, pas la query
                onSearch(g.$3);
              },
            )).toList(),
          ),
        ),
      ]),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String emoji, label;
  final VoidCallback onTap;
  const _GenreChip({required this.emoji, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBgCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kPrimary.withOpacity(0.2)),
          ),
          child: Row(children: [
            const SizedBox(width: 14),
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Flexible(child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w500))),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// LIBRARY OVERLAY
// ─────────────────────────────────────────────────────────────────
class _LibraryOverlay extends StatelessWidget {
  final double topPad;
  final void Function(String url) onTap;
  const _LibraryOverlay({required this.topPad, required this.onTap});

  // URLs vérifiées, toutes en HTTPS
  static const _links = <(String, IconData, String)>[
    ('Playlists',    Icons.playlist_play_rounded, 'https://music.youtube.com/library/playlists'),
    ('Titres aimés', Icons.favorite_rounded,       'https://music.youtube.com/playlist?list=LM'),
    ('Albums',       Icons.album_rounded,           'https://music.youtube.com/library/albums'),
    ('Artistes',     Icons.people_rounded,          'https://music.youtube.com/library/artists'),
    ('Historique',   Icons.history_rounded,         'https://music.youtube.com/history'),
    ('Abonnements',  Icons.subscriptions_rounded,   'https://music.youtube.com/library/subscriptions'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      padding: EdgeInsets.only(top: topPad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: ShaderMask(
            shaderCallback: (b) => const LinearGradient(
                colors: [kPrimary, kSecondary]).createShader(b),
            child: const Text('Bibliothèque',
                style: TextStyle(fontFamily: 'SuperWonder',
                    color: Colors.white, fontSize: 22)),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _links.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Colors.white10, height: 1),
            itemBuilder: (_, i) {
              final l = _links[i];
              return ListTile(
                onTap: () => onTap(l.$3),
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: kBgSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(l.$2, color: kPrimary, size: 20),
                ),
                title: Text(l.$1,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.w500)),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.3)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// SETTINGS OVERLAY
// ─────────────────────────────────────────────────────────────────
class _SettingsOverlay extends StatelessWidget {
  final double topPad;
  final VoidCallback onLogin;
  const _SettingsOverlay({required this.topPad, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      padding: EdgeInsets.only(top: topPad),
      child: ListView(padding: EdgeInsets.zero, children: [
        // ── Titre ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: ShaderMask(
            shaderCallback: (b) => const LinearGradient(
                colors: [kPrimary, kSecondary]).createShader(b),
            child: const Text('Paramètres',
                style: TextStyle(fontFamily: 'SuperWonder',
                    color: Colors.white, fontSize: 22)),
          ),
        ),

        // ── Compte ────────────────────────────────────────────
        _Section(title: 'Compte', children: [
          _SettingsTile(
            icon: Icons.login_rounded,
            label: 'Se connecter à Google',
            subtitle: 'Accéder à vos playlists et historique',
            onTap: onLogin,
          ),
        ]),
        const SizedBox(height: 20),

        // ── Sécurité & Blocage ────────────────────────────────
        _Section(title: 'Sécurité & Blocage', children: [
          _SettingsTile(
            icon: Icons.block_rounded,
            label: 'Publicités',
            subtitle: 'Actif — CSS + API intercept + auto-skip',
            statusOk: true,
          ),
          _SettingsTile(
            icon: Icons.shield_rounded,
            label: 'Trackers réseau',
            subtitle: '${_kBlockedHosts.length} domaines bloqués',
            statusOk: true,
          ),
          _SettingsTile(
            icon: Icons.javascript_rounded,
            label: 'Injection JS',
            subtitle: 'Fetch, XHR et CSS interceptés',
            statusOk: true,
          ),
        ]),
        const SizedBox(height: 20),

        // ── Application ───────────────────────────────────────
        _Section(title: 'Application', children: [
          _SettingsTile(
            icon: Icons.music_note_rounded,
            label: 'Source',
            subtitle: 'music.youtube.com',
          ),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            label: 'Version',
            subtitle: 'Calatube 2.0',
          ),
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// SETTINGS COMPONENTS
// ─────────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title.toUpperCase(),
              style: TextStyle(color: kPrimary.withOpacity(0.8),
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ),
        Container(
          decoration: BoxDecoration(
            color: kBgCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: children),
        ),
      ]),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool statusOk;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.statusOk = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon,
          color: statusOk ? Colors.greenAccent.shade400 : kPrimary,
          size: 22),
      title: Text(label,
          style: const TextStyle(color: Colors.white,
              fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12))
          : null,
      trailing: onTap != null
          ? Icon(Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.3))
          : statusOk
              ? Icon(Icons.check_circle_rounded,
                  color: Colors.greenAccent.shade400, size: 18)
              : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// MINI PLAYER
// ─────────────────────────────────────────────────────────────────
class _MiniPlayer extends StatelessWidget {
  final String title, artist, thumb;
  final bool playing;
  final VoidCallback onPlay, onPause, onTap;

  const _MiniPlayer({
    required this.title,  required this.artist, required this.thumb,
    required this.playing,
    required this.onPlay, required this.onPause, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: kBgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPrimary.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4),
                blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(children: [
          // ── Thumbnail ────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(15),
              bottomLeft: Radius.circular(15),
            ),
            child: _Thumb(url: thumb, size: 64),
          ),

          const SizedBox(width: 12),

          // ── Titre + Artiste ───────────────────────────────────
          Expanded(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w600)),
              if (artist.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 11)),
              ],
            ],
          )),

          // ── Bouton Play/Pause ─────────────────────────────────
          GestureDetector(
            onTap: playing ? onPause : onPlay,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40, height: 40,
              margin: const EdgeInsets.only(right: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [kPrimary, kSecondary]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 22,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Widget thumbnail avec fallback robuste.
class _Thumb extends StatelessWidget {
  final String url;
  final double size;
  const _Thumb({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty || !url.startsWith('http')) {
      return _placeholder();
    }
    return Image.network(
      url,
      width: size, height: size,
      fit: BoxFit.cover,
      // Timeout via headers
      headers: const {'Connection': 'keep-alive'},
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _placeholder(),
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
    width: size, height: size,
    color: kBgSurface,
    child: const Icon(Icons.music_note_rounded, color: kPrimary, size: 28),
  );
}

// ─────────────────────────────────────────────────────────────────
// BOTTOM NAV
// ─────────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int current;
  final double botPad;
  final void Function(int) onTap;

  const _BottomNav({
    required this.current, required this.botPad, required this.onTap,
  });

  static const _items = <(IconData, IconData, String)>[
    (Icons.home_filled,           Icons.home_outlined,          'Accueil'),
    (Icons.search_rounded,        Icons.search_rounded,         'Recherche'),
    (Icons.library_music_rounded, Icons.library_music_outlined, 'Biblio'),
    (Icons.settings_rounded,      Icons.settings_outlined,      'Réglages'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: kBg.withOpacity(0.92),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: List.generate(_items.length, (i) {
                  final sel  = i == current;
                  final item = _items[i];
                  return Expanded(
                    child: InkWell(
                      onTap: () => onTap(i),
                      child: SizedBox.expand(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                sel ? item.$1 : item.$2,
                                key: ValueKey(sel),
                                color: sel
                                    ? kPrimary
                                    : Colors.white.withOpacity(0.3),
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(item.$3,
                                style: TextStyle(
                                  color: sel
                                      ? kPrimary
                                      : Colors.white.withOpacity(0.25),
                                  fontSize: 9,
                                  fontWeight: sel
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                )),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
