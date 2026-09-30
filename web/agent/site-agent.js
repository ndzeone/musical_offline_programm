/* Помощник на странице площадки (Spotify, SoundCloud, Яндекс Музыка, VK) — общий для Mac, Windows и Android.
   Сообщает программе, что играет, даёт кнопки управления и умеет включить нужный трек из плейлиста.
   Mac: window.webkit.messageHandlers.mc; Windows и Android: window.MuzykaSite.post(строка). */
(function () {
  if (window.__mc) return;
  var mc = window.__mc = { media: new Set(), handlers: {}, pos: null, timer: null, last: 0, volume: null, ap: null };
  var host = location.hostname;
  var P = /(^|\.)spotify\.com$/.test(host) ? 'spotify' : /(^|\.)soundcloud\.com$/.test(host) ? 'soundcloud'
        : /(^|\.)yandex\./.test(host) ? 'yandex' : /(^|\.)vk\.(ru|com)$/.test(host) ? 'vk' : 'other';
  mc.platform = P;
  function now() { return performance.now(); }
  function fold() {
    if (mc.pos && !mc.pos.frozen) { mc.pos.p += (now() - mc.pos.t) / 1000 * mc.pos.r; mc.pos.t = now(); }
  }
  function send(o) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mc) { window.webkit.messageHandlers.mc.postMessage(o); return; }
      if (window.MuzykaSite && window.MuzykaSite.post) window.MuzykaSite.post(typeof o === 'string' ? o : JSON.stringify(o));
    } catch (e) {}
  }
  function post() {
    if (mc.timer) return;
    var wait = Math.max(0, 120 - (now() - mc.last));
    mc.timer = setTimeout(function () { mc.timer = null; mc.last = now(); send(mc.state()); }, wait);
  }
  mc.post = post;
  function track(m) {
    if (!m || mc.media.has(m)) return;
    mc.media.add(m);
    m.addEventListener('pause', function () { fold(); if (mc.pos) mc.pos.frozen = true; post(); });
    m.addEventListener('playing', function () { if (mc.pos && mc.pos.frozen) { mc.pos.t = now(); mc.pos.frozen = false; } post(); });
    ['play', 'ended', 'loadedmetadata', 'durationchange', 'seeked', 'ratechange', 'emptied'].forEach(function (ev) {
      m.addEventListener(ev, post);
    });
    try { if (mc.volume !== null) m.volume = mc.volume; } catch (e) {}
  }
  var origPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function () { try { track(this); } catch (e) {} return origPlay.apply(this, arguments); };
  var ms = navigator.mediaSession;
  if (ms) {
    if (ms.setActionHandler) {
      var oh = ms.setActionHandler.bind(ms);
      ms.setActionHandler = function (a, h) { mc.handlers[a] = h; try { return oh(a, h); } catch (e) {} };
    }
    if (ms.setPositionState) {
      var op = ms.setPositionState.bind(ms);
      ms.setPositionState = function (s) {
        var m = mc.active();
        mc.pos = (s && s.duration) ? { d: s.duration, p: s.position || 0, r: s.playbackRate || 1, t: now(), frozen: m ? m.paused : false } : null;
        post();
        try { return op(s); } catch (e) {}
      };
    }
    try {
      var proto = Object.getPrototypeOf(ms);
      ['metadata', 'playbackState'].forEach(function (k) {
        var d = Object.getOwnPropertyDescriptor(proto, k);
        if (d && d.get && d.set) {
          Object.defineProperty(ms, k, {
            configurable: true, enumerable: true,
            get: function () { return d.get.call(ms); },
            set: function (v) { d.set.call(ms, v); post(); }
          });
        }
      });
    } catch (e) {}
  }

  // ---------- помощники ----------
  function q(s, r) { try { return (r || document).querySelector(s); } catch (e) { return null; } }
  function qa(s, r) { try { return Array.prototype.slice.call((r || document).querySelectorAll(s)); } catch (e) { return []; } }
  function txt(el) { return el ? String(el.textContent || '').replace(/\s+/g, ' ').trim() : ''; }
  function norm(s) {
    return String(s || '').toLowerCase().replace(/ё/g, 'е')
      .replace(/\s[-–—]\s[^-–—]*(remaster|version|edit|live|mono|stereo)[^-–—]*$/i, ' ')
      .replace(/\([^)]*\)|\[[^\]]*\]/g, ' ')
      .replace(/\s(feat\.?|ft\.)\s.*$/i, ' ')
      .replace(/[^\p{L}\p{N}]+/gu, ' ').replace(/\s+/g, ' ').trim();
  }
  function words(s) { return norm(s).split(' ').filter(Boolean); }
  function artistOk(text, artist) {
    if (!artist) return true;
    var t = ' ' + norm(text) + ' ';
    var parts = String(artist).split(/,|&|;|\/|\sx\s|\sи\s|\sfeat\.?\s|\sft\.\s/i).map(norm).filter(Boolean);
    if (!parts.length) return true;
    return parts.some(function (p) { return t.indexOf(' ' + p + ' ') >= 0; });
  }
  function parseTime(s) {
    var m = String(s || '').match(/(\d+):(\d{2})(?::(\d{2}))?/);
    if (!m) return 0;
    return m[3] ? (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]) : (+m[1]) * 60 + (+m[2]);
  }
  function abs(h) { try { return h ? new URL(h, location.href).href : null; } catch (e) { return null; } }
  function bgUrl(el) {
    if (!el) return null;
    var b = (el.style && el.style.backgroundImage) || '';
    if (!b) { try { b = getComputedStyle(el).backgroundImage || ''; } catch (e) {} }
    var m = /url\(["']?(.*?)["']?\)/.exec(b);
    return m ? m[1] : null;
  }

  // Что играет — по полоске плеера на самой странице (если сайт не сообщил это системе)
  mc.domNow = function () {
    var r = { title: '', artist: '', art: null, link: null, dur: 0 };
    try {
      if (P === 'soundcloud') {
        var a = q('.playbackSoundBadge__titleLink');
        if (a) { r.title = a.getAttribute('title') || txt(q('span[aria-hidden="true"]', a)) || txt(a); r.link = abs(a.getAttribute('href')); }
        var u = q('.playbackSoundBadge__lightLink');
        if (u) r.artist = u.getAttribute('title') || txt(u);
        var bu = bgUrl(q('.playbackSoundBadge .sc-artwork span') || q('.playbackSoundBadge span.image__full'));
        if (bu) r.art = bu.replace(/-t\d+x\d+\./, '-t500x500.');
        var d = q('.playbackTimeline__duration span[aria-hidden="true"]') || q('.playbackTimeline__duration');
        if (d) r.dur = parseTime(txt(d));
      } else if (P === 'spotify') {
        var w = q('[data-testid="now-playing-widget"]');
        if (w) {
          var t = q('[data-testid="context-item-info-title"] a', w) || q('a[data-testid="context-item-link"]', w);
          if (t) {
            r.title = txt(t);
            var h = t.getAttribute('href') || '', mm = /spotify:track:([A-Za-z0-9]+)/.exec(decodeURIComponent(h));
            r.link = mm ? 'https://open.spotify.com/track/' + mm[1] : (/\/track\//.test(h) ? abs(h) : null);
          }
          var ar = qa('[data-testid="context-item-info-artist"]', w).map(txt).filter(Boolean);
          if (ar.length) r.artist = ar.join(', ');
          var im = q('img', w);
          if (im && im.src) r.art = im.src;
        }
        var dd = q('[data-testid="playback-duration"]');
        if (dd) r.dur = parseTime(txt(dd));
      } else if (P === 'yandex') {
        var bar = q('[class*="PlayerBarDesktop"]') || q('section[aria-label="Плеер"]') || q('[class*="PlayerBar_root"]');
        if (bar) {
          var tl = q('a[href*="/track/"]', bar);
          var names = qa('[class*="trackNameText"], [class*="Meta_title"]', bar).map(txt).filter(Boolean);
          if (tl) { r.title = tl.getAttribute('title') || txt(tl); r.link = abs(tl.getAttribute('href')); }
          else if (names.length) r.title = names[0];
          var al = qa('a[href*="/artist/"]', bar).map(txt).filter(Boolean);
          if (al.length) r.artist = al.join(', '); else if (names.length > 1) r.artist = names[1];
          var ii = q('img', bar);
          if (ii && ii.src && ii.src.indexOf('data:') !== 0) r.art = ii.src;
          var tc = q('[class*="timecode"], [class*="Timecode"]', bar);
          if (tc) { var pp = txt(tc).split('/'); if (pp.length > 1) r.dur = parseTime(pp[1]); }
        }
      } else if (P === 'vk') {
        var vt = q('.top_audio_player_title') || q('[class*="AudioPlayer__title"]');
        if (vt) {
          var s = txt(vt), sp = s.split(/\s[–—-]\s/);
          if (sp.length > 1) { r.artist = sp[0]; r.title = sp.slice(1).join(' - '); } else r.title = s;
        }
      }
    } catch (e) {}
    return r;
  };

  mc.active = function () {
    document.querySelectorAll('audio,video').forEach(track);
    var best = null;
    function score(x) { return (x.paused ? 0 : 4) + (x.duration > 0 ? 2 : 0) + (x.isConnected ? 1 : 0); }
    mc.media.forEach(function (m) { if (!best || score(m) > score(best)) best = m; });
    return best;
  };

  mc.state = function () {
    var m = mc.active();
    var md = ms && ms.metadata;
    var playing = m ? !m.paused : !!(ms && ms.playbackState === 'playing');
    var pos = 0, dur = 0;
    if (mc.pos) {
      pos = mc.pos.p + ((playing && !mc.pos.frozen) ? (now() - mc.pos.t) / 1000 * mc.pos.r : 0);
      dur = mc.pos.d;
      pos = Math.min(pos, dur);
    } else if (m) {
      pos = m.currentTime || 0;
      dur = isFinite(m.duration) ? m.duration : 0;
    }
    var art = null, bw = -1;
    if (md && md.artwork) {
      for (var i = 0; i < md.artwork.length; i++) {
        var a = md.artwork[i];
        var w = parseInt(String(a.sizes || '0').split('x')[0], 10) || 0;
        if (w > bw) { bw = w; art = a.src; }
      }
    }
    var title = md ? (md.title || '') : '', artist = md ? (md.artist || '') : '', album = md ? (md.album || '') : '';
    if (!title || !art || !dur || P === 'soundcloud') {
      var dn = mc.domNow();
      if (!title && dn.title) { title = dn.title; artist = artist || dn.artist; }
      if (!art && dn.art) art = dn.art;
      // У SoundCloud длина из полоски плеера точнее, чем у потока
      if (dn.dur && (!dur || (P === 'soundcloud' && !mc.pos))) dur = dn.dur;
    }
    return JSON.stringify({
      title: title, artist: artist, album: album, art: art, pos: pos, dur: dur,
      paused: !playing, ended: m ? !!m.ended : false,
      rate: mc.pos ? mc.pos.r : (m ? m.playbackRate : 1)
    });
  };

  var buttons = {
    nexttrack: ['[data-testid="control-button-skip-forward"]', '.skipControl__next', '.top_audio_player_next',
                '.audio_page_player_next', '[aria-label="Следующая песня"]', '[aria-label*="Следующ"]', '[aria-label*="Next"]'],
    previoustrack: ['[data-testid="control-button-skip-back"]', '.skipControl__previous', '.top_audio_player_prev',
                    '.audio_page_player_prev', '[aria-label="Предыдущая песня"]', '[aria-label*="Предыдущ"]', '[aria-label*="Previous"]'],
    play: ['[data-testid="control-button-playpause"]', '.playControl', '.top_audio_player_play',
           '[aria-label="Воспроизведение"]', '[aria-label="Воспроизвести"]', '[aria-label="Play"]'],
    pause: ['[data-testid="control-button-playpause"]', '.playControl', '.top_audio_player_play',
            '[aria-label="Пауза"]', '[aria-label="Pause"]']
  };
  mc.cmd = function (a, arg) {
    var m = mc.active();
    if (a === 'play' && m && !m.paused) return 'already';
    if (a === 'pause' && m && m.paused) return 'already';
    var h = mc.handlers[a];
    if (typeof h === 'function') {
      try { var d = { action: a }; if (a === 'seekto') { d.seekTime = arg; d.fastSeek = false; } h(d); return 'handler'; } catch (e) {}
    }
    var sel = buttons[a] || [];
    for (var i = 0; i < sel.length; i++) { var b = q(sel[i]); if (b) { b.click(); return 'click'; } }
    if (m) {
      if (a === 'play') { m.play(); return 'media'; }
      if (a === 'pause') { m.pause(); return 'media'; }
      if (a === 'seekto') { m.currentTime = arg; return 'media'; }
    }
    return 'none';
  };
  mc.setVolume = function (v) { mc.volume = v; mc.media.forEach(function (m) { try { m.volume = v; } catch (e) {} }); };

  mc.link = function () {
    var dn = mc.domNow();
    if (dn.link) return dn.link;
    var md = ms && ms.metadata;
    var want = norm(md && md.title ? md.title : dn.title);
    if (want) {
      var links = qa('a[href*="/track/"], a[href*="/tracks/"]');
      for (var i = 0; i < links.length; i++) {
        if (norm(links[i].getAttribute('title') || txt(links[i])) === want) return abs(links[i].getAttribute('href'));
      }
    }
    return null;
  };

  // ---------- поиск точной кнопки «играть» для нужного трека ----------
  function playLike(b) {
    var l = ((b.getAttribute('aria-label') || '') + ' ' + (b.getAttribute('title') || '')).toLowerCase();
    if (/pause|пауз|нрав|like|добав|add|меню|menu|трейлер|trailer|more|ещё|еще|скач|share|подел|репост|repost|очеред|queue/.test(l)) return false;
    var c = String(typeof b.className === 'string' ? b.className : '');
    return /play|включ|воспр|слуш|игра/.test(l) || /sc-button-play|audio_row__play_btn|play_btn/.test(c);
  }
  function playButtonsIn(el) {
    return qa('button, [role="button"], a.sc-button-play, .audio_row__play_btn', el).filter(playLike);
  }
  function area(el) { var r = el.getBoundingClientRect(); return r.width * r.height; }
  var noise = ['by', 'playlist', 'track', 'трек', 'песня', 'исполнителя', 'исполнитель', 'от', 'album', 'альбом',
               'single', 'сингл', 'explicit', 'e', 'play', 'включить', 'слушать'];
  // Подпись карточки — это «исполнитель + название» и ничего лишнего
  function cardMatches(label, want, artist) {
    var nl = ' ' + norm(label) + ' ', w = ' ' + want + ' ';
    var i = nl.indexOf(w);
    if (i < 0) return false;
    var rest = (nl.slice(0, i) + ' ' + nl.slice(i + w.length)).split(' ').filter(Boolean);
    var ok = words(artist).concat(noise);
    return rest.every(function (t) { return ok.indexOf(t) >= 0; }) && artistOk(label, artist);
  }

  mc.findPlay = function (title, artist) {
    var want = norm(title), path = location.pathname;
    if (!want) return null;
    // 1) страница самого трека: большая кнопка
    if (P === 'spotify' && /^\/track\//.test(path)) {
      var h1 = q('[data-testid="entityTitle"] h1') || q('section[data-testid="track-page"] h1');
      if (h1 && norm(txt(h1)) === want) {
        var b1 = q('section[data-testid="track-page"] [data-testid="action-bar-row"] button[data-testid="play-button"]')
              || q('section[data-testid="track-page"] button[data-testid="play-button"]');
        if (b1) return b1;
      }
    }
    if (P === 'soundcloud') {
      var h2 = q('.fullListenHero h1.soundTitle__title') || q('.fullHero h1');
      if (h2 && norm(txt(h2)) === want) {
        var b2 = q('.fullListenHero .soundTitle__playButtonHero .sc-button-play') || q('.fullHero .sc-button-play');
        if (b2) return b2;
      }
    }
    // 2) кнопка, в подписи которой назван трек: «Включить трек «X» исполнителя Y» / «Play X by Y»
    var labelled = qa('button[aria-label], [role="button"][aria-label]').filter(function (b) {
      if (!playLike(b)) return false;
      var l = b.getAttribute('aria-label') || '';
      var m = /[«"“]([^»"”]+)[»"”]/.exec(l) || /^play\s+(.+?)\s+by\s+/i.exec(l);
      return m && norm(m[1]) === want && artistOk(l, artist);
    });
    if (labelled.length) return labelled[0];
    // 3) карточка трека с подписью «исполнитель название» (Яндекс) или «… by исполнитель» (SoundCloud)
    var cards = qa('[aria-label]').filter(function (el) {
      if (el.tagName === 'BUTTON' || el.tagName === 'A') return false;
      var l = el.getAttribute('aria-label') || '';
      return l.length < 240 && cardMatches(l, want, artist);
    }).sort(function (a, b) { return area(a) - area(b); });
    for (var i = 0; i < cards.length; i++) {
      var pb = playButtonsIn(cards[i]);
      if (pb.length) return pb[0];
    }
    // 4) название трека → ближайший блок, где есть исполнитель и ровно одна кнопка «играть»
    var titles = qa('a[href*="/track/"], a.soundTitle__title, .soundTitle__title, .audio_row__title_inner, [class*="title"], [class*="Title"]')
      .filter(function (el) { return norm(el.getAttribute('title') || txt(el)) === want; }).slice(0, 12);
    for (var j = 0; j < titles.length; j++) {
      var el = titles[j];
      for (var k = 0; k < 8 && el; k++) {
        el = el.parentElement;
        if (!el || el === document.body) break;
        var pbs = playButtonsIn(el);
        if (pbs.length === 1 && artistOk(txt(el), artist)) return pbs[0];
        if (pbs.length > 1) break;
        if (P === 'vk' && /audio_row/.test(String(el.className)) && artistOk(txt(el), artist)) return el;
      }
    }
    return null;
  };

  // Нажать найденную кнопку. Если её ничего не закрывает — просим программу нажать по-настоящему
  // (сайт видит это как нажатие пользователя), иначе нажимаем из скрипта.
  function press(el) {
    try { el.scrollIntoView({ block: 'center', inline: 'center' }); } catch (e) {}
    mc.target = el;
    var r = el.getBoundingClientRect();
    var x = r.left + r.width / 2, y = r.top + r.height / 2;
    var top = document.elementFromPoint(x, y);
    if (r.width > 2 && r.height > 2 && top && (top === el || el.contains(top) || top.contains(el))) {
      send({ ev: 'autoplay', r: 'press', x: x, y: y, vw: window.innerWidth, vh: window.innerHeight });
    } else {
      mc.pressTarget();
    }
  }
  mc.pressTarget = function () { var el = mc.target; if (el) { try { el.click(); } catch (e) {} } };
  function playingTitle() {
    var md = ms && ms.metadata;
    return md && md.title ? md.title : mc.domNow().title;
  }
  // Кнопка уже показывает «пауза»/«загрузка» — значит, нажатие сработало, ждём звук
  function pressedAlready(el) {
    if (!el || !el.isConnected) return false;
    var l = ((el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('title') || '') + ' ' + (typeof el.className === 'string' ? el.className : '')).toLowerCase();
    return /pause|пауз|buffering|loading|загруз/.test(l);
  }

  // Помощник: ждёт, пока на странице появится нужный трек, нажимает ровно его и следит, что он заиграл
  mc.autoplayStop = function () { if (mc.ap) { clearInterval(mc.ap.timer); mc.ap = null; } };
  mc.autoplayStart = function (title, artist, limit) {
    mc.autoplayStop();
    var ap = mc.ap = { t0: Date.now(), clicks: 0, last: 0, limit: limit || 15000, want: norm(title), el: null };
    function tick() {
      if (mc.ap !== ap) return;
      var m = mc.active(), playing = !!(m && !m.paused), cur = playingTitle();
      if (playing && cur && norm(cur) === ap.want) { mc.autoplayStop(); post(); return; }
      if (Date.now() - ap.t0 > ap.limit) { mc.autoplayStop(); send({ ev: 'autoplay', r: 'timeout', clicks: ap.clicks }); return; }
      if (ap.clicks > 0) {
        if (Date.now() - ap.last < 5000) return;          // после нажатия даём сайту время
        if (playing && !cur) return;                      // что-то заиграло, но название ещё не пришло
        if (pressedAlready(ap.el)) return;                // кнопка уже «пауза» — не жмём повторно
      }
      if (ap.clicks >= 3) return;
      var b = mc.findPlay(title, artist);
      if (b) { ap.el = b; press(b); ap.clicks++; ap.last = Date.now(); send({ ev: 'autoplay', r: 'click', clicks: ap.clicks }); }
    }
    ap.timer = setInterval(tick, 350);
    tick();
    return 'started';
  };

  mc.whoami = function () {
    var list = ['[data-testid="user-widget-link"]', '.header__userNavUsernameButton .truncate', '.header__userNavUsername',
                '.top_profile_name', '[data-test-id="USER_NAME"]', '.user-account__name'];
    for (var i = 0; i < list.length; i++) {
      var el = q(list[i]);
      if (!el) continue;
      var t = (el.getAttribute('aria-label') || el.textContent || '').trim();
      if (t) return t;
    }
    return '';
  };
})();
