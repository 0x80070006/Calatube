/**
 * Calatube — noutube_inject.js v6
 *
 * Technique copiée de NouTube (open source) :
 * → Strip de 4 clés API dans /youtubei/v1/player et /get_watch
 * → XHR intercepté via readystatechange (technique NouTube)
 * → CSS minimal
 * → ZÉRO logique de skip vidéo JS
 * → ZÉRO détection de durée
 * → ZÉRO timer de skip
 */
(function () {
  'use strict';

  if (window.__calaVersion >= 6) return;
  window.__calaVersion = 6;

  // ── Utilitaires ─────────────────────────────────────────────────
  function safe(fn) { try { return fn(); } catch (_) {} }
  function send(obj) {
    safe(function () {
      if (window.CalatubeFlutter && typeof window.CalatubeFlutter.postMessage === 'function')
        window.CalatubeFlutter.postMessage(JSON.stringify(obj));
    });
  }

  // ── État bridge ──────────────────────────────────────────────────
  var _lastTitle  = '';
  var _lastArtist = '';
  var _lastDur    = 0;
  var _userPaused = false;

  // ═══════════════════════════════════════════════════════════════
  // 1. CSS — masquer les éléments pub (minimal, comme NouTube)
  // ═══════════════════════════════════════════════════════════════
  function injectCSS() {
    if (document.getElementById('__cala_css')) return;
    var s = document.createElement('style');
    s.id = '__cala_css';
    s.textContent = [
      'ytd-page-top-ad-layout-renderer',
      'ytd-in-feed-ad-layout-renderer',
      'ad-slot-renderer',
      'yt-mealbar-promo-renderer',
      'ytm-promoted-sparkles-web-renderer',
      'ytmusic-mealbar-promo-renderer',
      'ytmusic-player-ad-badge-renderer',
      '.ytd-player-legacy-desktop-watch-ads-renderer',
      '.ytp-ad-module',
      '.ytp-ad-player-overlay',
      '.ytp-ad-player-overlay-layout',
      '.ytp-ad-skip-button-container',
      '.video-ads',
      'a.app-install-link',
      '.open-app-banner',
      '#open-app-banner',
    ].join(',') + '{display:none!important;}';
    (document.head || document.documentElement).appendChild(s);
  }
  injectCSS();
  document.addEventListener('DOMContentLoaded', injectCSS);

  // ═══════════════════════════════════════════════════════════════
  // 2. INTERCEPTION API — technique exacte de NouTube
  //    Strip de exactement 4 clés : adBreakHeartbeatParams,
  //    adPlacements, adSlots, playerAds
  //    (source : NouTube/lib/intercept.ts)
  // ═══════════════════════════════════════════════════════════════
  var AD_KEYS = ['adBreakHeartbeatParams', 'adPlacements', 'adSlots', 'playerAds'];
  var RE_API  = /\/youtubei\/v1\/(get_watch|player|search)/;

  function stripAdKeys(data) {
    AD_KEYS.forEach(function (k) { delete data[k]; });
    return data;
  }

  function transformPlayerResponse(text) {
    var data = JSON.parse(text);
    stripAdKeys(data);
    // Cas get_watch : wrapper array (comme NouTube transformGetWatchResponse)
    if (Array.isArray(data) && data[0] && data[0].playerResponse) {
      stripAdKeys(data[0].playerResponse);
    }
    return JSON.stringify(data);
  }

  // ── fetch wrapper (NouTube intercept.ts) ────────────────────────
  var _origFetch = window.fetch;
  if (typeof _origFetch === 'function') {
    window.fetch = function () {
      var args = arguments;
      var req  = args[0];
      var url  = '';
      try { url = req instanceof Request ? req.url : String(req || ''); } catch (_) {}

      if (!RE_API.test(url)) return _origFetch.apply(this, args);

      return _origFetch.apply(this, args).then(function (res) {
        if (res.status > 200) return res;
        return res.text().then(function (text) {
          var transformed;
          try { transformed = transformPlayerResponse(text); } catch (_) { transformed = text; }
          return new Response(transformed, { status: res.status, headers: res.headers });
        });
      });
    };
  }

  // ── XHR wrapper — technique NouTube (readystatechange) ─────────
  // https://stackoverflow.com/a/78369686
  var _origXhrOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    var self = this;
    var urlStr = String(url || '');
    if (urlStr.indexOf('youtubei/v1/player') !== -1) {
      self.addEventListener('readystatechange', function () {
        if (self.readyState === 4) {
          safe(function () {
            var transformed = transformPlayerResponse(self.responseText);
            Object.defineProperty(self, 'response',     { writable: true });
            Object.defineProperty(self, 'responseText', { writable: true });
            self.response = self.responseText = transformed;
          });
        }
      });
    }
    return _origXhrOpen.apply(this, arguments);
  };

  // ═══════════════════════════════════════════════════════════════
  // 3. SKIP bouton natif YT (preroll classique uniquement)
  //    Polling léger 500ms — clique le bouton si présent.
  //    C'est tout. Aucune autre logique de skip.
  // ═══════════════════════════════════════════════════════════════
  setInterval(function () {
    safe(function () {
      var btn = document.querySelector(
        '.ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-ad-skip-button-modern'
      );
      if (btn) btn.click();
    });
  }, 500);

  // ═══════════════════════════════════════════════════════════════
  // 4. BRIDGE Flutter ↔ WebView
  // ═══════════════════════════════════════════════════════════════
  setInterval(function () {
    safe(function () {
      var titleEl  = document.querySelector('.ytmusic-player-bar .title');
      var artistEl = document.querySelector('.ytmusic-player-bar .byline');
      var thumbEl  = document.querySelector('ytmusic-player-bar img.thumbnail') ||
                     document.querySelector('.ytmusic-player-bar img');
      var video    = document.querySelector('video');

      var title  = titleEl  ? (titleEl.textContent  || '').trim() : '';
      var artist = artistEl ? (artistEl.textContent || '').trim() : '';
      var thumb  = thumbEl  ? (thumbEl.src || '') : '';
      var playing = video ? (!video.paused && !video.ended) : false;
      var dur = (video && isFinite(video.duration) && video.duration > 1)
                  ? Math.round(video.duration) : 0;
      var pos = video ? Math.round(video.currentTime || 0) : 0;

      if (title && dur > 0 &&
          (title !== _lastTitle || artist !== _lastArtist || Math.abs(dur - _lastDur) > 2)) {
        _lastTitle  = title;
        _lastArtist = artist;
        _lastDur    = dur;
        send({ type: 'nowPlaying', title: title, artist: artist,
               thumb: thumb, playing: playing, duration: dur });
      }
      if (playing && dur > 0) send({ type: 'progress', playing: true, pos: pos });
    });
  }, 1000);

  // ═══════════════════════════════════════════════════════════════
  // 5. COMMANDES Flutter → WebView
  // ═══════════════════════════════════════════════════════════════
  window.__calaCommand = function (cmd, arg) {
    if (cmd === 'pause') _userPaused = true;
    if (cmd === 'play')  _userPaused = false;
    safe(function () {
      var v = document.querySelector('video');
      switch (cmd) {
        case 'play':  if (v) v.play();  break;
        case 'pause': if (v) v.pause(); break;
        case 'seek':
          var s = parseFloat(arg);
          if (v && isFinite(s) && s >= 0) v.currentTime = s;
          break;
        case 'next': safe(function () {
          var b = document.querySelector(
            'ytmusic-player-bar [data-testid="next-button"],' +
            'ytmusic-player-bar [aria-label="Next"],' +
            'ytmusic-player-bar [aria-label="Suivant"]');
          if (b) b.click();
        }); break;
        case 'prev': safe(function () {
          var b = document.querySelector(
            'ytmusic-player-bar [data-testid="prev-button"],' +
            'ytmusic-player-bar [aria-label="Previous"],' +
            'ytmusic-player-bar [aria-label="Précédent"]');
          if (b) b.click();
        }); break;
        case 'search':
          if (arg && arg.length < 500)
            location.href = 'https://music.youtube.com/search?q=' + encodeURIComponent(arg);
          break;
        case 'home':    location.href = 'https://music.youtube.com/'; break;
        case 'library': location.href = 'https://music.youtube.com/library'; break;
      }
    });
  };

  // ═══════════════════════════════════════════════════════════════
  // 6. STORAGE ACCESS API (connexion Google)
  // ═══════════════════════════════════════════════════════════════
  safe(function () {
    ['requestStorageAccessFor', 'requestStorageAccess'].forEach(function (fn) {
      if (typeof document[fn] === 'function') {
        var orig = document[fn].bind(document);
        document[fn] = function () {
          return orig.apply(this, arguments).catch(function () { return Promise.resolve(); });
        };
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 7. PAGE VISIBILITY — empêcher YouTube de mettre en pause
  // ═══════════════════════════════════════════════════════════════
  safe(function () {
    ['hidden', 'webkitHidden'].forEach(function (p) {
      Object.defineProperty(document, p, { get: function () { return false; }, configurable: true });
    });
    ['visibilityState', 'webkitVisibilityState'].forEach(function (p) {
      Object.defineProperty(document, p, { get: function () { return 'visible'; }, configurable: true });
    });
    var STOP = { visibilitychange:1, webkitvisibilitychange:1, pagehide:1, freeze:1 };
    var _dOn = document.addEventListener.bind(document);
    var _wOn = window.addEventListener.bind(window);
    document.addEventListener = function (t, l, o) { if (!STOP[t]) _dOn(t, l, o); };
    window.addEventListener   = function (t, l, o) { if (!STOP[t]) _wOn(t, l, o); };
  });

})();
