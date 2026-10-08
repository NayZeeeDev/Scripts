/* ═══════════════════════════════════════════════════════════
   Canvas candlestick chart — redraws only when invalidated
   ═══════════════════════════════════════════════════════════ */
(() => {
  const C = {
    teal: '#08afa2', red: '#e5484d', amber: '#e5a50a', white: '#ffffff',
    ink2: '#9ea5aa', ink3: '#63696d', grid: 'rgba(255,255,255,.045)', axis: 'rgba(255,255,255,.08)',
    tag: '#1c2023', ema9: 'rgba(255,255,255,.72)', ema21: '#e5a50a', vwap: '#0fd4c4',
  };
  const FONT = '400 10px Lexend, system-ui, sans-serif';
  const AXIS_W = 66, AXIS_H = 22, RIGHT_PAD = 5;

  function niceStep(range, target) {
    const raw = range / target;
    const mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const n = raw / mag;
    return (n < 1.5 ? 1 : n < 3 ? 2 : n < 7 ? 5 : 10) * mag;
  }

  function ema(data, period) {
    const out = new Array(data.length);
    const k = 2 / (period + 1);
    let prev;
    for (let i = 0; i < data.length; i++) {
      prev = prev === undefined ? data[i].c : data[i].c * k + prev * (1 - k);
      out[i] = prev;
    }
    return out;
  }

  function vwap(data) {
    const out = new Array(data.length);
    let pv = 0, v = 0;
    for (let i = 0; i < data.length; i++) {
      const d = data[i];
      const vol = d.v || 1;
      pv += ((d.h + d.l + d.c) / 3) * vol;
      v += vol;
      out[i] = pv / v;
    }
    return out;
  }

  class Chart {
    constructor(wrap, opts = {}) {
      this.wrap = wrap;
      this.opts = opts;
      this.cv = document.createElement('canvas');
      wrap.appendChild(this.cv);
      this.ctx = this.cv.getContext('2d');
      this.data = [];
      this.tf = 60;
      this.barW = 9;
      this.offset = 0;
      this.type = 'candle';
      this.ind = { ema9: true, ema21: true, vwap: false, vol: true };
      this.lines = [];
      this.hover = null;
      this.raf = 0;
      this.W = this.H = 0;

      this.ro = new ResizeObserver(() => this.resize());
      this.ro.observe(wrap);
      this.bind();
    }

    destroy() {
      this.ro.disconnect();
      cancelAnimationFrame(this.raf);
      this.cv.remove();
    }

    resize() {
      const W = this.wrap.clientWidth, H = this.wrap.clientHeight;
      if (!W || !H) return;
      const k = (window.devicePixelRatio || 1) * (NZ.scale || 1);
      this.W = W; this.H = H; this.k = k;
      this.cv.width = Math.round(W * k);
      this.cv.height = Math.round(H * k);
      this.draw();
    }

    invalidate() {
      if (!this.raf) this.raf = requestAnimationFrame(() => { this.raf = 0; this.draw(); });
    }

    setData(rows, tf) {
      this.tf = tf;
      this.data = rows.map((r) => ({ t: r[0], o: r[1], h: r[2], l: r[3], c: r[4], v: r[5] }));
      this.offset = 0;
      this.invalidate();
    }

    // live update from the quote stream
    update(t, price, dvol) {
      if (!this.data.length || price == null) return;
      const bucket = t - (t % this.tf);
      const last = this.data[this.data.length - 1];
      if (bucket > last.t) {
        this.data.push({ t: bucket, o: last.c, h: Math.max(last.c, price), l: Math.min(last.c, price), c: price, v: dvol });
        if (this.data.length > 600) this.data.shift();
        else if (this.offset > 0) this.offset += 1;
      } else {
        if (price > last.h) last.h = price;
        if (price < last.l) last.l = price;
        last.c = price;
        last.v += dvol;
      }
      this.invalidate();
    }

    setLines(lines) { this.lines = lines; this.invalidate(); }

    // ── geometry ─────────────────────────────────────────────
    plotW() { return this.W - AXIS_W; }
    xOf(i) { return this.plotW() - (RIGHT_PAD + 0.5) * this.barW - (this.data.length - 1 - this.offset - i) * this.barW; }
    iOf(x) { return Math.round(this.data.length - 1 - this.offset - (this.plotW() - (RIGHT_PAD + 0.5) * this.barW - x) / this.barW); }
    yOf(p) { return this.top + ((this.hi - p) / (this.hi - this.lo)) * (this.bottom - this.top); }
    pOf(y) { return this.hi - ((y - this.top) / (this.bottom - this.top)) * (this.hi - this.lo); }

    local(e) {
      const r = this.cv.getBoundingClientRect();
      return { x: ((e.clientX - r.left) * this.W) / r.width, y: ((e.clientY - r.top) * this.H) / r.height };
    }

    bind() {
      const cv = this.cv;
      let drag = null;
      cv.addEventListener('wheel', (e) => {
        e.preventDefault();
        this.barW = Math.max(3, Math.min(40, this.barW * (e.deltaY < 0 ? 1.12 : 1 / 1.12)));
        this.invalidate();
      }, { passive: false });
      cv.addEventListener('mousedown', (e) => {
        if (e.button !== 0) return;
        drag = { x: this.local(e).x, off: this.offset };
      });
      window.addEventListener('mouseup', () => { drag = null; });
      cv.addEventListener('mousemove', (e) => {
        const p = this.local(e);
        if (drag) {
          const max = Math.max(0, this.data.length - 12);
          this.offset = Math.max(0, Math.min(max, drag.off + (p.x - drag.x) / this.barW));
        }
        this.hover = p;
        this.invalidate();
      });
      cv.addEventListener('mouseleave', () => { this.hover = null; this.invalidate(); });
      cv.addEventListener('dblclick', () => { this.offset = 0; this.barW = 9; this.invalidate(); });
      cv.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        const p = this.local(e);
        if (this.opts.onContext && p.y < this.bottom && p.x < this.plotW()) this.opts.onContext(NZ.roundTick(this.pOf(p.y)), e);
      });
    }

    // ── drawing ──────────────────────────────────────────────
    draw() {
      const { ctx, W, H, data } = this;
      if (!W) return;
      ctx.setTransform(this.k, 0, 0, this.k, 0, 0);
      ctx.clearRect(0, 0, W, H);
      ctx.font = FONT;
      if (!data.length) return;

      const pw = this.plotW();
      const ph = H - AXIS_H;
      const volH = this.ind.vol ? ph * 0.16 : 0;
      this.top = 14;
      this.bottom = ph - volH - 8;

      let i0 = Math.max(0, this.iOf(0) - 1);
      let i1 = Math.min(data.length - 1, this.iOf(pw) + 1);
      if (i1 < i0) return;

      let hi = -Infinity, lo = Infinity, vmax = 0;
      for (let i = i0; i <= i1; i++) {
        const d = data[i];
        if (d.h > hi) hi = d.h;
        if (d.l < lo) lo = d.l;
        if (d.v > vmax) vmax = d.v;
      }
      if (hi === lo) { hi *= 1.001; lo *= 0.999; }
      const padP = (hi - lo) * 0.08;
      this.hi = hi + padP;
      this.lo = lo - padP;

      // grid + price axis
      const step = niceStep(this.hi - this.lo, Math.max(3, Math.floor((this.bottom - this.top) / 56)));
      const dec = step < 0.01 ? 4 : step < 1 ? 2 : step < 10 ? 2 : 0;
      ctx.strokeStyle = C.grid;
      ctx.lineWidth = 1;
      ctx.fillStyle = C.ink3;
      ctx.textBaseline = 'middle';
      ctx.textAlign = 'left';
      for (let p = Math.ceil(this.lo / step) * step; p <= this.hi; p += step) {
        const y = Math.round(this.yOf(p)) + 0.5;
        if (y < 4 || y > this.bottom + 4) continue;
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(pw, y); ctx.stroke();
        ctx.fillText(p.toFixed(dec), pw + 10, y);
      }

      // time axis
      const every = Math.max(1, Math.ceil(96 / this.barW));
      ctx.textAlign = 'center';
      ctx.textBaseline = 'alphabetic';
      for (let i = i0; i <= i1; i++) {
        const d = data[i];
        if ((d.t / this.tf) % every !== 0) continue;
        const x = Math.round(this.xOf(i)) + 0.5;
        if (x < 20 || x > pw - 20) continue;
        ctx.strokeStyle = C.grid;
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, ph); ctx.stroke();
        ctx.fillStyle = C.ink3;
        ctx.fillText(NZ.clock(d.t, this.tf < 60), x, H - 7);
      }
      ctx.strokeStyle = C.axis;
      ctx.beginPath(); ctx.moveTo(pw + 0.5, 0); ctx.lineTo(pw + 0.5, H); ctx.moveTo(0, ph + 0.5); ctx.lineTo(W, ph + 0.5); ctx.stroke();

      ctx.save();
      ctx.beginPath(); ctx.rect(0, 0, pw, ph); ctx.clip();

      // volume
      if (volH && vmax > 0) {
        for (let i = i0; i <= i1; i++) {
          const d = data[i];
          const h = (d.v / vmax) * volH;
          ctx.fillStyle = d.c >= d.o ? 'rgba(8,175,162,.22)' : 'rgba(229,72,77,.22)';
          const bw = Math.max(1, this.barW * 0.64);
          ctx.fillRect(this.xOf(i) - bw / 2, ph - h, bw, h);
        }
      }

      // price
      if (this.type === 'line') {
        const g = ctx.createLinearGradient(0, this.top, 0, this.bottom);
        g.addColorStop(0, 'rgba(8,175,162,.28)');
        g.addColorStop(1, 'rgba(8,175,162,0)');
        ctx.beginPath();
        for (let i = i0; i <= i1; i++) {
          const x = this.xOf(i), y = this.yOf(data[i].c);
          i === i0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        }
        ctx.strokeStyle = C.teal; ctx.lineWidth = 1.6; ctx.stroke();
        ctx.lineTo(this.xOf(i1), this.bottom + 8); ctx.lineTo(this.xOf(i0), this.bottom + 8); ctx.closePath();
        ctx.fillStyle = g; ctx.fill();
      } else {
        const bw = Math.max(1, Math.round(this.barW * 0.64));
        for (let i = i0; i <= i1; i++) {
          const d = data[i];
          const x = Math.round(this.xOf(i));
          const up = d.c >= d.o;
          ctx.fillStyle = ctx.strokeStyle = up ? C.teal : C.red;
          ctx.lineWidth = 1;
          ctx.beginPath(); ctx.moveTo(x + 0.5, Math.round(this.yOf(d.h))); ctx.lineTo(x + 0.5, Math.round(this.yOf(d.l))); ctx.stroke();
          const yo = this.yOf(d.o), yc = this.yOf(d.c);
          const top = Math.round(Math.min(yo, yc)), h = Math.max(1, Math.round(Math.abs(yc - yo)));
          ctx.fillRect(x - Math.floor(bw / 2) + 0.5 - 0.5, top, bw, h);
        }
      }

      // indicators
      const series = (vals, color, dash) => {
        ctx.beginPath();
        for (let i = i0; i <= i1; i++) {
          const x = this.xOf(i), y = this.yOf(vals[i]);
          i === i0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        }
        ctx.setLineDash(dash || []);
        ctx.strokeStyle = color; ctx.lineWidth = 1.2; ctx.stroke();
        ctx.setLineDash([]);
      };
      if (this.ind.ema9) series(ema(data, 9), C.ema9);
      if (this.ind.ema21) series(ema(data, 21), C.ema21);
      if (this.ind.vwap) series(vwap(data), C.vwap, [4, 3]);

      ctx.restore();

      // overlay lines (position, orders, alerts, bracket preview)
      const tags = [], placed = [];
      for (const ln of this.lines) {
        if (ln.price == null || ln.price > this.hi || ln.price < this.lo) continue;
        const y = Math.round(this.yOf(ln.price)) + 0.5;
        ctx.setLineDash(ln.dash || [6, 4]);
        ctx.strokeStyle = ln.color; ctx.lineWidth = 1;
        ctx.globalAlpha = 0.85;
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(pw, y); ctx.stroke();
        ctx.globalAlpha = 1;
        ctx.setLineDash([]);
        if (ln.label) {
          ctx.font = '500 10px Lexend, system-ui, sans-serif';
          const tw = ctx.measureText(ln.label).width + 14;
          let lx = 10;
          for (const p of placed) if (Math.abs(p.y - y) < 19 && lx < p.x2 + 6) lx = p.x2 + 6;
          placed.push({ y, x2: lx + tw });
          ctx.fillStyle = '#0e1011';
          ctx.strokeStyle = ln.color;
          this.roundRect(lx, y - 9, tw, 18, 3);
          ctx.fill(); ctx.stroke();
          ctx.fillStyle = ln.color;
          ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
          ctx.fillText(ln.label, lx + 7, y + 0.5);
          ctx.font = FONT;
        }
        tags.push({ y, text: NZ.px(ln.price), bg: ln.color, fg: ln.ink || '#000' });
      }

      // last price
      const last = data[data.length - 1];
      const ly = Math.round(this.yOf(last.c)) + 0.5;
      const lastUp = last.c >= last.o;
      if (ly >= 0 && ly <= ph) {
        ctx.setLineDash([2, 3]);
        ctx.strokeStyle = lastUp ? C.teal : C.red;
        ctx.beginPath(); ctx.moveTo(0, ly); ctx.lineTo(pw, ly); ctx.stroke();
        ctx.setLineDash([]);
        tags.push({ y: ly, text: NZ.px(last.c), bg: lastUp ? C.teal : C.red, fg: lastUp ? '#00201d' : '#fff', bold: true });
      }

      // crosshair
      const hv = this.hover;
      if (hv && hv.x < pw && hv.y < ph) {
        ctx.setLineDash([3, 3]);
        ctx.strokeStyle = 'rgba(255,255,255,.28)';
        const hx = Math.round(this.xOf(Math.max(i0, Math.min(i1, this.iOf(hv.x))))) + 0.5;
        const hy = Math.round(hv.y) + 0.5;
        ctx.beginPath(); ctx.moveTo(hx, 0); ctx.lineTo(hx, ph); ctx.moveTo(0, hy); ctx.lineTo(pw, hy); ctx.stroke();
        ctx.setLineDash([]);
        if (hy <= this.bottom + 8) tags.push({ y: hy, text: NZ.px(this.pOf(hv.y)), bg: C.tag, fg: C.white, line: 'rgba(255,255,255,.18)' });
        const hi2 = Math.max(i0, Math.min(i1, this.iOf(hv.x)));
        const label = NZ.clock(data[hi2].t, this.tf < 60);
        const tw = ctx.measureText(label).width + 14;
        ctx.fillStyle = C.tag;
        this.roundRect(hx - tw / 2, ph + 3, tw, 17, 3); ctx.fill();
        ctx.fillStyle = C.white; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText(label, hx, ph + 12);
      }

      // axis tags
      ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
      for (const t of tags) {
        ctx.font = (t.bold ? '600 ' : '500 ') + '10px Lexend, system-ui, sans-serif';
        ctx.fillStyle = t.bg;
        this.roundRect(pw + 3, t.y - 9, AXIS_W - 6, 18, 3);
        ctx.fill();
        if (t.line) { ctx.strokeStyle = t.line; ctx.stroke(); }
        ctx.fillStyle = t.fg;
        ctx.fillText(t.text, pw + 9, t.y + 0.5);
      }
      ctx.font = FONT;

      if (this.opts.onLegend) {
        const idx = hv && hv.x < pw ? Math.max(i0, Math.min(i1, this.iOf(hv.x))) : data.length - 1;
        this.opts.onLegend(data[idx], idx > 0 ? data[idx - 1] : null);
      }
    }

    roundRect(x, y, w, h, r) {
      const c = this.ctx;
      c.beginPath();
      c.moveTo(x + r, y);
      c.arcTo(x + w, y, x + w, y + h, r);
      c.arcTo(x + w, y + h, x, y + h, r);
      c.arcTo(x, y + h, x, y, r);
      c.arcTo(x, y, x + w, y, r);
      c.closePath();
    }
  }

  // small line chart (equity curve, sparklines)
  NZ.sparkline = (values, w = 90, h = 24) => {
    if (!values || values.length < 2) return '<svg class="spark"></svg>';
    let lo = Infinity, hi = -Infinity;
    for (const v of values) { if (v < lo) lo = v; if (v > hi) hi = v; }
    const span = hi - lo || 1;
    const pts = values.map((v, i) => `${((i / (values.length - 1)) * w).toFixed(1)},${(h - 2 - ((v - lo) / span) * (h - 4)).toFixed(1)}`).join(' ');
    const color = values[values.length - 1] >= values[0] ? C.teal : C.red;
    return `<svg class="spark" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"><polyline fill="none" stroke="${color}" stroke-width="1.4" stroke-linejoin="round" points="${pts}"/></svg>`;
  };

  NZ.Chart = Chart;
  NZ.colors = C;
})();
