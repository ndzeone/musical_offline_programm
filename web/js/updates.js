/* Обновления: проверка выпусков на GitHub (кнопкой и сама — при запуске и раз в 6 часов),
   скачивание установщика и запуск установки. */
(function () {
  'use strict';

  var REPO = 'ndzeone/musical_offline_programm';
  var API = 'https://api.github.com/repos/' + REPO + '/releases/latest';
  var PAGE = 'https://github.com/' + REPO + '/releases/latest';
  var EVERY = 6 * 3600 * 1000;

  var Updates = {
    status: 'idle',        // idle | checking | latest | available | downloading | installing | error
    latest: null,          // {version, tag, page, notes, asset: {name, url, size}}
    progress: 0,
    checkedAt: 0,
    error: '',
    listeners: [],
    page: PAGE
  };
  function emit() { Updates.listeners.forEach(function (f) { try { f(); } catch (e) { console.error(e); } }); }
  Updates.onChange = function (f) { Updates.listeners.push(f); };

  Updates.current = function () { return String(NB.version() || '0').replace(/^v/i, ''); };

  // Какой файл выпуска подходит этой системе
  function pickAsset(assets) {
    var want = NB.kind === 'android' ? /-Android\.apk$/i : NB.kind === 'windows' ? /-Windows-Setup\.exe$/i : null;
    if (!want) return null;
    var a = (assets || []).filter(function (x) { return want.test(x.name); })[0];
    return a ? { name: a.name, url: a.browser_download_url, size: a.size || 0 } : null;
  }

  // manual — нажали кнопку (показываем результат всегда); opts.current — для проверки
  Updates.check = function (manual, opts) {
    if (Updates.status === 'checking' || Updates.status === 'downloading' || Updates.status === 'installing') return Promise.resolve(Updates.status);
    var current = (opts && opts.current) || Updates.current();
    Updates.status = 'checking'; Updates.error = ''; emit();
    return NB.http(API, { Accept: 'application/vnd.github+json' }).then(function (r) {
      Updates.checkedAt = Date.now();
      if (!r || r.status !== 200) throw new Error(r && r.status === 403 ? 'GitHub временно ограничил проверки, попробую позже' : 'Нет связи с GitHub');
      var d = JSON.parse(r.body);
      var ver = String(d.tag_name || '').replace(/^v/i, '');
      if (!ver) throw new Error('Не удалось прочитать выпуск');
      Updates.latest = { version: ver, tag: d.tag_name, page: d.html_url || PAGE, notes: String(d.body || ''), asset: pickAsset(d.assets) };
      Updates.status = cmpVersion(ver, current) > 0 ? 'available' : 'latest';
      Store.settings.lastUpdateCheck = Updates.checkedAt; Store.saveSettings();
      emit();
      if (Updates.status === 'available' && !manual && Store.settings.skipVersion !== ver && Updates.onFound) Updates.onFound(Updates.latest);
      return Updates.status;
    }).catch(function (e) {
      Updates.status = 'error'; Updates.error = (e && e.message) || 'Ошибка проверки'; emit();
      return 'error';
    });
  };

  // Скачать и установить (Android — установщик системы, Windows — установщик программы)
  Updates.install = function () {
    var l = Updates.latest;
    if (!l) return;
    if (!l.asset || !NB.canSelfUpdate()) { NB.openLink(l.page); return; }
    Updates.status = 'downloading'; Updates.progress = 0; emit();
    NB.installUpdate(l.asset.url, l.asset.name);
  };

  NB.on('update', function (e) {
    if (!e) return;
    if (e.phase === 'progress') { Updates.status = 'downloading'; Updates.progress = +e.progress || 0; }
    else if (e.phase === 'installing') { Updates.status = 'installing'; Updates.progress = 1; }
    else if (e.phase === 'error') { Updates.status = 'error'; Updates.error = e.message || 'Не получилось скачать обновление'; }
    emit();
  });

  // Сама: через 8 секунд после запуска и раз в 6 часов (если не выключено в настройках)
  Updates.auto = function () {
    function due() {
      return Store.settings.autoUpdates && Date.now() - (+Store.settings.lastUpdateCheck || 0) > EVERY - 60000;
    }
    setTimeout(function () { if (Store.settings.autoUpdates) Updates.check(false); }, 8000);
    setInterval(function () { if (due()) Updates.check(false); }, 15 * 60 * 1000);
  };

  // Короткие заметки к выпуску: без разметки, первые строки
  Updates.notesText = function (n) {
    return String(n || '').replace(/\r/g, '').split('\n')
      .map(function (l) { return l.replace(/^#+\s*/, '').replace(/\*\*/g, '').replace(/^\s*[-*]\s+/, '• ').replace(/\|/g, ' ').trim(); })
      .filter(function (l) { return l && !/^[-: ]+$/.test(l); }).slice(0, 8).join('\n');
  };

  window.Updates = Updates;
})();
