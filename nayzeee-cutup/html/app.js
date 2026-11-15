'use strict';
/* =====================================================================
   CUT UP - NayZeee Development
   HUD, popups, threat arrows, toasts, run summary, leaderboard, menu
   ===================================================================== */

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-cutup';
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

function el(tag, cls, html) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html !== undefined) e.innerHTML = html;
    return e;
}
function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
    }).then(r => r.json()).catch(() => ({}));
}
const fmt = n => Math.floor(Number(n) || 0).toLocaleString('en-US');
const compact = n => n >= 1e6 ? (n / 1e6).toFixed(1).replace(/\.0$/, '') + 'M' : n >= 1e4 ? (n / 1e3).toFixed(1).replace(/\.0$/, '') + 'K' : String(n);
const mmss = s => { s = Math.max(0, Math.floor(s)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
function hexRgb(hex) {
    const m = /^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i.exec(hex || '');
    return m ? `${parseInt(m[1], 16)}, ${parseInt(m[2], 16)}, ${parseInt(m[3], 16)}` : '168, 115, 255';
}
function hashColor(str) {
    let h = 0;
    for (const c of String(str)) h = (h * 31 + c.charCodeAt(0)) | 0;
    return `hsl(${Math.abs(h) % 360}, 55%, 45%)`;
}
const getPath = (o, p) => p.split('.').reduce((a, k) => a?.[k], o);
function setPath(o, p, v) { const k = p.split('.'); const last = k.pop(); k.reduce((a, x) => a[x], o)[last] = v; }

const State = {
    config: null, hud: { show: true, tacho: true, pb: true, bonuses: true, popups: true }, ui: {},
    settings: null, profile: {}, crewData: { crew: null, invites: [] }, cameraModes: [],
    menuOpen: false, menuTab: 'camera', boardOpen: false, board: 'solo', boardData: null, units: 'kmh',
};

/* ============================== THEME ============================== */
const Theme = {
    apply(ui) {
        if (!ui) return;
        State.ui = ui;
        const r = document.documentElement.style;
        r.setProperty('--accent', ui.accent); r.setProperty('--accent-rgb', hexRgb(ui.accent));
        r.setProperty('--accent2', ui.accent2); r.setProperty('--accent2-rgb', hexRgb(ui.accent2));
        r.setProperty('--alert', ui.alert); r.setProperty('--alert-rgb', hexRgb(ui.alert));
        r.setProperty('--scale', ui.scale || 1);
        document.body.classList.toggle('reduce-motion', !!ui.reduceMotion);
        $('#toasts').className = ui.toastPosition || 'top-right';
    },
};

/* ============================== SOUND (synthesised, no files) ============================== */
const Sound = {
    ctx: null,
    tone(freq, dur, type = 'sine', vol = .25, when = 0, slide = 0) {
        const ui = State.ui;
        if (!ui.sounds) return;
        this.ctx = this.ctx || new (window.AudioContext || window.webkitAudioContext)();
        const t = this.ctx.currentTime + when;
        const o = this.ctx.createOscillator(), g = this.ctx.createGain();
        o.type = type; o.frequency.setValueAtTime(freq, t);
        if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, freq + slide), t + dur);
        g.gain.setValueAtTime(vol * (ui.volume ?? .7), t);
        g.gain.exponentialRampToValueAtTime(.0001, t + dur);
        o.connect(g).connect(this.ctx.destination);
        o.start(t); o.stop(t + dur + .02);
    },
    noise(dur, vol = .3) {
        if (!State.ui.sounds) return;
        this.ctx = this.ctx || new (window.AudioContext || window.webkitAudioContext)();
        const len = this.ctx.sampleRate * dur, buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate), d = buf.getChannelData(0);
        for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len);
        const src = this.ctx.createBufferSource(), f = this.ctx.createBiquadFilter(), g = this.ctx.createGain();
        f.type = 'lowpass'; f.frequency.value = 600; g.gain.value = vol * (State.ui.volume ?? .7);
        src.buffer = buf; src.connect(f).connect(g).connect(this.ctx.destination); src.start();
    },
    play(name) {
        switch (name) {
            case 'pass': this.tone(880, .07, 'sine', .12); break;
            case 'insane': this.tone(990, .06, 'triangle', .16); this.tone(1480, .1, 'triangle', .16, .06); break;
            case 'crash': this.noise(.45, .5); this.tone(120, .4, 'sawtooth', .18, 0, -70); break;
            case 'shift': this.tone(240, .04, 'square', .07); break;
            case 'grind': this.tone(90, .25, 'sawtooth', .2); this.noise(.2, .2); break;
            case 'flow': [523, 659, 784, 1046].forEach((f, i) => this.tone(f, .22, 'triangle', .12, i * .07)); break;
            case 'start': this.tone(300, .35, 'sawtooth', .1, 0, 600); break;
            case 'end': this.tone(700, .45, 'triangle', .14, 0, -450); break;
            case 'rankup': [392, 523, 659, 784, 1046].forEach((f, i) => this.tone(f, .3, 'triangle', .14, i * .09)); break;
            case 'ui': this.tone(660, .04, 'sine', .07); break;
        }
    },
};

