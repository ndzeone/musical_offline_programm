/* Профиль «Музыка в офлайн»: регистрация и вход, чтобы на всех устройствах было видно,
   какие музыкальные сервисы уже подключены. Пароли от Spotify, Яндекса, VK и SoundCloud
   никуда не отправляются: на сервер уходит только «активирован / не активирован». */
(function () {
  'use strict';

  var CONFIG_URL = 'https://raw.githubusercontent.com/ndzeone/musical_offline_programm/main/server.json';
  var Profile = {
    state: { api: '', token: '', user: null, services: {}, syncedAt: 0 },   // services: площадка → {active, device, updated}
    busy: false, error: '', listeners: [], loaded: false
  };
  function emit() { Profile.listeners.forEach(function (f) { try { f(); } catch (e) { console.error(e); } }); }
  Profile.onChange = function (f) { Profile.listeners.push(f); };
  var save = U.debounce(function () { NB.writeFile('profile.json', JSON.stringify(Profile.state)); }, 200);

  Profile.load = function () {
    return NB.readFile('profile.json').then(function (t) {
      try { Object.assign(Profile.state, JSON.parse(t || '{}') || {}); } catch (e) {}
      Profile.loaded = true;
      emit();
      if (Profile.state.token) Profile.refresh();
    });
  };
  Profile.signedIn = function () { return !!(Profile.state.token && Profile.state.user); };
  Profile.deviceName = function () { return NB.kind === 'android' ? 'Android' : NB.kind === 'windows' ? 'Windows' : 'Браузер'; };

  // Адрес сервера: свой из настроек или общий из server.json в репозитории (его меняет владелец сайта)
  Profile.api = function () {
    var own = String(Store.settings.syncServer || '').trim();
    if (own) return Promise.resolve(own);
    if (Profile.state.api && Date.now() - (Profile.state.apiAt || 0) < 12 * 3600e3) return Promise.resolve(Profile.state.api);
    return NB.http(CONFIG_URL + '?t=' + Math.floor(Date.now() / 600000), {}).then(function (r) {
      var api = '';
      try { api = r && r.status === 200 ? String(JSON.parse(r.body).api || '') : ''; } catch (e) {}
      if (api) { Profile.state.api = api; Profile.state.apiAt = Date.now(); save(); }
      return api || Profile.state.api || '';
    });
  };

  function call(action, body, method) {
    return Profile.api().then(function (api) {
      if (!api || !/^https?:\/\//.test(api)) throw new Error('Сервер профилей ещё не подключён. Скоро заработает!');
      if (/^http:\/\//.test(api) && !/^http:\/\/(localhost|127\.|10\.0\.2\.2)/.test(api)) throw new Error('Сервер должен работать по https');
      var h = { 'Content-Type': 'application/json', Accept: 'application/json' };
      if (Profile.state.token) { h.Authorization = 'Bearer ' + Profile.state.token; h['X-Auth-Token'] = Profile.state.token; }
      var url = api + (api.indexOf('?') >= 0 ? '&' : '?') + 'action=' + encodeURIComponent(action);
      return NB.request(url, method || 'POST', h, body ? JSON.stringify(body) : '').then(function (r) {
        var d = null;
        try { d = JSON.parse(r.body || 'null'); } catch (e) {}
        if (!r || !r.status) throw new Error('Нет связи с сервером профилей');
        if (r.status === 401 && action !== 'login') { Profile.forget(); throw new Error('Вход устарел — войди в профиль снова'); }
        if (!d || d.ok === false || r.status >= 400) throw new Error((d && d.error) || ('Сервер ответил ошибкой ' + r.status));
        return d;
      });
    });
  }
  Profile.call = call;

  function run(p) {
    Profile.busy = true; Profile.error = ''; emit();
    return p.then(function (v) { Profile.busy = false; emit(); return v; }, function (e) {
      Profile.busy = false; Profile.error = (e && e.message) || 'Ошибка'; emit(); throw e;
    });
  }
  function accept(d) {
    Profile.state.token = d.token || Profile.state.token;
    Profile.state.user = d.user || Profile.state.user;
    if (d.services) Profile.state.services = d.services;
    save(); emit();
  }

  var EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
  Profile.register = function (email, name, password, agree) {
    email = String(email || '').trim().toLowerCase(); name = String(name || '').trim();
    if (!EMAIL.test(email)) return Promise.reject(new Error('Проверь почту'));
    if (String(password || '').length < 8) return Promise.reject(new Error('Пароль — от 8 символов'));
    if (!agree) return Promise.reject(new Error('Нужно согласие с условиями хранения данных'));
    return run(call('register', { email: email, name: name, password: password, device: Profile.deviceName(), agree: true }).then(function (d) {
      accept(d); return Profile.sync();
    }));
  };
  Profile.login = function (email, password) {
    email = String(email || '').trim().toLowerCase();
    if (!EMAIL.test(email) || !password) return Promise.reject(new Error('Введи почту и пароль'));
    return run(call('login', { email: email, password: password, device: Profile.deviceName() }).then(function (d) {
      accept(d); return Profile.sync();
    }));
  };
  Profile.forget = function () {
    Profile.state.token = ''; Profile.state.user = null; Profile.state.services = {}; Profile.state.syncedAt = 0;
    save(); emit();
  };
  Profile.logout = function () {
    var p = Profile.state.token ? call('logout', {}).catch(function () {}) : Promise.resolve();
    return p.then(function () { Profile.forget(); });
  };
  Profile.remove = function (password) {
    return run(call('delete', { password: password }).then(function () { Profile.forget(); }));
  };
  Profile.refresh = function () {
    return call('me', null, 'GET').then(accept).catch(function (e) { Profile.error = e.message; emit(); });
  };

  // Отметки «активирован / не активирован» для этого устройства → на сервер
  Profile.sync = function () {
    if (!Profile.signedIn()) return Promise.resolve();
    var p = window.Sites ? Sites.refreshLogins() : Promise.resolve({});
    return p.then(function (l) {
      var mine = {};
      Object.keys(PLATFORMS).forEach(function (k) { mine[k] = !!(l && l[k]); });
      return call('services', { device: Profile.deviceName(), services: mine });
    }).then(function (d) {
      if (d.services) Profile.state.services = d.services;
      Profile.state.syncedAt = Date.now(); save(); emit();
    }).catch(function (e) { Profile.error = e.message; emit(); });
  };
  var syncSoon = U.debounce(function () { Profile.sync(); }, 1500);
  Profile.servicesChanged = function () { if (Profile.signedIn()) syncSoon(); };

  // Статус сервиса для экрана: 'here' — вход на этом устройстве, 'other' — активирован на другом, '' — нет
  Profile.status = function (p) {
    if (window.Sites && Sites.logins[p]) return 'here';
    var s = Profile.state.services && Profile.state.services[p];
    return s && s.active ? 'other' : '';
  };

  window.Profile = Profile;
})();
