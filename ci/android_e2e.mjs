// Проверка Android-версии на эмуляторе: управляем настоящим приложением через WebView DevTools,
// снимаем экран телефона и проверяем службу плеера (dumpsys). Запуск: node ci/android_e2e.mjs <apk-debug> <out>
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [apk, out] = process.argv.slice(2);
const PKG = 'ru.muzyka.offline.debug';
fs.mkdirSync(out, { recursive: true });
const report = [];
let failed = 0;
const log = (s) => { console.log(s); report.push(s); };
const check = (name, ok, info = '') => { log((ok ? 'PASS ' : 'FAIL ') + name + (info ? ' — ' + info : '')); if (!ok) failed++; };
const sh = (cmd, opts = {}) => execSync(cmd, { encoding: opts.binary ? undefined : 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 << 20, ...opts });
const adb = (args, opts) => sh('adb ' + args, opts);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const shot = (name) => { fs.writeFileSync(path.join(out, name + '.png'), adb('exec-out screencap -p', { binary: true })); log('screenshot ' + name); };

// ---------- DevTools ----------
let ws = null, seq = 0;
const waiting = new Map();
async function connect() {
  if (ws) { try { ws.close(); } catch (e) {} ws = null; }
  for (let i = 0; i < 40; i++) {
    const socks = adb('shell cat /proc/net/unix').split('\n').map((l) => l.trim().split(' ').pop()).filter((s) => s && s.startsWith('@webview_devtools_remote_'));
    const pid = adb(`shell pidof ${PKG}`).trim();
    const sock = socks.find((s) => s.endsWith('_' + pid)) || socks[0];
    if (sock) {
      adb(`forward tcp:9333 localabstract:${sock.slice(1)}`);
      try {
        const pages = await (await fetch('http://127.0.0.1:9333/json')).json();
        const page = pages.find((p) => p.type === 'page' && p.url.includes('appassets'));
        if (page) {
          ws = new WebSocket(page.webSocketDebuggerUrl);
          await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
          ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waiting.has(d.id)) { waiting.get(d.id)(d); waiting.delete(d.id); } };
          return;
        }
      } catch (e) {}
    }
    await sleep(1000);
  }
  throw new Error('WebView DevTools not found');
}
async function js(expr) {
  const id = ++seq;
  const p = new Promise((res) => waiting.set(id, res));
  ws.send(JSON.stringify({ id, method: 'Runtime.evaluate', params: { expression: expr, awaitPromise: true, returnByValue: true } }));
  const d = await p;
  if (d.result && d.result.exceptionDetails) throw new Error('JS: ' + JSON.stringify(d.result.exceptionDetails).slice(0, 400));
  return d.result && d.result.result ? d.result.result.value : undefined;
}
const launch = () => adb(`shell am start -W -n ${PKG}/ru.muzyka.offline.MainActivity`);
const media = () => { try { return adb('shell dumpsys media_session'); } catch (e) { return ''; } };
function ourSession() {
  const d = media();
  const i = d.indexOf('package=' + PKG);
  if (i < 0) return '';
  return d.slice(Math.max(0, d.lastIndexOf('\n', i - 400)), i + 1500);
}

