/* ═══════════════════════════════════════════════════════════
   nayzeee weed lab - NUI (NAYZEEE UI)
   HUD · toasts · Benson's texts · dialogue · first person overlay · panels · store · tablet
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
const IMG = '../install/images/';

const CFG = { effects: {}, quality: [], items: {}, ingredients: {}, strains: {}, maxEffects: 8, ui: {}, categories: [] };

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

/* ─────────────── helpers ─────────────── */
function effLabel(e) { return (CFG.effects[e] && CFG.effects[e].label) || e; }
function effColor(e) { return (CFG.effects[e] && CFG.effects[e].color) || '#9ea5aa'; }
function chips(list) { return `<div class="chips">${arr(list).map((e) => `<span class="chip" style="--c:${effColor(e)}">${esc(effLabel(e))}</span>`).join('') || '<span class="chip off">No effects</span>'}</div>`; }
function qualityOf(q) { return arr(CFG.quality).find((x) => x.id === q) || { label: 'Standard', color: '#9ea5aa' }; }
function img(item, icon, cls = '') { return `<div class="img ${cls}"><img src="${IMG}${esc(item)}.png" onerror="this.replaceWith(document.createRange().createContextualFragment(window.Icons.svg('${icon || 'box'}')))"></div>`; }
function budImg(bud) { return img('nzw_bud_' + (bud || 'green'), 'leaf'); }
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
    const s = CFG.strains[base]; if (!s) return 0;
    let m = 0; for (const e of effects) m += (CFG.effects[e] && CFG.effects[e].mult) || 0;
    return Math.round(s.price * (1 + m));
}
function fmtLeft(s) { s = Math.max(0, Math.floor(s)); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60); return h ? `${h}h ${String(m).padStart(2, '0')}m` : m ? `${m}m ${String(s % 60).padStart(2, '0')}s` : `${s}s`; }

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

/* ─────────────── HUD: the objective, top left ─────────────── */
function renderHud(d) {
    const el = $('#hud');
    if (!d || !d.quest) { el.classList.add('hidden'); el.innerHTML = ''; return; }
    const q = d.quest;
    el.innerHTML = `<div class="hud-item"><div class="hud-ic">${I('star')}</div><div><b>${esc(q.title)}</b><p>${esc(q.text)}</p></div></div>`;
    el.classList.remove('hidden');
}

/* ─────────────── a text from Benson ─────────────── */
let textT;
function text(d) {
    const el = $('#text');
    clearTimeout(textT);
    if (!d) { el.classList.add('hidden'); el.innerHTML = ''; return; }
    el.innerHTML = `<div class="card"><div class="card-in">
        <div class="card-bar"><div class="tile mute">${I('msg')}</div><div class="t"><b>${esc(d.from)}</b><span>Text message</span></div></div>
        <div class="card-body"><div class="bubbles">${arr(d.lines).map((l) => `<div class="bub">${esc(l)}</div>`).join('')}</div></div>
        <div class="timer"><i style="animation-duration:${d.timeout || 14}s"></i></div>
    </div></div>`;
    el.classList.remove('hidden');
    textT = setTimeout(() => text(false), (d.timeout || 14) * 1000);
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
    el._finish = finish;
}

/* ─────────────── panels ─────────────── */
let panel = null;
function panelClose(result) { post('panel:done', result || {}); hidePanel(); }
function hidePanel() { $('#panel').classList.add('hidden'); $('#panel').innerHTML = ''; panel = null; }

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

function keyStacks(list) { return arr(list).map((s, i) => Object.assign(s, { _k: `${s.pid}|${s.q}|${i}` })); }

function stackRow(s, on, end) {
    const q = qualityOf(s.q);
    return `<button class="row ${on ? 'on' : ''}" data-k="${esc(s._k)}">${budImg(s.bud)}
        <div class="row-txt"><b>${esc(s.name)} <span class="chip" style="--c:${q.color}">${esc(q.label)}</span></b><span>${arr(s.effects).map(effLabel).join(', ') || 'No effects'} · ${money(s.value)}/unit</span></div>
        <div class="end">${end != null ? end : 'x' + s.n}</div></button>`;
}

