// Настройки и библиотека: запись целиком во временный файл и подмена одним шагом,
// запасная копия раз в 10 минут, испорченный файл откладывается в сторону (как на Android и Mac).
'use strict';
const fs = require('fs');
const path = require('path');

function safe(name) {
  const s = String(name || '').replace(/[^A-Za-z0-9._-]/g, '_');
  return s || 'data.json';
}
function valid(text) {
  if (!text || !text.trim()) return false;
  try { JSON.parse(text); return true; } catch (e) { return false; }
}
function readText(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch (e) { return null; }
}

function read(dir, name) {
  const f = path.join(dir, safe(name)), bak = f + '.bak';
  const s = readText(f);
  if (valid(s)) return s;
  if (s && s.trim()) {
    try { fs.renameSync(f, f + '.broken-' + Date.now()); } catch (e) {}
  }
  const b = readText(bak);
  return valid(b) ? b : '';
}

function write(dir, name, text) {
  if (typeof text !== 'string') return false;
  fs.mkdirSync(dir, { recursive: true });
  const f = path.join(dir, safe(name)), tmp = f + '.tmp', bak = f + '.bak';
  try {
    const fd = fs.openSync(tmp, 'w');
    fs.writeSync(fd, text, null, 'utf8');
    fs.fsyncSync(fd);
    fs.closeSync(fd);
  } catch (e) { return false; }
  let oldBackup = true;
  try { oldBackup = Date.now() - fs.statSync(bak).mtimeMs > 10 * 60 * 1000; } catch (e) {}
  if (oldBackup && valid(readText(f))) {
    try { fs.copyFileSync(f, bak); } catch (e) {}
  }
  try { fs.renameSync(tmp, f); return true; } catch (e) {
    try { fs.writeFileSync(f, text, 'utf8'); return true; } catch (e2) { return false; }
  }
}

module.exports = { read, write, valid };
