/* Мост к системе: Android (Java), Windows (Electron) или проверочный режим в браузере.
   Все команды возвращают Promise, чтобы остальной код не зависел от системы. */
(function () {
  'use strict';
  var A = window.AndroidNative || null;
  var E = window.ElectronNative || null;
  var kind = A ? 'android' : (E ? 'windows' : 'web');
  var seq = 0;
  var waiting = {};

  // Android присылает ответы сюда: window.__nb(id, json)
  window.__nb = function (id, payload) {
    var w = waiting[id];
    if (!w) return;
    delete waiting[id];
    var v = payload;
    if (typeof payload === 'string') { try { v = JSON.parse(payload); } catch (e) { v = payload; } }
    w(v);
  };
  // События от Android (плеер, сеансы других приложений, кнопка «назад»)
  var listeners = {};
  window.__nbEvent = function (name, payload) {
    var v = payload;
    if (typeof payload === 'string') { try { v = JSON.parse(payload); } catch (e) { v = payload; } }
    (listeners[name] || []).forEach(function (f) { try { f(v); } catch (e) { console.error(e); } });
  };

  // События от Windows (браузер внутри программы, загрузка обновления)
  if (E && E.onEvent) E.onEvent(function (name, payload) { window.__nbEvent(name, payload); });

  function acall(fn, args) {
    return new Promise(function (res) {
      var id = 'r' + (++seq);
      waiting[id] = res;
      try { A[fn].apply(A, [id].concat(args || [])); }
      catch (e) { delete waiting[id]; console.error(fn, e); res(null); }
    });
  }
  function sync(fn, args, fallback) {
    try { return A[fn].apply(A, args || []); } catch (e) { return fallback; }
  }
  function json(s, fallback) { try { return s ? JSON.parse(s) : fallback; } catch (e) { return fallback; } }

  // ---------- проверочный режим (браузер на Mac): всё в памяти ----------
  var mem = {};
  var mock = {
    http: function (url) {
      if (window.__mockHttp) return Promise.resolve(window.__mockHttp(url));
      return fetch(url).then(function (r) { return r.text().then(function (t) { return { status: r.status, body: t }; }); })
        .catch(function () { return { status: 0, body: '' }; });
    },
    readFile: function (n) { return Promise.resolve(mem[n] || (window.localStorage ? localStorage.getItem('f:' + n) : null)); },
    writeFile: function (n, t) { mem[n] = t; try { localStorage.setItem('f:' + n, t); } catch (e) {} return Promise.resolve(true); }
  };

  var NB = {
    kind: kind,
    on: function (name, f) { (listeners[name] = listeners[name] || []).push(f); },
    version: function () {
      if (A) return sync('version', [], '2.4.0');
      if (E && E.version) return E.version;
      return window.__mockVersion || '2.4.0';
    },
    http: function (url, headers) {
      var h = JSON.stringify(headers || {});
      if (A) return acall('http', [url, h]).then(function (r) { return r || { status: 0, body: '' }; });
      if (E) return E.http(url, headers || {});
      return mock.http(url, headers);
    },
    readFile: function (name) {
      if (A) return Promise.resolve(sync('readFile', [name], null));
      if (E) return E.readFile(name);
      return mock.readFile(name);
    },
    writeFile: function (name, text) {
      if (A) return Promise.resolve(!!sync('writeFile', [name, text], false));
      if (E) return E.writeFile(name, text);
      return mock.writeFile(name, text);
    },
    // Музыка на устройстве / выбор файлов
    // ask — показать запрос разрешения (иначе только проверить)
    scanMusic: function (ask) {
      if (A) return acall('scanMusic', [!!ask]).then(function (r) { return r || { ok: false, tracks: [] }; });
      if (E) return E.pickMusic();
      return Promise.resolve(window.__mockTracks ? { ok: true, tracks: window.__mockTracks } : { ok: true, tracks: [] });
    },
    pickFolder: function () {
      if (E && E.pickFolder) return E.pickFolder();
      return NB.scanMusic();
    },
    exportText: function (fileName, text) {
      if (A) return acall('exportText', [fileName, text]);
      if (E) return E.exportText(fileName, text);
      return Promise.resolve({ ok: true });
    },
    importText: function () {
      if (A) return acall('importText', []);
      if (E) return E.importText();
      return Promise.resolve(null);
    },
    embeddedArt: function (uri) {
      if (A) return acall('embeddedArt', [uri]).then(function (r) { return (r && r.art) || null; });
      if (E) return E.embeddedArt(uri);
      return Promise.resolve(null);
    },
    mediaURL: function (uri) {
      if (E) return E.mediaURL(uri);
      return uri;
    },
    // Плеер Android (служба в фоне: играет, даже когда экран выключен)
    setQueue: function (qid, items, index, autoplay, startPos) { if (A) sync('setQueue', [qid, JSON.stringify(items), index | 0, !!autoplay, +startPos || 0]); },
    queueState: function () { return A ? json(sync('queueState', [], ''), null) : null; },
    control: function (action, arg) { if (A) sync('control', [action, arg == null ? 0 : +arg]); },
    playbackState: function () { return A ? json(sync('playbackState', [], ''), null) : null; },
    setMode: function (shuffle, repeat) { if (A) sync('setMode', [!!shuffle, repeat]); },
    setBass: function (v) { if (A) sync('setBass', [+v]); },
    // Что играет в других приложениях (Spotify, Яндекс Музыка, VK, SoundCloud)
    hasNotifAccess: function () { return A ? !!sync('hasNotifAccess', [], false) : false; },
    openNotifAccess: function () { if (A) sync('openNotifAccess', []); },
    sessions: function () { return A ? json(sync('sessions', [], '[]'), []) : []; },
    sessionArt: function (pkg) { return A ? sync('sessionArt', [pkg], '') : ''; },
    sessionControl: function (pkg, action, arg) { if (A) sync('sessionControl', [pkg, action, arg == null ? 0 : +arg]); },
    appIcon: function (pkg) { return A ? sync('appIcon', [pkg], '') : ''; },
    installedApps: function () { return A ? json(sync('installedApps', [], '[]'), []) : []; },
    launchApp: function (pkg) { return A ? !!sync('launchApp', [pkg], false) : false; },
    openAppSettings: function () { if (A) sync('openAppSettings', []); },
    openLink: function (url) {
      if (A) return sync('openLink', [url]);
      if (E) return E.openLink(url);
      window.open(url, '_blank');
    },
    // Обновление: скачать установщик из выпуска на GitHub и запустить его
    canSelfUpdate: function () { return !!(A || (E && E.installUpdate)); },
    installUpdate: function (url, name) {
      if (A) { sync('installUpdate', [url, name || 'update.apk']); return true; }
      if (E && E.installUpdate) { E.installUpdate(url, name); return true; }
      return false;
    },
    // Браузер внутри программы: страница площадки поверх интерфейса в прямоугольнике rect
    hasBrowser: function () { return !!(A || (E && E.browserOpen)); },
    browserOpen: function (url, rect) {
      var r = JSON.stringify(rect || {});
      if (A) return sync('browserOpen', [url, r]);
      if (E && E.browserOpen) return E.browserOpen(url, rect);
    },
    browserBounds: function (rect) {
      if (A) return sync('browserBounds', [JSON.stringify(rect)]);
      if (E && E.browserBounds) return E.browserBounds(rect);
    },
    browserNav: function (action) {
      if (A) return sync('browserNav', [action]);
      if (E && E.browserNav) return E.browserNav(action);
    },
    browserClose: function () {
      if (A) return sync('browserClose', []);
      if (E && E.browserClose) return E.browserClose();
    },
    keepScreenOn: function (on) { if (A) sync('keepScreenOn', [!!on]); },
    systemBars: function (lightIcons) { if (A) sync('systemBars', [!!lightIcons]); },
    insets: function () { return A ? json(sync('insets', [], ''), null) : null; },
    ready: function () { if (A) sync('ready', []); if (E && E.ready) E.ready(); }
  };
  window.NB = NB;
})();
