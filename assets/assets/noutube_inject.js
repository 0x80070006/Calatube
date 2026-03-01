(function() {
  'use strict';
  if (window._calatubeInjected) return;
  window._calatubeInjected = true;

  // ══════════════════════════════════════════════════════════════
  // 0. PATCHER L'API STORAGE ACCESS — évite "Permission denied"
  //    music.youtube.com appelle requestStorageAccessFor() pour
  //    les cookies cross-origin (googleapis.com etc.)
  //    On l'approuve automatiquement pour ne pas bloquer les vidéos
  // ══════════════════════════════════════════════════════════════
  if (document.requestStorageAccessFor) {
    const origRSAF = document.requestStorageAccessFor.bind(document);
    document.requestStorageAccessFor = async function(origin) {
      try { return await origRSAF(origin); } catch(_) { return Promise.resolve(); }
    };
  }
  if (document.requestStorageAccess) {
    const origRSA = document.requestStorageAccess.bind(document);
    document.requestStorageAccess = async function() {
      try { return await origRSA(); } catch(_) { return Promise.resolve(); }
    };
  }

  // ══════════════════════════════════════════════════════════════
  // 1. CSS — BLOQUER PUBS SANS CASSER LA MISE EN PAGE
  // ══════════════════════════════════════════════════════════════
  function injectCSS() {
    if (document.getElementById('calatube-styles')) return;
    const style = document.createElement('style');
    style.id = 'calatube-styles';
    style.textContent = `
      /* Pubs */
      ytd-page-top-ad-layout-renderer,
      ytd-in-feed-ad-layout-renderer,
      ad-slot-renderer,
      yt-mealbar-promo-renderer,
      ytm-promoted-sparkles-web-renderer,
      ytm-companion-slot,
      ytm-promoted-video-renderer,
      ytm-display-ad-renderer,
      ytm-banner-promo-renderer,
      ytm-mealbar-promo-renderer,
      .ytp-ad-module,
      .video-ads,
      a.app-install-link,
      /* Bannière ouvrir dans l'app */
      ytm-open-app-promo-renderer,
      .open-app-banner,
      #open-app-banner { display: none !important; }

      /* Consent — UNIQUEMENT l'overlay de fond, pas le contenu */
      tp-yt-iron-overlay-backdrop { display: none !important; }
    `;
    (document.head || document.documentElement).appendChild(style);
  }
  injectCSS();

  // ══════════════════════════════════════════════════════════════
  // 2. INTERCEPTER LES REQUÊTES — SUPPRIMER DONNÉES PUBS
  // ══════════════════════════════════════════════════════════════
  const AD_KEYS = ['adBreakHeartbeatParams','adPlacements','adSlots','playerAds','adRequestedDelay'];
  const RE = /\/youtubei\/v1\/(get_watch|player|search|next)/;

  function stripAds(data) {
    AD_KEYS.forEach(k => delete data[k]);
    if (data.playerConfig) delete data.playerConfig.adConfig;
    if (data.adBreaks) data.adBreaks = [];
    return data;
  }

  const origFetch = window.fetch;
  window.fetch = async function(...args) {
    const url = (args[0] instanceof Request ? args[0].url : String(args[0]));
    const res = await origFetch.apply(this, args);
    try {
      if (res.status === 200 && RE.test(new URL(url).pathname)) {
        const text = await res.text();
        const data = JSON.parse(text);
        return new Response(JSON.stringify(stripAds(data)), {
          status: res.status, headers: res.headers
        });
      }
    } catch(_) {}
    return res;
  };

  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, url) {
    this.addEventListener('readystatechange', function() {
      if (this.readyState === 4 && String(url).includes('youtubei/v1/player')) {
        try {
          const data = JSON.parse(this.responseText);
          const json = JSON.stringify(stripAds(data));
          Object.defineProperty(this, 'response',     { writable: true, value: json });
          Object.defineProperty(this, 'responseText', { writable: true, value: json });
        } catch(_) {}
      }
    });
    return origOpen.apply(this, arguments);
  };

  // ══════════════════════════════════════════════════════════════
  // 3. SKIP AUTO DES PUBS VIDÉO
  // ══════════════════════════════════════════════════════════════
  function skipAds() {
    // Bouton skip visible
    const skip = document.querySelector(
      '.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern'
    );
    if (skip) { skip.click(); return; }

    // Pub en cours → avancer à la fin
    if (document.querySelector('.ad-showing')) {
      const v = document.querySelector('video');
      if (v && v.duration && isFinite(v.duration)) {
        v.currentTime = v.duration;
      }
    }
  }
  setInterval(skipAds, 300);

  // ══════════════════════════════════════════════════════════════
  // 4. REFUSER COOKIES — PROPRE, SANS CASSER LE BODY
  // ══════════════════════════════════════════════════════════════
  function rejectCookies() {
    // Chercher le bouton "Refuser" par aria-label
    const ariaSelectors = [
      '[aria-label="Reject all"]',
      '[aria-label="Refuser tout"]',
      '[aria-label="Tout refuser"]',
    ];
    for (const sel of ariaSelectors) {
      const btn = document.querySelector(sel);
      if (btn) { btn.click(); return true; }
    }

    // Chercher par texte visible dans les boutons de la dialog cookie
    const dialog = document.querySelector(
      'ytd-consent-bump-v2-lightbox, ytm-consent-bump-v2-renderer, ' +
      '[id*="consent"], tp-yt-paper-dialog'
    );
    if (dialog) {
      const btns = dialog.querySelectorAll('button, [role="button"]');
      for (const btn of btns) {
        const t = btn.textContent?.trim().toLowerCase() || '';
        if (t.includes('reject') || t.includes('refuser') || t.includes('refuse')) {
          btn.click(); return true;
        }
      }
    }
    return false;
  }

  // Observer uniquement les dialogs cookie, pas tout le DOM
  let cookieDone = false;
  const cookieObs = new MutationObserver(() => {
    if (cookieDone) return;
    if (rejectCookies()) {
      cookieDone = true;
      // Supprimer l'overlay de fond après le clic
      setTimeout(() => {
        document.querySelectorAll('tp-yt-iron-overlay-backdrop').forEach(e => e.remove());
      }, 500);
    }
  });
  cookieObs.observe(document.documentElement, { childList: true, subtree: false });

  // Retry pendant 10s
  let cTries = 0;
  const cInt = setInterval(() => {
    if (cookieDone || cTries++ > 40) { clearInterval(cInt); return; }
    if (rejectCookies()) {
      cookieDone = true;
      setTimeout(() => {
        document.querySelectorAll('tp-yt-iron-overlay-backdrop').forEach(e => e.remove());
      }, 500);
    }
  }, 250);

  // ══════════════════════════════════════════════════════════════
  // 5. SUPPRIMER BANNIÈRE "OUVRIR L'APP"
  // ══════════════════════════════════════════════════════════════
  function removeAppBanner() {
    document.querySelectorAll(
      '#open-app-banner, .open-app-banner, ytm-open-app-promo-renderer'
    ).forEach(b => b.remove());
    // Bloquer liens intent://
    document.querySelectorAll('a[href^="intent://"], a[href^="vnd.youtube"]').forEach(a => {
      a.removeAttribute('href');
    });
  }
  setInterval(removeAppBanner, 2000);

  // ══════════════════════════════════════════════════════════════
  // 6. WINDOW.NOUTUBE — contrôles player pour les notifications
  // ══════════════════════════════════════════════════════════════
  window.NouTube = {
    play:  () => {
      const p = document.getElementById('movie_player');
      if (p) p.playVideo();
      else { const v = document.querySelector('video'); if (v) v.play(); }
    },
    pause: () => {
      const p = document.getElementById('movie_player');
      if (p) p.pauseVideo();
      else { const v = document.querySelector('video'); if (v) v.pause(); }
    },
    prev:  () => document.getElementById('movie_player')?.previousVideo?.(),
    next:  () => document.getElementById('movie_player')?.nextVideo?.(),
    seekBy:(d) => document.getElementById('movie_player')?.seekBy?.(d),
  };

  // ══════════════════════════════════════════════════════════════
  // 7. BRIDGE → FLUTTER : infos titre en cours
  // ══════════════════════════════════════════════════════════════
  let lastId = '';

  function sendToFlutter(payload) {
    try {
      if (window.CalatubeFlutter) {
        window.CalatubeFlutter.postMessage(JSON.stringify(payload));
      }
    } catch(_) {}
  }

  function watchPlayer() {
    const player = document.getElementById('movie_player');
    if (!player) return false;

    player.addEventListener('onStateChange', function(state) {
      try {
        const res = player.getPlayerResponse?.();
        if (!res?.videoDetails) return;
        const d = res.videoDetails;
        const isPlaying = (state === 1);

        if (d.videoId !== lastId || state === 1) {
          lastId = d.videoId;
          const thumb = d.thumbnail?.thumbnails?.slice(-1)[0]?.url || '';
          sendToFlutter({
            type: 'nowPlaying',
            title: d.title || '',
            artist: d.author || '',
            thumb,
            playing: isPlaying,
            duration: (parseInt(d.lengthSeconds || '0') * 1000),
          });
        } else if (state === 2) {
          sendToFlutter({ type: 'playState', playing: false, pos: 0 });
        }
      } catch(_) {}
    });

    // Progrès toutes les 5s
    const video = document.querySelector('video');
    if (video) {
      let lastReport = 0;
      video.addEventListener('timeupdate', () => {
        const now = Date.now();
        if (now - lastReport < 5000) return;
        lastReport = now;
        sendToFlutter({
          type: 'progress',
          playing: !video.paused,
          pos: Math.round(video.currentTime * 1000),
        });
      });
    }
    return true;
  }

  // Poll jusqu'au player (YouTube Music charge en SPA)
  let pTries = 0;
  const pInt = setInterval(() => {
    if (pTries++ > 60 || watchPlayer()) clearInterval(pInt);
  }, 500);

  console.log('✅ Calatube NouTube script injected');
})();
