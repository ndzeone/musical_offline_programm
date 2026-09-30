// «Музыка в офлайн» для Windows: окно с общим интерфейсом (папка web) и доступ к файлам компьютера.
'use strict';
const { app, BrowserWindow, WebContentsView, protocol, ipcMain, dialog, shell, net, nativeImage, Menu } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const { Readable } = require('stream');
const Files = require('./files');

const WEB = app.isPackaged ? path.join(process.resourcesPath, 'web') : path.join(__dirname, 'web');
const WEB_ROOT = fs.existsSync(WEB) ? WEB : path.join(__dirname, '..', 'web');
const DATA = path.join(app.getPath('userData'), 'data');
const SNAPSHOT = process.env.MUZ_SNAPSHOT || '';        // для проверки на сборочном сервере
const AUDIO = /\.(mp3|m4a|aac|flac|wav|ogg|oga|opus|wma|aiff?|alac|webm)$/i;

protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true, corsEnabled: true } }
]);

if (!SNAPSHOT && !app.requestSingleInstanceLock()) app.quit();

let win = null;
let pendingWrites = 0;

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf', '.otf': 'font/otf',
  '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4', '.aac': 'audio/aac', '.flac': 'audio/flac', '.wav': 'audio/wav',
  '.ogg': 'audio/ogg', '.oga': 'audio/ogg', '.opus': 'audio/ogg', '.webm': 'audio/webm', '.wma': 'audio/x-ms-wma', '.aif': 'audio/aiff', '.aiff': 'audio/aiff'
};

// app://local/… — страница; app://local/media/<путь> — свой музыкальный файл, с поддержкой перемотки
function serve(request) {
  const url = new URL(request.url);
  let p = decodeURIComponent(url.pathname);
  if (p.startsWith('/media/')) return serveMedia(p.slice(7), request.headers.get('range'));
  if (p === '/' || p === '') p = '/index.html';
  const file = path.normalize(path.join(WEB_ROOT, p));
  if (!file.startsWith(WEB_ROOT)) return new Response('', { status: 403 });
  try {
    const data = fs.readFileSync(file);
    return new Response(data, { status: 200, headers: { 'content-type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream', 'cache-control': 'no-cache' } });
  } catch (e) {
    return new Response('', { status: 404 });
  }
}

function serveMedia(file, range) {
  let st;
  try { st = fs.statSync(file); } catch (e) { return new Response('', { status: 404 }); }
  if (!st.isFile()) return new Response('', { status: 404 });
  const type = MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
  const size = st.size;
  let start = 0, end = size - 1, status = 200;
  const m = range && /bytes=(\d*)-(\d*)/.exec(range);
  if (m) {
    if (m[1] === '' && m[2] !== '') { start = Math.max(0, size - Number(m[2])); }
    else { start = Number(m[1] || 0); if (m[2] !== '') end = Math.min(size - 1, Number(m[2])); }
    if (start >= size) return new Response('', { status: 416, headers: { 'content-range': 'bytes */' + size } });
    status = 206;
  }
  const headers = { 'content-type': type, 'accept-ranges': 'bytes', 'content-length': String(end - start + 1) };
  if (status === 206) headers['content-range'] = 'bytes ' + start + '-' + end + '/' + size;
  const stream = Readable.toWeb(fs.createReadStream(file, { start, end }));
  return new Response(stream, { status, headers });
}

// ---------- окно: размер и место запоминаются ----------
function loadBounds() {
  try {
    const b = JSON.parse(fs.readFileSync(path.join(DATA, 'window.json'), 'utf8'));
    if (b && b.width > 300 && b.height > 400) return b;
  } catch (e) {}
  return { width: 1280, height: 800 };
}
function saveBounds() {
  if (!win || win.isDestroyed()) return;
  const b = win.getNormalBounds();
  Files.write(DATA, 'window.json', JSON.stringify({ x: b.x, y: b.y, width: b.width, height: b.height, maximized: win.isMaximized() }));
}

