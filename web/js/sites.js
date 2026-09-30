/* Сайты площадок внутри программы (Android и Windows): вкладки, вход в аккаунты, что играет,
   включение сохранённых треков из плейлистов. Страницы работают в своих «окнах» поверх интерфейса,
   скрытые вкладки продолжают играть. На каждой странице работает помощник (agent/site-agent.js). */
(function () {
  'use strict';

  var desk = function () { return window.matchMedia('(min-width: 900px) and (min-height: 541px)').matches; };
  var MAX_TABS = NB.kind === 'android' ? 5 : 10;
  var seq = 0;

  var Sites = {
    tabs: [],          // {id, platform, url, title, loading, progress, canBack, canFwd, st, cmdAt, created}
    active: null,      // вкладка на экране
    open: false,       // браузер показан
    logins: {},        // площадка → вошли ли
    current: null,     // вкладка, чья музыка сейчас «главная»
    listeners: []
  };
  function emit() { Sites.listeners.forEach(function (f) { try { f(); } catch (e) { console.error(e); } }); }
  Sites.onChange = function (f) { Sites.listeners.push(f); };

  // ---------- площадки ----------
  Sites.platformOf = function (url) {
    var h = (/^https?:\/\/([^\/?#:]+)/i.exec(url || '') || [])[1] || '';
    h = h.toLowerCase();
    if (/(^|\.)spotify\.com$/.test(h)) return 'spotify';
    if (/(^|\.)soundcloud\.com$/.test(h)) return 'soundcloud';
    if (/(^|\.)yandex\.(ru|com|by|kz|uz)$/.test(h) || /(^|\.)ya\.ru$/.test(h)) return 'yandex';
    if (/(^|\.)vk\.(ru|com|me)$/.test(h) || /(^|\.)vkontakte\.ru$/.test(h)) return 'vk';
    return null;
  };
  Sites.searchURL = function (platform, title, artist) {
    var q = [artist, title].filter(Boolean).join(' '), e = encodeURIComponent(q);
    return { spotify: 'https://open.spotify.com/search/' + e + '/tracks', soundcloud: 'https://soundcloud.com/search/sounds?q=' + e,
             yandex: 'https://music.yandex.ru/search?text=' + e + '&type=tracks', vk: 'https://vk.ru/audio?q=' + e + '&section=search' }[platform] || null;
  };
  Sites.loginURL = function (p) {
    return { spotify: 'https://accounts.spotify.com/ru/login?continue=https%3A%2F%2Fopen.spotify.com%2F', soundcloud: 'https://soundcloud.com/signin',
             yandex: 'https://passport.yandex.ru/auth?retpath=https%3A%2F%2Fmusic.yandex.ru%2F', vk: 'https://vk.ru/login?u=2&to=L2F1ZGlv' }[p] || PLATFORMS[p].home;
  };

  function tab(id) { return Sites.tabs.filter(function (t) { return t.id === id; })[0] || null; }
  Sites.tab = tab;
  Sites.tabFor = function (platform) { return Sites.tabs.filter(function (t) { return t.platform === platform; })[0] || null; };

  // ---------- место браузера на экране ----------
  function rect() {
    var el = document.getElementById('bview'), r = el.getBoundingClientRect();
    return { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height), vw: window.innerWidth, vh: window.innerHeight };
  }
  Sites.rect = rect;
  Sites.sync = function () {
    if (!Sites.open || !Sites.active || !NB.hasBrowser()) return;
    setTimeout(function () { NB.siteBounds(rect()); }, 30);
  };

  function newTab(url, platform) {
    // вкладок слишком много — закрываем самую старую, где ничего не играет
    if (Sites.tabs.length >= MAX_TABS) {
      var old = Sites.tabs.filter(function (t) { return t.id !== Sites.active && !(t.st && t.st.playing); })[0];
      if (old) Sites.close(old.id, true);
    }
    var t = { id: 't' + (++seq) + '-' + Date.now().toString(36), platform: platform || Sites.platformOf(url), url: url, title: '',
              loading: true, progress: 0, canBack: false, canFwd: false, st: null, cmdAt: 0, created: Date.now() };
    Sites.tabs.push(t);
    return t;
  }

  // Показать страницу: вкладка площадки (или новая), браузер поверх интерфейса
  Sites.show = function (id) {
    var t = tab(id);
    if (!t) return;
    Sites.active = id; Sites.open = true;
    document.body.classList.add('browsing');
    document.getElementById('browser').className = '';
    emit();
    setTimeout(function () {
      if (!NB.hasBrowser()) { iframe(t.url); return; }
      if (t.opened) NB.siteShow(id, rect()); else { t.opened = true; NB.siteOpen(id, t.url, rect(), true); }
    }, 30);
  };
  // Открыть адрес: площадка — в её вкладке, другое — в новой (или в активной на телефоне)
  Sites.openURL = function (url, opts) {
    opts = opts || {};
    var p = Sites.platformOf(url);
    var t = !opts.newTab && p ? Sites.tabFor(p) : null;
    if (t) {
      if (url && opts.navigate !== false && url !== t.url) { t.url = url; t.loading = true; if (t.opened) NB.siteLoad(t.id, url); }
    } else {
      t = newTab(url, p);
    }
    Sites.show(t.id);
    return t;
  };
  Sites.openPlatform = function (p, login) {
    var t = Sites.tabFor(p);
    if (t) { Sites.show(t.id); if (login) { t.url = Sites.loginURL(p); NB.siteLoad(t.id, t.url); } return t; }
    return Sites.openURL(login ? Sites.loginURL(p) : PLATFORMS[p].home);
  };
  Sites.newTab = function (url) { return Sites.openURL(url || 'https://www.google.com/', { newTab: true }); };

  // Свернуть: страницы прячутся, но работают (музыка продолжает играть)
  Sites.hide = function () {
    if (!Sites.open) return;
    Sites.open = false;
    if (NB.hasBrowser()) NB.siteHide(); else document.getElementById('bview').innerHTML = '';
    document.body.classList.remove('browsing');
    document.getElementById('browser').className = 'off';
    emit();
  };
  Sites.minimizeAll = function () { Sites.hide(); toast('Окна площадок свёрнуты — музыка играет дальше'); };
  Sites.close = function (id, quiet) {
    var t = tab(id);
    if (!t) return;
    Sites.tabs = Sites.tabs.filter(function (x) { return x.id !== id; });
    if (NB.hasBrowser() && t.opened) NB.siteClose(id);
    if (Sites.current === id) { Sites.current = null; Player.setSite(null); mirror(); }
    if (Sites.active === id) {
      Sites.active = null;
      var next = Sites.tabs[Sites.tabs.length - 1];
      if (next && Sites.open && !quiet) Sites.show(next.id); else Sites.hide();
    }
    emit();
  };
  Sites.nav = function (action) {
    var t = tab(Sites.active);
    if (!t) return;
    if (action === 'back' && !t.canBack) { Sites.hide(); return; }
    NB.siteNav(t.id, action);
  };

  // Проверочный режим в обычном браузере: рамка вместо страницы
  function iframe(url) {
    document.getElementById('bview').innerHTML = '<iframe src="' + U.esc(url) + '" referrerpolicy="no-referrer"></iframe>';
    var t = tab(Sites.active); if (t) { t.loading = false; t.title = Sites.platformOf(url) ? PLATFORMS[Sites.platformOf(url)].name : url; }
    emit();
  }

  // ---------- события от системы ----------
  NB.on('site', function (e) {
    var t = e && tab(e.tab);
    if (!t) return;
    ['url', 'title', 'canBack', 'canFwd', 'loading', 'progress'].forEach(function (k) { if (e[k] != null) t[k] = e[k]; });
    var p = Sites.platformOf(t.url);
    if (p) t.platform = p;
    if (e.loading === false) { afterLoad(t); refreshLoginsSoon(); }
    emit();
  });
  NB.on('siteGone', function (e) {
    var t = e && tab(e.tab);
    if (!t) return;
    t.opened = false; t.st = null;
    if (Sites.current === t.id) { Sites.current = null; Player.setSite(null); mirror(); }
    if (Sites.active === t.id && Sites.open) Sites.show(t.id);   // страница упала — открываем заново
    emit();
  });
  // Ссылка «в новом окне»: на компьютере — новая вкладка, на телефоне — в этой же
  NB.on('siteNew', function (e) {
    if (!e || !e.url) return;
    if (desk() && Sites.tabs.length < MAX_TABS) Sites.openURL(e.url, { newTab: true });
    else { var t = tab(e.tab) || tab(Sites.active); if (t) { t.url = e.url; NB.siteLoad(t.id, e.url); } }
  });
  // Сообщения помощника со страницы: что играет, ход включения трека
  NB.on('siteMsg', function (e) {
    var t = e && tab(e.tab);
    if (!t) return;
    var d = e.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (x) { return; } }
    if (!d) return;
    if (d.ev) { agentEvent(t, d); return; }
    applyState(t, d);
  });
  // Android: кнопки уведомления, когда играет сайт
  NB.on('siteControl', function (e) {
    var a = e && e.action;
    if (a === 'play' || a === 'pause' || a === 'toggle') { if (Player.useSite()) Player.toggle(); }
    else if (a === 'next') Player.next(false);
    else if (a === 'prev') Player.prev();
    else if (a === 'seek' && e.pos != null) Player.seek(+e.pos);
    if (UI && UI.refresh) UI.refresh();
  });

  // ---------- что играет ----------
  function applyState(t, raw) {
    var st = {
      title: String(raw.title || '').trim(), artist: String(raw.artist || '').trim(), album: raw.album || '', art: raw.art || null,
      pos: Math.max(0, +raw.pos || 0), dur: Math.max(0, +raw.dur || 0), playing: raw.paused === false, ended: !!raw.ended, stamp: Date.now()
    };
    var prev = t.st;
    t.st = st;
    var started = st.playing && !(prev && prev.playing);
    if (started) {
      var ours = Date.now() - t.cmdAt < 6000 || (Job.cur && Job.cur.tab === t.id) || (Sites.open && Sites.active === t.id);
      if (!ours) {
        // скрытая вкладка заиграла сама (сайт восстановил прошлый трек) — не даём перебить музыку
        Sites.cmd(t.id, 'pause', null, true);
        st.playing = false;
        return;
      }
      if (Sites.current && Sites.current !== t.id) Sites.cmd(Sites.current, 'pause', null, true);
      Sites.current = t.id;
    }
    if (Job.cur && Job.cur.tab === t.id) Job.check(t);
    if (Sites.current === t.id || (!Sites.current && st.title)) {
      Sites.current = t.id;
      publish(t);
    }
    if (Runner.active && Runner.webTab === t.id) Runner.siteChanged(t, prev);
  }
  function publish(t) {
    var st = t.st;
    if (!st || !st.title) { Player.setSite(null); mirror(); return; }
    var job = Job.cur && Job.cur.tab === t.id && !Job.cur.done ? Job.cur : null;
    Player.setSite({
      tab: t.id, platform: t.platform || 'other', title: job ? job.title : st.title, artist: job ? job.artist : st.artist, album: st.album,
      art: job && job.art ? job.art : st.art, pos: st.pos, dur: st.dur || (job ? job.duration : 0), playing: st.playing || !!job,
      loading: !!job, stamp: st.stamp, link: t.link || null
    });
    mirror();
  }
  // Android: уведомление с треком сайта (и чтобы музыка не засыпала при выключенном экране)
  var mirrored = '';
  function mirror() {
    if (NB.kind !== 'android') return;
    var s = Player.useSite() ? Player.site : null;
    var m = s ? { title: s.title, artist: s.artist, art: s.art && /^https?:/.test(s.art) ? s.art : '', playing: !!s.playing, pos: s.pos, dur: s.dur } : null;
    var key = m ? [m.title, m.artist, m.art, m.playing, Math.round(m.pos / 5), Math.round(m.dur)].join('|') : '';
    if (key === mirrored) return;
    mirrored = key;
    NB.siteMirror(m);
  }
  Sites.mirror = mirror;

  // Команда странице: play, pause, nexttrack, previoustrack, seekto
  Sites.cmd = function (id, action, arg, quiet) {
    var t = tab(id);
    if (!t) return;
    if (!quiet) t.cmdAt = Date.now();
    if (action !== 'pause' && !quiet && Sites.current !== id) {
      if (Sites.current) Sites.cmd(Sites.current, 'pause', null, true);
      Sites.current = id;
    }
    if (action === 'play' && Player.playing) Player.yieldToSite();
    run(id, "__mc.cmd(" + JSON.stringify(action) + (arg != null ? ', ' + (+arg) : '') + ")");
    setTimeout(function () { poll(id); }, 400);
  };
  Sites.pauseAll = function () {
    Job.cancel();
    Sites.tabs.forEach(function (t) { if (t.st && t.st.playing) Sites.cmd(t.id, 'pause', null, true); });
  };
  function run(id, js) { NB.siteEval(id, 'window.__mc ? String(' + js + ') : "nohook"'); }

  // Сверка состояния: играющая и открытая вкладки — раз в секунду, остальные — редко
  function poll(id) {
    var t = tab(id);
    if (!t || !t.opened) return;
    t.polled = Date.now();
    NB.siteEval(id, 'window.__mc ? window.__mc.state() : ""').then(function (s) {
      if (!s || typeof s !== 'string' || s.charAt(0) !== '{') return;
      try { applyState(t, JSON.parse(s)); } catch (e) {}
    });
  }
  setInterval(function () {
    if (!NB.hasBrowser()) return;
    Sites.tabs.forEach(function (t) {
      var busy = (t.st && t.st.playing) || t.id === Sites.active || (Job.cur && Job.cur.tab === t.id);
      if (busy || Date.now() - (t.polled || 0) > 6000) poll(t.id);
    });
    if (Job.cur) Job.tick();
  }, 1000);

  // Ссылка на трек, который играет (для «Любимых» и плейлистов)
  Sites.link = function (id) {
    return NB.siteEval(id, 'window.__mc ? (window.__mc.link() || "") : ""').then(function (v) { return v && /^https?:/.test(v) ? v : null; });
  };

  // ---------- включить сохранённый трек (как на Mac: страница трека или поиск, помощник жмёт «играть») ----------
  var Job = {
    cur: null,   // {tab, title, artist, duration, art, url, t0, reloaded, agentAt, done, onDone}
    start: function (item, onDone) {
      Job.cancel();
      var p = item.platform, link = item.link || Sites.searchURL(p, item.title, item.artist);
      if (!p || !link) { if (onDone) onDone(false); return; }
      var t = Sites.tabFor(p);
      if (!t) { t = newTab(link, p); t.loading = true; }
      Job.cur = { tab: t.id, title: item.title, artist: item.artist, duration: item.duration || 0, art: item.artURL || null, url: link,
                  t0: Date.now(), reloaded: false, agentAt: 0, done: false, onDone: onDone || null, loadAt: Date.now() };
      t.cmdAt = Date.now();
      t.link = item.link || null;
      if (Sites.current && Sites.current !== t.id) Sites.cmd(Sites.current, 'pause', null, true);
      Sites.current = t.id;
      if (Player.playing) Player.yieldToSite();
      // показываем трек сразу, со значком загрузки
      t.st = t.st || { title: '', artist: '', pos: 0, dur: 0, playing: false, stamp: Date.now() };
      publish({ id: t.id, platform: p, st: { title: item.title, artist: item.artist, album: '', art: item.artURL, pos: 0, dur: item.duration || 0, playing: false, stamp: Date.now() }, link: t.link });
      var soft = p !== 'vk' && t.opened && !t.loading && t.url && Sites.platformOf(t.url) === p;
      if (soft) {
        var path = link.replace(/^https?:\/\/[^\/]+/, '');
        NB.siteEval(t.id, "(function(p){if(window.next&&window.next.router&&window.next.router.push){window.next.router.push(p);return 'next'}history.pushState({},'',p);window.dispatchEvent(new PopStateEvent('popstate',{state:{}}));return 'history'})(" + JSON.stringify(path) + ")");
        t.url = link;
        setTimeout(function () { Job.agent(7000); }, 600);
      } else {
        t.url = link; t.loading = true;
        if (t.opened) NB.siteLoad(t.id, link);
        else { t.opened = true; NB.siteOpen(t.id, link, rect(), false); }
      }
      emit();
    },
    agent: function (limit) {
      var j = Job.cur;
      if (!j) return;
      j.agentAt = Date.now();
      NB.siteEval(j.tab, 'window.__mc ? window.__mc.autoplayStart(' + JSON.stringify(j.title) + ', ' + JSON.stringify(j.artist) + ', ' + (limit | 0) + ') : "nohook"')
        .then(function (v) { if (Job.cur === j && v !== 'started') j.agentAt = 0; });
    },
    loaded: function (t) {
      var j = Job.cur;
      if (j && j.tab === t.id && !j.done) setTimeout(function () { if (Job.cur === j) Job.agent(15000); }, 500);
    },
    check: function (t) {
      var j = Job.cur;
      if (!j || j.done || !t.st || !t.st.playing) return;
      if (U.sameSong(t.st.title, t.st.artist, j.title, j.artist) || (t.st.title && U.norm(t.st.title) === U.norm(j.title))) Job.finish(true);
    },
    tick: function () {
      var j = Job.cur;
      if (!j || j.done) return;
      var t = tab(j.tab);
      if (!t) { Job.finish(false); return; }
      if (Date.now() - j.t0 > 35000) { Job.finish(false); return; }
      // страница долго «грузится» фоновыми запросами, а кнопки уже есть — начинаем
      if (!j.agentAt && Date.now() - j.loadAt > 6000) Job.agent(15000);
    },
    event: function (t, d) {
      var j = Job.cur;
      if (!j || j.tab !== t.id) return;
      if (d.r === 'press') {
        t.cmdAt = Date.now();
        NB.sitePress(t.id, d.x, d.y, d.vw, d.vh);
        setTimeout(function () { if (Job.cur === j && !j.done) run(t.id, '__mc.pressTarget()'); }, 900);
      } else if (d.r === 'click') {
        t.cmdAt = Date.now();
      } else if (d.r === 'timeout') {
        if (!j.reloaded) { j.reloaded = true; j.loadAt = Date.now(); j.agentAt = 0; t.loading = true; NB.siteLoad(t.id, j.url); }
        else Job.finish(false);
      }
    },
    finish: function (ok) {
      var j = Job.cur;
      if (!j) return;
      j.done = true;
      Job.cur = null;
      NB.siteEval(j.tab, 'window.__mc && __mc.autoplayStop()');
      var t = tab(j.tab);
      if (t) publish(t);
      if (!ok) {
        if (!(j.onDone && j.onDone(false))) {
          toast('Площадка не дала включить «' + j.title + '» сама — нажми ▶ на странице');
          if (t) Sites.show(t.id);
        }
      } else if (j.onDone) j.onDone(true);
      emit();
    },
    cancel: function () {
      var j = Job.cur;
      if (!j) return;
      Job.cur = null;
      NB.siteEval(j.tab, 'window.__mc && __mc.autoplayStop()');
    }
  };
  Sites.job = Job;
  function afterLoad(t) { Job.loaded(t); }
  function agentEvent(t, d) { if (d.ev === 'autoplay') Job.event(t, d); }

  Sites.playTrack = function (item, onDone) {
    if (!NB.hasBrowser()) { Sites.openURL(item.link || Sites.searchURL(item.platform, item.title, item.artist)); return; }
    Job.start(item, onDone);
  };

  // ---------- вход в аккаунты ----------
  var loginTimer = null;
  Sites.refreshLogins = function () {
    return NB.siteLogins().then(function (l) {
      l = l || {};
      var changed = Object.keys(PLATFORMS).some(function (p) { return !!l[p] !== !!Sites.logins[p]; });
      Sites.logins = l;
      if (changed) { emit(); if (window.Profile) Profile.servicesChanged(); }
      return l;
    });
  };
  function refreshLoginsSoon() { clearTimeout(loginTimer); loginTimer = setTimeout(Sites.refreshLogins, 1200); }
  Sites.logout = function (p) {
    var t = Sites.tabFor(p);
    if (t) Sites.close(t.id, true);
    return NB.siteLogout(p).then(function () { return Sites.refreshLogins(); });
  };

  window.addEventListener('resize', function () { Sites.sync(); });

  // ---------- плейлист со своими файлами и треками площадок подряд ----------
  var Runner = {
    active: false, items: [], order: [], pos: 0, webTab: null, confirmed: false, fails: 0, fileUri: null,
    // items — треки плейлиста; start — с какого; shuffle — вперемешку
    start: function (items, start, shuffle, resolveFile) {
      Runner.stop();
      Runner.items = items; Runner.resolveFile = resolveFile;
      var o = items.map(function (_, i) { return i; });
      if (shuffle) {
        for (var i = o.length - 1; i > 0; i--) { var j = Math.random() * (i + 1) | 0, x = o[i]; o[i] = o[j]; o[j] = x; }
        var k = o.indexOf(start); if (k > 0) { o[k] = o[0]; o[0] = start; }
      }
      Runner.order = o; Runner.pos = Math.max(0, o.indexOf(start)); Runner.active = true; Runner.fails = 0;
      NB.delegateSkips(true);
      Runner.play();
    },
    stop: function () {
      if (!Runner.active) return;
      Runner.active = false; Runner.webTab = null; Runner.fileUri = null;
      NB.delegateSkips(false);
      Player.modeOverride = null;
      Player.setMode();
    },
    item: function () { return Runner.items[Runner.order[Runner.pos]]; },
    play: function () {
      var it = Runner.item();
      if (!it) { Runner.stop(); return; }
      Runner.confirmed = false; Runner.webTab = null; Runner.fileUri = null;
      if (it.source && it.source.web) {
        var w = it.source.web;
        Sites.playTrack({ platform: w.platform, link: w.link, title: it.title, artist: it.artist, duration: it.duration, artURL: it.artURL }, function (ok) {
          if (!Runner.active) return false;
          if (ok) { Runner.fails = 0; Runner.confirmed = true; return true; }
          toast('Не получилось включить «' + it.title + '» — включаю следующий');
          Runner.skip();
          return true;
        });
        var t = Sites.tabFor(w.platform);
        Runner.webTab = t ? t.id : null;
      } else {
        var f = Runner.resolveFile && Runner.resolveFile(it);
        if (!f) { toast('Нет файла «' + it.title + '» на этом устройстве — пропускаю'); Runner.skip(); return; }
        Runner.fileUri = f.uri;
        Player.modeOverride = { shuffle: false, repeat: 'none' };
        Player.setQueue([f], 0, true);
      }
      emit();
    },
    skip: function () {
      Runner.fails++;
      if (Runner.fails >= Runner.order.length) { Runner.stop(); toast('Ни один трек этого плейлиста сейчас не включается'); return; }
      setTimeout(function () { if (Runner.active) Runner.step(1, true); }, 900);
    },
    // Вперёд или назад по плейлисту. true — шаг сделан
    step: function (d, auto) {
      if (!Runner.active) return false;
      var n = Runner.order.length, p = Runner.pos + d;
      if (p >= n) {
        if (auto && Store.settings.repeat === 'none') { Runner.stop(); toast('Плейлист закончился'); return true; }
        p = 0;
      }
      if (p < 0) p = n - 1;
      if (auto && Store.settings.repeat === 'one') p = Runner.pos;
      Runner.pos = p;
      var cur = tab(Runner.webTab);
      if (cur && cur.st && cur.st.playing && !(Runner.item().source && Runner.item().source.web && Runner.item().source.web.platform === cur.platform)) Sites.cmd(cur.id, 'pause', null, true);
      Runner.play();
      return true;
    },
    // Трек площадки закончился или сайт сам перешёл к другому — следующий трек плейлиста
    siteChanged: function (t, prev) {
      if (!Runner.confirmed || !t.st) return;
      var it = Runner.item();
      var same = it && U.sameSong(t.st.title, t.st.artist, it.title, it.artist);
      if (t.st.ended || (!same && t.st.title && prev && prev.title !== t.st.title)) {
        Runner.confirmed = false;
        Sites.cmd(t.id, 'pause', null, true);
        Runner.step(1, true);
      }
    }
  };
  // Своя очередь доиграла (файл из плейлиста) — дальше по плейлисту
  Player.onQueueEnd = function () { if (Runner.active && Runner.fileUri) Runner.step(1, true); };
  NB.on('queueEnd', function () { if (Player.onQueueEnd) Player.onQueueEnd(); });
  NB.on('control', function (e) {
    // «дальше/назад» из уведомления, пока играет плейлист с треками площадок
    if (!e) return;
    if (e.action === 'next') { if (!Runner.step(1)) Player.next(false); }
    else if (e.action === 'prev') { if (!Runner.step(-1)) Player.prev(); }
  });

  window.Runner = Runner;
  window.Sites = Sites;
})();
