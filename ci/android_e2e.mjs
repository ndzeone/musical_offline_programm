// Проверка Android-версии на эмуляторе: управляем настоящим приложением через WebView DevTools,
// снимаем экран телефона и проверяем службу плеера (dumpsys). Запуск: node ci/android_e2e.mjs <apk-debug> <out>
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [apk, out, hidden] = process.argv.slice(2);
const PKG = 'ru.muzyka.offline.debug';
fs.mkdirSync(out, { recursive: true });
const report = [];
let failed = 0;
const log = (s) => { console.log(s); report.push(s); };
const check = (name, ok, info = '') => { log((ok ? 'PASS ' : 'FAIL ') + name + (info ? ' — ' + info : '')); if (!ok) failed++; };
const sh = (cmd, opts = {}) => execSync(cmd, { encoding: opts.binary ? undefined : 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 << 20, ...opts });
const adb = (args, opts) => sh('adb ' + args, opts);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const shot = (name) => { try { adb('shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS'); } catch (e) {} fs.writeFileSync(path.join(out, name + '.png'), adb('exec-out screencap -p', { binary: true })); log('screenshot ' + name); };

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

// Маленькая страница «площадки» со звуком: проверяем помощник, «сейчас играет», уведомление
function testSiteURL() {
  const rate = 8000, n = rate * 20, buf = Buffer.alloc(44 + n);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n, 4); buf.write('WAVE', 8); buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22); buf.writeUInt32LE(rate, 24);
  buf.writeUInt32LE(rate, 28); buf.writeUInt16LE(1, 32); buf.writeUInt16LE(8, 34); buf.write('data', 36); buf.writeUInt32LE(n, 40);
  for (let i = 0; i < n; i++) buf[44 + i] = 128 + Math.round(Math.sin(i / rate * 2 * Math.PI * 330) * 20);
  const page = '<!doctype html><meta name="viewport" content="width=device-width"><title>Тестовая песня</title><body style="font:20px sans-serif;padding:20px">' +
    '<h1>Тестовая площадка</h1><audio id="a" controls loop src="data:audio/wav;base64,' + buf.toString('base64') + '"></audio>' +
    '<script>try{navigator.mediaSession.metadata=new MediaMetadata({title:"Тестовая песня",artist:"Проверка CI"})}catch(e){}</script>';
  return 'data:text/html;charset=utf-8;base64,' + Buffer.from(page).toString('base64');
}

