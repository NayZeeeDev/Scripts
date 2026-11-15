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
function shade(hex, to, t) {
    const a = hexRgb(hex).split(',').map(Number), b = hexRgb(to).split(',').map(Number);
    return '#' + a.map((v, i) => Math.round(v + (b[i] - v) * t).toString(16).padStart(2, '0')).join('');
}
const Theme = {
    apply(ui) {
        if (!ui) return;
        State.ui = ui;
        const r = document.documentElement.style;
        const hud = ui.hudAccent || '#a873ff', hud2 = ui.hudAccent2 || '#ff6fb5', menu = ui.accent || '#08afa2';
        r.setProperty('--accent', hud); r.setProperty('--accent-rgb', hexRgb(hud));
        r.setProperty('--accent2', hud2); r.setProperty('--accent2-rgb', hexRgb(hud2));
        r.setProperty('--alert', ui.alert); r.setProperty('--alert-rgb', hexRgb(ui.alert));
        r.setProperty('--nz-red-lo', shade(ui.alert, '#000000', .2));
        r.setProperty('--nz-teal', menu); r.setProperty('--nz-teal-rgb', hexRgb(menu));
        r.setProperty('--nz-teal-hi', shade(menu, '#ffffff', .25));
        r.setProperty('--nz-teal-lo', shade(menu, '#000000', .28));
        r.setProperty('--nz-on-teal', shade(menu, '#000000', .87));
        r.setProperty('--scale', ui.scale || 1);
        this.zoom();
        document.body.classList.toggle('reduce-motion', !!ui.reduceMotion);
    },
    zoom() {
        const scale = State.ui.scale || 1;
        document.documentElement.style.setProperty('--vz', Math.min(window.innerHeight / 1080, window.innerWidth / 1920 * 1.25) * scale);
    },
};
window.addEventListener('resize', () => Theme.zoom());

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

/* ============================== HINT (in-HUD, replaces toasts) ============================== */
const Hint = {
    timer: null,
    show(d) {
        const h = $('#hint');
        h.className = `hint${d.kind === 'warn' ? ' warn' : ''}`;
        $('#hint-ico').innerHTML = d.kind === 'warn'
            ? '<svg viewBox="0 0 24 24"><path d="M12 8v5M12 16.5v.01"/><circle cx="12" cy="12" r="9"/></svg>'
            : '<svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';
        $('#hint-txt').textContent = d.text;
        clearTimeout(this.timer);
        this.timer = setTimeout(() => { h.classList.add('out'); setTimeout(() => h.classList.add('hidden'), 260); }, 1600);
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
        $$('#board-tabs button').forEach(b => b.classList.toggle('on', b.dataset.board === board));
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
                <div class="player-cell"><span class="crew-chip" style="--c:${esc(r.color)};--c-rgb:${hexRgb(r.color)}">${esc(r.tag)}</span><span class="strong">${esc(r.name)}</span></div>
                <div class="num">${fmt(r.points)}</div>
                <div>${r.members}</div>
                <div>${esc(r.bestName || '-')}</div>
                <div class="num muted">${fmt(r.bestPoints)}</div>
                <div></div></div>`;
            return wrap;
        }
        const initial = esc((r.name || '?').trim().charAt(0).toUpperCase());
        const chip = r.crew ? `<span class="crew-chip" style="--c:${esc(r.crew.color)};--c-rgb:${hexRgb(r.crew.color)}">${esc(r.crew.tag)}</span>` : '';
        wrap.innerHTML = `<div class="brow-main">
            <div>${this.badge(r.pos)}</div>
            <div class="player-cell"><span class="avatar" style="background:${r.crew ? esc(r.crew.color) : hashColor(r.name)}">${initial}</span><span class="strong">${esc(r.name)}</span>${chip}</div>
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
        const what = data.board === 'crews' ? 'crews' : 'drivers';
        $('#board-meta').innerHTML = `<b>${fmt(data.total)}</b> ${what} ranked · ${esc(State.config?.serverName || '')}${data.myPos ? ` · you are <b>#${fmt(data.myPos)}</b>` : ''}`;
        $('#board-count').innerHTML = `Showing <b>${list.length}</b> of <b>${fmt(data.total)}</b>`;
    },
};

