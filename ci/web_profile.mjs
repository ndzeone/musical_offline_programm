// Профиль в самой программе (общий интерфейс) против настоящего сервера: регистрация с согласием,
// отметки сервисов, выход, вход, удаление. Страница открыта в Chrome без окна, управление через DevTools.
// Запуск: node ci/web_profile.mjs http://127.0.0.1:8090/index.html http://127.0.0.1:8088/api.php <out>
import fs from 'node:fs';
import path from 'node:path';

const [page, api, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
let failed = 0;
const check = (name, ok, info = '') => { console.log((ok ? 'PASS ' : 'FAIL ') + name + (info ? ' — ' + info : '')); if (!ok) failed++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const list = await (await fetch('http://127.0.0.1:9222/json')).json();
const target = list.find((p) => p.type === 'page');
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => { ws.onopen = r; });
let seq = 0;
const waiting = new Map();
ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waiting.has(d.id)) { waiting.get(d.id)(d); waiting.delete(d.id); } };
const send = (method, params) => new Promise((res) => { const id = ++seq; waiting.set(id, res); ws.send(JSON.stringify({ id, method, params })); });
const js = async (expr) => {
  const d = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (d.result.exceptionDetails) throw new Error(JSON.stringify(d.result.exceptionDetails).slice(0, 300));
  return d.result.result.value;
};
const shot = async (name) => { const d = await send('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(path.join(out, name + '.png'), Buffer.from(d.result.data, 'base64')); };

await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url: page });
await sleep(3000);
check('page loaded', await js('typeof UI === "object" && typeof Profile === "object"'));
await js(`Store.settings.syncServer = ${JSON.stringify(api)}; Store.settings.setTab = 'profile'; UI.S.auth = 'register'; UI.A.tab('set'); true`);
await sleep(800);
await shot('web_profile_register');

const noAgree = await js(`Profile.register('web@example.com', 'Проверка', 'пароль-надёжный', false).then(function () { return 'ok'; }, function (e) { return e.message; })`);
check('registration needs consent', /согласие/.test(noAgree), noAgree);
// вход в Spotify и Яндекс «выполнен» на этом устройстве
await js(`window.__mockLogins = { spotify: true, yandex: true }; true`);
const reg = await js(`Profile.register('web@example.com', 'Проверка', 'пароль-надёжный', true).then(function () { return JSON.stringify({ user: Profile.state.user, services: Profile.state.services }); }, function (e) { return 'ERR ' + e.message; })`);
check('register from the app', /"email":"web@example.com"/.test(reg), reg);
const sv = JSON.parse(reg.startsWith('ERR') ? '{}' : reg).services || {};
check('services synced as «activated»', sv.spotify && sv.spotify.active && sv.yandex && sv.yandex.active && !(sv.vk && sv.vk.active), JSON.stringify(sv));
await js(`UI.render(); true`); await sleep(600);
await shot('web_profile_signed_in');
await js(`UI.A.tab('apps'); true`); await sleep(600);
await shot('web_apps_status');
check('services screen shows «login done»', await js(`document.querySelectorAll('.stat.ok').length === 2`));

await js(`Profile.logout().then(function () { return true; })`);
check('logout', await js('!Profile.signedIn()'));
const login = await js(`Profile.login('WEB@example.com', 'пароль-надёжный').then(function () { return Profile.state.user && Profile.state.user.name; }, function (e) { return 'ERR ' + e.message; })`);
check('login again', login === 'Проверка', login);
const bad = await js(`(Profile.forget(), Profile.login('web@example.com', 'неверный').then(function () { return 'ok'; }, function (e) { return e.message; }))`);
check('wrong password is refused', /Неверная/.test(bad), bad);
await js(`Profile.login('web@example.com', 'пароль-надёжный').then(function () { return true; })`);
const del = await js(`Profile.remove('пароль-надёжный').then(function () { return Profile.signedIn() ? 'still' : 'gone'; }, function (e) { return 'ERR ' + e.message; })`);
check('delete profile from the app', del === 'gone', del);

ws.close();
console.log(failed ? `FAILED: ${failed}` : 'ALL PASSED');
process.exit(failed ? 1 : 0);
