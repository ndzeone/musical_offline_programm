/* Экраны и управление: «Сейчас играет», «Музыка», плейлисты, «Площадки», «Настройки». */
(function () {
  'use strict';

  var S = {
    tab: 'np', libSeg: 'device', playlist: null, device: [], search: '', focus: false,
    lyr: {}, nowKey: null, artTracks: {}, scene: null, previews: {}, deviceLoaded: false, askedMusic: false
  };
  var $ = function (id) { return document.getElementById(id); };
  // Широкий экран с боковой панелью (как в app.css) и телефон, повёрнутый боком
  function isDesk() { return window.matchMedia('(min-width: 900px) and (min-height: 541px)').matches; }
  function isLand() { return window.matchMedia('(orientation: landscape) and (max-height: 540px)').matches; }
  var esc = U.esc;
  var FAV = Store.favID;

  // ---------- оформление ----------
  function applyLook() {
    var s = Store.settings, perf = PERF[s.perf] || PERF.balanced;
    document.body.dataset.theme = s.theme;
    document.body.classList.toggle('eco', s.perf === 'eco');
    document.body.classList.toggle('noblur', !perf.blur);
    document.documentElement.style.setProperty('--scale', s.textScale);
    if (S.scene) { S.scene.id = s.background; S.scene.fps = perf.fps; S.scene.dpr = perf.dpr; }
    NB.systemBars(s.theme === 'kitty');
    NB.keepScreenOn(!!s.keepScreenOn);
  }

  // ---------- обложки ----------
  function artHTML(t, cls) {
    var key = Art.keyOf(t), known = Art.known(t);
    S.artTracks[key] = t;
    var src = known || Art.placeholder((t.artist || '') + (t.title || ''));
    return '<div class="art ' + (cls || '') + '"><img src="' + esc(src) + '" data-art="' + esc(key) + '"' + (known ? '' : ' data-ph="1"') + ' alt=""></div>';
  }
  function hydrateArt(root) {
    (root || document).querySelectorAll('img[data-ph="1"]').forEach(function (img) {
      img.removeAttribute('data-ph');
      var t = S.artTracks[img.getAttribute('data-art')];
      if (!t) return;
      Art.resolve(t).then(function (u) {
        if (!u) return;
        document.querySelectorAll('img[data-art="' + CSS.escape(img.getAttribute('data-art')) + '"]').forEach(function (i) { i.src = u; });
        if (t.source && t.source.web) patchArt(t, u);
      });
    });
  }
  // Найденную обложку запоминаем в плейлистах
  function patchArt(t, u) {
    var key = Art.keyOf(t), changed = false;
    Store.playlists.forEach(function (p) {
      p.items.forEach(function (it) { if (!it.artURL && Art.keyOf(it) === key) { it.artURL = u; changed = true; } });
    });
    if (changed) Store.saveLibrary();
  }
  function badge(platform, size) {
    var p = PLATFORMS[platform];
    if (!p) return '<span class="badge" style="background:#777">?</span>';
    var ic = Art.platformIcon(platform), st = size ? 'width:' + size + 'px;height:' + size + 'px;' : '';
    if (ic) return '<span class="badge" style="' + st + '"><img src="' + esc(ic) + '" alt=""></span>';
    return '<span class="badge" style="' + st + 'background:' + p.color + ';color:' + (platform === 'yandex' ? '#000' : '#fff') + '">' + p.letter + '</span>';
  }
  function sourceLabel(t) {
    if (t.source && t.source.web) {
      var p = PLATFORMS[t.source.web.platform];
      return badge(t.source.web.platform, 16) + '<span class="ell">' + esc(p ? p.name : 'Площадка') + '</span>';
    }
    var path = (t.source && t.source.file && t.source.file.path) || t.uri || '';
    var ext = (/\.([a-z0-9]{2,5})$/i.exec(path) || [])[1];
    return icon('music') .replace('<svg', '<svg style="width:13px;height:13px"') + '<span>Файл' + (ext ? ' · ' + ext.toUpperCase() : '') + '</span>';
  }

  // ---------- навигация ----------
  var TABS = [
    { id: 'np', name: 'Играет', ic: 'music' },
    { id: 'lib', name: 'Музыка', ic: 'list' },
    { id: 'apps', name: 'Площадки', ic: 'apps' },
    { id: 'set', name: 'Настройки', ic: 'gear' }
  ];
  function renderTabs() {
    $('tabs').innerHTML = TABS.map(function (t) {
      return '<button class="tab' + (S.tab === t.id ? ' on' : '') + '" data-a="tab" data-x="' + t.id + '">' + icon(t.ic) + '<span>' + t.name + '</span></button>';
    }).join('');
    var logo = LOGO();
    $('side').innerHTML = '<div class="side-logo"><img src="' + logo + '" alt="">Музыка<br>в офлайн</div>' +
      TABS.map(function (t) {
        return '<button class="side-item' + (S.tab === t.id && !S.playlist ? ' on' : '') + '" data-a="tab" data-x="' + t.id + '">' + icon(t.ic) + t.name + '</button>';
      }).join('') +
      '<div class="label" style="margin:18px 10px 6px">Плейлисты</div>' +
      Store.playlists.map(function (p) {
        return '<button class="side-item' + (S.playlist === p.id ? ' on' : '') + '" data-a="openPl" data-x="' + p.id + '">' + icon(p.id === FAV ? 'heart' : 'list') + '<span class="ell">' + esc(p.name) + '</span></button>';
      }).join('') +
      '<button class="side-item" data-a="newPl">' + icon('plus') + 'Новый плейлист</button>';
  }
  function go(tab) {
    S.tab = tab; S.playlist = null; S.focus = false;
    Store.settings.lastTab = tab; Store.saveSettings();
    render();
  }

  // ---------- главный рендер ----------
  function render() {
    renderTabs();
    var el = $('screen');
    if (S.playlist) el.innerHTML = playlistScreen(S.playlist);
    else if (S.tab === 'np') el.innerHTML = npScreen();
    else if (S.tab === 'lib') el.innerHTML = libScreen();
    else if (S.tab === 'apps') el.innerHTML = appsScreen();
    else el.innerHTML = setScreen();
    renderMini();
    hydrateArt(el);
    if (S.tab === 'np' && !S.playlist) { layoutNP(); buildLyrics(); }
    if (S.tab === 'set' && !S.playlist) drawPreviews();
    tickProgress();
  }

  // ---------- «Сейчас играет» ----------
  function npScreen() {
    var now = Player.now();
    if (!now) return welcome();
    var playing = Player.isPlaying(), liked = isFav(now);
    var src = now.kind === 'ext'
      ? (now.platform ? badge(now.platform, 16) : '') + '<span class="ell">' + esc(now.app || 'Приложение') + '</span>'
      : sourceLabel(now);
    var sticker = '';
    var th = Store.settings.theme;
    if (th === 'dora') sticker = '<span class="sticker" style="top:-14px;right:-10px">✨</span><span class="sticker" style="bottom:-12px;left:-10px">💖</span>';
    if (th === 'kitty') sticker = '<span class="sticker" style="top:-18px;left:-14px;font-size:38px">🎀</span>';
    return '<div class="np' + (playing ? ' playing' : '') + (S.focus ? ' focus' : '') + '" id="np">' +
      '<div class="np-top"><span class="chip">' + src + '</span>' +
      '<button class="icon-btn" data-a="lyricsSheet">' + icon('lyrics') + '</button></div>' +
      '<div class="np-side"><div class="np-cover-wrap" data-a="focus"><div class="np-vinyl"></div>' +
      '<div class="np-cover art">' + coverImg(now) + '</div>' + sticker + '</div>' +
      '<div class="np-meta"><div class="np-title mc-shadow">' + esc(now.title) + '</div><div class="np-artist">' + esc(now.artist) + '</div></div></div>' +
      '<div class="np-lyrics" data-a="focus"><div class="lyr" id="lyr"></div><div class="np-nolyr hide" id="nolyr"></div></div>' +
      '<div class="np-prog"><div class="seek" id="npseek"><div class="track"><div class="fill"></div></div><div class="knob"></div></div>' +
      '<div class="times"><span id="tcur">0:00</span><span id="tdur">' + U.time(Player.duration()) + '</span></div></div>' +
      '<div class="np-ctrl">' +
      '<button class="icon-btn' + (Store.settings.shuffle ? ' on' : '') + '" data-a="shuffle">' + icon('shuffle') + '</button>' +
      '<div class="main"><button class="icon-btn" data-a="prev">' + icon('prev') + '</button>' +
      '<button class="play-btn" data-a="toggle">' + icon(playing ? 'pause' : 'play') + '</button>' +
      '<button class="icon-btn" data-a="next">' + icon('next') + '</button></div>' +
      '<button class="icon-btn' + (Store.settings.repeat !== 'none' ? ' on' : '') + '" data-a="repeat">' + icon(Store.settings.repeat === 'one' ? 'repeat1' : 'repeat') + '</button></div>' +
      '<div class="np-actions">' +
      '<button class="icon-btn round' + (liked ? ' on' : '') + '" data-a="fav">' + icon(liked ? 'heartF' : 'heart') + '</button>' +
      '<button class="icon-btn round" data-a="addTo">' + icon('plus') + '</button>' +
      '<button class="icon-btn round" data-a="focus">' + icon('focus') + '</button>' +
      '<button class="icon-btn round" data-a="trackMenu">' + icon('more') + '</button>' +
      '</div></div>';
  }
  function coverImg(now) {
    if (now.art) return '<img src="' + esc(now.art) + '" alt="">';
    S.artTracks[Art.keyOf(now)] = now;
    var k = Art.known(now);
    return '<img src="' + esc(k || Art.placeholder(now.artist + now.title)) + '" data-art="' + esc(Art.keyOf(now)) + '"' + (k ? '' : ' data-ph="1"') + ' alt="">';
  }
  function layoutNP() {
    var np = $('np');
    if (!np) return;
    var W = np.clientWidth, H = np.clientHeight, desk = isDesk();
    var cov = desk ? Math.min(420, Math.max(220, Math.min(W * 0.3, H * 0.52)))
      : isLand() ? Math.round(Math.max(110, Math.min(H * 0.5, W * 0.3, 240)))
      : Math.round(Math.min(W - 80, Math.max(150, H * 0.3), 340));
    np.style.setProperty('--cov', cov + 'px');
  }
  function welcome() {
    var android = NB.kind === 'android';
    return '<div class="welcome"><img class="logo" src="' + LOGO() + '" alt="">' +
      '<div class="h1 mc-shadow">Музыка в офлайн</div><div class="sub">Твоя музыка, тексты песен и живые фоны</div>' +
      '<button class="btn primary block" style="max-width:340px" data-a="' + (android ? 'libDevice' : 'pickFiles') + '">' + icon('folder') + (android ? 'Музыка на телефоне' : 'Открыть файлы') + '</button>' +
      '<button class="btn block" style="max-width:340px" data-a="tab" data-x="apps">' + icon('apps') + 'Spotify, Яндекс, VK, SoundCloud</button>' +
      '<button class="btn block" style="max-width:340px" data-a="tab" data-x="set">' + icon('gear') + 'Темы и фоны</button>' +
      (resumeHTML() || '') + '</div>';
  }
  function resumeHTML() {
    var last = Store.settings.last;
    if (!last || !last.queue || !last.queue.length || Player.current()) return '';
    var t = last.queue[last.index] || last.queue[0];
    return '<button class="row" style="max-width:360px;width:100%;margin-top:8px" data-a="resume">' + artHTML(t) +
      '<div class="meta"><div class="a">Продолжить</div><div class="t ell">' + esc(t.title) + '</div></div>' + icon('play').replace('<svg', '<svg style="width:22px;height:22px"') + '</button>';
  }

  // ---------- текст песни ----------
  function lyrEntry(now) {
    if (!now) return null;
    var e = S.lyr[now.key];
    if (!e) {
      e = S.lyr[now.key] = { ly: null, status: 'Ищу текст…', offset: +(Cache.get('off:' + now.key) || 0), results: [], idx: 0, source: '' };
      var cached = Cache.get('lyr:' + now.key);
      if (cached) setLy(now, cached, 'сохранённый текст');
      else if (!now.title) e.status = 'Нет названия трека';
      else if (Store.settings.autoLyrics) searchLyrics(now, null, 0);
      else e.status = 'Автопоиск текста выключен — нажми «Текст»';
    }
    return e;
  }
  function setLy(now, text, source, save) {
    var e = S.lyr[now.key] || (S.lyr[now.key] = { offset: 0, results: [], idx: 0 });
    var p = Lyrics.parse(text);
    if (!p) return false;
    e.plain = p.synced ? null : p;
    e.ly = p.synced ? p : Lyrics.estimate(p, now.duration);
    e.source = source; e.status = '';
    if (save) Cache.set('lyr:' + now.key, text);
    if (currentKey() === now.key) buildLyrics();
    return true;
  }
  function searchLyrics(now, query, attempt) {
    var e = S.lyr[now.key];
    e.status = 'Ищу текст…';
    Lyrics.find(now.artist, now.title, now.duration, query).then(function (list) {
      if (!list.length) { e.status = 'Текст не найден ни в одной базе. Можно вставить свой.'; refreshLyrics(now); return; }
      e.results = list; e.idx = 0;
      var r = list[0];
      setLy(now, r.synced || r.plain, r.artist + ' — ' + r.track + ' (' + r.provider + ')', !!r.synced || !!query);
    }).catch(function () {
      var delays = [4, 12, 30];
      if (attempt < delays.length) {
        e.status = 'Нет связи с сервером текстов. Повторю через ' + delays[attempt] + ' с…';
        refreshLyrics(now);
        setTimeout(function () { if (currentKey() === now.key && !e.ly) searchLyrics(now, query, attempt + 1); }, delays[attempt] * 1000);
      } else { e.status = 'Нет связи с сервером текстов. Проверь интернет.'; refreshLyrics(now); }
    });
    refreshLyrics(now);
  }
  function refreshLyrics(now) { if (currentKey() === now.key) buildLyrics(); }
  function currentKey() { var n = Player.now(); return n ? n.key : null; }

  var lyrState = { key: null, idx: -2, sung: -1 };
  function buildLyrics() {
    var box = $('lyr'), none = $('nolyr');
    if (!box) return;
    var now = Player.now(), e = lyrEntry(now);
    lyrState = { key: now ? now.key : null, idx: -2, sung: -1 };
    if (!e || !e.ly) {
      box.innerHTML = '';
      none.classList.remove('hide');
      none.innerHTML = '<div>' + esc(e ? e.status : '') + '</div>' +
        '<button class="btn small" data-a="lyricsSheet">' + icon('search') + 'Найти текст</button>';
      return;
    }
    none.classList.add('hide');
    box.innerHTML = e.ly.lines.map(function (l) { return '<div class="l" data-i="' + l.id + '">' + esc(l.text || '♪ ♪ ♪') + '</div>'; }).join('') +
      (e.ly.synced ? '' : '<div class="l" style="font-size:11px;opacity:.5">текст без тайминга, строки идут примерно</div>');
    tickLyrics(true);
  }
  function tickLyrics(force) {
    var box = $('lyr');
    if (!box || !box.children.length) return;
    var now = Player.now(), e = now && S.lyr[now.key];
    if (!e || !e.ly) return;
    var fr = Lyrics.frame(e.ly, Player.time() + (e.offset || 0));
    if (!fr) return;
    var idx = Math.max(0, fr.index), sung = Store.settings.karaoke === 'line' ? 1e9 : fr.sung;
    if (idx !== lyrState.idx || force) {
      var old = box.querySelector('.l.cur');
      if (old) { old.classList.remove('cur'); old.textContent = old.getAttribute('data-t') || old.textContent; }
      var cur = box.children[idx];
      if (cur) {
        cur.setAttribute('data-t', cur.textContent);
        cur.classList.add('cur');
        var y = cur.offsetTop + cur.offsetHeight / 2;
        box.style.transform = 'translateY(' + (-y) + 'px)';
      }
      if (PERF[Store.settings.perf] && PERF[Store.settings.perf].blur) {
        Array.prototype.forEach.call(box.children, function (c, i) { c.style.filter = i === idx ? '' : 'blur(' + Math.min(2.4, Math.abs(i - idx) * 0.5) + 'px)'; });
      }
      lyrState.idx = idx; lyrState.sung = -1;
    }
    if (sung !== lyrState.sung && e.ly.synced && fr.index >= 0) {
      var c = box.children[idx];
      if (c) {
        var txt = Array.from(c.getAttribute('data-t') || '');
        var n = Math.min(txt.length, sung);
        c.innerHTML = '<span class="s">' + esc(txt.slice(0, n).join('')) + '</span><span class="u">' + esc(txt.slice(n).join('')) + '</span>';
      }
      lyrState.sung = sung;
    }
  }

  // ---------- мини-плеер и прогресс ----------
  function renderMini() {
    var now = Player.now(), el = $('mini'), desk = isDesk();
    var show = now && (S.tab !== 'np' || S.playlist || desk);
    el.className = show ? (desk ? 'desk' : '') : 'off';
    if (!now) { el.innerHTML = ''; return; }
    var playing = Player.isPlaying();
    el.innerHTML = '<div class="art" data-a="tab" data-x="np">' + (now.art ? '<img src="' + esc(now.art) + '">' : coverImg(now)) + '</div>' +
      '<div class="meta" data-a="tab" data-x="np"><div class="t ell">' + esc(now.title) + '</div><div class="a ell">' + esc(now.artist || (now.app || '')) + '</div></div>' +
      (desk ? '<div class="seek" id="miniseek" style="max-width:520px"><div class="track"><div class="fill"></div></div><div class="knob"></div></div>' : '') +
      (desk ? '<button class="icon-btn" data-a="prev">' + icon('prev') + '</button>' : '') +
      '<button class="icon-btn" data-a="toggle">' + icon(playing ? 'pause' : 'play') + '</button>' +
      '<button class="icon-btn" data-a="next">' + icon('next') + '</button>' +
      (desk ? '<button class="icon-btn' + (isFav(now) ? ' on' : '') + '" data-a="fav">' + icon(isFav(now) ? 'heartF' : 'heart') + '</button>' : '') +
      '<div class="bar"><i></i></div>';
    hydrateArt(el);
  }
  function tickProgress() {
    var t = Player.time(), d = Player.duration(), p = d > 0 ? Math.min(1, t / d) : 0;
    document.querySelectorAll('.seek').forEach(function (s) {
      if (s.dataset.drag) return;
      var f = s.querySelector('.fill'), k = s.querySelector('.knob');
      if (f) f.style.width = (p * 100) + '%';
      if (k) k.style.left = (p * 100) + '%';
    });
    var bar = document.querySelector('#mini .bar i');
    if (bar) bar.style.width = (p * 100) + '%';
    var tc = $('tcur'), td = $('tdur');
    if (tc) tc.textContent = U.time(t);
    if (td) td.textContent = U.time(d);
  }
  // Перемотка пальцем / мышью
  document.addEventListener('pointerdown', function (ev) {
    var s = ev.target.closest && ev.target.closest('.seek');
    if (!s) return;
    var d = Player.duration();
    if (!(d > 0)) return;
    s.dataset.drag = '1';
    function at(e) { var r = s.getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); }
    function move(e) { var p = at(e); s.querySelector('.fill').style.width = p * 100 + '%'; var k = s.querySelector('.knob'); if (k) k.style.left = p * 100 + '%'; s._p = p; }
    function up(e) { move(e); delete s.dataset.drag; Player.seek(s._p * d); window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); }
    move(ev);
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  });

  // ---------- «Музыка» ----------
  function libScreen() {
    var seg = '<div class="seg">' + [['device', NB.kind === 'android' ? 'На телефоне' : 'Файлы'], ['fav', 'Любимые'], ['lists', 'Плейлисты']].map(function (s) {
      return '<button class="' + (S.libSeg === s[0] ? 'on' : '') + '" data-a="libSeg" data-x="' + s[0] + '">' + s[1] + '</button>';
    }).join('') + '</div>';
    var body = '';
    if (S.libSeg === 'device') body = deviceList();
    else if (S.libSeg === 'fav') body = playlistBody(playlist(FAV), true);
    else body = listsBody();
    return '<div class="scroll"><div class="h1 mc-shadow">Музыка</div>' + seg + '<div style="height:14px"></div>' + body + '</div>';
  }
  function deviceList() {
    var head = '';
    if (NB.kind !== 'android') head = '<div class="pl-actions"><button class="btn primary" data-a="pickFiles">' + icon('plus') + 'Файлы</button>' +
      (NB.kind === 'windows' ? '<button class="btn" data-a="pickFolder">' + icon('folder') + 'Папка</button>' : '') + '</div>';
    if (!S.device.length) {
      if (NB.kind === 'android' && (!S.deviceLoaded || S.permDenied)) {
        var msg = !S.permDenied ? 'Покажу музыку, которая есть на телефоне.'
          : S.permForever ? 'Доступ к музыке выключен в настройках Android. Открой «Разрешения» → «Музыка и аудио» → «Разрешить».'
          : 'Без доступа к музыке программа не видит песни на телефоне.';
        return '<div class="empty">' + icon('music') + msg + '<br><br>' + (S.permForever
          ? '<button class="btn primary" data-a="appSettings">' + icon('gear') + 'Открыть настройки</button>'
          : '<button class="btn primary" data-a="scan">' + icon('folder') + (S.permDenied ? 'Разрешить доступ' : 'Найти музыку') + '</button>') + '</div>';
      }
      return head + '<div class="empty">' + icon('music') + (NB.kind === 'android' ? 'На телефоне не нашлось музыки.' : 'Добавь музыку кнопками сверху.') + '</div>';
    }
    var q = U.norm(S.search), list = S.device.filter(function (t) { return !q || U.norm(t.title + ' ' + t.artist).indexOf(q) >= 0; });
    var cur = Player.current();
    return head + '<input class="search" id="search" placeholder="Поиск по названию и исполнителю" value="' + esc(S.search) + '">' +
      '<div class="sub" style="margin:10px 4px">Треков: ' + list.length + '</div><div class="list">' +
      list.slice(0, 400).map(function (t) {
        var on = cur && cur.uri === t.uri && Player.now() && Player.now().kind === 'file';
        return '<div class="row' + (on ? ' on' : '') + '" data-a="playDevice" data-x="' + esc(t.uri) + '">' + artHTML(fileTrack(t)) +
          '<div class="meta"><div class="t ell">' + esc(t.title) + '</div><div class="a ell">' + esc(t.artist || 'Неизвестный исполнитель') + '</div></div>' +
          (isFavKey('file:' + t.uri) ? '<span style="color:var(--accent)">' + icon('heartF').replace('<svg', '<svg style="width:14px;height:14px"') + '</span>' : '') +
          '<span class="dur">' + U.time(t.duration) + '</span>' +
          '<button class="more" data-a="devMenu" data-x="' + esc(t.uri) + '">' + icon('more') + '</button></div>';
      }).join('') + '</div>';
  }
  function fileTrack(t) { return { title: t.title, artist: t.artist, album: t.album, duration: t.duration, uri: t.uri, source: { file: { path: t.uri } } }; }
  function listsBody() {
    var lists = Store.playlists.filter(function (p) { return p.id !== FAV; });
    return '<div class="pl-actions"><button class="btn primary" data-a="newPl">' + icon('plus') + 'Новый плейлист</button>' +
      '<button class="btn" data-a="importLib">' + icon('download') + 'Загрузить копию</button></div>' +
      (lists.length ? '<div class="cards">' + lists.map(function (p) {
        return '<button class="card" data-a="openPl" data-x="' + p.id + '">' + mosaic(p) + '<div class="cap"><div class="t ell">' + esc(p.name) + '</div><div class="a">Треков: ' + p.items.length + '</div></div></button>';
      }).join('') + '</div>' : '<div class="empty">' + icon('list') + 'Создай плейлист: в нём можно смешивать файлы и треки со всех площадок.</div>');
  }
  function mosaic(p) {
    var its = p.items.slice(0, 4);
    if (!its.length) return '<div class="sq"><div class="art" style="background:linear-gradient(135deg,var(--accent),var(--accent2))"><div class="ph">' + icon(p.id === FAV ? 'heartF' : 'list') + '</div></div></div>';
    if (its.length < 4) return '<div class="sq">' + artHTML(its[0]) + '</div>';
    return '<div class="sq"><div class="mosaic" style="border-radius:0">' + its.map(function (t) { return artHTML(t); }).join('') + '</div></div>';
  }

  // ---------- плейлист ----------
  function playlist(id) { return Store.playlists.filter(function (p) { return p.id === id; })[0] || null; }
  function playlistScreen(id) {
    var p = playlist(id);
    if (!p) { S.playlist = null; return libScreen(); }
    var sources = {};
    p.items.forEach(function (t) { sources[t.source && t.source.web ? (PLATFORMS[t.source.web.platform] || {}).name : 'файлы'] = 1; });
    return '<div class="scroll"><button class="btn small" data-a="closePl">' + icon('back') + 'Назад</button>' +
      '<div class="pl-head"><div class="mosaic' + (p.items.length < 4 ? ' one' : '') + '">' + (p.items.length ? p.items.slice(0, p.items.length < 4 ? 1 : 4).map(function (t) { return artHTML(t); }).join('')
        : '<div class="art" style="background:linear-gradient(135deg,var(--accent),var(--accent2))"><div class="ph">' + icon(p.id === FAV ? 'heartF' : 'list') + '</div></div>') + '</div>' +
      '<div style="min-width:0"><div class="h1 mc-shadow ell">' + esc(p.name) + '</div><div class="sub">Треков: ' + p.items.length + ' · ' + U.long(p.items.reduce(function (s, t) { return s + (t.duration || 0); }, 0)) +
      (p.items.length ? ' · ' + esc(Object.keys(sources).join(', ')) : '') + '</div></div></div>' +
      playlistBody(p, false) + '</div>';
  }
  function playlistBody(p, embedded) {
    if (!p) return '';
    var actions = '<div class="pl-actions"><button class="btn primary" data-a="playPl" data-x="' + p.id + '">' + icon('play') + 'Слушать</button>' +
      '<button class="btn" data-a="shufflePl" data-x="' + p.id + '">' + icon('shuffle') + 'Вперемешку</button>' +
      (p.id !== FAV && !embedded ? '<button class="btn" data-a="renamePl" data-x="' + p.id + '">' + icon('edit') + '</button><button class="btn" data-a="deletePl" data-x="' + p.id + '">' + icon('trash') + '</button>' : '') + '</div>';
    if (!p.items.length) {
      return actions.replace('pl-actions"', 'pl-actions" style="display:none"') + '<div class="empty">' + icon(p.id === FAV ? 'heart' : 'list') +
        (p.id === FAV ? 'Нажми ♥ у играющего трека — он появится здесь.' : 'Добавляй сюда треки кнопкой «+».') + '</div>';
    }
    return actions + '<div class="list">' + p.items.map(function (t, i) {
      var avail = available(t);
      return '<div class="row' + (avail ? '' : ' off') + '" data-a="playItem" data-x="' + p.id + '|' + i + '">' + artHTML(t) +
        '<div class="meta"><div class="t ell">' + esc(t.title) + '</div><div class="a ell">' + sourceLabel(t) + '<span class="ell">· ' + esc(t.artist || '') + '</span></div></div>' +
        '<span class="dur">' + U.time(t.duration) + '</span>' +
        '<button class="more" data-a="itemMenu" data-x="' + p.id + '|' + i + '">' + icon('more') + '</button></div>';
    }).join('') + '</div>';
  }
  // Файл из плейлиста есть на этом устройстве? (с Mac — ищем по названию и исполнителю)
  function localMatch(t) {
    var path = t.source && t.source.file && t.source.file.path;
    if (!path) return null;
    var byUri = S.device.filter(function (d) { return d.uri === path; })[0];
    if (byUri) return byUri;
    return S.device.filter(function (d) { return U.sameSong(d.title, d.artist, t.title, t.artist); })[0] || null;
  }
  function available(t) { return !!(t.source && t.source.web) || !!localMatch(t) || NB.kind === 'windows'; }

  // ---------- «Площадки» ----------
  function appsScreen() {
    var h = '<div class="scroll"><div class="h1 mc-shadow">Площадки</div>';
    if (NB.kind === 'android') {
      var access = NB.hasNotifAccess();
      h += '<div class="panel" style="margin-top:10px"><div class="h2">' + (access ? '✓ Программа видит музыку приложений' : 'Текст для музыки из приложений') + '</div>' +
        '<div class="sub" style="margin:8px 0 12px;color:var(--panel-dim)">' + (access
          ? 'Включай музыку в Spotify, Яндекс Музыке, VK или SoundCloud — здесь появятся текст, обложка и управление.'
          : 'Разреши доступ к уведомлениям — так программа узнает, что играет в Spotify, Яндекс Музыке, VK и SoundCloud, покажет текст и даст управлять музыкой.') + '</div>' +
        (access ? '' : '<button class="btn primary" data-a="notifAccess">' + icon('bell') + 'Разрешить доступ</button>') + '</div>';
      if (access) {
        h += '<div class="label">Сейчас в приложениях</div>';
        h += Player.extList.length ? '<div class="list">' + Player.extList.map(function (s) {
          var pl = PKG[s.pkg], ic = NB.appIcon(s.pkg);
          return '<div class="row' + (Player.ext && Player.ext.pkg === s.pkg && Player.useExt() ? ' on' : '') + '" data-a="useSession" data-x="' + esc(s.pkg) + '">' +
            '<div class="art">' + (ic ? '<img src="' + esc(ic) + '">' : '') + '</div><div class="meta"><div class="t ell">' + esc(s.title || s.app) + '</div><div class="a ell">' + esc((s.artist ? s.artist + ' · ' : '') + s.app) + '</div></div>' +
            '<button class="more" data-a="sessToggle" data-x="' + esc(s.pkg) + '">' + icon(s.playing ? 'pause' : 'play') + '</button></div>';
        }).join('') + '</div>' : '<div class="empty" style="padding:18px">Сейчас ничего не играет.</div>';
      }
    } else {
      h += '<div class="sub" style="margin:4px 4px 12px">Треки площадок из твоих плейлистов открываются на сайте. Полноценные аккаунты с текстом — в версии для Mac.</div>';
    }
    h += '<div class="label">Открыть</div><div class="list">' + Object.keys(PLATFORMS).map(function (id) {
      var p = PLATFORMS[id];
      return '<div class="row" data-a="openPlatform" data-x="' + id + '">' + '<div class="art" style="display:grid;place-items:center">' + badge(id, 46) + '</div>' +
        '<div class="meta"><div class="t">' + esc(p.name) + '</div><div class="a">' + (NB.kind === 'android' ? 'Открыть приложение' : 'Открыть сайт') + '</div></div>' + icon('open').replace('<svg', '<svg style="width:20px;height:20px;opacity:.7"') + '</div>';
    }).join('') + '</div></div>';
    return h;
  }

  // ---------- «Настройки» ----------
  function setScreen() {
    var s = Store.settings;
    var themes = '<div class="themes">' + THEMES.map(function (t) {
      return '<button class="theme-card' + (s.theme === t.id ? ' on' : '') + '" data-a="theme" data-x="' + t.id + '"><div class="pv" style="background:linear-gradient(135deg,' + t.pv.join(',') + ');font-family:' + t.font + ';color:' + t.sung + '">Аа</div>' +
        '<div class="nm"><b>' + t.name + '</b><div style="opacity:.75;font-size:11px;margin-top:3px">' + t.tag + '</div></div></button>';
    }).join('') + '</div>';
    var bgs = '<div class="bgs">' + BACKGROUNDS.map(function (b) {
      return '<button class="bg-card' + (s.background === b.id ? ' on' : '') + '" data-a="bg" data-x="' + b.id + '"><canvas data-pv="' + b.id + '" width="208" height="140"></canvas><div class="nm">' + b.name + '</div></button>';
    }).join('') + '</div>';
    var perf = '<div class="seg">' + Object.keys(PERF).map(function (k) {
      return '<button class="' + (s.perf === k ? 'on' : '') + '" data-a="perf" data-x="' + k + '">' + PERF[k].name + '</button>';
    }).join('') + '</div><div class="sub" style="margin:8px 4px 0">' + PERF[s.perf].tag + ' · ' + PERF[s.perf].fps + ' кадров</div>';
    function sw(key, title, desc) {
      return '<div class="set-row"><div><div>' + title + '</div>' + (desc ? '<div class="d">' + desc + '</div>' : '') + '</div><button class="switch' + (s[key] ? ' on' : '') + '" data-a="sw" data-x="' + key + '"></button></div>';
    }
    return '<div class="scroll"><div class="h1 mc-shadow">Настройки</div>' +
      '<div class="label">Тема</div>' + themes +
      '<div class="label">Живой фон</div>' + bgs +
      '<div class="label">Производительность</div>' + perf +
      '<div class="label">Текст песни</div><div class="panel">' +
      '<div class="set-row"><div>Размер текста</div><div style="width:50%"><input type="range" min="0.7" max="1.5" step="0.05" value="' + s.textScale + '" data-in="textScale"></div></div>' +
      '<div class="set-row"><div>Подсветка</div><div class="seg" style="width:60%">' + [['letters', 'По буквам'], ['line', 'Строка']].map(function (k) {
        return '<button class="' + (s.karaoke === k[0] ? 'on' : '') + '" data-a="karaoke" data-x="' + k[0] + '">' + k[1] + '</button>';
      }).join('') + '</div></div>' +
      sw('autoLyrics', 'Искать текст сам', 'lrclib и NetEase, с повтором при сбоях связи') +
      sw('trackToasts', 'Сообщать о новом треке', '') +
      (NB.kind === 'android' ? sw('keepScreenOn', 'Не гасить экран', 'Пока открыт экран «Играет»') : '') + '</div>' +
      '<div class="label">Звук</div><div class="panel"><div class="set-row"><div>Басы<div class="d">' + (s.bass ? (s.bass > 0 ? '+' : '') + s.bass + ' дБ' : 'выкл') + '</div></div><div style="width:55%"><input type="range" min="0" max="15" step="1" value="' + s.bass + '" data-in="bass"></div></div>' +
      '<div class="d" style="padding:4px 2px">Басы работают для твоих файлов. Музыку приложений играют сами приложения.</div></div>' +
      '<div class="label">Библиотека</div><div class="panel"><div class="sub" style="color:var(--panel-dim);margin-bottom:12px">Плейлисты и «Любимые» сохраняются сами, прошлая версия всегда остаётся резервной копией. Копию можно перенести на Mac или Windows.</div>' +
      '<div class="pl-actions" style="margin:0"><button class="btn" data-a="exportLib">' + icon('upload') + 'Сохранить копию</button><button class="btn" data-a="importLib">' + icon('download') + 'Загрузить копию</button></div></div>' +
      '<div class="label">О программе</div><div class="panel"><div class="sub" style="color:var(--panel-dim)">Музыка в офлайн ' + esc(NB.version()) + ' · ' + (NB.kind === 'android' ? 'Android' : NB.kind === 'windows' ? 'Windows' : 'браузер') + '</div></div></div>';
  }
  function drawPreviews() {
    document.querySelectorAll('canvas[data-pv]').forEach(function (c) {
      var id = c.getAttribute('data-pv');
      var sc = new BGScene(c, { input: function () { return { playing: true, progress: 0.3, palette: null }; } });
      sc.id = id; sc.dpr = 1;
      c.style.width = '100%'; c.style.height = '70px';
      try { sc.once(); } catch (e) {}
    });
  }

  // ---------- окна поверх ----------
  function sheet(html) {
    var m = $('modal');
    m.innerHTML = '<div class="dim" data-a="closeModal"></div><div class="sheet"><div class="grip"></div>' + html + '</div>';
    m.classList.add('on');
    hydrateArt(m);
  }
  function closeSheet() { var m = $('modal'); m.classList.remove('on'); m.innerHTML = ''; }
  function menuItem(ic, text, act, x) { return '<button class="menu-item" data-a="' + act + '"' + (x != null ? ' data-x="' + esc(x) + '"' : '') + '>' + icon(ic) + '<span>' + text + '</span></button>'; }

  function addToSheet(track) {
    S.pendingAdd = track;
    var lists = Store.playlists.filter(function (p) { return p.id !== FAV; });
    sheet('<div class="h2" style="margin-bottom:6px">Добавить в плейлист</div>' +
      menuItem('plus', 'Новый плейлист…', 'newPlAdd') +
      lists.map(function (p) { return menuItem('list', esc(p.name) + (hasKey(p, keyOfItem(track)) ? ' ✓' : ''), 'addToPl', p.id); }).join(''));
  }
  function lyricsSheet() {
    var now = Player.now();
    if (!now) return;
    var e = lyrEntry(now);
    sheet('<div class="h2">' + esc((now.artist ? now.artist + ' — ' : '') + now.title) + '</div>' +
      '<div class="sub" style="margin:6px 0 12px;color:var(--panel-dim)">' + esc(e.ly ? 'Текст: ' + e.source : e.status) + '</div>' +
      '<input class="search" id="lyrq" value="' + esc((now.artist ? now.artist + ' ' : '') + now.title) + '">' +
      '<div class="pl-actions" style="margin-top:10px"><button class="btn primary" data-a="lyrSearch">' + icon('search') + 'Найти</button>' +
      '<button class="btn" data-a="lyrNext">Другой вариант</button><button class="btn" data-a="lyrPaste">' + icon('clip') + 'Вставить свой</button></div>' +
      '<div class="set-row"><div>Сдвиг текста<div class="d" id="offv">' + (e.offset > 0 ? '+' : '') + (e.offset || 0).toFixed(1) + ' с</div></div><div style="width:55%"><input type="range" min="-5" max="5" step="0.1" value="' + (e.offset || 0) + '" data-in="offset"></div></div>');
  }

  // ---------- действия ----------
  var A = {
    tab: function (x) { closeSheet(); go(x); },
    toggle: function () { Player.toggle(); render(); },
    next: function () { Player.next(false); setTimeout(render, 250); },
    prev: function () { Player.prev(); setTimeout(render, 250); },
    shuffle: function () { Store.settings.shuffle = !Store.settings.shuffle; Store.saveSettings(); Player.setMode(); toast(Store.settings.shuffle ? 'Перемешивание включено' : 'Перемешивание выключено'); render(); },
    repeat: function () {
      var r = Store.settings.repeat; Store.settings.repeat = r === 'all' ? 'one' : r === 'one' ? 'none' : 'all';
      Store.saveSettings(); Player.setMode();
      toast({ all: 'Повтор: весь список', one: 'Повтор: один трек', none: 'Повтор выключен' }[Store.settings.repeat]); render();
    },
    focus: function () { S.focus = !S.focus; var np = $('np'); if (np) { np.classList.toggle('focus', S.focus); setTimeout(function () { tickLyrics(true); }, 50); } },
    fav: function () { toggleFav(); },
    addTo: function () { var n = Player.now(); if (n) addToSheet(savedFromNow(n)); },
    trackMenu: function () {
      var n = Player.now(); if (!n) return;
      sheet('<div class="h2" style="margin-bottom:6px">' + esc(n.title) + '</div>' +
        menuItem(isFav(n) ? 'heartF' : 'heart', isFav(n) ? 'Убрать из любимых' : 'В любимые', 'fav') +
        menuItem('plus', 'Добавить в плейлист', 'addTo') + menuItem('lyrics', 'Текст песни и поиск', 'lyricsSheet') +
        (n.kind === 'ext' ? menuItem('open', 'Открыть ' + esc(n.app || 'приложение'), 'openApp', n.pkg) : ''));
    },
    lyricsSheet: function () { lyricsSheet(); },
    closeModal: closeSheet,
    libSeg: function (x) { S.libSeg = x; render(); },
    libDevice: function () { S.tab = 'lib'; S.libSeg = 'device'; render(); if (NB.kind === 'android') A.scan(); },
    scan: function () { loadDevice(true); },
    pickFiles: function () {
      if (NB.kind === 'windows') { NB.scanMusic().then(addPicked); return; }
      if (NB.kind === 'web') $('filepick').click();
    },
    pickFolder: function () { NB.pickFolder().then(addPicked); },
    playDevice: function (uri) {
      var q = U.norm(S.search), list = S.device.filter(function (t) { return !q || U.norm(t.title + ' ' + t.artist).indexOf(q) >= 0; });
      var i = list.findIndex(function (t) { return t.uri === uri; });
      Player.setQueue(list, Math.max(0, i), true);
      saveLast();
      if (!isDesk()) go('np'); else render();
    },
    devMenu: function (uri) {
      var t = S.device.filter(function (d) { return d.uri === uri; })[0]; if (!t) return;
      var st = { id: U.uuid(), source: { file: { path: t.uri } }, title: t.title, artist: t.artist, album: t.album || '', duration: t.duration || 0, artURL: null, added: U.iso() };
      S.pendingAdd = st;
      sheet('<div class="h2" style="margin-bottom:6px">' + esc(t.title) + '</div>' +
        menuItem('heart', isFavKey('file:' + t.uri) ? 'Убрать из любимых' : 'В любимые', 'favPending') + menuItem('plus', 'Добавить в плейлист', 'addPending'));
    },
    favPending: function () { var t = S.pendingAdd; if (!t) return; toggleFavItem(t); closeSheet(); render(); },
    addPending: function () { if (S.pendingAdd) addToSheet(S.pendingAdd); },
    newPl: function () { newPlaylist(false); },
    newPlAdd: function () { newPlaylist(true); },
    addToPl: function (id) {
      var p = playlist(id), t = S.pendingAdd; if (!p || !t) return;
      if (hasKey(p, keyOfItem(t))) { toast('Уже есть в «' + p.name + '»'); closeSheet(); return; }
      p.items.push(Object.assign({}, t, { id: U.uuid(), added: U.iso() }));
      Store.saveLibrary(); closeSheet(); toast('Добавлено в «' + p.name + '»'); render();
    },
    openPl: function (id) { S.playlist = id; render(); },
    closePl: function () { S.playlist = null; render(); },
    playPl: function (id) { playPlaylist(id, 0, false); },
    shufflePl: function (id) { playPlaylist(id, 0, true); },
    playItem: function (x) { var a = x.split('|'); playPlaylist(a[0], +a[1], false); },
    itemMenu: function (x) {
      var a = x.split('|'), p = playlist(a[0]), t = p && p.items[+a[1]]; if (!t) return;
      S.pendingAdd = t; S.pendingItem = x;
      var link = t.source && t.source.web && (t.source.web.link || searchURL(t));
      sheet('<div class="h2" style="margin-bottom:6px">' + esc(t.title) + '</div>' +
        (link ? menuItem('open', 'Открыть в ' + esc((PLATFORMS[t.source.web.platform] || {}).name || 'приложении'), 'openLink', link) : '') +
        menuItem('plus', 'Добавить в другой плейлист', 'addPending') +
        menuItem('back', 'Выше', 'moveItem', x + '|-1') + menuItem('back', 'Ниже', 'moveItem', x + '|1').replace('<svg', '<svg style="transform:rotate(180deg)"') +
        menuItem('trash', p.id === FAV ? 'Убрать из любимых' : 'Убрать из плейлиста', 'removeItem', x));
    },
    moveItem: function (x) {
      var a = x.split('|'), p = playlist(a[0]), i = +a[1], d = +a[2], j = Math.max(0, Math.min(p.items.length - 1, i + d));
      if (i !== j) { var it = p.items.splice(i, 1)[0]; p.items.splice(j, 0, it); Store.saveLibrary(); }
      closeSheet(); render();
    },
    removeItem: function (x) { var a = x.split('|'), p = playlist(a[0]); p.items.splice(+a[1], 1); Store.saveLibrary(); closeSheet(); render(); },
    renamePl: function (id) { var p = playlist(id); var n = prompt('Название плейлиста', p.name); if (n && n.trim()) { p.name = n.trim(); Store.saveLibrary(); render(); } },
    deletePl: function (id) { var p = playlist(id); if (confirm('Удалить плейлист «' + p.name + '»? Сами треки не удалятся.')) { Store.playlists = Store.playlists.filter(function (q) { return q.id !== id; }); S.playlist = null; Store.saveLibrary(); render(); } },
    openLink: function (url) { closeSheet(); NB.openLink(url); },
    openApp: function (pkg) { closeSheet(); if (NB.launchApp(pkg)) return; var pl = PKG[pkg]; if (pl) NB.openLink(PLATFORMS[pl].home); },
    openPlatform: function (id) { if (NB.kind === 'android' && NB.launchApp(PLATFORMS[id].pkg)) return; NB.openLink(PLATFORMS[id].home); },
    appSettings: function () { NB.openAppSettings(); },
    notifAccess: function () { NB.openNotifAccess(); },
    useSession: function (pkg) { Player.lastLocal = 0; if (Player.ext && Player.ext.pkg !== pkg) Player.ext = null; go('np'); },
    sessToggle: function (pkg) { var s = Player.extList.filter(function (q) { return q.pkg === pkg; })[0]; if (s) NB.sessionControl(pkg, s.playing ? 'pause' : 'play'); setTimeout(function () { Player.poll(); render(); }, 400); },
    theme: function (id) {
      var t = THEMES.filter(function (q) { return q.id === id; })[0];
      Store.settings.theme = id; Store.settings.background = t.bg; Store.saveSettings(); applyLook(); render();
    },
    bg: function (id) { Store.settings.background = id; Store.saveSettings(); applyLook(); render(); },
    perf: function (k) { Store.settings.perf = k; Store.saveSettings(); applyLook(); render(); },
    karaoke: function (k) { Store.settings.karaoke = k; Store.saveSettings(); render(); },
    sw: function (k) { Store.settings[k] = !Store.settings[k]; Store.saveSettings(); applyLook(); render(); },
    exportLib: function () {
      NB.exportText('Музыка в офлайн — библиотека.json', Store.libraryText()).then(function (r) { if (r && r.ok !== false) toast('Копия библиотеки сохранена'); });
    },
    importLib: function () {
      NB.importText().then(function (r) {
        var text = r && (r.text || (typeof r === 'string' ? r : null));
        if (!text) return;
        var list = Store.parseLibrary(text);
        if (!list) { toast('В этом файле нет библиотеки'); return; }
        var np = 0, nt = 0;
        list.forEach(function (p) {
          var mine = Store.playlists.filter(function (q) { return q.id === p.id || (q.id !== FAV && p.id !== FAV && q.name === p.name); })[0];
          if (mine) p.items.forEach(function (it) { if (!hasKey(mine, keyOfItem(it))) { mine.items.push(it); nt++; } });
          else { Store.playlists.push(p); np++; nt += p.items.length; }
        });
        Store.saveLibrary(); toast('Добавлено: плейлистов ' + np + ', треков ' + nt); render();
      });
    },
    lyrSearch: function () {
      var now = Player.now(), q = ($('lyrq') || {}).value; if (!now || !q) return;
      closeSheet(); S.lyr[now.key] = { ly: null, status: 'Ищу текст…', offset: 0, results: [], idx: 0 }; searchLyrics(now, q, 0);
    },
    lyrNext: function () {
      var now = Player.now(), e = now && S.lyr[now.key];
      if (!e || e.results.length < 2) { toast('Других вариантов нет'); return; }
      e.idx = (e.idx + 1) % e.results.length;
      var r = e.results[e.idx];
      setLy(now, r.synced || r.plain, r.artist + ' — ' + r.track + ' (' + r.provider + ', вариант ' + (e.idx + 1) + ' из ' + e.results.length + ')', true);
      closeSheet(); toast('Вариант ' + (e.idx + 1) + ' из ' + e.results.length);
    },
    lyrPaste: function () {
      sheet('<div class="h2">Свой текст песни</div><div class="sub" style="margin:6px 0 10px;color:var(--panel-dim)">Вставь текст. Со временем строк вида [01:23.45] он пойдёт точно под музыку.</div>' +
        '<textarea id="pastebox" placeholder="Текст песни"></textarea><div class="pl-actions" style="margin-top:10px"><button class="btn primary" data-a="pasteSave">' + icon('check') + 'Сохранить</button></div>');
    },
    pasteSave: function () {
      var now = Player.now(), t = ($('pastebox') || {}).value;
      if (!now || !t || !setLy(now, t, 'вставлен вручную', true)) { toast('Здесь нет текста'); return; }
      closeSheet(); toast('Текст сохранён');
    },
    resume: function () {
      var last = Store.settings.last; if (!last) return;
      Player.setQueue(last.queue, last.index || 0, true, last.pos > 2 ? last.pos : 0);
      go('np');
    }
  };

  // Клик по элементу с data-a
  document.addEventListener('click', function (ev) {
    var el = ev.target.closest ? ev.target.closest('[data-a]') : null;
    if (!el) return;
    var a = el.getAttribute('data-a'), x = el.getAttribute('data-x');
    if (el.classList.contains('more') || a === 'sessToggle') ev.stopPropagation();
    if (A[a]) { A[a](x); }
  }, true);
  document.addEventListener('input', function (ev) {
    var k = ev.target.getAttribute && ev.target.getAttribute('data-in');
    if (ev.target.id === 'search') { S.search = ev.target.value; var pos = ev.target.selectionStart; render(); var s = $('search'); if (s) { s.focus(); s.setSelectionRange(pos, pos); } return; }
    if (!k) return;
    var v = +ev.target.value;
    if (k === 'offset') {
      var now = Player.now(); if (!now) return;
      var e = lyrEntry(now); e.offset = v; Cache.set('off:' + now.key, Math.abs(v) < 0.05 ? null : String(v));
      var ov = $('offv'); if (ov) ov.textContent = (v > 0 ? '+' : '') + v.toFixed(1) + ' с';
      return;
    }
    Store.settings[k] = v; Store.saveSettings();
    if (k === 'bass') Player.setBass(v);
    if (k === 'textScale') { applyLook(); tickLyrics(true); }
  });

  // ---------- любимые и плейлисты ----------
  function keyOfItem(t) { return Art.keyOf(t); }
  function hasKey(p, k) { return p.items.some(function (it) { return keyOfItem(it) === k; }); }
  function isFavKey(k) { var f = playlist(FAV); return !!f && hasKey(f, k); }
  function isFav(now) { return now ? isFavKey(now.kind === 'file' ? 'file:' + now.uri : now.key) : false; }
  function savedFromNow(n) {
    var src = n.kind === 'file' ? { file: { path: n.uri } } : { web: { platform: n.platform || 'other', link: null } };
    return { id: U.uuid(), source: src, title: n.title, artist: n.artist, album: n.album || '', duration: n.duration || 0,
             artURL: n.art && n.art.indexOf('http') === 0 ? n.art : (Cache.get('art:' + n.key) || null), added: U.iso() };
  }
  function toggleFavItem(t) {
    var f = playlist(FAV), k = keyOfItem(t);
    if (hasKey(f, k)) { f.items = f.items.filter(function (it) { return keyOfItem(it) !== k; }); toast('Убрано из любимых'); }
    else { f.items.unshift(t); toast('♥ Добавлено в любимые'); }
    Store.saveLibrary();
  }
  function toggleFav() { var n = Player.now(); if (!n) return; toggleFavItem(savedFromNow(n)); closeSheet(); render(); }
  function newPlaylist(addPending) {
    var n = prompt('Название плейлиста', 'Плейлист ' + Store.playlists.length);
    if (!n || !n.trim()) return;
    var p = { id: U.uuid(), name: n.trim(), created: U.iso(), items: [] };
    if (addPending && S.pendingAdd) p.items.push(Object.assign({}, S.pendingAdd, { id: U.uuid() }));
    Store.playlists.push(p); Store.saveLibrary(); closeSheet();
    toast(addPending ? 'Создан плейлист и трек добавлен' : 'Плейлист создан');
    if (!addPending) { S.playlist = p.id; }
    render();
  }
  function searchURL(t) {
    var q = encodeURIComponent([t.artist, t.title].filter(Boolean).join(' ')), pl = t.source.web.platform;
    return { spotify: 'https://open.spotify.com/search/' + q, soundcloud: 'https://soundcloud.com/search?q=' + q,
             yandex: 'https://music.yandex.ru/search?text=' + q, vk: 'https://vk.ru/audio?q=' + q }[pl] || null;
  }
  // Слушать плейлист: свои файлы — по очереди в плеере; трек площадки — открыть в её приложении
  function playPlaylist(id, start, shuffle) {
    var p = playlist(id); if (!p || !p.items.length) return;
    var t = p.items[start];
    if (t && t.source && t.source.web && !shuffle) {
      var link = t.source.web.link || searchURL(t);
      if (link) { NB.openLink(link); toast('Открываю в ' + ((PLATFORMS[t.source.web.platform] || {}).name || 'приложении')); }
      return;
    }
    var local = [];
    p.items.forEach(function (it, i) {
      var m = localMatch(it) || (NB.kind === 'windows' && it.source.file ? { uri: it.source.file.path, title: it.title, artist: it.artist, duration: it.duration } : null);
      if (m) local.push({ i: i, t: m });
    });
    if (!local.length) { toast('В этом плейлисте нет файлов с этого устройства — треки площадок открываются в их приложениях'); return; }
    if (shuffle) for (var k = local.length - 1; k > 0; k--) { var j = Math.random() * (k + 1) | 0, tmp = local[k]; local[k] = local[j]; local[j] = tmp; }
    var from = Math.max(0, local.findIndex(function (x) { return x.i === start; }));
    Player.setQueue(local.map(function (x) { return x.t; }), shuffle ? 0 : from, true);
    saveLast();
    if (!isDesk()) go('np'); else render();
  }

  // ---------- музыка на устройстве ----------
  function loadDevice(ask) {
    if (NB.kind !== 'android') return;
    S.askedMusic = true;
    NB.scanMusic(ask).then(function (r) {
      var denied = !!(r && r.denied);
      if (ask) { Store.settings.askedPerm = true; Store.saveSettings(); }
      S.deviceLoaded = !denied || !!Store.settings.askedPerm;     // ещё не спрашивали — просто кнопка «Найти музыку»
      S.permDenied = denied && !!Store.settings.askedPerm;
      S.permForever = S.permDenied && !!(r && r.forever);
      if (r && r.ok) S.device = r.tracks || [];
      else if (ask && S.permDenied && !S.permForever) toast('Нужно разрешение на доступ к музыке');
      render();
    });
  }
  function addPicked(r) {
    if (!r || !r.tracks) return;
    var have = {};
    S.device.forEach(function (t) { have[t.uri] = 1; });
    r.tracks.forEach(function (t) { if (!have[t.uri]) S.device.push(t); });
    NB.writeFile('files.json', JSON.stringify(S.device));
    toast('Добавлено треков: ' + r.tracks.length);
    render();
  }

  // ---------- продолжить с того же места ----------
  function saveLast() {
    var q = Player.queue;
    if (!q.length || Player.index < 0) return;
    var from = Math.max(0, Math.min(Player.index - 250, q.length - 500));
    Store.settings.last = { queue: q.slice(from, from + 500), index: Player.index - from, pos: Math.round(Player.time() * 10) / 10, at: U.iso() };
    Store.saveSettings();
  }
  // Сохранить всё прямо сейчас (приложение сворачивают или закрывают)
  window.__flush = function () {
    try { saveLast(); } catch (e) {}
    Store.saveSettings.flush();
    Store.saveLibrary.flush();
    return true;
  };
  // При запуске: последний трек стоит на паузе на том же месте — нажал «играть» и слушаешь дальше
  function restoreLast() {
    if (Player.current()) return;
    if (NB.kind === 'android') {
      var st = NB.playbackState();
      if (st && st.length) { Player.applyState(st); return; }   // служба сама помнит очередь и место
    }
    var last = Store.settings.last;
    if (!last || !last.queue || !last.queue.length) return;
    if (last.queue.some(function (t) { return /^blob:/.test(t.uri); })) return;   // файлы из браузера не переживают перезапуск
    Player.setQueue(last.queue, last.index || 0, false, last.pos || 0);
  }

  // ---------- таймеры ----------
  var lastKey = null;
  Player.onChange(function () {
    var n = Player.now(), k = n ? n.key : null;
    if (k !== lastKey) {
      lastKey = k;
      if (n && Store.settings.trackToasts && lastKey) toast('Сейчас играет: ' + (n.artist ? n.artist + ' — ' : '') + n.title);
      if (n && n.art && n.art.indexOf('data:') === 0) Art.palette(n.art).then(function (p) { S.palette = p; });
      else if (n) Art.resolve(n).then(function (u) { if (u) Art.palette(u).then(function (p) { S.palette = p; }); });
      saveLast();
    }
    if (S.tab === 'np' && !S.playlist) render(); else renderMini();
  });
  setInterval(function () {
    if (document.hidden) return;
    tickProgress();
    if (S.tab === 'np' && !S.playlist) tickLyrics(false);
  }, 70);
  setInterval(function () { if (!document.hidden) Player.poll(); }, 500);
  setInterval(function () { if (Player.isPlaying()) saveLast(); }, 10000);
  var wasPlaying = false;
  Player.onChange(function () {
    var p = Player.playing;
    if (wasPlaying && !p) saveLast();          // поставили на паузу — место запомнено
    wasPlaying = p;
  });
  document.addEventListener('visibilitychange', function () {
    if (!S.scene) return;
    if (document.hidden) { S.scene.stop(); window.__flush(); }
    else {
      S.scene.start(); Player.poll(); render();
      if (NB.kind === 'android' && S.permDenied) loadDevice(false);   // вернулись из настроек с разрешением
    }
  });
  window.addEventListener('pagehide', function () { window.__flush(); });
  window.addEventListener('resize', U.debounce(function () { render(); }, 150));
  $('filepick').addEventListener('change', function (ev) {
    var files = Array.prototype.slice.call(ev.target.files || []);
    addPicked({ tracks: files.map(function (f) { return { uri: URL.createObjectURL(f), title: f.name.replace(/\.[^.]+$/, ''), artist: '', duration: 0 }; }) });
  });

  // Кнопка «назад» на Android
  window.__back = function () {
    if ($('modal').classList.contains('on')) { closeSheet(); return true; }
    if (S.playlist) { S.playlist = null; render(); return true; }
    if (S.focus) { A.focus(); return true; }
    if (S.tab !== 'np') { go('np'); return true; }
    return false;
  };
  window.__insets = function (top, bottom) {
    document.documentElement.style.setProperty('--st', top + 'px');
    document.documentElement.style.setProperty('--sb', bottom + 'px');
  };

  // Логотип приложения (рисуем сами, как иконку на Mac)
  var logoURL = null;
  function LOGO() {
    if (logoURL) return logoURL;
    var c = document.createElement('canvas'); c.width = c.height = 192;
    var x = c.getContext('2d'), g = x.createLinearGradient(0, 0, 192, 192);
    g.addColorStop(0, '#5b2bf0'); g.addColorStop(0.55, '#e0318f'); g.addColorStop(1, '#ffa64d');
    x.fillStyle = g; x.beginPath(); x.roundRect ? x.roundRect(0, 0, 192, 192, 42) : x.rect(0, 0, 192, 192); x.fill();
    x.fillStyle = '#121216'; x.beginPath(); x.arc(86, 104, 58, 0, 7); x.fill();
    x.strokeStyle = 'rgba(255,255,255,0.07)'; for (var r = 54; r > 24; r -= 5) { x.beginPath(); x.arc(86, 104, r, 0, 7); x.stroke(); }
    var lg = x.createLinearGradient(66, 84, 106, 124); lg.addColorStop(0, '#ffd36b'); lg.addColorStop(1, '#ff4f9a');
    x.fillStyle = lg; x.beginPath(); x.arc(86, 104, 20, 0, 7); x.fill();
    x.fillStyle = '#fff';
    x.beginPath(); x.ellipse(104, 132, 14, 10, -0.35, 0, 7); x.fill(); x.beginPath(); x.ellipse(146, 122, 14, 10, -0.35, 0, 7); x.fill();
    x.fillRect(113, 62, 6, 70); x.fillRect(155, 52, 6, 70);
    x.beginPath(); x.moveTo(113, 62); x.lineTo(161, 52); x.lineTo(161, 66); x.lineTo(113, 76); x.closePath(); x.fill();
    logoURL = c.toDataURL('image/png');
    return logoURL;
  }

  // ---------- запуск ----------
  function start() {
    Store.load().then(function () {
      var ins = NB.insets();
      if (ins) window.__insets(ins.top, ins.bottom);
      S.scene = new BGScene($('bg'), {
        input: function () {
          var n = Player.now();
          return { playing: Player.isPlaying(), spectrum: Player.spectrum(), binHz: Player.binHz(), particles: PERF[Store.settings.perf].particles && Store.settings.particles,
                   progress: n && Player.duration() > 0 ? Player.time() / Player.duration() : null, palette: S.palette, level: 0.5 };
        }
      });
      applyLook();
      S.scene.start();
      S.tab = Store.settings.lastTab || 'np';
      if (NB.kind === 'windows') NB.readFile('files.json').then(function (t) { try { S.device = JSON.parse(t || '[]'); } catch (e) {} render(); });
      if (NB.kind === 'android') loadDevice(false);
      Player.setBass(Store.settings.bass);
      Player.setMode();
      restoreLast();
      render();
      NB.ready();
    });
  }
  window.UI = { render: render, S: S, A: A };
  start();
})();