/* ============================== HUD ============================== */
const HUD = {
    lastHearts: null,
    init() {
        const dots = $('#t-dots');
        for (let i = 0; i < 9; i++) dots.appendChild(el('i'));
    },
    applyConfig() {
        const h = State.hud;
        $('#h-tacho').classList.toggle('hidden', !h.tacho);
        $('#h-pb').classList.toggle('hidden', !h.pb);
        $('#h-bonus').classList.toggle('hidden', !h.bonuses);
    },
    update(d) {
        const show = d.active && State.hud.show;
        $('#hud').classList.toggle('hidden', !show);
        if (!show) return;
        State.units = d.unit === 'MPH' ? 'mph' : 'kmh';

        const panel = $('.score-panel');
        panel.classList.toggle('idle', !d.run);
        $('#h-combo').textContent = `${d.combo}X`;
        $('#h-speedmult').textContent = `${Number(d.speedMult).toFixed(1)}X`;
        $('#h-timer').textContent = mmss(d.timer);
        $('#h-mult').textContent = `${Number(d.mult).toFixed(1)}X`;
        $('#h-hold').style.width = `${(d.hold * 100).toFixed(1)}%`;
        $('#h-score').textContent = d.run ? `${fmt(d.score)} PTS` : 'CUT UP  ·  READY';

        // hearts
        const pills = $('#h-pills');
        if (pills.children.length !== d.maxHearts) {
            pills.innerHTML = '';
            for (let i = 0; i < d.maxHearts; i++) pills.appendChild(el('i'));
        }
        Array.from(pills.children).forEach((p, i) => p.classList.toggle('off', i >= d.hearts));
        if (this.lastHearts !== null && d.hearts < this.lastHearts) {
            const h = $('#h-hearts'); h.classList.remove('hit'); void h.offsetWidth; h.classList.add('hit');
        }
        this.lastHearts = d.hearts;

        // bonuses
        $$('#b-aggro i').forEach((s, i) => s.classList.toggle('on', i < d.aggro));
        $('#b-aggro').parentElement.classList.toggle('on', d.aggro > 0);
        $('#b-physics').classList.toggle('on', d.physics);
        $('#b-physics').parentElement.classList.toggle('on', d.physics);
        $('#b-fpv').classList.toggle('on', d.fpv);
        $('#b-fpv').parentElement.classList.toggle('on', d.fpv);
        const s = d.sync || {};
        $('#b-sync').classList.toggle('on', !!s.flow);
        $('#b-syncwrap').classList.toggle('on', !!s.flow);
        $('#b-synclabel').textContent = s.flow && s.crew ? 'Crew Flow' : 'Sync';

        // sync panel
        const sp = $('#h-sync');
        const syncing = s.pct > 0 && s.partner;
        sp.classList.toggle('hidden', !syncing);
        if (syncing) {
            sp.classList.toggle('flow', !!s.flow);
            $('#s-title').textContent = s.flow ? (s.crew ? 'CREW FLOW' : 'FLOW STATE') : `SYNCING ${Math.floor(s.pct)}%`;
            const mates = s.crew && s.mates > 1 ? ` +${s.mates - 1}` : '';
            $('#s-partner').textContent = `with ${s.partner}${mates}`;
            $('#s-fill').style.width = `${s.pct}%`;
            const used = s.gapMax > 0 ? clamp(s.gap / s.gapMax, 0, 1) : 0;
            const g = $('#s-gap');
            g.style.width = `${used * 100}%`;
            g.style.background = used < .6 ? 'var(--ok)' : used < .85 ? 'var(--warn)' : 'var(--alert)';
            $('#s-gaptext').textContent = `${Math.floor(s.gap)} / ${Math.floor(s.gapMax)} m`;
        }

        // PB + rank
        const rank = d.rank || {};
        $('#pb-val').textContent = fmt(d.pb);
        $('#pb-mode').textContent = d.pbMode;
        $('#pb-pos').textContent = d.position > 0 ? `#${compact(d.position)}` : '#-';
        $('#rank-fill').style.width = `${rank.pct || 0}%`;
        $('.rank-bar').style.setProperty('--rank', rank.color || 'var(--blue)');
        $('#rank-name').textContent = rank.name || '';
        $('#rank-pct').textContent = `${rank.pct || 0}%`;
        $('#rank-next').textContent = rank.nextName ? `${fmt(rank.toNext)} PTS to ${rank.nextName}` : 'MAX RANK';

        // tacho
        const rpm = clamp(d.rpmNorm, 0, 1);
        $('#t-gear').textContent = d.gear;
        $('#t-rpmring').style.setProperty('--p', rpm);
        $('#t-rpmring').classList.toggle('limit', rpm > .97);
        $('#t-rpm').textContent = d.rpm;
        const dots = $('#t-dots'), lit = Math.round(clamp((rpm - .55) / .42, 0, 1) * 9);
        Array.from(dots.children).forEach((dot, i) => { dot.className = i < lit ? (i < 3 ? 'g' : i < 7 ? 'y' : 'r') : ''; });
        dots.classList.toggle('flash', rpm > .97);
        $('#t-speedring').style.setProperty('--p', clamp(d.speed / (d.unit === 'MPH' ? 220 : 350), 0, 1));
        $('#t-speed').textContent = d.speed;
        $('#t-unit').textContent = d.unit;
        $('#t-a').classList.toggle('on', d.trans === 'auto');
        $('#t-m').classList.toggle('on', d.trans === 'hpattern');
        $('#t-s').classList.toggle('on', d.trans === 'sequential');
        $('#t-abs').classList.toggle('on', d.abs);
        $('#t-tc').classList.toggle('on', d.tc);
        $('#t-wheel').classList.toggle('hidden', !d.wheel);
    },
};

/* ============================== POPUPS ============================== */
const Popups = {
    show(d) {
        if (!State.hud.popups) return;
        const box = $('#popups');
        while (box.children.length > 3) box.firstChild.remove();
        const p = el('div', 'popup');
        p.style.color = d.color || '#fff';
        let html = `<b>${esc(d.text)}</b>`;
        if (d.sub) html += `<small>${esc(d.sub)}</small>`;
        if (d.points) html += `<em class="${d.points < 0 ? 'neg' : ''}">${d.points < 0 ? '' : '+'}${fmt(d.points)}</em>`;
        p.innerHTML = html;
        box.appendChild(p);
        // push older popups down by the new one's real height
        const shift = p.offsetHeight + 8;
        Array.from(box.children).forEach(c => { if (c !== p) c.style.top = `${(parseFloat(c.style.top) || 0) + shift}px`; });
        setTimeout(() => p.remove(), 1300);
    },
};