const emptyProduct = (what) => `<div class="empty">${I('leaf')}<b>No loose weed</b><span>${esc(what || 'Harvest a plant first. Trimmed buds show up here.')}</span></div>`;

/* choose: { title, options: [{ item, label, n, locked, level }] } */
function panelChoose(d) {
    const el = mountPanel(shell(d.title || 'Pick one', 'What do you want to use?',
        `<div class="list">${arr(d.options).map((o) => `<button class="row ${o.locked ? 'dim' : ''}" data-item="${esc(o.item)}" ${o.locked ? 'disabled' : ''}>${img(o.item, 'box')}<div class="row-txt"><b>${esc(o.label)}</b>${o.locked ? `<span class="lock">${I('lock')} Level ${o.level}</span>` : ''}</div><div class="end">${o.n != null ? 'x' + o.n : ''}</div></button>`).join('')}</div>`));
    $$('[data-item]', el).forEach((b) => b.onclick = () => panelClose({ item: b.dataset.item }));
}

/* place: { items: [{ item, label, icon, n, locked, level }], lab, maxGrow, maxObjects, objects } */
function panelPlace(d) {
    const el = mountPanel(shell('Set up equipment', `${d.lab || 'Lab'} · ${d.objects || 0}/${d.maxObjects || '?'} placed · ${d.maxGrow || '?'} growing stations max`,
        `<div class="eq">${arr(d.items).map((o) => `<button data-item="${esc(o.item)}" ${o.locked ? 'disabled' : ''}>${img(o.item, o.icon, 'lg')}${esc(o.label)}<small>${o.locked ? 'Level ' + o.level : 'x' + o.n}</small></button>`).join('')}</div>`,
        `<div class="grow"><span><span class="key">Scroll</span> Rotate</span><span><span class="key">E</span> Place</span><span><span class="key">Backspace</span> Cancel</span></div>`));
    $$('[data-item]', el).forEach((b) => b.onclick = () => panelClose({ item: b.dataset.item }));
}

/* pack: { stacks, baggies, jars, jarLevel, level, max: { baggie, jar }, per: { baggie, jar } } */
function panelPack(d) {
    const stacks = keyStacks(d.stacks);
    panel.sel = stacks.find((x) => x._k === panel.sel) ? panel.sel : (stacks[0] && stacks[0]._k);
    const jarsOk = d.level >= d.jarLevel;
    panel.kind = panel.kind === 'jar' && jarsOk ? 'jar' : (panel.kind || 'baggie');
    const s = stacks.find((x) => x._k === panel.sel);
    const per = d.per[panel.kind];
    const packs = panel.kind === 'jar' ? d.jars : d.baggies;
    const max = s ? Math.max(0, Math.min(d.max[panel.kind], Math.floor(s.n / per), packs)) : 0;
    panel.n = clamp(panel.n || max, max ? 1 : 0, max);
    const body = !stacks.length ? emptyProduct() : `
        <div class="pack-row">
            <div class="slot"><div class="box ${s ? 'fill' : ''}">${s ? budImg(s.bud) : I('leaf')}${s ? `<i>${s.n}x</i>` : ''}</div>Tray</div>
            <div class="slot"><div class="box fill">${img(panel.kind === 'jar' ? 'nzw_jar_empty' : 'nzw_baggie_empty', panel.kind === 'jar' ? 'jar' : 'bag')}<i>${packs}x</i></div>Packaging</div>
            <div class="arrow"><span>PACK</span><svg viewBox="0 0 18 26"><path d="M0 0l18 13L0 26z" fill="currentColor" opacity=".35"/></svg></div>
            <div class="slot"><div class="box">${I('hatch')}</div>Hatch</div>
        </div>
        <div class="sect-h">Product</div><div class="list">${stacks.map((x) => stackRow(x, x._k === panel.sel)).join('')}</div>
        <div class="sect-h" style="margin-top:14px">Packaging</div>
        <div class="between"><div class="seg"><button data-kind="baggie" class="${panel.kind === 'baggie' ? 'on' : ''}">Baggie · ${d.per.baggie} unit (${d.baggies})</button><button data-kind="jar" class="${panel.kind === 'jar' ? 'on' : ''}" ${jarsOk ? '' : 'disabled'}>Jar · ${d.per.jar} units (${d.jars})${jarsOk ? '' : ' · Lvl ' + d.jarLevel}</button></div>
        <div class="qty"><button data-q="-1">−</button><b>${panel.n}</b><button data-q="1">+</button></div></div>`;
    const el = mountPanel(shell('Packaging Station', 'Tray · packaging · hatch', body,
        `<div class="grow muted">Up to ${d.max[panel.kind]} ${panel.kind === 'jar' ? 'jars' : 'baggies'} line up per batch</div><button class="btn-teal" data-go ${max ? '' : 'disabled'}>${I('box')}Start packaging</button>`));
    $$('[data-k]', el).forEach((b) => b.onclick = () => { panel.sel = b.dataset.k; panel.n = 0; panelPack(d); });
    $$('[data-kind]', el).forEach((b) => b.onclick = () => { panel.kind = b.dataset.kind; panel.n = 0; panelPack(d); });
    $$('[data-q]', el).forEach((b) => b.onclick = () => { panel.n += +b.dataset.q; panelPack(d); });
    const go = $('[data-go]', el);
    if (go && s) go.onclick = () => panelClose({ pid: s.pid, q: s.q, kind: panel.kind, n: panel.n });
}

