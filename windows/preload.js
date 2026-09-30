// Мост между страницей (папка web) и Windows: window.ElectronNative
'use strict';
const { contextBridge, ipcRenderer } = require('electron');

const versionArg = process.argv.find((a) => a.startsWith('--muz-version='));

contextBridge.exposeInMainWorld('ElectronNative', {
  version: versionArg ? versionArg.split('=')[1] : '2.3',
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
  // 2.4: события (браузер, загрузка обновления), обновление, браузер внутри программы
  onEvent: (fn) => ipcRenderer.on('nb-event', (e, name, payload) => fn(name, payload)),
  installUpdate: (url, name) => ipcRenderer.send('installUpdate', url, name),
  browserOpen: (url, rect) => ipcRenderer.send('browserOpen', url, rect),
  browserBounds: (rect) => ipcRenderer.send('browserBounds', rect),
  browserNav: (action) => ipcRenderer.send('browserNav', action),
  browserClose: () => ipcRenderer.send('browserClose')
});
