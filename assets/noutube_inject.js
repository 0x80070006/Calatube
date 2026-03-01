(function() {
  'use strict';
  if (window._calatubeInjected) return;
  window._calatubeInjected = true;

  // ══ 0. STORAGE ACCESS API ═══════════════════════════════════════
  if (document.requestStorageAccessFor) {
    const orig = document.requestStorageAccessFor.bind(document);
    document.requestStorageAccessFor = async (o) => { try { return await orig(o); } catch(_) { return Promise.resolve(); } };
  }
  if (document.requestStorageAccess) {
    const orig = document.requestStorageAccess.bind(document);
    document.requestStorageAccess = async () => { try { return await orig(); } catch(_) { return Promise.resolve(); } };
  }

  // ══ 1. CSS AD BLOCKING ══════════════════════════════════════════
  function injectCSS() {
    if (document.getElementById('calatube-styles')) return;
    const s = document.createElement('style');
    s.id = 'calatube-styles';
    s.textContent = `
      ytd-page-top-ad-layout-renderer, ytd-in-feed-ad-layout-renderer,
      ad-slot-renderer, yt-mealbar-promo-renderer,
      ytm-promoted-sparkles-web-renderer, ytm-companion-slot,
      ytm-promoted-video-renderer, ytm-display-ad-renderer,
      ytm-banner-promo-renderer, ytm-mealbar-promo-renderer,
      .ytp-ad-module, .video-ads, a.app-install-link,
      ytm-open-app-promo-renderer, .open-app-banner, #open-app-banner
      { display: none !important; }
      tp-yt-iron-overlay-backdrop { display: none !important; }
    `;
    (document.head || document.documentElement).appendChild(s);
  }
  injectCSS();

  // ══ 2. INTERCEPT FETCH/XHR — STRIP ADS ══════════════════════════
  const AD_KEYS = ['adBreakHeartbeatParams','adPlacements','adSlots','playerAds','adRequestedDelay'];
  const RE = /\/youtubei\/v1\/(get_watch|player|search|next)/;
  function stripAds(d) {
    AD_KEYS.forEach(k => delete d[k]);
    if (d.playerConfig) delete d.playerConfig.adConfig;
    if (d.adBreaks) d.adBreaks = [];
    return d;
  }
  const origFetch = window.fetch;
  window.fetch = async function(...args) {
    const url = (args[0] instanceof Request ? args[0].url : String(args[0]));
    const res = await origFetch.apply(this, args);
    try {
      if (res.status === 200 && RE.test(new URL(url).pathname)) {
        const text = await res.text();
        return new Response(JSON.stringify(stripAds(JSON.parse(text))), { status: res.status, headers: res.headers });
      }
    } catch(_) {}
    return res;
  };
  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, url) {
    this.addEventListener('readystatechange', function() {
      if (this.readyState === 4 && String(url).includes('youtubei/v1/player')) {
        try {
          const json = JSON.stringify(stripAds(JSON.parse(this.responseText)));
          Object.defineProperty(this, 'response',     { writable: true, value: json });
          Object.defineProperty(this, 'responseText', { writable: true, value: json });
        } catch(_) {}
      }
    });
    return origOpen.apply(this, arguments);
  };

  // ══ 3. SKIP AUTO ADS ════════════════════════════════════════════
  function skipAds() {
    const skip = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern');
    if (skip) { skip.click(); return; }
    const vid = document.querySelector('video');
    if (vid && document.querySelector('.ad-showing')) {
      vid.currentTime = vid.duration;
    }
  }
  setInterval(skipAds, 300);

  // ══ 4. COOKIE CONSENT AUTO-REFUS ════════════════════════════════
  let cookieDone = false;
  function rejectCookies() {
    const btns = Array.from(document.querySelectorAll('button, [role="button"]'));
    const btn = btns.find(b => {
      const t = (b.textContent || '').trim().toLowerCase();
      return t === 'reject all' || t === 'tout refuser' || t === 'refuser tout' || t === 'refuse all';
    });
    if (btn) { btn.click(); return true; }
    return false;
  }
  const cookieObs = new MutationObserver(() => {
    if (!cookieDone && rejectCookies()) {
      cookieDone = true;
      setTimeout(() => document.querySelectorAll('tp-yt-iron-overlay-backdrop').forEach(e => e.remove()), 500);
    }
  });
  cookieObs.observe(document.documentElement, { childList: true, subtree: false });
  let cTries = 0;
  const cInt = setInterval(() => {
    if (cookieDone || cTries++ > 40) { clearInterval(cInt); return; }
    if (rejectCookies()) {
      cookieDone = true;
      setTimeout(() => document.querySelectorAll('tp-yt-iron-overlay-backdrop').forEach(e => e.remove()), 500);
    }
  }, 250);

  // ══ 5. BANNIÈRE APP ══════════════════════════════════════════════
  function removeAppBanner() {
    document.querySelectorAll('#open-app-banner, .open-app-banner, ytm-open-app-promo-renderer').forEach(b => b.remove());
    document.querySelectorAll('a[href^="intent://"], a[href^="vnd.youtube"]').forEach(a => a.removeAttribute('href'));
  }
  setInterval(removeAppBanner, 2000);

  // ══ 6. NOUTUBE CONTROLS ══════════════════════════════════════════
  window.NouTube = {
    play:  () => { const p = document.getElementById('movie_player'); if (p) p.playVideo(); else document.querySelector('video')?.play(); },
    pause: () => { const p = document.getElementById('movie_player'); if (p) p.pauseVideo(); else document.querySelector('video')?.pause(); },
    prev:  () => document.getElementById('movie_player')?.previousVideo?.(),
    next:  () => document.getElementById('movie_player')?.nextVideo?.(),
  };

  // ══ 7. BRIDGE → FLUTTER : surveillance directe de la balise video ══
  // YouTube Music SPA — on surveille la video + les métadonnées DOM
  // car onStateChange est peu fiable en WebView
  function sendToFlutter(payload) {
    try { window.CalatubeFlutter?.postMessage(JSON.stringify(payload)); } catch(_) {}
  }

  let lastVideoId = '';
  let lastPlaying = null;
  let progressTimer = null;

  function getVideoId() {
    try {
      // Extraire l'id depuis l'URL ou le player
      const match = location.href.match(/[?&]v=([^&]+)/);
      if (match) return match[1];
      const p = document.getElementById('movie_player');
      const resp = p?.getPlayerResponse?.();
      return resp?.videoDetails?.videoId || '';
    } catch(_) { return ''; }
  }

  function getMetadata() {
    try {
      const p = document.getElementById('movie_player');
      const resp = p?.getPlayerResponse?.();
      const d = resp?.videoDetails;
      if (!d) return null;
      return {
        id:       d.videoId || '',
        title:    d.title || document.title.replace(' - YouTube Music','').replace(' - YouTube',''),
        artist:   d.author || '',
        thumb:    d.thumbnail?.thumbnails?.slice(-1)[0]?.url || '',
        duration: (parseInt(d.lengthSeconds || '0') * 1000),
      };
    } catch(_) {
      // Fallback DOM pour YouTube Music
      try {
        const title  = document.querySelector('.title.ytmusic-player-bar, .content-info-wrapper .title')?.textContent?.trim() || '';
        const artist = document.querySelector('.byline.ytmusic-player-bar, .content-info-wrapper .subtitle')?.textContent?.trim() || '';
        const thumb  = document.querySelector('.thumbnail.ytmusic-player-bar img, ytmusic-player-bar img')?.src || '';
        if (title) return { id: getVideoId(), title, artist, thumb, duration: 0 };
      } catch(_) {}
      return null;
    }
  }

  function startProgressTimer(video) {
    if (progressTimer) clearInterval(progressTimer);
    progressTimer = setInterval(() => {
      if (!video || video.paused) return;
      sendToFlutter({
        type: 'progress',
        playing: true,
        pos: Math.round(video.currentTime * 1000),
      });
    }, 3000);
  }

  function attachVideoListeners(video) {
    video.addEventListener('play', () => {
      const meta = getMetadata();
      const id   = getVideoId();
      lastPlaying = true;
      if (meta) {
        lastVideoId = id;
        sendToFlutter({ type: 'nowPlaying', ...meta, playing: true });
      } else {
        sendToFlutter({ type: 'playState', playing: true, pos: Math.round(video.currentTime * 1000) });
      }
      startProgressTimer(video);
    });

    video.addEventListener('pause', () => {
      lastPlaying = false;
      if (progressTimer) clearInterval(progressTimer);
      sendToFlutter({ type: 'playState', playing: false, pos: Math.round(video.currentTime * 1000) });
    });

    video.addEventListener('emptied', () => {
      lastVideoId = '';
      if (progressTimer) clearInterval(progressTimer);
    });

    // Nouveau titre détecté (changement src = nouveau morceau)
    const obs = new MutationObserver(() => {
      const id = getVideoId();
      if (id && id !== lastVideoId) {
        lastVideoId = id;
        setTimeout(() => {
          const meta = getMetadata();
          if (meta) sendToFlutter({ type: 'nowPlaying', ...meta, playing: !video.paused });
        }, 800);
      }
    });
    obs.observe(video, { attributeFilter: ['src'] });
    startProgressTimer(video);
  }

  // Attendre que la balise video apparaisse (SPA)
  let videoAttached = false;
  function findAndAttachVideo() {
    const video = document.querySelector('video');
    if (video && !videoAttached) {
      videoAttached = true;
      attachVideoListeners(video);
      // Si déjà en train de jouer au moment de l'injection
      if (!video.paused) {
        const meta = getMetadata();
        if (meta) sendToFlutter({ type: 'nowPlaying', ...meta, playing: true });
        startProgressTimer(video);
      }
      return true;
    }
    return false;
  }

  // Observer les nouvelles balises video dans le DOM
  const domObs = new MutationObserver(() => {
    if (!videoAttached) findAndAttachVideo();
  });
  domObs.observe(document.body || document.documentElement, { childList: true, subtree: true });

  // Retry poll
  let vTries = 0;
  const vInt = setInterval(() => {
    if (videoAttached || vTries++ > 60) { clearInterval(vInt); return; }
    findAndAttachVideo();
  }, 500);

  console.log('✅ Calatube NouTube script injected');
})();