/* dry: { stacks, slots: [{ pid, q, done, name }], capacity, now, max, minutes } */
function panelDry(d) {
    const stacks = keyStacks(d.stacks).filter((s) => s.q < d.max);
    const slots = arr(d.slots);
    const skew = (d.now || Date.now() / 1000) - Date.now() / 1000;
    const nowS = Date.now() / 1000 + skew;
    const room = Math.max(0, d.capacity - slots.length);
    panel.sel = stacks.find((x) => x._k === panel.sel) ? panel.sel : (stacks[0] && stacks[0]._k);
    const s = stacks.find((x) => x._k === panel.sel);
    const max = s ? Math.min(room, s.n) : 0;
    panel.n = clamp(panel.n || max, max ? 1 : 0, max);
    const ready = slots.filter((x) => x.done <= nowS).length;
    const grid = Array.from({ length: d.capacity }, (_, i) => {
        const x = slots[i];
        if (!x) return `<div class="s">${i + 1}</div>`;
        const left = x.done - nowS;
        return `<div class="s full ${left <= 0 ? 'dry' : ''}"><span>${left <= 0 ? 'DRY' : fmtLeft(left)}</span></div>`;
    }).join('');
    const body = `<div class="sect-h">On the rack · ${slots.length}/${d.capacity}</div><div class="slots">${grid}</div>
        <div class="sect-h" style="margin-top:14px">Hang up · +1 quality after ${d.minutes} min</div>
        <div class="list">${stacks.length ? stacks.map((x) => stackRow(x, x._k === panel.sel)).join('') : emptyProduct('Loose weed below Heavenly quality shows up here.')}</div>`;
    const el = mountPanel(shell('Drying Rack', 'One bud per clip', body,
        `<div class="grow"><div class="qty"><button data-q="-1">−</button><b>${panel.n}</b><button data-q="1">+</button></div>${ready ? `<button class="btn-line" data-collect>${I('check')}Collect ${ready} dry</button>` : ''}</div><button class="btn-teal" data-go ${max ? '' : 'disabled'}>${I('rack')}Hang up</button>`));
    $$('[data-k]', el).forEach((b) => b.onclick = () => { panel.sel = b.dataset.k; panel.n = 0; panelDry(d); });
    $$('[data-q]', el).forEach((b) => b.onclick = () => { panel.n += +b.dataset.q; panelDry(d); });
    const c = $('[data-collect]', el);
    if (c) c.onclick = () => panelClose({ collect: true });
    const go = $('[data-go]', el);
    if (go && s) go.onclick = () => panelClose({ pid: s.pid, q: s.q, n: panel.n });
}