/* ============================== THREAT ARROWS ============================== */
const Arrows = {
    pool: [],
    render(list) {
        const box = $('#arrows');
        while (this.pool.length < list.length) {
            const a = el('div', 'arrow', '<i></i><span></span>');
            box.appendChild(a); this.pool.push(a);
        }
        const rx = window.innerWidth * .2, ry = window.innerHeight * .24;
        this.pool.forEach((a, i) => {
            const d = list[i];
            if (!d) { a.style.opacity = 0; return; }
            const rad = d.angle * Math.PI / 180;
            const x = Math.sin(rad) * rx, y = -Math.cos(rad) * ry;
            a.style.opacity = .35 + d.intensity * .65;
            a.style.transform = `translate(${x}px, ${y}px) rotate(${d.angle}deg) scale(${.75 + d.intensity * .45})`;
            a.classList.toggle('hot', d.closing && d.intensity > .6);
            const label = a.querySelector('span');
            label.textContent = `${d.name} · ${d.dist}m`;
            label.style.transform = `rotate(${-d.angle}deg)`;
        });
    },
};

/* ============================== TOASTS ============================== */
const Toasts = {
    show(d) {
        const box = $('#toasts');
        const t = el('div', `toast glass ${d.kind || 'info'}`, `<div><b>${esc(d.title)}</b>${d.msg ? `<p>${esc(d.msg)}</p>` : ''}</div>`);
        box.appendChild(t);
        while (box.children.length > 5) box.firstChild.remove();
        setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 300); }, 4200);
    },
};

/* ============================== RUN SUMMARY ============================== */
const Summary = {
    timer: null,
    show(d) {
        const r = d.run || {};
        const kmh = d.units !== 'mph';
        const speed = kmh ? `${Math.round(r.avgSpeed * 3.6)} km/h` : `${Math.round(r.avgSpeed * 2.237)} mph`;
        $('#sum-reason').textContent = d.reason || 'RUN OVER';
        $('#sum-points').textContent = fmt(r.points);
        $('#sum-badges').innerHTML = r.crewRun ? '<span class="badge crew">CREW RUN</span>' : '';
        const stats = [
            ['Max Combo', `${fmt(r.maxCombo)}x`], ['Cars Passed', fmt(r.carsPassed)], ['Avg Speed', speed],
            ['Distance', `${(r.distance / 1000).toFixed(1)} km`], ['Time', mmss(r.time)], ['Crashes', r.crashes],
            ['Car', r.car], ['Map', r.map], ['Camera', r.camera],
        ];
        $('#sum-grid').innerHTML = stats.map(([k, v]) => `<div><span>${k}</span><b>${esc(v)}</b></div>`).join('');
        $('#summary').classList.remove('hidden');
        clearTimeout(this.timer);
        this.timer = setTimeout(() => $('#summary').classList.add('hidden'), 9000);
    },
    result(res) {
        if (!res || !res.ok) return;
        const b = $('#sum-badges');
        if (res.newPB) b.insertAdjacentHTML('beforeend', '<span class="badge">NEW PB</span>');
        if (res.position) b.insertAdjacentHTML('beforeend', `<span class="badge">#${fmt(res.position)}</span>`);
        if (res.rankUp) b.insertAdjacentHTML('beforeend', `<span class="badge">${esc(res.rankUp)}</span>`);
    },
};

/* ============================== LEADERBOARD ============================== */
const CHEV = '<svg viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>';
const FLAG = '<svg viewBox="0 0 24 24"><path d="M5 21V4M5 4h11l-2 4 2 4H5"/></svg>';

const Board = {
    open() {
        State.boardOpen = true;
        $('#board').classList.remove('hidden');
        $('#board-search').value = '';
        this.select(State.board);
    },
    close() {
        State.boardOpen = false;
        $('#board').classList.add('hidden');
    },
    select(board) {
        State.board = board;
        $$('#board-tabs button').forEach(b => b.classList.toggle('active', b.dataset.board === board));
        $('#board-rows').innerHTML = '<div class="board-empty">Loading...</div>';
        $('#board-me').innerHTML = '';
        post('leaderboard', { board });
    },
    cols(board) {
        return board === 'crews'
            ? { cols: '7rem 2.6fr 1.5fr 1fr 2fr 1.5fr 1.5rem', head: ['Position', 'Crew', 'Points', 'Members', 'Best Driver', 'Best Run', ''] }
            : { cols: '7rem 2.3fr 1.4fr 1fr 2fr 1.1fr 1fr .8fr 1.3fr 1.5rem', head: ['Position', 'Player', 'Points', 'Combo', 'Car', 'Avg Speed', 'Distance', 'Time', 'Map', ''] };
    },
    badge(pos) {
        const cls = pos === 1 ? 'p1' : pos === 2 ? 'p2' : pos === 3 ? 'p3' : '';
        return `<span class="pos-badge ${cls}">${FLAG}#${pos}</span>`;
    },
    speed(ms) { return State.units === 'mph' ? `${Math.round(ms * 2.237)} mph` : `${Math.round(ms * 3.6)} km/h`; },
    row(r, board, isMe) {
        const wrap = el('div', `brow${r.pos === 1 ? ' p1' : ''}${isMe ? ' me' : ''}`);
        if (board === 'crews') {
            wrap.innerHTML = `<div class="brow-main">
                <div>${this.badge(r.pos)}</div>
                <div class="player-cell"><span class="crew-chip" style="background:${esc(r.color)}">${esc(r.tag)}</span><span>${esc(r.name)}</span></div>
                <div class="num">${fmt(r.points)}</div>
                <div>${r.members}</div>
                <div>${esc(r.bestName || '-')}</div>
                <div class="num muted">${fmt(r.bestPoints)}</div>
                <div></div></div>`;
            return wrap;
        }
        const initial = esc((r.name || '?').trim().charAt(0).toUpperCase());
        const chip = r.crew ? `<span class="crew-chip" style="background:${esc(r.crew.color)}">${esc(r.crew.tag)}</span>` : '';
        wrap.innerHTML = `<div class="brow-main">
            <div>${this.badge(r.pos)}</div>
            <div class="player-cell"><span class="avatar" style="background:${r.crew ? esc(r.crew.color) : hashColor(r.name)}">${initial}</span><span>${esc(r.name)}</span>${chip}</div>
            <div class="num">${fmt(r.points)}</div>
            <div><span class="num">${fmt(r.combo)}x</span></div>
            <div>${esc(r.car)}</div>
            <div>${this.speed(r.avgSpeed)}</div>
            <div>${Math.round(r.distance / 1000)} km</div>
            <div>${mmss(r.time)}</div>
            <div>${esc(r.map)}</div>
            <div class="chev">${CHEV}</div></div>
            <div class="brow-detail">
                <div><span>Server Played On:</span><b>${esc(r.server)}</b></div>
                <div><span>Traffic Density:</span><b>${esc(r.density)}</b></div>
                <div><span>Transmission:</span><b>${esc(r.transmission)}</b></div>
                <div><span>AVG Proximity:</span><b>${r.avgProximity}x</b></div>
                <div><span>Cars Passed:</span><b>${fmt(r.carsPassed)}</b></div>
                <div><span>Camera Type:</span><b>${esc(r.camera)}</b></div>
            </div>`;
        wrap.addEventListener('click', () => wrap.classList.toggle('open'));
        return wrap;
    },
    render(data) {
        if (data) State.boardData = data;
        data = State.boardData;
        if (!data || data.board !== State.board) return;
        const { cols, head } = this.cols(data.board);
        $('.board-table').style.setProperty('--cols', cols);
        $('#board-head').innerHTML = head.map(h => `<div>${h}</div>`).join('');
        const q = $('#board-search').value.trim().toLowerCase();
        const rows = $('#board-rows');
        rows.innerHTML = '';
        const list = data.rows.filter(r => !q || [r.name, r.car, r.tag, r.crew && r.crew.tag, r.crew && r.crew.name, r.map]
            .some(v => v && String(v).toLowerCase().includes(q)));
        if (!list.length) rows.innerHTML = '<div class="board-empty">No runs on this board yet. Go set one.</div>';
        list.forEach(r => rows.appendChild(this.row(r, data.board, r.pos === data.myPos)));
        const me = $('#board-me');
        me.innerHTML = '';
        if (data.me && data.myPos > data.rows.length) me.appendChild(this.row(data.me, data.board, true));
    },
};