// ---------- сценарий ----------
async function main() {
  adb('shell settings put global window_animation_scale 0');
  adb(`install -r -g ${apk}`);
  adb(`shell pm clear ${PKG}`);
  const api = parseInt(adb('shell getprop ro.build.version.sdk').trim(), 10);
  log('Android API ' + api);
  adb(`shell pm grant ${PKG} android.permission.${api >= 33 ? 'READ_MEDIA_AUDIO' : 'READ_EXTERNAL_STORAGE'}`);
  if (api >= 33) try { adb(`shell pm grant ${PKG} android.permission.POST_NOTIFICATIONS`); } catch (e) {}
  launch();
  await sleep(6000);
  await connect();
  await js("UI.A.perf('eco'); true");
  shot('01_start');
  check('page loaded in Android mode', await js('NB.kind') === 'android');
  log('WebView: ' + await js('navigator.userAgent'));
  const vis = await js('JSON.stringify((function(){var r=document.getElementById("screen").getBoundingClientRect(); return {w: Math.round(r.width), h: Math.round(r.height), welcome: !!document.querySelector(".welcome .btn")};})())');
  check('main screen is laid out (not empty)', JSON.parse(vis).h > 200 && JSON.parse(vis).welcome, vis);
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
  await js('Player.seek(0.5); true'); await sleep(400);      // «назад» в первые 3 секунды — предыдущий трек
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
  await js('Player.seek(12); true'); await sleep(1200);
  await js('UI.A.toggle(); true'); await sleep(1500);
  await js('UI.A.fav(); true'); await sleep(500);
  adb('shell input keyevent KEYCODE_HOME'); await sleep(3000);
  adb(`shell am force-stop ${PKG}`); await sleep(1500);
  launch(); await sleep(6000);
  await connect();
  const rs = JSON.parse(await js('JSON.stringify({t: Player.current() && Player.current().title, p: Player.playing, time: Player.time(), fav: Store.playlists[0].items.map(function(i){return i.title})})'));
  check('after restart: same song, paused, same second', rs.t && rs.t.includes('Второй') && !rs.p && Math.abs(rs.time - 12) < 2.5, JSON.stringify(rs));
  check('favorites survived the restart', rs.fav.some((t) => t.includes('Второй')), JSON.stringify(rs.fav));
  shot('05_restored');
  await js('UI.A.toggle(); true'); await sleep(3000);
  const cont = JSON.parse(await js('JSON.stringify(NB.playbackState())'));
  check('continues from the same place', cont.playing && cont.index === 1 && cont.pos > 12, JSON.stringify(cont));
  await js('UI.A.toggle(); true');

  // 2.5: переключатели и кнопки не сбрасывают прокрутку наверх
  await js("UI.A.perf('balanced'); UI.A.setTab('look'); true"); await sleep(1500);
  await js("document.querySelector('#screen .scroll').scrollTop = 420; true"); await sleep(400);
  const sc0 = await js("document.querySelector('#screen .scroll').scrollTop");
  await js("document.querySelector('[data-a=sw][data-x=glass]').click(); true"); await sleep(700);
  const sc1 = await js("document.querySelector('#screen .scroll').scrollTop");
  await js("document.querySelector('[data-a=sw][data-x=glass]').click(); true"); await sleep(500);
  await js("document.querySelector('#mini [data-a=toggle]').click(); true"); await sleep(1500);
  const sc2 = await js("document.querySelector('#screen .scroll').scrollTop");
  await js("document.querySelector('#mini [data-a=toggle]').click(); true"); await sleep(800);
  check('switches and play/pause keep the scroll position', sc0 > 200 && Math.abs(sc1 - sc0) < 5 && Math.abs(sc2 - sc0) < 5, `before=${sc0} switch=${sc1} play=${sc2}`);
  check('60 frames by default', await js('Store.settings.fps === 60 && UI.S.scene.fps === 60'), 'measured ' + await js('UI.S.scene.measured') + ' fps on the emulator');

  // 2.5: у песни нет текста — посередине пластинка с обложкой на наклейке
  await js("UI.A.tab('np'); true");
  let vin = false;
  for (let i = 0; i < 40 && !vin; i++) { await sleep(2000); vin = await js("!!document.querySelector('#np.nolyr .bigvinyl .lbl img')"); }
  check('no lyrics → vinyl with the cover in the middle', vin, await js("UI.S.lyr[Player.now().key] && UI.S.lyr[Player.now().key].status"));
  shot('06b_no_lyrics_vinyl');

  // Экраны
  await js("UI.A.libDevice(); UI.A.libSeg('fav'); true"); await sleep(1500); shot('06_favorites');
  await js("UI.A.tab('set'); true"); await sleep(1500); shot('07_settings');
  await js("UI.A.tab('apps'); true"); await sleep(1500); shot('08_apps');
  await js("UI.A.theme('kitty'); UI.A.tab('np'); true"); await sleep(5000);
  const th = JSON.parse(await js('JSON.stringify({theme: document.body.dataset.theme, np: !!document.getElementById("np")})'));
  check('theme switch (Китти)', th.theme === 'kitty' && th.np, JSON.stringify(th));
  shot('09_kitty');
  await js("UI.A.theme('neon'); true"); await sleep(2500); shot('10_neon');
  await js("UI.A.theme('minecraft'); UI.A.tab('lib'); true"); await sleep(1000);
  adb('shell settings put system accelerometer_rotation 0');
  adb('shell settings put system user_rotation 1'); await sleep(3000);
  await js("UI.A.tab('np'); true"); await sleep(2000); shot('11_landscape');
  adb('shell settings put system user_rotation 0'); await sleep(2000);

  // 2.4: браузер внутри программы
  await js("UI.A.tab('apps'); true"); await sleep(1500);
  await js("UI.A.openLink('https://example.com/'); true"); await sleep(9000);
  const br = JSON.parse(await js('JSON.stringify(window.__brState())'));
  check('in-app browser opened the site', br.open && /Example Domain/i.test(br.title || ''), JSON.stringify(br));
  shot('13_browser');
  await js('window.__back(); true'); await sleep(1500);
  const br2 = JSON.parse(await js('JSON.stringify(window.__brState())'));
  check('back closes the in-app browser', !br2.open, JSON.stringify(br2));

  // 2.5: музыка на сайте площадки — «сейчас играет», уведомление, управление из программы
  await js(`Sites.openURL(${JSON.stringify(testSiteURL())}); true`); await sleep(5000);
  const agent = await js(`NB.siteEval(Sites.active, 'typeof window.__mc + "/" + typeof window.MuzykaSite')`);
  check('site helper runs on the page', agent === 'object/object', String(agent));
  await js(`NB.siteEval(Sites.active, 'document.getElementById("a").play(); "ok"')`);
  let sn = null;
  for (let i = 0; i < 10; i++) { await sleep(1000); sn = JSON.parse(await js('JSON.stringify(Player.now())')); if (sn && sn.kind === 'site') break; }
  // во встроенном браузере Android нет Media Session: название берётся из страницы
  check('music on a site becomes «now playing»', sn && sn.kind === 'site' && sn.title === 'Тестовая песня', JSON.stringify(sn));
  shot('16_site');
  await sleep(1500);
  check('lock screen / notification shows the site track', /Тестовая песня/.test(ourSession()), ourSession().slice(0, 400).replace(/\s+/g, ' '));
  await js('UI.A.minimizeAll(); true'); await sleep(1500);
  const mini = JSON.parse(await js('JSON.stringify({open: Sites.open, tabs: Sites.tabs.length, playing: Player.isPlaying(), kind: Player.now() && Player.now().kind})'));
  check('«minimize all» hides the pages, music keeps playing', !mini.open && mini.tabs >= 2 && mini.playing && mini.kind === 'site', JSON.stringify(mini));
  await js("UI.A.tab('np'); true"); await sleep(2500); shot('17_np_site');
  await js('UI.A.toggle(); true'); await sleep(1500);
  const pz = await js(`NB.siteEval(Sites.current, 'String(document.getElementById("a").paused)')`);
  check('play/pause in the app controls the site', pz === 'true', String(pz));
  await js("UI.A.tab('apps'); true"); await sleep(1500); shot('18_apps_tabs');

  // 2.5: вся музыка телефона — файл в любой папке, которого медиатека ещё не видела
  if (hidden && fs.existsSync(hidden)) {
    adb('shell mkdir -p /sdcard/Documents/Глубокая_папка');
    adb(`push ${hidden} /sdcard/Documents/Глубокая_папка/track4.mp3`);
  }
  const ds = JSON.parse(await js("NB.deepScan().then(function (r) { return JSON.stringify({ ok: r.ok, n: (r.tracks || []).length, titles: (r.tracks || []).map(function (t) { return t.title; }), stats: r.stats }); })"));
  check('deep scan finds music in any folder', ds.ok && ds.titles.some((t) => /Спрятанный/.test(t)), JSON.stringify(ds));
  await js("UI.A.deepScan(); true"); await sleep(8000); shot('19_deep_scan');
  await js("UI.A.closeModal(); UI.A.setTab('profile'); UI.A.authMode('register'); true"); await sleep(1500); shot('20_profile');
  await js("UI.A.setTab('perf'); true"); await sleep(1500); shot('21_perf');

  // 2.4: обновления с GitHub (как будто стоит старая версия) → загрузка → установка Android
  let upd = null;
  for (let i = 0; i < 3; i++) {
    upd = JSON.parse(await js("Updates.check(true, {current: '2.0.0'}).then(function (s) { return JSON.stringify({s: s, v: Updates.latest && Updates.latest.version, asset: Updates.latest && Updates.latest.asset && Updates.latest.asset.name, err: Updates.error}); })"));
    if (upd.s === 'available') break;
    await sleep(8000);
  }
  check('update check finds a newer release on GitHub', upd.s === 'available' && /Android\.apk$/.test(upd.asset || ''), JSON.stringify(upd));
  await js("UI.A.tab('set'); true"); await sleep(1500); shot('14_update_available');
  await js('UI.A.updInstall(); true');
  let top = '';
  for (let i = 0; i < 60; i++) {
    await sleep(1000);
    const d = adb('shell dumpsys activity activities');
    top = (d.match(/(topResumedActivity|mResumedActivity)[^\n]*/) || [''])[0];
    if (/packageinstaller/i.test(top)) break;
  }
  check('downloaded update opens the Android installer', /packageinstaller/i.test(top), top.trim());
  shot('15_installer');
  adb('shell input keyevent KEYCODE_BACK'); await sleep(1500);
  launch(); await sleep(3000);

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