/* mix: { stacks, ingredients: [{ item, label, effect, n, locked, level }], max } */
function panelMix(d) {
    const stacks = keyStacks(d.stacks);
    panel.sel = stacks.find((x) => x._k === panel.sel) ? panel.sel : (stacks[0] && stacks[0]._k);
    const ings = arr(d.ingredients);
    panel.ing = ings.find((x) => x.item === panel.ing && !x.locked) ? panel.ing : ((ings.find((x) => !x.locked) || {}).item);
    const s = stacks.find((x) => x._k === panel.sel);
    const ing = ings.find((x) => x.item === panel.ing);
    const max = s && ing ? Math.min(d.max || 10, s.n, ing.n) : 0;
    panel.n = clamp(panel.n || max, max ? 1 : 0, max);
    let preview = '';
    if (s && ing) {
        const out = mixApply(arr(s.effects), ing.item);
        const v0 = valueOf(s.base, arr(s.effects)), v1 = valueOf(s.base, out);
        preview = `<div class="fx-preview"><div class="val"><span>Result</span><b>${money(v1)}<small class="muted" style="font-size:11px;margin-left:6px">${v1 >= v0 ? '+' : '-'}${money(Math.abs(v1 - v0))} / unit</small></b></div>${chips(out)}</div>`;
    }
    const body = !stacks.length ? emptyProduct('Mixing works on loose (unbagged) weed.') : `
        <div class="cols2"><div><div class="sect-h">Product</div><div class="list">${stacks.map((x) => stackRow(x, x._k === panel.sel)).join('')}</div></div>
        <div><div class="sect-h">Ingredient</div><div class="list">${ings.length ? ings.map((x) => `<button class="row ${x.item === panel.ing ? 'on' : ''} ${x.locked ? 'dim' : ''}" data-ing="${esc(x.item)}" ${x.locked ? 'disabled' : ''}>${img(x.item, 'flask')}<div class="row-txt"><b>${esc(x.label)}</b><span>${x.locked ? 'Level ' + x.level : 'Adds ' + esc(effLabel(x.effect))}</span></div><div class="end">x${x.n}</div></button>`).join('') : `<div class="empty">${I('cart')}<b>No ingredients</b><span>The hardware store sells them once you unlock mixing.</span></div>`}</div></div></div>
        <div style="margin-top:14px">${preview}</div>`;
    const el = mountPanel(shell('Mixing Station', 'One ingredient per unit', body,
        `<div class="grow"><div class="qty"><button data-q="-1">−</button><b>${panel.n}</b><button data-q="1">+</button></div><span class="muted">units</span></div><button class="btn-teal" data-go ${max ? '' : 'disabled'}>${I('flask')}Mix</button>`, true));
    $$('[data-k]', el).forEach((b) => b.onclick = () => { panel.sel = b.dataset.k; panel.n = 0; panelMix(d); });
    $$('[data-ing]', el).forEach((b) => b.onclick = () => { panel.ing = b.dataset.ing; panel.n = 0; panelMix(d); });
    $$('[data-q]', el).forEach((b) => b.onclick = () => { panel.n += +b.dataset.q; panelMix(d); });
    const go = $('[data-go]', el);
    if (go && s && ing) go.onclick = () => panelClose({ pid: s.pid, q: s.q, ingredient: ing.item, n: panel.n });
}

