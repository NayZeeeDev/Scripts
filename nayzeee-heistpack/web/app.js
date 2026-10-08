/* nayzeee heistpack - NUI controller (vanilla JS, no build step) */
(function () {
    'use strict';

    const IN_GAME = typeof window.GetParentResourceName === 'function';
    const RES = IN_GAME ? window.GetParentResourceName() : 'nayzeee-heistpack';
    const $ = (id) => document.getElementById(id);
    const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const money = (n) => '$' + Math.floor(n || 0).toLocaleString('en-US');
    const mmss = (s) => { s = Math.max(0, Math.floor(s)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
    const T = (k, f) => (window.UIStrings && window.UIStrings[k]) || f || k;

    const Mock = {
        post(name, data) {
            const H = window.MockData || {};
            const r = H[name];
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

    const S = {
        ui: null, levels: [], profile: null, crew: null, heists: [], police: 0, playerCooldown: 0,
        featured: null, tab: 'heists', selected: null, filter: 'all', search: '',
        market: null, cart: {}, marketCat: 'all', fence: null, chat: [], board: [], history: [],
        serverId: 0, hudExpanded: true, hud: null, hudEndAt: 0, hudTimer: 0, unreadChat: 0,
    };

    /* ================================================================ theme */
    function hexToRgb(hex) {
        const h = hex.replace('#', '');
        const n = parseInt(h.length === 3 ? h.split('').map(c => c + c).join('') : h, 16);
        return `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`;
    }

    function applyTheme(ui) {
        const r = document.documentElement.style;
        const t = ui.theme || {};
        ['accent', 'accent2', 'success', 'danger', 'warning'].forEach((k) => {
            if (t[k]) { r.setProperty('--' + k, t[k]); r.setProperty(`--${k}-rgb`, hexToRgb(t[k])); }
        });
        if (t.font) r.setProperty('--font', t.font);
        if (t.radius) r.setProperty('--radius', t.radius);
        const hud = ui.hud || {};
        $('hud').classList.toggle('left', hud.position === 'left');
        $('hud').classList.toggle('bg-glass', hud.background === 'glass');
        $('hud').classList.toggle('bg-solid', hud.background === 'solid');
        r.setProperty('--hud-scale', hud.scale || 1);
        $('notify').className = 'notify ' + ((ui.notify && ui.notify.position) || 'top-right');
        $('textui').classList.toggle('right', ui.textui && ui.textui.position === 'right');
    }

    function translate() {
        document.querySelectorAll('[data-t]').forEach((el) => { el.textContent = T(el.dataset.t, el.textContent); });
    }

    /* ================================================================ toasts */
    const TOAST_ICON = { success: 'check', error: 'x', warning: 'siren', info: 'bolt' };
    function notify({ text, kind, duration }) {
        const el = document.createElement('div');
        el.className = 'toast ' + (kind || 'info');
        const d = duration || 5000;
        el.innerHTML = `${Icons.svg(TOAST_ICON[kind] || 'bolt')}<div>${esc(text)}</div><div class="bar" style="animation-duration:${d}ms"></div>`;
        $('notify').prepend(el);
        while ($('notify').children.length > 5) $('notify').lastChild.remove();
        setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 300); }, d);
    }

    /* ================================================================ text ui / progress */
    function textui(data) {
        const el = $('textui');
        if (!data) return el.classList.add('hidden');
        el.innerHTML = data.lines.map(l => `<div class="line"><kbd>${esc(l.key)}</kbd>${esc(l.label)}</div>`).join('');
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
            S.hud = null; el.classList.add('hidden'); clearInterval(S.hudTimer); S.hudTimer = 0;
            return;
        }
        S.hud = Object.assign(S.hud || {}, data);
        if (data.remaining != null) S.hudEndAt = Date.now() + data.remaining * 1000;
        else if (data.remaining === undefined && !('remaining' in data)) { /* keep */ }
        renderHud();
        el.classList.remove('hidden');
        if (S.hudEndAt && !S.hudTimer) S.hudTimer = setInterval(renderHudTimer, 1000);
    }

    function renderHudTimer() {
        const t = document.getElementById('hud-time');
        if (!t || !S.hudEndAt) return;
        const left = (S.hudEndAt - Date.now()) / 1000;
        t.textContent = mmss(left);
        t.parentElement.classList.toggle('bad', left < 120);
    }

    function renderHud() {
        const h = S.hud;
        const pct = h.stages ? ((h.stage - 1) / h.stages) * 100 : 0;
        let meta = '';
        if (S.hudEndAt) meta += `<span>${Icons.svg('clock')}<b id="hud-time">--:--</b></span>`;
        if (h.distance) {
            const ok = h.distance.current >= h.distance.target;
            meta += `<span class="${ok ? '' : 'warn'}">${Icons.svg('map')}${h.distance.current}m / ${h.distance.target}m</span>`;
        }
        if (h.guards) meta += `<span class="${h.guards.alive > 0 ? 'bad' : ''}">${Icons.svg('crosshair')}${T('guards', 'Hostiles')} ${h.guards.alive}/${h.guards.total}</span>`;
        if (h.tracker) meta += `<span class="bad">${Icons.svg('siren')}${T('tracker', 'GPS tracker active')}</span>`;

        let list = '';
        if (S.hudExpanded && h.objectives && h.objectives.length) {
            list = `<div class="hud-list">${h.objectives.map(o => `
                <div class="hud-obj ${o.done ? 'done' : ''} ${o.optional ? 'optional' : ''}">
                    <span class="box"></span><span>${esc(o.label)}</span>${o.total > 1 || o.optional ? `<span class="count">${o.count}/${o.total}</span>` : ''}
                </div>`).join('')}</div>`;
        }
        let crew = '';
        if (S.hudExpanded && h.members && h.members.length > 1) {
            crew = `<div class="hud-crew">${h.members.map(m => `<span class="m ${m.leader ? 'lead' : ''}">${Icons.avatar(m.avatar, 18)}${esc(m.nickname)}</span>`).join('')}</div>`;
        }
        const noise = S.noise != null ? `<div class="noise"><div class="noise-top"><span>${T('noise', 'Noise')}</span><span>${S.noise}%</span></div><div class="noise-track"><div class="noise-fill" style="width:${S.noise}%"></div></div></div>` : '';

        $('hud').innerHTML = `
            <div class="hud-head">
                <span class="hud-icon">${Icons.svg(h.icon || 'mask')}</span>
                <div><div class="hud-title">${esc(h.title)}</div><div class="hud-sub">${esc(h.location || '')}</div></div>
                <span class="hud-stage">${h.stage}/${h.stages}</span>
            </div>
            <div class="hud-bar"><div style="width:${pct}%"></div></div>
            <div class="hud-task">${esc(h.task)}</div>
            ${meta ? `<div class="hud-meta">${meta}</div>` : ''}
            ${noise}${list}${crew}
            <div class="hud-hint"><kbd>${esc((S.ui && S.ui.hud && S.ui.hud.expandKey) || 'B')}</kbd>${T('hud_expand', 'expand')}</div>`;
        renderHudTimer();
    }

    /* ================================================================ drone / delivery / invite / result */
    function drone(d) {
        const el = $('drone');
        if (!d || !d.show) { el.classList.add('hidden'); el.innerHTML = ''; return; }
        if (el.classList.contains('hidden') || !el.innerHTML) {
            el.innerHTML = `<div class="corner tl"></div><div class="corner tr"></div><div class="corner bl"></div><div class="corner br"></div>
                <div class="readout" id="dr-read"></div><div class="rec">${T('drone_title', 'Recon drone')}</div>
                <div class="cross" id="dr-cross">${Icons.svg('crosshair')}</div><div class="drop hidden" id="dr-drop">${T('drone_in_zone', 'Press G to drop')}</div>
                <div class="range"><div id="dr-range"></div></div><div class="keys">${T('drone_keys', '')}</div>`;
            el.classList.remove('hidden');
        }
        if (d.altitude != null) {
            $('dr-read').innerHTML = `<span>${T('drone_alt', 'ALT')} <b>${d.altitude}m</b></span><span>${T('drone_range', 'RANGE')} <b>${d.distance}/${d.range}m</b></span>${d.zones ? `<span>${T('drone_targets', 'TARGETS')} <b>${d.remaining}/${d.zones}</b></span>` : ''}`;
            $('dr-range').style.width = Math.min(100, d.distance / d.range * 100) + '%';
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
            el.innerHTML = `${Icons.svg('cart')}${T('delivery_eta', 'Arriving in')} <b>${mmss(left)}</b>`;
            if (left <= 0) clearInterval(deliveryTimer);
        };
        draw();
        el.classList.remove('hidden');
        deliveryTimer = setInterval(draw, 1000);
    }

    function invite(d) {
        const el = $('invite');
        if (!d) { el.classList.add('hidden'); return; }
        el.innerHTML = `
            <div class="row">${Icons.avatar(d.avatar, 44)}<div><h3>${T('invite_title', 'Crew invite')}</h3><p><b>${esc(d.nickname)}</b> (LVL ${d.level}) ${T('invite_text', 'wants you on their crew.')}</p></div></div>
            <div class="actions">
                <button class="btn primary" data-act="accept"><kbd>Y</kbd>${T('accept', 'Accept')}</button>
                <button class="btn" data-act="decline"><kbd>N</kbd>${T('decline', 'Decline')}</button>
            </div>
            <div class="timer"><div style="animation-duration:${d.timeout}s"></div></div>`;
        el.querySelectorAll('[data-act]').forEach(b => b.onclick = async () => {
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
        el.className = 'result ' + (r.success ? '' : 'failed');
        el.innerHTML = `<div class="result-card">
            <h2>${r.success ? T('result_success', 'Heist complete') : T('result_failed', 'Heist failed')}</h2>
            <div class="sub">${esc(r.label)}${!r.success && reason ? ' · ' + esc(reason) : ''}</div>
            <div class="result-stats">
                <div><b>${mmss(r.duration || 0)}</b><span>${T('result_time', 'Time')}</span></div>
                <div><b>+${r.xp || 0}</b><span>${T('result_xp', 'Experience')}</span></div>
                <div><b class="money">${money(r.money)}</b><span>${T('result_cut', 'Your cut')}</span></div>
                <div><b class="money">${money(r.earned)}</b><span>${T('result_loot', 'Total take')}</span></div>
            </div>
            ${r.leveled ? `<div class="levelup">${T('result_levelup', 'Level up!')} LVL ${r.level}</div>` : ''}
        </div>`;
        resultTimer = setTimeout(() => el.classList.add('hidden'), 9000);
    }

    /* ================================================================ tablet */
    const TABS = [
        ['heists', 'target', 'tab_heists'], ['crew', 'users', 'tab_crew'], ['market', 'cart', 'tab_market'], ['fence', 'bag', 'tab_fence'],
        ['profile', 'user', 'tab_profile'], ['board', 'trophy', 'tab_board'], ['chat', 'chat', 'tab_chat'],
    ];

    function renderNav() {
        $('nav').innerHTML = TABS.map(([id, icon, key]) => `
            <button class="${S.tab === id ? 'active' : ''}" data-tab="${id}">${Icons.svg(icon)}<span>${T(key, id)}</span>${id === 'chat' && S.unreadChat ? `<span class="badge">${S.unreadChat}</span>` : ''}${id === 'crew' && S.crew && S.crew.members.length > 1 ? `<span class="badge" style="background:var(--accent)">${S.crew.members.length}</span>` : ''}</button>`).join('');
        $('nav').querySelectorAll('[data-tab]').forEach(b => b.onclick = () => go(b.dataset.tab));
    }

    function renderChip() {
        const p = S.profile;
        if (!p) return;
        const pct = p.levelNeed ? (p.levelXp / p.levelNeed * 100) : 100;
        $('profile-chip').innerHTML = `${Icons.avatar(p.avatar, 36)}<div class="who"><b>${esc(p.nickname)}</b><small>LVL ${p.level} · ${p.levelNeed ? `${p.levelXp}/${p.levelNeed} XP` : 'MAX'}</small><div class="xpbar"><div style="width:${pct}%"></div></div></div>`;
        $('profile-chip').onclick = () => go('profile');
    }

    function title(t, sub) { $('page-title').textContent = t; $('page-sub').textContent = sub || ''; }

    async function go(tab) {
        S.tab = tab;
        if (tab === 'chat') S.unreadChat = 0;
        renderNav();
        const page = $('page');
        page.innerHTML = '';
        if (tab === 'heists') { await loadHeists(); renderHeists(); }
        else if (tab === 'crew') renderCrew();
        else if (tab === 'market') { S.market = await post('market:data'); renderMarket(); }
        else if (tab === 'fence') { const r = await post('fence:data'); S.fence = r && r.data !== undefined ? r.data : r; renderFence(); }
        else if (tab === 'profile') { S.history = arr(await post('profile:history')); renderProfile(); }
        else if (tab === 'board') { S.board = arr(await post('profile:leaderboard')); renderBoard(); }
        else if (tab === 'chat') { S.chat = arr(await post('chat:history')); renderChat(); }
    }

    function arr(r) { const d = unwrap(r).data; return Array.isArray(d) ? d : []; }

    function unwrap(r) { return r && Object.prototype.hasOwnProperty.call(r, 'ok') ? r : { ok: !!r, data: r }; }

    /* ---------- heists */
    async function loadHeists() {
        const r = unwrap(await post('heists:list'));
        const d = r.data || {};
        S.heists = d.heists || [];
        S.police = d.police || 0;
        S.playerCooldown = d.playerCooldown || 0;
        $('police-count').textContent = S.police;
        if (!S.selected || !S.heists.find(h => h.id === S.selected)) S.selected = (S.heists.find(h => h.featured) || S.heists[0] || {}).id;
    }

    function renderHeists() {
        title(T('tab_heists', 'Heists'), `${S.heists.length} jobs available`);
        const q = S.search.toLowerCase();
        const list = S.heists.filter(h => (S.filter === 'all' || h.category === S.filter) && (!q || h.label.toLowerCase().includes(q)));
        const chips = ['all', 'small', 'medium', 'major'].map(f => `<button class="chip ${S.filter === f ? 'active' : ''}" data-f="${f}">${T(f, f)}</button>`).join('');
        const cards = list.map(h => `
            <button class="hcard ${S.selected === h.id ? 'active' : ''} ${h.locked ? 'locked' : ''}" data-id="${h.id}">
                <span class="bgico">${Icons.svg(h.icon)}</span>
                ${h.locked ? `<span class="lockico">${Icons.svg('lock')}</span>` : ''}
                <span class="hico">${Icons.svg(h.icon)}</span>
                <h4>${esc(h.label)}</h4>
                <div class="meta">
                    <span class="tag ${h.category}">${T(h.category, h.category)}</span>
                    ${h.featured ? `<span class="tag feat">${Icons.svg('star')} ${T('featured', 'Featured')}</span>` : ''}
                    ${h.cooldown > 0 ? `<span class="tag cd">${Icons.svg('clock')} ${Math.ceil(h.cooldown / 60)}m</span>` : ''}
                    ${h.running > 0 ? `<span class="tag cd">${h.running}/${h.simultaneous} LIVE</span>` : ''}
                </div>
            </button>`).join('');

        $('page').innerHTML = `
            <div class="heists">
                <div class="heists-left">
                    <div class="heists-tools"><input class="input" id="hsearch" placeholder="${T('search', 'Search...')}" value="${esc(S.search)}"/><div class="chips">${chips}</div></div>
                    <div class="heist-grid scroll">${cards || `<div class="empty">No heists match.</div>`}</div>
                </div>
                <div class="card detail" id="hdetail"></div>
            </div>`;
        $('hsearch').oninput = (e) => { S.search = e.target.value; renderHeistsKeepFocus(); };
        $('page').querySelectorAll('[data-f]').forEach(b => b.onclick = () => { S.filter = b.dataset.f; renderHeists(); });
        $('page').querySelectorAll('[data-id]').forEach(b => b.onclick = () => { S.selected = b.dataset.id; renderHeists(); });
        renderDetail();
    }

    function renderHeistsKeepFocus() {
        const pos = $('hsearch').selectionStart;
        renderHeists();
        const i = $('hsearch'); i.focus(); i.setSelectionRange(pos, pos);
    }

    function renderDetail() {
        const el = $('hdetail');
        const crew = S.crew;
        const active = crew && crew.heist;
        const isLeader = crew && crew.leader === S.serverId;
        if (active) {
            el.innerHTML = `
                <div class="active-heist">${Icons.svg('bolt')}<div><b>${esc(active.label)}</b><small>${esc(active.task || '')} · ${active.stage}/${active.stages}</small></div></div>
                <p class="desc">${T('running', 'In progress')} - follow the objectives on your HUD.</p>
                <div class="grow"></div>
                ${isLeader ? `<button class="btn danger" id="hstop">${Icons.svg('x')} ${T('stop', 'Abort heist')}</button>` : ''}`;
            const stop = $('hstop');
            if (stop) stop.onclick = async () => { const r = unwrap(await post('heist:stop')); if (!r.ok && r.data) notify({ text: r.data, kind: 'error' }); };
            return;
        }
        const h = S.heists.find(x => x.id === S.selected);
        if (!h) { el.innerHTML = `<div class="empty">Pick a heist.</div>`; return; }
        const cash = h.money ? `${money(h.money[0])}-${money(h.money[1]).slice(1)}` : '-';
        const reasons = [];
        if (h.locked) reasons.push(`${T('locked', 'Locked')} - LVL ${h.level}`);
        if (h.cooldown > 0) reasons.push(`${T('on_cooldown', 'On cooldown')} ${Math.ceil(h.cooldown / 60)}m`);
        if (S.police < h.police) reasons.push(`${T('police', 'Police')} ${S.police}/${h.police}`);
        if (!isLeader) reasons.push(T('leader', 'Leader') + ' only');
        el.innerHTML = `
            <div class="detail-head"><div class="big">${Icons.svg(h.icon)}</div><div><h2>${esc(h.label)}</h2><span class="tag ${h.category}">${T(h.category, h.category)}</span> ${h.featured ? `<span class="tag feat">x${(S.featuredBonus && S.featuredBonus.money) || 1} ${T('featured', 'Featured')}</span>` : ''}</div></div>
            <div class="grow">
                <p class="desc">${esc(h.description)}</p>
                <div class="stats">
                    <div class="stat"><b>${h.level}</b><span>${T('level', 'LVL')}</span></div>
                    <div class="stat"><b>${h.police}</b><span>${T('police', 'Police')}</span></div>
                    <div class="stat"><b>${h.members.min}-${h.members.max}</b><span>${T('crew', 'Crew')}</span></div>
                    <div class="stat"><b>${h.timeLimit ? h.timeLimit + 'm' : '∞'}</b><span>${T('time_limit', 'Time limit')}</span></div>
                    <div class="stat"><b>+${h.xp}</b><span>${T('xp', 'XP')}</span></div>
                    <div class="stat"><b class="money">${cash}</b><span>${T('reward', 'Reward')}</span></div>
                </div>
                ${h.requiredItems.length ? `<div><div class="label">${T('required_items', 'Required items')}</div><div class="req" style="margin-top:8px">${h.requiredItems.map(i => `<span class="chip">${esc(i.label)}${i.count > 1 ? ' x' + i.count : ''}</span>`).join('')}</div></div>` : ''}
                <div><div class="label">${T('briefing', 'Briefing')}</div><ol class="brief" style="margin-top:8px">${h.briefing.map(b => `<li>${esc(b)}</li>`).join('')}</ol></div>
            </div>
            ${reasons.length ? `<div class="label" style="color:var(--warning)">${reasons.map(esc).join(' · ')}</div>` : ''}
            <button class="btn primary" id="hstart" ${h.locked || !isLeader ? 'disabled' : ''}>${Icons.svg('bolt')} ${T('start', 'Start heist')}</button>`;
        $('hstart').onclick = async () => {
            $('hstart').disabled = true;
            const r = unwrap(await post('heist:start', { id: h.id }));
            if (!r.ok) { notify({ text: r.data || 'Could not start', kind: 'error' }); $('hstart').disabled = false; }
        };
    }

    /* ---------- crew */
    function renderCrew() {
        const c = S.crew;
        title(T('tab_crew', 'Crew'), c ? `${c.members.length}/8` : '');
        if (!c) { $('page').innerHTML = '<div class="empty">...</div>'; return; }
        const isLeader = c.leader === S.serverId;
        const me = c.members.find(m => m.source === S.serverId);
        const members = c.members.map(m => `
            <div class="member">
                ${Icons.avatar(m.avatar, 44)}
                <div class="who"><b>${esc(m.nickname)} ${m.leader ? `<span class="tag feat">${T('leader', 'Leader')}</span>` : ''} ${m.source === S.serverId ? `<span class="tag cd">${T('you', 'You')}</span>` : ''}</b><small>LVL ${m.level} · ID ${m.source}</small></div>
                <span class="state ${m.ready ? 'on' : 'off'}">${m.ready ? T('ready', 'Ready') : T('not_ready', 'Not ready')}</span>
                ${isLeader && m.source !== S.serverId ? `<button class="btn small" data-promote="${m.source}">${T('promote', 'Leader')}</button><button class="btn small danger" data-kick="${m.source}">${T('kick', 'Kick')}</button>` : ''}
            </div>`).join('');
        $('page').innerHTML = `
            <div class="two">
                <div class="list scroll">${members}</div>
                <div class="card panel">
                    <h3>${T('invite', 'Invite')}</h3>
                    <p>Invite players by their server ID. They get a popup and can accept with <kbd>Y</kbd>.</p>
                    <div class="row"><input class="input" id="inv-id" placeholder="${T('invite_placeholder', 'Server ID')}" ${isLeader ? '' : 'disabled'}/><button class="btn primary" id="inv-btn" ${isLeader ? '' : 'disabled'}>${Icons.svg('plus')}</button></div>
                    <div style="flex:1"></div>
                    ${!isLeader && me ? `<button class="btn ${me.ready ? '' : 'primary'}" id="ready-btn">${Icons.svg('check')} ${me.ready ? T('not_ready', 'Not ready') : T('ready', 'Ready')}</button>` : ''}
                    ${c.members.length > 1 ? `<button class="btn danger" id="leave-btn">${T('leave', 'Leave crew')}</button>` : ''}
                </div>
            </div>`;
        const act = async (name, data) => { const r = unwrap(await post(name, data)); if (r.data && typeof r.data === 'string') notify({ text: r.data, kind: r.ok ? 'success' : 'error' }); return r; };
        const inv = $('inv-btn');
        if (inv) inv.onclick = async () => { const v = $('inv-id').value.trim(); if (!v) return; await act('crew:invite', { target: v }); $('inv-id').value = ''; };
        const ready = $('ready-btn');
        if (ready) ready.onclick = () => act('crew:ready', { state: !me.ready });
        const leave = $('leave-btn');
        if (leave) leave.onclick = () => act('crew:leave');
        $('page').querySelectorAll('[data-kick]').forEach(b => b.onclick = () => act('crew:kick', { target: b.dataset.kick }));
        $('page').querySelectorAll('[data-promote]').forEach(b => b.onclick = () => act('crew:promote', { target: b.dataset.promote }));
    }

    /* ---------- market */
    function renderMarket() {
        const m = unwrap(S.market).data || {};
        title(T('tab_market', 'Market'), T('delivery', 'Drone delivery'));
        if (!m.enabled) { $('page').innerHTML = `<div class="empty">Market closed.</div>`; return; }
        const level = S.profile ? S.profile.level : 1;
        const cats = [['all', T('all', 'All')]].concat((m.categories || []).map(c => [c.id, c.label]));
        const items = (m.items || []).filter(i => S.marketCat === 'all' || i.category === S.marketCat);
        const cartRows = Object.entries(S.cart).map(([name, qty]) => {
            const it = m.items.find(i => i.name === name);
            return `<div class="cart-row"><span>${esc(it.label)}</span><div class="qty"><button data-dec="${name}">${Icons.svg('minus')}</button><b>${qty}</b><button data-inc="${name}">${Icons.svg('plus')}</button></div><b class="money" style="min-width:70px;text-align:right">${money(it.price * qty)}</b></div>`;
        }).join('');
        const total = Object.entries(S.cart).reduce((a, [n, q]) => a + (m.items.find(i => i.name === n) || { price: 0 }).price * q, 0);
        $('page').innerHTML = `
            <div class="two">
                <div style="display:flex;flex-direction:column;gap:14px;min-height:0">
                    <div class="chips">${cats.map(([id, l]) => `<button class="chip ${S.marketCat === id ? 'active' : ''}" data-cat="${id}">${esc(l)}</button>`).join('')}</div>
                    <div class="market-grid scroll">${items.map(i => `
                        <div class="card mitem">
                            <div class="row" style="justify-content:space-between"><h4>${esc(i.label)}</h4>${level < (i.level || 1) ? `<span class="tag cd">${Icons.svg('lock')} LVL ${i.level}</span>` : ''}</div>
                            <small>${esc(i.used || '')}</small>
                            <div class="foot"><span class="price money">${money(i.price)}</span><button class="btn small primary" data-add="${i.name}" ${level < (i.level || 1) ? 'disabled' : ''}>${Icons.svg('plus')} ${T('add', 'Add')}</button></div>
                        </div>`).join('')}</div>
                </div>
                <div class="card panel">
                    <h3>${Icons.svg('cart')} ${T('cart', 'Cart')}</h3>
                    ${m.order ? `<p>${T('delivery', 'Drone delivery')}: ${mmss(m.order.remaining)} (${money(m.order.total)})</p>` : ''}
                    <div class="list scroll" style="flex:1">${cartRows || `<div class="empty">Empty</div>`}</div>
                    <div class="total"><span>${T('total', 'Total')}</span><span class="money">${money(total)}</span></div>
                    <div class="row"><button class="btn primary" style="flex:1;justify-content:center" data-pay="cash" ${!total || m.order ? 'disabled' : ''}>${T('pay_cash', 'Pay cash')}</button><button class="btn" style="flex:1;justify-content:center" data-pay="bank" ${!total || m.order ? 'disabled' : ''}>${T('pay_bank', 'Pay bank')}</button></div>
                </div>
            </div>`;
        const max = m.maxPerItem || 10;
        $('page').querySelectorAll('[data-cat]').forEach(b => b.onclick = () => { S.marketCat = b.dataset.cat; renderMarket(); });
        $('page').querySelectorAll('[data-add]').forEach(b => b.onclick = () => { S.cart[b.dataset.add] = Math.min(max, (S.cart[b.dataset.add] || 0) + 1); renderMarket(); });
        $('page').querySelectorAll('[data-inc]').forEach(b => b.onclick = () => { S.cart[b.dataset.inc] = Math.min(max, S.cart[b.dataset.inc] + 1); renderMarket(); });
        $('page').querySelectorAll('[data-dec]').forEach(b => b.onclick = () => { S.cart[b.dataset.dec]--; if (S.cart[b.dataset.dec] <= 0) delete S.cart[b.dataset.dec]; renderMarket(); });
        $('page').querySelectorAll('[data-pay]').forEach(b => b.onclick = async () => {
            const cart = Object.entries(S.cart).map(([name, amount]) => ({ name, amount }));
            const r = unwrap(await post('market:buy', { cart, account: b.dataset.pay }));
            if (r.ok) { S.cart = {}; notify({ text: r.data && r.data.instant ? 'Delivered.' : `${T('delivery', 'Drone delivery')} - ${r.data.seconds}s`, kind: 'success' }); S.market = await post('market:data'); renderMarket(); }
            else notify({ text: r.data || 'Failed', kind: 'error' });
        });
    }

    /* ---------- fence */
    function renderFence() {
        const f = S.fence;
        title(T('tab_fence', 'Fence'), f && !f.near ? T('fence_far', 'Visit a fence to sell.') : '');
        if (!f) { $('page').innerHTML = `<div class="empty">Fence closed.</div>`; return; }
        $('page').innerHTML = `
            <div class="fence-head label"><span>Item</span><span>Price</span><span>${T('owned', 'Owned')}</span><span>Qty</span><span></span></div>
            <div class="list scroll" style="height:calc(100% - 24px)">${f.items.map(i => `
                <div class="fence-row">
                    <b>${esc(i.label)}</b><span class="money">${money(i.price)}</span><span>${i.owned}</span>
                    <input class="input" type="number" min="1" max="${i.owned}" value="${Math.max(1, Math.min(1, i.owned))}" id="q-${i.name}" ${i.owned ? '' : 'disabled'}/>
                    <div class="row"><button class="btn small primary" data-sell="${i.name}" ${i.owned && f.near ? '' : 'disabled'}>${T('sell', 'Sell')}</button><button class="btn small" data-all="${i.name}" ${i.owned && f.near ? '' : 'disabled'}>${T('sell_all', 'All')}</button></div>
                </div>`).join('')}</div>`;
        const sell = async (name, amount) => {
            const r = unwrap(await post('fence:sell', { name, amount }));
            notify({ text: r.data || (r.ok ? 'Sold' : 'Failed'), kind: r.ok ? 'success' : 'error' });
            const d = await post('fence:data'); S.fence = d && d.data !== undefined ? d.data : d; renderFence();
        };
        $('page').querySelectorAll('[data-sell]').forEach(b => b.onclick = () => sell(b.dataset.sell, Number($('q-' + b.dataset.sell).value) || 1));
        $('page').querySelectorAll('[data-all]').forEach(b => b.onclick = () => sell(b.dataset.all, f.items.find(i => i.name === b.dataset.all).owned));
    }

    /* ---------- profile */
    function renderProfile() {
        const p = S.profile;
        title(T('tab_profile', 'Profile'));
        if (!p) return;
        const pct = p.levelNeed ? (p.levelXp / p.levelNeed * 100) : 100;
        const avatars = Array.from({ length: Icons.count }, (_, n) => `<button class="${p.avatar === n + 1 ? 'sel' : ''}" data-av="${n + 1}">${Icons.avatar(n + 1, 34)}</button>`).join('');
        const hist = (S.history || []).map(h => `
            <div class="hist"><span class="${h.success ? 'ok' : 'bad'}">${Icons.svg(h.success ? 'check' : 'x')}</span><b>${esc(h.label)}</b><span>${esc(h.location || '')}</span><span>${mmss(h.duration)}</span><span class="money">${money(h.payout)}</span></div>`).join('');
        $('page').innerHTML = `
            <div class="profile">
                <div class="card pcard scroll">
                    <div class="lvl-ring">${Icons.avatar(p.avatar, 96)}<span class="lv">LVL ${p.level}</span></div>
                    <h2>${esc(p.nickname)}</h2>
                    <div style="width:100%"><div class="xpbar" style="height:6px"><div style="width:${pct}%"></div></div><small style="color:var(--muted)">${p.levelNeed ? `${p.levelXp} / ${p.levelNeed} XP` : 'MAX LEVEL'}</small></div>
                    <div style="width:100%;text-align:left"><div class="label">${T('nickname', 'Nickname')}</div><div class="row" style="margin-top:6px"><input class="input" id="nick" maxlength="20" value="${esc(p.nickname)}"/><button class="btn primary" id="nick-save">${T('save', 'Save')}</button></div></div>
                    <div style="width:100%;text-align:left"><div class="label">${T('avatar', 'Avatar')}</div><div class="avatar-pick" style="margin-top:8px">${avatars}</div></div>
                </div>
                <div style="display:flex;flex-direction:column;gap:14px;min-height:0">
                    <div class="kpis">
                        <div class="card kpi"><b>${p.completed}</b><span>${T('completed', 'Completed')}</span></div>
                        <div class="card kpi"><b>${p.failed}</b><span>${T('failed', 'Failed')}</span></div>
                        <div class="card kpi"><b class="money">${money(p.earned)}</b><span>${T('earned', 'Earned')}</span></div>
                        <div class="card kpi"><b>${p.xp.toLocaleString('en-US')}</b><span>${T('xp', 'XP')}</span></div>
                    </div>
                    <div class="card panel" style="flex-direction:row;gap:24px;align-items:center">
                        <div class="label">${T('perks', 'Level perks')}</div>
                        <span>${T('loot_bonus', 'Loot bonus')} <b class="money">+${Math.round((p.perks.loot - 1) * 100)}%</b></span>
                        <span>${T('speed_bonus', 'Action speed')} <b style="color:var(--accent2)">+${Math.round((p.perks.speed - 1) * 100)}%</b></span>
                    </div>
                    <div class="label">${T('history', 'Recent jobs')}</div>
                    <div class="list scroll" style="flex:1">${hist || `<div class="empty">${T('no_history', 'No jobs yet.')}</div>`}</div>
                </div>
            </div>`;
        $('nick-save').onclick = async () => {
            const r = unwrap(await post('profile:nickname', { nickname: $('nick').value }));
            if (r.ok && r.data && typeof r.data === 'object') { S.profile = r.data; renderChip(); renderProfile(); notify({ text: 'Saved', kind: 'success' }); }
            else notify({ text: (r.data) || 'Failed', kind: 'error' });
        };
        $('page').querySelectorAll('[data-av]').forEach(b => b.onclick = async () => {
            const r = unwrap(await post('profile:avatar', { avatar: Number(b.dataset.av) }));
            if (r.ok && r.data) { S.profile = r.data; renderChip(); renderProfile(); }
        });
    }

    /* ---------- leaderboard */
    function renderBoard() {
        title(T('tab_board', 'Leaderboard'), 'Top players by experience');
        $('page').innerHTML = `<div class="list scroll" style="height:100%">${(S.board || []).map((r, i) => `
            <div class="board-row"><span class="rank">${i + 1}</span>${Icons.avatar(r.avatar, 36)}<b>${esc(r.nickname)}</b><span>LVL ${r.level}</span><span>${r.completed} jobs</span><span class="money">${money(r.earned)}</span></div>`).join('') || `<div class="empty">Nobody yet.</div>`}</div>`;
    }

    /* ---------- chat */
    function msgHtml(m) {
        const me = m.source === S.serverId;
        const time = m.time ? new Date(m.time * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
        return `<div class="msg ${me ? 'me' : ''}">${Icons.avatar(m.avatar, 34)}<div class="body"><div class="name">${esc(m.nickname)} <small>LVL ${m.level} · ${time}</small></div><div class="text">${esc(m.text)}</div></div></div>`;
    }

    function renderChat() {
        title(T('tab_chat', 'Underground'), 'Everyone with a tablet open can see this');
        $('page').innerHTML = `
            <div class="chat">
                <div class="card chat-log scroll" id="log">${(S.chat || []).map(msgHtml).join('') || `<div class="empty">Quiet in here.</div>`}</div>
                <div class="row"><input class="input" id="chat-in" maxlength="180" placeholder="${T('chat_placeholder', 'Say something...')}"/><button class="btn primary" id="chat-send">${Icons.svg('send')}</button></div>
            </div>`;
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
        if (S.tab === 'chat' && !$('tablet').classList.contains('hidden')) {
            const log = $('log');
            if (log) {
                if (log.querySelector('.empty')) log.innerHTML = '';
                log.insertAdjacentHTML('beforeend', msgHtml(m));
                log.scrollTop = log.scrollHeight;
            }
        } else { S.unreadChat++; renderNav(); }
    }

    /* ---------- open / close */
    function openMenu(d) {
        S.profile = d.profile; S.crew = d.crew; S.featured = d.featured; S.featuredBonus = d.featuredBonus;
        S.levels = d.levels || S.levels; S.serverId = d.serverId;
        $('tablet').classList.remove('hidden');
        renderChip();
        go(d.tab || S.tab || 'heists');
        if ((d.tab || S.tab) !== 'heists') loadHeists();
    }

    function closeMenu() {
        $('tablet').classList.add('hidden');
        $('page').innerHTML = '';
    }

    function crewUpdate(c) {
        S.crew = c;
        if (S.profile && c) {
            const me = c.members.find(m => m.source === S.serverId);
            if (me) { S.profile.nickname = me.nickname; S.profile.avatar = me.avatar; }
        }
        if ($('tablet').classList.contains('hidden')) return;
        renderNav();
        if (S.tab === 'crew') renderCrew();
        if (S.tab === 'heists') renderDetail();
    }

    $('close-btn').onclick = () => post('menu:close');

    window.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if (window.Minigames && Minigames.active()) { Minigames.cancel(); return; }
        if (!$('tablet').classList.contains('hidden')) post('menu:close');
    });

    /* ================================================================ message router */
    const handlers = {
        init(d) {
            S.ui = d.ui; S.levels = d.levels || [];
            window.UIStrings = d.strings || {};
            applyTheme(d.ui); translate();
        },
        notify, textui, progress, hud, drone, delivery, invite, result,
        hudToggle() { S.hudExpanded = !S.hudExpanded; if (S.hud) renderHud(); },
        noise(d) { S.noise = d ? d.value : null; if (S.hud) renderHud(); },
        minigame(d) {
            Minigames.start(d.type, d.difficulty, (ok) => post('minigame', { success: ok }));
        },
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

    /* ================================================================ browser preview (not in FiveM) */
    if (!IN_GAME) {
        const s = document.createElement('script');
        s.src = 'preview.js';
        document.body.appendChild(s);
    }
})();