/* ============================== MENU ============================== */
const ICONS = {
    camera: '<svg viewBox="0 0 24 24"><path d="M3 7h4l2-3h6l2 3h4v12H3z"/><circle cx="12" cy="13" r="3.5"/></svg>',
    driving: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2"/><path d="M12 14v7M10.2 11L3.5 9M13.8 11l6.7-2"/></svg>',
    wheel: '<svg viewBox="0 0 24 24"><path d="M6 8h12M6 16h12M8 8v8M16 8v8"/><circle cx="6" cy="8" r="2"/><circle cx="18" cy="16" r="2"/></svg>',
    crew: '<svg viewBox="0 0 24 24"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.6-3.6 3.3-5.5 6.5-5.5s5.9 1.9 6.5 5.5"/><circle cx="17" cy="9" r="2.5"/><path d="M16.5 14.6c2.6 0 4.5 1.6 5 4.4"/></svg>',
    profile: '<svg viewBox="0 0 24 24"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></svg>',
    interface: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="8" cy="10" r="1.3"/><circle cx="12" cy="7.5" r="1.3"/><circle cx="16" cy="10" r="1.3"/><path d="M12 21c-1.5 0-2-1-2-2 0-1.5 1-2 2.5-2H15a6 6 0 0 0 6-6"/></svg>',
};
const CAM_ICONS = {
    cockpit: '<svg viewBox="0 0 24 24"><circle cx="12" cy="13" r="7"/><circle cx="12" cy="13" r="1.5"/><path d="M5 13h5.5M13.5 13H19M12 14.5V20"/></svg>',
    hood: '<svg viewBox="0 0 24 24"><path d="M3 17l3-6h12l3 6zM8 11l2-4h4l2 4"/></svg>',
    bumper: '<svg viewBox="0 0 24 24"><path d="M3 15h18M5 15v3h3v-3M16 15v3h3v-3M4 15l2-5h12l2 5"/></svg>',
    chase_near: '<svg viewBox="0 0 24 24"><rect x="7" y="10" width="10" height="6" rx="2"/><path d="M12 22v-4M9 4l3 3 3-3"/></svg>',
    chase_far: '<svg viewBox="0 0 24 24"><rect x="9" y="6" width="6" height="4" rx="1"/><path d="M12 22v-9M8 18l4-3 4 3"/></svg>',
    cinematic: '<svg viewBox="0 0 24 24"><rect x="2" y="6" width="14" height="12" rx="2"/><path d="M16 10l6-3v10l-6-3"/></svg>',
    native: '<svg viewBox="0 0 24 24"><path d="M4 4h16v16H4zM4 12h16M12 4v16"/></svg>',
};