/* ============================== MENU (NayZeee UI) ============================== */
const svgI = d => `<svg viewBox="0 0 24 24">${d}</svg>`;
const ICONS = {
    camera: svgI('<path d="M3 7h4l2-3h6l2 3h4v12H3z"/><circle cx="12" cy="13" r="3.5"/>'),
    driving: svgI('<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2"/><path d="M12 14v7M10.2 11L3.5 9M13.8 11l6.7-2"/>'),
    wheel: svgI('<path d="M6 8h12M6 16h12M8 8v8M16 8v8"/><circle cx="6" cy="8" r="2"/><circle cx="18" cy="16" r="2"/>'),
    crew: svgI('<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.6-3.6 3.3-5.5 6.5-5.5s5.9 1.9 6.5 5.5"/><circle cx="17" cy="9" r="2.5"/><path d="M16.5 14.6c2.6 0 4.5 1.6 5 4.4"/>'),
    profile: svgI('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
    board: svgI('<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM7 6H4v2a3 3 0 0 0 3 3M17 6h3v2a3 3 0 0 1-3 3"/>'),
    interface: svgI('<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>'),
    check: svgI('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
    reset: svgI('<path d="M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5"/>'),
    flag: svgI('<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>'),
    road: svgI('<path d="M5 21L9 3M19 21L15 3M12 5v2M12 11v2M12 17v2"/>'),
    gauge: svgI('<path d="M4 18a8 8 0 1 1 16 0"/><path d="M12 18l4-6"/>'),
    trophy: svgI('<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0z"/>'),
    plus: svgI('<path d="M12 5v14M5 12h14"/>'),
    alert: svgI('<path d="M12 8v5M12 16.5v.01"/><circle cx="12" cy="12" r="9"/>'),
    out: svgI('<path d="M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10"/>'),
    eye: svgI('<circle cx="12" cy="12" r="3"/><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/>'),
    bolt: svgI('<path d="M13 2L4 14h7l-1 8 9-12h-7z"/>'),
    star: svgI('<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/>'),
};
const CAM_ICONS = {
    cockpit: svgI('<circle cx="12" cy="13" r="7"/><circle cx="12" cy="13" r="1.5"/><path d="M5 13h5.5M13.5 13H19M12 14.5V20"/>'),
    hood: svgI('<path d="M3 17l3-6h12l3 6zM8 11l2-4h4l2 4"/>'),
    bumper: svgI('<path d="M3 15h18M5 15v3h3v-3M16 15v3h3v-3M4 15l2-5h12l2 5"/>'),
    chase_near: svgI('<rect x="7" y="10" width="10" height="6" rx="2"/><path d="M12 22v-4M9 4l3 3 3-3"/>'),
    chase_far: svgI('<rect x="9" y="6" width="6" height="4" rx="1"/><path d="M12 22v-9M8 18l4-3 4 3"/>'),
    cinematic: svgI('<rect x="2" y="6" width="14" height="12" rx="2"/><path d="M16 10l6-3v10l-6-3"/>'),
    native: svgI('<path d="M4 4h16v16H4zM4 12h16M12 4v16"/>'),
};
const clone = o => JSON.parse(JSON.stringify(o));
const initials = n => esc((String(n || '?').match(/[A-Za-z0-9]/g) || ['?']).slice(0, 2).join('').toUpperCase());

const UIx = {
    saved: null, dirty: false,
    snapshot() { this.saved = clone(State.settings); this.dirty = false; Menu.status(); },
    apply() {
        Theme.apply(State.settings.ui);
        State.hud = State.settings.hud;
        HUD.applyConfig();
    },
    change(path, value) {
        setPath(State.settings, path, value);
        if (path.startsWith('ui.') || path.startsWith('hud.')) this.apply();
        post('settings', { settings: State.settings, save: false });
        if (!this.dirty) { this.dirty = true; Menu.status(); }
    },
    save() {
        post('settings', { settings: State.settings, save: true });
        Sound.play('ui');
        this.snapshot();
        Menu.status('Saved');
    },
    revert(rerender = true) {
        if (!this.saved) return;
        State.settings = clone(this.saved);
        this.apply();
        post('settings', { settings: State.settings, save: false });
        this.dirty = false;
        Menu.status();
        if (rerender) Menu.renderTab();
    },
    accessor(o) {
        if (o.get) return o;
        return { get: () => getPath(State.settings, o.path), set: v => this.change(o.path, v) };
    },
    sec(title, desc, ...kids) {
        const s = el('section', 'sec');
        if (title) s.appendChild(el('h4', '', esc(title)));
        if (desc) s.appendChild(el('div', 'desc', desc));
        kids.flat().forEach(k => k && s.appendChild(k));
        return s;
    },
    grid(cols, ...kids) {
        const g = el('div', `opt-grid${cols === 3 ? ' c3' : ''}`);
        kids.flat().forEach(k => k && g.appendChild(k));
        return g;
    },
    opt(label, desc, control, col) {
        const o = el('div', `opt${col ? ' col' : ''}`, `<div class="opt-t"><b>${esc(label)}</b>${desc ? `<small>${esc(desc)}</small>` : ''}</div>`);
        if (control) o.appendChild(control);
        return o;
    },
    toggle(o) {
        const a = this.accessor(o);
        const sw = el('button', `sw${a.get() ? ' on' : ''}`, '<i></i>');
        sw.onclick = () => { const v = !sw.classList.contains('on'); sw.classList.toggle('on', v); Sound.play('ui'); a.set(v); if (o.onCommit) o.onCommit(); };
        return this.opt(o.label, o.desc, sw);
    },
    seg(o) {
        const a = this.accessor(o);
        const seg = el('div', 'segc');
        o.options.forEach(opt => {
            const b = el('button', opt.v === a.get() ? 'on' : '', esc(opt.l));
            b.onclick = () => {
                $$('button', seg).forEach(x => x.classList.toggle('on', x === b));
                Sound.play('ui'); a.set(opt.v);
                if (o.onChange) o.onChange(opt.v);
            };
            seg.appendChild(b);
        });
        return this.opt(o.label, o.desc, seg);
    },
    slider(o) {
        const a = this.accessor(o);
        const fmtv = o.format || (v => v);
        const wrap = el('div', 'rng', `<input type="range" min="${o.min}" max="${o.max}" step="${o.step || 1}" value="${a.get()}"><output>${fmtv(a.get())}</output>`);
        const input = $('input', wrap), out = $('output', wrap);
        const paint = () => input.style.setProperty('--fill', `${((input.value - o.min) / (o.max - o.min)) * 100}%`);
        paint();
        input.oninput = () => { const n = parseFloat(input.value); out.textContent = fmtv(n); paint(); a.set(n); };
        if (o.onCommit) input.onchange = o.onCommit;
        return this.opt(o.label, o.desc, wrap, true);
    },
    color(o) {
        const presets = State.config?.presets || [];
        const box = el('div', 'swatches');
        const input = el('input', 'nz-input');
        input.maxLength = 7; input.spellcheck = false;
        const paint = () => {
            const cur = (getPath(State.settings, o.path) || '').toLowerCase();
            $$('.swatch', box).forEach(s => s.classList.toggle('on', s.dataset.c.toLowerCase() === cur));
            input.value = cur.toUpperCase();
        };
        presets.forEach(c => {
            const s = el('button', 'swatch'); s.dataset.c = c; s.style.setProperty('--sw', c);
            s.onclick = () => { this.change(o.path, c); paint(); };
            box.appendChild(s);
        });
        input.onchange = () => { if (/^#[\da-f]{6}$/i.test(input.value)) this.change(o.path, input.value.toLowerCase()); paint(); };
        box.appendChild(input);
        paint();
        return this.opt(o.label, o.desc, box, true);
    },
    stat(icon, label, value, red) {
        return el('div', 'stat', `<div class="tile${red ? ' red' : ''}">${ICONS[icon] || ''}</div><div class="stat-txt"><span>${esc(label)}</span><b>${esc(value)}</b></div>`);
    },
    btn(cls, label, icon, fn) {
        const b = el('button', cls, `${icon ? ICONS[icon] : ''}${esc(label)}`);
        b.onclick = fn;
        return b;
    },
};

const Tabs = {
    camera() {
        const cards = el('div', 'cards');
        (State.cameraModes || []).forEach(m => {
            const c = el('button', `card${State.settings.camera.mode === m.id ? ' on' : ''}`, `<div class="pv">${CAM_ICONS[m.id] || ''}</div><span>${esc(m.label)}</span>`);
            c.onclick = () => { $$('.card', cards).forEach(x => x.classList.toggle('on', x === c)); Sound.play('ui'); UIx.change('camera.mode', m.id); };
            cards.appendChild(c);
        });
        const deg = v => `${Math.round(v)}°`, m = v => `${Number(v).toFixed(2)} m`;
        const k = State.config?.keys || {};
        return [
            UIx.sec('Camera', `Pick how you see the road. <kbd>${esc(k.Camera || 'V')}</kbd> cycles them while you drive.`, cards),
            UIx.sec('Field of view', `Change it on the move with <kbd>${esc(k.FovUp || 'PAGEUP')}</kbd> / <kbd>${esc(k.FovDown || 'PAGEDOWN')}</kbd>.`, UIx.grid(3,
                UIx.slider({ label: 'Cockpit', path: 'camera.cockpitFov', min: 40, max: 110, format: deg }),
                UIx.slider({ label: 'Hood & bumper', path: 'camera.hoodFov', min: 40, max: 110, format: deg }),
                UIx.slider({ label: 'Chase', path: 'camera.chaseFov', min: 40, max: 110, format: deg }))),
            UIx.sec('Cockpit seat', 'Move the in-car camera until the dash sits where you like it.', UIx.grid(2,
                UIx.slider({ label: 'Left / right', path: 'camera.seatX', min: -.4, max: .4, step: .01, format: m }),
                UIx.slider({ label: 'Forward / back', path: 'camera.seatY', min: -.4, max: .4, step: .01, format: m }),
                UIx.slider({ label: 'Height', path: 'camera.seatZ', min: -.3, max: .3, step: .01, format: m }),
                UIx.slider({ label: 'Tilt', path: 'camera.pitch', min: -20, max: 10, step: .5, format: deg }))),
            UIx.sec('Feel', null, UIx.grid(2,
                UIx.toggle({ label: 'Speed FOV', desc: 'FOV opens up the faster you go', path: 'camera.speedFov' }),
                UIx.slider({ label: 'Speed FOV amount', path: 'camera.speedFovAmount', min: 0, max: 25, format: deg }),
                UIx.toggle({ label: 'Camera shake', desc: 'Road vibration and impacts', path: 'camera.shake' }),
                UIx.slider({ label: 'Free look speed', path: 'camera.lookSpeed', min: 1, max: 15, step: .5, format: v => v.toFixed(1) }))),
            UIx.sec('Chase camera', null, UIx.grid(2,
                UIx.slider({ label: 'Distance', path: 'camera.chaseDistance', min: 3, max: 12, step: .1, format: m }),
                UIx.slider({ label: 'Height', path: 'camera.chaseHeight', min: .6, max: 4, step: .05, format: m }),
                UIx.slider({ label: 'Smoothing', desc: '0 is locked to the car, higher floats behind it', path: 'camera.chaseLag', min: 0, max: .5, step: .01, format: v => v.toFixed(2) }),
                UIx.slider({ label: 'Tilt', path: 'camera.chaseTilt', min: -5, max: 15, step: .5, format: deg }))),
        ];
    },
    driving() {
        const desc = { auto: 'GTA shifts for you', sequential: 'Paddles or keys, one gear at a time', hpattern: 'Pick any gear from a shifter, clutch in first' };
        const gear = UIx.seg({
            label: 'Gearbox', desc: desc[State.settings.gameplay.transmission], path: 'gameplay.transmission',
            options: [{ v: 'auto', l: 'Automatic' }, { v: 'sequential', l: 'Sequential' }, { v: 'hpattern', l: 'H-Pattern' }],
            onChange: v => { $('small', gear).textContent = desc[v]; },
        });
        const dens = v => `${['Light', 'Medium', 'Heavy', 'Insane'][v < .5 ? 0 : v < .9 ? 1 : v < 1.2 ? 2 : 3]} · ${Math.round(v * 100)}%`;
        const k = State.config?.keys || {};
        const keys = el('div', 'keys');
        [['Toggle CUT UP', k.ToggleMode], ['Menu', k.Menu], ['Leaderboard', k.Leaderboard], ['Camera', k.Camera], ['Shift up', k.ShiftUp],
            ['Shift down', k.ShiftDown], ['Clutch', k.Clutch], ['Flash high beams', k.Flash], ['Toggle HUD', k.ToggleHud]]
            .filter(x => x[1]).forEach(([a, b]) => keys.appendChild(UIx.opt(a, null, el('kbd', '', esc(b)))));
        return [
            UIx.sec('Gearbox', 'Manual and H-pattern earn the Physics Bonus.', gear),
            UIx.sec('Road', null,
                UIx.slider({ label: 'Traffic density', desc: 'How busy the road is around you. The server sets the limit.', path: 'gameplay.density', min: .25, max: 1.5, step: .05, format: dens }),
                UIx.grid(2,
                    UIx.seg({ label: 'Units', path: 'gameplay.units', options: [{ v: 'kmh', l: 'km/h' }, { v: 'mph', l: 'mph' }] }),
                    el('div'),
                    UIx.toggle({ label: 'Threat arrows', desc: 'Red arrows when non-crew players close in', path: 'gameplay.showArrows' }),
                    UIx.toggle({ label: 'See-through ghosts', desc: 'Players outside your crew look faded', path: 'gameplay.ghostAlpha' }))),
            UIx.sec('Keys', 'Rebind any of these in Settings > Key Bindings > FiveM.', keys),
        ];
    },
    wheel() {
        return window.WheelUI ? WheelUI.render() : el('div', 'empty', '<b>Wheel support failed to load</b>');
    },
    crew() {
        const out = [];
        const { crew, invites } = State.crewData || {};
        const limits = State.config?.crewLimits || { name: [3, 20], tag: [2, 4], max: 8 };
        (invites || []).forEach(inv => {
            const c = el('div', 'inc', `<div class="inc-top"><span class="chip">CREW INVITE</span><span class="crew-chip" style="--c:${esc(inv.color)};--c-rgb:${hexRgb(inv.color)}">${esc(inv.tag)}</span></div>
                <h3>${esc(inv.crewName)}</h3><p>${esc(inv.from)} wants you on the crew. Crew runs count toward their board and you get crew flow with them.</p><div class="acts"></div>`);
            $('.acts', c).append(UIx.btn('btn-teal', 'Accept', 'check', () => post('crew', { action: 'accept' })), UIx.btn('btn-line', 'Decline', null, () => post('crew', { action: 'decline' })));
            out.push(c);
        });
        if (!crew) {
            const colors = State.config?.crewColors || ['#08afa2'];
            let color = colors[0];
            const form = el('div', 'panel', `<div class="p-head"><div><h2>Start a crew</h2><p>Name, a short tag and a colour. You can invite drivers once it's made.</p></div></div>
                <div class="p-body"><div class="opt-grid">
                    <div class="field"><label>Crew name (${limits.name[0]}-${limits.name[1]})</label><input class="nz-input" id="c-name" maxlength="${limits.name[1]}" spellcheck="false" placeholder="Night Shift"></div>
                    <div class="field"><label>Tag (${limits.tag[0]}-${limits.tag[1]} letters)</label><input class="nz-input" id="c-tag" maxlength="${limits.tag[1]}" spellcheck="false" placeholder="NS" style="text-transform:uppercase"></div>
                </div><div class="field" style="margin-top:6px"><label>Colour</label><div class="swatches" id="c-colors"></div></div><div class="actions" id="c-act"></div></div>`);
            const sw = $('#c-colors', form);
            colors.forEach(c => {
                const s = el('button', `swatch${c === color ? ' on' : ''}`); s.style.setProperty('--sw', c);
                s.onclick = () => { color = c; $$('.swatch', sw).forEach(x => x.classList.toggle('on', x === s)); };
                sw.appendChild(s);
            });
            $('#c-act', form).appendChild(UIx.btn('btn-teal', 'Create crew', 'plus', () => post('crew', { action: 'create', payload: { name: $('#c-name', form).value, tag: $('#c-tag', form).value, color } })));
            out.push(form);
            out.push(UIx.sec('How crews work', null, el('div', 'inc', `<h3>Run together, climb together</h3><p>Drive in sync with crewmates to build CREW FLOW. The more of you on the road together, the bigger the gap you can keep and the bigger the bonus.
                Crew runs go on the crew board. Players outside your crew are ghosts: they drive straight through you.</p>`)));
            return out;
        }
        const canManage = crew.myRole === 'owner' || crew.myRole === 'officer';
        const online = crew.members.filter(m => m.online).length;
        const stats = el('div', 'stats');
        stats.append(UIx.stat('trophy', 'Crew points', fmt(crew.points)), UIx.stat('flag', 'Crew board', crew.position ? `#${crew.position} of ${crew.totalCrews}` : 'Unranked'),
            UIx.stat('crew', 'Members', `${crew.members.length} / ${crew.max}`));
        out.push(stats);

        const panel = el('div', 'panel', `<div class="p-head"><div><h2><span class="crew-chip" style="--c:${esc(crew.color)};--c-rgb:${hexRgb(crew.color)};margin-right:8px">${esc(crew.tag)}</span>${esc(crew.name)}</h2>
            <p>${online} online · you are ${esc(crew.myRole)}</p></div><div class="row-inv" style="display:flex;gap:8px"></div></div><div class="p-body"></div>`);
        if (canManage) {
            const inp = el('input', 'nz-input'); inp.placeholder = 'Server ID'; inp.style.width = '110px';
            $('.row-inv', panel).append(inp, UIx.btn('btn-teal', 'Invite', 'plus', () => post('crew', { action: 'invite', payload: { target: inp.value } })));
        }
        const body = $('.p-body', panel);
        const rank = { member: 1, officer: 2, owner: 3 };
        crew.members.forEach(mb => {
            const r = el('div', 'row', `<i class="on-dot ${mb.online ? 'on' : ''}"></i><div class="av">${initials(mb.name)}</div>
                <div class="row-txt"><b>${esc(mb.name)}${mb.me ? ' <span style="display:inline;color:var(--nz-ink-3)">(you)</span>' : ''}</b><span>Crew PB ${fmt(mb.pbCrew)} · Solo PB ${fmt(mb.pbSolo)}</span></div>
                <span class="tag ${mb.role === 'owner' ? 'live' : mb.role === 'officer' ? 'hot' : 'off'}">${esc(mb.role)}</span><div class="acts"></div>`);
            const acts = $('.acts', r);
            if (!mb.me) {
                if (crew.myRole === 'owner') {
                    if (mb.role === 'member') acts.appendChild(UIx.btn('btn-ghost', 'Promote', null, () => post('crew', { action: 'promote', payload: { key: mb.key } })));
                    if (mb.role === 'officer') acts.appendChild(UIx.btn('btn-ghost', 'Demote', null, () => post('crew', { action: 'demote', payload: { key: mb.key } })));
                    acts.appendChild(UIx.btn('btn-ghost', 'Make owner', null, () => post('crew', { action: 'transfer', payload: { key: mb.key } })));
                }
                if (canManage && rank[crew.myRole] > rank[mb.role]) acts.appendChild(UIx.btn('btn-ghost danger', 'Kick', null, () => post('crew', { action: 'kick', payload: { key: mb.key } })));
            }
            body.appendChild(r);
        });
        out.push(panel);

        if (crew.myRole === 'owner') {
            const sw = el('div', 'swatches');
            (State.config?.crewColors || []).forEach(c => {
                const s = el('button', `swatch${c === crew.color ? ' on' : ''}`); s.style.setProperty('--sw', c);
                s.onclick = () => post('crew', { action: 'color', payload: { color: c } });
                sw.appendChild(s);
            });
            out.push(UIx.sec('Crew colour', 'Shows on the leaderboard and next to every member.', sw));
        }
        const danger = el('div', 'actions');
        const confirm = el('div', 'modal hidden', `<div class="modal-b"><div class="warn">${ICONS.alert}</div><div><h4>Disband ${esc(crew.name)}?</h4>
            <p>Everyone is removed and the crew leaves the board. Members keep their own runs. This can't be undone.</p></div></div><div class="modal-f"></div>`);
        $('.modal-f', confirm).append(UIx.btn('btn-line', 'Cancel', null, () => confirm.classList.add('hidden')), UIx.btn('btn-red', 'Disband crew', null, () => post('crew', { action: 'disband' })));
        danger.appendChild(UIx.btn('btn-line', 'Leave crew', 'out', () => post('crew', { action: 'leave' })));
        if (crew.myRole === 'owner') danger.appendChild(UIx.btn('btn-red', 'Disband', null, () => confirm.classList.remove('hidden')));
        out.push(UIx.sec('Danger zone', crew.myRole === 'owner' ? 'Leaving hands the crew to your highest ranked member.' : null, danger, confirm));
        return out;
    },
    profile() {
        const p = State.profile || {};
        const pb = Math.max(p.pbSolo || 0, p.pbCrew || 0);
        const rank = rankFor(pb);
        const s1 = el('div', 'stats'), s2 = el('div', 'stats');
        s1.append(UIx.stat('trophy', 'PB solo', fmt(p.pbSolo)), UIx.stat('crew', 'PB crew', fmt(p.pbCrew)), UIx.stat('bolt', 'Runs', fmt(p.runs)));
        s2.append(UIx.stat('flag', 'Solo board', p.position ? `#${fmt(p.position)}` : '-'), UIx.stat('flag', 'Crew run board', p.crewPosition ? `#${fmt(p.crewPosition)}` : '-'),
            UIx.stat('road', 'Distance', `${fmt((p.totalDistance || 0) / 1000)} km`));
        const rp = el('div', 'panel', `<div class="p-head"><div><h2>${esc(rank.name)}</h2><p>${rank.nextName ? `${fmt(rank.toNext)} pts to ${esc(rank.nextName)}` : 'Top rank'} · ranked by your best run, solo or crew</p></div>
            <span class="tag live">${rank.pct}%</span></div><div class="p-body"><div class="progress"><i style="width:${rank.pct}%"></i></div>
            <div class="opt"><div class="opt-t"><b>Total points</b><small>Every run you've finished</small></div><b>${fmt(p.totalPoints)}</b></div>
            <div class="opt"><div class="opt-t"><b>Crew</b></div><b>${p.crew ? `[${esc(p.crew.tag)}] ${esc(p.crew.name)}` : 'Solo'}</b></div></div>`);
        const acts = el('div', 'actions');
        acts.appendChild(UIx.btn('btn-teal', 'Open leaderboard', 'trophy', () => Menu.tab('board')));
        return [s1, s2, rp, acts];
    },
    interface() {
        const out = [];
        if (State.config?.playerPrefs) {
            out.push(
                UIx.sec('Colours', 'Your own colours. Saved on your PC only.', UIx.grid(2,
                    UIx.color({ label: 'Menu accent', desc: 'Buttons, toggles and highlights', path: 'ui.accent' }),
                    UIx.color({ label: 'Alert', desc: 'Crashes, threat arrows, hearts, close', path: 'ui.alert' }),
                    UIx.color({ label: 'HUD colour', desc: 'Multiplier tag, rings, flow state', path: 'ui.hudAccent' }),
                    UIx.color({ label: 'HUD fade', desc: 'Score bar and combo hold', path: 'ui.hudAccent2' }))),
                UIx.sec('Layout', null,
                    UIx.slider({ label: 'Size', desc: 'Scales the HUD and every menu', path: 'ui.scale', min: .8, max: 1.25, step: .01, format: v => `${Math.round(v * 100)}%` }),
                    UIx.seg({ label: 'Notifications', desc: 'Where ox_lib notifications pop up', path: 'ui.toastPosition', options: [
                        { v: 'top-left', l: 'Top left' }, { v: 'top-center', l: 'Top' }, { v: 'top-right', l: 'Top right' }, { v: 'bottom-left', l: 'Bottom left' }, { v: 'bottom-right', l: 'Bottom right' }] })),
                UIx.sec('Sound & motion', null, UIx.grid(2,
                    UIx.toggle({ label: 'Sounds', desc: 'Near misses, crashes, shifts', path: 'ui.sounds' }),
                    UIx.slider({ label: 'Volume', path: 'ui.volume', min: 0, max: 1, step: .05, format: v => `${Math.round(v * 100)}%` }),
                    UIx.toggle({ label: 'Reduce motion', desc: 'No scanlines, glows or popup animations', path: 'ui.reduceMotion' }))),
            );
        }
        const chips = el('div', 'chips');
        [['tacho', 'Tacho', 'gauge'], ['pb', 'PB & rank', 'trophy'], ['bonuses', 'Bonus strip', 'bolt'], ['popups', 'Score popups', 'star']].forEach(([k, l, i]) => {
            const c = el('button', `chip-t${State.settings.hud[k] ? ' on' : ''}`, `${ICONS[i]}${l}`);
            c.onclick = () => { const v = !c.classList.contains('on'); c.classList.toggle('on', v); Sound.play('ui'); UIx.change(`hud.${k}`, v); };
            chips.appendChild(c);
        });
        out.push(UIx.sec('HUD', null, UIx.toggle({ label: 'Show HUD', desc: 'Hide everything while you drive', path: 'hud.show' }), UIx.opt('Elements', 'Pick what shows on screen', null, true), chips));
        return out;
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
const TAB_GROUPS = [['Driving', ['camera', 'driving', 'wheel']], ['Crew', ['crew', 'profile', 'board']], ['Display', ['interface']]];

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
    active: false,
    open(d) {
        State.menuOpen = true;
        State.settings = d.settings;
        State.profile = d.profile || State.profile;
        State.cameraModes = d.cameraModes || [];
        this.active = !!d.active;
        if (d.wheelProfiles && window.WheelMgr) WheelMgr.setProfiles(d.wheelProfiles);
        UIx.apply();
        UIx.snapshot();
        $('#m-ver').textContent = `v${State.config?.version || '1.0.0'}`;
        $('#m-sub').textContent = `Settings · ${State.config?.serverName || ''}`;
        const k = State.config?.keys || {};
        $('#m-statusbar').innerHTML = `<span><span class="key">ESC</span>Close</span><span><span class="key">${esc(k.Leaderboard || 'F10')}</span>Leaderboard</span>
            <span><span class="key">${esc(k.Camera || 'V')}</span>Camera</span><span><span class="key">${esc(k.ToggleMode || 'F6')}</span>CUT UP</span><span class="spacer"></span><span><b>NayZeee</b> Development</span>`;
        $('#menu').classList.remove('hidden');
        this.tab(d.tab || State.menuTab);
        post('crew', { action: 'refresh' });
    },
    close(silent) {
        if (UIx.dirty) UIx.revert(false);
        State.menuOpen = false;
        $('#menu').classList.add('hidden');
        if (window.WheelUI) WheelUI.onHide();
        if (!silent) post('close');
    },
    status(flash) {
        const p = State.profile || {};
        const dot = $('#m-dot'), txt = $('#m-status');
        $('#m-undo').classList.toggle('hidden', !UIx.dirty);
        if (UIx.dirty) {
            dot.className = 'dot amber';
            txt.innerHTML = 'You have <b>unsaved changes</b> · they preview live, Save keeps them';
        } else if (flash) {
            dot.className = 'dot';
            txt.innerHTML = `<b>${esc(flash)}</b> · your settings are stored on this PC`;
        } else {
            const pb = Math.max(p.pbSolo || 0, p.pbCrew || 0);
            dot.className = this.active ? 'dot' : 'dot off';
            txt.innerHTML = `Driving as <b>${esc(p.name || 'Driver')}</b> · ${esc(rankFor(pb).name)} · PB <b>${fmt(pb)}</b>`;
        }
    },
    side() {
        const p = State.profile || {};
        const pb = Math.max(p.pbSolo || 0, p.pbCrew || 0);
        const r = rankFor(pb);
        const side = $('#m-side');
        side.innerHTML = `<div class="who"><div class="av">${initials(p.name)}</div><div class="who-txt"><b>${esc(p.name || 'Driver')}</b><span>${esc(r.name)}${p.crew ? ` · [${esc(p.crew.tag)}]` : ''}</span></div></div>
            <div class="shift"><span>${compact(pb)} PB</span><b class="${this.active ? '' : 'off'}"><span class="dot ${this.active ? '' : 'off'}"></span>${this.active ? 'Cutting up' : 'Off the road'}</b></div>`;
        const invites = (State.crewData?.invites || []).length;
        const wheelOn = window.WheelMgr && Object.values(WheelMgr.profiles()).some(x => x && x.enabled);
        TAB_GROUPS.forEach(([grp, ids], gi) => {
            if (gi > 0) side.appendChild(el('div', 'grp', esc(grp)));
            ids.forEach(id => {
                const label = id === 'board' ? 'Leaderboard' : TAB_META[id][0];
                let tally = '';
                if (id === 'wheel' && wheelOn) tally = '<span class="tally live">ON</span>';
                if (id === 'crew' && invites) tally = `<span class="tally live">${invites}</span>`;
                else if (id === 'crew' && State.crewData?.crew) tally = `<span class="tally">${esc(State.crewData.crew.tag)}</span>`;
                if (id === 'board') tally = `<span class="tally">${esc(State.config?.keys?.Leaderboard || 'F10')}</span>`;
                const b = el('button', `nav${id === State.menuTab ? ' on' : ''}`, `${ICONS[id]}${esc(label)}${tally}`);
                b.dataset.tab = id;
                b.onclick = () => { Sound.play('ui'); this.tab(id); };
                side.appendChild(b);
            });
        });
    },
    tab(id) {
        if (id === 'board') { this.close(true); post('openBoard'); return; }
        if (id !== 'wheel' && window.WheelUI) WheelUI.onHide();
        State.menuTab = id;
        $('#menu-title').textContent = TAB_META[id][0];
        $('#menu-sub').textContent = TAB_META[id][1];
        const act = $('#m-headact');
        act.innerHTML = '';
        if (id === 'interface') {
            act.appendChild(UIx.btn('btn-red', 'Reset to default', 'reset', () => {
                const d = State.config?.defaults;
                if (!d) return;
                State.settings.ui = clone(d.ui); State.settings.hud = clone(d.hud);
                UIx.change('hud.show', d.hud.show);
                this.renderTab();
            }));
        }
        if (id === 'camera') act.appendChild(el('span', 'tag live', esc((State.cameraModes.find(m => m.id === State.settings.camera.mode) || {}).label || '')));
        this.side();
        this.status();
        this.renderTab();
    },
    renderTab() {
        const body = $('#menu-body');
        body.innerHTML = '';
        [].concat(Tabs[State.menuTab]()).forEach(n => n && body.appendChild(n));
        body.scrollTop = 0;
    },
};

$('#m-save').onclick = () => UIx.save();
$('#m-undo').onclick = () => UIx.revert();

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
    hint(d) { Hint.show(d); },
    arrows(d) { Arrows.render(d || []); },
    sound(name) { Sound.play(name); },
    summary(d) { Summary.show(d); },
    'summary:result'(d) { Summary.result(d); },
    profile(d) { State.profile = d; if (State.menuOpen) { Menu.side(); Menu.status(); if (State.menuTab === 'profile') Menu.renderTab(); } },
    crew(d) { State.crewData = d || { crew: null, invites: [] }; if (State.menuOpen) { Menu.side(); if (State.menuTab === 'crew') Menu.renderTab(); } },
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
