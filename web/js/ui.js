/* Экраны и управление: «Сейчас играет», «Музыка», плейлисты, «Площадки», «Настройки». */
(function () {
  'use strict';

  var S = {
    tab: 'np', libSeg: 'device', playlist: null, device: [], search: '', focus: false,
    lyr: {}, npKey: null, artTracks: {}, scene: null, deviceLoaded: false, askedMusic: false,
    scrollMem: {}, lastKey: null, lowBattery: false, auth: 'login', form: {}, scanning: false
  };
  var $ = function (id) { return document.getElementById(id); };
  // Широкий экран с боковой панелью (как в app.css) и телефон, повёрнутый боком
  function isDesk() { return window.matchMedia('(min-width: 900px) and (min-height: 541px)').matches; }
  function isLand() { return window.matchMedia('(orientation: landscape) and (max-height: 540px)').matches; }
  var esc = U.esc;
  var FAV = Store.favID;

  // ---------- оформление и производительность ----------
  function applyLook() {
    var s = Store.settings, low = S.lowBattery && s.batterySaver, b = document.body;
    b.dataset.theme = s.theme;
    b.classList.toggle('eco', low || perfMode() === 'eco');
    b.classList.toggle('noblur', !s.lyricBlur || low);
    b.classList.toggle('fxblur', !!s.panelBlur && !low);
    b.classList.toggle('novinyl', !s.vinylSpin || low);
    b.classList.toggle('round', !!s.roundPanel);
    b.classList.toggle('glass', !!s.glass);
    b.classList.toggle('light', s.theme === 'kitty');
    document.documentElement.style.setProperty('--scale', s.textScale);
    if (S.scene) {
      var sc = S.scene;
      sc.id = s.background; sc.fps = low ? 30 : (+s.fps || 0); sc.quality = low ? 0.5 : (+s.bgQuality || 1);
      sc.still = !s.bgAnim; sc.idleFps = s.idleSlow ? 30 : 0; sc.redraw();
    }
    var f = $('fps'); if (f) f.className = s.showFps ? '' : 'off';
    NB.systemBars(s.theme === 'kitty');
    NB.keepScreenOn(!!s.keepScreenOn);
  }
  // Экономия при низком заряде (где браузер это умеет)
  function watchBattery() {
    if (!navigator.getBattery) return;
    navigator.getBattery().then(function (bt) {
      function upd() { var low = !bt.charging && bt.level < 0.2; if (low !== S.lowBattery) { S.lowBattery = low; applyLook(); } }
      bt.addEventListener('levelchange', upd); bt.addEventListener('chargingchange', upd); upd();
    }).catch(function () {});
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
    var st = size ? 'width:' + size + 'px;height:' + size + 'px;font-size:' + Math.round(size * 0.4) + 'px;' : '';
    if (!p) return '<span class="badge" style="' + st + 'background:#777">' + icon('globe') + '</span>';
    var ic = Art.platformIcon(platform);
    if (ic) return '<span class="badge" style="' + st + '"><img src="' + esc(ic) + '" alt=""></span>';
    return '<span class="badge b-' + platform + '" style="' + st + '">' + p.letter + '</span>';
  }
  function sourceLabel(t) {
    if (t.source && t.source.web) {
      var p = PLATFORMS[t.source.web.platform];
      return badge(t.source.web.platform, 16) + '<span class="ell">' + esc(p ? p.name : 'Площадка') + '</span>';
    }
    var path = (t.source && t.source.file && t.source.file.path) || t.uri || '';
    var ext = (/\.([a-z0-9]{2,5})$/i.exec(path) || [])[1];
    return '<span class="ic14">' + icon('music') + '</span><span>Файл' + (ext ? ' · ' + ext.toUpperCase() : '') + '</span>';
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
      return '<button class="tab' + (S.tab === t.id ? ' on' : '') + '" data-a="tab" data-x="' + t.id + '">' + icon(t.ic) + '<span>' + t.name + '</span>' + tabDot(t.id) + '</button>';
    }).join('');
    var logo = LOGO();
    $('side').innerHTML = '<div class="side-logo"><img src="' + logo + '" alt="">Музыка<br>в офлайн</div>' +
      TABS.map(function (t) {
        return '<button class="side-item' + (S.tab === t.id && !S.playlist && !Sites.open ? ' on' : '') + '" data-a="tab" data-x="' + t.id + '">' + icon(t.ic) + '<span class="ell">' + t.name + '</span>' + tabDot(t.id) + '</button>';
      }).join('') +
      (Sites.tabs.length ? '<div class="label side-label">Открытые площадки</div>' + Sites.tabs.map(function (st) {
        var on = Sites.open && Sites.active === st.id, pl = st.st && st.st.playing;
        return '<button class="side-item' + (on ? ' on' : '') + '" data-a="brTab" data-x="' + st.id + '">' + badge(st.platform, 18) +
          '<span class="ell">' + esc(tabTitle(st)) + '</span>' + (pl ? '<i class="eq"><b></b><b></b><b></b></i>' : '') + '</button>';
      }).join('') : '') +
      '<div class="label side-label">Плейлисты</div>' +
      Store.playlists.map(function (p) {
        return '<button class="side-item' + (S.playlist === p.id && !Sites.open ? ' on' : '') + '" data-a="openPl" data-x="' + p.id + '">' + icon(p.id === FAV ? 'heart' : 'list') + '<span class="ell">' + esc(p.name) + '</span></button>';
      }).join('') +
      '<button class="side-item" data-a="newPl">' + icon('plus') + '<span class="ell">Новый плейлист</span></button>';
  }
  function tabDot(id) {
    if (id !== 'set') return '';
    return Updates.status === 'available' ? '<i class="dot upd"></i>' : anyNew() ? '<i class="dot"></i>' : '';
  }
  function go(tab) {
    Sites.hide();
    S.tab = tab; S.playlist = null; S.focus = false;
    Store.settings.lastTab = tab; Store.saveSettings();
    render();
  }

  // ---------- главный рендер (место прокрутки сохраняется) ----------
  function scrollKey() {
    if (S.playlist) return 'pl:' + S.playlist;
    if (S.tab === 'lib') return 'lib:' + S.libSeg;
    if (S.tab === 'set') return 'set:' + Store.settings.setTab;
    return S.tab;
  }
  function render() {
    var el = $('screen');
    var old = el.querySelector('.scroll');
    if (old && S.lastKey) S.scrollMem[S.lastKey] = old.scrollTop;
    renderTabs();
    if (S.playlist) el.innerHTML = playlistScreen(S.playlist);
    else if (S.tab === 'np') el.innerHTML = npScreen();
    else if (S.tab === 'lib') el.innerHTML = libScreen();
    else if (S.tab === 'apps') el.innerHTML = appsScreen();
    else el.innerHTML = setScreen();
    var k = scrollKey(), sc = el.querySelector('.scroll');
    if (sc && S.scrollMem[k]) sc.scrollTop = S.scrollMem[k];
    S.lastKey = k;
    renderMini();
    hydrateArt(el);
    if (S.tab === 'np' && !S.playlist) { layoutNP(); buildLyrics(); }
    if (S.tab === 'set' && !S.playlist) drawPreviews();
    tickProgress();
  }
  // Лёгкое обновление без перерисовки экрана: кнопки, мини-плеер, прогресс
  function refresh() {
    var n = Player.now(), k = n ? n.key : null;
    if (S.tab === 'np' && !S.playlist && k !== S.npKey) { render(); return; }
    var np = $('np');
    if (np && n) {
      var pl = Player.isPlaying();
      np.classList.toggle('playing', pl);
      var pb = np.querySelector('.play-btn');
      if (pb && pb.getAttribute('data-pl') !== String(pl)) { pb.setAttribute('data-pl', pl); pb.innerHTML = icon(pl ? 'pause' : 'play'); }
      setOn(np, 'shuffle', Store.settings.shuffle);
      var rb = np.querySelector('[data-a="repeat"]');
      if (rb) { rb.classList.toggle('on', Store.settings.repeat !== 'none'); rb.innerHTML = icon(Store.settings.repeat === 'one' ? 'repeat1' : 'repeat'); }
      var liked = isFav(n), fb = np.querySelector('.np-actions [data-a="fav"]');
      if (fb && fb.classList.contains('on') !== liked) { fb.classList.toggle('on', liked); fb.innerHTML = icon(liked ? 'heartF' : 'heart'); }
      var ch = np.querySelector('.np-top .chip');
      if (ch) ch.classList.toggle('loading', !!n.loading);
    }
    renderMini();
    tickProgress();
  }
  function setOn(root, a, on) { var b = root.querySelector('[data-a="' + a + '"]'); if (b) b.classList.toggle('on', !!on); }

  // ---------- «Сейчас играет» ----------
  function npScreen() {
    var now = Player.now();
    S.npKey = now ? now.key : null;
    if (!now) return welcome();
    var playing = Player.isPlaying(), liked = isFav(now);
    var src = now.kind === 'ext' || now.kind === 'site'
      ? (now.platform ? badge(now.platform, 16) : '') + '<span class="ell">' + esc(now.app || 'Приложение') + '</span>'
      : sourceLabel(now);
    var sticker = '';
    var th = Store.settings.theme;
    if (th === 'dora') sticker = '<span class="sticker" style="top:-14px;right:-10px">✨</span><span class="sticker" style="bottom:-12px;left:-10px">💖</span>';
    if (th === 'kitty') sticker = '<span class="sticker" style="top:-18px;left:-14px;font-size:38px">🎀</span>';
    return '<div class="np' + (playing ? ' playing' : '') + (S.focus ? ' focus' : '') + '" id="np">' +
      '<div class="np-top"><span class="chip' + (now.loading ? ' loading' : '') + '">' + src + '<i class="spin"></i></span>' +
      '<div class="np-top-btns">' + (now.kind === 'site' ? '<button class="icon-btn" data-a="brTab" data-x="' + esc(now.tab) + '" title="Открыть страницу">' + icon('globe') + '</button>' : '') +
      '<button class="icon-btn" data-a="lyricsSheet" title="Текст песни">' + icon('lyrics') + '</button></div></div>' +
      '<div class="np-side"><div class="np-cover-wrap" data-a="focus"><div class="np-vinyl"></div>' +
      '<div class="np-cover art">' + coverImg(now) + '</div>' + sticker + '</div>' +
      '<div class="np-meta"><div class="np-title mc-shadow">' + esc(now.title) + '</div><div class="np-artist">' + esc(now.artist) + '</div></div></div>' +
      '<div class="np-lyrics" data-a="focus"><div class="lyr" id="lyr"></div><div class="np-nolyr hide" id="nolyr"></div></div>' +
      '<div class="np-prog"><div class="seek" id="npseek"><div class="track"><div class="fill"></div></div><div class="knob"></div></div>' +
      '<div class="times"><span id="tcur">0:00</span><span id="tdur">' + U.time(Player.duration()) + '</span></div></div>' +
      '<div class="np-ctrl">' +
      '<button class="icon-btn' + (Store.settings.shuffle ? ' on' : '') + '" data-a="shuffle">' + icon('shuffle') + '</button>' +
      '<div class="main"><button class="icon-btn" data-a="prev">' + icon('prev') + '</button>' +
      '<button class="play-btn" data-a="toggle" data-pl="' + playing + '">' + icon(playing ? 'pause' : 'play') + '</button>' +
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
  // Пластинка с обложкой на наклейке и именем исполнителя по кругу (когда у песни нет текста)
  function bigVinyl(now) {
    // по кругу помещается ~50 знаков: повторяем «исполнитель • название» целиком, лишнее не режем посреди слова
    var ring = [now.artist, now.title].filter(Boolean).join(' • ').toUpperCase() || 'МУЗЫКА В ОФЛАЙН', MAX = 50;
    if (ring.length > MAX - 3) ring = ring.slice(0, MAX - 4).replace(/\s+\S*$/, '') + '…';
    var txt = ring + ' • ';
    while (txt.length + ring.length + 3 <= MAX) txt += ring + ' • ';
    return '<div class="bigvinyl"><div class="disc">' +
      '<svg class="ring" viewBox="0 0 200 200"><defs><path id="vring" d="M100,100 m-66,0 a66,66 0 1,1 132,0 a66,66 0 1,1 -132,0"/></defs>' +
      '<text><textPath href="#vring" textLength="408" lengthAdjust="spacing">' + esc(txt) + '</textPath></text></svg>' +
      '<div class="lbl">' + coverImg(now) + '</div><div class="hole"></div></div><div class="shine"></div></div>';
  }
  function layoutNP() {
    var np = $('np');
    if (!np) return;
    var W = np.clientWidth, H = np.clientHeight, desk = isDesk();
    var cov = desk ? Math.min(420, Math.max(220, Math.min(W * 0.3, H * 0.52)))
      : isLand() ? Math.max(110, Math.min(H * 0.5, W * 0.3, 240))
      : Math.min(W - 80, Math.max(150, H * 0.3), 340);
    np.style.setProperty('--cov', Math.round(cov) + 'px');
    var ly = np.querySelector('.np-lyrics');
    if (ly && np.classList.contains('nolyr')) {
      var vs = Math.min(ly.clientWidth * 0.82, ly.clientHeight - (isLand() ? 70 : 128), 440);
      np.style.setProperty('--vs', Math.round(Math.max(110, vs) / 2) * 2 + 'px');
    }
  }
  function welcome() {
    var android = NB.kind === 'android';
    return '<div class="welcome"><img class="logo" src="' + LOGO() + '" alt="">' +
      '<div class="h1 mc-shadow">Музыка в офлайн</div><div class="sub">Твоя музыка, тексты песен и живые фоны</div>' +
      '<button class="btn primary block" data-a="' + (android ? 'libDevice' : 'pickFiles') + '">' + icon('folder') + (android ? 'Музыка на телефоне' : 'Открыть файлы') + '</button>' +
      (NB.kind === 'windows' ? '<button class="btn block" data-a="deepScan">' + icon('scan') + 'Найти всю музыку на компьютере</button>' : '') +
      '<button class="btn block" data-a="tab" data-x="apps">' + icon('apps') + 'Spotify, Яндекс, VK, SoundCloud</button>' +
      '<button class="btn block" data-a="setTab" data-x="look">' + icon('palette') + 'Темы и фоны</button>' +
      (resumeHTML() || '') + '</div>';
  }
  function resumeHTML() {
    var last = Store.settings.last;
    if (!last || !last.queue || !last.queue.length || Player.current()) return '';
    var t = last.queue[last.index] || last.queue[0];
    return '<button class="row resume" data-a="resume">' + artHTML(t) +
      '<div class="meta"><div class="a">Продолжить</div><div class="t ell">' + esc(t.title) + '</div></div><span class="ic22">' + icon('play') + '</span></button>';
  }

  // ---------- текст песни ----------
  function lyrEntry(now) {
    if (!now) return null;
    var e = S.lyr[now.key];
    if (!e) {
      e = S.lyr[now.key] = { ly: null, status: 'Ищу текст…', final: false, offset: +(Cache.get('off:' + now.key) || 0), results: [], idx: 0, source: '' };
      var cached = Cache.get('lyr:' + now.key);
      if (cached) setLy(now, cached, 'сохранённый текст');
      else if (!now.title) { e.status = 'Нет названия трека'; e.final = true; }
      else if (Store.settings.autoLyrics) searchLyrics(now, null, 0);
      else { e.status = 'Автопоиск текста выключен'; e.final = true; }
    }
    return e;
  }
  function setLy(now, text, source, save) {
    var e = S.lyr[now.key] || (S.lyr[now.key] = { offset: 0, results: [], idx: 0 });
    var p = Lyrics.parse(text);
    if (!p) return false;
    e.plain = p.synced ? null : p;
    e.ly = p.synced ? p : Lyrics.estimate(p, now.duration);
    e.source = source; e.status = ''; e.final = false;
    if (save) Cache.set('lyr:' + now.key, text);
    if (currentKey() === now.key) buildLyrics();
    return true;
  }
  function searchLyrics(now, query, attempt) {
    var e = S.lyr[now.key];
    e.status = 'Ищу текст…'; e.final = false;
    Lyrics.find(now.artist, now.title, now.duration, query).then(function (list) {
      if (!list.length) { e.status = 'Текст этой песни не нашёлся'; e.final = true; refreshLyrics(now); return; }
      e.results = list; e.idx = 0;
      var r = list[0];
      setLy(now, r.synced || r.plain, r.artist + ' — ' + r.track + ' (' + r.provider + ')', !!r.synced || !!query);
    }).catch(function () {
      var delays = [4, 12, 30];
      if (attempt < delays.length) {
        e.status = 'Нет связи с сервером текстов. Повторю через ' + delays[attempt] + ' с…';
        refreshLyrics(now);
        setTimeout(function () { if (currentKey() === now.key && !e.ly) searchLyrics(now, query, attempt + 1); }, delays[attempt] * 1000);
      } else { e.status = 'Нет связи с сервером текстов'; e.final = true; refreshLyrics(now); }
    });
    refreshLyrics(now);
  }
  function refreshLyrics(now) { if (currentKey() === now.key) buildLyrics(); }
  function currentKey() { var n = Player.now(); return n ? n.key : null; }

  var lyrState = { key: null, idx: -2, sung: -1 };
  function buildLyrics() {
    var box = $('lyr'), none = $('nolyr'), np = $('np');
    if (!box || !np) return;
    var now = Player.now(), e = lyrEntry(now);
    lyrState = { key: now ? now.key : null, idx: -2, sung: -1 };
    if (!e || !e.ly) {
      box.innerHTML = '';
      var fin = !!(e && e.final);
      np.classList.toggle('nolyr', fin);
      none.classList.remove('hide');
      none.innerHTML = fin
        ? bigVinyl(now) + '<div class="bv-meta"><div class="np-title mc-shadow ell">' + esc(now.title) + '</div><div class="np-artist ell">' + esc(now.artist) + '</div></div>' +
          '<div class="bv-status"><span>' + esc(e.status) + '</span><button class="btn small" data-a="lyricsSheet">' + icon('search') + 'Найти текст</button></div>'
        : '<div class="lyr-wait">' + esc(e ? e.status : '') + '</div>';
      hydrateArt(none);
      layoutNP();
      return;
    }
    np.classList.remove('nolyr');
    none.classList.add('hide');
    box.innerHTML = e.ly.lines.map(function (l) { return '<div class="l" data-i="' + l.id + '">' + esc(l.text || '♪ ♪ ♪') + '</div>'; }).join('') +
      (e.ly.synced ? '' : '<div class="l note">текст без тайминга, строки идут примерно</div>');
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
        // целые пиксели: строки не «дрожат» и не расплываются
        var y = Math.round(cur.offsetTop + cur.offsetHeight / 2);
        box.style.transform = 'translate3d(0,' + (-y) + 'px,0)';
      }
      if (Store.settings.lyricBlur && !document.body.classList.contains('noblur')) {
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
    var show = now && (S.tab !== 'np' || S.playlist || desk || Sites.open);
    el.className = show ? (desk ? 'desk' : '') : 'off';
    var had = document.body.classList.contains('withmini');
    document.body.classList.toggle('withmini', !!show);
    if (Sites.open && had !== !!show) Sites.sync();
    if (!now) { el.innerHTML = ''; el.removeAttribute('data-key'); return; }
    var playing = Player.isPlaying(), liked = isFav(now), sig = now.key + '|' + desk + '|' + document.body.dataset.theme;
    if (el.getAttribute('data-key') === sig) {
      var tb = el.querySelector('[data-a="toggle"]');
      if (tb && tb.getAttribute('data-pl') !== String(playing)) { tb.setAttribute('data-pl', playing); tb.innerHTML = icon(playing ? 'pause' : 'play'); }
      var fb = el.querySelector('[data-a="fav"]');
      if (fb && fb.classList.contains('on') !== liked) { fb.classList.toggle('on', liked); fb.innerHTML = icon(liked ? 'heartF' : 'heart'); }
      el.classList.toggle('loading', !!now.loading);
      return;
    }
    el.setAttribute('data-key', sig);
    el.classList.toggle('loading', !!now.loading);
    el.innerHTML = '<div class="art" data-a="tab" data-x="np">' + coverImg(now) + '</div>' +
      '<div class="meta" data-a="tab" data-x="np"><div class="t ell">' + esc(now.title) + '</div><div class="a ell">' +
      (now.platform ? badge(now.platform, 14) : '') + '<span class="ell">' + esc(now.artist || (now.app || '')) + '</span></div></div>' +
      (desk ? '<div class="seek" id="miniseek"><div class="track"><div class="fill"></div></div><div class="knob"></div></div>' : '') +
      (desk ? '<button class="icon-btn" data-a="prev">' + icon('prev') + '</button>' : '') +
      '<button class="icon-btn" data-a="toggle" data-pl="' + playing + '">' + icon(playing ? 'pause' : 'play') + '</button>' +
      '<button class="icon-btn" data-a="next">' + icon('next') + '</button>' +
      (desk ? '<button class="icon-btn' + (liked ? ' on' : '') + '" data-a="fav">' + icon(liked ? 'heartF' : 'heart') + '</button>' : '') +
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
    return '<div class="scroll"><div class="h1 mc-shadow">Музыка</div>' + seg + '<div class="gap14"></div>' + body + '</div>';
  }
  function scanButton() {
    if (NB.kind === 'web') return '';
    return '<button class="btn' + (S.scanning ? ' busy' : '') + '" data-a="deepScan"' + (S.scanning ? ' disabled' : '') + '>' + icon('scan') +
      (S.scanning ? 'Ищу музыку…' : NB.kind === 'android' ? 'Найти всю музыку' : 'Вся музыка компьютера') + newBadge('scan') + '</button>';
  }
  function deviceList() {
    var head = '<div class="pl-actions">' + (NB.kind !== 'android' ? '<button class="btn primary" data-a="pickFiles">' + icon('plus') + 'Файлы</button>' +
      (NB.kind === 'windows' ? '<button class="btn" data-a="pickFolder">' + icon('folder') + 'Папка</button>' : '') : '') +
      (NB.kind !== 'android' || (S.deviceLoaded && !S.permDenied) ? scanButton() : '') + '</div>';
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
    var cur = Player.current(), nowFile = Player.now() && Player.now().kind === 'file';
    return head + '<input class="search" id="search" placeholder="Поиск по названию и исполнителю" value="' + esc(S.search) + '">' +
      '<div class="sub count">Треков: ' + list.length + '</div><div class="list">' +
      list.slice(0, 400).map(function (t) {
        var on = cur && cur.uri === t.uri && nowFile;
        return '<div class="row' + (on ? ' on' : '') + '" data-a="playDevice" data-x="' + esc(t.uri) + '">' + artHTML(fileTrack(t)) +
          '<div class="meta"><div class="t ell">' + esc(t.title) + '</div><div class="a ell">' + esc(t.artist || 'Неизвестный исполнитель') + '</div></div>' +
          (isFavKey('file:' + t.uri) ? '<span class="favmark">' + icon('heartF') + '</span>' : '') +
          '<span class="dur">' + U.time(t.duration) + '</span>' +
          '<button class="more" data-a="devMenu" data-x="' + esc(t.uri) + '">' + icon('more') + '</button></div>';
      }).join('') + '</div>' + (list.length > 400 ? '<div class="sub count">Показаны первые 400 — уточни поиск</div>' : '');
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
    if (!its.length) return '<div class="sq"><div class="art grad"><div class="ph">' + icon(p.id === FAV ? 'heartF' : 'list') + '</div></div></div>';
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
        : '<div class="art grad"><div class="ph">' + icon(p.id === FAV ? 'heartF' : 'list') + '</div></div>') + '</div>' +
      '<div class="minw0"><div class="h1 mc-shadow ell">' + esc(p.name) + '</div><div class="sub">Треков: ' + p.items.length + ' · ' + U.long(p.items.reduce(function (s, t) { return s + (t.duration || 0); }, 0)) +
      (p.items.length ? ' · ' + esc(Object.keys(sources).join(', ')) : '') + '</div></div></div>' +
      playlistBody(p, false) + '</div>';
  }
  function playlistBody(p, embedded) {
    if (!p) return '';
    var actions = '<div class="pl-actions"><button class="btn primary" data-a="playPl" data-x="' + p.id + '">' + icon('play') + 'Слушать</button>' +
      '<button class="btn" data-a="shufflePl" data-x="' + p.id + '">' + icon('shuffle') + 'Вперемешку</button>' +
      (p.id !== FAV && !embedded ? '<button class="btn" data-a="renamePl" data-x="' + p.id + '">' + icon('edit') + '</button><button class="btn" data-a="deletePl" data-x="' + p.id + '">' + icon('trash') + '</button>' : '') + '</div>';
    if (!p.items.length) {
      return '<div class="empty">' + icon(p.id === FAV ? 'heart' : 'list') +
        (p.id === FAV ? 'Нажми ♥ у играющего трека — он появится здесь.' : 'Добавляй сюда треки кнопкой «+».') + '</div>';
    }
    var cur = Runner.active ? Runner.item() : null;
    return actions + '<div class="list">' + p.items.map(function (t, i) {
      var avail = available(t), on = cur && cur.id === t.id;
      return '<div class="row' + (avail ? '' : ' off') + (on ? ' on' : '') + '" data-a="playItem" data-x="' + p.id + '|' + i + '">' + artHTML(t) +
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
  function resolveFile(it) {
    return localMatch(it) || (NB.kind === 'windows' && it.source.file ? { uri: it.source.file.path, title: it.title, artist: it.artist, duration: it.duration } : null);
  }
  function available(t) { return !!(t.source && t.source.web) || !!localMatch(t) || NB.kind === 'windows'; }

  // ---------- «Площадки» ----------
  function tabTitle(t) {
    var p = PLATFORMS[t.platform];
    if (t.st && t.st.playing && t.st.title) return t.st.title;
    return p ? p.name : (t.title || hostOf(t.url) || 'Вкладка');
  }
  function hostOf(u) { var m = /^https?:\/\/([^\/?#]+)/i.exec(u || ''); return m ? m[1].replace(/^www\./, '') : ''; }
  function appsScreen() {
    var h = '<div class="scroll"><div class="h1 mc-shadow">Площадки</div>' +
      '<div class="sub lead">Войди один раз — вход запомнится. Музыка играет прямо в программе: с текстом песни, обложкой и «Любимыми». Устанавливать приложения и открывать браузер не нужно.</div>';
    if (!Profile.signedIn()) {
      h += '<button class="hint-card" data-a="setTab" data-x="profile">' + icon('cloud') + '<div><b>Профиль на всех устройствах' + newBadge('profile') + '</b>' +
        '<span>Зарегистрируйся — на телефоне и компьютере будет видно, какие сервисы уже подключены</span></div>' + icon('fwd') + '</button>';
    }
    h += '<div class="label">Сервисы' + newBadge('browser') + '</div><div class="svc-grid">' + Object.keys(PLATFORMS).map(function (id) {
      var p = PLATFORMS[id], st = Profile.status(id), t = Sites.tabFor(id), pl = t && t.st && t.st.playing && t.st.title;
      var status = st === 'here' ? '<span class="stat ok">' + icon('check') + 'Вход выполнен</span>'
        : st === 'other' ? '<span class="stat mid">Активирован на другом устройстве — войди здесь</span>'
        : '<span class="stat">Не подключён</span>';
      return '<div class="svc">' + '<div class="svc-top">' + badge(id, 44) + '<div class="meta"><div class="t">' + esc(p.name) + '</div>' + status + '</div>' +
        '<button class="more" data-a="svcMenu" data-x="' + id + '">' + icon('more') + '</button></div>' +
        (pl ? '<div class="svc-now">' + '<i class="eq"><b></b><b></b><b></b></i><span class="ell">' + esc(t.st.title + (t.st.artist ? ' — ' + t.st.artist : '')) + '</span></div>' : '') +
        '<div class="svc-btns"><button class="btn ' + (st === 'here' ? 'primary' : '') + ' small" data-a="openPlatform" data-x="' + id + '">' + icon('globe') + 'Открыть</button>' +
        (st !== 'here' ? '<button class="btn primary small" data-a="loginPlatform" data-x="' + id + '">' + icon('user') + 'Войти</button>' : '') + '</div></div>';
    }).join('') + '</div>';
    if (Sites.tabs.length) {
      h += '<div class="label">Открытые вкладки' + newBadge('tabs') + '</div><div class="list">' + Sites.tabs.map(function (t) {
        var pl = t.st && t.st.playing;
        return '<div class="row" data-a="brTab" data-x="' + t.id + '"><div class="art center">' + badge(t.platform, 40) + '</div>' +
          '<div class="meta"><div class="t ell">' + esc(tabTitle(t)) + '</div><div class="a ell">' + (pl ? 'играет · ' : '') + esc(hostOf(t.url)) + '</div></div>' +
          '<button class="more" data-a="brCloseTab" data-x="' + t.id + '" title="Закрыть вкладку">' + icon('close') + '</button></div>';
      }).join('') + '</div><div class="pl-actions top8"><button class="btn" data-a="brNewTab">' + icon('plus') + 'Новая вкладка</button>' +
        '<button class="btn" data-a="minimizeAll">' + icon('minimize') + 'Свернуть все окна площадок</button></div>';
    }
    if (NB.kind === 'android') {
      var access = NB.hasNotifAccess();
      h += '<div class="label">Музыка из других приложений · необязательно</div><div class="panel">';
      if (!access) {
        h += '<div class="sub dimp">Если слушаешь в самих приложениях Spotify, Яндекс Музыки, VK или SoundCloud, программа может показывать к ним текст и обложку. Для этого нужен доступ к уведомлениям — без него всё остальное работает.</div>' +
          '<button class="btn small" data-a="notifAccess">' + icon('bell') + 'Разрешить доступ</button>';
      } else {
        h += Player.extList.length ? '<div class="list">' + Player.extList.map(function (s) {
          var ic = NB.appIcon(s.pkg);
          return '<div class="row' + (Player.ext && Player.ext.pkg === s.pkg && Player.useExt() ? ' on' : '') + '" data-a="useSession" data-x="' + esc(s.pkg) + '">' +
            '<div class="art">' + (ic ? '<img src="' + esc(ic) + '">' : '') + '</div><div class="meta"><div class="t ell">' + esc(s.title || s.app) + '</div><div class="a ell">' + esc((s.artist ? s.artist + ' · ' : '') + s.app) + '</div></div>' +
            '<button class="more" data-a="sessToggle" data-x="' + esc(s.pkg) + '">' + icon(s.playing ? 'pause' : 'play') + '</button></div>';
        }).join('') + '</div>' : '<div class="sub dimp">Сейчас в приложениях ничего не играет.</div>';
      }
      h += '</div>';
    }
    return h + '</div>';
  }

  // ---------- «Настройки» ----------
  var SET_TABS = [
    { id: 'general', name: 'Основные', ic: 'gear' },
    { id: 'look', name: 'Оформление', ic: 'palette' },
    { id: 'perf', name: 'Скорость', ic: 'cpu', badge: 'perf' },
    { id: 'sound', name: 'Звук', ic: 'sound' },
    { id: 'keys', name: 'Клавиши', ic: 'keys', desk: true, badge: 'keys' },
    { id: 'profile', name: 'Профиль', ic: 'user', badge: 'profile' }
  ];
  function setTabs() {
    return SET_TABS.filter(function (t) { return !t.desk || NB.kind !== 'android'; });
  }
  function sw(key, title, desc, feature) {
    var s = Store.settings;
    return '<div class="set-row"><div class="minw0"><div>' + title + (feature ? newBadge(feature) : '') + '</div>' + (desc ? '<div class="d">' + desc + '</div>' : '') + '</div>' +
      '<button class="switch' + (s[key] ? ' on' : '') + '" data-a="sw" data-x="' + key + '" aria-label="' + esc(title) + '"></button></div>';
  }
  function segRow(title, desc, key, opts) {
    var v = Store.settings[key];
    return '<div class="set-row col"><div><div>' + title + '</div>' + (desc ? '<div class="d">' + desc + '</div>' : '') + '</div><div class="seg">' + opts.map(function (o) {
      return '<button class="' + (v === o[0] ? 'on' : '') + '" data-a="set" data-x="' + key + ':' + o[0] + '">' + o[1] + '</button>';
    }).join('') + '</div></div>';
  }
  function card(ic, title, body, extra) {
    return '<div class="set-card' + (extra || '') + '"><div class="set-head">' + icon(ic) + '<span>' + title + '</span></div>' + body + '</div>';
  }
  function setScreen() {
    var cur = Store.settings.setTab;
    if (!setTabs().some(function (t) { return t.id === cur; })) cur = Store.settings.setTab = 'general';
    var head = '<div class="set-top"><div class="h1 mc-shadow">Настройки</div>' +
      '<div class="set-tabs">' + setTabs().map(function (t) {
        return '<button class="set-tab' + (cur === t.id ? ' on' : '') + '" data-a="setTab" data-x="' + t.id + '">' + icon(t.ic) + '<span>' + t.name + '</span>' +
          (t.badge && isNew(t.badge) ? '<i class="dot"></i>' : '') + (t.id === 'general' && Updates.status === 'available' ? '<i class="dot upd"></i>' : '') + '</button>';
      }).join('') + '</div></div>';
    var body = cur === 'look' ? setLook() : cur === 'perf' ? setPerf() : cur === 'sound' ? setSound() : cur === 'keys' ? setKeys() : cur === 'profile' ? setProfile() : setGeneral();
    return '<div class="scroll settings">' + head + '<div class="set-body">' + body + '</div></div>';
  }
  function setGeneral() {
    var s = Store.settings;
    return updatesPanel() +
      card('lyrics', 'Текст песни',
        '<div class="set-row"><div>Размер текста</div><div class="w50"><input type="range" min="0.7" max="1.5" step="0.05" value="' + s.textScale + '" data-in="textScale"></div></div>' +
        '<div class="set-row"><div>Подсветка</div><div class="seg w60">' + [['letters', 'По буквам'], ['line', 'Строка']].map(function (k) {
          return '<button class="' + (s.karaoke === k[0] ? 'on' : '') + '" data-a="karaoke" data-x="' + k[0] + '">' + k[1] + '</button>';
        }).join('') + '</div></div>' +
        sw('autoLyrics', 'Искать текст сам', 'lrclib и NetEase, с повтором при сбоях связи') +
        sw('trackToasts', 'Сообщать о новом треке', '') +
        (NB.kind === 'android' ? sw('keepScreenOn', 'Не гасить экран', 'Пока открыт экран «Играет»') : '')) +
      (NB.kind !== 'web' ? card('scan', 'Музыка на устройстве' + newBadge('scan'),
        '<div class="sub dimp">' + (NB.kind === 'android' ? 'Проверю всю память телефона и карту: найду песни в любых папках, даже те, что Android ещё не видит, и уберу из списка исчезнувшие.'
          : 'Проверю все диски компьютера: найду песни в любых папках и уберу из списка файлы, которых больше нет.') + '</div>' +
        '<div class="pl-actions m0">' + scanButton() + '</div>') : '') +
      card('list', 'Библиотека',
        '<div class="sub dimp">Плейлисты и «Любимые» сохраняются сами, прошлая версия всегда остаётся резервной копией. Копию можно перенести на Mac или Windows.</div>' +
        '<div class="pl-actions m0"><button class="btn" data-a="exportLib">' + icon('upload') + 'Сохранить копию</button><button class="btn" data-a="importLib">' + icon('download') + 'Загрузить копию</button></div>');
  }
  function setLook() {
    var s = Store.settings, desk = isDesk();
    var themes = '<div class="themes">' + THEMES.map(function (t) {
      return '<button class="theme-card' + (s.theme === t.id ? ' on' : '') + '" data-a="theme" data-x="' + t.id + '"><div class="pv" style="background:linear-gradient(135deg,' + t.pv.join(',') + ');font-family:' + t.font + ';color:' + t.sung + '">Аа</div>' +
        '<div class="nm"><b>' + t.name + '</b><div class="tg">' + t.tag + '</div></div></button>';
    }).join('') + '</div>';
    var bgs = '<div class="bgs">' + BACKGROUNDS.map(function (b) {
      return '<button class="bg-card' + (s.background === b.id ? ' on' : '') + '" data-a="bg" data-x="' + b.id + '"><canvas data-pv="' + b.id + '" width="208" height="140"></canvas><div class="nm">' + b.name + '</div></button>';
    }).join('') + '</div>';
    return card('palette', 'Тема — меняет всё оформление', themes) +
      card('image', 'Живой фон', bgs) +
      card('tabs', 'Панели',
        sw('roundPanel', 'Закруглённая панель', desk ? 'Боковое меню — отдельной карточкой со скруглёнными углами' : 'Нижняя панель парит над экраном, углы скруглены', 'roundPanel') +
        sw('glass', 'Жидкое стекло', 'Прозрачные панели с бликом. На светлой теме — светлое стекло', 'glass'));
  }
  function setPerf() {
    var s = Store.settings, cur = perfMode();
    var modes = '<div class="modes">' + Object.keys(PERF).map(function (k) {
      var m = PERF[k];
      return '<button class="mode' + (cur === k ? ' on' : '') + '" data-a="perf" data-x="' + k + '"><b>' + icon(k === 'eco' ? 'sparkle' : k === 'beauty' ? 'palette' : 'cpu') + m.name + '</b><span>' + m.tag + '</span></button>';
    }).join('') + '</div>' + (cur ? '' : '<div class="sub dimp">Настроено по-своему</div>');
    return card('cpu', 'Режим' + newBadge('perf'), modes +
        '<div class="fps-now">' + icon('sparkle') + '<span>Сейчас: <b id="fpsnow">' + (S.scene ? S.scene.measured || '…' : '…') + '</b> кадров в секунду' +
        (S.lowBattery && s.batterySaver ? ' · экономлю заряд' : '') + '</span></div>') +
      card('image', 'Живой фон',
        segRow('Кадров в секунду', 'Больше — плавнее, меньше — легче для батареи', 'fps', [[30, '30'], [60, '60'], [0, 'Как у экрана']]) +
        segRow('Качество фона', 'Фон мягкий: на «среднем» разница незаметна, а нагрузка вдвое меньше', 'bgQuality', [[0.5, 'Низкое'], [0.75, 'Среднее'], [1, 'Высокое']]) +
        sw('bgAnim', 'Фон двигается', 'Если выключить — неподвижная картинка, почти без нагрузки') +
        sw('idleSlow', 'На паузе фон отдыхает', 'Когда музыка не играет — 30 кадров') +
        sw('particles', 'Ноты и сердечки на ударах', '')) +
      card('disc', 'Эффекты',
        sw('vinylSpin', 'Пластинка крутится', '') +
        sw('lyricBlur', 'Размытие соседних строк текста', 'Красиво, но нагружает слабые телефоны') +
        sw('panelBlur', 'Размытие под панелями', 'Матовое стекло под меню и мини-плеером') +
        sw('batterySaver', 'Беречь заряд', 'При заряде меньше 20% — лёгкий режим') +
        sw('showFps', 'Счётчик кадров на экране', ''));
  }
  function setSound() {
    var s = Store.settings;
    return card('sound', 'Звук',
      (NB.kind !== 'android' ? '<div class="set-row"><div>Громкость<div class="d">' + Math.round((s.volume != null ? s.volume : 1) * 100) + '%</div></div><div class="w55"><input type="range" min="0" max="1" step="0.05" value="' + (s.volume != null ? s.volume : 1) + '" data-in="volume"></div></div>' : '') +
      '<div class="set-row"><div>Басы<div class="d" id="bassv">' + (s.bass ? '+' + s.bass + ' дБ' : 'выкл') + '</div></div><div class="w55"><input type="range" min="0" max="15" step="1" value="' + s.bass + '" data-in="bass"></div></div>' +
      '<div class="d pad4">Басы работают для твоих файлов. Музыку площадок и приложений играют сами площадки.</div>');
  }
  function setKeys() {
    var b = Keys.binds();
    return card('keys', 'Клавиши' + newBadge('keys'),
      '<div class="sub dimp">Нажми на клавишу справа и затем новую — так можно поставить любую. Backspace — убрать, Esc — отмена.</div>' +
      Keys.ACTIONS.map(function (a) {
        var cap = Keys.capture === a.id;
        return '<div class="set-row"><div>' + a.name + '</div><button class="kbd' + (cap ? ' cap' : '') + '" data-a="keyCap" data-x="' + a.id + '">' + (cap ? 'Нажми клавишу…' : esc(Keys.nameOf(b[a.id]))) + '</button></div>';
      }).join('') +
      '<div class="pl-actions top8 m0"><button class="btn" data-a="keysReset">' + icon('refresh') + 'Вернуть как было</button></div>' +
      '<div class="d pad4">Клавиши не мешают печатать: в полях ввода и на сайтах площадок они работают как обычно.</div>');
  }
  var DISCLAIMER = 'Мы хотим заслужить твоё доверие, поэтому говорим прямо. Мы не используем твои данные против тебя и не продаём их, ' +
    'а храним надёжно. Пароли и вход в Spotify, Яндекс Музыку, VK и SoundCloud остаются только на твоём устройстве — мы их не получаем и не сохраняем. ' +
    'На сервере хранится лишь почта, имя, пароль от профиля в зашифрованном виде и отметка по каждому сервису: «есть активация» или «нет активации». ' +
    'Профиль и все данные можно удалить в любой момент одной кнопкой.';
  function setProfile() {
    var P = Profile, st = P.state;
    if (!P.signedIn()) {
      var reg = S.auth === 'register', f = S.form;
      return card('user', 'Профиль «Музыка в офлайн»' + newBadge('profile'),
        '<div class="sub dimp">Один профиль на всех устройствах: на телефоне и компьютере сразу видно, какие музыкальные сервисы у тебя уже подключены.</div>' +
        '<div class="seg">' + [['login', 'Вход'], ['register', 'Регистрация']].map(function (x) {
          return '<button class="' + (S.auth === x[0] ? 'on' : '') + '" data-a="authMode" data-x="' + x[0] + '">' + x[1] + '</button>';
        }).join('') + '</div>' +
        '<div class="form">' +
        '<input class="search" type="email" autocomplete="email" data-f="email" placeholder="Почта" value="' + esc(f.email || '') + '">' +
        (reg ? '<input class="search" data-f="name" autocomplete="nickname" placeholder="Имя (как к тебе обращаться)" value="' + esc(f.name || '') + '">' : '') +
        '<input class="search" type="password" autocomplete="' + (reg ? 'new-password' : 'current-password') + '" data-f="password" placeholder="Пароль' + (reg ? ' — от 8 символов' : '') + '" value="' + esc(f.password || '') + '">' +
        (reg ? '<div class="disclaimer">' + icon('shield') + '<div><b>Как мы храним данные</b><p>' + DISCLAIMER + '</p></div></div>' +
          '<label class="agree"><input type="checkbox" data-f="agree"' + (f.agree ? ' checked' : '') + '><span>Я прочитал(а) и согласен(на)</span></label>' : '') +
        (P.error ? '<div class="err">' + esc(P.error) + '</div>' : '') +
        '<button class="btn primary block" data-a="' + (reg ? 'doRegister' : 'doLogin') + '"' + (P.busy ? ' disabled' : '') + '>' + icon(reg ? 'sparkle' : 'user') + (P.busy ? 'Подожди…' : reg ? 'Зарегистрироваться' : 'Войти') + '</button>' +
        '</div>' +
        '<details class="adv"><summary>Свой сервер профилей</summary><div class="form"><input class="search" data-f="server" placeholder="https://сайт.ru/muzyka/api.php" value="' + esc(f.server != null ? f.server : Store.settings.syncServer || '') + '">' +
        '<button class="btn small" data-a="saveServer">' + icon('check') + 'Сохранить адрес</button></div></details>');
    }
    var u = st.user || {};
    var rows = Object.keys(PLATFORMS).map(function (id) {
      var sv = st.services && st.services[id], here = Sites.logins[id], on = here || (sv && sv.active);
      var where = here ? 'на этом устройстве' + (sv && sv.devices && sv.devices.length > 1 ? ' и ещё: ' + sv.devices.filter(function (d) { return d !== Profile.deviceName(); }).join(', ') : '')
        : sv && sv.active ? 'на устройствах: ' + (sv.devices || []).join(', ') : 'нигде не подключён';
      return '<div class="set-row"><div class="svc-line">' + badge(id, 30) + '<div class="minw0"><div>' + esc(PLATFORMS[id].name) + '</div><div class="d">' + esc(where) + '</div></div></div>' +
        '<span class="pill ' + (on ? 'ok' : '') + '">' + (on ? 'Есть активация' : 'Нет активации') + '</span></div>';
    }).join('');
    return card('user', 'Профиль',
        '<div class="me"><div class="ava">' + esc(((u.name || u.email || '?').trim()[0] || '?').toUpperCase()) + '</div><div class="minw0"><div class="t ell">' + esc(u.name || 'Без имени') + '</div>' +
        '<div class="d ell">' + esc(u.email || '') + '</div></div></div>' +
        '<div class="d pad4">' + (st.syncedAt ? 'Синхронизировано в ' + new Date(st.syncedAt).toTimeString().slice(0, 5) : 'Ещё не синхронизировано') + (P.error ? ' · ' + esc(P.error) : '') + '</div>' +
        '<div class="pl-actions m0"><button class="btn primary" data-a="doSync"' + (P.busy ? ' disabled' : '') + '>' + icon('cloud') + 'Синхронизировать</button>' +
        '<button class="btn" data-a="doLogout">' + icon('logout') + 'Выйти</button></div>') +
      card('apps', 'Сервисы', rows +
        '<div class="d pad4">Отметка ставится сама, когда входишь в сервис в «Площадках». Сам вход в сервисы не переносится — только отметка, чтобы было видно, где ещё войти.</div>') +
      card('shield', 'Данные', '<div class="d pad4">' + DISCLAIMER + '</div><div class="pl-actions m0"><button class="btn danger" data-a="doDelete">' + icon('trash') + 'Удалить профиль и данные</button></div>');
  }
  function sysName() { return NB.kind === 'android' ? 'Android' : NB.kind === 'windows' ? 'Windows' : 'браузер'; }
  function updStatusText() {
    var u = Updates, l = u.latest;
    if (u.status === 'checking') return 'Проверяю GitHub…';
    if (u.status === 'available') return 'Доступна версия ' + esc(l.version);
    if (u.status === 'downloading') return 'Скачиваю ' + esc(l ? l.version : '') + '… ' + Math.round(u.progress * 100) + '%';
    if (u.status === 'installing') return NB.kind === 'android' ? 'Открываю установку — нажми «Установить»' : 'Устанавливаю, программа сейчас перезапустится';
    if (u.status === 'latest') return 'У тебя последняя версия · проверено в ' + new Date(u.checkedAt).toTimeString().slice(0, 5);
    if (u.status === 'error') return esc(u.error);
    var last = +Store.settings.lastUpdateCheck;
    return last ? 'Последняя проверка: ' + new Date(last).toLocaleString('ru-RU', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' }) : 'Ещё не проверяли';
  }
  function updatesPanel() {
    var u = Updates, busy = u.status === 'checking' || u.status === 'downloading' || u.status === 'installing';
    var prog = u.status === 'downloading' ? '<div class="upd-prog"><i style="width:' + Math.round(u.progress * 100) + '%"></i></div>' : '';
    return '<div id="updpanel">' + card('refresh', 'Обновления' + newBadge('updates'),
      '<div class="set-row first"><div><div>Музыка в офлайн ' + esc(Updates.current()) + ' · ' + sysName() + '</div><div class="d" id="updstatus">' + updStatusText() + '</div></div></div>' + prog +
      '<div class="pl-actions m0">' +
      (u.status === 'available' ? '<button class="btn primary" data-a="updInstall">' + icon('download') + 'Обновить до ' + esc(u.latest.version) + '</button>' : '') +
      '<button class="btn' + (u.status === 'available' ? '' : ' primary') + '" data-a="updCheck"' + (busy ? ' disabled' : '') + '>' + icon('refresh') + 'Проверить обновления</button></div>' +
      sw('autoUpdates', 'Проверять автоматически', 'При запуске и раз в 6 часов'), u.status === 'available' ? ' hot' : '') + '</div>';
  }
  function updateSheet() {
    var l = Updates.latest; if (!l) return;
    var notes = Updates.notesText(l.notes);
    S.updSheet = true;
    sheet('<div class="h2 ic-title">' + icon('sparkle') + 'Доступна версия ' + esc(l.version) + '</div>' +
      '<div class="sub dimp">Сейчас у тебя ' + esc(Updates.current()) + '. Плейлисты, «Любимые» и настройки сохранятся.</div>' +
      (notes ? '<div class="upd-notes">' + esc(notes) + '</div>' : '') +
      '<div id="updsheet">' + updSheetBody() + '</div>');
  }
  function updSheetBody() {
    var u = Updates;
    if (u.status === 'downloading' || u.status === 'installing') {
      return '<div class="sub top8">' + updStatusText() + '</div><div class="upd-prog"><i style="width:' + Math.round(u.progress * 100) + '%"></i></div>';
    }
    return '<div class="pl-actions top8"><button class="btn primary" data-a="updInstall">' + icon('download') + 'Обновить</button>' +
      '<button class="btn" data-a="updLater">Позже</button></div>' + (u.status === 'error' ? '<div class="d">' + esc(u.error) + '</div>' : '');
  }
  Updates.onFound = function () { if (!Sites.open && !$('modal').classList.contains('on')) updateSheet(); };
  Updates.onChange(function () {
    renderTabs();
    var up = $('updpanel');
    if (up) { var t = document.createElement('div'); t.innerHTML = updatesPanel(); up.parentNode.replaceChild(t.firstChild, up); }
    var box = $('updsheet');
    if (box && S.updSheet) box.innerHTML = updSheetBody();
  });

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
    // страница площадки лежит поверх интерфейса — на время окна убираем её
    if (Sites.open && NB.hasBrowser() && !S.sheetOverSite) { S.sheetOverSite = true; NB.siteHide(); }
  }
  function closeSheet() {
    var m = $('modal'); m.classList.remove('on'); m.innerHTML = ''; S.updSheet = false;
    if (S.sheetOverSite) { S.sheetOverSite = false; if (Sites.open && Sites.active) NB.siteShow(Sites.active, Sites.rect()); }
  }
  function menuItem(ic, text, act, x) { return '<button class="menu-item" data-a="' + act + '"' + (x != null ? ' data-x="' + esc(x) + '"' : '') + '>' + icon(ic) + '<span>' + text + '</span></button>'; }

  function addToSheet(track) {
    S.pendingAdd = track;
    var lists = Store.playlists.filter(function (p) { return p.id !== FAV; });
    sheet('<div class="h2 mb6">Добавить в плейлист</div>' +
      menuItem('plus', 'Новый плейлист…', 'newPlAdd') +
      lists.map(function (p) { return menuItem('list', esc(p.name) + (hasKey(p, keyOfItem(track)) ? ' ✓' : ''), 'addToPl', p.id); }).join(''));
  }
  function lyricsSheet() {
    var now = Player.now();
    if (!now) return;
    var e = lyrEntry(now);
    sheet('<div class="h2">' + esc((now.artist ? now.artist + ' — ' : '') + now.title) + '</div>' +
      '<div class="sub dimp">' + esc(e.ly ? 'Текст: ' + e.source : e.status) + '</div>' +
      '<input class="search" id="lyrq" value="' + esc((now.artist ? now.artist + ' ' : '') + now.title) + '">' +
      '<div class="pl-actions top8"><button class="btn primary" data-a="lyrSearch">' + icon('search') + 'Найти</button>' +
      '<button class="btn" data-a="lyrNext">Другой вариант</button><button class="btn" data-a="lyrPaste">' + icon('clip') + 'Вставить свой</button></div>' +
      '<div class="set-row"><div>Сдвиг текста<div class="d" id="offv">' + (e.offset > 0 ? '+' : '') + (e.offset || 0).toFixed(1) + ' с</div></div><div class="w55"><input type="range" min="-5" max="5" step="0.1" value="' + (e.offset || 0) + '" data-in="offset"></div></div>');
  }
  function newTabSheet() {
    sheet('<div class="h2 mb6">Новая вкладка</div>' + Object.keys(PLATFORMS).map(function (id) {
      return '<button class="menu-item" data-a="openPlatformNew" data-x="' + id + '">' + badge(id, 24) + '<span>' + esc(PLATFORMS[id].name) + '</span></button>';
    }).join('') +
      '<div class="form"><input class="search" id="newurl" placeholder="Адрес сайта или поиск"><button class="btn primary" data-a="openTyped">' + icon('globe') + 'Открыть</button></div>');
  }

  // ---------- браузер внутри программы: вкладки и панель ----------
  function brRender() {
    var t = Sites.tab(Sites.active), bar = $('brbar'), tb = $('brtabs');
    if (!bar) return;
    var desk = isDesk(), many = Sites.tabs.length > 1;
    tb.className = desk || many ? 'br-tabs' : 'br-tabs off';
    tb.innerHTML = Sites.tabs.map(function (x) {
      var on = x.id === Sites.active, pl = x.st && x.st.playing;
      return '<button class="br-tab' + (on ? ' on' : '') + '" data-a="brTab" data-x="' + x.id + '">' + badge(x.platform, 16) +
        '<span class="ell">' + esc(tabTitle(x)) + '</span>' + (pl ? '<i class="eq"><b></b><b></b><b></b></i>' : '') +
        '<span class="x" data-a="brCloseTab" data-x="' + x.id + '" title="Закрыть вкладку">' + icon('close') + '</span></button>';
    }).join('') + '<button class="br-add" data-a="brNewTab" title="Новая вкладка">' + icon('plus') + '</button>';
    if (!t) { bar.innerHTML = ''; return; }
    bar.innerHTML =
      '<button class="icon-btn" data-a="brBack" title="Назад">' + icon('back') + '</button>' +
      '<button class="icon-btn' + (t.canFwd ? '' : ' dim') + '" data-a="brFwd" title="Вперёд">' + icon('fwd') + '</button>' +
      '<button class="icon-btn" data-a="brReload" title="' + (t.loading ? 'Остановить' : 'Обновить') + '">' + icon(t.loading ? 'close' : 'refresh') + '</button>' +
      '<div class="br-title"><div class="t ell">' + esc(t.title || tabTitle(t) || 'Загрузка…') + '</div><div class="u ell">' + (/^https:/i.test(t.url) ? '🔒 ' : '') + esc(hostOf(t.url)) + '</div></div>' +
      (!desk ? '<button class="icon-btn" data-a="brNewTab" title="Вкладки">' + icon('tabs') + '</button>' : '') +
      '<button class="icon-btn" data-a="minimizeAll" title="Свернуть все окна площадок">' + icon('minimize') + '</button>' +
      '<button class="icon-btn" data-a="brMenu" title="Ещё">' + icon('more') + '</button>';
    var pr = document.querySelector('#browser .br-prog i');
    if (pr) { pr.style.width = (t.loading ? Math.max(8, Math.round((t.progress || 0) * 100)) : 0) + '%'; pr.parentNode.style.opacity = t.loading ? 1 : 0; }
  }
  var appsSoon = U.debounce(function () { if (S.tab === 'apps' && !S.playlist && !Sites.open) render(); else renderTabs(); }, 250);
  Sites.onChange(function () {
    brRender();
    appsSoon();
    // сайт закрывает весь экран телефона — живой фон не рисуем
    if (S.scene && !document.hidden) { if (Sites.open && !isDesk()) S.scene.stop(); else S.scene.start(); }
  });

  // ---------- действия ----------
  var A = {
    tab: function (x) { closeSheet(); go(x); },
    toggle: function () { Player.toggle(); refresh(); },
    next: function () { Player.next(false); setTimeout(refresh, 250); },
    prev: function () { Player.prev(); setTimeout(refresh, 250); },
    shuffle: function () { Store.settings.shuffle = !Store.settings.shuffle; Store.saveSettings(); Player.setMode(); toast(Store.settings.shuffle ? 'Перемешивание включено' : 'Перемешивание выключено'); refresh(); },
    repeat: function () {
      var r = Store.settings.repeat; Store.settings.repeat = r === 'all' ? 'one' : r === 'one' ? 'none' : 'all';
      Store.saveSettings(); Player.setMode();
      toast({ all: 'Повтор: весь список', one: 'Повтор: один трек', none: 'Повтор выключен' }[Store.settings.repeat]); refresh();
    },
    focus: function () { S.focus = !S.focus; var np = $('np'); if (np) { np.classList.toggle('focus', S.focus); setTimeout(function () { layoutNP(); tickLyrics(true); }, 50); } },
    fav: function () { toggleFav(); },
    addTo: function () { var n = Player.now(); if (n) savedFromNow(n).then(addToSheet); },
    trackMenu: function () {
      var n = Player.now(); if (!n) return;
      sheet('<div class="h2 mb6">' + esc(n.title) + '</div>' +
        menuItem(isFav(n) ? 'heartF' : 'heart', isFav(n) ? 'Убрать из любимых' : 'В любимые', 'fav') +
        menuItem('plus', 'Добавить в плейлист', 'addTo') + menuItem('lyrics', 'Текст песни и поиск', 'lyricsSheet') +
        (n.kind === 'site' ? menuItem('globe', 'Открыть страницу ' + esc(n.app), 'brTab', n.tab) : '') +
        (n.kind === 'ext' ? menuItem('open', 'Открыть ' + esc(n.app || 'приложение'), 'openApp', n.pkg) : ''));
    },
    lyricsSheet: function () { lyricsSheet(); },
    closeModal: closeSheet,
    libSeg: function (x) { S.libSeg = x; render(); },
    libDevice: function () { S.tab = 'lib'; S.libSeg = 'device'; render(); if (NB.kind === 'android') A.scan(); },
    scan: function () { loadDevice(true); },
    deepScan: function () { deepScan(); },
    pickFiles: function () {
      if (NB.kind === 'windows') { NB.scanMusic().then(addPicked); return; }
      if (NB.kind === 'web') $('filepick').click();
    },
    pickFolder: function () { NB.pickFolder().then(addPicked); },
    playDevice: function (uri) {
      var q = U.norm(S.search), list = S.device.filter(function (t) { return !q || U.norm(t.title + ' ' + t.artist).indexOf(q) >= 0; });
      var i = list.findIndex(function (t) { return t.uri === uri; });
      Runner.stop();
      Player.setQueue(list, Math.max(0, i), true);
      saveLast();
      if (!isDesk()) go('np'); else render();
    },
    devMenu: function (uri) {
      var t = S.device.filter(function (d) { return d.uri === uri; })[0]; if (!t) return;
      var st = { id: U.uuid(), source: { file: { path: t.uri } }, title: t.title, artist: t.artist, album: t.album || '', duration: t.duration || 0, artURL: null, added: U.iso() };
      S.pendingAdd = st;
      sheet('<div class="h2 mb6">' + esc(t.title) + '</div>' +
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
    openPl: function (id) { Sites.hide(); S.playlist = id; render(); },
    closePl: function () { S.playlist = null; render(); },
    playPl: function (id) { playPlaylist(id, 0, false); },
    shufflePl: function (id) { playPlaylist(id, 0, true); },
    playItem: function (x) { var a = x.split('|'); playPlaylist(a[0], +a[1], false); },
    itemMenu: function (x) {
      var a = x.split('|'), p = playlist(a[0]), t = p && p.items[+a[1]]; if (!t) return;
      S.pendingAdd = t; S.pendingItem = x;
      var link = t.source && t.source.web && (t.source.web.link || Sites.searchURL(t.source.web.platform, t.title, t.artist));
      sheet('<div class="h2 mb6">' + esc(t.title) + '</div>' +
        (link ? menuItem('globe', 'Открыть в ' + esc((PLATFORMS[t.source.web.platform] || {}).name || 'браузере'), 'openLink', link) : '') +
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
    openLink: function (url) { closeSheet(); Sites.openURL(url); },
    openApp: function (pkg) { closeSheet(); if (NB.launchApp(pkg)) return; var pl = PKG[pkg]; if (pl) Sites.openPlatform(pl); },
    openPlatform: function (id) { closeSheet(); Sites.openPlatform(id); },
    openPlatformNew: function (id) { closeSheet(); var t = Sites.tabFor(id); if (t) Sites.show(t.id); else Sites.openPlatform(id); },
    loginPlatform: function (id) { closeSheet(); Sites.openPlatform(id, true); },
    openTyped: function () {
      var v = String(($('newurl') || {}).value || '').trim(); if (!v) return;
      var url = /^https?:\/\//i.test(v) ? v : /^[\w-]+(\.[\w-]+)+(\/|$)/.test(v) ? 'https://' + v : 'https://www.google.com/search?q=' + encodeURIComponent(v);
      closeSheet(); Sites.newTab(url);
    },
    svcMenu: function (id) {
      var st = Profile.status(id), t = Sites.tabFor(id);
      sheet('<div class="h2 mb6">' + esc(PLATFORMS[id].name) + '</div>' +
        menuItem('globe', 'Открыть', 'openPlatform', id) +
        (st !== 'here' ? menuItem('user', 'Войти в аккаунт', 'loginPlatform', id) : '') +
        (t ? menuItem('close', 'Закрыть вкладку', 'brCloseTab', t.id) : '') +
        (st === 'here' ? menuItem('logout', 'Выйти из аккаунта на этом устройстве', 'logoutPlatform', id) : ''));
    },
    logoutPlatform: function (id) {
      closeSheet();
      if (!confirm('Выйти из ' + PLATFORMS[id].name + ' на этом устройстве? Вход удалится, войти можно будет снова.')) return;
      Sites.logout(id).then(function () { toast('Вышли из ' + PLATFORMS[id].name); render(); });
    },
    brTab: function (id) { closeSheet(); if (Sites.tab(id)) Sites.show(id); },
    brCloseTab: function (id) { closeSheet(); Sites.close(id); if (!Sites.open) render(); },
    brNewTab: function () { newTabSheet(); },
    brBack: function () { Sites.nav('back'); },
    brFwd: function () { Sites.nav('forward'); },
    brReload: function () { var t = Sites.tab(Sites.active); Sites.nav(t && t.loading ? 'stop' : 'reload'); },
    brMenu: function () {
      var t = Sites.tab(Sites.active); if (!t) return;
      sheet('<div class="h2 mb6">' + esc(tabTitle(t)) + '</div>' +
        menuItem('plus', 'Новая вкладка', 'brNewTab') +
        menuItem('minimize', 'Свернуть все окна площадок', 'minimizeAll') +
        menuItem('close', 'Закрыть эту вкладку', 'brCloseTab', t.id) +
        menuItem('open', 'Открыть в системном браузере', 'brExternal'));
    },
    brExternal: function () { closeSheet(); var t = Sites.tab(Sites.active); if (t) NB.openLink(t.url); },
    minimizeAll: function () { closeSheet(); Sites.minimizeAll(); render(); },
    updCheck: function () {
      Updates.check(true).then(function (st) {
        if (st === 'latest') toast('У тебя последняя версия ' + Updates.current());
        else if (st === 'available') toast('Доступна версия ' + Updates.latest.version);
        else if (st === 'error') toast(Updates.error);
      });
    },
    updInstall: function () { Updates.install(); if (!S.updSheet) render(); },
    updLater: function () { if (Updates.latest) { Store.settings.skipVersion = Updates.latest.version; Store.saveSettings(); } closeSheet(); toast('Напомню о следующей версии. Обновиться можно в Настройках'); },
    appSettings: function () { NB.openAppSettings(); },
    notifAccess: function () { NB.openNotifAccess(); },
    useSession: function (pkg) { Player.lastLocal = 0; if (Player.ext && Player.ext.pkg !== pkg) Player.ext = null; go('np'); },
    sessToggle: function (pkg) { var s = Player.extList.filter(function (q) { return q.pkg === pkg; })[0]; if (s) NB.sessionControl(pkg, s.playing ? 'pause' : 'play'); setTimeout(function () { Player.poll(); render(); }, 400); },
    theme: function (id) {
      var t = THEMES.filter(function (q) { return q.id === id; })[0];
      Store.settings.theme = id; Store.settings.background = t.bg; Store.saveSettings(); applyLook(); render();
    },
    bg: function (id) { Store.settings.background = id; Store.saveSettings(); applyLook(); render(); },
    perf: function (k) { applyPerfMode(k); Store.saveSettings(); applyLook(); render(); toast('Режим «' + PERF[k].name + '»'); },
    set: function (x) {
      var i = x.indexOf(':'), k = x.slice(0, i), v = +x.slice(i + 1);
      Store.settings[k] = v; Store.saveSettings(); applyLook(); render();
    },
    karaoke: function (k) { Store.settings.karaoke = k; Store.saveSettings(); render(); },
    sw: function (k, el) {
      Store.settings[k] = !Store.settings[k]; Store.saveSettings(); applyLook();
      if (PERF_KEYS.indexOf(k) >= 0) { render(); return; }
      if (el) el.classList.toggle('on', !!Store.settings[k]);
      if (k === 'roundPanel' || k === 'glass') { Sites.sync(); layoutNP(); }
    },
    setTab: function (x) {
      closeSheet(); Sites.hide();
      Store.settings.setTab = x; Store.saveSettings();
      if (S.tab !== 'set' || S.playlist) { S.tab = 'set'; S.playlist = null; Store.settings.lastTab = 'set'; }
      render();
    },
    keyCap: function (id) { Keys.capture = Keys.capture === id ? null : id; render(); },
    keysReset: function () { Keys.reset(); render(); toast('Клавиши как были'); },
    authMode: function (x) { S.auth = x; Profile.error = ''; render(); },
    doLogin: function () {
      Profile.login(S.form.email, S.form.password).then(function () { S.form = {}; toast('Вход выполнен ✓'); render(); }, function (e) { Profile.error = e.message; render(); });
    },
    doRegister: function () {
      Profile.register(S.form.email, S.form.name, S.form.password, S.form.agree).then(function () { S.form = {}; toast('Профиль создан ✓'); render(); }, function (e) { Profile.error = e.message; render(); });
    },
    saveServer: function () {
      var v = String(S.form.server != null ? S.form.server : '').trim();
      if (v && !/^https?:\/\/\S+$/.test(v)) { toast('Адрес должен начинаться с https://'); return; }
      Store.settings.syncServer = v; Store.saveSettings(); Profile.state.api = ''; Profile.error = '';
      toast(v ? 'Адрес сервера сохранён' : 'Буду брать адрес сервера из GitHub'); render();
    },
    doSync: function () { Profile.sync().then(function () { toast(Profile.error || 'Синхронизировано'); render(); }); },
    doLogout: function () { Profile.logout().then(function () { toast('Вышли из профиля'); render(); }); },
    doDelete: function () {
      var pw = prompt('Чтобы удалить профиль и все данные на сервере, введи пароль от профиля');
      if (!pw) return;
      Profile.remove(pw).then(function () { toast('Профиль и данные удалены'); render(); }, function (e) { toast(e.message); render(); });
    },
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
      sheet('<div class="h2">Свой текст песни</div><div class="sub dimp">Вставь текст. Со временем строк вида [01:23.45] он пойдёт точно под музыку.</div>' +
        '<textarea id="pastebox" placeholder="Текст песни"></textarea><div class="pl-actions top8"><button class="btn primary" data-a="pasteSave">' + icon('check') + 'Сохранить</button></div>');
    },
    pasteSave: function () {
      var now = Player.now(), t = ($('pastebox') || {}).value;
      if (!now || !t || !setLy(now, t, 'вставлен вручную', true)) { toast('Здесь нет текста'); return; }
      closeSheet(); toast('Текст сохранён');
    },
    resume: function () {
      var last = Store.settings.last; if (!last) return;
      Runner.stop();
      Player.setQueue(last.queue, last.index || 0, true, last.pos > 2 ? last.pos : 0);
      go('np');
    }
  };

  // Клавиши → действия
  Keys.run = function (id) {
    var modal = $('modal').classList.contains('on');
    switch (id) {
      case 'toggle': A.toggle(); return true;
      case 'seekBack': Player.seek(Player.time() - 5); tickProgress(); return true;
      case 'seekFwd': Player.seek(Player.time() + 5); tickProgress(); return true;
      case 'volUp': Player.volume(Player.volume() + 0.05); toast('Громкость ' + Math.round(Player.volume() * 100) + '%'); return true;
      case 'volDown': Player.volume(Player.volume() - 0.05); toast('Громкость ' + Math.round(Player.volume() * 100) + '%'); return true;
      case 'next': A.next(); return true;
      case 'prev': A.prev(); return true;
      case 'repeat': A.repeat(); return true;
      case 'shuffle': A.shuffle(); return true;
      case 'fav': A.fav(); return true;
      case 'lyrics': if (S.tab !== 'np' || S.playlist) go('np'); A.focus(); return true;
      case 'library': go('lib'); return true;
      case 'sites': go('apps'); return true;
      case 'minimize': A.minimizeAll(); return true;
      case 'settings': if (S.tab === 'set' && !modal) go('np'); else go('set'); return true;
      case 'back': return window.__back() || modal;
    }
    return false;
  };
  Keys.onCaptured = function () { render(); };

  // Клик по элементу с data-a
  document.addEventListener('click', function (ev) {
    var el = ev.target.closest ? ev.target.closest('[data-a]') : null;
    if (!el) return;
    if (el.hasAttribute('disabled')) return;
    var a = el.getAttribute('data-a'), x = el.getAttribute('data-x');
    if (el.classList.contains('more') || a === 'sessToggle' || a === 'openApp' || a === 'brCloseTab') ev.stopPropagation();
    if (A[a]) { ev.preventDefault(); A[a](x, el); }
  }, true);
  document.addEventListener('input', function (ev) {
    var t = ev.target, k = t.getAttribute && t.getAttribute('data-in'), f = t.getAttribute && t.getAttribute('data-f');
    if (f) { S.form[f] = t.type === 'checkbox' ? t.checked : t.value; return; }
    if (t.id === 'search') {
      S.search = t.value;
      var pos = t.selectionStart;
      S.scrollMem[scrollKey()] = 0;
      render();
      var s = $('search'); if (s) { s.focus(); s.setSelectionRange(pos, pos); }
      return;
    }
    if (!k) return;
    var v = +t.value;
    if (k === 'offset') {
      var now = Player.now(); if (!now) return;
      var e = lyrEntry(now); e.offset = v; Cache.set('off:' + now.key, Math.abs(v) < 0.05 ? null : String(v));
      var ov = $('offv'); if (ov) ov.textContent = (v > 0 ? '+' : '') + v.toFixed(1) + ' с';
      return;
    }
    if (k === 'volume') { Player.volume(v); var d = t.closest('.set-row').querySelector('.d'); if (d) d.textContent = Math.round(v * 100) + '%'; return; }
    Store.settings[k] = v; Store.saveSettings();
    if (k === 'bass') { Player.setBass(v); var bv = $('bassv'); if (bv) bv.textContent = v ? '+' + v + ' дБ' : 'выкл'; }
    if (k === 'textScale') { applyLook(); tickLyrics(true); }
  });
  document.addEventListener('change', function (ev) {
    var t = ev.target, f = t.getAttribute && t.getAttribute('data-f');
    if (f && t.type === 'checkbox') S.form[f] = t.checked;
  });
  document.addEventListener('keydown', function (ev) {
    if (ev.key !== 'Enter' || !ev.target.getAttribute) return;
    if (ev.target.getAttribute('data-f')) { var b = document.querySelector('[data-a="doLogin"],[data-a="doRegister"]'); if (b) b.click(); }
    if (ev.target.id === 'newurl') A.openTyped();
  });

  // ---------- любимые и плейлисты ----------
  function keyOfItem(t) { return Art.keyOf(t); }
  function hasKey(p, k) { return p.items.some(function (it) { return keyOfItem(it) === k; }); }
  function isFavKey(k) { var f = playlist(FAV); return !!f && hasKey(f, k); }
  function isFav(now) { return now ? isFavKey(now.kind === 'file' ? 'file:' + now.uri : now.key) : false; }
  // Запись для плейлиста из того, что играет. У трека площадки узнаём ссылку на его страницу.
  function savedFromNow(n) {
    var art = n.art && n.art.indexOf('http') === 0 ? n.art : (Cache.get('art:' + n.key) || null);
    var base = { id: U.uuid(), title: n.title, artist: n.artist, album: n.album || '', duration: n.duration || 0, artURL: art, added: U.iso() };
    if (n.kind === 'file') { base.source = { file: { path: n.uri } }; return Promise.resolve(base); }
    var job = Runner.active && Runner.item();
    if (n.kind === 'site') {
      if (n.loading && job && job.source && job.source.web) { base.source = { web: { platform: n.platform, link: job.source.web.link || null } }; return Promise.resolve(base); }
      var snap = n.title;
      return Sites.link(n.tab).then(function (l) {
        var still = Player.now() && Player.now().title === snap;
        base.source = { web: { platform: n.platform || 'other', link: still ? l : null } };
        return base;
      });
    }
    base.source = { web: { platform: n.platform || 'other', link: null } };
    return Promise.resolve(base);
  }
  function toggleFavItem(t) {
    var f = playlist(FAV), k = keyOfItem(t);
    if (hasKey(f, k)) { f.items = f.items.filter(function (it) { return keyOfItem(it) !== k; }); toast('Убрано из любимых'); }
    else { f.items.unshift(t); toast('♥ Добавлено в любимые'); }
    Store.saveLibrary();
  }
  function toggleFav() {
    var n = Player.now(); if (!n) { toast('Сначала включи песню'); return; }
    if (isFav(n)) { toggleFavItem({ title: n.title, artist: n.artist, source: n.kind === 'file' ? { file: { path: n.uri } } : { web: {} } }); closeSheet(); refresh(); if (S.tab !== 'np') render(); return; }
    savedFromNow(n).then(function (t) { toggleFavItem(t); closeSheet(); refresh(); if (S.tab !== 'np' || S.playlist) render(); });
  }
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
  // Слушать плейлист: свои файлы и треки площадок подряд
  function playPlaylist(id, start, shuffle) {
    var p = playlist(id); if (!p || !p.items.length) return;
    var hasWeb = p.items.some(function (t) { return t.source && t.source.web; });
    if (hasWeb && NB.hasBrowser()) {
      Runner.start(p.items, start, shuffle, resolveFile);
      if (!isDesk()) go('np'); else render();
      return;
    }
    Runner.stop();
    var t = p.items[start];
    if (t && t.source && t.source.web && !shuffle) {
      Sites.openURL(t.source.web.link || Sites.searchURL(t.source.web.platform, t.title, t.artist));
      return;
    }
    var local = [];
    p.items.forEach(function (it, i) { var m = resolveFile(it); if (m) local.push({ i: i, t: m }); });
    if (!local.length) { toast('В этом плейлисте нет файлов с этого устройства'); return; }
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
  // Вся музыка устройства: ищем в любых папках, проверяем, что файлы на месте
  function deepScan() {
    if (S.scanning) return;
    S.scanning = true; render();
    var before = S.device.length;
    NB.deepScan().then(function (r) {
      if (!r || !r.ok) { S.scanning = false; render(); toast(r && r.denied ? 'Нужно разрешение на доступ к музыке' : 'Не получилось проверить устройство'); return; }
      var st = r.stats || {};
      if (NB.kind === 'android') {
        S.device = r.tracks || [];
        return { found: S.device.length, fresh: st.fresh || 0, missing: st.missing || 0, before: before };
      }
      // Windows: объединяем с добавленными раньше и убираем исчезнувшие файлы
      var have = {}, merged = [];
      (r.tracks || []).forEach(function (t) { have[t.uri] = 1; merged.push(t); });
      var fresh = merged.length;
      S.device.forEach(function (t) { if (!have[t.uri]) { merged.push(t); } else fresh--; });
      return NB.filesExist(merged.map(function (t) { return t.uri; })).then(function (ok) {
        var kept = merged.filter(function (_, i) { return ok[i] !== false; });
        S.device = kept;
        NB.writeFile('files.json', JSON.stringify(S.device));
        return { found: kept.length, fresh: Math.max(0, kept.length - before), missing: merged.length - kept.length, before: before };
      });
    }).then(function (x) {
      S.scanning = false;
      if (!x) return;
      S.tab = 'lib'; S.libSeg = 'device'; S.playlist = null;
      render();
      sheet('<div class="h2 ic-title">' + icon('check') + 'Проверка закончена</div>' +
        '<div class="stats"><div><b>' + x.found + '</b><span>песен на устройстве</span></div><div><b>' + x.fresh + '</b><span>новых найдено</span></div>' +
        '<div><b>' + x.missing + '</b><span>исчезнувших убрано</span></div></div>' +
        '<div class="pl-actions top8"><button class="btn primary" data-a="closeModal">Готово</button></div>');
    }).catch(function () { S.scanning = false; render(); });
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
    if (!q.length || Player.index < 0 || Runner.active) return;
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
      if (n && Store.settings.trackToasts && lastKey && !n.loading) toast('Сейчас играет: ' + (n.artist ? n.artist + ' — ' : '') + n.title);
      if (n && n.art && n.art.indexOf('data:') === 0) Art.palette(n.art).then(function (p) { S.palette = p; });
      else if (n) Art.resolve(n).then(function (u) { if (u) Art.palette(u).then(function (p) { S.palette = p; }); });
      saveLast();
    }
    Sites.mirror();
    if (S.tab === 'np' && !S.playlist) refresh(); else renderMini();
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
      if (!(Sites.open && !isDesk())) S.scene.start();
      Player.poll(); refresh(); Sites.refreshLogins();
      if (NB.kind === 'android' && S.permDenied) loadDevice(false);   // вернулись из настроек с разрешением
      if (S.tab === 'apps' && !Sites.open) render();
    }
  });
  window.addEventListener('pagehide', function () { window.__flush(); });
  // Поворот и размер окна. Пока печатают (открыта клавиатура) — не перерисовываем, чтобы не сбить ввод
  window.addEventListener('resize', U.debounce(function () {
    var a = document.activeElement;
    if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA')) { layoutNP(); return; }
    render(); brRender(); Sites.sync();
  }, 150));
  $('filepick').addEventListener('change', function (ev) {
    var files = Array.prototype.slice.call(ev.target.files || []);
    addPicked({ tracks: files.map(function (f) { return { uri: URL.createObjectURL(f), title: f.name.replace(/\.[^.]+$/, ''), artist: '', duration: 0 }; }) });
  });

  // Кнопка «назад» на Android (и Esc на компьютере)
  window.__back = function () {
    if (Keys.capture) { Keys.capture = null; render(); return true; }
    if ($('modal').classList.contains('on')) { closeSheet(); return true; }
    if (Sites.open) { Sites.nav('back'); return true; }
    if (S.playlist) { S.playlist = null; render(); return true; }
    if (S.focus) { A.focus(); return true; }
    if (S.tab !== 'np') { go('np'); return true; }
    return false;
  };
  window.__insets = function (top, bottom) {
    document.documentElement.style.setProperty('--st', top + 'px');
    document.documentElement.style.setProperty('--sb', bottom + 'px');
    Sites.sync();
  };

  // Логотип приложения (рисуем сами, как иконку на Mac)
  var logoURL = null;
  function LOGO() {
    if (logoURL) return logoURL;
    var c = document.createElement('canvas'); c.width = c.height = 192;
    var x = c.getContext('2d'), g = x.createLinearGradient(0, 0, 192, 192);
    g.addColorStop(0, '#5b2bf0'); g.addColorStop(0.55, '#e0318f'); g.addColorStop(1, '#ffa64d');
    x.fillStyle = g; x.beginPath(); if (x.roundRect) x.roundRect(0, 0, 192, 192, 42); else x.rect(0, 0, 192, 192); x.fill();
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
          return { playing: Player.isPlaying(), spectrum: Player.spectrum(), binHz: Player.binHz(), particles: Store.settings.particles && !(S.lowBattery && Store.settings.batterySaver),
                   progress: n && Player.duration() > 0 ? Player.time() / Player.duration() : null, palette: S.palette, level: 0.5 };
        },
        idle: function () { return !Player.isPlaying(); }
      });
      S.scene.onFps = function (n) {
        var f = $('fps'); if (f && Store.settings.showFps) f.textContent = n + ' FPS';
        var k = $('fpsnow'); if (k) k.textContent = n;
      };
      applyLook();
      S.scene.start();
      watchBattery();
      S.tab = Store.settings.lastTab || 'np';
      if (NB.kind === 'windows') NB.readFile('files.json').then(function (t) { try { S.device = JSON.parse(t || '[]'); } catch (e) {} render(); });
      if (NB.kind === 'android') loadDevice(false);
      Player.setBass(Store.settings.bass);
      Player.setMode();
      restoreLast();
      render();
      Profile.load();
      Profile.onChange(function () { if (S.tab === 'set' && Store.settings.setTab === 'profile' && !S.playlist) render(); else if (S.tab === 'apps' && !Sites.open) appsSoon(); });
      Sites.refreshLogins();
      Updates.auto();
      setInterval(function () {
        renderTabs();
        document.querySelectorAll('.new-badge').forEach(function (b) { if (!isNew(b.getAttribute('data-f'))) b.remove(); });
      }, 60 * 1000);
      NB.ready();
    });
  }
  window.__brState = function () { var t = Sites.tab(Sites.active); return { open: Sites.open, url: t ? t.url : '', title: t ? t.title : '', canBack: t ? t.canBack : false, tabs: Sites.tabs.length }; };
  window.UI = { render: render, refresh: refresh, S: S, A: A };
  start();
})();
