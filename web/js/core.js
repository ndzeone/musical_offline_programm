/* Общее: значки, темы, настройки, библиотека (тот же формат, что у версии для Mac) */
(function () {
  'use strict';

  // ---------- мелочи ----------
  var U = {
    esc: function (s) {
      return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
      });
    },
    time: function (s) {
      if (!isFinite(s) || s <= 0) return '0:00';
      s = Math.floor(s);
      return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2);
    },
    long: function (s) {
      var m = Math.round((s || 0) / 60);
      return m >= 60 ? Math.floor(m / 60) + ' ч ' + (m % 60) + ' мин' : m + ' мин';
    },
    uuid: function () {
      if (window.crypto && crypto.randomUUID) return crypto.randomUUID().toUpperCase();
      return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
        var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16);
      }).toUpperCase();
    },
    // Дата как у версии для Mac: без миллисекунд
    iso: function (d) { return (d || new Date()).toISOString().replace(/\.\d{3}Z$/, 'Z'); },
    hash: function (s) {
      var h = 2166136261 >>> 0;
      for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
      return h;
    },
    // Отложенный вызов; .flush() — выполнить немедленно, если что-то ждёт
    debounce: function (f, ms) {
      var t = null;
      var d = function () { clearTimeout(t); t = setTimeout(function () { t = null; f(); }, ms); };
      d.flush = function () { if (t) { clearTimeout(t); t = null; f(); } };
      return d;
    },
    // Сравнение названий (как в версии для Mac)
    norm: function (s) {
      return String(s || '').toLowerCase().replace(/ё/g, 'е')
        .replace(/\s[-–—]\s[^-–—]*(remaster|version|edit|live|mono|stereo)[^-–—]*$/i, ' ')
        .replace(/\([^)]*\)|\[[^\]]*\]/g, ' ')
        .replace(/\s(feat\.?|ft\.)\s.*$/i, ' ')
        .replace(/[^\p{L}\p{N}]+/gu, ' ').replace(/\s+/g, ' ').trim();
    },
    bareTitle: function (s) {
      return String(s || '')
        .replace(/\s*[\(\[][^\)\]]*(feat|ft\.|prod|remaster|explicit|version|edit|mix|live|bonus)[^\)\]]*[\)\]]/gi, '')
        .replace(/\s+-\s+.*(remaster|version|edit|live).*$/i, '')
        .replace(/\s+(feat\.?|ft\.)\s.*$/i, '').trim();
    },
    mainArtist: function (s) {
      var first = String(s || '').split(/[,&;\/]/)[0] || '';
      return first.replace(/\s+(feat\.?|ft\.|x|и)\s.*$/i, '').trim();
    },
    similarity: function (a, b) {
      var x = U.norm(a), y = U.norm(b);
      if (!x || !y) return 0;
      if (x === y) return 1;
      if (x.indexOf(y) >= 0 || y.indexOf(x) >= 0) return 0.85;
      var sx = x.split(' '), sy = y.split(' '), inter = 0, uni = {};
      sx.forEach(function (w) { uni[w] = 1; });
      sy.forEach(function (w) { if (uni[w] === 1) inter++; uni[w] = 2; });
      var n = Object.keys(uni).length;
      return n ? inter / n : 0;
    },
    sameSong: function (t1, a1, t2, a2) {
      var x = U.norm(U.bareTitle(t1)), y = U.norm(U.bareTitle(t2));
      if (!x || x !== y) return false;
      if (!a1 || !a2) return true;
      return U.similarity(U.mainArtist(a1), U.mainArtist(a2)) > 0.3 || U.similarity(a1, a2) > 0.3;
    },
    webKey: function (artist, title) { return 'web:' + (artist + '|' + title).toLowerCase(); }
  };

  // ---------- значки (свои, простые) ----------
  var P = {
    play: ['f', 'M8 5.5v13a1 1 0 0 0 1.5.86l10.6-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z'],
    pause: ['f', 'M7 5h3.2v14H7zM13.8 5H17v14h-3.2z'],
    next: ['f', 'M5.5 6.2v11.6a.8.8 0 0 0 1.2.7l8.3-5.8a.85.85 0 0 0 0-1.4L6.7 5.5a.8.8 0 0 0-1.2.7zM16.2 5.5h2.3v13h-2.3z'],
    prev: ['f', 'M18.5 6.2v11.6a.8.8 0 0 1-1.2.7L9 12.7a.85.85 0 0 1 0-1.4l8.3-5.8a.8.8 0 0 1 1.2.7zM5.5 5.5h2.3v13H5.5z'],
    heart: ['s', 'M12 20.5s-7.5-4.6-9.2-9.3C1.6 7.8 3.9 4.5 7.3 4.5c2 0 3.4 1.1 4.7 2.8 1.3-1.7 2.7-2.8 4.7-2.8 3.4 0 5.7 3.3 4.5 6.7-1.7 4.7-9.2 9.3-9.2 9.3z'],
    heartF: ['f', 'M12 20.5s-7.5-4.6-9.2-9.3C1.6 7.8 3.9 4.5 7.3 4.5c2 0 3.4 1.1 4.7 2.8 1.3-1.7 2.7-2.8 4.7-2.8 3.4 0 5.7 3.3 4.5 6.7-1.7 4.7-9.2 9.3-9.2 9.3z'],
    plus: ['s', 'M12 5v14M5 12h14'],
    shuffle: ['s', 'M3 7h3.5c4 0 5.5 10 10 10H21M18 14l3 3-3 3M3 17h3.5c1.6 0 2.8-1.3 3.8-3M13.7 10c1-1.8 2.2-3 3.8-3H21M18 4l3 3-3 3'],
    repeat: ['s', 'M4 11V9a3 3 0 0 1 3-3h13M17 3l3 3-3 3M20 13v2a3 3 0 0 1-3 3H4M7 21l-3-3 3-3'],
    repeat1: ['s', 'M4 11V9a3 3 0 0 1 3-3h13M17 3l3 3-3 3M20 13v2a3 3 0 0 1-3 3H4M7 21l-3-3 3-3M11 10.5l1.5-1v5'],
    lyrics: ['s', 'M4 5h16v11H10l-5 4v-4H4zM8 9h8M8 12.5h5'],
    music: ['s', 'M9 18V6l11-2v12M9 18a3 3 0 1 1-3-3 3 3 0 0 1 3 3zM20 16a3 3 0 1 1-3-3 3 3 0 0 1 3 3z'],
    list: ['s', 'M4 6h11M4 11h11M4 16h7M17 14v6M14 17h6'],
    apps: ['s', 'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z'],
    gear: ['s', 'M4 7h9M17 7h3M4 17h3M11 17h9M15 5v4M9 15v4'],
    more: ['f', 'M12 6.5a1.6 1.6 0 1 0 0-3.2 1.6 1.6 0 0 0 0 3.2zM12 13.6a1.6 1.6 0 1 0 0-3.2 1.6 1.6 0 0 0 0 3.2zM12 20.7a1.6 1.6 0 1 0 0-3.2 1.6 1.6 0 0 0 0 3.2z'],
    search: ['s', 'M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13zM20 20l-4.8-4.8'],
    back: ['s', 'M15 5l-7 7 7 7'],
    folder: ['s', 'M3 6.5h6l2 2h10V19H3z'],
    trash: ['s', 'M5 7h14M9.5 7V4.5h5V7M7 7l1 13h8l1-13'],
    edit: ['s', 'M4 20l4-1 11-11-3-3L5 16zM13.5 6.5l3 3'],
    open: ['s', 'M14 4h6v6M20 4l-9 9M18 14v6H4V6h6'],
    bell: ['s', 'M6 17V11a6 6 0 0 1 12 0v6l2 2H4zM10 21h4'],
    bass: ['s', 'M3 12h2M7 8v8M11 5v14M15 9v6M19 11v2'],
    check: ['s', 'M5 12.5l4.5 4.5L19 7.5'],
    close: ['s', 'M6 6l12 12M18 6L6 18'],
    upload: ['s', 'M12 15V4M7.5 8.5L12 4l4.5 4.5M4 15v5h16v-5'],
    download: ['s', 'M12 4v11M7.5 10.5L12 15l4.5-4.5M4 15v5h16v-5'],
    image: ['s', 'M4 5h16v14H4zM4 16l5-5 4 4 3-3 4 4M15 9.5a1 1 0 1 0 0-.01'],
    focus: ['s', 'M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5'],
    clip: ['s', 'M8 4h8v3H8zM6 5.5H4V21h16V5.5h-2'],
    refresh: ['s', 'M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7'],
    globe: ['s', 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18'],
    fwd: ['s', 'M9 5l7 7-7 7'],
    sparkle: ['f', 'M12 2l2.2 6.3L20.5 10l-6.3 2.2L12 18.5l-2.2-6.3L3.5 10l6.3-1.7z']
  };
  function icon(name, cls) {
    var p = P[name] || P.music;
    return p[0] === 'f'
      ? '<svg viewBox="0 0 24 24" class="' + (cls || '') + '" fill="currentColor"><path d="' + p[1] + '"/></svg>'
      : '<svg viewBox="0 0 24 24" class="' + (cls || '') + '" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="' + p[1] + '"/></svg>';
  }

  // ---------- темы (как в версии для Mac) ----------
  var THEMES = [
    { id: 'minecraft', name: 'Майнкрафт', tag: 'Пиксели, блоки и хотбар', bg: 'minecraft', pv: ['#5d9a30', '#866043', '#4a78c8'], sample: 'Аа', font: 'PressStart', sung: '#ffff55' },
    { id: 'dora', name: 'Дора', tag: 'Кьют-рок: розовый неон и звёзды', bg: 'cuteRock', pv: ['#2a0b3d', '#ff4fb8', '#b36bff'], sample: 'Аа', font: 'Unbounded', sung: '#ff6bcb' },
    { id: 'kitty', name: 'Китти', tag: 'Розовая, с бантиками и сердечками', bg: 'hearts', pv: ['#ffd6e7', '#ff5c93', '#ffffff'], sample: 'Аа', font: 'Comfortaa', sung: '#e8174f' },
    { id: 'neon', name: 'Неон', tag: 'Ретро-80-е и синтвейв', bg: 'synthwave', pv: ['#0b0322', '#ff2bd6', '#00f0ff'], sample: 'Аа', font: 'RussoOne', sung: '#00f0ff' },
    { id: 'minimal', name: 'Минимал', tag: 'Спокойная, цвета берёт из обложки', bg: 'aurora', pv: ['#1b1b24', '#7b2ff7', '#f72f8c'], sample: 'Аа', font: 'system-ui', sung: '#ffffff' }
  ];
  var BACKGROUNDS = [
    { id: 'minecraft', name: 'Майнкрафт' }, { id: 'hearts', name: 'Сердечки' }, { id: 'cuteRock', name: 'Кьют-рок' },
    { id: 'space', name: 'Космос' }, { id: 'synthwave', name: 'Синтвейв' }, { id: 'aurora', name: 'Цвета обложки' },
    { id: 'ocean', name: 'Ночной океан' }
  ];
  var PLATFORMS = {
    spotify: { name: 'Spotify', color: '#1DB954', letter: 'S', pkg: 'com.spotify.music', home: 'https://open.spotify.com/' },
    soundcloud: { name: 'SoundCloud', color: '#FF5500', letter: 'SC', pkg: 'com.soundcloud.android', home: 'https://soundcloud.com/' },
    yandex: { name: 'Яндекс Музыка', color: '#FFCC00', letter: 'Я', pkg: 'ru.yandex.music', home: 'https://music.yandex.ru/' },
    vk: { name: 'VK Музыка', color: '#0077FF', letter: 'VK', pkg: 'com.uma.musicvk', home: 'https://vk.ru/audio' }
  };
  // Пакет приложения на Android → площадка
  var PKG = {
    'com.spotify.music': 'spotify', 'com.soundcloud.android': 'soundcloud', 'ru.yandex.music': 'yandex',
    'com.uma.musicvk': 'vk', 'com.vkontakte.android': 'vk', 'ru.yandex.yandexmusic': 'yandex'
  };

  // ---------- настройки ----------
  var mobile = window.matchMedia && window.matchMedia('(max-width: 899px)').matches;
  var DEFAULTS = {
    theme: 'minecraft', background: 'minecraft', perf: 'balanced', textScale: 1, karaoke: 'letters',
    autoLyrics: true, trackToasts: true, keepScreenOn: false, bass: 0, treble: 0, shuffle: false, repeat: 'all',
    volume: 0.8, particles: true, lastTab: 'np',
    // 2.4: закруглённая панель (на телефоне сразу), жидкое стекло, автопроверка обновлений
    roundPanel: mobile, glass: false, autoUpdates: true, seen: {}, skipVersion: ''
  };

  // ---------- новые функции: плашка «Новое» 240 минут после первого запуска версии ----------
  var NEW_MINUTES = 240;
  var FEATURES = { updates: '2.4.0', roundPanel: '2.4.0', glass: '2.4.0', browser: '2.4.0' };
  function isNew(id) {
    var v = FEATURES[id], t = v && Store.settings.seen && Store.settings.seen[v];
    return !!t && Date.now() - t < NEW_MINUTES * 60000;
  }
  function anyNew() { return Object.keys(FEATURES).some(isNew); }
  function newBadge(id) { return isNew(id) ? '<span class="new-badge" data-f="' + id + '">Новое</span>' : ''; }

  // Сравнение версий «2.4.0» / «v2.10.1»
  function cmpVersion(a, b) {
    var x = String(a || '0').replace(/^v/i, '').split(/[.-]/), y = String(b || '0').replace(/^v/i, '').split(/[.-]/);
    for (var i = 0; i < Math.max(x.length, y.length); i++) {
      var p = parseInt(x[i] || '0', 10) || 0, q = parseInt(y[i] || '0', 10) || 0;
      if (p !== q) return p > q ? 1 : -1;
    }
    return 0;
  }
  var PERF = {
    eco: { name: 'Экономия', fps: 20, particles: false, blur: false, dpr: 1, tag: 'Дольше работает от батареи' },
    balanced: { name: 'Баланс', fps: mobile ? 30 : 60, particles: true, blur: false, dpr: 1.5, tag: 'Плавно и не греет телефон' },
    beauty: { name: 'Красота', fps: 60, particles: true, blur: true, dpr: 2, tag: 'Все эффекты на максимум' }
  };

  var Store = {
    settings: Object.assign({}, DEFAULTS),
    playlists: [],
    loaded: false,
    load: function () {
      return Promise.all([NB.readFile('settings.json'), NB.readFile('library.json')]).then(function (r) {
        try { Object.assign(Store.settings, JSON.parse(r[0] || '{}')); } catch (e) {}
        if (Store.settings.roundPanel == null) Store.settings.roundPanel = mobile;
        Store.playlists = Store.parseLibrary(r[1]) || [];
        Store.ensureFavorites();
        Store.loaded = true;
        var ver = String(NB.version()).replace(/^v/i, '');
        if (!Store.settings.seen || typeof Store.settings.seen !== 'object') Store.settings.seen = {};
        if (!Store.settings.seen[ver]) { Store.settings.seen[ver] = Date.now(); Store.saveSettings(); }
      });
    },
    // Понимает и формат версии для Mac, и простой список плейлистов
    parseLibrary: function (text) {
      if (!text) return null;
      var d;
      try { d = JSON.parse(text); } catch (e) { return null; }
      var list = Array.isArray(d) ? d : (d && Array.isArray(d.playlists) ? d.playlists : null);
      if (!list) return null;
      return list.map(function (p) {
        return {
          id: String(p.id || U.uuid()).toUpperCase(), name: String(p.name || 'Плейлист'), created: p.created || U.iso(),
          items: (Array.isArray(p.items) ? p.items : []).filter(function (t) { return t && t.source && t.title; }).map(function (t) {
            return {
              id: String(t.id || U.uuid()).toUpperCase(), source: t.source, title: String(t.title), artist: String(t.artist || ''),
              album: String(t.album || ''), duration: +t.duration || 0, artURL: t.artURL || null, added: t.added || U.iso()
            };
          })
        };
      });
    },
    libraryText: function (app) {
      return JSON.stringify({ format: 'muzyka-offline-library', version: 2, app: app || NB.kind, savedAt: U.iso(), playlists: Store.playlists }, null, 2);
    },
    ensureFavorites: function () {
      var FAV = 'F4F0F4F0-0000-4000-8000-00000000F4F0';
      if (!Store.playlists.some(function (p) { return p.id === FAV; })) {
        Store.playlists.unshift({ id: FAV, name: 'Любимые', created: U.iso(), items: [] });
      }
    },
    favID: 'F4F0F4F0-0000-4000-8000-00000000F4F0',
    saveSettings: null,
    saveLibrary: null
  };
  Store.saveSettings = U.debounce(function () { NB.writeFile('settings.json', JSON.stringify(Store.settings)); }, 300);
  Store.saveLibrary = U.debounce(function () { NB.writeFile('library.json', Store.libraryText()); }, 400);

  // Небольшие кэши (тексты, адреса обложек, сдвиги) — в памяти страницы, переживают перезапуск
  var Cache = {
    get: function (k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set: function (k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) {} }
  };

  // Сообщение внизу экрана
  var toastTimer = null;
  function toast(text) {
    var el = document.getElementById('toast');
    el.textContent = text;
    el.classList.add('on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.classList.remove('on'); }, 3200);
  }

  window.isNew = isNew;
  window.anyNew = anyNew;
  window.newBadge = newBadge;
  window.cmpVersion = cmpVersion;
  window.FEATURES = FEATURES;
  window.U = U;
  window.icon = icon;
  window.THEMES = THEMES;
  window.BACKGROUNDS = BACKGROUNDS;
  window.PLATFORMS = PLATFORMS;
  window.PKG = PKG;
  window.PERF = PERF;
  window.Store = Store;
  window.Cache = Cache;
  window.toast = toast;
})();
