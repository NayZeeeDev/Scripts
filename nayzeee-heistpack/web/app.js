/* nayzeee heistpack - NUI controller (vanilla JS, no build step) - NAYZEEE UI */
(function () {
    'use strict';

    const IN_GAME = typeof window.GetParentResourceName === 'function';
    const RES = IN_GAME ? window.GetParentResourceName() : 'nayzeee-heistpack';
    const $ = (id) => document.getElementById(id);
    const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const money = (n) => '$' + Math.floor(n || 0).toLocaleString('en-US');
    const mmss = (s) => { s = Math.max(0, Math.floor(s)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
    const T = (k, f) => (window.UIStrings && window.UIStrings[k]) || f || k;
    const I = (n) => Icons.svg(n);

    /* browser preview only */
    const Mock = {
        post(name, data) {
            const r = (window.MockData || {})[name];
            return Promise.resolve(typeof r === 'function' ? r(data) : (r !== undefined ? r : { ok: true }));
        },
    };

    async function post(name, data) {
        if (!IN_GAME) return Mock.post(name, data);
        try {
            const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}) });
            return await r.json();
        } catch (e) { return null; }
    }
    const unwrap = (r) => (r && Object.prototype.hasOwnProperty.call(r, 'ok') ? r : { ok: !!r, data: r });
    const arr = (r) => { const d = unwrap(r).data; return Array.isArray(d) ? d : []; };

    const S = {
        ui: null, profile: null, crew: null, heists: [], police: 0, playerCooldown: 0,
        featured: null, featuredBonus: null, tab: 'heists', selected: null, filter: 'all', search: '',
        market: null, cart: {}, marketCat: 'all', fence: null, chat: [], board: [], history: [],
        serverId: 0, hudExpanded: true, hud: null, hudEndAt: 0, hudTimer: 0, unreadChat: 0, noise: null, clockTimer: 0,
    };

    /* ================================================================ theme */
    function rgb(hex) {
        const h = hex.replace('#', '');
        const n = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h, 16);
        return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
    }
    const shade = (c, k) => '#' + c.map((v) => Math.max(0, Math.min(255, Math.round(v * k))).toString(16).padStart(2, '0')).join('');

    function applyTheme(ui) {
        const r = document.documentElement.style;
        const t = ui.theme || {};
        if (t.accent) { const c = rgb(t.accent); r.setProperty('--teal', t.accent); r.setProperty('--teal-rgb', c.join(', ')); r.setProperty('--teal-lo', shade(c, 0.72)); }
        if (t.accent2) r.setProperty('--teal-hi', t.accent2);
        if (t.danger) { const c = rgb(t.danger); r.setProperty('--red', t.danger); r.setProperty('--red-rgb', c.join(', ')); r.setProperty('--red-lo', shade(c, 0.8)); }
        if (t.warning) { r.setProperty('--amber', t.warning); r.setProperty('--amber-rgb', rgb(t.warning).join(', ')); }
        if (t.success) r.setProperty('--ok', t.success);
        if (t.font) r.setProperty('--font', t.font);
        if (t.radius) r.setProperty('--r-md', t.radius);
        const hud = ui.hud || {};
        $('hud').classList.toggle('left', hud.position === 'left');
        $('hud').classList.toggle('bg-glass', hud.background === 'glass');
        $('hud').classList.toggle('bg-solid', hud.background === 'solid');
        r.setProperty('--hud-scale', hud.scale || 1);
        $('notify').className = 'notify ' + ((ui.notify && ui.notify.position) || 'top-right');
        $('textui').classList.toggle('right', !!(ui.textui && ui.textui.position === 'right'));
    }

    function translate() {
        document.querySelectorAll('[data-t]').forEach((el) => { el.textContent = T(el.dataset.t, el.textContent); });
    }

    /* ================================================================ toasts */
    const TOAST = { success: ['check', 'toast_success', 'Done'], error: ['x', 'toast_error', 'Heads up'], warning: ['siren', 'toast_warning', 'Warning'], info: ['bolt', 'toast_info', 'Heist'] };
    function notify({ text, kind, duration, title }) {
        const k = TOAST[kind] ? kind : 'info';
        const d = duration || 5000;
        const el = document.createElement('div');
        el.className = 'toast ' + k;
        el.style.setProperty('--d', d + 'ms');
        el.innerHTML = `<div class="ti">${I(TOAST[k][0])}</div><div><b>${esc(title || T(TOAST[k][1], TOAST[k][2]))}</b><p>${esc(text)}</p></div>`;
        $('notify').prepend(el);
        while ($('notify').children.length > 5) $('notify').lastChild.remove();
        setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, d);
    }

    /* ================================================================ text ui / progress */
    function textui(data) {
        const el = $('textui');
        if (!data) return el.classList.add('hidden');
        el.innerHTML = data.lines.map((l) => `<div class="line"><span class="key lg">${esc(l.key)}</span>${esc(l.label)}</div>`).join('');
        el.classList.remove('hidden');
    }

    let progressRaf = 0;
    function progress(data) {
        cancelAnimationFrame(progressRaf);
        const el = $('progress');
        if (!data) return el.classList.add('hidden');
        $('progress-text').textContent = data.label;
        el.classList.remove('hidden');
        const start = performance.now();
        const step = (now) => {
            const k = Math.min(1, (now - start) / data.duration);
            $('progress-fill').style.width = (k * 100) + '%';
            $('progress-pct').textContent = Math.floor(k * 100) + '%';
            if (k < 1) progressRaf = requestAnimationFrame(step);
        };
        progressRaf = requestAnimationFrame(step);
    }

    /* ================================================================ HUD (transparent) */
    function hud(data) {
        const el = $('hud');
        if (!data || !data.show) {
            S.hud = null; S.hudEndAt = 0; el.classList.add('hidden'); clearInterval(S.hudTimer); S.hudTimer = 0;
            return;
        }
        S.hud = Object.assign(S.hud || {}, data);
        if (data.remaining != null) S.hudEndAt = Date.now() + data.remaining * 1000;
        renderHud();
        el.classList.remove('hidden');
        if (S.hudEndAt && !S.hudTimer) S.hudTimer = setInterval(renderHudTimer, 1000);
    }

    function renderHudTimer() {
        const t = $('hud-time');
        if (!t || !S.hudEndAt) return;
        const left = (S.hudEndAt - Date.now()) / 1000;
        t.textContent = mmss(left);
        t.parentElement.classList.toggle('bad', left < 120);
    }

    function renderHud() {
        const h = S.hud;
        const pct = h.stages ? ((h.stage - 1) / h.stages) * 100 : 0;
        let meta = '';
        if (S.hudEndAt) meta += `<span>${I('clock')}<b id="hud-time">--:--</b></span>`;
        if (h.distance) meta += `<span class="${h.distance.current >= h.distance.target ? '' : 'warn'}">${I('map')}${h.distance.current}m / ${h.distance.target}m</span>`;
        if (h.guards) meta += `<span class="${h.guards.alive > 0 ? 'bad' : ''}">${I('crosshair')}${T('guards', 'Hostiles')} ${h.guards.alive}/${h.guards.total}</span>`;
        if (h.tracker) meta += `<span class="bad">${I('siren')}${T('tracker', 'GPS tracker active')}</span>`;

        const list = S.hudExpanded && h.objectives && h.objectives.length ? `<div class="hud-list">${h.objectives.map((o) => `
            <div class="hud-obj ${o.done ? 'done' : ''} ${o.optional ? 'optional' : ''}"><span class="box"></span><span>${esc(o.label)}</span>${o.total > 1 || o.optional ? `<span class="count">${o.count}/${o.total}</span>` : ''}</div>`).join('')}</div>` : '';
        const crew = S.hudExpanded && h.members && h.members.length > 1 ? `<div class="hud-crew">${h.members.map((m) => `<span class="${m.leader ? 'lead' : ''}">${Icons.avatar(m.avatar, 18, m.leader ? 'teal' : '')}${esc(m.nickname)}</span>`).join('')}</div>` : '';
        const noise = S.noise != null ? `<div class="hud-noise ${S.noise >= 70 ? 'loud' : ''}"><div class="top"><span>${T('noise', 'Noise')}</span><span>${S.noise}%</span></div><div class="track"><i style="width:${S.noise}%"></i></div></div>` : '';
        const key = esc((S.ui && S.ui.hud && S.ui.hud.expandKey) || 'B');

        $('hud').innerHTML = `
            <div class="hud-head">
                <div class="mark sm"></div>
                <div><div class="title-txt">${esc(h.title)}</div><div class="sub">${esc(h.location || '')}</div></div>
                <span class="hud-stage">${h.stage}/${h.stages}</span>
            </div>
            <div class="hud-rail"><i style="width:${pct}%"></i></div>
            <div class="hud-task"><span class="dot"></span><span>${esc(h.task)}</span></div>
            ${meta ? `<div class="hud-meta">${meta}</div>` : ''}
            ${noise}${list}${crew}
            <div class="hud-hint"><span class="key">${key}</span>${S.hudExpanded ? T('hud_collapse', 'Collapse') : T('hud_expand', 'Expand')}</div>`;
        renderHudTimer();
    }

    /* ================================================================ drone / delivery / invite / result */
    function drone(d) {
        const el = $('drone');
        if (!d || !d.show) { el.classList.add('hidden'); el.innerHTML = ''; return; }
        if (!el.innerHTML) {
            el.innerHTML = `<div class="c tl"></div><div class="c tr"></div><div class="c bl"></div><div class="c br"></div>
                <div class="read" id="dr-read"></div><div class="rec"><span class="dot red"></span>${T('drone_title', 'Recon drone')}</div>
                <div class="cross" id="dr-cross">${I('crosshair')}</div>
                <div class="drop hidden" id="dr-drop"><span class="key lg teal">G</span>${T('drone_in_zone', 'Drop payload')}</div>
                <div class="range"><i id="dr-range"></i></div>
                <div class="keys"><span><span class="key">WASD</span>Move</span><span><span class="key">Q</span><span class="key">E</span>Up / down</span><span><span class="key">SHIFT</span>Boost</span><span><span class="key">G</span>Drop</span><span><span class="key">⌫</span>Exit</span></div>`;
            el.classList.remove('hidden');
        }
        if (d.altitude != null) {
            $('dr-read').innerHTML = `<span>${T('drone_alt', 'Altitude')}<b>${d.altitude}m</b></span><span>${T('drone_range', 'Range')}<b>${d.distance} / ${d.range}m</b></span>${d.zones ? `<span>${T('drone_targets', 'Targets')}<b>${d.remaining} / ${d.zones}</b></span>` : ''}`;
            $('dr-range').style.width = Math.min(100, (d.distance / d.range) * 100) + '%';
            $('dr-cross').classList.toggle('hot', !!d.inZone);
            $('dr-drop').classList.toggle('hidden', !d.inZone);
        }
    }

    let deliveryTimer = 0;
    function delivery(d) {
        clearInterval(deliveryTimer);
        const el = $('delivery');
        if (!d) return el.classList.add('hidden');
        const end = Date.now() + d.remaining * 1000;
        const draw = () => {
            const left = (end - Date.now()) / 1000;
            el.innerHTML = `<div class="tile">${I('cart')}</div>${T('delivery_eta', 'Drone delivery in')} <b>${mmss(left)}</b>`;
            if (left <= 0) clearInterval(deliveryTimer);
        };
        draw();
        el.classList.remove('hidden');
        deliveryTimer = setInterval(draw, 1000);
    }

    function invite(d) {
        const el = $('invite');
        if (!d) { el.classList.add('hidden'); return; }
        el.innerHTML = `<div class="card"><div class="card-in">
            <div class="modal-b">${Icons.avatar(d.avatar, 36, 'teal')}<div><h4>${T('invite_title', 'Crew invite')}</h4><p><b>${esc(d.nickname)}</b> · LVL ${d.level} ${T('invite_text', 'wants you on their crew.')}</p></div></div>
            <div class="timer"><i style="animation-duration:${d.timeout}s"></i></div>
            <div class="card-foot"><div class="grow"><span><span class="key">Y</span>${T('accept', 'Accept')}</span><span><span class="key">N</span>${T('decline', 'Decline')}</span></div>
                <button class="btn-line" data-act="decline">${T('decline', 'Decline')}</button><button class="btn-teal" data-act="accept">${T('accept', 'Accept')}</button></div>
        </div></div>`;
        el.querySelectorAll('[data-act]').forEach((b) => b.onclick = async () => {
            await post('crew:respond', { accept: b.dataset.act === 'accept' });
            el.classList.add('hidden');
        });
        el.classList.remove('hidden');
    }

    let resultTimer = 0;
    function result(r) {
        clearTimeout(resultTimer);
        const el = $('result');
        const reason = r.reason ? T('reason_' + r.reason, r.reason) : '';
        el.innerHTML = `<div class="card"><div class="card-in">
            <div class="card-bar"><div class="mark sm"></div><div class="title-txt">${esc(r.label)}</div><span class="end">${mmss(r.duration || 0)}</span></div>
            <div class="hero"><div class="tile ${r.success ? '' : 'red'}">${I(r.success ? 'check' : 'x')}</div><div><h2>${r.success ? T('result_success', 'Heist complete') : T('result_failed', 'Heist failed')}</h2><p>${r.success ? T('result_success_sub', 'Clean getaway. Lay low for a while.') : esc(reason)}</p></div></div>
            <div class="grid">
                <div><span>${T('result_time', 'Time')}</span><b>${mmss(r.duration || 0)}</b></div>
                <div><span>${T('result_xp', 'Experience')}</span><b>+${r.xp || 0}</b></div>
                <div><span>${T('result_cut', 'Your cut')}</span><b class="money">${money(r.money)}</b></div>
                <div><span>${T('result_loot', 'Total take')}</span><b class="money">${money(r.earned)}</b></div>
            </div>
            ${r.leveled ? `<div class="lvl"><span class="dot"></span>${T('result_levelup', 'Level up')} · LVL ${r.level}</div>` : ''}
        </div></div>`;
        el.classList.remove('hidden');
        resultTimer = setTimeout(() => el.classList.add('hidden'), 9000);
    }

    /* ================================================================ tablet chrome */
    const NAV = [
        ['grp_jobs', 'Jobs', [['heists', 'target', 'tab_heists', 'Heists'], ['crew', 'users', 'tab_crew', 'Crew']]],
        ['grp_market', 'Black market', [['market', 'cart', 'tab_market', 'Market'], ['fence', 'bag', 'tab_fence', 'Fence']]],
        ['grp_network', 'Network', [['profile', 'user', 'tab_profile', 'Profile'], ['board', 'trophy', 'tab_board', 'Leaderboard'], ['chat', 'chat', 'tab_chat', 'Underground']]],
    ];

    const STATUS = {
        heists: [['↵', 'Start heist'], ['/', 'Search']],
        crew: [['ID', 'Invite by server id'], ['Y', 'Accept invites']],
        market: [['+', 'Add to cart']],
        fence: [['$', 'Sell at a heist contact']],
        profile: [['↵', 'Save nickname']],
        board: [],
        chat: [['↵', 'Send']],
    };

    function renderSide() {
        const p = S.profile;
        const c = S.crew;
        const pct = p && p.levelNeed ? (p.levelXp / p.levelNeed) * 100 : 100;
        const busy = c && c.heist;
        let h = '';
        if (p) {
            h += `<div class="who" id="who">${Icons.avatar(p.avatar, 34, 'teal')}<div class="who-txt"><b>${esc(p.nickname)}</b><span>LVL ${p.level} · ${p.levelNeed ? `${p.levelXp}/${p.levelNeed} XP` : 'MAX'}</span><div class="xp"><i style="width:${pct}%"></i></div></div></div>`;
            h += `<div class="shift"><span>${c ? c.members.length : 1}/8 ${T('crew', 'crew')}</span><b class="${busy ? 'red' : ''}"><span class="dot ${busy ? 'red' : ''}"></span>${busy ? T('on_job', 'On a job') : T('standby', 'Standby')}</b></div>`;
        }
        NAV.forEach(([gk, gl, items]) => {
            h += `<div class="grp">${T(gk, gl)}</div>`;
            items.forEach(([id, icon, key, label]) => {
                let tally = '';
                if (id === 'chat' && S.unreadChat) tally = `<span class="tally red">${S.unreadChat}</span>`;
                else if (id === 'crew' && c) tally = `<span class="tally">${c.members.length}</span>`;
                else if (id === 'heists' && S.heists.length) tally = `<span class="tally">${S.heists.length}</span>`;
                h += `<button class="nav ${S.tab === id ? 'on' : ''}" data-tab="${id}">${I(icon)}${T(key, label)}${tally}</button>`;
            });
        });
        $('side').innerHTML = h;
        $('side').querySelectorAll('[data-tab]').forEach((b) => b.onclick = () => go(b.dataset.tab));
        const who = $('who');
        if (who) who.onclick = () => go('profile');
    }

    function renderBar() {
        const busy = S.crew && S.crew.heist;
        $('bar-dot').className = 'dot' + (S.police === 0 ? ' red' : '');
        $('bar-status').innerHTML = busy
            ? `${T('bar_on_job', 'On the job')} · <b>${esc(busy.label)}</b> · ${T('police_on', 'police on duty')} <b>${S.police}</b>`
            : `${T('bar_connected', 'Connected to the')} <b>${T('bar_network', 'underground')}</b> · <b>${S.police}</b> ${T('police_on', 'police on duty')}`;
    }

    function renderStatus() {
        const keys = [['ESC', T('close', 'Close')]].concat(STATUS[S.tab] || []);
        const f = S.featured && S.heists.find((x) => x.id === S.featured);
        $('statusbar').innerHTML = keys.map(([k, l]) => `<span><span class="key">${esc(k)}</span>${esc(l)}</span>`).join('')
            + (f ? `<span class="right">${T('featured', 'Featured today')} · <b>${esc(f.label)}</b></span>` : '');
    }

    function tickClock() {
        const d = new Date();
        $('clock-time').textContent = d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
        $('clock-date').textContent = d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });
    }

    function head(title, sub) { $('page-title').textContent = title; $('page-sub').textContent = sub || ''; }

    function stat(icon, label, value, opts) {
        opts = opts || {};
        return `<div class="stat"><div class="tile ${opts.red ? 'red' : ''}">${I(icon)}</div><div class="stat-txt"><span>${esc(label)}</span><b>${value}</b></div>${opts.delta ? `<div class="delta ${opts.down ? 'dn' : ''}">${opts.delta}</div>` : ''}</div>`;
    }

    function empty(icon, title, text) {
        return `<div class="empty">${I(icon)}<b>${esc(title)}</b>${text ? `<span>${esc(text)}</span>` : ''}</div>`;
    }

    async function go(tab) {
        S.tab = tab;
        if (tab === 'chat') S.unreadChat = 0;
        renderSide();
        renderStatus();
        $('page').innerHTML = '';
        if (tab === 'heists') { await loadHeists(); renderHeists(); }
        else if (tab === 'crew') renderCrew();
        else if (tab === 'market') { S.market = await post('market:data'); renderMarket(); }
        else if (tab === 'fence') { S.fence = unwrap(await post('fence:data')).data; renderFence(); }
        else if (tab === 'profile') { S.history = arr(await post('profile:history')); renderProfile(); }
        else if (tab === 'board') { S.board = arr(await post('profile:leaderboard')); renderBoard(); }
        else if (tab === 'chat') { S.chat = arr(await post('chat:history')); renderChat(); }
    }

    /* ---------- heists */
    async function loadHeists() {
        const d = unwrap(await post('heists:list')).data || {};
        S.heists = d.heists || [];
        S.police = d.police || 0;
        S.playerCooldown = d.playerCooldown || 0;
        renderBar(); renderSide(); renderStatus();
        if (!S.selected || !S.heists.find((h) => h.id === S.selected)) S.selected = (S.heists.find((h) => h.featured) || S.heists[0] || {}).id;
    }

    function heistState(h) {
        if (h.locked) return ['hot', `LVL ${h.level}`];
        if (h.cooldown > 0) return ['off', `${Math.ceil(h.cooldown / 60)}m`];
        if (h.running >= h.simultaneous) return ['warn', T('busy', 'Busy')];
        if (S.police < h.police) return ['off', `${h.police} ${T('police_short', 'cops')}`];
        if (h.featured) return ['live', T('featured_short', 'Featured')];
        return ['live', T('available', 'Available')];
    }

    const TIER = { small: ['chip', 'Small'], medium: ['chip amber', 'Medium'], major: ['chip red', 'Major'] };

    function renderHeists() {
        const avail = S.heists.filter((h) => !h.locked && h.cooldown <= 0).length;
        const f = S.heists.find((h) => h.featured);
        head(T('tab_heists', 'Heists'), T('heists_sub', 'Pick a job, check the requirements and brief your crew.'));
        const q = S.search.toLowerCase();
        const list = S.heists.filter((h) => (S.filter === 'all' || h.category === S.filter) && (!q || h.label.toLowerCase().includes(q)));
        const filters = ['all', 'small', 'medium', 'major'].map((k) => `<button class="btn-ghost ${S.filter === k ? 'on' : ''}" data-f="${k}">${T(k, k[0].toUpperCase() + k.slice(1))}</button>`).join('');
        const rows = list.map((h) => {
            const [cls, label] = heistState(h);
            const tier = TIER[h.category] || TIER.small;
            return `<button class="row ${S.selected === h.id ? 'on' : ''} ${h.locked ? 'dim' : ''}" data-id="${h.id}">
                <div class="tile sm ${h.locked ? 'mute' : (h.category === 'major' ? 'red' : '')}">${I(h.icon)}</div>
                <div class="row-txt"><b>${esc(h.label)} <span class="${tier[0]}">${T(h.category, tier[1])}</span></b><span>LVL ${h.level} · ${h.members.min}-${h.members.max} ${T('crew', 'crew')} · ${h.police} ${T('police_short', 'cops')}${h.timeLimit ? ` · ${h.timeLimit}m` : ''}</span></div>
                <span class="tag ${cls}">${esc(label)}</span>
            </button>`;
        }).join('');

        $('page').innerHTML = `
            <div class="stats">
                ${stat('target', T('stat_jobs', 'Jobs available'), `${avail}<small> / ${S.heists.length}</small>`)}
                ${stat('siren', T('stat_police', 'Police on duty'), S.police, { red: S.police === 0 })}
                ${stat('star', T('stat_featured', 'Featured today'), f ? `<span style="font-size:17px;letter-spacing:-.02em">${esc(f.label)}</span>` : '-', { delta: f && S.featuredBonus ? `×${S.featuredBonus.money} cash` : '' })}
            </div>
            <div class="cols">
                <section class="panel">
                    <div class="p-head"><div><h2>${T('jobs', 'Jobs')}</h2><p>${list.length} ${T('listed', 'listed')}</p></div><div class="p-tools">${filters}</div></div>
                    <div style="padding:10px 10px 0"><input class="input" id="hsearch" placeholder="${T('search', 'Search heists...')}" value="${esc(S.search)}"/></div>
                    <div class="p-body">${rows || empty('target', T('no_match', 'No heists match'), T('no_match_sub', 'Try a different filter or search.'))}</div>
                </section>
                <section class="panel" id="hdetail"></section>
            </div>`;
        $('hsearch').oninput = (e) => { S.search = e.target.value; const pos = e.target.selectionStart; renderHeists(); const i = $('hsearch'); i.focus(); i.setSelectionRange(pos, pos); };
        $('page').querySelectorAll('[data-f]').forEach((b) => b.onclick = () => { S.filter = b.dataset.f; renderHeists(); });
        $('page').querySelectorAll('[data-id]').forEach((b) => b.onclick = () => { S.selected = b.dataset.id; renderHeists(); });
        renderDetail();
    }

    function renderDetail() {
        const el = $('hdetail');
        if (!el) return;
        const crew = S.crew;
        const active = crew && crew.heist;
        const isLeader = crew && crew.leader === S.serverId;
        if (active) {
            el.innerHTML = `
                <div class="p-head"><div><h2>${T('active_job', 'Active job')}</h2><p>${T('active_sub', 'Follow the objectives on your HUD.')}</p></div><span class="tag hot">${T('live', 'Live')}</span></div>
                <div class="p-body pad">
                    <article class="inc urgent">
                        <div class="inc-top"><span class="chip red">${T('in_progress', 'In progress')}</span><span class="ref">${active.stage}/${active.stages}</span></div>
                        <h3>${esc(active.label)}</h3><p>${esc(active.task || '')}</p>
                        <div class="meta"><span>${T('crew_label', 'Crew')} <b>${crew.members.length}</b></span><span>${T('leader', 'Leader')} <b>${esc((crew.members.find((m) => m.leader) || {}).nickname || '-')}</b></span></div>
                    </article>
                </div>
                <div class="p-foot"><span class="grow">${isLeader ? T('abort_hint', 'Aborting fails the heist for the whole crew.') : T('leader_only', 'Only the leader can abort.')}</span>${isLeader ? `<button class="btn-red" id="hstop">${I('x')}${T('stop', 'Abort heist')}</button>` : ''}</div>`;
            const stop = $('hstop');
            if (stop) stop.onclick = async () => { const r = unwrap(await post('heist:stop')); if (!r.ok && r.data) notify({ text: r.data, kind: 'error' }); };
            return;
        }
        const h = S.heists.find((x) => x.id === S.selected);
        if (!h) { el.innerHTML = `<div class="p-body pad">${empty('target', T('pick_heist', 'Pick a heist'), '')}</div>`; return; }
        const tier = TIER[h.category] || TIER.small;
        const cash = h.money ? `${money(h.money[0])}–${money(h.money[1]).slice(1)}` : '-';
        const blockers = [];
        if (h.locked) blockers.push(['red', `${T('needs_level', 'Needs')} LVL ${h.level}`]);
        if (h.cooldown > 0) blockers.push(['off', `${T('cooldown', 'Cooldown')} ${Math.ceil(h.cooldown / 60)}m`]);
        if (S.police < h.police) blockers.push(['red', `${T('police', 'Police')} ${S.police}/${h.police}`]);
        if (h.running >= h.simultaneous) blockers.push(['amber', T('busy_long', 'Another crew is on it')]);
        if (!isLeader) blockers.push(['off', T('leader_only_start', 'Leader starts the job')]);
        el.innerHTML = `
            <div class="p-head"><div><h2>${I(h.icon)}${esc(h.label)}</h2><p>${h.locations} ${h.locations === 1 ? T('location', 'location') : T('locations', 'locations')} · +${h.xp} XP</p></div><div class="p-tools"><span class="${tier[0]}">${T(h.category, tier[1])}</span>${h.featured ? `<span class="chip">${T('featured_short', 'Featured')}</span>` : ''}</div></div>
            <div class="p-body pad">
                <p class="detail-desc">${esc(h.description)}</p>
                <div class="facts">
                    <div class="fact"><span>${T('level', 'Level')}</span><b>${h.level}</b></div>
                    <div class="fact"><span>${T('police', 'Police')}</span><b>${h.police}</b></div>
                    <div class="fact"><span>${T('crew_label', 'Crew')}</span><b>${h.members.min}–${h.members.max}</b></div>
                    <div class="fact"><span>${T('time_limit', 'Time limit')}</span><b>${h.timeLimit ? h.timeLimit + 'm' : '∞'}</b></div>
                    <div class="fact"><span>${T('cooldown', 'Cooldown')}</span><b>${h.playerCooldown || 0}m</b></div>
                    <div class="fact"><span>${T('reward', 'Payout')}</span><b class="money">${cash}</b></div>
                </div>
                ${h.requiredItems.length ? `<div class="sect"><div class="sect-h">${T('required_items', 'Required items')}</div><div class="chips">${h.requiredItems.map((i) => `<span class="chip off">${esc(i.label)}${i.count > 1 ? ' ×' + i.count : ''}</span>`).join('')}</div></div>` : ''}
                <div class="sect"><div class="sect-h">${T('briefing', 'Briefing')}</div><div class="steps">${h.briefing.map((b, n) => `<div class="step"><i>${n + 1}</i><span>${esc(b)}</span></div>`).join('')}</div></div>
            </div>
            <div class="p-foot"><div class="grow blockers">${blockers.map(([c, t]) => `<span class="chip ${c}">${esc(t)}</span>`).join('')}</div><button class="btn-teal" id="hstart" ${h.locked || !isLeader ? 'disabled' : ''}>${I('bolt')}${T('start', 'Start heist')}</button></div>`;
        $('hstart').onclick = async () => {
            $('hstart').disabled = true;
            const r = unwrap(await post('heist:start', { id: h.id }));
            if (!r.ok) { notify({ text: r.data || 'Could not start', kind: 'error' }); $('hstart').disabled = false; }
        };
    }

    /* ---------- crew */
    function renderCrew() {
        const c = S.crew;
        head(T('tab_crew', 'Crew'), T('crew_sub', 'Build your team. Everyone gets a share of the completion payout.'));
        if (!c) { $('page').innerHTML = empty('users', '...', ''); return; }
        const isLeader = c.leader === S.serverId;
        const me = c.members.find((m) => m.source === S.serverId);
        const ready = c.members.filter((m) => m.ready).length;
        const leader = c.members.find((m) => m.leader);
        const rows = c.members.map((m) => `
            <div class="row">
                ${Icons.avatar(m.avatar, 30, m.leader ? 'teal' : '')}
                <div class="row-txt"><b>${esc(m.nickname)} ${m.leader ? `<span class="chip">${T('leader', 'Leader')}</span>` : ''} ${m.source === S.serverId ? `<span class="chip off">${T('you', 'You')}</span>` : ''}</b><span>LVL ${m.level} · ID ${m.source}</span></div>
                <div class="end">
                    ${isLeader && m.source !== S.serverId ? `<button class="btn-ghost" data-promote="${m.source}">${I('crown')}${T('promote', 'Lead')}</button><button class="btn-ghost danger" data-kick="${m.source}">${I('x')}${T('kick', 'Kick')}</button>` : ''}
                    <span class="tag ${m.ready ? 'live' : 'off'}">${m.ready ? T('ready', 'Ready') : T('not_ready', 'Not ready')}</span>
                </div>
            </div>`).join('');
        $('page').innerHTML = `
            <div class="stats">
                ${stat('users', T('stat_members', 'Members'), `${c.members.length}<small> / 8</small>`)}
                ${stat('check', T('stat_ready', 'Ready'), `${ready}<small> / ${c.members.length}</small>`, { red: ready < c.members.length })}
                ${stat('crown', T('leader', 'Leader'), `<span style="font-size:17px;letter-spacing:-.02em">${esc(leader ? leader.nickname : '-')}</span>`)}
            </div>
            <div class="cols even">
                <section class="panel"><div class="p-head"><div><h2>${T('members', 'Members')}</h2><p>${T('members_sub', 'Your crew for the next job')}</p></div></div><div class="p-body">${rows}</div></section>
                <section class="panel">
                    <div class="p-head"><div><h2>${T('invite', 'Invite')}</h2><p>${T('invite_sub', 'They get a popup and accept with Y')}</p></div></div>
                    <div class="p-body pad">
                        <div class="field"><label>${T('invite_placeholder', 'Server ID')}</label><div class="compose"><input class="input" id="inv-id" placeholder="e.g. 14" ${isLeader ? '' : 'disabled'}/><button class="btn-teal" id="inv-btn" ${isLeader ? '' : 'disabled'}>${I('plus')}${T('invite', 'Invite')}</button></div></div>
                        ${isLeader ? '' : empty('crown', T('not_leader', 'You are not the leader'), T('not_leader_sub', 'Only the crew leader can invite and start jobs.'))}
                    </div>
                    <div class="p-foot"><span class="grow">${T('crew_hint', 'Everyone except the leader must be ready.')}</span>
                        ${!isLeader && me ? `<button class="${me.ready ? 'btn-line' : 'btn-teal'}" id="ready-btn">${I('check')}${me.ready ? T('not_ready', 'Not ready') : T('ready', 'Ready')}</button>` : ''}
                        ${c.members.length > 1 ? `<button class="btn-red" id="leave-btn">${T('leave', 'Leave crew')}</button>` : ''}
                    </div>
                </section>
            </div>`;
        const act = async (name, data) => { const r = unwrap(await post(name, data)); if (r.data && typeof r.data === 'string') notify({ text: r.data, kind: r.ok ? 'success' : 'error' }); return r; };
        const inv = $('inv-btn');
        if (inv) inv.onclick = async () => { const v = $('inv-id').value.trim(); if (!v) return; await act('crew:invite', { target: v }); $('inv-id').value = ''; };
        const inp = $('inv-id');
        if (inp) inp.onkeydown = (e) => { if (e.key === 'Enter' && inv) inv.click(); };
        const rb = $('ready-btn');
        if (rb) rb.onclick = () => act('crew:ready', { state: !me.ready });
        const lb = $('leave-btn');
        if (lb) lb.onclick = () => act('crew:leave');
        $('page').querySelectorAll('[data-kick]').forEach((b) => b.onclick = () => act('crew:kick', { target: b.dataset.kick }));
        $('page').querySelectorAll('[data-promote]').forEach((b) => b.onclick = () => act('crew:promote', { target: b.dataset.promote }));
    }

    /* ---------- market */
    const CAT_ICON = { tools: 'crosshair', electronics: 'chip', explosives: 'fire', gear: 'mask' };

    function renderMarket() {
        const m = unwrap(S.market).data || {};
        head(T('tab_market', 'Market'), T('market_sub', 'Heist gear, delivered by drone wherever you are.'));
        if (!m.enabled) { $('page').innerHTML = empty('cart', T('market_closed', 'Market closed'), ''); return; }
        const level = S.profile ? S.profile.level : 1;
        const cats = [['all', T('all', 'All')]].concat((m.categories || []).map((c) => [c.id, c.label]));
        const items = (m.items || []).filter((i) => S.marketCat === 'all' || i.category === S.marketCat);
        const max = m.maxPerItem || 10;
        const rows = items.map((i) => {
            const locked = level < (i.level || 1);
            return `<div class="row ${locked ? 'dim' : ''}">
                <div class="tile sm ${locked ? 'mute' : ''}">${I(CAT_ICON[i.category] || 'bag')}</div>
                <div class="row-txt"><b>${esc(i.label)}</b><span>${esc(i.used || '')}</span></div>
                <div class="end"><span class="amount">${money(i.price)}</span>${locked ? `<span class="tag hot">LVL ${i.level}</span>` : `<button class="btn-ghost" data-add="${i.name}">${I('plus')}${T('add', 'Add')}</button>`}</div>
            </div>`;
        }).join('');
        const cart = Object.entries(S.cart).map(([name, qty]) => {
            const it = m.items.find((i) => i.name === name);
            return `<div class="row"><div class="row-txt"><b>${esc(it.label)}</b><span>${money(it.price)} ${T('each', 'each')}</span></div><div class="end"><div class="qty"><button data-dec="${name}">${I('minus')}</button><b>${qty}</b><button data-inc="${name}">${I('plus')}</button></div><span class="amount money" style="min-width:64px;text-align:right">${money(it.price * qty)}</span></div></div>`;
        }).join('');
        const total = Object.entries(S.cart).reduce((a, [n, q]) => a + (m.items.find((i) => i.name === n) || { price: 0 }).price * q, 0);
        const order = m.order ? `<article class="inc"><div class="inc-top"><span class="chip">${T('delivery', 'Drone delivery')}</span><span class="ref">${mmss(m.order.remaining)}</span></div><h3>${T('order_en_route', 'Order en route')}</h3><p>${T('order_text', 'A drone drops the bag next to you when the timer ends. Pick it up to collect.')}</p><div class="meta"><span>${T('total', 'Total')} <b>${money(m.order.total)}</b></span></div></article>` : '';
        $('page').innerHTML = `
            <div class="cols side-r">
                <section class="panel">
                    <div class="p-head"><div><h2>${T('catalogue', 'Catalogue')}</h2><p>${items.length} ${T('items', 'items')}</p></div><div class="p-tools">${cats.map(([id, l]) => `<button class="btn-ghost ${S.marketCat === id ? 'on' : ''}" data-cat="${id}">${esc(l)}</button>`).join('')}</div></div>
                    <div class="p-body">${rows}</div>
                </section>
                <section class="panel">
                    <div class="p-head"><div><h2>${T('cart', 'Cart')}</h2><p>${T('cart_sub', 'Max')} ${max} ${T('per_item', 'per item')}</p></div></div>
                    <div class="p-body">${order}${cart || (order ? '' : empty('cart', T('cart_empty', 'Your cart is empty'), T('cart_empty_sub', 'Add gear from the catalogue.')))}</div>
                    <div class="p-foot" style="flex-direction:column;align-items:stretch;gap:10px">
                        <div class="total"><span>${T('total', 'Total')}</span><b>${money(total)}</b></div>
                        <div class="compose"><button class="btn-teal" style="flex:1" data-pay="cash" ${!total || m.order ? 'disabled' : ''}>${T('pay_cash', 'Pay cash')}</button><button class="btn-white" style="flex:1" data-pay="bank" ${!total || m.order ? 'disabled' : ''}>${T('pay_bank', 'Pay bank')}</button></div>
                    </div>
                </section>
            </div>`;
        $('page').querySelectorAll('[data-cat]').forEach((b) => b.onclick = () => { S.marketCat = b.dataset.cat; renderMarket(); });
        $('page').querySelectorAll('[data-add]').forEach((b) => b.onclick = () => { S.cart[b.dataset.add] = Math.min(max, (S.cart[b.dataset.add] || 0) + 1); renderMarket(); });
        $('page').querySelectorAll('[data-inc]').forEach((b) => b.onclick = () => { S.cart[b.dataset.inc] = Math.min(max, S.cart[b.dataset.inc] + 1); renderMarket(); });
        $('page').querySelectorAll('[data-dec]').forEach((b) => b.onclick = () => { S.cart[b.dataset.dec]--; if (S.cart[b.dataset.dec] <= 0) delete S.cart[b.dataset.dec]; renderMarket(); });
        $('page').querySelectorAll('[data-pay]').forEach((b) => b.onclick = async () => {
            const cartList = Object.entries(S.cart).map(([name, amount]) => ({ name, amount }));
            const r = unwrap(await post('market:buy', { cart: cartList, account: b.dataset.pay }));
            if (r.ok) {
                S.cart = {};
                notify({ text: r.data && r.data.instant ? T('delivered', 'Delivered to your inventory.') : `${T('delivery', 'Drone delivery')} · ${r.data.seconds}s`, kind: 'success', title: T('order_placed', 'Order placed') });
                S.market = await post('market:data'); renderMarket();
            } else notify({ text: r.data || 'Failed', kind: 'error' });
        });
    }

    /* ---------- fence */
    function renderFence() {
        const f = S.fence;
        head(T('tab_fence', 'Fence'), T('fence_sub', 'Turn hot loot into clean cash. Prices move every day.'));
        if (!f) { $('page').innerHTML = empty('bag', T('fence_closed', 'Fence closed'), ''); return; }
        const total = f.items.reduce((a, i) => a + i.price * i.owned, 0);
        $('page').innerHTML = `
            <section class="panel fill">
                <div class="p-head"><div><h2>${T('todays_prices', "Today's prices")}</h2><p>${T('worth', 'Your stash is worth')} <span class="money">${money(total)}</span></p></div><span class="tag ${f.near ? 'live' : 'off'}">${f.near ? T('at_fence', 'At a fence') : T('fence_far_short', 'Visit a contact to sell')}</span></div>
                <div class="p-body pad"><table>
                    <thead><tr><th>${T('item', 'Item')}</th><th>${T('price', 'Price')}</th><th>${T('owned', 'Owned')}</th><th>${T('qty', 'Qty')}</th><th class="r"></th></tr></thead>
                    <tbody>${f.items.map((i) => `<tr>
                        <td><b>${esc(i.label)}</b></td><td class="money">${money(i.price)}</td><td>${i.owned}</td>
                        <td><input class="input sm" style="width:72px" type="number" min="1" max="${i.owned}" value="1" id="q-${i.name}" ${i.owned ? '' : 'disabled'}/></td>
                        <td class="r"><div class="compose" style="justify-content:flex-end"><button class="btn-ghost" data-sell="${i.name}" ${i.owned && f.near ? '' : 'disabled'}>${T('sell', 'Sell')}</button><button class="btn-ghost" data-all="${i.name}" ${i.owned && f.near ? '' : 'disabled'}>${T('sell_all', 'Sell all')}</button></div></td>
                    </tr>`).join('')}</tbody>
                </table></div>
            </section>`;
        const sell = async (name, amount) => {
            const r = unwrap(await post('fence:sell', { name, amount }));
            notify({ text: r.data || (r.ok ? 'Sold' : 'Failed'), kind: r.ok ? 'success' : 'error', title: r.ok ? T('sold', 'Sold') : undefined });
            S.fence = unwrap(await post('fence:data')).data; renderFence();
        };
        $('page').querySelectorAll('[data-sell]').forEach((b) => b.onclick = () => sell(b.dataset.sell, Number($('q-' + b.dataset.sell).value) || 1));
        $('page').querySelectorAll('[data-all]').forEach((b) => b.onclick = () => sell(b.dataset.all, f.items.find((i) => i.name === b.dataset.all).owned));
    }

    /* ---------- profile */
    function renderProfile() {
        const p = S.profile;
        head(T('tab_profile', 'Profile'), T('profile_sub', 'Your street name, level and record.'));
        if (!p) return;
        const pct = p.levelNeed ? (p.levelXp / p.levelNeed) * 100 : 100;
        const avatars = Array.from({ length: Icons.count }, (_, n) => `<button class="${p.avatar === n + 1 ? 'sel' : ''}" data-av="${n + 1}">${Icons.avatar(n + 1)}</button>`).join('');
        const hist = (S.history || []).map((h) => `
            <article class="inc ${h.success ? '' : 'urgent'}">
                <div class="inc-top"><span class="chip ${h.success ? '' : 'red'}">${h.success ? T('completed', 'Completed') : T('failed', 'Failed')}</span><span class="ref">${mmss(h.duration)}</span></div>
                <h3>${esc(h.label)}</h3>
                <div class="meta"><span>${T('location', 'Location')} <b>${esc(h.location || '-')}</b></span><span>${T('payout', 'Payout')} <b class="money">${money(h.payout)}</b></span>${h.reason && !h.success ? `<span>${esc(T('reason_' + h.reason, h.reason))}</span>` : ''}</div>
            </article>`).join('');
        $('page').innerHTML = `
            <div class="stats">
                ${stat('check', T('completed', 'Completed'), p.completed)}
                ${stat('x', T('failed', 'Failed'), p.failed, { red: true })}
                ${stat('coin', T('earned', 'Earned'), money(p.earned))}
            </div>
            <div class="cols even">
                <section class="panel">
                    <div class="p-head"><div><h2>${T('identity', 'Identity')}</h2><p>${T('identity_sub', 'Shown in crews, chat and the leaderboard')}</p></div></div>
                    <div class="p-body pad">
                        <div class="ident">${Icons.avatar(p.avatar, 56, 'teal')}<div><h3>${esc(p.nickname)}</h3><p>LVL ${p.level} · ${p.xp.toLocaleString('en-US')} XP</p></div></div>
                        <div class="levelbar"><div class="top"><span>${T('next_level', 'Next level')}</span><b>${p.levelNeed ? `${p.levelXp} / ${p.levelNeed} XP` : 'MAX'}</b></div><div class="track"><i style="width:${pct}%"></i></div></div>
                        <div class="field"><label>${T('nickname', 'Nickname')}</label><div class="compose"><input class="input" id="nick" maxlength="20" value="${esc(p.nickname)}"/><button class="btn-teal" id="nick-save">${T('save', 'Save')}</button></div></div>
                        <div class="field"><label>${T('avatar', 'Avatar')}</label><div class="avatar-pick">${avatars}</div></div>
                        <div class="sect"><div class="sect-h">${T('perks', 'Level perks')}</div>
                            <div class="perk"><span>${T('loot_bonus', 'Loot bonus')}</span><b>+${Math.round((p.perks.loot - 1) * 100)}%</b></div>
                            <div class="perk"><span>${T('speed_bonus', 'Action speed')}</span><b>+${Math.round((p.perks.speed - 1) * 100)}%</b></div>
                        </div>
                    </div>
                </section>
                <section class="panel">
                    <div class="p-head"><div><h2>${T('history', 'Recent jobs')}</h2><p>${T('history_sub', 'Your last 15 heists')}</p></div></div>
                    <div class="p-body">${hist || empty('clock', T('no_history', 'No jobs yet'), T('no_history_sub', 'Finished heists show up here.'))}</div>
                </section>
            </div>`;
        const save = async () => {
            const r = unwrap(await post('profile:nickname', { nickname: $('nick').value }));
            if (r.ok && r.data && typeof r.data === 'object') { S.profile = r.data; renderSide(); renderProfile(); notify({ text: T('nick_saved', 'Nickname updated.'), kind: 'success', title: T('saved', 'Saved') }); }
            else notify({ text: r.data || 'Failed', kind: 'error' });
        };
        $('nick-save').onclick = save;
        $('nick').onkeydown = (e) => { if (e.key === 'Enter') save(); };
        $('page').querySelectorAll('[data-av]').forEach((b) => b.onclick = async () => {
            const r = unwrap(await post('profile:avatar', { avatar: Number(b.dataset.av) }));
            if (r.ok && r.data) { S.profile = r.data; renderSide(); renderProfile(); }
        });
    }

    /* ---------- leaderboard */
    function renderBoard() {
        head(T('tab_board', 'Leaderboard'), T('board_sub', 'Top players by experience.'));
        const rows = (S.board || []).map((r, i) => `<tr>
            <td><span class="rank ${i < 3 ? 'g' + (i + 1) : ''}">${i + 1}</span></td>
            <td><div class="cell">${Icons.avatar(r.avatar, 28, i === 0 ? 'teal' : '')}<b>${esc(r.nickname)}</b></div></td>
            <td>LVL ${r.level}</td><td>${r.completed}</td><td class="r money">${money(r.earned)}</td></tr>`).join('');
        $('page').innerHTML = `<section class="panel fill">
            <div class="p-head"><div><h2>${T('top_players', 'Top players')}</h2><p>${T('board_refresh', 'Refreshes every minute')}</p></div></div>
            <div class="p-body pad">${rows ? `<table><thead><tr><th>#</th><th>${T('player', 'Player')}</th><th>${T('level', 'Level')}</th><th>${T('jobs_done', 'Jobs')}</th><th class="r">${T('earned', 'Earned')}</th></tr></thead><tbody>${rows}</tbody></table>` : empty('trophy', T('board_empty', 'Nobody yet'), T('board_empty_sub', 'Finish a heist to get on the board.'))}</div>
        </section>`;
    }

    /* ---------- chat */
    function msgHtml(m) {
        const me = m.source === S.serverId;
        const time = m.time ? new Date(m.time * 1000).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) : '';
        return `<div class="msg ${me ? 'me' : ''}">${Icons.avatar(m.avatar, 30, me ? 'teal' : '')}<div class="bub"><div class="who-l">${esc(m.nickname)} <small>LVL ${m.level} · ${time}</small></div><div class="txt">${esc(m.text)}</div></div></div>`;
    }

    function renderChat() {
        head(T('tab_chat', 'Underground'), T('chat_sub', 'Everyone with a tablet open can read this.'));
        $('page').innerHTML = `<section class="panel fill">
            <div class="p-head"><div><h2>${T('channel', '#underground')}</h2><p>${T('chat_rules', 'No names, no faces.')}</p></div><span class="tag live">${T('live', 'Live')}</span></div>
            <div class="p-body pad" id="log">${(S.chat || []).map(msgHtml).join('') || empty('chat', T('chat_empty', 'Quiet in here'), T('chat_empty_sub', 'Say something to the network.'))}</div>
            <div class="p-foot"><div class="compose" style="flex:1"><input class="input" id="chat-in" maxlength="180" placeholder="${T('chat_placeholder', 'Say something...')}"/><button class="btn-teal" id="chat-send">${I('send')}${T('send', 'Send')}</button></div></div>
        </section>`;
        const log = $('log'); log.scrollTop = log.scrollHeight;
        const send = async () => {
            const v = $('chat-in').value.trim();
            if (!v) return;
            $('chat-in').value = '';
            const r = unwrap(await post('chat:send', { text: v }));
            if (!r.ok && r.data) notify({ text: r.data, kind: 'error' });
        };
        $('chat-send').onclick = send;
        $('chat-in').onkeydown = (e) => { if (e.key === 'Enter') send(); };
        $('chat-in').focus();
    }

    function chatMessage(m) {
        S.chat.push(m);
        if (S.chat.length > 60) S.chat.shift();
        const log = $('log');
        if (S.tab === 'chat' && log && !$('tablet').classList.contains('hidden')) {
            if (log.querySelector('.empty')) log.innerHTML = '';
            log.insertAdjacentHTML('beforeend', msgHtml(m));
            log.scrollTop = log.scrollHeight;
        } else { S.unreadChat++; if (!$('tablet').classList.contains('hidden')) renderSide(); }
    }

    /* ---------- open / close */
    function openMenu(d) {
        S.profile = d.profile; S.crew = d.crew; S.featured = d.featured; S.featuredBonus = d.featuredBonus; S.serverId = d.serverId;
        $('tablet').classList.remove('hidden');
        tickClock();
        clearInterval(S.clockTimer);
        S.clockTimer = setInterval(tickClock, 15000);
        renderBar();
        const tab = d.tab || S.tab || 'heists';
        go(tab);
        if (tab !== 'heists') loadHeists();
    }

    function closeMenu() {
        $('tablet').classList.add('hidden');
        $('page').innerHTML = '';
        clearInterval(S.clockTimer);
    }

    function crewUpdate(c) {
        S.crew = c;
        if (S.profile && c) {
            const me = c.members.find((m) => m.source === S.serverId);
            if (me) { S.profile.nickname = me.nickname; S.profile.avatar = me.avatar; }
        }
        if ($('tablet').classList.contains('hidden')) return;
        renderSide(); renderBar();
        if (S.tab === 'crew') renderCrew();
        if (S.tab === 'heists') renderDetail();
    }

    $('close-btn').onclick = () => post('menu:close');

    window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (window.Minigames && Minigames.active()) { Minigames.cancel(); return; }
            if (!$('tablet').classList.contains('hidden')) post('menu:close');
        } else if (e.key === '/' && S.tab === 'heists' && $('hsearch') && document.activeElement !== $('hsearch')) {
            e.preventDefault(); $('hsearch').focus();
        } else if (e.key === 'Enter' && S.tab === 'heists' && document.activeElement === document.body && $('hstart') && !$('hstart').disabled) {
            $('hstart').click();
        }
    });

    /* ================================================================ message router */
    const handlers = {
        init(d) {
            S.ui = d.ui;
            window.UIStrings = d.strings || {};
            applyTheme(d.ui); translate();
        },
        notify, textui, progress, hud, drone, delivery, invite, result,
        hudToggle() { S.hudExpanded = !S.hudExpanded; if (S.hud) renderHud(); },
        noise(d) { S.noise = d ? d.value : null; if (S.hud) renderHud(); },
        minigame(d) { Minigames.start(d.type, d.difficulty, (ok) => post('minigame', { success: ok })); },
        menu(d) { if (d.open) openMenu(d.data); else closeMenu(); },
        crew: crewUpdate,
        chat: chatMessage,
    };

    window.addEventListener('message', (e) => {
        const m = e.data;
        if (!m || !m.action || !handlers[m.action]) return;
        handlers[m.action](m.data);
    });

    window.NUI = { handlers, S };
    post('ready');

    if (!IN_GAME) {
        const s = document.createElement('script');
        s.src = 'preview.js';
        document.body.appendChild(s);
    }
})();
