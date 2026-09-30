/* Живые фоны (как в версии для Mac): Майнкрафт, Сердечки, Кьют-рок, Космос, Синтвейв, Цвета обложки, Ночной океан.
   Частота кадров ограничена настройкой, когда программу не видно — фон не рисуется. */
(function () {
  'use strict';

  // ---------- общее ----------
  function rng(seed) {
    var s = seed >>> 0 || 1;
    return function () { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return (s % 100000) / 100000; };
  }
  function pick(r, arr) { return arr[Math.floor(r() * arr.length) % arr.length]; }
  function lerpC(a, b, t) {
    t = Math.max(0, Math.min(1, t));
    var ar = (a >> 16) & 255, ag = (a >> 8) & 255, ab = a & 255, br = (b >> 16) & 255, bg = (b >> 8) & 255, bb = b & 255;
    return ((ar + (br - ar) * t) << 16) | ((ag + (bg - ag) * t) << 8) | (ab + (bb - ab) * t);
  }
  function hex(c, a) {
    var r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    return a == null ? 'rgb(' + r + ',' + g + ',' + b + ')' : 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')';
  }
  function vgrad(ctx, h, stops) {
    var g = ctx.createLinearGradient(0, 0, 0, h);
    stops.forEach(function (s) { g.addColorStop(s[0], s[1]); });
    return g;
  }
  var Shapes = {
    heart: function (ctx, x, y, s) {
      ctx.beginPath();
      ctx.moveTo(x, y + s * 0.5);
      ctx.bezierCurveTo(x - s * 0.95, y - s * 0.02, x - s * 0.45, y - s * 0.72, x, y - s * 0.2);
      ctx.bezierCurveTo(x + s * 0.45, y - s * 0.72, x + s * 0.95, y - s * 0.02, x, y + s * 0.5);
      ctx.closePath();
    },
    sparkle: function (ctx, x, y, r) {
      ctx.beginPath();
      ctx.moveTo(x, y - r);
      ctx.quadraticCurveTo(x, y, x + r, y); ctx.quadraticCurveTo(x, y, x, y + r);
      ctx.quadraticCurveTo(x, y, x - r, y); ctx.quadraticCurveTo(x, y, x, y - r);
      ctx.closePath();
    },
    bow: function (ctx, x, y, s) {
      ctx.beginPath();
      [-1, 1].forEach(function (k) {
        ctx.moveTo(x, y);
        ctx.bezierCurveTo(x + k * s * 0.15, y - s * 0.35, x + k * s * 0.35, y - s * 0.45, x + k * s * 0.5, y - s * 0.32);
        ctx.bezierCurveTo(x + k * s * 0.62, y - s * 0.15, x + k * s * 0.62, y + s * 0.15, x + k * s * 0.5, y + s * 0.32);
        ctx.bezierCurveTo(x + k * s * 0.35, y + s * 0.45, x + k * s * 0.15, y + s * 0.35, x, y);
      });
      ctx.closePath();
    },
    bolt: function (ctx, x, y, s) {
      var p = [[0.1, 0], [0.55, 0], [0.33, 0.42], [0.62, 0.42], [0.05, 1.15], [0.22, 0.6], [-0.05, 0.6]];
      ctx.beginPath();
      ctx.moveTo(x + p[0][0] * s, y + p[0][1] * s);
      for (var i = 1; i < p.length; i++) ctx.lineTo(x + p[i][0] * s, y + p[i][1] * s);
      ctx.closePath();
    }
  };

  // Плавная «псевдо-музыка», когда настоящий звук недоступен (музыка других приложений)
  function ambient(t, n, binHz) {
    var beat = Math.exp(-((t * 2) % 1) * 5), hat = Math.exp(-((t * 4 + 0.5) % 1) * 8), out = new Float32Array(n);
    for (var i = 1; i < n; i++) {
      var f = i * binHz, lf = Math.log2(Math.max(f, 20));
      var v = Math.max(0, 0.72 - (lf - 5) * 0.055) + 0.12 * Math.sin(t * 1.7 + lf * 1.3) + 0.08 * Math.sin(t * 3.1 + lf * 2.7);
      if (f < 150) v += 0.35 * beat;
      if (f > 3000 && f < 12000) v += 0.15 * hat;
      out[i] = Math.min(1, Math.max(0, v));
    }
    return out;
  }
  function bandsOf(f, n, f0, f1) {
    f0 = f0 || 35; f1 = f1 || 15000;
    var out = new Array(n).fill(0), spec = f.spectrum, cnt = spec ? spec.length : 0;
    if (!f.active || !cnt) return out;
    for (var i = 0; i < n; i++) {
      var a = f0 * Math.pow(f1 / f0, i / n), b = f0 * Math.pow(f1 / f0, (i + 1) / n);
      var b1 = Math.floor(a / f.binHz), b2 = Math.max(b1 + 1, Math.ceil(b / f.binHz)), v = 0;
      for (var k = b1; k < Math.min(b2, cnt); k++) v = Math.max(v, spec[k]);
      out[i] = Math.min(1, v * (0.9 + 0.3 * i / n));
    }
    return out;
  }

  // ---------- Майнкрафт ----------
  var SKY = [
    [0.00, 0x2e3c7a, 0xf2995a, 0.35, 1], [0.10, 0x4a78c8, 0x92b4e6, 0, 0.2], [0.25, 0x4a78c8, 0x8fb0e0, 0, 0],
    [0.66, 0x4a78c8, 0x8fb0e0, 0, 0], [0.78, 0x46407f, 0xee7a4a, 0.25, 1], [0.88, 0x151a3f, 0x39386a, 0.8, 0.2],
    [1.00, 0x0a0e26, 0x232e62, 1, 0]
  ];
  function skyAt(p) {
    p = Math.max(0, Math.min(1, p));
    for (var i = 1; i < SKY.length; i++) {
      if (p <= SKY[i][0]) {
        var a = SKY[i - 1], b = SKY[i], t = (p - a[0]) / Math.max(0.0001, b[0] - a[0]);
        return { top: lerpC(a[1], b[1], t), bottom: lerpC(a[2], b[2], t), night: a[3] + (b[3] - a[3]) * t, warm: a[4] + (b[4] - a[4]) * t };
      }
    }
    var l = SKY[SKY.length - 1];
    return { top: l[1], bottom: l[2], night: l[3], warm: l[4] };
  }
  function tile(colors, seed, top) {
    var c = document.createElement('canvas'); c.width = c.height = 16;
    var x = c.getContext('2d'), r = rng(seed);
    for (var yy = 0; yy < 16; yy++) for (var xx = 0; xx < 16; xx++) {
      var col = pick(r, colors);
      if (top && yy < 4 + (r() > 0.6 ? 1 : 0)) col = pick(r, top);
      x.fillStyle = hex(col); x.fillRect(xx, yy, 1, 1);
    }
    return c;
  }
  function Minecraft() {
    this.dirt = tile([0x866043, 0x79553a, 0x966c4a, 0x6c4a31, 0x8b6446], 7);
    this.grass = tile([0x866043, 0x79553a, 0x966c4a, 0x6c4a31], 11, [0x5d9a30, 0x6aae3a, 0x7dc24a, 0x4f8a28]);
    this.stone = tile([0x7f7f7f, 0x8f8f8f, 0x747474, 0x686868, 0x9a9a9a], 3);
    this.ores = [[0x2a2a2a, 0x4a4a4a], [0xfcee4b, 0xffffb5], [0x5decf5, 0xa1fbe8], [0xff3c3c, 0xffa3a3]].map(function (o, i) {
      var c = tile([0x7f7f7f, 0x8f8f8f, 0x747474, 0x686868], 21 + i), x = c.getContext('2d'), r = rng(40 + i);
      for (var k = 0; k < 7; k++) { x.fillStyle = hex(r() > 0.5 ? o[0] : o[1]); x.fillRect(2 + (r() * 11 | 0), 2 + (r() * 11 | 0), 2, 2); }
      return c;
    });
    var r = rng(5);
    this.clouds = [];
    for (var i = 0; i < 7; i++) {
      var w = 4 + (r() * 7 | 0), h = 2 + (r() > 0.5 ? 1 : 0), cells = [];
      for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
        var corner = (x === 0 || x === w - 1) && (y === 0 || y === h - 1);
        if (y === (h >> 1) || (!corner && r() > 0.3)) cells.push([x, y]);
      }
      this.clouds.push({ x: r(), y: 0.08 + r() * 0.2, speed: 5 + r() * 9, cells: cells, w: w });
    }
    this.stars = []; for (i = 0; i < 70; i++) this.stars.push([r(), r() * 0.6]);
    this.heights = []; this.peaks = []; this.hold = []; this.parts = []; this.r = rng(99);
    this.noteCols = [0x77d700, 0xb2a500, 0xe26500, 0xfc1e00, 0xd8008e, 0x9000d5, 0x3600f5, 0x00b0d9];
  }
  Minecraft.prototype.draw = function (ctx, W, H, f) {
    var cell = Math.max(12, Math.min(30, Math.round(W / (W < 700 ? 18 : 52)))), cols = Math.ceil(W / cell);
    var rows = Math.max(6, Math.floor(H * 0.3 / cell)), i;
    if (this.heights.length !== cols) { this.heights = new Array(cols).fill(4); this.peaks = this.heights.slice(); this.hold = new Array(cols).fill(0); }
    var p = f.progress != null ? f.progress : (f.t / 240) % 1, sky = skyAt(p);
    ctx.fillStyle = vgrad(ctx, H * 0.85, [[0, hex(sky.top)], [1, hex(sky.bottom)]]);
    ctx.fillRect(0, 0, W, H);
    if (sky.night > 0.02) {
      this.stars.forEach(function (s) {
        ctx.fillStyle = 'rgba(255,255,255,' + (sky.night * (0.45 + 0.4 * Math.sin(f.t * 1.7 + s[0] * 60))) + ')';
        ctx.fillRect(s[0] * W, s[1] * H, 2, 2);
      });
    }
    var sz = cell * 3;
    if (p < 0.86) {
      var q = p / 0.86, sx = -sz + (W + sz) * q, sy = H * 0.5 - Math.sin(q * Math.PI) * H * 0.4;
      ctx.fillStyle = 'rgba(255,243,160,0.18)'; ctx.fillRect(sx - sz * 0.35, sy - sz * 0.35, sz * 1.7, sz * 1.7);
      ctx.fillStyle = '#ffe95c'; ctx.fillRect(sx, sy, sz, sz);
      ctx.fillStyle = '#ffffd8'; ctx.fillRect(sx + sz * 0.2, sy + sz * 0.2, sz * 0.6, sz * 0.6);
    }
    if (p > 0.72) {
      var q2 = (p - 0.72) / 0.28, mx = -sz + (W * 0.72 + sz) * q2, my = H * 0.5 - Math.sin(q2 * Math.PI / 2) * H * 0.38;
      ctx.fillStyle = '#e6e6d6'; ctx.fillRect(mx, my, sz, sz);
      ctx.fillStyle = '#bfbfae'; ctx.fillRect(mx + sz * 0.2, my + sz * 0.25, sz * 0.25, sz * 0.25);
    }
    var cc = cell * 0.85, cloud = lerpC(lerpC(0xffffff, 0x4a5070, sky.night), 0xffc8a8, sky.warm * 0.5);
    ctx.fillStyle = hex(cloud, 0.85);
    this.clouds.forEach(function (c) {
      var cw = c.w * cc;
      c.x += c.speed * f.dt / (W + cw); if (c.x > 1) c.x -= 1;
      var x0 = c.x * (W + cw) - cw, y0 = c.y * H;
      c.cells.forEach(function (k) { ctx.fillRect(x0 + k[0] * cc, y0 + k[1] * cc * 0.6, cc + 0.5, cc * 0.6 + 0.5); });
    });
    // рельеф-эквалайзер
    var bands = bandsOf(f, cols), base = 3;
    for (i = 0; i < cols; i++) {
      var target = base + Math.pow(bands[i], 1.4) * (rows - base - 1);
      this.heights[i] = target > this.heights[i] ? target : Math.max(target, this.heights[i] - f.dt * 14);
      var hh = Math.round(this.heights[i]);
      if (hh >= this.peaks[i]) { this.peaks[i] = hh; this.hold[i] = 0.5; }
      else if (this.hold[i] > 0) this.hold[i] -= f.dt;
      else this.peaks[i] = Math.max(hh, this.peaks[i] - f.dt * 4);
    }
    ctx.imageSmoothingEnabled = false;
    var ground = H - rows * cell;
    for (i = 0; i < cols; i++) {
      var h = Math.round(this.heights[i]), x = i * cell;
      for (var k = 0; k < rows; k++) {
        var y = H - (k + 1) * cell;
        if (k >= h) break;
        var img = k === h - 1 ? this.grass : (k > h - 4 ? this.dirt : ((i * 7 + k * 13) % 17 === 0 ? this.ores[(i + k) % 4] : this.stone));
        ctx.drawImage(img, x, y, cell + 0.5, cell + 0.5);
      }
      if (f.active && this.peaks[i] > h) {
        ctx.fillStyle = 'rgba(255,255,255,0.8)';
        ctx.fillRect(x + cell * 0.2, H - this.peaks[i] * cell - cell * 0.3, cell * 0.6, cell * 0.2);
      }
    }
    if (sky.night > 0.01) { ctx.fillStyle = 'rgba(5,8,26,' + sky.night * 0.5 + ')'; ctx.fillRect(0, ground, W, H - ground); }
    // ноты на ударах
    if (f.beat && f.particles) {
      for (var n = 0; n < 2; n++) {
        var c2 = this.r() * cols | 0;
        this.parts.push({ x: c2 * cell + cell * 0.2, y: H - this.heights[c2] * cell - cell, age: 0, life: 1.4 + this.r() * 0.8,
                          col: pick(this.r, this.noteCols), size: cell * 0.8, ph: this.r() * 6 });
      }
    }
    this.parts = this.parts.filter(function (q) { return q.age < q.life; });
    this.parts.forEach(function (q) {
      q.age += f.dt; q.y -= 55 * f.dt;
      ctx.globalAlpha = Math.max(0, 1 - q.age / q.life);
      ctx.fillStyle = hex(q.col);
      var x = q.x + Math.sin(q.age * 3 + q.ph) * 6, s = q.size / 8;
      ctx.fillRect(x + 4 * s, q.y, s * 2, s * 6); ctx.fillRect(x, q.y + 5 * s, s * 4, s * 3); ctx.fillRect(x + 5 * s, q.y, s * 3, s * 2);
    });
    ctx.globalAlpha = 1;
  };

  // ---------- Сердечки и бантики ----------
  function Hearts() { this.r = rng(77); this.items = []; this.dots = null; }
  Hearts.prototype.make = function (randomY) {
    var r = this.r, k = r();
    return { x: r(), y: randomY ? r() * 1.1 : 1.08, size: 14 + r() * 26, speed: 0.03 + r() * 0.05, ph: r() * 6.28,
             kind: k < 0.55 ? 0 : (k < 0.78 ? 1 : 2), color: pick(r, ['#ff6fa5', '#ff8fb8', '#e8374f', '#ffa3c6', '#d98bff']), rot: (r() - 0.5) * 0.6 };
  };
  Hearts.prototype.draw = function (ctx, W, H, f) {
    var self = this;
    if (!this.items.length) for (var i = 0; i < 24; i++) this.items.push(this.make(true));
    ctx.fillStyle = vgrad(ctx, H, [[0, '#ffc7dd'], [0.55, '#ffe3ee'], [1, '#fff4f8']]); ctx.fillRect(0, 0, W, H);
    if (!this.dots) {
      var d = document.createElement('canvas'); d.width = d.height = 54;
      var x = d.getContext('2d'); x.fillStyle = 'rgba(255,255,255,0.6)';
      x.beginPath(); x.arc(0, 0, 5, 0, 7); x.arc(54, 0, 5, 0, 7); x.arc(0, 54, 5, 0, 7); x.arc(54, 54, 5, 0, 7); x.arc(27, 27, 5, 0, 7); x.fill();
      this.dots = ctx.createPattern(d, 'repeat');
    }
    var off = (f.t * 10) % 54;
    ctx.save(); ctx.translate(off * 0.5, off); ctx.fillStyle = this.dots; ctx.fillRect(-60, -60, W + 120, H + 120); ctx.restore();
    var gr = Math.min(W, H) * (0.45 + f.bass * 0.12), rg = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, gr);
    rg.addColorStop(0, 'rgba(255,255,255,0.45)'); rg.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = rg; ctx.fillRect(0, 0, W, H);
    if (f.beat && f.particles) {
      for (var n = 0; n < 3; n++) { var it = this.make(false); it.kind = 0; it.size = 10 + this.r() * 8; it.speed = 0.22 + this.r() * 0.2; this.items.push(it); }
      if (this.items.length > 56) this.items.splice(0, this.items.length - 56);
    }
    this.items.forEach(function (it, idx) {
      it.y -= it.speed * f.dt * (1 + f.level);
      if (it.y < -0.1) self.items[idx] = it = self.make(false);
      var s = it.size * (1 + f.bass * 0.35);
      ctx.save();
      ctx.translate(it.x * W + Math.sin(f.t * 0.8 + it.ph) * 26, it.y * H);
      ctx.rotate(Math.sin(f.t + it.ph) * 0.35 + it.rot);
      if (it.kind === 0) {
        Shapes.heart(ctx, 0, 0, s); ctx.fillStyle = it.color; ctx.globalAlpha = 0.88; ctx.fill(); ctx.globalAlpha = 1;
        Shapes.heart(ctx, -s * 0.2, -s * 0.12, s * 0.22); ctx.fillStyle = 'rgba(255,255,255,0.4)'; ctx.fill();
      } else if (it.kind === 1) {
        Shapes.bow(ctx, 0, 0, s * 1.5); ctx.fillStyle = '#e8374f'; ctx.fill(); ctx.strokeStyle = '#b21d3a'; ctx.lineWidth = 2; ctx.stroke();
        ctx.fillStyle = '#c92440'; ctx.beginPath(); ctx.ellipse(0, 0, s * 0.17, s * 0.19, 0, 0, 7); ctx.fill();
      } else {
        var tw = 0.5 + 0.5 * Math.sin(f.t * 3 + it.ph);
        Shapes.sparkle(ctx, 0, 0, s * (0.35 + 0.35 * tw)); ctx.fillStyle = 'rgba(255,255,255,0.95)'; ctx.fill();
      }
      ctx.restore();
    });
  };

  // ---------- Кьют-рок ----------
  function CuteRock() { this.r = rng(31); this.bars = []; this.bolts = []; }
  CuteRock.prototype.draw = function (ctx, W, H, f) {
    var r = this.r, self = this, i;
    if (!this.stars) {
      this.stars = []; this.hearts = []; this.glitter = [];
      for (i = 0; i < 14; i++) this.stars.push({ x: r(), y: r() * 0.75, size: 8 + r() * 20, ph: r() * 6.28, color: pick(r, ['#ff6bcb', '#d9a1ff', '#ffe66b', '#ffffff']) });
      for (i = 0; i < 8; i++) this.hearts.push({ x: r(), y: r(), size: 22 + r() * 34, vx: (r() - 0.5) * 0.02, vy: -0.01 - r() * 0.02, ph: r() * 6.28, color: pick(r, ['#ff4fb8', '#b36bff', '#ff8ad8']) });
      for (i = 0; i < 110; i++) this.glitter.push([r(), r()]);
    }
    ctx.fillStyle = vgrad(ctx, H, [[0, '#12051c'], [0.55, '#2a0b3d'], [1, '#51104f']]); ctx.fillRect(0, 0, W, H);
    var gr = Math.min(W, H) * (0.55 + f.bass * 0.2), rg = ctx.createRadialGradient(W * 0.5, H * 0.45, 0, W * 0.5, H * 0.45, gr);
    rg.addColorStop(0, 'rgba(255,45,170,' + (0.28 + f.bass * 0.2) + ')'); rg.addColorStop(1, 'rgba(255,45,170,0)');
    ctx.fillStyle = rg; ctx.fillRect(0, 0, W, H);
    this.glitter.forEach(function (g, k) {
      ctx.fillStyle = (k % 3 === 0 ? 'rgba(255,179,230,' : 'rgba(255,255,255,') + (0.15 + 0.55 * Math.max(0, Math.sin(f.t * (1.5 + (k % 7) * 0.3) + k))) + ')';
      ctx.fillRect(g[0] * W, g[1] * H, 2.2, 2.2);
    });
    this.stars.forEach(function (s) {
      var rr = s.size * (0.55 + 0.45 * Math.sin(f.t * 2.2 + s.ph)) * (1 + f.bass * 0.4);
      ctx.save(); ctx.translate(s.x * W, s.y * H); ctx.rotate(f.t * 0.3 + s.ph);
      ctx.globalAlpha = 0.18; Shapes.sparkle(ctx, 0, 0, rr * 1.8); ctx.fillStyle = s.color; ctx.fill();
      ctx.globalAlpha = 0.95; Shapes.sparkle(ctx, 0, 0, rr); ctx.fill(); ctx.restore();
    });
    ctx.globalAlpha = 1;
    this.hearts.forEach(function (h) {
      h.x += h.vx * f.dt; h.y += h.vy * f.dt * (1 + f.level * 2);
      if (h.y < -0.1) { h.y = 1.1; h.x = r(); }
      if (h.x < -0.1) h.x = 1.1; else if (h.x > 1.1) h.x = -0.1;
      var s = h.size * (1 + f.bass * 0.25);
      ctx.save(); ctx.translate(h.x * W, h.y * H); ctx.rotate(Math.sin(f.t * 0.9 + h.ph) * 0.3);
      Shapes.heart(ctx, 0, 0, s); ctx.fillStyle = h.color; ctx.globalAlpha = 0.9; ctx.fill(); ctx.globalAlpha = 1;
      ctx.lineWidth = 3.5; ctx.strokeStyle = '#14041f'; ctx.stroke();
      Shapes.heart(ctx, -s * 0.2, -s * 0.12, s * 0.2); ctx.fillStyle = 'rgba(255,255,255,0.55)'; ctx.fill();
      ctx.restore();
    });
    if (f.beat && f.particles) this.bolts.push({ x: 0.08 + r() * 0.84, y: 0.04 + r() * 0.3, age: 0, scale: 50 + r() * 60, color: pick(r, ['#ffe66b', '#ff6bcb', '#c7a2ff']) });
    this.bolts = this.bolts.filter(function (b) { return b.age <= 0.4; });
    this.bolts.forEach(function (b) {
      b.age += f.dt;
      var a = Math.max(0, 1 - b.age / 0.4);
      Shapes.bolt(ctx, b.x * W, b.y * H, b.scale);
      ctx.globalAlpha = a * 0.35; ctx.lineWidth = 10; ctx.strokeStyle = b.color; ctx.stroke();
      ctx.globalAlpha = a; ctx.fillStyle = b.color; ctx.fill();
    });
    ctx.globalAlpha = 1;
    var n = W < 700 ? 24 : 40, bands = bandsOf(f, n), bw = W / n;
    if (this.bars.length !== n) this.bars = new Array(n).fill(0);
    var gb = ctx.createLinearGradient(0, H * 0.7, 0, H);
    gb.addColorStop(0, '#ff6bcb'); gb.addColorStop(1, 'rgba(138,61,255,0.6)');
    ctx.fillStyle = gb;
    for (i = 0; i < n; i++) {
      self.bars[i] = bands[i] > self.bars[i] ? bands[i] : Math.max(bands[i], self.bars[i] - f.dt * 1.6);
      var bh = Math.max(4, self.bars[i] * H * 0.22);
      roundRect(ctx, i * bw + bw * 0.18, H - bh, bw * 0.64, bh + 8, bw * 0.3); ctx.fill();
    }
  };
  function roundRect(ctx, x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }

  // ---------- Космос ----------
  function Space() { this.r = rng(123); this.stars = []; this.shoot = null; this.next = 3; }
  Space.prototype.spawn = function (far) { var r = this.r; return { x: r() * 2 - 1, y: r() * 2 - 1, z: far ? 1 : 0.05 + r() * 0.95 }; };
  Space.prototype.draw = function (ctx, W, H, f) {
    var self = this, i;
    var count = W < 700 ? 200 : 360;
    while (this.stars.length < count) this.stars.push(this.spawn(false));
    ctx.fillStyle = vgrad(ctx, H, [[0, '#02030a'], [0.6, '#080c24'], [1, '#0e1233']]); ctx.fillRect(0, 0, W, H);
    [[0x5b2ab8, 0.3, 0.35, 0.3], [0x1f4fb0, 0.72, 0.3, 0.26], [0xb02e8a, 0.55, 0.72, 0.22]].forEach(function (nb, k) {
      var cx = W * (nb[1] + 0.06 * Math.sin(f.t * 0.05 + k * 2)), cy = H * (nb[2] + 0.05 * Math.cos(f.t * 0.04 + k)), rr = Math.max(W, H) * (0.42 + f.bass * 0.05);
      var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, rr); g.addColorStop(0, hex(nb[0], nb[3])); g.addColorStop(1, hex(nb[0], 0));
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    });
    var speed = 0.05 + f.level * 0.45 + (f.beat ? 0.25 : 0), cx = W / 2, cy = H / 2, k2 = Math.max(W, H) * 0.42;
    for (i = 0; i < this.stars.length; i++) {
      var s = this.stars[i]; s.z -= speed * f.dt;
      if (s.z <= 0.03) { this.stars[i] = this.spawn(true); continue; }
      var sx = cx + s.x / s.z * k2, sy = cy + s.y / s.z * k2;
      if (sx < -20 || sx > W + 20 || sy < -20 || sy > H + 20) { this.stars[i] = this.spawn(true); continue; }
      var a = Math.min(1, (1 - s.z) * 1.4), rad = Math.max(0.7, (1 - s.z) * 3);
      ctx.fillStyle = 'rgba(255,255,255,' + a + ')'; ctx.fillRect(sx - rad / 2, sy - rad / 2, rad, rad);
    }
    var pr = Math.min(W, H) * 0.14 * (1 + f.bass * 0.04), pcx = W * 0.82, pcy = H * 0.74;
    ctx.lineWidth = pr * 0.12; ctx.strokeStyle = 'rgba(255,209,166,0.35)';
    ctx.beginPath(); ctx.ellipse(pcx, pcy, pr * 1.9, pr * 0.45, 0, 0, 7); ctx.stroke();
    var pg = ctx.createLinearGradient(pcx - pr, pcy - pr, pcx + pr, pcy + pr);
    pg.addColorStop(0, '#ffb36b'); pg.addColorStop(0.5, '#c2417e'); pg.addColorStop(1, '#4a1e6b');
    ctx.fillStyle = pg; ctx.beginPath(); ctx.arc(pcx, pcy, pr, 0, 7); ctx.fill();
    ctx.save(); ctx.beginPath(); ctx.rect(pcx - pr * 2, pcy, pr * 4, pr); ctx.clip();
    ctx.strokeStyle = 'rgba(255,209,166,0.7)'; ctx.beginPath(); ctx.ellipse(pcx, pcy, pr * 1.9, pr * 0.45, 0, 0, 7); ctx.stroke(); ctx.restore();
    this.next -= f.dt;
    if (!this.shoot && this.next <= 0) { this.shoot = { x: this.r() * 0.6, y: this.r() * 0.35, age: 0 }; this.next = 4 + this.r() * 6; }
    if (this.shoot) {
      var t = this.shoot.age / 0.9, x0 = (this.shoot.x + t * 0.35) * W, y0 = (this.shoot.y + t * 0.18) * H;
      var lg = ctx.createLinearGradient(x0 - 120, y0 - 60, x0, y0); lg.addColorStop(0, 'rgba(255,255,255,0)'); lg.addColorStop(1, 'rgba(255,255,255,' + 0.9 * (1 - t) + ')');
      ctx.strokeStyle = lg; ctx.lineWidth = 2.2; ctx.beginPath(); ctx.moveTo(x0 - 120, y0 - 60); ctx.lineTo(x0, y0); ctx.stroke();
      this.shoot.age += f.dt; if (this.shoot.age > 0.9) this.shoot = null;
    }
  };

  // ---------- Синтвейв ----------
  function Synthwave() { var r = rng(8); this.stars = []; for (var i = 0; i < 80; i++) this.stars.push([r(), r() * 0.55]); this.ridge = []; }
  Synthwave.prototype.draw = function (ctx, W, H, f) {
    var hy = H * 0.62, i;
    ctx.fillStyle = vgrad(ctx, hy, [[0, '#07021a'], [0.55, '#220843'], [0.85, '#7a1470'], [1, '#ff2bd6']]); ctx.fillRect(0, 0, W, hy);
    this.stars.forEach(function (s, k) { ctx.fillStyle = 'rgba(255,255,255,' + (0.3 + 0.5 * Math.max(0, Math.sin(f.t * 1.3 + k))) + ')'; ctx.fillRect(s[0] * W, s[1] * H, 1.8, 1.8); });
    var R = Math.min(W, H) * 0.24 * (1 + f.bass * 0.05), scx = W / 2, scy = hy - R * 0.38;
    var glow = ctx.createRadialGradient(scx, scy, R * 0.8, scx, scy, R * 1.8);
    glow.addColorStop(0, 'rgba(255,78,154,0.35)'); glow.addColorStop(1, 'rgba(255,78,154,0)'); ctx.fillStyle = glow; ctx.fillRect(0, 0, W, hy);
    ctx.save(); ctx.beginPath(); ctx.arc(scx, scy, R, 0, 7); ctx.clip();
    ctx.fillStyle = vgrad(ctx, H, [[0, '#ffe259'], [scy / H, '#ff8a3d'], [Math.min(1, (scy + R) / H), '#ff2bd6']]);
    ctx.fillStyle = (function () { var g = ctx.createLinearGradient(0, scy - R, 0, scy + R); g.addColorStop(0, '#ffe259'); g.addColorStop(0.5, '#ff8a3d'); g.addColorStop(1, '#ff2bd6'); return g; })();
    ctx.fillRect(scx - R, scy - R, 2 * R, 2 * R);
    var shift = (f.t * 12) % (R * 0.16), y = scy + R * 0.05 + shift, k = 1;
    while (y < scy + R) { ctx.clearRect(scx - R, y, 2 * R, 2 + k * 1.6); ctx.fillStyle = '#220843'; ctx.fillRect(scx - R, y, 2 * R, 2 + k * 1.6); y += R * 0.16; k++; }
    ctx.restore();
    var n = 40, bands = bandsOf(f, n);
    if (this.ridge.length !== n + 1) this.ridge = new Array(n + 1).fill(0);
    ctx.beginPath(); ctx.moveTo(0, hy);
    for (i = 0; i <= n; i++) {
      var mir = i <= n / 2 ? n / 2 - i : i - n / 2, b = bands[Math.min(n - 1, mir * 2)], base = 0.2 + 0.25 * Math.abs(Math.sin(i * 1.7));
      var tgt = base + b * 0.9; this.ridge[i] = tgt > this.ridge[i] ? tgt : Math.max(tgt, this.ridge[i] - f.dt * 1.2);
      ctx.lineTo(W * i / n, hy - this.ridge[i] * H * 0.12);
    }
    ctx.lineTo(W, hy); ctx.closePath(); ctx.fillStyle = '#1a0633'; ctx.fill();
    ctx.lineWidth = 1.6; ctx.strokeStyle = 'rgba(0,229,255,0.9)'; ctx.stroke();
    ctx.fillStyle = vgrad(ctx, H, [[hy / H, '#16032e'], [1, '#0a0016']]); ctx.fillRect(0, hy, W, H - hy);
    ctx.beginPath();
    for (i = -18; i <= 18; i++) { ctx.moveTo(W / 2 + i * W * 0.02, hy); ctx.lineTo(W / 2 + i * W * 0.18, H); }
    var ph = (f.t * (0.3 + f.level * 1.4)) % 1;
    for (i = 0; i < 14; i++) { var u = (i + ph) / 14, gy = hy + (H - hy) * Math.pow(u, 2.4); ctx.moveTo(0, gy); ctx.lineTo(W, gy); }
    ctx.lineWidth = 1.3; ctx.strokeStyle = 'rgba(255,79,224,0.85)'; ctx.stroke();
    ctx.fillStyle = 'rgba(255,179,240,0.9)'; ctx.fillRect(0, hy - 1, W, 3);
  };

  // ---------- Цвета обложки ----------
  function Aurora() {}
  Aurora.prototype.draw = function (ctx, W, H, f) {
    var pal = f.palette && f.palette.length ? f.palette : ['#7b2ff7', '#f72f8c', '#ffb347', '#2fc6f7'];
    ctx.fillStyle = '#0c0a14'; ctx.fillRect(0, 0, W, H);
    ctx.globalCompositeOperation = 'screen';
    for (var i = 0; i < 5; i++) {
      var cx = W * (0.5 + 0.38 * Math.sin(f.t * 0.06 * (i + 1) + i * 1.7)), cy = H * (0.5 + 0.36 * Math.cos(f.t * 0.045 * (i + 1) + i * 2.3));
      var r = Math.max(W, H) * (0.36 + 0.08 * Math.sin(f.t * 0.1 + i)) * (1 + f.bass * 0.14);
      var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
      var c = pal[i % pal.length];
      g.addColorStop(0, c.replace('rgb(', 'rgba(').replace(')', ',0.55)').replace('#', '#'));
      g.addColorStop(1, 'rgba(0,0,0,0)');
      if (c[0] === '#') { var n = parseInt(c.slice(1), 16); g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r); g.addColorStop(0, hex(n, 0.55)); g.addColorStop(1, hex(n, 0)); }
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    }
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = 'rgba(0,0,0,0.18)'; ctx.fillRect(0, 0, W, H);
  };

  // ---------- Ночной океан ----------
  function Ocean() { var r = rng(44); this.stars = []; for (var i = 0; i < 80; i++) this.stars.push([r(), r() * 0.5]); }
  Ocean.prototype.draw = function (ctx, W, H, f) {
    ctx.fillStyle = vgrad(ctx, H, [[0, '#060b22'], [0.5, '#13265a'], [1, '#2b4f8c']]); ctx.fillRect(0, 0, W, H);
    this.stars.forEach(function (s, i) { ctx.fillStyle = 'rgba(255,255,255,' + (0.25 + 0.5 * Math.max(0, Math.sin(f.t * 1.1 + i * 1.3))) + ')'; ctx.fillRect(s[0] * W, s[1] * H, 2, 2); });
    var mr = Math.min(W, H) * 0.065, mx = W * 0.78, my = H * 0.18;
    var mg = ctx.createRadialGradient(mx, my, mr, mx, my, mr * 4); mg.addColorStop(0, 'rgba(255,246,216,0.25)'); mg.addColorStop(1, 'rgba(255,246,216,0)');
    ctx.fillStyle = mg; ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = '#f7f2dc'; ctx.beginPath(); ctx.arc(mx, my, mr, 0, 7); ctx.fill();
    var bands = bandsOf(f, 5, 40, 6000), cols = ['#1e4a86', '#17407a', '#10336a', '#0b2858', '#071c44'];
    for (var k = 0; k < 5; k++) {
      var base = H * (0.56 + k * 0.09), amp = (6 + k * 5) * (1 + bands[k] * 2.2 + f.bass * 0.6), fr = 0.006 - k * 0.0006, sp = 0.6 + k * 0.25;
      ctx.beginPath(); ctx.moveTo(0, H);
      for (var x = 0; x <= W + 10; x += 10) ctx.lineTo(x, base + Math.sin(x * fr + f.t * sp + k) * amp + Math.sin(x * fr * 2.3 - f.t * sp * 1.3) * amp * 0.35);
      ctx.lineTo(W, H); ctx.closePath(); ctx.fillStyle = cols[k]; ctx.globalAlpha = 0.95; ctx.fill(); ctx.globalAlpha = 1;
      if (k < 2) for (var j = 0; j < 12; j++) {
        ctx.fillStyle = 'rgba(255,246,216,' + (0.2 + 0.5 * Math.max(0, Math.sin(f.t * 3 + j * 1.7))) + ')';
        ctx.fillRect(mx + Math.sin(j * 12.9 + f.t * 0.7) * mr * 2.5 - 10, base + j * 6 - 10, 20, 1.6);
      }
    }
  };

  var MAKERS = { minecraft: Minecraft, hearts: Hearts, cuteRock: CuteRock, space: Space, synthwave: Synthwave, aurora: Aurora, ocean: Ocean };

  // ---------- движок ----------
  function Scene(canvas, opts) {
    this.canvas = canvas; this.ctx = canvas.getContext('2d', { alpha: false });
    this.opts = opts || {}; this.renderers = {}; this.id = 'minecraft';
    this.fps = 30; this.dpr = 1; this.last = 0; this.lastDraw = 0; this.running = false;
    this.bass = 0; this.level = 0; this.avg = 0; this.lastBeat = 0;
  }
  Scene.prototype.renderer = function (id) {
    if (!this.renderers[id]) this.renderers[id] = new (MAKERS[id] || Minecraft)();
    return this.renderers[id];
  };
  Scene.prototype.resize = function () {
    var w = this.canvas.clientWidth || this.canvas.width, h = this.canvas.clientHeight || this.canvas.height;
    var d = Math.min(window.devicePixelRatio || 1, this.dpr);
    var cw = Math.max(1, Math.round(w * d)), ch = Math.max(1, Math.round(h * d));
    if (this.canvas.width !== cw || this.canvas.height !== ch) { this.canvas.width = cw; this.canvas.height = ch; }
    this.scale = d; this.W = w; this.H = h;
  };
  Scene.prototype.frame = function (now) {
    var t = now / 1000, dt = this.last ? Math.min(0.1, Math.max(0, t - this.last)) : 1 / 60;
    this.last = t;
    var inp = (this.opts.input && this.opts.input()) || {};
    var binHz = inp.binHz || (44100 / 2048);
    var spec = inp.spectrum || (inp.playing ? ambient(t, 1024, binHz) : null);
    var active = !!(inp.playing && spec && spec.length), bassNow = 0;
    if (active) {
      var b0 = Math.max(1, Math.floor(35 / binHz)), b1 = Math.min(spec.length - 1, Math.max(b0 + 1, Math.floor(150 / binHz)));
      for (var b = b0; b <= b1; b++) bassNow += spec[b];
      bassNow /= (b1 - b0 + 1);
    }
    this.bass += (bassNow - this.bass) * Math.min(1, dt * 18);
    this.level += ((active ? (inp.level != null ? inp.level : 0.5) : 0) - this.level) * Math.min(1, dt * 12);
    this.avg += (bassNow - this.avg) * Math.min(1, dt * 1.5);
    var beat = false;
    if (active && bassNow > this.avg * 1.2 && bassNow > 0.45 && t - this.lastBeat > 0.2) { beat = true; this.lastBeat = t; }
    window.__bass = this.bass;
    var f = { t: t, dt: dt, active: active, bass: this.bass, level: this.level, beat: beat, progress: inp.progress,
              spectrum: spec, binHz: binHz, particles: inp.particles !== false, palette: inp.palette };
    this.resize();
    var ctx = this.ctx;
    ctx.setTransform(this.scale, 0, 0, this.scale, 0, 0);
    this.renderer(this.id).draw(ctx, this.W, this.H, f);
  };
  Scene.prototype.loop = function (now) {
    if (!this.running) return;
    var self = this;
    requestAnimationFrame(function (n) { self.loop(n); });
    if (now - this.lastDraw < 1000 / this.fps - 2) return;
    this.lastDraw = now;
    this.frame(now);
  };
  Scene.prototype.start = function () {
    if (this.running) return;
    this.running = true; this.last = 0;
    var self = this;
    requestAnimationFrame(function (n) { self.loop(n); });
  };
  Scene.prototype.stop = function () { this.running = false; };
  Scene.prototype.once = function () { this.frame(performance.now()); };

  window.BGScene = Scene;
  window.BGAmbient = ambient;
})();
