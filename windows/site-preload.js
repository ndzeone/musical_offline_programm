// Страница площадки (вкладка внутри программы): помощник сообщает программе, что играет.
'use strict';
const { contextBridge, ipcRenderer, webFrame } = require('electron');

contextBridge.exposeInMainWorld('MuzykaSite', {
  post: (s) => { if (typeof s === 'string' && s.length < 65536) ipcRenderer.send('site-msg', s); }
});

// Помощник ставим до скриптов сайта, чтобы он видел, как сайт включает звук
try {
  const js = ipcRenderer.sendSync('site-agent');
  if (js) webFrame.executeJavaScript(js).catch(() => {});
} catch (e) {}
