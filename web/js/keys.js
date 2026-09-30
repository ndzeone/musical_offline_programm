/* Горячие клавиши (компьютер). Любую можно переназначить в «Настройки → Клавиши». */
(function () {
  'use strict';

  // действие → клавиша по умолчанию (как KeyboardEvent.code, с модификаторами «Ctrl+», «Shift+», «Alt+»)
  var ACTIONS = [
    { id: 'toggle', name: 'Пауза / играть', key: 'Space' },
    { id: 'seekBack', name: 'Назад на 5 секунд', key: 'ArrowLeft' },
    { id: 'seekFwd', name: 'Вперёд на 5 секунд', key: 'ArrowRight' },
    { id: 'volUp', name: 'Громче', key: 'ArrowUp', desk: true },
    { id: 'volDown', name: 'Тише', key: 'ArrowDown', desk: true },
    { id: 'next', name: 'Следующий трек', key: 'KeyN' },
    { id: 'prev', name: 'Предыдущий трек', key: 'KeyB' },
    { id: 'repeat', name: 'Повтор', key: 'KeyR' },
    { id: 'shuffle', name: 'Перемешать', key: 'KeyS' },
    { id: 'fav', name: 'В любимые', key: 'KeyF' },
    { id: 'lyrics', name: 'Текст на весь экран', key: 'KeyL' },
    { id: 'library', name: 'Музыка', key: 'KeyE' },
    { id: 'sites', name: 'Площадки', key: 'KeyP' },
    { id: 'minimize', name: 'Свернуть окна площадок', key: 'KeyM' },
    { id: 'settings', name: 'Настройки', key: 'Ctrl+Comma' },
    { id: 'back', name: 'Назад / закрыть окно', key: 'Escape' }
  ];
  var NAMES = {
    Space: 'Пробел', ArrowLeft: '←', ArrowRight: '→', ArrowUp: '↑', ArrowDown: '↓', Escape: 'Esc', Enter: 'Enter', Comma: ',', Period: '.',
    Slash: '/', Backquote: '`', Minus: '−', Equal: '=', BracketLeft: '[', BracketRight: ']', Semicolon: ';', Quote: "'", Backslash: '\\',
    Tab: 'Tab', Backspace: '⌫', Delete: 'Del', Home: 'Home', End: 'End', PageUp: 'PgUp', PageDown: 'PgDn',
    MediaPlayPause: '⏯', MediaTrackNext: '⏭', MediaTrackPrevious: '⏮'
  };
  function nameOf(code) {
    if (!code) return '—';
    return code.split('+').map(function (p) {
      if (p === 'Ctrl') return NB.kind === 'web' && /Mac/.test(navigator.platform) ? '⌘' : 'Ctrl';
      if (p === 'Shift') return 'Shift'; if (p === 'Alt') return 'Alt';
      if (NAMES[p]) return NAMES[p];
      if (/^Key[A-Z]$/.test(p)) return p.slice(3);
      if (/^Digit\d$/.test(p)) return p.slice(5);
      if (/^Numpad/.test(p)) return 'Num ' + p.slice(6);
      return p;
    }).join(' + ');
  }
  function codeOf(e) {
    var c = e.code;
    if (!c || /^(Control|Shift|Alt|Meta)(Left|Right)$/.test(c)) return null;
    var m = (e.ctrlKey || e.metaKey ? 'Ctrl+' : '') + (e.altKey ? 'Alt+' : '') + (e.shiftKey ? 'Shift+' : '');
    return m + c;
  }
  function binds() {
    var own = Store.settings.keys || {}, out = {};
    ACTIONS.forEach(function (a) { out[a.id] = own[a.id] != null ? own[a.id] : a.key; });
    return out;
  }

  var Keys = { ACTIONS: ACTIONS, nameOf: nameOf, binds: binds, capture: null };

  Keys.set = function (id, code) {
    var b = binds();
    // эта клавиша уже занята другим действием — снимаем её там
    Object.keys(b).forEach(function (k) { if (k !== id && b[k] === code) Store.settings.keys[k] = ''; });
    Store.settings.keys[id] = code;
    Store.saveSettings();
  };
  Keys.reset = function () { Store.settings.keys = {}; Store.saveSettings(); };

  function typing(t) { return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable); }

  document.addEventListener('keydown', function (e) {
    // ждём новую клавишу для действия
    if (Keys.capture) {
      e.preventDefault(); e.stopPropagation();
      var c = codeOf(e);
      if (!c) return;
      var id = Keys.capture; Keys.capture = null;
      if (c !== 'Escape') Keys.set(id, c === 'Backspace' ? '' : c);
      if (Keys.onCaptured) Keys.onCaptured();
      return;
    }
    if (typing(e.target) && e.code !== 'Escape') return;
    var code = codeOf(e), b = binds();
    var id = Object.keys(b).filter(function (k) { return b[k] && b[k] === code; })[0];
    if (!id || !Keys.run) return;
    if (Keys.run(id)) e.preventDefault();
  }, true);

  window.Keys = Keys;
})();