// ---------- сценарий ----------
async function main() {
  adb('shell settings put global window_animation_scale 0');
  adb(`install -r -g ${apk}`);
  adb(`shell pm clear ${PKG}`);
  adb(`shell pm grant ${PKG} android.permission.READ_MEDIA_AUDIO`);
  try { adb(`shell pm grant ${PKG} android.permission.POST_NOTIFICATIONS`); } catch (e) {}
  launch();
  await sleep(6000);
  await connect();
  shot('01_start');
  check('page loaded in Android mode', await js('NB.kind') === 'android');
  const ins = await js('getComputedStyle(document.documentElement).getPropertyValue("--st")');
  check('status bar inset passed to page', parseFloat(ins) > 0, 'top=' + ins);

  await js('UI.A.libDevice(); true');
  await sleep(2500);
  const dev = await js('JSON.stringify(UI.S.device.map(function(t){return t.artist + " — " + t.title + " (" + Math.round(t.duration) + "s)"}))');
  check('music on the phone found (MediaStore)', JSON.parse(dev).length >= 3, dev);
  shot('02_library');

  const uri = await js('UI.S.device.filter(function(t){return /Второй/.test(t.title)})[0].uri');
  await js(`UI.A.playDevice(${JSON.stringify(uri)}); true`);
  await sleep(4000);
  let st = JSON.parse(await js('JSON.stringify(NB.playbackState())'));
  const p1 = st.pos; await sleep(2000);
  let st2 = JSON.parse(await js('JSON.stringify(NB.playbackState())'));
  check('playback started in the service', st.playing && st2.pos > p1 + 1, JSON.stringify(st2));
  check('page shows the playing track', (await js('Player.current().title')).includes('Второй'));
  const art = await js('document.querySelector(".np-cover img") && document.querySelector(".np-cover img").src.slice(0, 22)');
  check('cover from the file tags shown', String(art).startsWith('data:image/jpeg'), String(art));
  check('media session is playing (lock screen / headphones)', /state=PlaybackState \{state=(3|PLAYING)/.test(ourSession()) || /state=3/.test(ourSession()), ourSession().slice(0, 300).replace(/\s+/g, ' '));
  await sleep(1500);
  shot('03_now_playing');

  await js('UI.A.next(); true'); await sleep(2500);
  check('next track', (await js('Player.current().title')).includes('Третий'), await js('Player.current().title'));
  await js('UI.A.prev(); true'); await sleep(2500);
  check('previous track', (await js('Player.current().title')).includes('Второй'), await js('Player.current().title'));
  await js('Player.seek(20); true'); await sleep(1500);
  await js('UI.A.prev(); true'); await sleep(1500);
  const tPrev = await js('Player.time()');
  check('prev after 3 s restarts the song', (await js('Player.current().title')).includes('Второй') && tPrev < 5, 't=' + tPrev);

  // Экран выключен — музыка играет
  adb('shell input keyevent KEYCODE_SLEEP'); await sleep(6000);
  const off = JSON.parse(await js('JSON.stringify(NB.playbackState())'));
  adb('shell input keyevent KEYCODE_WAKEUP'); await sleep(1500);
  adb('shell wm dismiss-keyguard'); await sleep(1500);
  check('keeps playing with the screen off', off.playing && off.pos > tPrev + 4, JSON.stringify(off));

  // Уведомление с кнопками
  adb('shell cmd statusbar expand-notifications'); await sleep(2000);
  shot('04_notification');
  adb('shell cmd statusbar collapse'); await sleep(1000);

  // Пауза на 0:25, сворачиваем, система закрывает приложение → открываем снова
  await js('Player.seek(25); true'); await sleep(1200);
  await js('UI.A.toggle(); true'); await sleep(1500);
  await js('UI.A.fav(); true'); await sleep(500);
  adb('shell input keyevent KEYCODE_HOME'); await sleep(3000);
  adb(`shell am force-stop ${PKG}`); await sleep(1500);
  launch(); await sleep(6000);
  await connect();
  const rs = JSON.parse(await js('JSON.stringify({t: Player.current() && Player.current().title, p: Player.playing, time: Player.time(), fav: Store.playlists[0].items.map(function(i){return i.title})})'));
  check('after restart: same song, paused, same second', rs.t && rs.t.includes('Второй') && !rs.p && Math.abs(rs.time - 25) < 2.5, JSON.stringify(rs));
  check('favorites survived the restart', rs.fav.some((t) => t.includes('Второй')), JSON.stringify(rs.fav));
  shot('05_restored');
  await js('UI.A.toggle(); true'); await sleep(3000);
  const cont = JSON.parse(await js('JSON.stringify(NB.playbackState())'));
  check('continues from the same place', cont.playing && cont.pos > 25, JSON.stringify(cont));
  await js('UI.A.toggle(); true');

  // Экраны
  await js("UI.A.libDevice(); UI.A.libSeg('fav'); true"); await sleep(1500); shot('06_favorites');
  await js("UI.A.tab('set'); true"); await sleep(1500); shot('07_settings');
  await js("UI.A.tab('apps'); true"); await sleep(1500); shot('08_apps');
  await js("UI.A.theme('kitty'); UI.A.tab('np'); true"); await sleep(2500); shot('09_kitty');
  await js("UI.A.theme('neon'); true"); await sleep(2500); shot('10_neon');
  await js("UI.A.theme('minecraft'); UI.A.tab('lib'); true"); await sleep(1000);
  adb('shell settings put system accelerometer_rotation 0');
  adb('shell settings put system user_rotation 1'); await sleep(3000);
  await js("UI.A.tab('np'); true"); await sleep(2000); shot('11_landscape');
  adb('shell settings put system user_rotation 0'); await sleep(2000);

  const errs = adb('logcat -d -s MuzykaWeb:I').split('\n').filter((l) => /ERROR|Uncaught|console.error/.test(l));
  check('no errors in the page', errs.length === 0, errs.slice(0, 5).join(' | '));
  const crash = adb('logcat -d -b crash');
  check('no crashes', !crash.includes(PKG.replace('.debug', '')), crash.slice(0, 500));
}

main().catch((e) => { check('scenario finished', false, String(e && e.stack || e)); }).finally(() => {
  fs.writeFileSync(path.join(out, 'report.txt'), report.join('\n') + '\n');
  try { fs.writeFileSync(path.join(out, 'logcat.txt'), adb('logcat -d -v time')); } catch (e) {}
  console.log(failed ? `FAILED: ${failed}` : 'ALL PASSED');
  process.exit(failed ? 1 : 0);
});