/* press: { stacks, units } */
function panelPress(d) {
    const stacks = keyStacks(d.stacks);
    const ok = stacks.filter((s) => s.n >= d.units);
    panel.sel = ok.find((x) => x._k === panel.sel) ? panel.sel : (ok[0] && ok[0]._k);
    const s = ok.find((x) => x._k === panel.sel);
    const body = `<div class="pack-row">
            <div class="slot"><div class="box ${s ? 'fill' : ''}">${s ? budImg(s.bud) : I('leaf')}<i>${d.units}x</i></div>Weed</div>
            <div class="arrow"><span>PRESS</span><svg viewBox="0 0 18 26"><path d="M0 0l18 13L0 26z" fill="currentColor" opacity=".35"/></svg></div>
            <div class="slot"><div class="box">${img('nzw_brick', 'press')}</div>Brick</div>
        </div>
        <div class="sect-h">Product · ${d.units} units of one product and quality</div>
        <div class="list">${stacks.length ? stacks.map((x) => x.n >= d.units ? stackRow(x, x._k === panel.sel) : stackRow(x, false, `<span class="muted">${x.n}/${d.units}</span>`).replace('class="row', 'disabled class="row dim')).join('') : emptyProduct()}</div>`;
    const el = mountPanel(shell('Brick Press', 'Squish it into a brick', body,
        `<div class="grow muted">Load the mould, then pump the lever</div><button class="btn-teal" data-go ${s ? '' : 'disabled'}>${I('press')}Press</button>`));
    $$('[data-k]', el).forEach((b) => b.onclick = () => { panel.sel = b.dataset.k; panelPress(d); });
    const go = $('[data-go]', el);
    if (go && s) go.onclick = () => panelClose({ pid: s.pid, q: s.q });
}

/* shop: { items: [{ item, label, desc, price, cat, level, locked }], level, money, accounts, max } */
function panelShop(d) {
    panel.cat = panel.cat || (CFG.categories[0] && CFG.categories[0].id);
    panel.basket = panel.basket || {};
    panel.account = panel.account || arr(d.accounts)[0];
    const items = arr(d.items);
    const list = items.filter((x) => x.cat === panel.cat);
    const lines = Object.entries(panel.basket).filter(([, n]) => n > 0);
    const total = lines.reduce((a, [it, n]) => a + ((items.find((x) => x.item === it) || {}).price || 0) * n, 0);
    const have = (d.money || {})[panel.account] || 0;
    const body = `<div class="shop"><div>
        <div class="shop-cats">${arr(CFG.categories).map((c) => `<button data-cat="${esc(c.id)}" class="${c.id === panel.cat ? 'on' : ''}">${I(c.icon)}${esc(c.label)}</button>`).join('')}</div>
        <div class="shop-grid">${list.map((x) => `<button class="prod ${x.locked ? 'locked' : ''}" data-add="${esc(x.item)}" ${x.locked ? 'disabled' : ''}>
            ${x.locked ? `<span class="badge chip" style="--c:var(--amber)">${I('lock')} Level ${x.level}</span>` : ''}
            <div class="pic"><img src="${IMG}${esc(x.item)}.png" onerror="this.replaceWith(document.createRange().createContextualFragment(window.Icons.svg('box')))"></div>
            <b>${esc(x.label)}</b><span>${esc(x.desc)}</span>
            <div class="foot"><span class="money">${money(x.price)}</span>${panel.basket[x.item] ? `<span class="chip">x${panel.basket[x.item]}</span>` : `<span class="key">+</span>`}</div></button>`).join('')}</div>
      </div>
      <div class="basket"><div class="sect-h" style="margin:0">Basket</div>
        ${lines.length ? lines.map(([it, n]) => `<div class="ln"><span>${esc(CFG.items[it] || it)}</span><div class="qty"><button data-dec="${esc(it)}">−</button><b>${n}</b><button data-inc="${esc(it)}">+</button></div></div>`).join('') : '<div class="muted" style="font-size:11px">Click items to add them.</div>'}
        <div class="seg">${arr(d.accounts).map((a) => `<button data-acc="${esc(a)}" class="${a === panel.account ? 'on' : ''}">${esc(a)} · ${money((d.money || {})[a])}</button>`).join('')}</div>
        <div class="sum"><span>Total</span><b>${money(total)}</b></div>
        <button class="btn-teal wide" data-buy ${lines.length && total <= have ? '' : 'disabled'}>${I('cart')}Buy</button>
      </div></div>`;
    const el = mountPanel(shell('Hardware Store', `Level ${d.level} · higher levels unlock more stock`, body, null, true));
    const add = (it, k) => { panel.basket[it] = clamp((panel.basket[it] || 0) + k, 0, d.max || 50); panelShop(d); };
    $$('[data-cat]', el).forEach((b) => b.onclick = () => { panel.cat = b.dataset.cat; panelShop(d); });
    $$('[data-add]', el).forEach((b) => b.onclick = () => add(b.dataset.add, 1));
    $$('[data-inc]', el).forEach((b) => b.onclick = () => add(b.dataset.inc, 1));
    $$('[data-dec]', el).forEach((b) => b.onclick = () => add(b.dataset.dec, -1));
    $$('[data-acc]', el).forEach((b) => b.onclick = () => { panel.account = b.dataset.acc; panelShop(d); });
    const buy = $('[data-buy]', el);
    if (buy) buy.onclick = () => panelClose({ basket: lines.map(([item, n]) => ({ item, n })), account: panel.account });
}

