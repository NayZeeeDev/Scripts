(() => {
  const NH = window.NH;

  NH.STATS = [
    { k: 'health', s: 'h', icon: 'heart', c: '#ff4d5e', label: 'Health' },
    { k: 'armor', s: 'a', icon: 'shield', c: '#4d8dff', label: 'Armor' },
    { k: 'hunger', s: 'hu', icon: 'burger', c: '#ffad33', label: 'Hunger' },
    { k: 'thirst', s: 'th', icon: 'drop', c: '#33c4ff', label: 'Thirst' },
    { k: 'stamina', s: 'st', icon: 'bolt', c: '#4ade80', label: 'Stamina' },
    { k: 'stress', s: 'sr', icon: 'brain', c: '#c084fc', label: 'Stress' },
    { k: 'oxygen', s: 'ox', icon: 'bubbles', c: '#5eead4', label: 'Oxygen' },
    { k: 'voice', s: 'vr', icon: 'mic', c: '#e7ebf0', label: 'Voice' },
  ];

  let uid = 0;
  const svgShape = (shape, extra = '') =>
    `<svg class="sv" viewBox="0 0 40 40">${shape('bgc')}${shape('trk')}${shape('fil')}${extra}</svg>`;

  const SHAPES = {
    circle: c => `<circle class="${c}" cx="20" cy="20" r="16.5" pathLength="100" transform="rotate(-90 20 20)"/>`,
    squircle: c => `<rect class="${c}" x="4" y="4" width="32" height="32" rx="10.5" pathLength="100"/>`,
    hexagon: c => `<polygon class="${c}" points="20,3.5 34.3,11.75 34.3,28.25 20,36.5 5.7,28.25 5.7,11.75" pathLength="100"/>`,
    diamond: c => `<polygon class="${c}" points="20,2.8 37.2,20 20,37.2 2.8,20" pathLength="100"/>`,
    arc: c => `<path class="${c}" d="M8.3 31.7A16.5 16.5 0 1 1 31.7 31.7" pathLength="100"/>`,
  };

  // Each style returns the inner HTML for one stat. Values drive CSS through --v (0-100).
  NH.STATUS_STYLES = {
    ring:      { label: 'Ring',          html: s => svgShape(SHAPES.circle) + `<i class="ico">${NH.fic(s.icon)}</i>` },
    ringValue: { label: 'Ring + Value',  html: s => svgShape(SHAPES.circle) + `<b class="val">0</b>` },
    segmented: {
      label: 'Segmented',
      html: s => {
        const id = 'sg' + (++uid);
        return `<svg class="sv" viewBox="0 0 40 40"><defs><mask id="${id}"><circle cx="20" cy="20" r="16.2" fill="none" stroke="#fff" stroke-width="4.6" stroke-dasharray="1.5 1.1" pathLength="100"/></mask></defs>` +
          `<circle class="bgc" cx="20" cy="20" r="14"/><g mask="url(#${id})"><circle class="trk w" cx="20" cy="20" r="16.2" pathLength="100" transform="rotate(-90 20 20)"/><circle class="fil w" cx="20" cy="20" r="16.2" pathLength="100" transform="rotate(-90 20 20)"/></g></svg>` +
          `<i class="ico">${NH.fic(s.icon)}</i>`;
      },
    },
    squircle:  { label: 'Squircle',      html: s => svgShape(SHAPES.squircle) + `<i class="ico">${NH.fic(s.icon)}</i>` },
    hexagon:   { label: 'Hexagon',       html: s => svgShape(SHAPES.hexagon) + `<i class="ico">${NH.fic(s.icon)}</i>` },
    diamond:   { label: 'Diamond',       html: s => svgShape(SHAPES.diamond) + `<i class="ico sm">${NH.fic(s.icon)}</i>` },
    arc:       { label: 'Arc Gauge',     html: s => svgShape(SHAPES.arc) + `<i class="ico">${NH.fic(s.icon)}</i>` },
    liquid:    { label: 'Liquid Fill',   html: s => `<div class="liq" style="-webkit-mask-image:${NH.maskUrl(s.icon)};mask-image:${NH.maskUrl(s.icon)}"></div>` },
    hexfill:   { label: 'Hex Fill',      html: s => `<div class="hx"><div class="hxi"><span class="lf"></span><i class="ico">${NH.fic(s.icon)}</i></div></div>` },
    circlefill:{ label: 'Circle Fill',   html: s => `<div class="cf"><span class="lf"></span><i class="ico">${NH.fic(s.icon)}</i></div>` },
    squarefill:{ label: 'Square Fill',   html: s => `<div class="sqf"><span class="lf"></span><i class="ico">${NH.fic(s.icon)}</i></div>` },
    bars:      { label: 'Icon + Bar',    html: s => `<i class="ico c">${NH.fic(s.icon)}</i><div class="bar"><span></span></div>` },
    pill:      { label: 'Pill',          html: s => `<div class="pl"><span class="pf"></span><i class="ico">${NH.fic(s.icon)}</i><b class="val">0</b></div>` },
    vertical:  { label: 'Vertical',      html: s => `<div class="vb"><span></span></div><i class="ico c">${NH.fic(s.icon)}</i>` },
    minimal:   { label: 'Minimal',       html: s => `<i class="ico c">${NH.fic(s.icon)}</i><div class="ml"><span></span></div>` },
    dots:      { label: 'Dots',          html: s => `<i class="ico c">${NH.fic(s.icon)}</i><div class="dt"><span></span></div>` },
  };

  const colorFor = (stat, mode) => mode === 'accent' ? 'var(--accent)' : mode === 'mono' ? '#f2f4f0' : stat.c;
  const rgbFor = (stat, mode) => mode === 'accent' ? 'var(--accent-rgb)' : mode === 'mono' ? '242,244,240' : NH.hexToRgb(stat.c);

  function makeStat(stat, style, colorMode) {
    const el = document.createElement('div');
    el.className = `st st-${style}`;
    el.dataset.k = stat.k;
    el.style.setProperty('--c', colorFor(stat, colorMode));
    el.style.setProperty('--cr', rgbFor(stat, colorMode));
    el.innerHTML = (NH.STATUS_STYLES[style] || NH.STATUS_STYLES.ring).html(stat);
    return { el, val: el.querySelector('.val'), v: -1, cls: '' };
  }

  function setStat(item, v, flags) {
    if (v !== item.v) {
      item.v = v;
      item.el.style.setProperty('--v', v);
      if (item.val) item.val.textContent = Math.round(v);
    }
    if (flags !== item.cls) {
      item.cls = flags;
      item.el.className = `st st-${item.style}${flags}`;
    }
  }

  const status = NH.status = {
    root: null, items: {}, style: null, color: null,

    build(root) {
      this.root = root;
      root.innerHTML = '<div class="row"></div>';
      this.row = root.firstChild;
    },

    rebuild() {
      const st = NH.cur.status;
      this.style = st.style;
      this.color = st.color;
      this.row.innerHTML = '';
      this.items = {};
      for (const stat of NH.STATS) {
        const item = makeStat(stat, st.style, st.color);
        item.style = st.style;
        this.items[stat.k] = item;
        this.row.appendChild(item.el);
      }
      this.render(true);
    },

    apply() {
      const st = NH.cur.status;
      if (st.style !== this.style || st.color !== this.color) this.rebuild();
      this.root.classList.toggle('col', st.dir === 'col');
      this.render(true);
    },

    render() {
      const S = NH.S, st = NH.cur.status, edit = NH.editing;
      const auto = st.autoHide && !edit;
      for (const stat of NH.STATS) {
        const item = this.items[stat.k];
        if (!item) continue;
        let v = S[stat.s];
        let hide = !st.show[stat.k];
        let flags = '';
        if (stat.k === 'voice') {
          const range = S.vr || 2;
          v = Math.min(100, Math.round(range / 3 * 100));
          if (S.tk) flags += ' talk';
          if (S.rd) flags += ' radio';
        } else if (stat.k === 'oxygen') {
          if (v === false || v === undefined) { v = 100; if (!edit) hide = true; }
        } else {
          if (v === undefined || v === false) v = stat.k === 'stress' || stat.k === 'armor' ? 0 : 100;
          if (auto && stat.k === 'armor' && v <= 0) hide = true;
          if (auto && stat.k === 'stress' && v <= 0) hide = true;
          if (auto && stat.k === 'stamina' && v >= 100) hide = true;
          if (stat.k === 'stress' ? v >= 80 : v <= 20) flags += ' low';
        }
        if (edit && st.show[stat.k]) hide = false;
        if (hide) flags += ' hide';
        if (v <= 0) flags += ' zero';
        setStat(item, v, flags);
      }
    },

    // Static preview for the settings cards
    preview(style, colorMode, stats = ['health', 'armor', 'hunger']) {
      const wrap = document.createElement('div');
      wrap.className = 'w-status pv-status';
      const row = document.createElement('div');
      row.className = 'row';
      wrap.appendChild(row);
      const demo = { health: 78, armor: 54, hunger: 66, thirst: 41, stamina: 88, stress: 22, oxygen: 70, voice: 66 };
      for (const k of stats) {
        const stat = NH.STATS.find(s => s.k === k);
        const item = makeStat(stat, style, colorMode);
        item.style = style;
        setStat(item, demo[k], '');
        row.appendChild(item.el);
      }
      return wrap;
    },
  };
})();
