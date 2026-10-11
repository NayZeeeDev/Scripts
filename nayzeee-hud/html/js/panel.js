(() => {
  const NH = window.NH;
  const ic = NH.ic;

  const btn = (a, icon, label, i, tag) =>
    `<button class="vb" data-a="${a}"${i !== undefined ? ` data-i="${i}"` : ''}>${tag ? `<i class="tag">${tag}</i>` : ''}${ic(icon)}<span>${label}</span></button>`;

  const GROUPS = [
    [btn('engine', 'power', 'Engine'), btn('lock', 'lock', 'Lock'), btn('door', 'hood', 'Hood', 4), btn('door', 'trunk', 'Trunk', 5)],
    [btn('left', 'arrowL', 'Left'), btn('hazard', 'hazard', 'Hazard'), btn('right', 'arrowR', 'Right'), btn('lights', 'light', 'Lights'), btn('cruise', 'gauge', 'Cruise'), btn('neon', 'star', 'Neon')],
    [btn('door', 'door', 'Door', 0, 'FL'), btn('door', 'door', 'Door', 1, 'FR'), btn('door', 'door', 'Door', 2, 'RL'), btn('door', 'door', 'Door', 3, 'RR')],
    [btn('window', 'window', 'Window', 0, 'FL'), btn('window', 'window', 'Window', 1, 'FR'), btn('window', 'window', 'Window', 2, 'RL'), btn('window', 'window', 'Window', 3, 'RR')],
  ];

  // seat buttons follow the vehicle: Driver, Pass, then RL / RR (or R1L, R1R, R2L ... on bigger vehicles)
  const seatTag = (k, n) => {
    if (k === 0) return 'Driver';
    if (k === 1) return 'Pass';
    const row = Math.floor((k - 2) / 2) + 1, side = (k - 2) % 2 ? 'R' : 'L';
    return n <= 4 ? `R${side}` : `R${row}${side}`;
  };
  const seatGroup = (n) => {
    n = Math.max(2, Math.min(12, n));
    const cols = Math.max(2, Math.ceil(n / 2));
    return `<div class="vg seats" style="grid-template-columns:repeat(${cols},58px)">${Array.from({ length: n }, (_, k) => btn('seat', 'seat', 'Seat', k - 1, seatTag(k, n))).join('')}</div>`;
  };

  const DEMO = { engine: true, lock: false, ind: 0, lights: true, cruise: false, neon: false, driver: true, doors: [0, 0, 0, 0, 0, 0], windows: [0, 0, 0, 0], seats: [2, 0, 1, 0, 0, 1] };

  const panel = NH.panel = {
    el: null, state: null, isOpen: false,

    build() {
      const el = this.el = document.getElementById('panel');
      el.innerHTML = `<div class="vp panel"><div class="vp-hd"><b>Vehicle Controls</b><small>ESC to close</small></div><div class="vp-g">${GROUPS.map(g => `<div class="vg c${g.length}">${g.join('')}</div>`).join('')}${seatGroup(4)}</div></div>`;
      this.seatCount = 4;
      el.addEventListener('click', (e) => {
        const b = e.target.closest('.vb');
        if (!b || b.classList.contains('dis')) return;
        this.action(b.dataset.a, b.dataset.i !== undefined ? +b.dataset.i : undefined, b);
      });
    },

    open(state) {
      this.state = state || NH.clone(DEMO);
      this.isOpen = true;
      this.el.classList.add('open');
      this.render();
    },

    close(notify = true) {
      if (!this.isOpen) return;
      this.isOpen = false;
      this.el.classList.remove('open');
      if (notify) NH.post('close');
    },

    async action(a, i, b) {
      b.classList.toggle('on'); // optimistic
      NH.sfx?.('click');
      if (!NH.IS_GAME) { this.demoAction(a, i); return; }
      const s = await NH.post('vehAction', { a, i });
      if (s) { this.state = s; this.render(); }
    },

    demoAction(a, i) {
      const s = this.state;
      if (a === 'engine' || a === 'lock' || a === 'lights' || a === 'cruise' || a === 'neon') s[a] = !s[a];
      else if (a === 'left') s.ind = s.ind === 1 ? 0 : 1;
      else if (a === 'right') s.ind = s.ind === 2 ? 0 : 2;
      else if (a === 'hazard') s.ind = s.ind === 3 ? 0 : 3;
      else if (a === 'door') s.doors[i] = s.doors[i] ? 0 : 1;
      else if (a === 'window') s.windows[i] = s.windows[i] ? 0 : 1;
      else if (a === 'seat' && s.seats[i + 1] === 0) { s.seats = s.seats.map(v => (v === 2 ? 0 : v)); s.seats[i + 1] = 2; }
      this.render();
    },

    render() {
      const s = this.state;
      const n = Math.max(2, Math.min(12, (s.seats || []).length));
      if (n !== this.seatCount) {
        this.seatCount = n;
        this.el.querySelector('.vg.seats').outerHTML = seatGroup(n);
      }
      this.el.querySelectorAll('.vb').forEach(b => {
        const a = b.dataset.a, i = b.dataset.i !== undefined ? +b.dataset.i : null;
        let on = false, dis = false;
        switch (a) {
          case 'engine': on = s.engine; dis = !s.driver; break;
          case 'lock': on = s.lock; b.querySelector('svg').innerHTML = NH.ICONS[s.lock ? 'lock' : 'unlock']; break;
          case 'left': on = s.ind === 1; dis = !s.driver; break;
          case 'right': on = s.ind === 2; dis = !s.driver; break;
          case 'hazard': on = s.ind === 3; dis = !s.driver; break;
          case 'lights': on = s.lights; dis = !s.driver; break;
          case 'cruise': on = s.cruise; dis = !s.driver; break;
          case 'neon': on = s.neon; break;
          case 'door': on = s.doors[i] === 1; dis = s.doors[i] === -1; break;
          case 'window': on = s.windows[i] === 1; dis = s.windows[i] === -1; break;
          case 'seat': on = s.seats[i + 1] === 2; dis = s.seats[i + 1] !== 0 && s.seats[i + 1] !== 2; break;
        }
        b.classList.toggle('on', !!on);
        b.classList.toggle('dis', !!dis);
      });
    },
  };
})();