function createWindow() {
  const b = SNAPSHOT ? { width: 1280, height: 800 } : loadBounds();
  win = new BrowserWindow({
    x: b.x, y: b.y, width: b.width, height: b.height, minWidth: 380, minHeight: 560,
    backgroundColor: '#140A22', title: 'Музыка в офлайн', show: false, autoHideMenuBar: true,
    icon: path.join(__dirname, 'build', 'icon.ico'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true, sandbox: false, nodeIntegration: false,
      autoplayPolicy: 'no-user-gesture-required', spellcheck: false, backgroundThrottling: !SNAPSHOT,
      additionalArguments: ['--muz-version=' + app.getVersion()]
    }
  });
  Menu.setApplicationMenu(null);
  if (b.maximized) win.maximize();
  win.once('ready-to-show', () => win.show());
  win.webContents.setWindowOpenHandler(({ url }) => { shell.openExternal(url); return { action: 'deny' }; });
  win.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('app://')) { e.preventDefault(); shell.openExternal(url); } });
  win.webContents.on('console-message', (e, level, message, line, source) => {
    if (level >= 2) console.log('[web]', message, source + ':' + line);
  });

  // Перед закрытием сохраняем всё (плейлисты, место в треке, размер окна)
  let closing = false;
  win.on('close', (e) => {
    if (closing) return;
    e.preventDefault();
    closing = true;
    saveBounds();
    const done = () => { const t0 = Date.now(); const wait = () => (pendingWrites > 0 && Date.now() - t0 < 2000) ? setTimeout(wait, 50) : win.destroy(); setTimeout(wait, 150); };
    win.webContents.executeJavaScript('window.__flush && window.__flush()').then(done, done);
  });
  win.on('closed', () => { win = null; });
  win.loadURL('app://local/index.html');
  if (SNAPSHOT) runSnapshots();
}

// ---------- команды страницы ----------
ipcMain.handle('http', async (e, url, headers) => {
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 15000);
    const r = await net.fetch(url, { headers: Object.assign({ 'User-Agent': 'MuzykaOffline/' + app.getVersion() + ' (Windows)' }, headers || {}), signal: ctrl.signal });
    const body = await r.text();
    clearTimeout(t);
    return { status: r.status, body };
  } catch (err) {
    return { status: 0, body: '' };
  }
});
ipcMain.handle('readFile', (e, name) => Files.read(DATA, name));
ipcMain.handle('writeFile', (e, name, text) => {
  pendingWrites++;
  try { return Files.write(DATA, name, text); } finally { pendingWrites--; }
});

