/* Обложки: из самого файла, по ссылке на трек (Spotify, SoundCloud), поиском Яндекс Музыки.
   Если обложки нет — спокойная заглушка с нотой. */
(function () {
  'use strict';

  var mem = {};            // картинки из файлов (data:), только в памяти
  var memOrder = [];
  var pending = {};
  var phCache = {};

  var GRADS = [['#7b2ff7', '#f72f8c'], ['#ff5f6d', '#ffc371'], ['#11998e', '#38ef7d'], ['#396afc', '#2948ff'],
               ['#fc466b', '#3f5efb'], ['#f7971e', '#ffd200'], ['#8e2de2', '#4a00e0'], ['#ee0979', '#ff6a00'],
               ['#00c6ff', '#0072ff'], ['#da22ff', '#9733ee'], ['#ff758c', '#ff7eb3'], ['#43cea2', '#185a9d']];

  function darken(hex) {
    var n = parseInt(hex.slice(1), 16), r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
    return 'rgb(' + Math.round(r * 0.42 + 15) + ',' + Math.round(g * 0.42 + 15) + ',' + Math.round(b * 0.42 + 20) + ')';
  }

  var Art = {
    // Заглушка: тёмный градиент и нота
    placeholder: function (seed) {
      var k = String(seed || '');
      if (phCache[k]) return phCache[k];
      var c = document.createElement('canvas');
      c.width = c.height = 160;
      var x = c.getContext('2d');
      var gr = GRADS[U.hash(k) % GRADS.length];
      var g = x.createLinearGradient(0, 160, 160, 0);
      g.addColorStop(0, darken(gr[0])); g.addColorStop(1, darken(gr[1]));
      x.fillStyle = g; x.fillRect(0, 0, 160, 160);
      x.fillStyle = 'rgba(255,255,255,0.32)';
      x.beginPath(); x.ellipse(62, 108, 15, 11, -0.35, 0, Math.PI * 2); x.fill();
      x.beginPath(); x.ellipse(104, 98, 15, 11, -0.35, 0, Math.PI * 2); x.fill();
      x.fillRect(73, 50, 6, 58); x.fillRect(115, 40, 6, 58);
      x.beginPath(); x.moveTo(73, 50); x.lineTo(121, 40); x.lineTo(121, 55); x.lineTo(73, 65); x.closePath(); x.fill();
      var url = c.toDataURL('image/png');
      phCache[k] = url;
      return url;
    },

    keyOf: function (t) {
      if (!t) return '';
      if (t.source && t.source.file) return 'file:' + t.source.file.path;
      return U.webKey(t.artist || '', t.title || '');
    },

    // Сразу известная картинка (или null) — без ожидания
    known: function (t) {
      if (!t) return null;
      if (t.art) return t.art;
      var path = t.source && t.source.file && t.source.file.path;
      if (path && mem[path]) return mem[path];
      if (t.artURL) return t.artURL;
      return Cache.get('art:' + Art.keyOf(t));
    },

    // Найти картинку: из файла → по ссылке → поиском. Возвращает адрес или null.
    resolve: function (t) {
      var k = Art.keyOf(t);
      if (!k) return Promise.resolve(null);
      var known = Art.known(t);
      if (known) return Promise.resolve(known);
      if (pending[k]) return pending[k];
      var path = t.source && t.source.file && t.source.file.path;
      var p = (path ? NB.embeddedArt(path).then(function (a) {
        if (a) { remember(path, a); return a; }
        return online(t);
      }) : online(t)).then(function (u) {
        delete pending[k];
        if (u && u.indexOf('data:') !== 0) Cache.set('art:' + k, u);
        return u;
      }, function () { delete pending[k]; return null; });
      pending[k] = p;
      return p;
    },

    // Значок площадки: на Android — иконка установленного приложения, иначе — значок сайта
    platformIcon: function (id) {
      var pl = PLATFORMS[id];
      if (!pl) return null;
      var c = Cache.get('picon:' + id);
      if (c) return c;
      if (NB.kind === 'android') {
        var a = NB.appIcon(pl.pkg);
        if (a) { Cache.set('picon:' + id, a); return a; }
      }
      return null;
    }
  };

  function remember(path, data) {
    mem[path] = data;
    memOrder.push(path);
    if (memOrder.length > 300) delete mem[memOrder.shift()];
  }

  function online(t) {
    var link = t.source && t.source.web && t.source.web.link;
    var p = Promise.resolve(null);
    if (link && /spotify\.com/.test(link)) p = oembed('https://open.spotify.com/oembed?url=' + encodeURIComponent(link));
    else if (link && /soundcloud\.com/.test(link)) p = oembed('https://soundcloud.com/oembed?format=json&url=' + encodeURIComponent(link));
    return p.then(function (u) { return u || yandex(t.title, t.artist); });
  }

  function oembed(url) {
    return NB.http(url, {}).then(function (r) {
      if (r.status !== 200) return null;
      try { return JSON.parse(r.body).thumbnail_url || null; } catch (e) { return null; }
    });
  }

  // Поиск Яндекс Музыки: у русской музыки обложки находятся почти всегда
  function yandex(title, artist) {
    var bare = U.bareTitle(title), main = U.mainArtist(artist);
    if (!bare) return Promise.resolve(null);
    var q = [main, bare].filter(Boolean).join(' ');
    return NB.http('https://api.music.yandex.net/search?type=track&page=0&text=' + encodeURIComponent(q), {}).then(function (r) {
      if (r.status !== 200) return null;
      var d; try { d = JSON.parse(r.body); } catch (e) { return null; }
      var res = (d.result && d.result.tracks && d.result.tracks.results) || [];
      for (var i = 0; i < res.length; i++) {
        var tr = res[i], names = (tr.artists || []).map(function (a) { return a.name; }).join(', ');
        if (U.similarity(tr.title, bare) >= 0.8 && (!main || U.similarity(names, main) >= 0.5 || U.similarity(names, artist) >= 0.5)) {
          var cov = tr.coverUri || (tr.albums && tr.albums[0] && tr.albums[0].coverUri);
          if (cov) return 'https://' + cov.replace('%%', '400x400');
        }
      }
      return null;
    });
  }

  // Цвета обложки для фона «Цвета обложки» (только если картинку можно прочитать)
  Art.palette = function (src) {
    return new Promise(function (res) {
      if (!src) return res(null);
      var img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = function () {
        try {
          var c = document.createElement('canvas'); c.width = c.height = 8;
          var x = c.getContext('2d'); x.drawImage(img, 0, 0, 8, 8);
          var d = x.getImageData(0, 0, 8, 8).data, cols = [];
          for (var i = 0; i < 64; i++) {
            var r = d[i * 4], g = d[i * 4 + 1], b = d[i * 4 + 2], mx = Math.max(r, g, b), mn = Math.min(r, g, b);
            cols.push({ c: [r, g, b], s: (mx ? (mx - mn) / mx : 0) * 0.75 + mx / 255 * 0.25 });
          }
          cols.sort(function (a, b) { return b.s - a.s; });
          var out = [];
          cols.forEach(function (o) {
            if (out.length < 4 && out.every(function (p) { return Math.abs(p[0] - o.c[0]) + Math.abs(p[1] - o.c[1]) + Math.abs(p[2] - o.c[2]) > 90; })) out.push(o.c);
          });
          res(out.map(function (c) {
            var m = Math.max(c[0], c[1], c[2], 1), k = m < 150 ? 150 / m : 1;
            return 'rgb(' + Math.min(255, c[0] * k | 0) + ',' + Math.min(255, c[1] * k | 0) + ',' + Math.min(255, c[2] * k | 0) + ')';
          }));
        } catch (e) { res(null); }
      };
      img.onerror = function () { res(null); };
      img.src = src;
    });
  };

  window.Art = Art;
})();