/* tablet: { level, xp, need, title, objective, unlocks, labs, accounts, towFee, water, capacity } */
function panelTablet(d) {
    panel.tab = panel.tab || 'labs';
    panel.ent = panel.ent || {};
    panel.account = panel.account || arr(d.accounts)[0];
    const pct = d.need ? clamp(d.xp / d.need, 0, 1) : 1;
    const C = 2 * Math.PI * 32;
    const head = `<div class="tab-head">
        <div class="lvl-ring"><svg viewBox="0 0 74 74"><circle cx="37" cy="37" r="32" fill="none" stroke="var(--raise)" stroke-width="5"/><circle cx="37" cy="37" r="32" fill="none" stroke="var(--teal)" stroke-width="5" stroke-linecap="round" stroke-dasharray="${C * pct} ${C}"/></svg><b>${d.level}</b></div>
        <div><h3>${esc(d.title || '')}</h3><p>${d.need ? `${d.xp} / ${d.need} XP to level ${d.level + 1}` : 'Max level'} · watering can ${d.water}/${d.capacity}</p><div class="bar"><i style="width:${pct * 100}%"></i></div></div>
      </div>
      <div class="tabs seg"><button data-tab="labs" class="${panel.tab === 'labs' ? 'on' : ''}">Labs</button><button data-tab="unlocks" class="${panel.tab === 'unlocks' ? 'on' : ''}">Unlocks</button></div>`;
    let body = '';
    if (panel.tab === 'labs') {
        body = `<div class="labs">${arr(d.labs).map((l) => {
            const ents = arr(l.entrances);
            let act = '';
            if (l.owned) {
                act = `<button class="btn-line" data-gps="${l.id}">${I('pin')}GPS</button>${l.id === 'rv' ? `<button class="btn-line" data-tow>${I('truck')}Tow · ${money(d.towFee)}</button>` : ''}`;
            } else if (l.id === 'rv') {
                act = `<span class="muted" style="font-size:11px">Find Uncle Benson</span>`;
            } else if (l.locked) {
                act = `<span class="lock">${I('lock')} Level ${l.level}</span>`;
            } else {
                act = `<select data-ent="${l.id}">${ents.map((e, i) => `<option value="${i + 1}" ${(panel.ent[l.id] || 1) === i + 1 ? 'selected' : ''}>${esc(e)}</option>`).join('')}</select><button class="btn-teal" data-buy="${l.id}">${I('cash')}Buy · ${money(l.price)}</button>`;
            }
            return `<div class="lab ${l.owned ? 'owned' : ''} ${l.locked && !l.owned ? 'locked' : ''}"><h4><div class="tile ${l.owned ? '' : 'mute'}">${I(l.icon)}</div>${esc(l.label)}</h4>
                <div class="meta">${l.owned ? (l.entrance && ents[l.entrance - 1] ? esc(ents[l.entrance - 1]) + ' · ' : '') + 'Owned' : 'Level ' + l.level + (l.price ? ' · ' + money(l.price) : '')}<br>${l.maxGrow} growing stations · ${l.maxObjects} items</div>${act}</div>`;
        }).join('')}</div>
        <div class="sect-h" style="margin-top:14px">Pay with</div><div class="seg">${arr(d.accounts).map((a) => `<button data-acc="${esc(a)}" class="${a === panel.account ? 'on' : ''}">${esc(a)}</button>`).join('')}</div>`;
    } else {
        const by = {};
        for (const u of arr(d.unlocks)) (by[u.level] = by[u.level] || []).push(u);
        const levels = Object.keys(by).map(Number).sort((a, b) => a - b);
        const next = levels.find((l) => l > d.level);
        body = `<div class="timeline">${levels.map((l) => `<div class="tl ${l <= d.level ? 'done' : ''} ${l === next ? 'next' : ''}"><em>LVL ${l}</em><div class="chips">${by[l].map((u) => `<span class="chip ${l <= d.level ? '' : 'off'}" ${u.kind === 'lab' ? 'style="--c:var(--amber)"' : ''}>${esc(u.label)}</span>`).join('')}</div></div>`).join('')}</div>`;
    }
    const el = mountPanel(shell('Weed Lab', d.objective ? d.objective.title + ' · ' + d.objective.text : 'Grow · process · level up', head + body, null, true));
    $$('[data-tab]', el).forEach((b) => b.onclick = () => { panel.tab = b.dataset.tab; panelTablet(d); });
    $$('[data-acc]', el).forEach((b) => b.onclick = () => { panel.account = b.dataset.acc; panelTablet(d); });
    $$('[data-ent]', el).forEach((s) => s.onchange = () => { panel.ent[s.dataset.ent] = +s.value; });
    $$('[data-gps]', el).forEach((b) => b.onclick = () => panelClose({ gps: b.dataset.gps }));
    $$('[data-tow]', el).forEach((b) => b.onclick = () => panelClose({ tow: true, account: panel.account }));
    $$('[data-buy]', el).forEach((b) => b.onclick = () => panelClose({ buy: b.dataset.buy, entrance: panel.ent[b.dataset.buy] || 1, account: panel.account }));
}