async function tagsOf(file) {
  const t = { uri: file, title: '', artist: '', album: '', duration: 0 };
  try {
    const mm = require('music-metadata');
    const m = await mm.parseFile(file, { duration: false, skipCovers: true });
    const c = m.common || {};
    t.title = c.title || ''; t.artist = c.artist || (c.artists || []).join(', ') || ''; t.album = c.album || '';
    t.duration = (m.format && m.format.duration) || 0;
  } catch (err) {}
  if (!t.title) {
    // «Исполнитель - Название» в имени файла
    const name = path.basename(file).replace(/\.[^.]+$/, ''), k = name.indexOf(' - ');
    if (k > 0 && !t.artist) { t.artist = name.slice(0, k).trim(); t.title = name.slice(k + 3).trim(); } else t.title = name;
  }
  return t;
}
async function tagsAll(list) {
  const out = [];
  for (const f of list) out.push(await tagsOf(f));
  return out;
}
ipcMain.handle('pickMusic', async () => {
  const r = await dialog.showOpenDialog(win, { title: 'Выбери музыку', properties: ['openFile', 'multiSelections'],
    filters: [{ name: 'Музыка', extensions: ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma', 'aiff', 'webm'] }] });
  if (r.canceled) return { ok: false, tracks: [] };
  return { ok: true, tracks: await tagsAll(r.filePaths) };
});
ipcMain.handle('pickFolder', async () => {
  const r = await dialog.showOpenDialog(win, { title: 'Папка с музыкой', properties: ['openDirectory'] });
  if (r.canceled || !r.filePaths[0]) return { ok: false, tracks: [] };
  const found = [];
  (function walk(dir, depth) {
    if (depth > 8 || found.length > 5000) return;
    let items = [];
    try { items = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }
    for (const it of items) {
      const p = path.join(dir, it.name);
      if (it.isDirectory()) walk(p, depth + 1);
      else if (AUDIO.test(it.name)) found.push(p);
    }
  })(r.filePaths[0], 0);
  found.sort((a, b) => a.localeCompare(b, 'ru'));
  return { ok: true, tracks: await tagsAll(found) };
});
ipcMain.handle('exportText', async (e, name, text) => {
  const r = await dialog.showSaveDialog(win, { title: 'Сохранить копию библиотеки', defaultPath: path.join(app.getPath('documents'), name || 'библиотека.json'),
    filters: [{ name: 'JSON', extensions: ['json'] }] });
  if (r.canceled || !r.filePath) return { ok: false };
  try { fs.writeFileSync(r.filePath, text, 'utf8'); return { ok: true }; } catch (err) { return { ok: false }; }
});
ipcMain.handle('importText', async () => {
  const r = await dialog.showOpenDialog(win, { title: 'Загрузить копию библиотеки', properties: ['openFile'], filters: [{ name: 'JSON', extensions: ['json'] }] });
  if (r.canceled || !r.filePaths[0]) return null;
  try { return { text: fs.readFileSync(r.filePaths[0], 'utf8') }; } catch (err) { return null; }
});
ipcMain.handle('embeddedArt', async (e, file) => {
  try {
    if (!file || !fs.existsSync(file)) return null;
    const mm = require('music-metadata');
    const m = await mm.parseFile(file, { duration: false });
    const pic = m.common && m.common.picture && m.common.picture[0];
    if (!pic) return null;
    let img = nativeImage.createFromBuffer(Buffer.from(pic.data));
    if (img.isEmpty()) return null;
    const s = img.getSize();
    if (s.width > 400) img = img.resize({ width: 400, quality: 'good' });
    return 'data:image/jpeg;base64,' + img.toJPEG(86).toString('base64');
  } catch (err) {
    return null;
  }
});
ipcMain.handle('openLink', (e, url) => { if (/^https?:\/\//.test(url)) shell.openExternal(url); return true; });
ipcMain.on('ready', () => {});

function sendEvent(name, payload) {
  if (win && !win.isDestroyed()) win.webContents.send('nb-event', name, payload);
}

// ---------- браузер внутри программы: сайт площадки в прямоугольнике страницы ----------
let site = null, siteStart = '';
function siteState(extra) {
  const wc = site.webContents, h = wc.navigationHistory;
  return Object.assign({ url: wc.getURL(), title: wc.getTitle(), canBack: h.canGoBack(), canFwd: h.canGoForward(), loading: wc.isLoading() }, extra || {});
}
function siteBounds(r) {
  if (!site || !r) return;
  site.setBounds({ x: Math.round(r.x || 0), y: Math.round(r.y || 0), width: Math.max(1, Math.round(r.w || 1)), height: Math.max(1, Math.round(r.h || 1)) });
}
function createSite() {
  site = new WebContentsView({ webPreferences: { partition: 'persist:sites', contextIsolation: true, sandbox: true } });
  const wc = site.webContents;
  // сайты видят обычный Chrome
  wc.setUserAgent(wc.getUserAgent().replace(/\s(Electron|muzyka-offline|MuzykaOffline|Музыка в офлайн)\/\S+/gi, ''));
  wc.setWindowOpenHandler(({ url }) => { if (/^https?:/.test(url)) wc.loadURL(url); else shell.openExternal(url); return { action: 'deny' }; });
  wc.on('will-navigate', (e, url) => { if (!/^https?:/.test(url)) { e.preventDefault(); shell.openExternal(url); } });
  const upd = (extra) => sendEvent('browser', siteState(extra));
  wc.on('did-start-loading', () => upd({ loading: true, progress: 0.1 }));
  wc.on('did-stop-loading', () => upd({ loading: false, progress: 1 }));
  wc.on('page-title-updated', () => upd());
  wc.on('did-navigate', () => upd());
  wc.on('did-navigate-in-page', () => upd());
  wc.on('render-process-gone', () => { try { win.contentView.removeChildView(site); } catch (e) {} site = null; sendEvent('browser', { closed: true }); });
}
ipcMain.on('browserOpen', (e, url, rect) => {
  if (!win) return;
  if (!site) createSite();
  win.contentView.addChildView(site);
  siteBounds(rect);
  // тот же сайт уже открыт — показываем как есть (вход и музыка сохраняются)
  if (!(site.webContents.getURL() && url === siteStart)) site.webContents.loadURL(url).catch(() => {});
  siteStart = url;
  sendEvent('browser', siteState());
});
ipcMain.on('browserBounds', (e, rect) => siteBounds(rect));
ipcMain.on('browserNav', (e, action) => {
  if (!site) return;
  const wc = site.webContents, h = wc.navigationHistory;
  if (action === 'back' && h.canGoBack()) h.goBack();
  else if (action === 'forward' && h.canGoForward()) h.goForward();
  else if (action === 'reload') wc.reload();
  else if (action === 'stop') wc.stop();
});
// закрыть = спрятать: страница живёт дальше (если на сайте играет музыка, она не прервётся)
ipcMain.on('browserClose', () => { if (site && win) { try { win.contentView.removeChildView(site); } catch (e) {} } });

// ---------- обновление: скачать установщик и запустить его ----------
async function downloadTo(url, file, onProgress) {
  const r = await net.fetch(url);
  if (!r.ok) throw new Error('HTTP ' + r.status);
  const total = +r.headers.get('content-length') || 0;
  const out = fs.createWriteStream(file);
  const reader = r.body.getReader();
  let done = 0, last = -1;
  for (;;) {
    const { value, done: end } = await reader.read();
    if (end) break;
    if (!out.write(Buffer.from(value))) await new Promise((res) => out.once('drain', res));
    done += value.length;
    const pct = total ? Math.floor(done * 100 / total) : 0;
    if (pct !== last) { last = pct; onProgress(pct / 100); }
  }
  await new Promise((res, rej) => out.end((err) => (err ? rej(err) : res())));
  return done;
}
ipcMain.on('installUpdate', async (e, url, name) => {
  try {
    const dir = path.join(app.getPath('temp'), 'MuzykaOffline-update');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, String(name || 'setup.exe').replace(/[^A-Za-z0-9._-]/g, '_'));
    const size = await downloadTo(url, file, (p) => sendEvent('update', { phase: 'progress', progress: p }));
    if (size < 1000000) throw new Error('файл слишком маленький');
    sendEvent('update', { phase: 'installing' });
    if (SNAPSHOT) { lastUpdateFile = { file, size }; return; }   // проверка на сервере: не запускаем
    // тихая установка поверх и запуск новой версии; сами закрываемся, сохранив всё
    spawn(file, ['/S', '/currentuser', '--updated', '--force-run'], { detached: true, stdio: 'ignore' }).unref();
    setTimeout(() => app.quit(), 800);
  } catch (err) {
    sendEvent('update', { phase: 'error', message: 'Не получилось скачать обновление. Проверь интернет' });
  }
});
let lastUpdateFile = null;

// ---------- проверка на сборочном сервере: снимки экранов и работа плеера ----------
function wavSilence(file, seconds) {
  const rate = 22050, n = rate * seconds, buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8); buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22); buf.writeUInt32LE(rate, 24);
  buf.writeUInt32LE(rate * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.round(Math.sin(i / rate * 2 * Math.PI * 220) * 1200), 44 + i * 2);
  fs.writeFileSync(file, buf);
}
function runSnapshots() {
  const out = SNAPSHOT;
  fs.mkdirSync(out, { recursive: true });
  const report = [];
  const js = (code) => win.webContents.executeJavaScript(code);
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const shot = async (name) => { const img = await win.webContents.capturePage(); fs.writeFileSync(path.join(out, name + '.png'), img.toPNG()); report.push('saved ' + name); };
  win.webContents.once('did-finish-load', async () => {
    try {
      const music = path.join(out, 'music');
      fs.mkdirSync(music, { recursive: true });
      const files = ['Демо Исполнитель - Неоновый вечер.wav', 'Кто-то - Второй трек.wav', 'Ещё кто-то - Третий трек.wav'].map((n) => path.join(music, n));
      files.forEach((f) => wavSilence(f, 12));
      await wait(1500);
      const tracks = await tagsAll(files);
      report.push('tags: ' + JSON.stringify(tracks.map((t) => t.artist + ' — ' + t.title)));
      await js(`(function(){ var st=document.createElement('style'); st.textContent='*{transition:none!important;animation:none!important}'; document.head.appendChild(st);
        UI.S.device = ${JSON.stringify(tracks)}; UI.S.tab='lib'; UI.S.libSeg='device'; UI.render(); return true; })()`);
      await wait(800); await shot('win_library');
      // Играем второй файл: проверяем, что звук идёт и время движется
      await js(`UI.A.playDevice(${JSON.stringify(tracks[1].uri)}); true`);
      await wait(2500);
      const t1 = await js('Player.time()');
      await wait(1500);
      const t2 = await js('Player.time()');
      report.push('play: ' + JSON.stringify({ title: await js('Player.current() && Player.current().title'), t1, t2, playing: await js('Player.playing'), advancing: t2 > t1 }));
      await js('Player.seek(9); true'); await wait(800);
      report.push('seek: ' + (await js('Player.time()')).toFixed(1));
      await js('UI.A.next(); true'); await wait(1200);
      report.push('next: ' + await js('Player.current().title'));
      await js(`UI.S.tab='np'; UI.render(); true`); await wait(1500);
      await shot('win_nowplaying');
      await js('UI.A.fav(); window.__flush(); true'); await wait(600);
      const lib = Files.read(DATA, 'library.json');
      report.push('library saved: ' + (lib.indexOf('Третий трек') >= 0));
      const set = JSON.parse(Files.read(DATA, 'settings.json') || '{}');
      report.push('last saved: ' + JSON.stringify(set.last && { title: set.last.queue[set.last.index].title, pos: set.last.pos }));
      await js(`UI.A.tab('set'); true`); await wait(1200); await shot('win_settings');
      // 2.4: браузер внутри программы
      await js(`UI.A.openLink('https://example.com/'); true`); await wait(6000);
      const br = await js('JSON.stringify(UI.S && window.__brState ? window.__brState() : null)');
      report.push('browser: ' + JSON.stringify(site ? siteState() : null) + ' page: ' + br);
      await shot('win_browser');
      if (site) fs.writeFileSync(path.join(out, 'win_browser_site.png'), (await site.webContents.capturePage()).toPNG());
      await js(`UI.A.brClose(); true`); await wait(500);
      report.push('browser closed: ' + !win.contentView.children.includes(site));
      // 2.4: проверка обновлений (как будто стоит старая версия) и загрузка установщика
      const st = await js(`Updates.check(true, { current: '2.0.0' }).then(function (s) { return JSON.stringify({ s: s, v: Updates.latest && Updates.latest.version, asset: Updates.latest && Updates.latest.asset && Updates.latest.asset.name }); })`);
      report.push('update check: ' + st);
      await js(`UI.A.tab('set'); true`); await wait(800); await shot('win_update_available');
      await js(`UI.A.updInstall(); true`);
      for (let i = 0; i < 120 && !lastUpdateFile; i++) await wait(1000);
      report.push('update downloaded: ' + JSON.stringify(lastUpdateFile) + ' status: ' + await js('Updates.status'));
      await js(`UI.A.theme('kitty'); UI.A.tab('np'); true`); await wait(1500); await shot('win_kitty');
    } catch (err) {
      report.push('ERROR ' + (err && err.stack || err));
    }
    fs.writeFileSync(path.join(out, 'report.txt'), report.join('\n') + '\n');
    console.log(report.join('\n'));
    win.destroy();
    app.exit(0);
    setTimeout(() => process.exit(0), 3000);
  });
}

app.on('second-instance', () => { if (win) { if (win.isMinimized()) win.restore(); win.show(); win.focus(); } });
app.whenReady().then(() => {
  protocol.handle('app', serve);
  createWindow();
});
app.on('window-all-closed', () => app.quit());
