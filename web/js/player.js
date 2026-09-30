/* Плеер: свои файлы (на Android — служба, которая играет и с выключенным экраном; на Windows — в окне,
   с настоящим эквалайзером), плюс то, что играет в Spotify / Яндекс Музыке / VK / SoundCloud на Android.
   Переключение одинаковое везде: «перемешать» проигрывает каждый трек по разу, «назад» после 3 секунд
   возвращает в начало трека, битый файл пропускается, но без бесконечного круга. */
(function () {
  'use strict';

  var android = NB.kind === 'android';
  var Player = {
    queue: [],           // треки очереди: {uri, title, artist, album, duration}
    index: -1,
    qid: '',             // номер очереди (чтобы понимать, чья очередь сейчас в службе Android)
    sentAt: 0,
    playing: false,      // пользователь хочет, чтобы играло
    buffering: false,
    modeOverride: null,  // плейлист с треками площадок: свой режим для файлов (без повтора)
    pos: 0, dur: 0,
    order: [], op: -1,   // порядок игры (Windows / браузер)
    wants: false, failures: 0, pendingSeek: 0,
    ext: null,           // что играет в другом приложении (Android)
    extList: [],
    site: null,          // что играет на сайте площадки во встроенном браузере (sites.js)
    lastTick: 0,
    lastLocal: 0,
    listeners: [],
    audio: null, actx: null, analyser: null, lowShelf: null, highShelf: null, freq: null
  };

  function emit() { Player.listeners.forEach(function (f) { try { f(); } catch (e) { console.error(e); } }); }
  Player.onChange = function (f) { Player.listeners.push(f); };
  function noop() {}

  // ---------- Windows / браузер: играем в самой странице ----------
  function html() {
    if (Player.audio) return Player.audio;
    var a = new Audio();
    a.preload = 'auto';
    a.volume = Math.max(0, Math.min(1, Store.settings.volume != null ? +Store.settings.volume : 1));
    a.addEventListener('timeupdate', function () { Player.pos = a.currentTime; if (a.duration) Player.dur = a.duration; });
    a.addEventListener('playing', function () { Player.failures = 0; Player.buffering = false; Player.playing = true; emit(); });
    a.addEventListener('waiting', function () { Player.buffering = true; });
    a.addEventListener('pause', function () { if (!a.ended) { Player.playing = false; emit(); } });
    a.addEventListener('loadedmetadata', function () {
      Player.dur = a.duration || Player.dur;
      if (Player.pendingSeek > 0 && (!a.duration || Player.pendingSeek < a.duration - 1)) a.currentTime = Player.pendingSeek;
      Player.pendingSeek = 0;
      emit();
    });
    a.addEventListener('ended', function () { Player.next(true); });
    a.addEventListener('error', function () {
      if (!a.getAttribute('src')) return;
      var t = Player.current();
      toast('Не получилось открыть «' + (t ? t.title : 'файл') + '»');
      failed();
    });
    Player.audio = a;
    return a;
  }
  function graph() {
    if (Player.actx || !window.AudioContext) return;
    try {
      var ctx = new AudioContext(), src = ctx.createMediaElementSource(html());
      var low = ctx.createBiquadFilter(); low.type = 'lowshelf'; low.frequency.value = 100;
      var high = ctx.createBiquadFilter(); high.type = 'highshelf'; high.frequency.value = 7000;
      var an = ctx.createAnalyser(); an.fftSize = 2048; an.smoothingTimeConstant = 0.6;
      src.connect(low); low.connect(high); high.connect(an); an.connect(ctx.destination);
      Player.actx = ctx; Player.analyser = an; Player.lowShelf = low; Player.highShelf = high;
      Player.freq = new Uint8Array(an.frequencyBinCount);
      Player.setBass(Store.settings.bass);
    } catch (e) { console.warn('audio graph', e); }
  }
  function startHtml() {
    var a = html();
    graph();
    if (Player.actx && Player.actx.state === 'suspended') Player.actx.resume();
    Player.wants = true; Player.playing = true;
    a.play().catch(function (e) { if (e && e.name === 'NotAllowedError') { Player.wants = false; Player.playing = false; emit(); } });
  }
  function loadHtml(play, start) {
    var t = Player.queue[Player.index];
    if (!t) return;
    var a = html();
    Player.pendingSeek = start > 0 ? start : 0;
    Player.pos = Player.pendingSeek; Player.dur = t.duration || 0;
    Player.buffering = !!play;
    a.src = NB.mediaURL(t.uri);
    if (play) startHtml();
    else { Player.wants = false; Player.playing = false; a.load(); }
  }
  // Файл не открылся: следующий, но если подряд не открылось несколько — останавливаемся
  function failed() {
    Player.failures++;
    if (!Player.wants || Player.failures >= Math.min(Player.queue.length, 5)) {
      Player.failures = 0; Player.wants = false; Player.playing = false; Player.buffering = false; emit();
      return;
    }
    setTimeout(function () { Player.next(true); }, 250);
  }

  // Порядок игры: по списку или вперемешку (каждый трек по разу, текущий — первым)
  function shuffled(a) {
    for (var i = a.length - 1; i > 0; i--) { var j = Math.random() * (i + 1) | 0, t = a[i]; a[i] = a[j]; a[j] = t; }
    return a;
  }
  function mode() { return Player.modeOverride || { shuffle: Store.settings.shuffle, repeat: Store.settings.repeat }; }
  Player.mode = mode;
  function buildOrder(cur) {
    var n = Player.queue.length, o = [];
    for (var i = 0; i < n; i++) o.push(i);
    if (mode().shuffle && n > 1) {
      shuffled(o);
      var k = o.indexOf(cur); o[k] = o[0]; o[0] = cur;
      Player.op = 0;
    } else Player.op = Math.max(0, Math.min(cur, n - 1));
    Player.order = o;
  }
  function reshuffle() {
    var last = Player.index;
    shuffled(Player.order);
    if (Player.order.length > 1 && Player.order[0] === last) { Player.order[0] = Player.order[1]; Player.order[1] = last; }
  }

  // ---------- очередь своих файлов ----------
  // startPos — с какого места (секунды): так работает «продолжить с того же места»
  Player.setQueue = function (tracks, index, autoplay, startPos) {
    if (!tracks || !tracks.length) return;
    var play = autoplay !== false, start = Math.max(0, +startPos || 0);
    Player.queue = tracks.map(function (t) {
      return { uri: t.uri, title: t.title || '', artist: t.artist || '', album: t.album || '', duration: +t.duration || 0 };
    });
    Player.index = Math.max(0, Math.min(index || 0, tracks.length - 1));
    Player.qid = U.uuid();
    Player.failures = 0;
    Player.pos = start; Player.dur = Player.queue[Player.index].duration; Player.lastTick = Date.now();
    if (android) {
      Player.sentAt = Date.now();
      NB.setMode(mode().shuffle, mode().repeat);
      NB.setQueue(Player.qid, Player.queue, Player.index, play, start);
      Player.playing = play; Player.buffering = play;
    } else {
      buildOrder(Player.index);
      loadHtml(play, start);
    }
    Player.lastLocal = Date.now();
    if (play) Player.quietSites();
    emit();
  };
  Player.current = function () { return Player.queue[Player.index] || null; };
  // Своя музыка заиграла — сайты площадок замолкают (как на Mac: играет что-то одно)
  Player.quietSites = function () { if (window.Sites) Sites.pauseAll(); if (Player.site) { Player.site.playing = false; Player.site.stamp = 0; } };
  // Заиграл сайт — своя музыка на паузу
  Player.yieldToSite = function () {
    if (!Player.playing) return;
    if (android) NB.control('pause'); else if (Player.audio) { Player.wants = false; Player.audio.pause(); }
    Player.pos = Player.time(); Player.playing = false; Player.lastTick = Date.now();
    emit();
  };

  Player.toggle = function () {
    if (Player.useSite()) { Sites.cmd(Player.site.tab, Player.site.playing ? 'pause' : 'play'); Player.site.playing = !Player.site.playing; Player.site.stamp = Date.now(); emit(); return; }
    if (Player.useExt()) { NB.sessionControl(Player.ext.pkg, Player.ext.playing ? 'pause' : 'play'); Player.ext.playing = !Player.ext.playing; emit(); return; }
    if (!Player.current()) return;
    if (!Player.playing) Player.quietSites();
    if (android) {
      NB.control(Player.playing ? 'pause' : 'play');
      if (Player.playing) Player.pos = Player.time();
      Player.playing = !Player.playing; Player.lastTick = Date.now();
    } else {
      var a = html();
      if (a.paused || !Player.playing) {
        if (!a.getAttribute('src')) loadHtml(true, Player.pos); else startHtml();
      } else { Player.wants = false; a.pause(); }
    }
    Player.lastLocal = Date.now();
    emit();
  };
  function androidSkip(cmd) {
    NB.control(cmd);
    Player.playing = true; Player.buffering = true;
    Player.lastLocal = Date.now();
    setTimeout(function () { Player.poll(); }, 150);
  }
  // auto — трек доиграл сам
  Player.next = function (auto) {
    if (!auto && window.Runner && Runner.active && Runner.step(1)) return;
    if (!auto && Player.useSite()) { if (!(window.Runner && Runner.step(1))) Sites.cmd(Player.site.tab, 'nexttrack'); return; }
    if (!auto && Player.useExt()) { NB.sessionControl(Player.ext.pkg, 'next'); return; }
    if (!Player.queue.length) return;
    if (android) { androidSkip('next'); return; }
    var n = Player.queue.length, rep = mode().repeat;
    if (auto && rep === 'one') { var a = html(); a.currentTime = 0; startHtml(); return; }
    var nop = Player.op + 1;
    if (nop >= n) {
      if (!auto || rep === 'all') { if (mode().shuffle && n > 1) reshuffle(); nop = 0; }
      else {
        Player.op = 0; Player.index = Player.order[0]; loadHtml(false, 0); emit();   // очередь кончилась
        if (Player.onQueueEnd) Player.onQueueEnd();
        return;
      }
    }
    Player.op = nop; Player.index = Player.order[nop];
    loadHtml(true, 0); emit();
  };
  Player.prev = function () {
    if (window.Runner && Runner.active && !Player.useSite() && Player.time() <= 3 && Runner.step(-1)) return;
    if (Player.useSite()) {
      if (Player.time() > 3) { Player.seek(0); return; }
      if (!(window.Runner && Runner.step(-1))) Sites.cmd(Player.site.tab, 'previoustrack');
      return;
    }
    if (Player.useExt()) { NB.sessionControl(Player.ext.pkg, 'prev'); return; }
    if (!Player.queue.length) return;
    if (android) { androidSkip('prev'); return; }        // правило «3 секунды» служба выполняет сама
    if (Player.time() > 3) { Player.seek(0); if (!Player.playing) startHtml(); return; }
    var nop = Player.op - 1;
    if (nop < 0) nop = mode().repeat === 'all' ? Player.queue.length - 1 : 0;
    Player.op = nop; Player.index = Player.order[nop];
    loadHtml(true, 0); emit();
  };
  // Включить конкретный трек очереди
  Player.jump = function (i) {
    if (i < 0 || i >= Player.queue.length) return;
    if (android) { NB.control('jump', i); Player.index = i; androidSkip('noop'); return; }
    Player.index = i; Player.op = Math.max(0, Player.order.indexOf(i));
    loadHtml(true, 0); emit();
  };
  Player.seek = function (t) {
    t = Math.max(0, t);
    if (Player.useSite()) { Sites.cmd(Player.site.tab, 'seekto', t); Player.site.pos = t; Player.site.stamp = Date.now(); return; }
    if (Player.useExt()) { NB.sessionControl(Player.ext.pkg, 'seek', t); Player.ext.pos = t; Player.ext.stamp = Date.now(); return; }
    if (android) NB.control('seek', t);
    else { var a = html(); if (a.readyState > 0) a.currentTime = t; else Player.pendingSeek = t; }
    Player.pos = t; Player.lastTick = Date.now();
  };
  Player.setBass = function (v) {
    if (android) NB.setBass(v);
    if (Player.lowShelf) Player.lowShelf.gain.value = v;
    if (Player.highShelf) Player.highShelf.gain.value = Store.settings.treble || 0;
  };
  Player.setMode = function () {
    if (android) NB.setMode(mode().shuffle, mode().repeat);
    else if (Player.queue.length) buildOrder(Player.index);
  };
  // Громкость своей музыки (Windows; на телефоне — кнопками громкости)
  Player.volume = function (v) {
    if (v == null) return Player.audio ? Player.audio.volume : (Store.settings.volume || 0.8);
    v = Math.max(0, Math.min(1, v));
    Store.settings.volume = v; Store.saveSettings();
    if (Player.audio) Player.audio.volume = v;
    return v;
  };

  // Время сейчас (с досчётом между опросами службы)
  Player.time = function () {
    if (Player.useSite()) {
      var s = Player.site;
      return s.playing ? Math.min(s.dur || 1e9, s.pos + (Date.now() - s.stamp) / 1000) : s.pos;
    }
    if (Player.useExt()) {
      var e = Player.ext;
      return e.playing ? Math.min(e.dur || 1e9, e.pos + (Date.now() - e.stamp) / 1000) : e.pos;
    }
    if (!android) return Player.audio && Player.audio.getAttribute('src') ? (Player.audio.readyState > 0 ? Player.audio.currentTime : Player.pos) : Player.pos;
    return Player.playing && !Player.buffering ? Math.min(Player.dur || 1e9, Player.pos + (Date.now() - Player.lastTick) / 1000) : Player.pos;
  };
  Player.duration = function () { return Player.useSite() ? Player.site.dur : Player.useExt() ? Player.ext.dur : Player.dur; };
  Player.isPlaying = function () { return Player.useSite() ? Player.site.playing : Player.useExt() ? Player.ext.playing : Player.playing; };

  // Что показывать: сайт площадки, другое приложение или своё
  Player.useSite = function () {
    var s = Player.site;
    if (!s || !s.title) return false;
    if (Player.playing) return false;
    return s.playing || s.loading || (s.stamp > (Player.lastLocal || 0) && !(Player.ext && Player.ext.playing));
  };
  Player.useExt = function () {
    if (!Player.ext) return false;
    if (Player.playing) return false;
    if (Player.site && Player.site.playing) return false;
    return Player.ext.playing || !Player.current() || (Player.ext.stamp > (Player.lastLocal || 0));
  };

  // Трек, который сейчас на экране (единый вид для всех источников)
  Player.now = function () {
    if (Player.useSite()) {
      var s = Player.site, sp = PLATFORMS[s.platform];
      return { kind: 'site', key: U.webKey(s.artist || '', s.title || ''), title: s.title || '', artist: s.artist || '', album: s.album || '',
               duration: s.dur || 0, platform: s.platform, app: sp ? sp.name : 'Сайт', tab: s.tab, art: s.art || null, loading: !!s.loading,
               source: { web: { platform: s.platform || 'other', link: s.link || null } } };
    }
    if (Player.useExt()) {
      var e = Player.ext, pl = PKG[e.pkg];
      return { kind: 'ext', key: U.webKey(e.artist || '', e.title || ''), title: e.title || '', artist: e.artist || '', album: e.album || '',
               duration: e.dur || 0, platform: pl || null, app: e.app, pkg: e.pkg, art: e.art || null,
               source: { web: { platform: pl || 'other', link: null } } };
    }
    var t = Player.current();
    if (!t) return null;
    return { kind: 'file', key: 'file:' + t.uri, title: t.title, artist: t.artist, album: t.album || '', duration: Player.dur || t.duration || 0,
             uri: t.uri, art: null, source: { file: { path: t.uri } } };
  };

  // Спектр для живого фона (только когда играем сами на Windows)
  Player.spectrum = function () {
    if (!Player.analyser || !Player.playing || android) return null;
    Player.analyser.getByteFrequencyData(Player.freq);
    var out = new Float32Array(Player.freq.length);
    for (var i = 0; i < out.length; i++) out[i] = Player.freq[i] / 255;
    return out;
  };
  Player.binHz = function () { return Player.actx ? Player.actx.sampleRate / 2048 : 44100 / 2048; };

  // ---------- состояние службы Android ----------
  Player.applyState = function (st) {
    if (!st || !android) return;
    if (st.qid !== Player.qid) {
      // только что отправили новую очередь — служба её ещё не приняла
      if (Date.now() - Player.sentAt < 1500) return;
      if (st.length > 0) {
        var q = NB.queueState();
        if (q && q.items && q.items.length) { Player.queue = q.items; Player.qid = q.qid; }
      } else if (!st.length && Player.queue.length) {
        Player.queue = []; Player.index = -1; Player.qid = '';     // плеер закрыли из уведомления
        Player.playing = false; emit(); return;
      }
    }
    var changed = st.index !== Player.index || !!st.playing !== Player.playing || !!st.buffering !== Player.buffering;
    Player.index = st.index; Player.playing = !!st.playing; Player.buffering = !!st.buffering;
    Player.pos = st.pos || 0; if (st.dur > 0) Player.dur = st.dur;
    Player.lastTick = Date.now();
    if (st.playing) Player.lastLocal = Date.now();
    if (changed) emit();
  };
  if (android) {
    NB.on('state', function (st) { Player.applyState(st); });
    NB.on('error', function (e) { toast('Не получилось открыть «' + ((e && e.title) || 'файл') + '» — пропускаю'); });
  }

  // ---------- опрос службы Android и других приложений ----------
  Player.poll = function () {
    if (!android) return;
    Player.applyState(NB.playbackState());
    if (NB.hasNotifAccess()) {
      var list = NB.sessions().filter(function (s) { return s.pkg !== 'ru.muzyka.offline'; });
      Player.extList = list;
      var best = list.filter(function (s) { return s.playing; })[0] || (Player.ext ? list.filter(function (s) { return s.pkg === Player.ext.pkg; })[0] : null) || null;
      var prev = Player.ext;
      if (best) {
        var same = prev && prev.pkg === best.pkg && prev.title === best.title;
        var art = same && prev.art ? prev.art : (NB.sessionArt(best.pkg) || null);
        Player.ext = { pkg: best.pkg, app: best.app, title: best.title, artist: best.artist, album: best.album, dur: best.dur || 0,
                       pos: best.pos || 0, playing: !!best.playing, stamp: Date.now(), art: art };
      } else Player.ext = null;
      var ch = (!prev) !== (!Player.ext) || (prev && Player.ext && (prev.title !== Player.ext.title || prev.playing !== Player.ext.playing ||
               prev.pkg !== Player.ext.pkg || (!prev.art && Player.ext.art)));
      if (ch) emit();
    }
  };

  // Windows: медиаклавиши и системная панель управления музыкой
  if (!android && navigator.mediaSession) {
    var ms = navigator.mediaSession, metaFor = null;
    var h = {
      play: function () { if (!Player.playing) Player.toggle(); },
      pause: function () { if (Player.playing) Player.toggle(); },
      nexttrack: function () { Player.next(false); },
      previoustrack: function () { Player.prev(); },
      seekto: function (d) { if (d && d.seekTime != null) Player.seek(d.seekTime); }
    };
    Object.keys(h).forEach(function (k) { try { ms.setActionHandler(k, h[k]); } catch (e) {} });
    Player.onChange(function () {
      var t = Player.now();
      if (!t) return;
      if (metaFor !== t.key) {
        var k = metaFor = t.key;
        var set = function (art) {
          try { ms.metadata = new MediaMetadata({ title: t.title, artist: t.artist, album: t.album || '', artwork: art ? [{ src: art, sizes: '400x400' }] : [] }); } catch (e) {}
        };
        set(t.art || null);
        if (!t.art && window.Art) Art.resolve(t).then(function (u) { if (u && metaFor === k) set(u); });
      }
      try { ms.playbackState = Player.isPlaying() ? 'playing' : 'paused'; } catch (e) {}
    });
  }

  // Состояние сайта площадки (sites.js сообщает, что играет)
  Player.setSite = function (st) {
    var prev = Player.site;
    Player.site = st;
    var changed = !prev !== !st || (prev && st && (prev.title !== st.title || prev.artist !== st.artist || prev.playing !== st.playing ||
                  prev.art !== st.art || prev.loading !== st.loading || prev.tab !== st.tab || Math.abs((prev.dur || 0) - (st.dur || 0)) > 1));
    if (st && st.playing && (!prev || !prev.playing)) Player.yieldToSite();
    if (changed) emit();
  };
  Player.emit = emit;

  window.Player = Player;
})();
