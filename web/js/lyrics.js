/* Текст песни: разбор LRC и поиск в двух базах (lrclib и NetEase) с повторами при сбоях связи.
   Сам текст скачивается во время работы программы — в коде его нет. */
(function () {
  'use strict';

  var Lyrics = {};

  // Разбор текста: [мм:сс.xx] строки → синхронный текст, иначе — обычный
  Lyrics.parse = function (input) {
    if (!input) return null;
    var text = String(input).replace(/^﻿/, '').normalize('NFC');
    var timeRe = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/g;
    var offset = 0, synced = false, raw = [];
    text.split(/\r?\n/).forEach(function (line) {
      var off = /^\s*\[offset:\s*([+-]?\d+)\s*\]/i.exec(line);
      if (off) { offset = (+off[1]) / 1000; return; }
      var tags = [], m;
      timeRe.lastIndex = 0;
      while ((m = timeRe.exec(line))) tags.push(m);
      if (tags.length) {
        synced = true;
        var t = line.replace(/\[[^\]]*\]/g, '').replace(/<\d+:\d+(?:[.:]\d+)?>/g, '').trim();
        tags.forEach(function (tg) {
          raw.push({ time: (+tg[1]) * 60 + parseFloat(tg[2].replace(':', '.')) - offset, text: t });
        });
      } else if (!/^\s*\[[a-zA-Z#]+:.*\]\s*$/.test(line)) {
        raw.push({ time: null, text: line.trim() });
      }
    });
    var out;
    if (synced) {
      out = raw.filter(function (r) { return r.time != null; }).sort(function (a, b) { return a.time - b.time; });
    } else {
      out = [];
      raw.forEach(function (r) { if (!(r.text === '' && (out.length === 0 || out[out.length - 1].text === ''))) out.push({ time: 0, text: r.text }); });
      while (out.length && out[out.length - 1].text === '') out.pop();
    }
    if (!out.some(function (l) { return l.text; })) return null;
    return { synced: synced, lines: out.map(function (l, i) { return { id: i, time: l.time, text: l.text }; }) };
  };

  // Текст без тайминга раскладываем по длине песни
  Lyrics.estimate = function (ly, duration) {
    if (!ly || ly.synced) return ly;
    var d = duration > 0 ? duration : 180, start = d * 0.07, end = d * 0.93, n = Math.max(1, ly.lines.length);
    return { synced: false, lines: ly.lines.map(function (l, i) { return { id: i, time: start + (end - start) * i / n, text: l.text }; }) };
  };

  // Номер текущей строки и сколько букв уже «пропето»
  Lyrics.frame = function (ly, t) {
    if (!ly || !ly.lines.length) return null;
    var L = ly.lines, lo = 0, hi = L.length - 1, idx = -1;
    while (lo <= hi) {
      var mid = (lo + hi) >> 1;
      if (L[mid].time <= t) { idx = mid; lo = mid + 1; } else hi = mid - 1;
    }
    var sung = 0;
    if (idx >= 0 && ly.synced) {
      var txt = L[idx].text || '...', start = L[idx].time, end = idx + 1 < L.length ? L[idx + 1].time : start + 5;
      var dur = Math.min(Math.max(end - start, 0.3), 10), p = Math.min(1, Math.max(0, (t - start) / (dur * 0.85)));
      sung = Math.round(p * Array.from(txt).length);
    }
    return { index: idx, sung: sung };
  };

  // ---------- поиск ----------
  function get(url, headers, attempts) {
    attempts = attempts || 3;
    var n = 0;
    function once() {
      n++;
      return NB.http(url, headers).then(function (r) {
        if ((r.status === 429 || r.status >= 500 || r.status === 0) && n < attempts) {
          return new Promise(function (res) { setTimeout(res, 700 * Math.pow(2.4, n - 1)); }).then(once);
        }
        return r;
      });
    }
    return once();
  }
  var UA = { 'User-Agent': 'MuzykaOffline/2.3 (https://lrclib.net)' };

  function lrclibSearch(params) {
    var q = Object.keys(params).map(function (k) { return k + '=' + encodeURIComponent(params[k]); }).join('&');
    return get('https://lrclib.net/api/search?' + q, UA).then(function (r) {
      if (r.status !== 200) return { failed: r.status === 0, list: [] };
      var d = []; try { d = JSON.parse(r.body); } catch (e) {}
      return {
        failed: false, list: (d || []).filter(function (x) { return x.syncedLyrics || x.plainLyrics; }).map(function (x) {
          return { id: 'lrclib-' + x.id, provider: 'lrclib', track: x.trackName, artist: x.artistName, duration: x.duration, synced: x.syncedLyrics, plain: x.plainLyrics };
        })
      };
    });
  }

  function neteaseSearch(q) {
    var h = { 'Referer': 'https://music.163.com/' };
    return get('https://music.163.com/api/search/get?s=' + encodeURIComponent(q) + '&type=1&limit=8', h, 2).then(function (r) {
      if (r.status !== 200) return { failed: r.status === 0, songs: [] };
      var d = {}; try { d = JSON.parse(r.body); } catch (e) {}
      return { failed: false, songs: (d.result && d.result.songs) || [] };
    });
  }
  function neteaseLyric(song) {
    return get('https://music.163.com/api/song/lyric?id=' + song.id + '&lv=1&tv=-1', { 'Referer': 'https://music.163.com/' }, 2).then(function (r) {
      if (r.status !== 200) return null;
      var d = {}; try { d = JSON.parse(r.body); } catch (e) {}
      var raw = d.lrc && d.lrc.lyric;
      if (!raw || raw.indexOf('纯音乐') >= 0) return null;
      // строки с авторами на китайском («作词 : …») — не текст песни
      var text = raw.split(/\r?\n/).filter(function (l) { return !(/^\s*(\[[^\]]*\])+\s*[^\s:：]{1,12}\s*[:：]/.test(l) && /[一-鿿]/.test(l)); }).join('\n');
      var p = Lyrics.parse(text);
      if (!p || p.lines.filter(function (l) { return l.text; }).length < 4) return null;
      var artist = (song.artists || []).map(function (a) { return a.name; }).join(', ');
      return { id: 'netease-' + song.id, provider: 'NetEase', track: song.name, artist: artist, duration: song.duration ? song.duration / 1000 : null,
               synced: p.synced ? text : null, plain: p.synced ? null : text };
    });
  }

  function score(r, artist, title, duration) {
    var ts = U.similarity(r.track, title);
    var as = artist ? Math.max(U.similarity(r.artist, artist), U.similarity(r.artist, U.mainArtist(artist))) : 0.5;
    var s = (r.synced ? 100 : 0) + ts * 60 + as * 30;
    if (duration > 0 && r.duration > 0) s -= Math.min(45, Math.abs(r.duration - duration) * 2.5);
    if (r.provider === 'lrclib') s += 3;
    return s;
  }

  // Ищет текст: сначала lrclib, потом NetEase. Бросает 'network', если все источники недоступны.
  Lyrics.find = function (artist, title, duration, query) {
    var bare = U.bareTitle(title), main = U.mainArtist(artist);
    var both = [main, bare].filter(Boolean).join(' ');
    var fails = [], list = [];
    var p;
    if (query) {
      p = Promise.all([lrclibSearch({ q: query }), neteaseSearch(query)]).then(function (r) {
        fails.push(r[0].failed, r[1].failed);
        list = r[0].list;
        return Promise.all(r[1].songs.slice(0, 3).map(neteaseLyric)).then(function (x) { list = list.concat(x.filter(Boolean)); });
      });
    } else {
      p = Promise.all([lrclibSearch({ track_name: bare, artist_name: main }), lrclibSearch({ q: both })]).then(function (r) {
        fails.push(r[0].failed, r[1].failed);
        list = r[0].list.concat(r[1].list);
        var good = list.some(function (x) { return x.synced && U.similarity(x.track, bare) >= 0.8; });
        if (good) return;
        return neteaseSearch(both).then(function (n) {
          fails.push(n.failed);
          var fit = n.songs.filter(function (s) { return U.similarity(s.name, bare) >= 0.6; }).slice(0, 3);
          return Promise.all(fit.map(neteaseLyric)).then(function (x) { list = list.concat(x.filter(Boolean)); });
        });
      });
    }
    return p.then(function () {
      var seen = {};
      list = list.filter(function (x) { if (seen[x.id]) return false; seen[x.id] = 1; return true; });
      list.forEach(function (x) { x.score = score(x, artist, title, duration); });
      if (!query) list = list.filter(function (x) { return U.similarity(x.track, bare) >= 0.45; });
      list.sort(function (a, b) { return b.score - a.score; });
      if (!list.length && fails.length && fails.every(Boolean)) throw new Error('network');
      return list;
    });
  };

  window.Lyrics = Lyrics;
})();
