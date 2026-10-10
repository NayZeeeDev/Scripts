/* ═══════════════════════════════════════════════════════════
   nayzeee drug empire - NUI
   HUD · toasts · unknown text · dialogue · first person overlay · panels · give · phone
   No timers run while the page is idle.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;

async function post(name, data = {}) {
    if (!RES) return window.Mock ? window.Mock.handle(name, data) : null;
    try {
        const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
        const t = await r.text();
        return t ? JSON.parse(t) : null;
    } catch (e) { return null; }
}

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => '$' + Math.round(Number(n) || 0).toLocaleString('en-US');
const arr = (v) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const I = (n, c) => window.Icons.svg(n, c);

const CFG = { effects: {}, quality: [], standards: [], items: {}, ingredients: {}, drugs: {}, maxEffects: 8, ui: {} };

/* ─────────────── theme ─────────────── */
function hexRgb(hex) { const n = parseInt(String(hex || '#08afa2').replace('#', ''), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function mix(hex, to, k) { const a = hexRgb(hex), b = hexRgb(to); return '#' + a.map((v, i) => Math.round(v + (b[i] - v) * k).toString(16).padStart(2, '0')).join(''); }
function applyTheme(t) {
    if (!t) return;
    const st = document.documentElement.style;
    const set = (name, hex) => {
        if (!hex) return;
        const [r, g, b] = hexRgb(hex);
        st.setProperty(`--${name}`, hex); st.setProperty(`--${name}-rgb`, `${r}, ${g}, ${b}`);
    };
    set('teal', t.accent); set('red', t.danger); set('amber', t.warning); set('green', t.success);
    if (t.accent) { st.setProperty('--teal-hi', t.accent2 || mix(t.accent, '#ffffff', 0.2)); st.setProperty('--teal-lo', mix(t.accent, '#000000', 0.3)); }
    if (t.danger) st.setProperty('--red-lo', mix(t.danger, '#000000', 0.2));
    if (t.font) st.setProperty('--font', t.font);
}

/* ─────────────── product helpers (mirror of shared/mixing.lua) ─────────────── */
function effLabel(e) { return (CFG.effects[e] && CFG.effects[e].label) || e; }
function effColor(e) { return (CFG.effects[e] && CFG.effects[e].color) || '#9ea5aa'; }
function chips(list) { return `<div class="chips">${arr(list).map((e) => `<span class="chip" style="--c:${effColor(e)}">${esc(effLabel(e))}</span>`).join('') || '<span class="chip off">No effects</span>'}</div>`; }
function qualityOf(q) { return arr(CFG.quality).find((x) => x.id === q) || { label: 'Standard', color: '#9ea5aa' }; }
function mixApply(effects, ing) {
    const def = CFG.ingredients[ing]; if (!def) return effects;
    const have = new Set(effects), out = [];
    for (const e of effects) {
        const to = def.rules[e];
        if (to && !have.has(to)) { have.delete(e); have.add(to); out.push(to); } else out.push(e);
    }
    if (!have.has(def.effect) && out.length < CFG.maxEffects) out.push(def.effect);
    return out;
}
function valueOf(base, effects) {
    const d = CFG.drugs[base]; if (!d) return 0;
    let m = 0; for (const e of effects) m += (CFG.effects[e] && CFG.effects[e].mult) || 0;
    return Math.round(d.price * (1 + m));
}
const KIND_ICON = { weed: 'leaf', meth: 'crystal', shroom: 'shroom', coke: 'powder' };
function kindOf(base) { return (CFG.drugs[base] && CFG.drugs[base].kind) || 'weed'; }

/* ─────────────── toasts ─────────────── */
const TOAST_ICON = { info: 'msg', success: 'check', error: 'x', warning: 'siren' };
function notify({ text, kind = 'info', title, duration = 5000 }) {
    const host = $('#notify');
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.style.setProperty('--d', duration + 'ms');
    el.innerHTML = `<div class="ti">${I(TOAST_ICON[kind] || 'msg')}</div><div>${title ? `<b>${esc(title)}</b>` : ''}<p>${esc(text)}</p></div>`;
    host.appendChild(el);
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, duration);
    while (host.children.length > 5) host.firstChild.remove();
}

let smsTimer;
function sms(d) {
    const el = $('#sms');
    el.innerHTML = `<div class="ap">${I('msg')}</div><div><b>${esc(d.from)} <small>now</small></b><p>${esc(d.text)}</p></div>`;
    el.classList.remove('hidden');
    clearTimeout(smsTimer);
    smsTimer = setTimeout(() => el.classList.add('hidden'), 6500);
}

/* ─────────────── HUD ─────────────── */
let hudData = null, hudTimer = null;
function fmtLeft(s) { s = Math.max(0, Math.floor(s)); const m = Math.floor(s / 60); return m ? `${m}m ${String(s % 60).padStart(2, '0')}s` : `${s}s`; }
function renderHud() {
    const el = $('#hud');
    if (!hudData) { el.classList.add('hidden'); clearInterval(hudTimer); hudTimer = null; return; }
    const now = Date.now() / 1000 + (hudData.skew || 0);
    const q = hudData.quest;
    let html = '';
    if (q) html += `<div class="hud-item"><div class="hud-ic">${I('star')}</div><div><b>${esc(q.title)}</b><p>${esc(q.text)}${q.need ? `<i>${q.n || 0}/${q.need}</i>` : ''}</p></div></div>`;
    for (const d of arr(hudData.deals)) {
        let left = '';
        if (d.exp) { const s = d.exp - now; left = `<small class="${s < 120 ? 'late' : ''}">${s > 0 ? fmtLeft(s) + ' left' : 'Late!'}</small>`; }
        html += `<div class="hud-item"><div class="hud-ic ${d.sample ? 'sample' : 'deal'}">${I(d.sample ? 'leaf' : 'handshake')}</div><div><b>${esc(d.title)}</b><p>${esc(d.text)}</p>${left}</div></div>`;
    }
    el.innerHTML = html;
    el.classList.remove('hidden');
    const needsTick = arr(hudData.deals).some((d) => d.exp);
    if (needsTick && !hudTimer) hudTimer = setInterval(renderHud, 1000);
    if (!needsTick && hudTimer) { clearInterval(hudTimer); hudTimer = null; }
}

/* ─────────────── unknown text ─────────────── */
function text(d) {
    const el = $('#text');
    if (!d) { el.classList.add('hidden'); el.innerHTML = ''; return; }
    el.innerHTML = `<div class="card"><div class="card-in">
        <div class="card-bar"><div class="tile mute">${I('unknown')}</div><div class="t"><b>${esc(d.from)}</b><span>Unknown number · text message</span></div></div>
        <div class="card-body"><div class="bubbles">${arr(d.lines).map((l) => `<div class="bub">${esc(l)}</div>`).join('')}</div>
            <div class="pin"><div class="tile">${I('pin')}</div><div><b>Shared a location</b>Somewhere out of town</div></div></div>
        <div class="timer"><i style="animation-duration:${d.timeout || 40}s"></i></div>
        <div class="card-foot"><div class="grow"><span><span class="key teal">Y</span> ${esc(d.yes || 'Go')}</span><span><span class="key">N</span> ${esc(d.no || 'Ignore')}</span></div></div>
    </div></div>`;
    el.classList.remove('hidden');
}

/* ─────────────── textui / progress ─────────────── */
function textui(d) {
    const el = $('#textui');
    if (!d) { el.classList.add('hidden'); return; }
    el.innerHTML = arr(d.lines).map((l) => `<div class="line"><span class="key">${esc(l.key)}</span>${esc(l.label)}</div>`).join('');
    el.classList.remove('hidden');
}
let progT;
function progress(d) {
    const el = $('#progress'), fill = $('#progress-fill');
    clearInterval(progT);
    if (!d) { el.classList.add('hidden'); return; }
    $('#progress-text').textContent = d.label;
    fill.style.transition = 'none'; fill.style.width = '0%';
    el.classList.remove('hidden');
    const start = Date.now();
    requestAnimationFrame(() => { fill.style.transition = `width ${d.duration}ms linear`; fill.style.width = '100%'; });
    progT = setInterval(() => {
        const k = clamp((Date.now() - start) / d.duration, 0, 1);
        $('#progress-pct').textContent = Math.round(k * 100) + '%';
        if (k >= 1) clearInterval(progT);
    }, 100);
}

/* ─────────────── first person overlay ─────────────── */
let ixKeys = '';
function ix(d) {
    const el = $('#ix');
    if (!d) { el.classList.add('hidden'); el.innerHTML = ''; ixKeys = ''; return; }
    const tail = d.count ? ` <b>(${esc(d.count)})</b>` : (d.pct != null ? ` <b>(${d.pct}%)</b>` : '');
    const bar = d.pct != null ? `<div class="bar"><i style="width:${d.pct}%"></i></div>` : '';
    const keys = JSON.stringify(d.keys || []);
    if (keys !== ixKeys || !$('.ix-keys', el)) {
        ixKeys = keys;
        el.innerHTML = `<div class="ix-pill"></div><div class="ix-keys">${arr(d.keys).map((k) => `<div><span class="key">${esc(k.key)}</span>${esc(k.label)}</div>`).join('')}</div>`;
    }
    $('.ix-pill', el).innerHTML = `<span class="dot"></span>${esc(d.text)}${tail}${bar}`;
    el.classList.remove('hidden');
}

/* ─────────────── dialogue ─────────────── */
let dlgType = null, dlgChoices = [];
function dialogue(d) {
    const el = $('#dlg');
    clearInterval(dlgType);
    if (!d) { el.classList.add('hidden'); el.innerHTML = ''; return; }
    dlgChoices = arr(d.choices);
    el.innerHTML = `<div class="card"><div class="card-in">
        <div class="card-bar"><div class="mark sm"></div><div class="t"><b>${esc(d.name)}</b><span>${esc(d.role || '')}</span></div></div>
        <div class="card-body"><div class="line"></div><div class="opts"></div></div>
        <div class="card-foot"><div class="grow">${dlgChoices.length ? '<span><span class="key">1-4</span> Answer</span>' : '<span><span class="key teal">E</span> Continue</span>'}<span><span class="key">Esc</span> Leave</span></div></div>
    </div></div>`;
    el.classList.remove('hidden');
    const line = $('.line', el), opts = $('.opts', el);
    const full = String(d.text || '');
    let i = 0;
    const finish = () => {
        clearInterval(dlgType); dlgType = null;
        line.textContent = full;
        opts.innerHTML = dlgChoices.length
            ? dlgChoices.map((c, k) => `<button class="opt" data-i="${k + 1}"><span class="key">${k + 1}</span>${esc(c)}</button>`).join('')
            : `<button class="opt" data-i="0"><span class="key teal">E</span>Continue</button>`;
        $$('.opt', opts).forEach((b) => b.onclick = () => post('dialogue', { i: +b.dataset.i }));
    };
    line.innerHTML = '<span class="cursor"></span>';
    dlgType = setInterval(() => {
        i += 2;
        if (i >= full.length) return finish();
        line.innerHTML = esc(full.slice(0, i)) + '<span class="cursor"></span>';
    }, 18);
    el.dataset.finish = '1';
    el._finish = finish;
}

/* ─────────────── panels ─────────────── */
let panel = null; // { type, data, sel... }
function panelClose(result) { post('panel:done', result || {}); hidePanel(); }
function hidePanel() { $('#panel').classList.add('hidden'); $('#panel').innerHTML = ''; $('#give').classList.add('hidden'); $('#give').innerHTML = ''; panel = null; }

function shell(title, sub, body, foot, wide) {
    return `<div class="card pnl ${wide ? 'wide' : ''}"><div class="card-in">
        <div class="card-bar"><div class="mark sm"></div><div class="t"><b>${esc(title)}</b><span>${esc(sub || '')}</span></div><div class="end"><button class="x" data-close>${I('x')}</button></div></div>
        <div class="card-body">${body}</div>
        ${foot ? `<div class="card-foot">${foot}</div>` : ''}
    </div></div>`;
}

function mountPanel(html) {
    const el = $('#panel');
    el.innerHTML = html;
    el.classList.remove('hidden');
    $$('[data-close]', el).forEach((b) => b.onclick = () => post('close', { what: 'panel' }).then(hidePanel));
    return el;
}

function stackRow(s, on, extra = '') {
    const q = qualityOf(s.q);
    return `<button class="row ${on ? 'on' : ''}" data-k="${esc(s._k)}"><div class="tile" style="color:${(CFG.drugs[s.base] || {}).color || 'var(--teal)'}">${I(KIND_ICON[s.kind || kindOf(s.base)] || 'leaf')}</div>
        <div class="row-txt"><b>${esc(s.name)} <span class="chip" style="--c:${q.color}">${esc(q.label)}</span></b><span>${arr(s.effects).map(effLabel).join(', ') || 'No effects'}</span></div>
        <div class="end">${extra}x${s.n}</div></button>`;
}

function keyStacks(list) { return arr(list).map((s, i) => Object.assign(s, { _k: `${s.pid}|${s.q}|${i}` })); }

/* choose: { title, options: [{ item, label, n }] } */
function panelChoose(d) {
    const el = mountPanel(shell(d.title || 'Pick one', 'What do you want to use?',
        `<div class="list">${arr(d.options).map((o) => `<button class="row" data-item="${esc(o.item)}"><div class="tile">${I('box')}</div><div class="row-txt"><b>${esc(o.label)}</b></div><div class="end">${o.n != null ? 'x' + o.n : ''}</div></button>`).join('')}</div>`));
    $$('[data-item]', el).forEach((b) => b.onclick = () => panelClose({ item: b.dataset.item }));
}

/* place: { items: [{ item, label, icon, n, locked, rank }] } */
function panelPlace(d) {
    const el = mountPanel(shell('Set up equipment', 'Pick something to place in the RV',
        `<div class="eq">${arr(d.items).map((o) => `<button data-item="${esc(o.item)}" ${o.locked ? 'disabled' : ''}><div class="tile">${I(o.icon || 'box')}</div>${esc(o.label)}<small>${o.locked ? 'Unlocks at ' + esc(o.rank) : 'x' + o.n}</small></button>`).join('')}</div>`,
        `<div class="grow"><span><span class="key">Scroll</span> Rotate</span><span><span class="key">E</span> Place</span></div>`));
    $$('[data-item]', el).forEach((b) => b.onclick = () => panelClose({ item: b.dataset.item }));
}

/* pack: { stacks, baggies, jars } */
function panelPack(d) {
    const stacks = keyStacks(d.stacks);
    panel.sel = panel.sel || (stacks[0] && stacks[0]._k);
    panel.kind = panel.kind || 'baggie';
    panel.n = panel.n || 1;
    const s = stacks.find((x) => x._k === panel.sel);
    const per = panel.kind === 'jar' ? 5 : 1;
    const packs = panel.kind === 'jar' ? d.jars : d.baggies;
    const max = s ? Math.max(0, Math.min(20, Math.floor(s.n / per), packs)) : 0;
    panel.n = clamp(panel.n, max ? 1 : 0, max);
    const body = !stacks.length
        ? `<div class="empty">${I('leaf')}<b>Nothing to package</b><span>Harvest or cook something first. Loose product shows up here.</span></div>`
        : `<div class="pack-row">
            <div class="slot"><div class="box ${s ? 'fill' : ''}">${I(s ? KIND_ICON[s.kind] : 'leaf')}${s ? `<i>${s.n}x</i>` : ''}</div>Product</div>
            <div class="slot"><div class="box fill">${I(panel.kind === 'jar' ? 'beaker' : 'bag')}<i>${packs}x</i></div>Packaging</div>
            <div class="arrow"><span>PACKAGE</span><svg viewBox="0 0 18 26"><path d="M0 0l18 13L0 26z" fill="currentColor" opacity=".35"/></svg></div>
            <div class="slot"><div class="box">${I('box')}</div>Output</div>
          </div>
          <div class="sect-h">Product</div><div class="list">${stacks.map((x) => stackRow(x, x._k === panel.sel)).join('')}</div>
          <div class="sect-h" style="margin-top:14px">Packaging</div>
          <div class="between"><div class="seg"><button data-kind="baggie" class="${panel.kind === 'baggie' ? 'on' : ''}">Baggie · 1 unit (${d.baggies})</button><button data-kind="jar" class="${panel.kind === 'jar' ? 'on' : ''}" ${d.jars ? '' : 'disabled'}>Jar · 5 units (${d.jars})</button></div>
          <div class="qty"><button data-q="-1">−</button><b>${panel.n}</b><button data-q="1">+</button></div></div>`;
    const el = mountPanel(shell('Packaging Station', 'Bag it before you sell it', body,
        `<div class="grow muted">First one by hand, the rest pack themselves</div><button class="btn-teal" data-pack ${max ? '' : 'disabled'}>${I('box')}Pack</button>`));
    $$('[data-k]', el).forEach((b) => b.onclick = () => { panel.sel = b.dataset.k; panelPack(d); });
    $$('[data-kind]', el).forEach((b) => b.onclick = () => { panel.kind = b.dataset.kind; panelPack(d); });
    $$('[data-q]', el).forEach((b) => b.onclick = () => { panel.n += +b.dataset.q; panelPack(d); });
    const pk = $('[data-pack]', el);
    if (pk) pk.onclick = () => panelClose({ item: s.item, pid: s.pid, q: s.q, kind: panel.kind, n: panel.n });
}

/* mix: { stacks, ingredients, max } */
function panelMix(d) {
    const stacks = keyStacks(d.stacks);
    panel.sel = stacks.find((x) => x._k === panel.sel) ? panel.sel : (stacks[0] && stacks[0]._k);
    const ings = arr(d.ingredients);
    panel.ing = ings.find((x) => x.item === panel.ing) ? panel.ing : (ings[0] && ings[0].item);
    const s = stacks.find((x) => x._k === panel.sel);
    const ing = ings.find((x) => x.item === panel.ing);
    const max = s && ing ? Math.min(d.max || 10, s.n, ing.n) : 0;
    panel.n = clamp(panel.n || 1, max ? 1 : 0, max);
    let preview = '';
    if (s && ing) {
        const out = mixApply(arr(s.effects), ing.item);
        const v0 = valueOf(s.base, arr(s.effects)), v1 = valueOf(s.base, out);
        preview = `<div class="fx-preview"><div class="val"><span>Result</span><b>${money(v1)}<small class="muted" style="font-size:11px;margin-left:6px">${v1 >= v0 ? '+' : ''}${money(v1 - v0).replace('$-', '-$')} / unit</small></b></div>${chips(out)}</div>`;
    }
    const body = !stacks.length
        ? `<div class="empty">${I('flask')}<b>No loose product</b><span>Mixing works on loose (unbagged) product.</span></div>`
        : `<div class="cols2"><div><div class="sect-h">Product</div><div class="list">${stacks.map((x) => stackRow(x, x._k === panel.sel)).join('')}</div></div>
           <div><div class="sect-h">Ingredient</div><div class="list">${ings.length ? ings.map((x) => `<button class="row ${x.item === panel.ing ? 'on' : ''}" data-ing="${esc(x.item)}"><div class="tile" style="color:${effColor(x.effect)}">${I('flask')}</div><div class="row-txt"><b>${esc(x.label)}</b><span>Adds ${esc(effLabel(x.effect))}</span></div><div class="end">x${x.n}</div></button>`).join('') : `<div class="empty">${I('cart')}<b>No ingredients</b><span>Order some from the Gas-Mart in the Deliveries app.</span></div>`}</div></div></div>
           <div style="margin-top:14px">${preview}<div class="mixbar"><i></i></div></div>
           <div id="mixres"></div>`;
    const el = mountPanel(shell('Mixing Station', 'One ingredient per unit', body,
        `<div class="grow"><div class="qty"><button data-q="-1">−</button><b>${panel.n}</b><button data-q="1">+</button></div><span class="muted">units</span></div><button class="btn-teal" data-mix ${max ? '' : 'disabled'}>${I('flask')}Mix</button>`, true));
    $$('[data-k]', el).forEach((b) => b.onclick = () => { panel.sel = b.dataset.k; panelMix(d); });
    $$('[data-ing]', el).forEach((b) => b.onclick = () => { panel.ing = b.dataset.ing; panelMix(d); });
    $$('[data-q]', el).forEach((b) => b.onclick = () => { panel.n += +b.dataset.q; panelMix(d); });
    const mx = $('[data-mix]', el);
    if (mx) mx.onclick = async () => {
        mx.disabled = true;
        const bar = $('.mixbar i', el);
        const secs = (CFG.mixSeconds || 6) * 1000;
        bar.style.transition = `width ${secs}ms linear`;
        requestAnimationFrame(() => bar.style.width = '100%');
        await new Promise((r) => setTimeout(r, secs));
        const res = await post('mix:go', { item: s.item, pid: s.pid, q: s.q, ingredient: ing.item, n: panel.n });
        if (!res || !panel) { if (panel) panelMix(d); return; }
        panelMix(res.panel || d);
        const p = res.product;
        $('#mixres').innerHTML = `<div class="row on" style="margin-top:12px"><div class="tile">${I('star')}</div><div class="row-txt"><b>${esc(p.name)}${res.first ? ' <span class="chip">New discovery</span>' : ''}</b><span>Worth ${money(p.value)} per unit</span></div></div>`;
    };
}

/* rack: { stacks (weed), leaves, slots, capacity, now } */
function panelRack(d) {
    const stacks = keyStacks(d.stacks);
    const used = arr(d.slots).reduce((a, s) => a + s.n, 0);
    const room = Math.max(0, d.capacity - used);
    const skew = (d.now || Date.now() / 1000) - Date.now() / 1000;
    panel.sel = panel.sel || (d.leaves ? 'coca' : stacks[0] && stacks[0]._k);
    const s = stacks.find((x) => x._k === panel.sel);
    const avail = panel.sel === 'coca' ? d.leaves : (s ? s.n : 0);
    const max = Math.min(room, avail);
    panel.n = clamp(panel.n || max, max ? 1 : 0, max);
    const slotRows = arr(d.slots).map((x, i) => {
        const left = x.done - (Date.now() / 1000 + skew);
        return `<div class="row"><div class="tile ${left > 0 ? 'mute' : ''}">${I(x.kind === 'coca' ? 'leaf' : 'leaf')}</div><div class="row-txt"><b>${x.n}x ${x.kind === 'coca' ? 'Coca leaves' : 'Weed'}</b><span>${left > 0 ? 'Drying · ' + fmtLeft(left) : 'Dry'}</span></div><div class="end"><button class="btn-line" data-take="${i + 1}" style="height:28px">${left > 0 ? 'Take out' : 'Collect'}</button></div></div>`;
    }).join('');
    const body = `<div class="sect-h">On the rack · ${used}/${d.capacity}</div><div class="list">${slotRows || `<div class="empty">${I('rack')}<b>Empty</b><span>Hang weed for a quality bump, or coca leaves to dry them.</span></div>`}</div>
        <div class="sect-h" style="margin-top:14px">Hang up</div><div class="list">
        ${d.leaves ? `<button class="row ${panel.sel === 'coca' ? 'on' : ''}" data-k="coca"><div class="tile">${I('leaf')}</div><div class="row-txt"><b>Coca leaves</b><span>Dry them for the cauldron</span></div><div class="end">x${d.leaves}</div></button>` : ''}
        ${stacks.map((x) => stackRow(x, x._k === panel.sel)).join('')}
        ${!d.leaves && !stacks.length ? `<div class="empty">${I('leaf')}<b>Nothing to dry</b><span>Loose weed or coca leaves show up here.</span></div>` : ''}</div>`;
    const el = mountPanel(shell('Drying Rack', `${d.capacity} slots`, body,
        `<div class="grow"><div class="qty"><button data-q="-1">−</button><b>${panel.n}</b><button data-q="1">+</button></div></div><button class="btn-teal" data-add ${max ? '' : 'disabled'}>${I('rack')}Hang up</button>`));
    $$('[data-k]', el).forEach((b) => b.onclick = () => { panel.sel = b.dataset.k; panel.n = 0; panelRack(d); });
    $$('[data-q]', el).forEach((b) => b.onclick = () => { panel.n += +b.dataset.q; panelRack(d); });
    $$('[data-take]', el).forEach((b) => b.onclick = async () => { const r = await post('rack:take', { idx: +b.dataset.take }); if (r && panel) panelRack(r); });
    const add = $('[data-add]', el);
    if (add) add.onclick = async () => {
        const what = panel.sel === 'coca' ? 'coca' : { pid: s.pid, q: s.q };
        const r = await post('rack:add', { what, n: panel.n });
        if (r && panel) { panel.n = 0; panelRack(r); }
    };
}

/* give: { mode: 'deal'|'sample'|'dealer', name, standards, favorites, want, stock, units } */
function panelGive(d) {
    const el = $('#give');
    const stock = keyStacks(d.stock);
    panel.sel = stock.find((x) => x._k === panel.sel) ? panel.sel : null;
    const s = stock.find((x) => x._k === panel.sel);
    if (d.units) panel.n = clamp(panel.n || (s ? s.n : 1), 1, s ? s.n : 1);
    const std = arr(CFG.standards).find((x) => x.id === d.standards);
    const title = d.mode === 'deal' ? 'Hand Over' : d.mode === 'dealer' ? 'Stock Your Dealer' : 'Give Free Sample';
    const sub = d.mode === 'deal' ? `Pick the product for ${d.name}` : d.mode === 'dealer' ? `Bagged product for ${d.name} to sell` : `Place a product here for ${d.name} to try`;
    el.innerHTML = `<div class="mid">
        <h2>${title}</h2><div class="sub">${esc(sub)}</div>
        ${d.want ? `<div class="want">${I('handshake', 'ico')} Wants <b>${d.want.qty}x ${esc(d.want.product)}</b></div>` : ''}
        <div class="grid">${stock.length ? stock.map((x) => { const q = qualityOf(x.q); return `<button class="it ${x._k === panel.sel ? 'on' : ''}" data-k="${esc(x._k)}" style="--c:${(CFG.drugs[x.base] || {}).color || 'var(--teal)'}"><span class="ic">${I(KIND_ICON[kindOf(x.base)])}</span><i>${x.n}</i><b>${esc(x.name)}</b><span style="color:${q.color}">${esc(q.label)}</span></button>`; }).join('') : `<div class="empty" style="grid-column:span 4">${I('bag')}<b>Nothing bagged</b><span>Package your product at the packaging station first.</span></div>`}</div>
        ${d.favorites ? `<div class="fav"><b>${esc(d.name)}'s favourite effects:</b>${arr(d.favorites).map((e) => `<div style="color:${effColor(e)}">• ${esc(effLabel(e))}</div>`).join('')}</div>` : ''}
        ${d.units && s ? `<div class="qty"><button data-q="-5">−5</button><button data-q="-1">−</button><b>${panel.n}</b><button data-q="1">+</button><button data-q="5">+5</button></div>` : ''}
        <button class="done" data-done ${s ? '' : 'disabled'}>DONE</button>
      </div>
      ${d.favorites || std ? `<div class="side"><div class="info"><h3>${esc(d.name)}</h3>${std ? `<div class="k">Standards</div><div class="v">★ ${esc(std.label)}</div>` : ''}${d.favorites ? `<div class="k">Favourite effects</div>${chips(d.favorites)}` : ''}</div></div>` : ''}`;
    el.classList.remove('hidden');
    $$('[data-k]', el).forEach((b) => b.onclick = () => { panel.sel = b.dataset.k; panel.n = 0; panelGive(d); });
    $$('[data-q]', el).forEach((b) => b.onclick = () => { panel.n += +b.dataset.q; panelGive(d); });
    const done = $('[data-done]', el);
    if (done && s) done.onclick = () => panelClose({ pid: s.pid, q: s.q, n: panel.n });
}

const PANELS = { choose: panelChoose, place: panelPlace, pack: panelPack, mix: panelMix, rack: panelRack, give: panelGive };
function openPanel(d) {
    if (!d) return hidePanel();
    panel = { type: d.type, data: d.data };
    (PANELS[d.type] || panelChoose)(d.data || {});
}

/* ─────────────── level up / xp ─────────────── */
let lvlT;
function levelup(d) {
    const el = $('#lvl');
    el.innerHTML = `<small>Rank up</small><b>${esc(d.rank)}</b>${arr(d.unlocks).length ? `<p>Unlocked: ${arr(d.unlocks).map(esc).join(', ')}</p>` : ''}<div class="rule"></div>`;
    el.classList.remove('hidden');
    clearTimeout(lvlT);
    lvlT = setTimeout(() => el.classList.add('hidden'), 5500);
}
function xp(d) {
    const el = document.createElement('div');
    el.className = 'xp';
    el.innerHTML = `+${d.amount} XP<span>${esc(d.why || '')}</span>`;
    $('#xp-host').appendChild(el);
    setTimeout(() => el.remove(), 2500);
}

/* ─────────────── phone (on screen) ─────────────── */
function phone(d) {
    const el = $('#phone');
    if (!d || !d.open) { el.classList.add('hidden'); return; }
    if (!$('iframe', el)) {
        const f = document.createElement('iframe');
        f.src = 'phone/index.html?host=nui';
        el.appendChild(f);
    } else {
        $('iframe', el).contentWindow.postMessage({ type: 'refresh', what: 'all' }, '*');
    }
    el.classList.remove('hidden');
}

/* ─────────────── messages ─────────────── */
window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    switch (action) {
        case 'init':
            Object.assign(CFG, data || {});
            CFG.mixSeconds = (data && data.mixSeconds) || 6;
            applyTheme(CFG.ui && CFG.ui.theme);
            if (CFG.ui && CFG.ui.hud) {
                document.documentElement.style.setProperty('--hud-scale', CFG.ui.hud.scale || 1);
                $('#hud').classList.toggle('right', CFG.ui.hud.position === 'right');
            }
            if (CFG.ui && CFG.ui.notify) $('#notify').className = 'notify ' + (CFG.ui.notify.position || 'top-right');
            break;
        case 'notify': notify(data); break;
        case 'sms': sms(data); break;
        case 'text': text(data); break;
        case 'textui': textui(data); break;
        case 'progress': progress(data); break;
        case 'hud': hudData = data || null; renderHud(); break;
        case 'ix': ix(data); break;
        case 'dialogue': dialogue(data); break;
        case 'panel': openPanel(data); break;
        case 'panel:update': if (panel) (PANELS[panel.type] || panelChoose)(data); break;
        case 'levelup': levelup(data); break;
        case 'xp': xp(data); break;
        case 'phone': phone(data); break;
        case 'phone:push': { const f = $('#phone iframe'); if (f) f.contentWindow.postMessage(data, '*'); break; }
    }
});

document.addEventListener('keydown', (e) => {
    const dlg = $('#dlg');
    if (!dlg.classList.contains('hidden')) {
        if (e.key === 'Escape') return post('dialogue', { i: -1 });
        if (dlgType && (e.key === 'e' || e.key === 'E' || e.key === ' ' || e.key === 'Enter')) return dlg._finish && dlg._finish();
        if (!dlgType) {
            if (!dlgChoices.length && (e.key === 'e' || e.key === 'E' || e.key === ' ' || e.key === 'Enter')) return post('dialogue', { i: 0 });
            const n = parseInt(e.key, 10);
            if (n >= 1 && n <= dlgChoices.length) return post('dialogue', { i: n });
        }
        return;
    }
    if (e.key !== 'Escape') return;
    if (panel) return post('close', { what: 'panel' }).then(hidePanel);
    if (!$('#phone').classList.contains('hidden')) return post('close', { what: 'phone' });
    if (!$('#ix').classList.contains('hidden')) return post('close', { what: 'ix' });
});

window.addEventListener('message', (e) => {
    // the on-screen phone asks to close itself
    if (e.data && e.data.type === 'phone:close') post('close', { what: 'phone' });
});

post('ready');

if (!RES) {
    const s = document.createElement('script');
    s.src = 'preview.js';
    document.body.appendChild(s);
}