const PANELS = { choose: panelChoose, place: panelPlace, pack: panelPack, dry: panelDry, mix: panelMix, press: panelPress, shop: panelShop, tablet: panelTablet };
function openPanel(d) {
    if (!d) return hidePanel();
    panel = { type: d.type, data: d.data };
    (PANELS[d.type] || panelChoose)(d.data || {});
}

/* ─────────────── level up / xp ─────────────── */
let lvlT;
function levelup(d) {
    const el = $('#lvl');
    el.innerHTML = `<small>Level up</small><b>Level ${esc(d.level)} · ${esc(d.title)}</b>${arr(d.unlocks).length ? `<p>Unlocked: ${arr(d.unlocks).map(esc).join(', ')}</p>` : ''}<div class="rule"></div>`;
    el.classList.remove('hidden');
    clearTimeout(lvlT);
    lvlT = setTimeout(() => el.classList.add('hidden'), 6500);
}
function xp(d) {
    const el = document.createElement('div');
    el.className = 'xp';
    el.innerHTML = `+${d.amount} XP<span>${esc(d.why || '')}</span>`;
    $('#xp-host').appendChild(el);
    setTimeout(() => el.remove(), 2500);
}

/* ─────────────── messages ─────────────── */
window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    switch (action) {
        case 'init':
            Object.assign(CFG, data || {});
            applyTheme(CFG.ui && CFG.ui.theme);
            if (CFG.ui && CFG.ui.hud) {
                document.documentElement.style.setProperty('--hud-scale', CFG.ui.hud.scale || 1);
                $('#hud').classList.toggle('right', CFG.ui.hud.position === 'right');
            }
            if (CFG.ui && CFG.ui.notify) $('#notify').className = 'notify ' + (CFG.ui.notify.position || 'top-right');
            break;
        case 'notify': notify(data); break;
        case 'text': text(data); break;
        case 'textui': textui(data); break;
        case 'progress': progress(data); break;
        case 'hud': renderHud(data); break;
        case 'ix': ix(data); break;
        case 'dialogue': dialogue(data); break;
        case 'panel': openPanel(data); break;
        case 'panel:update': if (panel) (PANELS[panel.type] || panelChoose)(data); break;
        case 'levelup': levelup(data); break;
        case 'xp': xp(data); break;
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
    if (!$('#ix').classList.contains('hidden')) return post('close', { what: 'ix' });
});

post('ready');

if (!RES) {
    const s = document.createElement('script');
    s.src = 'preview.js';
    document.body.appendChild(s);
}
