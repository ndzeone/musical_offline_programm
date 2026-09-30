// Мост между страницей (папка web) и Windows: window.ElectronNative
'use strict';
const { contextBridge, ipcRenderer } = require('electron');

const versionArg = process.argv.find((a) => a.startsWith('--muz-version='));

contextBridge.exposeInMainWorld('ElectronNative', {
  version: versionArg ? versionArg.split('=')[1] : '2.5.0',
  http: (url, headers) => ipcRenderer.invoke('http', url, headers || {}),
  readFile: (name) => ipcRenderer.invoke('readFile', name),
  writeFile: (name, text) => ipcRenderer.invoke('writeFile', name, text),
  pickMusic: () => ipcRenderer.invoke('pickMusic'),
  pickFolder: () => ipcRenderer.invoke('pickFolder'),
  exportText: (name, text) => ipcRenderer.invoke('exportText', name, text),
  importText: () => ipcRenderer.invoke('importText'),
  embeddedArt: (p) => ipcRenderer.invoke('embeddedArt', p),
  // Свои файлы играются через app://local/media/… (с перемоткой)
  mediaURL: (uri) => {
    if (!uri || /^(blob:|https?:|data:|app:)/.test(uri)) return uri;
    return 'app://local/media/' + encodeURIComponent(uri);
  },
  openLink: (url) => ipcRenderer.invoke('openLink', url),
  ready: () => ipcRenderer.send('ready'),
  // 2.4: события (вкладки площадок, загрузка обновления), обновление
  onEvent: (fn) => ipcRenderer.on('nb-event', (e, name, payload) => fn(name, payload)),
  installUpdate: (url, name) => ipcRenderer.send('installUpdate', url, name),
  // 2.5: запросы с телом, вся музыка компьютера, вкладки площадок
  request: (url, method, headers, body) => ipcRenderer.invoke('request', url, method, headers || {}, body || ''),
  deepScan: () => ipcRenderer.invoke('deepScan'),
  filesExist: (list) => ipcRenderer.invoke('filesExist', list),
  siteOpen: (tab, url, rect, show) => ipcRenderer.send('siteOpen', tab, url, rect, show),
  siteShow: (tab, rect) => ipcRenderer.send('siteShow', tab, rect),
  siteHide: () => ipcRenderer.send('siteHide'),
  siteClose: (tab) => ipcRenderer.send('siteClose', tab),
  siteBounds: (rect) => ipcRenderer.send('siteBounds', rect),
  siteNav: (tab, action) => ipcRenderer.send('siteNav', tab, action),
  siteLoad: (tab, url) => ipcRenderer.send('siteLoad', tab, url),
  siteEval: (tab, js) => ipcRenderer.invoke('siteEval', tab, js),
  sitePress: (tab, x, y, vw, vh) => ipcRenderer.send('sitePress', tab, x, y, vw, vh),
  siteLogins: () => ipcRenderer.invoke('siteLogins'),
  siteLogout: (platform) => ipcRenderer.invoke('siteLogout', platform)
});