const UIx = {
    saveTimer: null,
    change(path, value) {
        setPath(State.settings, path, value);
        if (path.startsWith('ui.')) Theme.apply(State.settings.ui);
        if (path.startsWith('hud.')) { State.hud = State.settings.hud; HUD.applyConfig(); }
        post('settings', { settings: State.settings, save: false });
        clearTimeout(this.saveTimer);
        this.saveTimer = setTimeout(() => post('settings', { settings: State.settings, save: true }), 350);
    },
    group(title, ...children) {
        const g = el('div', 'group');
        if (title) g.appendChild(el('h4', '', esc(title)));
        children.forEach(c => c && g.appendChild(c));
        return g;
    },
    grid(n, ...children) {
        const g = el('div', n === 3 ? 'grid3' : 'grid2');
        children.forEach(c => c && g.appendChild(c));
        return g;
    },
    slider({ label, path, min, max, step = 1, format = v => v, hint }) {
        const f = el('div', 'field');
        const v = getPath(State.settings, path);
        f.innerHTML = `<div class="field-top"><span>${esc(label)}</span><output>${format(v)}</output></div>
            <input type="range" min="${min}" max="${max}" step="${step}" value="${v}">${hint ? `<small>${esc(hint)}</small>` : ''}`;
        const input = $('input', f), out = $('output', f);
        const paint = () => input.style.setProperty('--fill', `${((input.value - min) / (max - min)) * 100}%`);
        paint();
        input.addEventListener('input', () => {
            const n = parseFloat(input.value);
            out.textContent = format(n); paint(); this.change(path, n);
        });
        return f;
    },
    toggle({ label, path, hint }) {
        const f = el('div', 'field');
        f.innerHTML = `<div class="field-top"><span>${esc(label)}</span><div class="switch ${getPath(State.settings, path) ? 'on' : ''}"></div></div>${hint ? `<small>${esc(hint)}</small>` : ''}`;
        const sw = $('.switch', f);
        sw.addEventListener('click', () => {
            const n = !sw.classList.contains('on');
            sw.classList.toggle('on', n); Sound.play('ui'); this.change(path, n);
        });
        return f;
    },
    seg({ label, path, options, hint, onChange }) {
        const f = el('div', 'field');
        f.innerHTML = `<div class="field-top"><span>${esc(label)}</span></div><div class="seg"></div>${hint ? `<small>${esc(hint)}</small>` : ''}`;
        const seg = $('.seg', f), cur = getPath(State.settings, path);
        options.forEach(o => {
            const b = el('button', o.v === cur ? 'active' : '', esc(o.l));
            b.addEventListener('click', () => {
                $$('button', seg).forEach(x => x.classList.remove('active'));
                b.classList.add('active'); Sound.play('ui'); this.change(path, o.v);
                if (onChange) onChange(o.v);
            });
            seg.appendChild(b);
        });
        return f;
    },
    color({ label, path }) {
        const f = el('div', 'field');
        const presets = State.config?.presets || [];
        f.innerHTML = `<div class="field-top"><span>${esc(label)}</span></div><div class="swatches"></div>`;
        const box = $('.swatches', f);
        const paint = () => {
            const cur = (getPath(State.settings, path) || '').toLowerCase();
            $$('.swatch', box).forEach(s => s.classList.toggle('active', s.dataset.c.toLowerCase() === cur));
            input.value = cur;
        };
        presets.forEach(c => {
            const s = el('div', 'swatch'); s.dataset.c = c; s.style.background = c;
            s.addEventListener('click', () => { this.change(path, c); paint(); });
            box.appendChild(s);
        });
        const input = el('input', 'text-in hex-in');
        input.maxLength = 7; input.spellcheck = false;
        input.addEventListener('change', () => {
            if (/^#[\da-f]{6}$/i.test(input.value)) { this.change(path, input.value); paint(); } else paint();
        });
        box.appendChild(input);
        paint();
        return f;
    },
};

const Tabs = {
    camera() {
        const body = el('div');
        const cards = el('div', 'cam-cards');
        (State.cameraModes || []).forEach(m => {
            const c = el('button', `cam-card${State.settings.camera.mode === m.id ? ' active' : ''}`, `${CAM_ICONS[m.id] || ''}${esc(m.label)}`);
            c.addEventListener('click', () => {
                $$('.cam-card', cards).forEach(x => x.classList.remove('active'));
                c.classList.add('active'); Sound.play('ui'); UIx.change('camera.mode', m.id);
            });
            cards.appendChild(c);
        });
        const deg = v => `${Math.round(v)}°`, m = v => `${Number(v).toFixed(2)} m`;
        body.append(
            UIx.group('Camera', cards),
            UIx.group('Field of view',
                UIx.grid(3,
                    UIx.slider({ label: 'Cockpit FOV', path: 'camera.cockpitFov', min: 40, max: 110, format: deg }),
                    UIx.slider({ label: 'Hood / Bumper FOV', path: 'camera.hoodFov', min: 40, max: 110, format: deg }),
                    UIx.slider({ label: 'Chase FOV', path: 'camera.chaseFov', min: 40, max: 110, format: deg }))),
            UIx.group('Cockpit seat',
                UIx.grid(2,
                    UIx.slider({ label: 'Left / Right', path: 'camera.seatX', min: -.4, max: .4, step: .01, format: m }),
                    UIx.slider({ label: 'Forward / Back', path: 'camera.seatY', min: -.4, max: .4, step: .01, format: m }),
                    UIx.slider({ label: 'Height', path: 'camera.seatZ', min: -.3, max: .3, step: .01, format: m }),
                    UIx.slider({ label: 'Tilt', path: 'camera.pitch', min: -20, max: 10, step: .5, format: deg }))),
            UIx.group('Feel',
                UIx.grid(2,
                    UIx.toggle({ label: 'Speed FOV', path: 'camera.speedFov', hint: 'FOV opens up the faster you go' }),
                    UIx.slider({ label: 'Speed FOV amount', path: 'camera.speedFovAmount', min: 0, max: 25, format: deg }),
                    UIx.toggle({ label: 'Camera shake', path: 'camera.shake', hint: 'Road vibration and impacts' }),
                    UIx.slider({ label: 'Free look speed', path: 'camera.lookSpeed', min: 1, max: 15, step: .5, format: v => v.toFixed(1) }))),
            UIx.group('Chase camera',
                UIx.grid(2,
                    UIx.slider({ label: 'Distance', path: 'camera.chaseDistance', min: 3, max: 12, step: .1, format: m }),
                    UIx.slider({ label: 'Height', path: 'camera.chaseHeight', min: .6, max: 4, step: .05, format: m }),
                    UIx.slider({ label: 'Smoothing', path: 'camera.chaseLag', min: 0, max: .5, step: .01, format: v => v.toFixed(2), hint: '0 is locked to the car, higher floats behind it' }),
                    UIx.slider({ label: 'Tilt', path: 'camera.chaseTilt', min: -5, max: 15, step: .5, format: deg }))),
            el('div', 'note', `Cycle cameras with <kbd>${esc(State.config?.keys?.Camera || 'V')}</kbd>. Change FOV while driving with <kbd>${esc(State.config?.keys?.FovUp || 'PAGEUP')}</kbd> / <kbd>${esc(State.config?.keys?.FovDown || 'PAGEDOWN')}</kbd>. Hold the look-behind key to check your mirror.`),
        );
        return body;
    },
    driving() {
        const body = el('div');
        const desc = { auto: 'GTA shifts for you.', sequential: 'Paddles or keys. Shift up / down one gear at a time.', hpattern: 'Pick any gear from a shifter. Needs the clutch.' };
        const hint = el('small', '', desc[State.settings.gameplay.transmission]);
        const trans = UIx.seg({
            label: 'Gearbox', path: 'gameplay.transmission',
            options: [{ v: 'auto', l: 'Automatic' }, { v: 'sequential', l: 'Sequential' }, { v: 'hpattern', l: 'H-Pattern' }],
            onChange: v => { hint.textContent = desc[v]; },
        });
        trans.appendChild(hint);
        const dens = v => `${['Light', 'Medium', 'Heavy', 'Insane'][v < .5 ? 0 : v < .9 ? 1 : v < 1.2 ? 2 : 3]} (${Math.round(v * 100)}%)`;
        const keys = State.config?.keys || {};
        const k = [['Toggle CUT UP', keys.ToggleMode], ['Menu', keys.Menu], ['Leaderboard', keys.Leaderboard], ['Camera', keys.Camera],
            ['Shift up', keys.ShiftUp], ['Shift down', keys.ShiftDown], ['Clutch', keys.Clutch], ['Flash high beams', keys.Flash], ['Toggle HUD', keys.ToggleHud]];
        const keyBox = el('div', 'keys', k.filter(x => x[1]).map(([a, b]) => `<div>${esc(a)}<kbd>${esc(b)}</kbd></div>`).join(''));
        body.append(
            UIx.group('Gearbox', trans),
            UIx.group('Road',
                UIx.grid(2,
                    UIx.slider({ label: 'Traffic density', path: 'gameplay.density', min: .25, max: 1.5, step: .05, format: dens, hint: 'Capped by the server' }),
                    UIx.seg({ label: 'Units', path: 'gameplay.units', options: [{ v: 'kmh', l: 'km/h' }, { v: 'mph', l: 'mph' }] }),
                    UIx.toggle({ label: 'Threat arrows', path: 'gameplay.showArrows', hint: 'Red arrows for players outside your crew closing in' }),
                    UIx.toggle({ label: 'See-through ghosts', path: 'gameplay.ghostAlpha', hint: 'Players outside your crew look faded' }))),
            UIx.group('Keys', keyBox),
            el('div', 'note', 'Every key can be rebound in Settings > Key Bindings > FiveM.'),
        );
        return body;
    },
    wheel() {
        return window.WheelUI ? WheelUI.render() : el('div', 'empty', 'Wheel support failed to load.');
    },
    crew() {
        const body = el('div');
        const { crew, invites } = State.crewData || {};
        const limits = State.config?.crewLimits || { name: [3, 20], tag: [2, 4], max: 8 };
        if (invites && invites.length) {
            invites.forEach(inv => {
                const c = el('div', 'invite-card', `<span class="crew-chip" style="background:${esc(inv.color)}">${esc(inv.tag)}</span>
                    <div class="spacer"><b>${esc(inv.crewName)}</b><br><small class="muted">Invited by ${esc(inv.from)}</small></div>`);
                const acc = el('button', 'btn small', 'Accept'), dec = el('button', 'btn small ghost', 'Decline');
                acc.onclick = () => post('crew', { action: 'accept' });
                dec.onclick = () => post('crew', { action: 'decline' });
                c.append(acc, dec);
                body.appendChild(UIx.group('Invite', c));
            });
        }
        if (!crew) {
            const colors = State.config?.crewColors || ['#a873ff'];
            let color = colors[0];
            const form = el('div', 'card');
            form.innerHTML = `<div class="grid2">
                <div><small class="muted">Crew name (${limits.name[0]}-${limits.name[1]})</small><input class="text-in" id="c-name" maxlength="${limits.name[1]}" spellcheck="false"></div>
                <div><small class="muted">Tag (${limits.tag[0]}-${limits.tag[1]} letters)</small><input class="text-in" id="c-tag" maxlength="${limits.tag[1]}" spellcheck="false" style="text-transform:uppercase"></div>
            </div><div style="margin-top:.7rem"><small class="muted">Colour</small><div class="swatches" id="c-colors" style="margin-top:.35rem"></div></div>
            <div class="row end" style="margin-top:.9rem"><button class="btn" id="c-create">Create crew</button></div>`;
            const sw = $('#c-colors', form);
            colors.forEach(c => {
                const s = el('div', `swatch${c === color ? ' active' : ''}`); s.style.background = c;
                s.onclick = () => { color = c; $$('.swatch', sw).forEach(x => x.classList.remove('active')); s.classList.add('active'); };
                sw.appendChild(s);
            });
            $('#c-create', form).onclick = () => post('crew', { action: 'create', payload: { name: $('#c-name', form).value, tag: $('#c-tag', form).value, color } });
            body.append(
                UIx.group('Start a crew', form),
                el('div', 'note', 'Crews share a leaderboard. Drive in sync with crewmates to build CREW FLOW: the more of you on the road together, the bigger the gap you can keep. Players outside your crew are ghosts, they drive straight through you.'),
            );
            return body;
        }
        const canManage = crew.myRole === 'owner' || crew.myRole === 'officer';
        const hero = el('div', 'crew-hero', `<span class="crew-tag-big">${esc(crew.tag)}</span>
            <div class="spacer"><h5>${esc(crew.name)}</h5><p>${crew.members.length}/${crew.max} members · ${fmt(crew.points)} pts · ${crew.position ? `#${crew.position} of ${crew.totalCrews}` : 'unranked'}</p></div>`);
        hero.style.setProperty('--crew', crew.color);
        hero.style.setProperty('--crew-rgb', hexRgb(crew.color));
        const list = el('div', 'members');
        crew.members.forEach(mb => {
            const row = el('div', 'member', `<i class="on-dot ${mb.online ? 'on' : ''}"></i>
                <div><b>${esc(mb.name)}</b>${mb.me ? ' <span class="muted">(you)</span>' : ''}</div>
                <span class="role ${mb.role}">${mb.role}</span>
                <span class="num muted">${fmt(mb.pbCrew)}</span><div class="row"></div>`);
            const actions = $('.row', row);
            if (!mb.me) {
                if (crew.myRole === 'owner') {
                    if (mb.role === 'member') { const b = el('button', 'btn small ghost', 'Promote'); b.onclick = () => post('crew', { action: 'promote', payload: { key: mb.key } }); actions.appendChild(b); }
                    if (mb.role === 'officer') { const b = el('button', 'btn small ghost', 'Demote'); b.onclick = () => post('crew', { action: 'demote', payload: { key: mb.key } }); actions.appendChild(b); }
                    const t = el('button', 'btn small ghost', 'Make owner'); t.onclick = () => post('crew', { action: 'transfer', payload: { key: mb.key } }); actions.appendChild(t);
                }
                const rank = { member: 1, officer: 2, owner: 3 };
                if (canManage && rank[crew.myRole] > rank[mb.role]) {
                    const k = el('button', 'btn small danger', 'Kick'); k.onclick = () => post('crew', { action: 'kick', payload: { key: mb.key } }); actions.appendChild(k);
                }
            }
            list.appendChild(row);
        });
        body.append(UIx.group(null, hero), UIx.group('Members', list));
        if (canManage) {
            const inv = el('div', 'card', `<div class="row"><input class="text-in" id="c-target" placeholder="Server ID" style="max-width:10rem"><button class="btn" id="c-invite">Send invite</button></div>`);
            $('#c-invite', inv).onclick = () => post('crew', { action: 'invite', payload: { target: $('#c-target', inv).value } });
            body.appendChild(UIx.group('Invite a driver', inv));
        }
        if (crew.myRole === 'owner') {
            const colors = el('div', 'swatches');
            (State.config?.crewColors || []).forEach(c => {
                const s = el('div', `swatch${c === crew.color ? ' active' : ''}`); s.style.background = c;
                s.onclick = () => post('crew', { action: 'color', payload: { color: c } });
                colors.appendChild(s);
            });
            body.appendChild(UIx.group('Crew colour', colors));
        }
        const danger = el('div', 'row');
        const leave = el('button', 'btn ghost', 'Leave crew'); leave.onclick = () => post('crew', { action: 'leave' });
        danger.appendChild(leave);
        if (crew.myRole === 'owner') {
            const dis = el('button', 'btn danger', 'Disband');
            let armed = false;
            dis.onclick = () => {
                if (!armed) { armed = true; dis.textContent = 'Click again to disband'; setTimeout(() => { armed = false; dis.textContent = 'Disband'; }, 3000); return; }
                post('crew', { action: 'disband' });
            };
            danger.appendChild(dis);
        }
        body.appendChild(UIx.group('Danger zone', danger));
        return body;
    },
    profile() {
        const p = State.profile || {};
        const pb = Math.max(p.pbSolo || 0, p.pbCrew || 0);
        const rank = rankFor(pb);
        const body = el('div');
        const rc = el('div', 'card rank-big', `<div><small class="muted">Rank</small><div class="rb-name" style="color:${rank.color}">${esc(rank.name)}</div></div>
            <div class="rb-bar"><div class="row"><small class="muted">${rank.nextName ? `${fmt(rank.toNext)} pts to ${esc(rank.nextName)}` : 'Max rank'}</small><span class="spacer"></span><b class="num">${rank.pct}%</b></div>
            <div class="progress"><i style="width:${rank.pct}%"></i></div></div>`);
        const cards = el('div', 'stat-cards', [
            ['PB Solo', fmt(p.pbSolo)], ['PB Crew', fmt(p.pbCrew)], ['Solo Position', p.position ? `#${fmt(p.position)} / ${fmt(p.totalPlayers)}` : '-'],
            ['Crew Run Position', p.crewPosition ? `#${fmt(p.crewPosition)}` : '-'], ['Runs', fmt(p.runs)], ['Total Points', compact(p.totalPoints || 0)],
            ['Distance', `${fmt((p.totalDistance || 0) / 1000)} km`], ['Crew', p.crew ? `[${p.crew.tag}] ${p.crew.name}` : 'Solo'], ['Server', State.config?.serverName || '-'],
        ].map(([k, v]) => `<div class="stat-card"><span>${k}</span><b>${esc(v)}</b></div>`).join(''));
        const open = el('button', 'btn', 'Open leaderboard');
        open.onclick = () => { Menu.close(true); post('openBoard'); };
        body.append(UIx.group(null, rc), UIx.group('Stats', cards), UIx.group(null, open));
        return body;
    },
    interface() {
        const body = el('div');
        if (State.config?.playerPrefs) {
            body.append(
                UIx.group('Colours', UIx.grid(3,
                    UIx.color({ label: 'Accent', path: 'ui.accent' }),
                    UIx.color({ label: 'Accent fade', path: 'ui.accent2' }),
                    UIx.color({ label: 'Alert', path: 'ui.alert' }))),
                UIx.group('Layout', UIx.grid(2,
                    UIx.slider({ label: 'Size', path: 'ui.scale', min: .8, max: 1.25, step: .01, format: v => `${Math.round(v * 100)}%` }),
                    UIx.seg({ label: 'Notifications', path: 'ui.toastPosition', options: [
                        { v: 'top-left', l: 'Top L' }, { v: 'top-center', l: 'Top' }, { v: 'top-right', l: 'Top R' }, { v: 'bottom-left', l: 'Bot L' }, { v: 'bottom-right', l: 'Bot R' }] }))),
                UIx.group('Sound & motion', UIx.grid(3,
                    UIx.toggle({ label: 'Sounds', path: 'ui.sounds' }),
                    UIx.slider({ label: 'Volume', path: 'ui.volume', min: 0, max: 1, step: .05, format: v => `${Math.round(v * 100)}%` }),
                    UIx.toggle({ label: 'Reduce motion', path: 'ui.reduceMotion' }))),
            );
        }
        body.append(
            UIx.group('HUD', UIx.grid(3,
                UIx.toggle({ label: 'Show HUD', path: 'hud.show' }),
                UIx.toggle({ label: 'Tacho', path: 'hud.tacho' }),
                UIx.toggle({ label: 'PB & rank', path: 'hud.pb' }),
                UIx.toggle({ label: 'Bonus strip', path: 'hud.bonuses' }),
                UIx.toggle({ label: 'Score popups', path: 'hud.popups' }))),
        );
        const reset = el('button', 'btn ghost', 'Reset to server defaults');
        reset.onclick = () => {
            const d = State.config?.defaults;
            if (!d) return;
            State.settings.ui = JSON.parse(JSON.stringify(d.ui));
            State.settings.hud = JSON.parse(JSON.stringify(d.hud));
            UIx.change('ui.accent', d.ui.accent);
            UIx.change('hud.show', d.hud.show);
            Menu.renderTab();
        };
        body.appendChild(UIx.group(null, reset));
        return body;
    },
};

const TAB_META = {
    camera: ['Camera', 'Cockpit FOV, seat position and chase cameras'],
    driving: ['Driving', 'Gearbox, traffic and keys'],
    wheel: ['Wheel', 'Plug in any wheel, map it and calibrate it'],
    crew: ['Crew', 'Run with your crew, climb the crew board'],
    profile: ['Profile', 'Your bests, rank and stats'],
    interface: ['Interface', 'Colours, size, sounds and HUD'],
};

function rankFor(points) {
    const ranks = State.config?.ranks || [{ name: 'Rookie 1', min: 0, color: '#a7aeb3' }];
    let i = 0;
    ranks.forEach((r, k) => { if (points >= r.min) i = k; });
    const cur = ranks[i], nxt = ranks[i + 1];
    return {
        name: cur.name, color: cur.color, nextName: nxt?.name,
        pct: nxt ? clamp(Math.floor((points - cur.min) / (nxt.min - cur.min) * 100), 0, 100) : 100,
        toNext: nxt ? nxt.min - points : 0,
    };
}

const Menu = {
    open(d) {
        State.menuOpen = true;
        State.settings = d.settings;
        State.profile = d.profile || State.profile;
        State.cameraModes = d.cameraModes || [];
        if (d.wheelProfiles && window.WheelMgr) WheelMgr.setProfiles(d.wheelProfiles);
        Theme.apply(State.settings.ui);
        const nav = $('#menu-tabs');
        nav.innerHTML = '';
        Object.keys(TAB_META).forEach(id => {
            const b = el('button', '', `${ICONS[id]}<span>${TAB_META[id][0]}</span>`);
            b.dataset.tab = id;
            b.onclick = () => { Sound.play('ui'); this.tab(id); };
            nav.appendChild(b);
        });
        $('#menu').classList.remove('hidden');
        this.side();
        this.tab(d.tab || State.menuTab);
        post('crew', { action: 'refresh' });
    },
    close(silent) {
        State.menuOpen = false;
        $('#menu').classList.add('hidden');
        if (window.WheelUI) WheelUI.onHide();
        if (!silent) post('close');
    },
    side() {
        const p = State.profile || {};
        const pb = Math.max(p.pbSolo || 0, p.pbCrew || 0);
        const r = rankFor(pb);
        $('#menu-profile').innerHTML = `<span>${esc(p.name || 'Driver')}</span><b style="color:${r.color}">${esc(r.name)}</b><span>PB ${fmt(pb)}</span>`;
    },
    tab(id) {
        State.menuTab = id;
        $$('#menu-tabs button').forEach(b => b.classList.toggle('active', b.dataset.tab === id));
        $('#menu-title').textContent = TAB_META[id][0];
        $('#menu-sub').textContent = TAB_META[id][1];
        if (id !== 'wheel' && window.WheelUI) WheelUI.onHide();
        this.renderTab();
    },
    renderTab() {
        const body = $('#menu-body');
        body.innerHTML = '';
        body.appendChild(Tabs[State.menuTab]());
    },
};

/* ============================== MESSAGES ============================== */
const Handlers = {
    config(d) {
        State.config = d;
        State.hud = d.hud;
        Theme.apply(d.ui);
        HUD.applyConfig();
        if (window.WheelMgr) WheelMgr.configure(d.wheel);
    },
    hud(d) { HUD.update(d); },
    popup(d) { Popups.show(d); },
    toast(d) { Toasts.show(d); },
    arrows(d) { Arrows.render(d || []); },
    sound(name) { Sound.play(name); },
    summary(d) { Summary.show(d); },
    'summary:result'(d) { Summary.result(d); },
    profile(d) { State.profile = d; if (State.menuOpen) { Menu.side(); if (State.menuTab === 'profile') Menu.renderTab(); } },
    crew(d) { State.crewData = d || { crew: null, invites: [] }; if (State.menuOpen && State.menuTab === 'crew') Menu.renderTab(); },
    'menu:open'(d) { if (State.boardOpen) Board.close(); Menu.open(d); },
    'menu:close'() { Menu.close(true); },
    'board:open'() { if (State.menuOpen) Menu.close(true); Board.open(); },
    board(d) { Board.render(d); },
    'wheel:profiles'(d) { if (window.WheelMgr) WheelMgr.setProfiles(d); },
    'wheel:rumble'(d) { if (window.WheelMgr) WheelMgr.rumble(d); },
};

window.addEventListener('message', e => {
    const { action, data } = e.data || {};
    if (Handlers[action]) Handlers[action](data);
});

document.addEventListener('keydown', e => {
    if (e.key !== 'Escape') return;
    if (window.WheelUI && WheelUI.cancelListen()) return;
    if (State.menuOpen) Menu.close();
    else if (State.boardOpen) { Board.close(); post('close'); }
});

$('#menu-close').onclick = () => Menu.close();
$('#board-close').onclick = () => { Board.close(); post('close'); };
$$('#board-tabs button').forEach(b => { b.onclick = () => { Sound.play('ui'); Board.select(b.dataset.board); }; });
$('#board-search').addEventListener('input', () => Board.render());

HUD.init();
post('nuiReady');
