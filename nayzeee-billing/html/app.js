// ═══════════════════════════════════════════════════════════════
// NAYZEEE BILLING v2 · UI
// Discord: discord.gg/nayzeeedev
// All user text is escaped; actions use data-act delegation (no inline JS with data).
// ═══════════════════════════════════════════════════════════════
'use strict';

const IN_GAME = typeof GetParentResourceName === 'function';
const RES = IN_GAME ? GetParentResourceName() : 'nayzeee-billing';
const $ = (sel, root = document) => root.querySelector(sel);

// ═══════════════ STATE ═══════════════
const S = {
    mode: null,          // billing | admin | pos | receipt
    ctx: null,
    tab: 'home',
    currency: '$',
    imagePath: 'nui://ox_inventory/web/images/%s.png',
    billsFilter: 'all',
    order: null,
    history: { filter: 'all', search: '', rows: [], page: 0, hasMore: false, loading: false },
    boss: { dash: null, inv: { status: 'open', search: '', rows: [], page: 0, hasMore: false }, catTab: 'products' },
    admin: { data: null, tab: 'overview', catalogCompany: null, inv: { status: 'all', companyId: '', search: '', rows: [], page: 0, hasMore: false }, logs: { search: '', rows: [], page: 0, hasMore: false } },
    pos: null,
    display: null,
    receiptClose: null,
    items: null,
};

function newOrder() {
    return { items: [], recipient: null, discount: 0, notes: '', dueDays: '', personal: false, category: 'all', search: '', nearby: [], results: [], query: '' };
}
S.order = newOrder();

// ═══════════════ NUI ═══════════════
async function nui(event, data = {}) {
    if (!IN_GAME) return Mock.nui(event, data);
    try {
        const res = await fetch(`https://${RES}/${event}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
        });
        return await res.json();
    } catch (e) { return null; }
}

async function api(name, payload = {}) {
    const res = await nui('rpc', { name, payload });
    return res && typeof res === 'object' ? res : { ok: false, error: 'No response from server' };
}

// RPC that toasts its own errors. Returns data (or true) on success, null on failure
async function call(name, payload) {
    const res = await api(name, payload);
    if (!res.ok) { toast('Error', res.error || 'Something went wrong', 'error'); return null; }
    return res.data === undefined || res.data === null ? true : res.data;
}

// ═══════════════ UTILS ═══════════════
const esc = (v) => String(v ?? '').replace(/[&<>"'`]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '`': '&#96;' }[m]));
const num = (v, d = 0) => { const n = parseFloat(v); return Number.isFinite(n) ? n : d; };
const round2 = (n) => Math.round((num(n) + Number.EPSILON) * 100) / 100;
const money = (n) => { const v = round2(n); const s = Math.abs(v).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ','); return (v < 0 ? '-' : '') + S.currency + s; };
const moneyShort = (n) => { const v = num(n); if (Math.abs(v) >= 1e6) return S.currency + (v / 1e6).toFixed(1) + 'M'; if (Math.abs(v) >= 1e4) return S.currency + (v / 1e3).toFixed(1) + 'k'; return money(v); };
const initials = (name) => esc(String(name || '?').trim().split(/\s+/).map((p) => p[0]).slice(0, 2).join('').toUpperCase());
const pct = (n) => `${round2(num(n) * 100)}%`;

function toDate(v) {
    if (v === null || v === undefined || v === '') return null;
    if (typeof v === 'number') return new Date(v);
    const d = new Date(String(v).replace(' ', 'T'));
    return isNaN(d) ? null : d;
}
function fmtDate(v, withTime = true) {
    const d = toDate(v); if (!d) return '—';
    const date = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    return withTime ? `${date}, ${d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })}` : date;
}
function ago(v) {
    const d = toDate(v); if (!d) return '';
    const s = Math.round((Date.now() - d.getTime()) / 1000);
    if (s < 60) return 'just now';
    if (s < 3600) return `${Math.floor(s / 60)}m ago`;
    if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
    return `${Math.floor(s / 86400)}d ago`;
}
function dueLabel(inv) {
    if (['paid', 'cancelled', 'refunded'].includes(inv.status)) return null;
    if (inv.status === 'overdue') return { text: 'Overdue', cls: 'red' };
    const d = toDate(inv.dueDate); if (!d) return null;
    const h = (d.getTime() - Date.now()) / 3600000;
    if (h < 0) return { text: 'Overdue', cls: 'red' };
    if (h < 24) return { text: `Due in ${Math.max(1, Math.round(h))}h`, cls: 'amber' };
    return { text: `Due in ${Math.round(h / 24)}d`, cls: '' };
}
const STATUS = {
    pending: ['live', 'Pending'], partial: ['warn', 'Partial'], overdue: ['hot', 'Overdue'], disputed: ['warn', 'Disputed'],
    paid: ['solid', 'Paid'], cancelled: ['off', 'Cancelled'], refunded: ['off', 'Refunded'],
};
const statusTag = (s) => { const [cls, label] = STATUS[s] || ['off', s]; return `<span class="tag ${cls}">${esc(label)}</span>`; };
const isOpen = (inv) => ['pending', 'partial', 'overdue'].includes(inv.status);
const itemSummary = (items) => (items || []).map((i) => `${i.quantity}× ${i.name}`).join(', ');
const imgUrl = (name) => S.imagePath.replace('%s', encodeURIComponent(name));

function debounce(fn, ms) { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; }
function greeting() { const h = new Date().getHours(); return h < 5 ? 'Good night' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'; }
function firstName(n) { return String(n || '').split(' ')[0]; }

function calcTotals(items, discountPct, taxRate) {
    const subtotal = round2(items.reduce((s, i) => s + num(i.price) * num(i.quantity), 0));
    const discount = round2(subtotal * num(discountPct) / 100);
    const tax = round2((subtotal - discount) * num(taxRate));
    return { subtotal, discount, tax, total: round2(subtotal - discount + tax) };
}

// ═══════════════ ICONS ═══════════════
const P = {
    grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    inbox: '<path d="M3 13h5l1.5 3h5L16 13h5"/><path d="M5.5 5h13L21 13v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-5l2.5-8z"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    bolt: '<path d="M13 3 5 14h6l-1 7 8-11h-6l1-7z"/>',
    send: '<path d="M21 3 10 14"/><path d="M21 3l-7 18-4-7-7-4 18-7z"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
    list: '<path d="M8 6h13M8 12h13M8 18h13"/><path d="M3.5 6h.01M3.5 12h.01M3.5 18h.01"/>',
    box: '<path d="M21 8 12 3 3 8v8l9 5 9-5V8z"/><path d="m3 8 9 5 9-5M12 13v8"/>',
    building: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M9 7h1M14 7h1M9 11h1M14 11h1M9 15h1M14 15h1M10 21v-3h4v3"/>',
    register: '<rect x="3" y="11" width="18" height="10" rx="2"/><path d="M6 11V5h8v6M14 7h4l1 4M7 15h2M11 15h2M15 15h2"/>',
    log: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
    x: '<path d="M6 6l12 12M18 6 6 18"/>',
    check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
    alert: '<path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8v.01"/>',
    refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/>',
    trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
    edit: '<path d="M4 20h4L19 9l-4-4L4 16v4z"/><path d="m13 7 4 4"/>',
    card: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18M7 15h3"/>',
    cash: '<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 9.5v.01M18 14.5v.01"/>',
    receipt: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3z"/><path d="M9 8h6M9 12h6M9 16h3"/>',
    user: '<circle cx="12" cy="8" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
    users: '<circle cx="9" cy="8" r="3.2"/><path d="M3 20a6 6 0 0 1 12 0M16 4.5a3.2 3.2 0 0 1 0 6.4M17.5 14a6 6 0 0 1 3.5 6"/>',
    flag: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
    undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>',
    up: '<path d="M12 19V5M6 11l6-6 6 6"/>',
    down: '<path d="M12 5v14M6 13l6 6 6-6"/>',
    pin: '<path d="M12 21s-7-6.1-7-11.5a7 7 0 0 1 14 0C19 14.9 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
    wallet: '<path d="M4 7a2 2 0 0 1 2-2h12v4"/><path d="M4 7v11a2 2 0 0 0 2 2h14V9H6a2 2 0 0 1-2-2z"/><path d="M16 14.5h.01"/>',
    tag: '<path d="M3 12V3h9l9 9-9 9-9-9z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
    shield: '<path d="M12 3 4 6v6c0 5 3.4 8.3 8 9 4.6-.7 8-4 8-9V6l-8-3z"/>',
    teleport: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4"/><circle cx="12" cy="12" r="4"/>',
    store: '<path d="M4 10v10h16V10M3 10l2-6h14l2 6M3 10a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0"/><path d="M10 20v-5h4v5"/>',
    percent: '<path d="M19 5 5 19"/><circle cx="7" cy="7" r="2.5"/><circle cx="17" cy="17" r="2.5"/>',
    note: '<path d="M5 4h14v12l-4 4H5z"/><path d="M15 20v-4h4M9 9h6M9 13h4"/>',
};
const ic = (name) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${P[name] || P.box}</svg>`;
const faIcon = (cls) => /^fa-[\w-]+$/.test(cls || '') ? `<i class="fa-solid ${cls}"></i>` : '';

// ═══════════════ TOASTS ═══════════════
function toast(title, message, type = 'info') {
    const box = $('#toasts');
    const el = document.createElement('div');
    el.className = `toast ${type === 'success' ? '' : type}`;
    const icon = type === 'error' ? 'info' : type === 'warning' ? 'alert' : type === 'success' ? 'check' : 'info';
    el.innerHTML = `<div class="ti">${ic(icon)}</div><div><b>${esc(title)}</b><p>${esc(message)}</p></div>`;
    box.appendChild(el);
    while (box.children.length > 4) box.firstChild.remove();
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 220); }, 4500);
}

// ═══════════════ MODALS ═══════════════
const modalStack = [];
function openModal(html, { onClose, cls = '' } = {}) {
    const overlay = document.createElement('div');
    overlay.className = 'overlay';
    overlay.innerHTML = html;
    if (cls) overlay.firstElementChild.classList.add(...cls.split(' '));
    $('#modals').appendChild(overlay);
    const entry = { el: overlay, onClose };
    entry.close = (value) => {
        const i = modalStack.indexOf(entry);
        if (i >= 0) modalStack.splice(i, 1);
        overlay.remove();
        if (onClose) onClose(value);
    };
    overlay.addEventListener('mousedown', (e) => { if (e.target === overlay) entry.close(null); });
    modalStack.push(entry);
    const first = overlay.querySelector('[autofocus]');
    if (first) setTimeout(() => first.focus(), 30);
    return entry;
}
const topModal = () => modalStack[modalStack.length - 1];
function closeAllModals() { while (modalStack.length) modalStack[modalStack.length - 1].close(null); }

function modalHead(icon, title, sub, tone = 'teal') {
    return `<div class="modal-h"><div class="warn ${tone}">${ic(icon)}</div><div><h4>${title}</h4>${sub ? `<p>${sub}</p>` : ''}</div>
        <button class="icon-btn x" data-act="modalClose">${ic('x')}</button></div>`;
}

function confirmBox({ title, text, confirm = 'Confirm', danger = false, icon = 'alert' }) {
    return new Promise((resolve) => {
        const m = openModal(`<div class="modal">
            ${modalHead(icon, esc(title), '', danger ? '' : 'teal')}
            <div class="modal-b"><p class="copy">${esc(text)}</p></div>
            <div class="modal-f"><button class="btn-line" data-act="modalClose">Cancel</button>
            <button class="${danger ? 'btn-red' : 'btn-teal'}" data-act="modalOk">${esc(confirm)}</button></div></div>`,
            { onClose: (v) => resolve(v === true) });
        m.ok = () => m.close(true);
    });
}

function promptBox({ title, text, placeholder = '', confirm = 'Submit', danger = false, required = false, icon = 'note', max = 200 }) {
    return new Promise((resolve) => {
        const m = openModal(`<div class="modal">
            ${modalHead(icon, esc(title), '', danger ? '' : 'teal')}
            <div class="modal-b">${text ? `<p class="copy">${esc(text)}</p>` : ''}
                <div class="field"><textarea id="promptInput" maxlength="${max}" placeholder="${esc(placeholder)}" autofocus></textarea></div></div>
            <div class="modal-f"><button class="btn-line" data-act="modalClose">Cancel</button>
            <button class="${danger ? 'btn-red' : 'btn-teal'}" data-act="modalOk">${esc(confirm)}</button></div></div>`,
            { onClose: (v) => resolve(typeof v === 'string' ? v : null) });
        m.ok = () => {
            const v = $('#promptInput', m.el).value.trim();
            if (required && v.length < 3) { toast('Required', 'Please add a short reason', 'warning'); return; }
            m.close(v);
        };
    });
}

// ═══════════════ SHELL ═══════════════
function showShell(mode) {
    S.mode = mode;
    $('#frame').classList.remove('hidden');
    $('#shell').classList.toggle('pos', mode === 'pos');
    $('#body').classList.toggle('full', mode === 'pos');
    $('#side').classList.toggle('hidden', mode === 'pos');
}
function hideShell() {
    $('#frame').classList.add('hidden');
    S.mode = null; // before closing modals so a receipt's onClose doesn't send another close
    closeAllModals();
}
function setBar(title, sub, midHtml) {
    $('#barTitle').textContent = title;
    $('#barSub').textContent = sub;
    $('#barMid').innerHTML = midHtml;
}
function setStatus(keys, right = '') {
    $('#statusbar').innerHTML = keys.map(([k, t]) => `<span><span class="key">${esc(k)}</span>${esc(t)}</span>`).join('')
        + `<span class="right">${right}</span>`;
}
function navBtn(id, icon, label, active, tally, tallyCls = '') {
    return `<button class="nav ${active ? 'on' : ''}" data-act="tab" data-tab="${id}">${ic(icon)}${esc(label)}${tally ? `<span class="tally ${tallyCls}">${esc(tally)}</span>` : ''}</button>`;
}
function setMain(html) {
    const main = $('#main');
    main.innerHTML = `<div class="wm-wrap"><div class="wm"></div></div>${html}`;
}
function emptyState(icon, title, text) {
    return `<div class="empty">${ic(icon)}<b>${esc(title)}</b><span>${esc(text)}</span></div>`;
}
function skeleton(n = 3) {
    return Array.from({ length: n }, () => `<div class="skel"><div class="sk circ"></div><div style="flex:1"><div class="sk" style="height:9px;width:52%"></div><div class="sk" style="height:7px;width:32%;margin-top:7px"></div></div></div>`).join('');
}
function clockHtml() {
    const d = new Date();
    return `<div class="clock" id="clock"><b>${d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })}</b><span>${d.toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long' })}</span></div>`;
}
setInterval(() => { const c = $('#clock'); if (c) c.outerHTML = clockHtml(); }, 30000);

function stat(icon, label, value, tone = '', extra = '') {
    return `<div class="stat"><div class="tile ${tone}">${ic(icon)}</div><div class="stat-txt"><span>${esc(label)}</span><b>${value}</b></div>${extra}</div>`;
}

// ═══════════════════════════════════════════════════════════════
// BILLING
// ═══════════════════════════════════════════════════════════════
function openBilling(ctx) {
    S.ctx = ctx;
    S.currency = ctx.settings?.currency || '$';
    S.imagePath = ctx.settings?.imagePath || S.imagePath;
    S.order = newOrder();
    S.history = { filter: 'all', search: '', rows: [], page: 0, hasMore: false };
    S.boss.dash = null;
    S.tab = ctx.tab || 'home';
    showShell('billing');
    renderBilling();
}

function canCreate() { const p = S.ctx?.perms || {}; return p.canBill || p.canPersonal; }

function renderBilling() {
    const { ctx } = S;
    const p = ctx.perms;
    const company = ctx.company;
    const overdue = ctx.invoices.filter((i) => i.status === 'overdue').length;

    setBar(company ? company.label : 'Billing', company ? `${ctx.player.job} · ${ctx.player.grade || 'Employee'}` : 'Personal account',
        `<span class="dot ${overdue ? 'red' : ''}"></span><p>Signed in as <b>${esc(ctx.player.name)}</b> · ${ctx.stats.open} unpaid ${ctx.stats.open === 1 ? 'bill' : 'bills'}</p><span class="ver">v${esc(ctx.settings.version)}</span>`);

    let side = `<div class="who"><div class="av">${initials(ctx.player.name)}</div><div class="who-txt"><b>${esc(ctx.player.name)}</b><span>${esc(ctx.player.job || 'Citizen')}${ctx.player.grade ? ' · ' + esc(ctx.player.grade) : ''}</span></div></div>
        <div class="shift"><span>Bank</span><b>${money(ctx.player.bank)}</b></div>
        <div class="shift" style="margin-bottom:6px"><span>Owed</span><b class="${ctx.stats.owed > 0 ? 'red' : 'teal'}">${money(ctx.stats.owed)}</b></div>`;
    side += navBtn('home', 'grid', 'Overview', S.tab === 'home');
    side += `<div class="grp">Personal</div>`;
    side += navBtn('bills', 'inbox', 'My bills', S.tab === 'bills', ctx.stats.open || '', overdue ? 'red' : '');
    side += navBtn('history', 'clock', 'History', S.tab === 'history');
    if (canCreate()) {
        side += `<div class="grp">${p.canBill ? 'Business' : 'Invoicing'}</div>`;
        side += navBtn('new', 'plus', 'New invoice', S.tab === 'new', S.order.items.length || '');
        if (p.canBill && company && company.quickBills?.length) side += navBtn('quick', 'bolt', 'Quick bills', S.tab === 'quick');
    }
    if (p.isBoss && company) {
        side += `<div class="grp">Management</div>`;
        side += navBtn('dash', 'chart', 'Dashboard', S.tab === 'dash');
        side += navBtn('cinvoices', 'list', 'Company invoices', S.tab === 'cinvoices');
        if (p.canManageCatalog) side += navBtn('catalog', 'box', 'Catalog', S.tab === 'catalog');
    }
    if (ctx.stats.toCollect > 0) {
        side += `<div class="side-foot"><div class="note amber"><b>Cash to collect</b>${money(ctx.stats.toCollect)} is waiting at any bank teller.</div></div>`;
    }
    $('#side').innerHTML = side;

    const keys = [['ESC', 'Close'], ['/', 'Search']];
    if (S.tab === 'new') keys.push(['↵', 'Send invoice']);
    setStatus(keys, `nayzeee-billing · <b>${esc(company ? company.shortName : 'personal')}</b>`);

    const views = { home: viewHome, bills: viewBills, history: viewHistory, new: viewNew, quick: viewQuick, dash: viewDash, cinvoices: viewCompanyInvoices, catalog: viewCatalog };
    (views[S.tab] || viewHome)();
}

function setTab(tab) {
    S.tab = tab;
    if (S.mode === 'billing') renderBilling();
    else if (S.mode === 'admin') renderAdmin();
}

async function refreshContext() {
    if (S.mode !== 'billing') return;
    const res = await api('getContext');
    if (!res.ok) return;
    const tab = S.tab;
    S.ctx = res.data;
    S.tab = tab;
    if (tab === 'history') S.history.rows = [];
    if (tab === 'cinvoices') S.boss.inv.rows = [];
    if (tab === 'dash') S.boss.dash = null;
    renderBilling();
}

// ═══════════════ HOME ═══════════════
function invoiceCard(inv, compact = false) {
    const due = dueLabel(inv);
    const urgent = inv.status === 'overdue' ? 'urgent' : inv.status === 'disputed' ? 'warn' : '';
    const progress = inv.amountPaid > 0 && inv.status !== 'paid'
        ? `<div class="progress"><i style="width:${Math.min(100, (inv.amountPaid / (inv.total + inv.lateFee)) * 100)}%"></i></div>` : '';
    const actions = [];
    actions.push(`<button class="btn-ghost" data-act="invoice" data-id="${esc(inv.id)}">Details</button>`);
    if (!compact && inv.direction === 'received' && isOpen(inv) && S.ctx?.perms?.canDispute) {
        actions.push(`<button class="btn-ghost danger" data-act="dispute" data-id="${esc(inv.id)}">${ic('flag')}Dispute</button>`);
    }
    if (inv.direction === 'received' && isOpen(inv)) {
        actions.push(`<button class="btn-teal" style="height:27px;padding:0 12px" data-act="pay" data-id="${esc(inv.id)}">${ic('card')}Pay</button>`);
    }
    return `<article class="inc ${urgent}">
        <div class="inc-top"><span>${statusTag(inv.status)}${due && inv.status !== 'overdue' ? ` <span class="chip ${due.cls}">${esc(due.text)}</span>` : ''}</span><span class="ref">${esc(inv.id)}</span></div>
        <div class="inc-main"><div style="min-width:0"><h3>${esc(inv.company)}</h3><p>${esc(itemSummary(inv.items))}</p></div>
            <div class="big">${money(inv.remaining)}${inv.remaining !== inv.total ? `<small>of ${money(inv.total + inv.lateFee)}</small>` : ''}</div></div>
        ${progress}
        <div class="meta"><span>From <b>${esc(inv.senderName)}</b></span><span>${esc(ago(inv.createdAt))}</span>
            ${inv.lateFee > 0 ? `<span>Late fee <b>${money(inv.lateFee)}</b></span>` : ''}
            <span class="actions">${actions.join('')}</span></div>
    </article>`;
}

function activityRow(inv) {
    const sent = inv.direction === 'sent';
    return `<div class="row click" data-act="invoice" data-id="${esc(inv.id)}">
        <div class="av" style="color:${sent ? 'var(--teal)' : 'var(--ink-2)'}">${ic(sent ? 'up' : 'down')}</div>
        <div class="row-txt"><b>${esc(sent ? inv.targetName : inv.company)}</b><span>${esc(inv.id)} · ${esc(ago(inv.createdAt))}</span></div>
        ${statusTag(inv.status)}<span class="amt ${sent ? 'teal' : ''}" style="min-width:76px;text-align:right">${sent ? '+' : '−'}${money(inv.total)}</span></div>`;
}

function viewHome() {
    const { ctx } = S;
    const unpaid = ctx.invoices.filter((i) => i.status !== 'disputed').slice(0, 3);
    const third = ctx.stats.toCollect > 0
        ? stat('cash', 'Cash to collect', money(ctx.stats.toCollect), 'amber')
        : stat('send', 'Invoices sent · 30 days', esc(ctx.stats.sent30), 'off');
    setMain(`
        <div class="head"><div><h1>${greeting()}, ${esc(firstName(ctx.player.name))}</h1>
            <p>Your bills, payments and recent invoice activity in one place.</p></div>${clockHtml()}</div>
        <div class="stats">
            ${stat('receipt', 'Outstanding', money(ctx.stats.owed), ctx.stats.owed > 0 ? 'red' : '')}
            ${stat('wallet', 'Paid · 30 days', money(ctx.stats.paid30))}
            ${third}
        </div>
        <div class="cols">
            <section class="panel"><div class="p-head"><div><h2>Unpaid bills</h2><p>${ctx.stats.open} open · ${money(ctx.stats.owed)} total</p></div>
                <button class="btn-ghost" data-act="tab" data-tab="bills">View all</button></div>
                <div class="p-body">${unpaid.length ? unpaid.map((i) => invoiceCard(i, true)).join('') : emptyState('check', "You're all caught up", 'New invoices sent to you will show up here.')}</div></section>
            <section class="panel"><div class="p-head"><div><h2>Recent activity</h2><p>Invoices you sent or received</p></div>
                <button class="btn-ghost" data-act="tab" data-tab="history">${ic('clock')}History</button></div>
                <div class="p-body">${ctx.recent.length ? ctx.recent.map(activityRow).join('') : emptyState('clock', 'No activity yet', 'Invoices you send or receive will appear here.')}</div></section>
        </div>`);
}

// ═══════════════ MY BILLS ═══════════════
function viewBills() {
    const all = S.ctx.invoices;
    const counts = { all: all.length, overdue: 0, partial: 0, disputed: 0 };
    all.forEach((i) => { if (counts[i.status] !== undefined) counts[i.status]++; });
    const list = S.billsFilter === 'all' ? all : all.filter((i) => i.status === S.billsFilter);
    const chip = (id, label) => `<button class="fchip ${S.billsFilter === id ? 'on' : ''}" data-act="billsFilter" data-f="${id}">${label}<span class="n">${counts[id]}</span></button>`;
    setMain(`
        <div class="head"><div><h1>My bills</h1><p>Pay in full or in installments, dispute anything that looks wrong.</p></div>
            <div class="head-actions"><button class="btn-ghost" data-act="refresh">${ic('refresh')}Refresh</button></div></div>
        <div class="toolbar"><div class="filters">${chip('all', 'All')}${chip('overdue', 'Overdue')}${chip('partial', 'Partial')}${chip('disputed', 'Disputed')}</div></div>
        <div class="lines" style="gap:9px">${list.length ? list.map((i) => invoiceCard(i)).join('') : emptyState('inbox', 'Nothing here', 'You have no bills in this category.')}</div>`);
}

// ═══════════════ HISTORY ═══════════════
const HIST_FILTERS = [['all', 'All'], ['received', 'Received'], ['sent', 'Sent'], ['open', 'Open'], ['paid', 'Paid'], ['cancelled', 'Cancelled']];

function invoiceTable(rows, { party = 'direction', company = true } = {}) {
    return `<table class="table"><thead><tr><th>Invoice</th><th>${party === 'direction' ? 'Party' : 'Customer'}</th>${company ? '<th>Company</th>' : '<th>Employee</th>'}<th>Date</th><th>Status</th><th class="r">Amount</th></tr></thead><tbody>
        ${rows.map((i) => {
            const partyCell = party === 'direction'
                ? `${i.direction === 'sent' ? '<span style="color:var(--teal)">To</span>' : 'From'} <b>${esc(i.direction === 'sent' ? i.targetName : i.senderName)}</b>`
                : `<b>${esc(i.targetName)}</b>`;
            return `<tr class="click" data-act="invoice" data-id="${esc(i.id)}"><td><b>${esc(i.id)}</b></td><td class="ell">${partyCell}</td>
                <td class="ell">${esc(company ? i.company : i.senderName)}</td><td>${esc(fmtDate(i.createdAt))}</td><td>${statusTag(i.status)}</td><td class="r"><b>${money(i.total + i.lateFee)}</b></td></tr>`;
        }).join('')}</tbody></table>`;
}

async function loadHistory(append = false) {
    const h = S.history;
    if (!append) { h.page = 0; h.rows = []; }
    h.loading = true;
    const data = await call('getHistory', { filter: h.filter, search: h.search, page: h.page });
    h.loading = false;
    if (!data) return;
    h.rows = append ? h.rows.concat(data.rows) : data.rows;
    h.hasMore = data.hasMore;
    if (S.tab === 'history') renderHistoryList();
}

function renderHistoryList() {
    const el = $('#historyList'); if (!el) return;
    const h = S.history;
    el.innerHTML = h.rows.length
        ? invoiceTable(h.rows) + (h.hasMore ? `<button class="btn-ghost more" data-act="historyMore">Load more</button>` : '')
        : (h.loading ? skeleton(4) : emptyState('clock', 'No invoices found', 'Try another filter or search term.'));
}

function viewHistory() {
    const h = S.history;
    setMain(`
        <div class="head"><div><h1>History</h1><p>Every invoice you have sent or received.</p></div></div>
        <div class="toolbar"><div class="filters">${HIST_FILTERS.map(([id, l]) => `<button class="fchip ${h.filter === id ? 'on' : ''}" data-act="historyFilter" data-f="${id}">${l}</button>`).join('')}</div>
            <label class="search">${ic('search')}<input data-input="historySearch" placeholder="Search invoice, name or company" value="${esc(h.search)}"></label></div>
        <section class="panel grow"><div class="p-body pad" id="historyList">${skeleton(4)}</div></section>`);
    if (!h.rows.length) loadHistory(); else renderHistoryList();
}

// ═══════════════ NEW INVOICE ═══════════════
function orderCompany() { return (S.ctx.perms.canBill && !S.order.personal) ? S.ctx.company : null; }
function orderTaxRate() { const c = orderCompany(); return c ? num(c.taxRate) : num(S.ctx.settings.defaultTaxRate); }
function allowCustom() { const c = orderCompany(); return !c || c.allowCustomItems; }

function productCard(p, qtyMap, act = 'addProduct') {
    const q = qtyMap[p.id] || 0;
    const fallback = ic('box');
    return `<button class="product" data-act="${act}" data-id="${esc(p.id)}">
        ${q ? `<span class="qty-badge">${q}</span>` : ''}
        <div class="img">${p.image ? `<img src="${esc(imgUrl(p.image))}" alt="" onerror="this.replaceWith(document.createRange().createContextualFragment(window.__boxIcon))">` : fallback}</div>
        <b>${esc(p.name)}</b><span>${money(p.price)}</span></button>`;
}
window.__boxIcon = ic('box');

function catalogFilters(categories, active, act) {
    return `<div class="filters"><button class="fchip ${active === 'all' ? 'on' : ''}" data-act="${act}" data-f="all">All</button>
        ${(categories || []).map((c) => `<button class="fchip ${active === c.id ? 'on' : ''}" data-act="${act}" data-f="${esc(c.id)}">${faIcon(c.icon)}${esc(c.label)}</button>`).join('')}</div>`;
}

function filteredProducts(company, category, search) {
    const q = (search || '').toLowerCase();
    return (company?.products || []).filter((p) => (category === 'all' || p.category === category) && (!q || p.name.toLowerCase().includes(q)));
}

function viewNew() {
    const { ctx, order } = S;
    const company = orderCompany();
    const both = ctx.perms.canBill && ctx.perms.canPersonal;

    const left = company ? `
        <section class="panel"><div class="p-head"><div><h2>Catalog</h2><p>${(company.products || []).length} products · prices set by ${esc(company.shortName)}</p></div>
            <label class="search" style="max-width:220px">${ic('search')}<input data-input="productSearch" placeholder="Search products" value="${esc(order.search)}"></label></div>
            <div class="p-body pad catalog">
                ${catalogFilters(company.categories, order.category, 'productCategory')}
                <div class="products" id="productGrid"></div>
                ${company.allowCustomItems ? customLineHtml() : ''}
            </div></section>`
        : `<section class="panel"><div class="p-head"><div><h2>Line items</h2><p>Personal invoices use custom items · ${pct(orderTaxRate())} tax</p></div></div>
            <div class="p-body pad">${customLineHtml()}
            <div class="note" style="margin-top:6px"><b>Personal invoice</b>Money goes straight to you once paid.${ctx.stats ? '' : ''} Cash payments may need to be collected at a bank teller.</div></div></section>`;

    setMain(`
        <div class="head"><div><h1>New invoice</h1><p>${company ? `Billing as <b style="color:var(--white);font-weight:500">${esc(company.label)}</b>.` : 'Send a personal invoice to another citizen.'} Prices are verified by the server.</p></div>
            ${both ? `<div class="seg" style="width:240px"><button class="${!order.personal ? 'on' : ''}" data-act="orderMode" data-m="company">${ic('building')}Company</button><button class="${order.personal ? 'on' : ''}" data-act="orderMode" data-m="personal">${ic('user')}Personal</button></div>` : ''}</div>
        <div class="cols order">
            ${left}
            <section class="panel"><div class="p-head"><div><h2>Order</h2><p>Recipient, items and terms</p></div>
                <button class="btn-ghost danger" data-act="clearOrder">${ic('trash')}Clear</button></div>
                <div class="p-body pad" style="gap:14px" id="orderBody"></div>
                <div class="p-foot" id="orderFoot"></div></section>
        </div>`);
    renderProducts();
    renderOrderBody();
    renderOrderFoot();
    if (!order.nearby.length) loadNearby();
}

function customLineHtml() {
    return `<div class="custom-line"><input class="input" id="customName" maxlength="60" placeholder="Custom item name">
        <input class="input" id="customPrice" type="number" min="0" step="0.01" placeholder="Price">
        <button class="btn-teal" data-act="addCustom">${ic('plus')}Add</button></div>`;
}

function qtyMap(items) { const m = {}; items.forEach((i) => { if (i.productId) m[i.productId] = (m[i.productId] || 0) + i.quantity; }); return m; }

function renderProducts() {
    const grid = $('#productGrid'); if (!grid) return;
    const company = orderCompany();
    const list = filteredProducts(company, S.order.category, S.order.search);
    const qm = qtyMap(S.order.items);
    grid.innerHTML = list.length ? list.map((p) => productCard(p, qm)).join('') : `<div style="grid-column:1/-1">${emptyState('box', 'No products', 'Nothing matches this filter.')}</div>`;
}

async function loadNearby() {
    const data = await call('getNearby');
    if (!data) return;
    S.order.nearby = data;
    if (S.tab === 'new') renderOrderBody();
}

function personRow(p, act) {
    const sub = p.type === 'offline' ? 'Offline · will be notified on login' : `ID ${p.id}${p.distance !== undefined ? ` · ${p.distance}m` : ''}`;
    const key = p.type === 'offline' ? `data-ident="${esc(p.identifier)}"` : `data-pid="${esc(p.id)}"`;
    return `<button class="mini" data-act="${act}" ${key} data-name="${esc(p.name)}"><div class="av">${initials(p.name)}</div><b>${esc(p.name)}</b><span>${esc(sub)}</span></button>`;
}

function renderOrderBody() {
    const el = $('#orderBody'); if (!el) return;
    const { order, ctx } = S;
    const company = orderCompany();
    let html = '<div class="field"><div class="label-row"><span>Bill to</span>';
    if (order.recipient) {
        html += `</div><div class="recipient"><div class="av">${initials(order.recipient.name)}</div><div class="row-txt"><b>${esc(order.recipient.name)}</b>
            <span>${order.recipient.type === 'offline' ? 'Offline citizen' : 'ID ' + esc(order.recipient.id)}</span></div>
            <button class="icon-btn" data-act="clearRecipient">${ic('x')}</button></div></div>`;
    } else {
        html += `<button class="btn-ghost" style="height:22px" data-act="nearby">${ic('refresh')}Nearby</button></div>
            <label class="search">${ic('search')}<input data-input="playerSearch" placeholder="${ctx.perms.canRemote ? 'Name, ID or citizen ID' : 'Name or server ID'}" value="${esc(order.query)}"></label>
            <div class="results" id="playerResults">${playerResultsHtml()}</div></div>`;
    }

    html += `<div class="field"><div class="label-row"><span>Items</span><span>${order.items.length} line${order.items.length === 1 ? '' : 's'}</span></div><div class="lines">`;
    html += order.items.length ? order.items.map((it, idx) => `<div class="line"><div class="row-txt"><b>${esc(it.name)}</b><span>${money(it.price)} each${it.custom ? ' · custom' : ''}</span></div>
        <div class="stepper"><button data-act="qty" data-i="${idx}" data-d="-1">${ic('minus')}</button><span>${it.quantity}</span><button data-act="qty" data-i="${idx}" data-d="1">${ic('plus')}</button></div>
        <span class="amt" style="min-width:64px;text-align:right">${money(it.price * it.quantity)}</span></div>`).join('')
        : `<div class="empty" style="padding:18px">${ic('receipt')}<span>Pick products from the catalog${allowCustom() ? ' or add a custom item' : ''}.</span></div>`;
    html += '</div></div>';

    const extras = [];
    if (company && company.allowDiscounts) {
        extras.push(`<div class="field"><label>Discount % (max ${esc(company.maxDiscount)})</label><input type="number" min="0" max="${esc(company.maxDiscount)}" data-input="discount" value="${esc(order.discount || '')}" placeholder="0"></div>`);
    }
    if (ctx.settings.customDue) {
        const def = ctx.settings.dueDays;
        let opts = `<option value="">Default (${esc(def)} days)</option>`;
        for (let d = 1; d <= ctx.settings.maxDueDays; d++) opts += `<option value="${d}" ${String(order.dueDays) === String(d) ? 'selected' : ''}>${d} day${d > 1 ? 's' : ''}</option>`;
        extras.push(`<div class="field"><label>Due in</label><select data-change="dueDays">${opts}</select></div>`);
    }
    if (extras.length) html += `<div class="${extras.length > 1 ? 'grid2' : ''}">${extras.join('')}</div>`;
    html += `<div class="field"><label>Notes (shown on the invoice)</label><textarea data-input="notes" maxlength="${esc(ctx.settings.maxNote)}" placeholder="Optional reason, plate, case number...">${esc(order.notes)}</textarea></div>`;
    el.innerHTML = html;
}

function playerResultsHtml() {
    const { order } = S;
    const list = order.query ? order.results : order.nearby;
    if (!list.length) {
        return `<div class="label-row" style="padding:6px 2px">${order.query ? 'No citizens found' : 'Nobody nearby · search by name or ID'}</div>`;
    }
    return list.map((p) => personRow({ ...p, type: p.type || 'online' }, 'pickRecipient')).join('');
}

function renderOrderFoot() {
    const el = $('#orderFoot'); if (!el) return;
    const t = calcTotals(S.order.items, S.order.discount, orderTaxRate());
    el.innerHTML = `<div class="totals"><div><span>Subtotal</span><b>${money(t.subtotal)}</b></div>
        ${t.discount > 0 ? `<div class="neg"><span>Discount (${esc(S.order.discount)}%)</span><b>−${money(t.discount)}</b></div>` : ''}
        <div><span>Tax (${pct(orderTaxRate())})</span><b>${money(t.tax)}</b></div>
        <div class="grand"><span>Total</span><b>${money(t.total)}</b></div></div>
        <button class="btn-teal btn-lg btn-block" data-act="sendInvoice" ${!S.order.recipient || !S.order.items.length ? 'disabled' : ''}>${ic('send')}Send invoice</button>`;
}

function updateOrder() {
    renderOrderBody(); renderOrderFoot(); renderProducts();
    const tally = document.querySelector('.nav[data-tab="new"] .tally');
    const n = S.order.items.length;
    if (tally) tally.textContent = n || ''; else if (n) { const nav = document.querySelector('.nav[data-tab="new"]'); if (nav) nav.insertAdjacentHTML('beforeend', `<span class="tally">${n}</span>`); }
}

function addLine(line) {
    const max = S.ctx?.settings?.maxQuantity || 100;
    const key = line.productId ? 'productId' : line.quickBillId ? 'quickBillId' : null;
    const existing = key ? S.order.items.find((i) => i[key] === line[key]) : null;
    if (existing) existing.quantity = Math.min(max, existing.quantity + 1);
    else {
        if (S.order.items.length >= (S.ctx?.settings?.maxItems || 30)) { toast('Limit reached', 'Too many items on one invoice', 'warning'); return; }
        S.order.items.push({ ...line, quantity: 1 });
    }
}

async function sendInvoice() {
    const { order } = S;
    if (!order.recipient || !order.items.length) return;
    const btn = $('[data-act="sendInvoice"]'); if (btn) btn.disabled = true;
    const target = order.recipient.type === 'offline' ? { type: 'offline', identifier: order.recipient.identifier } : { type: 'online', id: order.recipient.id };
    const data = await call('createInvoice', {
        target, personal: order.personal, discount: num(order.discount), notes: order.notes, dueDays: order.dueDays ? num(order.dueDays) : null,
        items: order.items.map((i) => i.productId ? { productId: i.productId, quantity: i.quantity }
            : i.quickBillId ? { quickBillId: i.quickBillId, quantity: i.quantity }
                : { name: i.name, price: i.price, quantity: i.quantity }),
    });
    if (btn) btn.disabled = false;
    if (!data) return;
    toast('Invoice sent', `${data.invoiceId} · ${money(data.total)} to ${data.targetName}`, 'success');
    const keep = { personal: order.personal, nearby: order.nearby };
    S.order = Object.assign(newOrder(), keep);
    refreshContext();
}

// ═══════════════ QUICK BILLS ═══════════════
function viewQuick() {
    const company = S.ctx.company;
    setMain(`
        <div class="head"><div><h1>Quick bills</h1><p>One-click presets for ${esc(company.label)}. Picking one adds it to your current order.</p></div></div>
        <div class="quickbills">${(company.quickBills || []).map((q) => `<button class="quick" data-act="addQuick" data-id="${esc(q.id)}">
            <div class="tile">${ic('bolt')}</div><div class="row-txt"><b>${esc(q.label)}</b><span>${esc(q.description || 'Quick bill')}</span></div><span class="amt teal">${money(q.amount)}</span></button>`).join('')}</div>`);
}

// ═══════════════ BOSS DASHBOARD ═══════════════
function chartHtml(days) {
    const max = Math.max(1, ...days.map((d) => d.value));
    const today = days.length - 1;
    return `<div class="chart" role="img" aria-label="Revenue per day: ${esc(days.map((d) => `${d.label} ${money(d.value)}`).join(', '))}">
        <div class="gridline" style="bottom:calc(24px + (100% - 24px) * .5)"></div><div class="gridline" style="top:8px"></div>
        ${days.map((d, i) => `<div class="col ${i === today ? 'today' : ''}"><div class="tip"><b>${money(d.value)}</b>${esc(d.key)} · ${d.count || 0} payment${d.count === 1 ? '' : 's'}</div>
            <div class="bar-v ${d.value <= 0 ? 'zero' : ''}" style="height:calc((100% - 24px) * ${Math.max(0.012, d.value / max)})"></div><span>${esc(i === today ? 'Today' : d.label)}</span></div>`).join('')}
    </div>`;
}

function leaderboardHtml(rows) {
    if (!rows.length) return emptyState('users', 'No sales yet', 'Employee performance shows up after the first invoices.');
    return rows.map((r, i) => `<div class="row"><span class="rank">${i + 1}</span><div class="av">${initials(r.name)}</div>
        <div class="row-txt"><b>${esc(r.name)}</b><span>${r.invoices} invoice${r.invoices === 1 ? '' : 's'}${r.tips > 0 ? ` · ${money(r.tips)} tips` : ''}</span></div><span class="amt">${money(r.collected)}</span></div>`).join('');
}

async function viewDash() {
    const company = S.ctx.company;
    if (!S.boss.dash) {
        setMain(`<div class="head"><div><h1>${esc(company.label)}</h1><p>Loading company performance...</p></div></div><div class="lines">${skeleton(5)}</div>`);
        const data = await call('boss:getDashboard');
        if (!data || S.tab !== 'dash') return;
        S.boss.dash = data;
    }
    const d = S.boss.dash;
    const balance = d.balance !== undefined && d.balance !== null
        ? `<div class="shift" style="gap:16px;margin:0;padding:9px 14px"><span>Company account</span><b class="teal" style="font-size:15px">${money(d.balance)}</b></div>` : '';
    setMain(`
        <div class="head"><div><h1>${esc(company.label)}</h1><p>Revenue, outstanding balances and employee performance.</p></div>
            <div class="head-actions">${balance}<button class="icon-btn" data-act="dashRefresh" title="Refresh">${ic('refresh')}</button></div></div>
        <div class="stats four">
            ${stat('chart', 'Today', money(d.today))}
            ${stat('clock', 'Last 7 days', money(d.week))}
            ${stat('wallet', 'Last 30 days', money(d.month))}
            ${stat('receipt', `Outstanding · ${d.openCount} open`, money(d.outstanding), d.overdueCount ? 'red' : 'off')}
        </div>
        ${(d.disputedCount || d.overdueCount) ? `<div class="toolbar">
            ${d.disputedCount ? `<button class="fchip" data-act="bossFilter" data-f="disputed"><span class="dot amber"></span>${d.disputedCount} disputed invoice${d.disputedCount > 1 ? 's' : ''} need review</button>` : ''}
            ${d.overdueCount ? `<button class="fchip" data-act="bossFilter" data-f="overdue"><span class="dot red"></span>${d.overdueCount} overdue</button>` : ''}</div>` : ''}
        <div class="cols">
            <section class="panel"><div class="p-head"><div><h2>Revenue · last 7 days</h2><p>Net payments received per day</p></div><span class="ref">avg ticket ${money(d.avgTicket)}</span></div>
                <div class="p-body pad">${chartHtml(d.daily)}</div></section>
            <section class="panel"><div class="p-head"><div><h2>Top employees</h2><p>Collected in the last 30 days</p></div></div>
                <div class="p-body">${leaderboardHtml(d.leaderboard)}</div></section>
        </div>
        <section class="panel"><div class="p-head"><div><h2>Recent invoices</h2><p>${d.invoices30} invoices in the last 30 days · ${money(d.tips)} in tips</p></div>
            <button class="btn-ghost" data-act="tab" data-tab="cinvoices">View all</button></div>
            <div class="p-body pad">${d.recent.length ? invoiceTable(d.recent, { party: 'customer', company: false }) : emptyState('receipt', 'No invoices yet', 'Invoices from your employees will show up here.')}</div></section>`);
}

// ═══════════════ COMPANY INVOICES ═══════════════
const BOSS_FILTERS = [['open', 'Open'], ['overdue', 'Overdue'], ['disputed', 'Disputed'], ['paid', 'Paid'], ['closed', 'Closed'], ['all', 'All']];

async function loadBossInvoices(append = false) {
    const b = S.boss.inv;
    if (!append) { b.page = 0; b.rows = []; }
    const data = await call('boss:getInvoices', { status: b.status, search: b.search, page: b.page });
    if (!data) return;
    b.rows = append ? b.rows.concat(data.rows) : data.rows;
    b.hasMore = data.hasMore; b.loaded = true;
    renderBossList();
}
function renderBossList() {
    const el = $('#bossList'); if (!el) return;
    const b = S.boss.inv;
    el.innerHTML = b.rows.length ? invoiceTable(b.rows, { party: 'customer', company: false }) + (b.hasMore ? `<button class="btn-ghost more" data-act="bossMore">Load more</button>` : '')
        : (b.loaded ? emptyState('list', 'No invoices', 'Nothing matches this filter.') : skeleton(4));
}
function viewCompanyInvoices() {
    const b = S.boss.inv;
    setMain(`
        <div class="head"><div><h1>Company invoices</h1><p>Review, cancel, refund and resolve disputes for ${esc(S.ctx.company.label)}.</p></div></div>
        <div class="toolbar"><div class="filters">${BOSS_FILTERS.map(([id, l]) => `<button class="fchip ${b.status === id ? 'on' : ''}" data-act="bossFilter" data-f="${id}">${l}</button>`).join('')}</div>
            <label class="search">${ic('search')}<input data-input="bossSearch" placeholder="Search invoice, employee or customer" value="${esc(b.search)}"></label></div>
        <section class="panel grow"><div class="p-body pad" id="bossList">${skeleton(4)}</div></section>`);
    b.loaded = false;
    loadBossInvoices();
}

// ═══════════════ CATALOG (boss + admin) ═══════════════
function catalogCompany() {
    if (S.mode === 'admin') return (S.admin.data.companies || []).find((c) => c.id === S.admin.catalogCompany) || null;
    return S.ctx.company;
}
function catalogEditorHtml(company) {
    const t = S.boss.catTab;
    const seg = `<div class="seg" style="width:360px">
        <button class="${t === 'products' ? 'on' : ''}" data-act="catTab" data-t="products">${ic('box')}Products</button>
        <button class="${t === 'categories' ? 'on' : ''}" data-act="catTab" data-t="categories">${ic('tag')}Categories</button>
        <button class="${t === 'quick' ? 'on' : ''}" data-act="catTab" data-t="quick">${ic('bolt')}Quick bills</button></div>`;
    const addLabel = t === 'products' ? 'Add product' : t === 'categories' ? 'Add category' : 'Add quick bill';
    let body = '';
    const catName = (id) => (company.categories || []).find((c) => c.id === id)?.label || '—';
    if (t === 'products') {
        body = company.products.length ? `<table class="table"><thead><tr><th></th><th>Product</th><th>Category</th><th>ID</th><th class="r">Price</th><th></th></tr></thead><tbody>
            ${company.products.map((p) => `<tr><td style="width:44px"><div class="product" style="padding:0;border:0;background:none"><div class="img" style="width:32px;height:32px">${p.image ? `<img src="${esc(imgUrl(p.image))}" alt="" style="max-width:26px;max-height:26px">` : ic('box')}</div></div></td>
                <td><b>${esc(p.name)}</b></td><td>${esc(catName(p.category))}</td><td class="ref">${esc(p.id)}</td><td class="r"><b>${money(p.price)}</b></td>
                <td class="r"><span style="display:inline-flex;gap:6px"><button class="icon-btn" data-act="editProduct" data-id="${esc(p.id)}">${ic('edit')}</button><button class="icon-btn danger" data-act="deleteProduct" data-id="${esc(p.id)}">${ic('trash')}</button></span></td></tr>`).join('')}
            </tbody></table>` : emptyState('box', 'No products yet', 'Add products so employees can bill with fixed prices.');
    } else if (t === 'categories') {
        body = company.categories.length ? `<div class="lines">${company.categories.map((c) => `<div class="row"><div class="av">${faIcon(c.icon) || ic('tag')}</div>
            <div class="row-txt"><b>${esc(c.label)}</b><span>${esc(c.id)} · ${company.products.filter((p) => p.category === c.id).length} products</span></div>
            <button class="icon-btn" data-act="editCategory" data-id="${esc(c.id)}">${ic('edit')}</button><button class="icon-btn danger" data-act="deleteCategory" data-id="${esc(c.id)}">${ic('trash')}</button></div>`).join('')}</div>`
            : emptyState('tag', 'No categories', 'Categories group products in the catalog.');
    } else {
        body = company.quickBills.length ? `<div class="lines">${company.quickBills.map((q) => `<div class="row"><div class="tile">${ic('bolt')}</div>
            <div class="row-txt"><b>${esc(q.label)}</b><span>${esc(q.description || 'No description')}</span></div><span class="amt teal">${money(q.amount)}</span>
            <button class="icon-btn" data-act="editQuick" data-id="${esc(q.id)}">${ic('edit')}</button><button class="icon-btn danger" data-act="deleteQuick" data-id="${esc(q.id)}">${ic('trash')}</button></div>`).join('')}</div>`
            : emptyState('bolt', 'No quick bills', 'Quick bills are one-click presets for common charges.');
    }
    return `<div class="toolbar">${seg}<button class="btn-teal" style="margin-left:auto" data-act="catAdd">${ic('plus')}${addLabel}</button></div>
        <section class="panel grow"><div class="p-body pad">${body}</div></section>`;
}
function viewCatalog() {
    const company = S.ctx.company;
    setMain(`<div class="head"><div><h1>Catalog</h1><p>Products, categories and quick bills for ${esc(company.label)}. Changes apply instantly.</p></div></div>
        <div id="catalogEditor" style="display:flex;flex-direction:column;gap:14px;flex:1;min-height:0">${catalogEditorHtml(company)}</div>`);
}
function rerenderCatalog() {
    const el = $('#catalogEditor'); const company = catalogCompany();
    if (el && company) el.innerHTML = catalogEditorHtml(company);
}
function applyCatalogResult(company) {
    if (!company || typeof company !== 'object') return;
    if (S.mode === 'admin') {
        const list = S.admin.data.companies; const i = list.findIndex((c) => c.id === company.id);
        if (i >= 0) list[i] = company; else list.push(company);
    } else {
        S.ctx.company = Object.assign({}, S.ctx.company, company);
    }
    rerenderCatalog();
}

async function ensureItems() {
    if (S.items) return S.items;
    const data = await call('getItems');
    S.items = Array.isArray(data) ? data : [];
    return S.items;
}

function productModal(company, product) {
    const p = product || {};
    const cats = `<option value="">No category</option>` + (company.categories || []).map((c) => `<option value="${esc(c.id)}" ${p.category === c.id ? 'selected' : ''}>${esc(c.label)}</option>`).join('');
    const m = openModal(`<div class="modal wide">
        ${modalHead('box', product ? 'Edit product' : 'Add product', esc(company.label))}
        <div class="modal-b"><div class="grid2"><div class="field"><label>Name</label><input id="pName" maxlength="60" value="${esc(p.name)}" autofocus></div>
            <div class="field"><label>Price</label><input id="pPrice" type="number" min="0" step="0.01" value="${esc(p.price)}"></div></div>
            <div class="grid2"><div class="field"><label>Category</label><select id="pCat">${cats}</select></div>
            <div class="field"><label>Image (item name)</label><input id="pImage" maxlength="60" value="${esc(p.image)}" placeholder="e.g. burger" data-input="itemSearch"></div></div>
            <div class="field"><label>Inventory items</label><div class="results" id="itemResults" style="max-height:150px"><div class="label-row">Type in the image field to search items</div></div></div></div>
        <div class="modal-f"><button class="btn-line" data-act="modalClose">Cancel</button><button class="btn-teal" data-act="modalOk">${ic('check')}Save product</button></div></div>`);
    ensureItems();
    m.ok = async () => {
        const data = await call('catalog:saveProduct', { companyId: company.id, product: {
            id: p.id, name: $('#pName', m.el).value, price: num($('#pPrice', m.el).value), category: $('#pCat', m.el).value, image: $('#pImage', m.el).value.trim(),
        } });
        if (!data) return;
        m.close(); applyCatalogResult(data); toast('Saved', 'Product saved', 'success');
    };
}
function categoryModal(company, cat) {
    const c = cat || {};
    const m = openModal(`<div class="modal">
        ${modalHead('tag', cat ? 'Edit category' : 'Add category', esc(company.label))}
        <div class="modal-b"><div class="field"><label>Name</label><input id="cLabel" maxlength="40" value="${esc(c.label)}" autofocus></div>
            <div class="field"><label>Font Awesome icon</label><input id="cIcon" maxlength="40" value="${esc(c.icon)}" placeholder="fa-burger"><span class="hint">Any free solid icon name from fontawesome.com</span></div></div>
        <div class="modal-f"><button class="btn-line" data-act="modalClose">Cancel</button><button class="btn-teal" data-act="modalOk">${ic('check')}Save</button></div></div>`);
    m.ok = async () => {
        const data = await call('catalog:saveCategory', { companyId: company.id, category: { id: c.id, label: $('#cLabel', m.el).value, icon: $('#cIcon', m.el).value } });
        if (!data) return; m.close(); applyCatalogResult(data);
    };
}
function quickModal(company, quick) {
    const q = quick || {};
    const m = openModal(`<div class="modal">
        ${modalHead('bolt', quick ? 'Edit quick bill' : 'Add quick bill', esc(company.label))}
        <div class="modal-b"><div class="field"><label>Name</label><input id="qLabel" maxlength="60" value="${esc(q.label)}" autofocus></div>
            <div class="field"><label>Amount</label><input id="qAmount" type="number" min="0" step="0.01" value="${esc(q.amount)}"></div>
            <div class="field"><label>Description</label><input id="qDesc" maxlength="120" value="${esc(q.description)}"></div></div>
        <div class="modal-f"><button class="btn-line" data-act="modalClose">Cancel</button><button class="btn-teal" data-act="modalOk">${ic('check')}Save</button></div></div>`);
    m.ok = async () => {
        const data = await call('catalog:saveQuickBill', { companyId: company.id, quickBill: { id: q.id, label: $('#qLabel', m.el).value, amount: num($('#qAmount', m.el).value), description: $('#qDesc', m.el).value } });
        if (!data) return; m.close(); applyCatalogResult(data);
    };
}

// ═══════════════ INVOICE DETAIL ═══════════════
async function openInvoice(id) {
    const inv = await call('getInvoice', { invoiceId: id });
    if (!inv) return;
    const due = dueLabel(inv);
    const owe = S.mode === 'billing' && inv.direction === 'received' && isOpen(inv);
    const kv = [
        ['From', `${inv.senderName}${inv.company !== 'Personal' ? ' · ' + inv.company : ''}`],
        ['To', inv.targetName],
        ['Created', fmtDate(inv.createdAt)],
        inv.paidAt ? ['Paid', fmtDate(inv.paidAt)] : ['Due', inv.dueDate ? `${fmtDate(inv.dueDate)}${due ? ' · ' + due.text : ''}` : '—'],
    ];
    const items = `<table class="table"><thead><tr><th>Item</th><th class="r">Qty</th><th class="r">Price</th><th class="r">Total</th></tr></thead><tbody>
        ${inv.items.map((i) => `<tr><td><b>${esc(i.name)}</b>${i.custom ? ' <span class="chip off">custom</span>' : ''}</td><td class="r">${esc(i.quantity)}</td><td class="r">${money(i.price)}</td><td class="r"><b>${money(i.price * i.quantity)}</b></td></tr>`).join('')}</tbody></table>`;
    const totals = `<div class="totals"><div><span>Subtotal</span><b>${money(inv.subtotal)}</b></div>
        ${inv.discount > 0 ? `<div class="neg"><span>Discount</span><b>−${money(inv.discount)}</b></div>` : ''}
        <div><span>Tax</span><b>${money(inv.tax)}</b></div>
        ${inv.lateFee > 0 ? `<div class="fee"><span>Late fee</span><b>${money(inv.lateFee)}</b></div>` : ''}
        ${inv.amountPaid > 0 ? `<div class="neg"><span>Paid</span><b>−${money(inv.amountPaid)}</b></div>` : ''}
        ${inv.tip > 0 ? `<div><span>Tips</span><b>${money(inv.tip)}</b></div>` : ''}
        <div class="grand"><span>${isOpen(inv) || inv.status === 'disputed' ? 'Remaining' : 'Total'}</span><b>${money(isOpen(inv) || inv.status === 'disputed' ? inv.remaining : inv.total + inv.lateFee)}</b></div></div>`;
    const notes = [
        inv.notes ? `<div class="note"><b>Notes</b>${esc(inv.notes)}</div>` : '',
        inv.disputeReason ? `<div class="note amber"><b>Dispute reason</b>${esc(inv.disputeReason)}</div>` : '',
        inv.cancelReason ? `<div class="note red"><b>${inv.status === 'refunded' ? 'Refund' : 'Cancellation'} reason</b>${esc(inv.cancelReason)}</div>` : '',
    ].join('');
    const payments = (inv.payments || []).length ? `<div class="field"><label>Payments</label><div class="timeline">${inv.payments.map((p) => `<div class="tl ${p.kind === 'refund' ? 'refund' : ''}">
        <div><b>${money(Math.abs(p.amount))}</b> ${p.kind === 'refund' ? 'refunded' : p.kind === 'autocollect' ? 'auto-collected' : 'paid'} ${p.kind === 'refund' ? 'to' : 'by'} ${esc(p.payer || '—')} · ${esc(p.method)}${num(p.tip) > 0 ? ` · ${money(p.tip)} tip` : ''}</div><span>${esc(fmtDate(p.createdAt))}</span></div>`).join('')}</div></div>` : '';

    const left = [];
    if (inv.amountPaid > 0 || inv.status === 'paid') left.push(`<button class="btn-line" data-act="receiptFromDetail">${ic('receipt')}Receipt</button>`);
    if (inv.canCancel) left.push(`<button class="btn-red" data-act="cancelInvoice" data-id="${esc(inv.id)}">Cancel invoice</button>`);
    if (inv.canRefund) left.push(`<button class="btn-red" data-act="refund" data-id="${esc(inv.id)}">${ic('undo')}Refund</button>`);
    const right = [];
    if (inv.canResolve) {
        right.push(`<button class="btn-line" data-act="resolve" data-id="${esc(inv.id)}" data-a="reinstate">Reject dispute</button>`);
        right.push(`<button class="btn-teal" data-act="resolve" data-id="${esc(inv.id)}" data-a="cancel">Accept · cancel invoice</button>`);
    }
    if (owe && S.ctx?.perms?.canDispute) right.push(`<button class="btn-line" data-act="dispute" data-id="${esc(inv.id)}">${ic('flag')}Dispute</button>`);
    if (owe) right.push(`<button class="btn-teal" data-act="pay" data-id="${esc(inv.id)}">${ic('card')}Pay ${money(inv.remaining)}</button>`);
    if (!right.length) right.push(`<button class="btn-line" data-act="modalClose">Close</button>`);

    const m = openModal(`<div class="modal xwide">
        ${modalHead('receipt', `${esc(inv.id)} &nbsp;${statusTag(inv.status)}`, `${esc(inv.company)} · ${esc(fmtDate(inv.createdAt))}`)}
        <div class="modal-b"><div class="kv">${kv.map(([k, v]) => `<div><span>${esc(k)}</span><b>${esc(v)}</b></div>`).join('')}</div>
            ${items}${totals}${notes}${payments}</div>
        <div class="modal-f"><div class="left">${left.join('')}</div>${right.join('')}</div></div>`);
    m.invoice = inv;
}

// ═══════════════ PAY ═══════════════
function findInvoice(id) {
    const fromCtx = S.ctx?.invoices?.find((i) => i.id === id);
    if (fromCtx) return fromCtx;
    for (const m of modalStack) if (m.invoice && m.invoice.id === id) return m.invoice;
    return null;
}

async function openPay(id) {
    let inv = findInvoice(id);
    if (!inv) inv = await call('getInvoice', { invoiceId: id });
    if (!inv) return;
    const st = S.ctx.settings;
    const methods = Object.entries(st.methods || { bank: true }).filter(([, v]) => v).map(([k]) => k);
    const tipsOk = st.tips && inv.tipsAllowed;
    const partialOk = st.allowPartial && inv.remaining > st.minPartial;
    const state = { method: methods[0] || 'bank', full: true, amount: inv.remaining, tipPct: 0, tipCustom: null };

    const m = openModal(`<div class="modal wide">
        ${modalHead('card', `Pay ${esc(inv.id)}`, `${esc(inv.company)} · ${esc(inv.senderName)}`)}
        <div class="modal-b" id="payBody"></div>
        <div class="modal-f"><span class="ref" style="margin-right:auto" id="payNote"></span><button class="btn-line" data-act="modalClose">Cancel</button>
            <button class="btn-teal" data-act="modalOk" id="payBtn">${ic('check')}Confirm payment</button></div></div>`);

    const render = () => {
        const amount = state.full ? inv.remaining : round2(Math.min(inv.remaining, Math.max(0, num(state.amount))));
        const tip = tipsOk ? round2(state.tipCustom !== null ? num(state.tipCustom) : inv.total * state.tipPct / 100) : 0;
        const charge = round2(amount + tip);
        const bal = state.method === 'cash' ? S.ctx.player.cash : S.ctx.player.bank;
        $('#payBody', m.el).innerHTML = `
            <div class="kv"><div><span>Invoice total</span><b>${money(inv.total + inv.lateFee)}</b></div><div><span>Remaining</span><b>${money(inv.remaining)}</b></div></div>
            <div class="field"><label>Pay with</label><div class="seg big">${methods.map((k) => `<button class="${state.method === k ? 'on' : ''}" data-act="payMethod" data-m="${k}">${ic(k === 'cash' ? 'cash' : 'card')}${k === 'cash' ? 'Cash' : 'Bank'}<small>${money(k === 'cash' ? S.ctx.player.cash : S.ctx.player.bank)}</small></button>`).join('')}</div></div>
            ${partialOk ? `<div class="field"><label>Amount</label><div class="seg"><button class="${state.full ? 'on' : ''}" data-act="payFull" data-v="1">Full amount</button><button class="${!state.full ? 'on' : ''}" data-act="payFull" data-v="0">Installment</button></div>
                ${!state.full ? `<input type="number" min="${esc(st.minPartial)}" max="${esc(inv.remaining)}" step="0.01" data-input="payAmount" value="${esc(state.amount)}" style="margin-top:8px"><span class="hint">Minimum ${money(Math.min(st.minPartial, inv.remaining))}</span>` : ''}</div>` : ''}
            ${tipsOk ? `<div class="field"><label>Add a tip</label><div class="tips">${st.tips.map((t) => `<button class="${state.tipCustom === null && state.tipPct === t ? 'on' : ''}" data-act="payTip" data-v="${t}">${t ? t + '%' : 'No tip'}</button>`).join('')}</div></div>` : ''}
            <div class="paybox"><div><span>You pay</span>${tip > 0 ? `<span style="display:block">incl. ${money(tip)} tip</span>` : ''}</div><b>${money(charge)}</b></div>`;
        $('#payNote', m.el).textContent = bal < charge ? 'Insufficient balance' : '';
        $('#payNote', m.el).style.color = 'var(--red)';
        $('#payBtn', m.el).disabled = bal < charge || amount <= 0;
        state.computed = { amount, tip };
    };
    m.payState = state; m.render = render;
    render();
    m.ok = async () => {
        const btn = $('#payBtn', m.el); btn.disabled = true;
        const res = await call('payInvoice', { invoiceId: inv.id, method: state.method, amount: state.full ? null : state.computed.amount, tip: state.computed.tip });
        btn.disabled = false;
        if (!res) return;
        m.close();
        modalStack.filter((x) => x.invoice && x.invoice.id === inv.id).forEach((x) => x.close());
        toast(res.status === 'paid' ? 'Invoice paid' : 'Installment paid', `${money(res.charged)} paid with ${res.method}${res.status !== 'paid' ? ` · ${money(res.remaining)} left` : ''}`, 'success');
        if (res.receipt) showReceipt(res.receipt);
        refreshContext();
    };
}

// ═══════════════ RECEIPT ═══════════════
function barcode(id) {
    let x = 4; let bars = '';
    const s = String(id || 'INV');
    for (let i = 0; i < s.length * 3 && x < 196; i++) {
        const c = s.charCodeAt(i % s.length) + i * 7;
        const w = 1 + (c % 3); const gap = 1 + ((c >> 2) % 3);
        bars += `<rect x="${x}" y="2" width="${w}" height="34" fill="currentColor"/>`;
        x += w + gap;
    }
    return `<svg class="barcode" viewBox="0 0 200 38" preserveAspectRatio="none" style="color:var(--ink-2)">${bars}</svg>`;
}

function showReceipt(inv, onClose) {
    const stamp = { paid: ['PAID', ''], partial: ['PARTIAL', 'amber'], refunded: ['REFUNDED', 'red'], cancelled: ['VOID', 'red'], overdue: ['OVERDUE', 'red'], pending: ['UNPAID', 'amber'], disputed: ['DISPUTED', 'amber'] }[inv.status] || ['', ''];
    openModal(`<div class="receipt"><div class="receipt-paper">
        ${stamp[0] ? `<div class="stamp ${stamp[1]}">${stamp[0]}</div>` : ''}
        <div class="r-head"><div class="mark"></div><h3>${esc(inv.company)}</h3><p>${esc(inv.id)}</p><p>${esc(fmtDate(inv.paidAt || inv.createdAt))}</p></div>
        <div class="r-items">${(inv.items || []).map((i) => `<div class="r-item"><span>${esc(i.quantity)}× ${esc(i.name)}</span><b>${money(i.price * i.quantity)}</b></div>`).join('')}</div>
        <div class="r-tot"><div><span>Subtotal</span><b>${money(inv.subtotal)}</b></div>
            ${inv.discount > 0 ? `<div><span>Discount</span><b>−${money(inv.discount)}</b></div>` : ''}
            <div><span>Tax</span><b>${money(inv.tax)}</b></div>
            ${inv.lateFee > 0 ? `<div><span>Late fee</span><b>${money(inv.lateFee)}</b></div>` : ''}
            ${inv.tip > 0 ? `<div><span>Tip</span><b>${money(inv.tip)}</b></div>` : ''}
            <div class="grand"><span>Total paid</span><b>${money(num(inv.amountPaid) + num(inv.tip))}</b></div></div>
        <div class="r-foot"><p>Served by ${esc(inv.senderName)} · billed to ${esc(inv.targetName)}</p>${barcode(inv.id)}<p>${esc(inv.footer || 'Thank you for your business!')}</p></div>
        </div><div class="modal-f"><button class="btn-teal btn-block" data-act="modalClose">${ic('check')}Done</button></div></div>`,
        { onClose: () => { if (onClose) onClose(); else if (S.mode === 'receipt') { S.mode = null; nui(S.receiptClose || 'close'); S.receiptClose = null; } } });
}

// ═══════════════════════════════════════════════════════════════
// ADMIN
// ═══════════════════════════════════════════════════════════════
function openAdmin(data) {
    S.admin.data = data;
    S.currency = S.currency || '$';
    S.imagePath = data.system?.imagePath || S.imagePath;
    S.tab = 'overview';
    S.admin.catalogCompany = S.admin.catalogCompany || data.companies[0]?.id || null;
    showShell('admin');
    renderAdmin();
}

function renderAdmin() {
    const d = S.admin.data;
    setBar('Billing Admin', 'Server management', `<span class="dot"></span><p><b>${d.companies.length}</b> companies · <b>${d.registers.length}</b> registers · banking <b>${esc(d.system.banking)}</b></p><span class="ver">v${esc(d.system.version)}</span>`);
    $('#side').innerHTML = `<div class="who"><div class="av" style="color:var(--teal)">${ic('shield')}</div><div class="who-txt"><b>Administrator</b><span>Full billing access</span></div></div>
        ${navBtn('overview', 'grid', 'Overview', S.tab === 'overview')}
        <div class="grp">Setup</div>
        ${navBtn('companies', 'building', 'Companies', S.tab === 'companies', d.companies.length)}
        ${navBtn('acatalog', 'box', 'Catalog', S.tab === 'acatalog')}
        ${navBtn('registers', 'register', 'Registers', S.tab === 'registers', d.registers.length)}
        <div class="grp">Records</div>
        ${navBtn('ainvoices', 'list', 'Invoices', S.tab === 'ainvoices', d.stats.disputedCount ? d.stats.disputedCount + ' disputed' : '', 'red')}
        ${navBtn('logs', 'log', 'Activity log', S.tab === 'logs')}
        <div class="side-foot"><div class="shift"><span>Framework</span><b>${esc(d.system.framework)}</b></div><div class="shift"><span>Inventory</span><b>${esc(d.system.inventory)}</b></div></div>`;
    setStatus([['ESC', 'Close'], ['/', 'Search']], `nayzeee-billing · <b>admin</b>`);
    const views = { overview: viewAdminOverview, companies: viewAdminCompanies, acatalog: viewAdminCatalog, registers: viewAdminRegisters, ainvoices: viewAdminInvoices, logs: viewAdminLogs };
    (views[S.tab] || viewAdminOverview)();
}

async function reloadAdmin() {
    const data = await call('admin:getData');
    if (!data) return;
    S.admin.data = data;
    renderAdmin();
}

function viewAdminOverview() {
    const { stats, system } = S.admin.data;
    const max = Math.max(1, ...stats.byCompany.map((c) => c.revenue));
    setMain(`
        <div class="head"><div><h1>Overview</h1><p>Server-wide billing activity.</p></div>${clockHtml()}</div>
        <div class="stats four">
            ${stat('receipt', 'Invoices today', esc(stats.invoicesToday))}
            ${stat('chart', 'Revenue · 7 days', money(stats.revenueWeek))}
            ${stat('wallet', `Outstanding · ${stats.openCount} open`, money(stats.outstanding), 'off')}
            ${stat('flag', 'Disputes', esc(stats.disputedCount), stats.disputedCount ? 'amber' : 'off')}
        </div>
        <div class="cols">
            <section class="panel"><div class="p-head"><div><h2>Revenue by company</h2><p>Net payments · last 30 days</p></div></div>
                <div class="p-body pad" style="gap:14px">${stats.byCompany.length ? stats.byCompany.map((c) => `<div class="hbar"><div class="label-row"><span style="color:var(--ink)">${esc(c.label)}</span><span>${money(c.revenue)}</span></div>
                    <div class="hbar-track"><i style="width:${Math.max(1.5, c.revenue / max * 100)}%"></i></div></div>`).join('') : emptyState('chart', 'No revenue yet', 'Company payments will show up here.')}</div></section>
            <section class="panel"><div class="p-head"><div><h2>System</h2><p>Detected integrations</p></div><button class="btn-ghost" data-act="adminReload">${ic('refresh')}Reload</button></div>
                <div class="p-body pad"><div class="kv">
                    <div><span>Framework</span><b>${esc(system.framework)}</b></div><div><span>Banking</span><b>${esc(system.banking)}</b></div>
                    <div><span>Inventory</span><b>${esc(system.inventory)}</b></div><div><span>Version</span><b>v${esc(system.version)}</b></div>
                    <div><span>Pending payouts</span><b>${money(stats.pendingPayouts)}</b></div><div><span>Open invoices</span><b>${esc(stats.openCount)}</b></div>
                </div>${system.banking === 'none' ? `<div class="note red" style="margin-top:12px"><b>No banking system</b>Company payments go to the employee who sent the invoice. Set Config.Banking.System to enable company accounts.</div>` : ''}</div></section>
        </div>`);
}

function viewAdminCompanies() {
    const list = S.admin.data.companies;
    setMain(`
        <div class="head"><div><h1>Companies</h1><p>Companies from companies.lua and ones created here. Edits are stored in the database.</p></div>
            <div class="head-actions"><button class="btn-teal" data-act="companyNew">${ic('plus')}New company</button></div></div>
        <div class="quickbills" style="grid-template-columns:repeat(auto-fill,minmax(260px,1fr))">${list.map((c) => `
            <div class="panel" style="padding:14px;gap:12px">
                <div style="display:flex;align-items:center;gap:11px"><div class="tile">${ic('building')}</div><div class="row-txt"><b>${esc(c.label)}</b><span>job ${esc(c.job || '—')}${c.jobs?.length ? ' +' + c.jobs.length : ''} · ${esc(c.id)}</span></div><span class="chip">${esc(c.shortName)}</span></div>
                <div class="kv" style="grid-template-columns:repeat(3,1fr)"><div><span>Tax</span><b>${pct(c.taxRate)}</b></div><div><span>Products</span><b>${c.products.length}</b></div><div><span>Quick</span><b>${c.quickBills.length}</b></div></div>
                <div style="display:flex;gap:5px;flex-wrap:wrap">${c.allowDiscounts ? '<span class="tag live">Discounts</span>' : ''}${c.allowCustomItems ? '<span class="tag live">Custom items</span>' : ''}${c.allowTips ? '<span class="tag live">Tips</span>' : ''}${c.isConfig ? '<span class="tag off">config</span>' : '<span class="tag warn">custom</span>'}${c.hasOverride && c.isConfig ? '<span class="tag off">edited</span>' : ''}</div>
                <div style="display:flex;gap:6px"><button class="btn-line" style="flex:1" data-act="companyEdit" data-id="${esc(c.id)}">${ic('edit')}Edit</button>
                    <button class="btn-line" data-act="companyCatalog" data-id="${esc(c.id)}">${ic('box')}Catalog</button>
                    ${(!c.isConfig || c.hasOverride) ? `<button class="icon-btn danger" style="height:32px;width:32px" data-act="companyDelete" data-id="${esc(c.id)}" title="${c.isConfig ? 'Reset to companies.lua' : 'Delete'}">${ic(c.isConfig ? 'undo' : 'trash')}</button>` : ''}</div>
            </div>`).join('')}</div>`);
}

function companyModal(c) {
    const isNew = !c; c = c || { taxRate: 0.08, allowDiscounts: true, maxDiscount: 100, allowTips: true, products: [], quickBills: [] };
    const sw = (id, on, label) => `<div class="sw-line"><span>${label}</span><span class="sw ${on ? 'on' : ''}" data-act="toggle" id="${id}"><i></i></span></div>`;
    const m = openModal(`<div class="modal xwide">
        ${modalHead('building', isNew ? 'New company' : 'Edit company', isNew ? 'Create a billing company for a job' : esc(c.label))}
        <div class="modal-b">
            <div class="grid3"><div class="field"><label>Company ID</label><input id="fId" value="${esc(c.id)}" ${isNew ? 'autofocus' : 'disabled'} placeholder="burgershot"></div>
                <div class="field"><label>Name</label><input id="fLabel" value="${esc(c.label)}" maxlength="100" placeholder="Burgershot"></div>
                <div class="field"><label>Short name</label><input id="fShort" value="${esc(c.shortName)}" maxlength="10" placeholder="BS"></div></div>
            <div class="grid3"><div class="field"><label>Job</label><input id="fJob" value="${esc(c.job)}" placeholder="burgershot"></div>
                <div class="field"><label>Extra jobs (comma separated)</label><input id="fJobs" value="${esc((c.jobs || []).join(', '))}" placeholder="burgershot2"></div>
                <div class="field"><label>Bank account</label><input id="fAccount" value="${esc(c.account)}" placeholder="defaults to job"></div></div>
            <div class="grid3"><div class="field"><label>Tax %</label><input id="fTax" type="number" min="0" max="100" step="0.1" value="${esc(round2(num(c.taxRate) * 100))}"></div>
                <div class="field"><label>Commission % (blank = default)</label><input id="fComm" type="number" min="0" max="100" step="0.1" value="${c.commission !== undefined && c.commission !== null ? esc(round2(c.commission * 100)) : ''}"></div>
                <div class="field"><label>Due days (blank = default)</label><input id="fDue" type="number" min="0" max="365" value="${c.dueDays !== undefined && c.dueDays !== null ? esc(c.dueDays) : ''}"></div></div>
            <div class="grid3"><div class="field"><label>Min grade to bill</label><input id="fMin" type="number" min="0" value="${esc(c.minGrade || 0)}"></div>
                <div class="field"><label>Boss grade (blank = framework boss)</label><input id="fBoss" type="number" min="0" value="${c.bossGrade !== undefined && c.bossGrade !== null ? esc(c.bossGrade) : ''}"></div>
                <div class="field"><label>Max discount %</label><input id="fMaxDisc" type="number" min="0" max="100" value="${esc(c.maxDiscount ?? 100)}"></div></div>
            <div class="field"><label>Discord webhook (this company only)</label><input id="fHook" value="${esc(c.webhook)}" placeholder="https://discord.com/api/webhooks/..."></div>
            <div class="grid3">${sw('fDisc', c.allowDiscounts, 'Allow discounts')}${sw('fCustom', c.allowCustomItems, 'Custom items')}${sw('fTips', c.allowTips, 'Allow tips')}</div>
        </div>
        <div class="modal-f"><button class="btn-line" data-act="modalClose">Cancel</button><button class="btn-teal" data-act="modalOk">${ic('check')}${isNew ? 'Create company' : 'Save changes'}</button></div></div>`);
    m.ok = async () => {
        const v = (id) => $('#' + id, m.el).value;
        const on = (id) => $('#' + id, m.el).classList.contains('on');
        const list = await call('admin:saveCompany', { isNew, company: {
            id: v('fId'), label: v('fLabel'), shortName: v('fShort'), job: v('fJob'), jobs: v('fJobs'), account: v('fAccount'),
            taxRate: num(v('fTax')), commission: v('fComm'), dueDays: v('fDue'), minGrade: num(v('fMin')), bossGrade: v('fBoss'),
            maxDiscount: num(v('fMaxDisc'), 100), webhook: v('fHook'), allowDiscounts: on('fDisc'), allowCustomItems: on('fCustom'), allowTips: on('fTips'),
        } });
        if (!list) return;
        S.admin.data.companies = list; m.close(); toast('Saved', 'Company saved', 'success'); renderAdmin();
    };
}

function viewAdminCatalog() {
    const list = S.admin.data.companies;
    if (!list.find((c) => c.id === S.admin.catalogCompany)) S.admin.catalogCompany = list[0]?.id || null;
    const company = catalogCompany();
    setMain(`<div class="head"><div><h1>Catalog</h1><p>Manage products, categories and quick bills for any company.</p></div>
        <div class="head-actions"><div class="field" style="width:240px"><select data-change="adminCatalogCompany">${list.map((c) => `<option value="${esc(c.id)}" ${c.id === S.admin.catalogCompany ? 'selected' : ''}>${esc(c.label)}</option>`).join('')}</select></div></div></div>
        <div id="catalogEditor" style="display:flex;flex-direction:column;gap:14px;flex:1;min-height:0">${company ? catalogEditorHtml(company) : emptyState('building', 'No companies', 'Create a company first.')}</div>`);
}

function viewAdminRegisters() {
    const { registers, companies } = S.admin.data;
    setMain(`
        <div class="head"><div><h1>Cash registers</h1><p>Registers let employees ring customers up with a live customer display.</p></div></div>
        <section class="panel"><div class="p-head"><div><h2>Add register at my position</h2><p>Stand where the register should be, then add it</p></div></div>
            <div class="p-body pad"><div style="display:grid;grid-template-columns:1.4fr 1.2fr 110px auto;gap:10px;align-items:end">
                <div class="field"><label>Label</label><input id="rLabel" maxlength="100" placeholder="Front counter"></div>
                <div class="field"><label>Company</label><select id="rCompany">${companies.map((c) => `<option value="${esc(c.id)}">${esc(c.label)}</option>`).join('')}</select></div>
                <div class="field"><label>Radius (m)</label><input id="rRadius" type="number" min="0.5" max="10" step="0.5" value="2"></div>
                <button class="btn-teal" data-act="registerAdd">${ic('pin')}Add here</button></div></div></section>
        <section class="panel grow"><div class="p-head"><div><h2>Registers</h2><p>${registers.length} total</p></div></div>
            <div class="p-body pad">${registers.length ? `<table class="table"><thead><tr><th>Label</th><th>Company</th><th>Coords</th><th>Radius</th><th>Source</th><th></th></tr></thead><tbody>
            ${registers.map((r) => `<tr><td><b>${esc(r.label)}</b></td><td>${esc(r.companyLabel)}</td><td class="ref">${esc(num(r.coords.x).toFixed(1))}, ${esc(num(r.coords.y).toFixed(1))}, ${esc(num(r.coords.z).toFixed(1))}</td>
                <td>${esc(r.radius)}m</td><td>${r.source === 'config' ? '<span class="tag off">config</span>' : '<span class="tag live">in-game</span>'}</td>
                <td class="r"><span style="display:inline-flex;gap:6px"><button class="icon-btn" title="Waypoint" data-act="registerWaypoint" data-id="${esc(r.id)}">${ic('pin')}</button>
                <button class="icon-btn" title="Teleport" data-act="registerTeleport" data-id="${esc(r.id)}">${ic('teleport')}</button>
                ${r.source !== 'config' ? `<button class="icon-btn danger" title="Delete" data-act="registerDelete" data-id="${esc(r.id)}">${ic('trash')}</button>` : ''}</span></td></tr>`).join('')}</tbody></table>`
            : emptyState('register', 'No registers', 'Add one above or define them in config.lua.')}</div></section>`);
}

async function loadAdminInvoices(append = false) {
    const a = S.admin.inv;
    if (!append) { a.page = 0; a.rows = []; }
    const data = await call('admin:getInvoices', { status: a.status, companyId: a.companyId || null, search: a.search, page: a.page });
    if (!data) return;
    a.rows = append ? a.rows.concat(data.rows) : data.rows;
    a.hasMore = data.hasMore; a.loaded = true;
    const el = $('#adminInvList'); if (!el) return;
    el.innerHTML = a.rows.length ? `<table class="table"><thead><tr><th>Invoice</th><th>Company</th><th>From</th><th>To</th><th>Date</th><th>Status</th><th class="r">Amount</th></tr></thead><tbody>
        ${a.rows.map((i) => `<tr class="click" data-act="invoice" data-id="${esc(i.id)}"><td><b>${esc(i.id)}</b></td><td class="ell">${esc(i.company)}</td><td class="ell">${esc(i.senderName)}</td><td class="ell">${esc(i.targetName)}</td><td>${esc(fmtDate(i.createdAt))}</td><td>${statusTag(i.status)}</td><td class="r"><b>${money(i.total + i.lateFee)}</b></td></tr>`).join('')}
        </tbody></table>${a.hasMore ? `<button class="btn-ghost more" data-act="adminInvMore">Load more</button>` : ''}` : emptyState('list', 'No invoices', 'Nothing matches these filters.');
}
function viewAdminInvoices() {
    const a = S.admin.inv;
    setMain(`<div class="head"><div><h1>Invoices</h1><p>Every invoice on the server. Open one to cancel, refund or resolve it.</p></div>
        <div class="head-actions"><div class="field" style="width:220px"><select data-change="adminInvCompany"><option value="">All companies</option>${S.admin.data.companies.map((c) => `<option value="${esc(c.id)}" ${a.companyId === c.id ? 'selected' : ''}>${esc(c.label)}</option>`).join('')}</select></div></div></div>
        <div class="toolbar"><div class="filters">${BOSS_FILTERS.map(([id, l]) => `<button class="fchip ${a.status === id ? 'on' : ''}" data-act="adminInvFilter" data-f="${id}">${l}</button>`).join('')}</div>
            <label class="search">${ic('search')}<input data-input="adminInvSearch" placeholder="Search invoice, name or company" value="${esc(a.search)}"></label></div>
        <section class="panel grow"><div class="p-body pad" id="adminInvList">${skeleton(5)}</div></section>`);
    loadAdminInvoices();
}

async function loadLogs(append = false) {
    const l = S.admin.logs;
    if (!append) { l.page = 0; l.rows = []; }
    const data = await call('admin:getLogs', { search: l.search, page: l.page });
    if (!data) return;
    l.rows = append ? l.rows.concat(data.rows) : data.rows;
    l.hasMore = data.hasMore;
    const el = $('#logList'); if (!el) return;
    const details = (d) => Object.entries(d || {}).filter(([, v]) => typeof v !== 'object').map(([k, v]) => `${k}: ${v}`).join(' · ');
    el.innerHTML = l.rows.length ? `<table class="table"><thead><tr><th>Time</th><th>Player</th><th>Action</th><th>Details</th></tr></thead><tbody>
        ${l.rows.map((r) => `<tr><td>${esc(fmtDate(r.timestamp))}</td><td><b>${esc(r.player)}</b></td><td><span class="chip ${/denied|cancel|refund|disput/.test(r.action) ? 'red' : ''}">${esc(r.action.replace(/_/g, ' '))}</span></td><td class="wrap" style="font-size:11px">${esc(details(r.data))}</td></tr>`).join('')}
        </tbody></table>${l.hasMore ? `<button class="btn-ghost more" data-act="logsMore">Load more</button>` : ''}` : emptyState('log', 'No log entries', 'Billing activity will be recorded here.');
}
function viewAdminLogs() {
    setMain(`<div class="head"><div><h1>Activity log</h1><p>Every invoice, payment, refund and admin action.</p></div></div>
        <div class="toolbar"><label class="search">${ic('search')}<input data-input="logSearch" placeholder="Search player, action or details" value="${esc(S.admin.logs.search)}"></label></div>
        <section class="panel grow"><div class="p-body pad" id="logList">${skeleton(6)}</div></section>`);
    loadLogs();
}

// ═══════════════════════════════════════════════════════════════
// POS (employee register)
// ═══════════════════════════════════════════════════════════════
function openPos(data) {
    S.pos = { register: data.register, company: data.company, nearby: data.nearby || [], customer: null, items: [], discount: 0, notes: '', status: 'idle', category: 'all', search: '', invoiceId: null, totals: null };
    S.currency = S.currency || '$';
    if (data.imagePath) S.imagePath = data.imagePath;
    showShell('pos');
    setBar(data.register.label, data.company.label, `<span class="dot pulse"></span><p>Register open · <b>${esc(data.company.shortName)}</b> · ${pct(data.company.taxRate)} tax</p>`);
    setStatus([['ESC', 'Close register'], ['/', 'Search']], `nayzeee-billing · <b>POS</b>`);
    const c = data.company;
    setMain(`<div class="pos-grid">
        <section class="panel"><div class="p-head"><div><h2>Menu</h2><p>${(c.products || []).length} items</p></div>
            <label class="search" style="max-width:240px">${ic('search')}<input data-input="posSearch" placeholder="Search menu"></label></div>
            <div class="p-body pad catalog">${catalogFilters(c.categories, 'all', 'posCategory')}<div class="products" id="posGrid"></div></div></section>
        <section class="panel"><div class="p-head"><div><h2>Order</h2><p id="posSub">Select a customer to begin</p></div>
            <button class="btn-ghost danger" data-act="posClear">${ic('trash')}Clear</button></div>
            <div class="p-body pad" style="gap:14px" id="posBody"></div><div class="p-foot" id="posFoot"></div></section></div>`);
    renderPosGrid(); renderPos();
}

function posLocked() { return ['checkout'].includes(S.pos.status); }

function renderPosGrid() {
    const el = $('#posGrid'); if (!el) return;
    const p = S.pos;
    const list = filteredProducts(p.company, p.category, p.search);
    const qm = qtyMap(p.items);
    el.innerHTML = list.length ? list.map((x) => productCard(x, qm, 'posAdd')).join('') : `<div style="grid-column:1/-1">${emptyState('box', 'No items', 'Nothing matches.')}</div>`;
}

function renderPos() {
    const p = S.pos; const body = $('#posBody'); const foot = $('#posFoot'); if (!body) return;
    const locked = posLocked();
    let html = '<div class="field"><div class="label-row"><span>Customer</span>';
    if (p.customer) {
        html += `</div><div class="recipient"><div class="av">${initials(p.customer.name)}</div><div class="row-txt"><b>${esc(p.customer.name)}</b><span>Watching the customer display</span></div></div></div>`;
    } else {
        html += `<button class="btn-ghost" style="height:22px" data-act="posNearby">${ic('refresh')}Refresh</button></div><div class="results">
            ${p.nearby.length ? p.nearby.map((n) => `<button class="mini" data-act="posAssign" data-pid="${esc(n.id)}"><div class="av">${initials(n.name)}</div><b>${esc(n.name)}</b><span>${esc(n.distance)}m</span></button>`).join('')
            : '<div class="label-row" style="padding:6px 2px">No customers at the counter</div>'}</div></div>`;
    }
    html += `<div class="field"><div class="label-row"><span>Items</span><span>${p.items.reduce((s, i) => s + i.quantity, 0)} total</span></div><div class="lines">`;
    html += p.items.length ? p.items.map((it, idx) => `<div class="line"><div class="row-txt"><b>${esc(it.name)}</b><span>${money(it.price)} each</span></div>
        <div class="stepper"><button data-act="posQty" data-i="${idx}" data-d="-1" ${locked ? 'disabled' : ''}>${ic('minus')}</button><span>${it.quantity}</span><button data-act="posQty" data-i="${idx}" data-d="1" ${locked ? 'disabled' : ''}>${ic('plus')}</button></div>
        <span class="amt" style="min-width:64px;text-align:right">${money(it.price * it.quantity)}</span></div>`).join('')
        : `<div class="empty" style="padding:18px">${ic('register')}<span>Tap menu items to add them to the order.</span></div>`;
    html += '</div></div>';
    if (p.company.allowDiscounts) html += `<div class="field"><label>Discount % (max ${esc(p.company.maxDiscount)})</label><input type="number" min="0" max="${esc(p.company.maxDiscount)}" data-input="posDiscount" value="${esc(p.discount || '')}" placeholder="0" ${locked ? 'disabled' : ''}></div>`;
    body.innerHTML = html;

    const t = calcTotals(p.items, p.discount, p.company.taxRate);
    const statusBox = {
        idle: ['', 'Select a customer at the counter'],
        viewing: ['', `<b>${esc(p.customer?.name || '')}</b> can see the order on their display`],
        checkout: ['wait', `Waiting for <b>${esc(p.customer?.name || '')}</b> to pay ${money(t.total)}`],
        paid: ['paid', p.lastPaid ? `<b>${esc(p.lastPaid.customer || 'Customer')}</b> paid ${money(p.lastPaid.amount)}${p.lastPaid.tip > 0 ? ` + ${money(p.lastPaid.tip)} tip` : ''}` : 'Paid'],
        declined: ['bad', 'The customer declined the payment'],
        left: ['bad', 'The customer left the counter'],
    }[p.status] || ['', ''];
    let buttons = '';
    if (p.status === 'checkout') buttons = `<button class="btn-red btn-lg btn-block" data-act="posVoid">Void checkout</button>`;
    else if (p.status === 'paid') buttons = `<button class="btn-teal btn-lg btn-block" data-act="posNext">${ic('users')}Next customer</button>`;
    else buttons = `<button class="btn-teal btn-lg btn-block" data-act="posCharge" ${!p.customer || !p.items.length ? 'disabled' : ''}>${ic('card')}Charge ${money(t.total)}</button>`;
    foot.innerHTML = `<div class="totals"><div><span>Subtotal</span><b>${money(t.subtotal)}</b></div>
        ${t.discount > 0 ? `<div class="neg"><span>Discount</span><b>−${money(t.discount)}</b></div>` : ''}
        <div><span>Tax (${pct(p.company.taxRate)})</span><b>${money(t.tax)}</b></div><div class="grand"><span>Total</span><b>${money(t.total)}</b></div></div>
        <div class="pos-status ${statusBox[0]}"><span class="dot ${statusBox[0] === 'wait' ? 'amber pulse' : statusBox[0] === 'bad' ? 'red' : ''}"></span><span>${statusBox[1]}</span></div>${buttons}`;
    const sub = $('#posSub'); if (sub) sub.textContent = p.customer ? `Serving ${p.customer.name}` : 'Select a customer to begin';
}

const syncPos = debounce(async () => {
    if (!S.pos) return;
    const res = await api('register:update', { registerId: S.pos.register.id, items: S.pos.items.map((i) => ({ productId: i.productId, quantity: i.quantity })), discount: num(S.pos.discount) });
    if (!res.ok) toast('Register', res.error, 'error');
}, 160);

function posChanged() { renderPos(); renderPosGrid(); syncPos(); }

function onPosState(state) {
    if (!S.pos) return;
    const p = S.pos;
    if (state.status === 'paid') {
        p.status = 'paid'; p.lastPaid = state; p.invoiceId = null; p.customer = null;
        toast('Payment received', `${state.customer || 'Customer'} paid ${money(state.amount)}${state.tip > 0 ? ` + ${money(state.tip)} tip` : ''}`, 'success');
    } else if (state.status === 'declined' || state.status === 'left') {
        p.status = state.status; p.customer = null; p.invoiceId = null;
        toast('Register', state.status === 'declined' ? 'Customer declined the payment' : 'Customer left the counter', 'warning');
        call('register:nearby', { registerId: p.register.id }).then((list) => { if (Array.isArray(list) && S.pos) { S.pos.nearby = list; renderPos(); } });
    }
    renderPos();
}

// ═══════════════════════════════════════════════════════════════
// CUSTOMER DISPLAY
// ═══════════════════════════════════════════════════════════════
function displayOpen(data) {
    S.display = { company: data.company, register: data.register, employee: data.employee, items: [], totals: { subtotal: 0, discount: 0, tax: 0, total: 0 }, stage: 'order', method: 'bank', tipPct: 0 };
    renderDisplay();
}
function displayUpdate(data) {
    if (!S.display) return;
    S.display.items = data.items || [];
    S.display.totals = data;
    renderDisplay();
}
function displayCheckout(data) {
    if (!S.display) S.display = { company: data.invoice.company, register: '', employee: data.invoice.senderName, items: [], totals: {}, method: 'bank', tipPct: 0 };
    Object.assign(S.display, { stage: 'checkout', invoice: data.invoice, allowTips: data.allowTips, items: data.invoice.items, totals: data.invoice });
    renderDisplay();
}
function displayClose() {
    const d = S.display;
    if (d && d.stage === 'done') return;
    S.display = null;
    $('#display').classList.add('hidden');
}

function renderDisplay() {
    const d = S.display; const el = $('#display'); if (!d) return;
    el.classList.remove('hidden');
    const t = d.totals || {};
    const lines = (d.items || []).map((i) => `<div class="line"><div class="row-txt"><b>${esc(i.name)}</b><span>${money(i.price)} × ${esc(i.quantity)}</span></div><span class="amt">${money(i.price * i.quantity)}</span></div>`).join('')
        || `<div class="label-row" style="justify-content:center;padding:22px 0">Waiting for items...</div>`;
    let state = `<div class="dstate"><span class="dot pulse"></span><span>Served by <b>${esc(d.employee)}</b></span></div>`;
    let foot = '';
    if (d.stage === 'order') {
        foot = `<div class="totals"><div><span>Subtotal</span><b>${money(t.subtotal)}</b></div>${num(t.discount) > 0 ? `<div class="neg"><span>Discount</span><b>−${money(t.discount)}</b></div>` : ''}<div><span>Tax</span><b>${money(t.tax)}</b></div><div class="grand"><span>Total</span><b>${money(t.total)}</b></div></div>
            <div class="dhint"><span class="key">BACKSPACE</span>&nbsp;Leave the counter (rebindable)</div>`;
    } else if (d.stage === 'checkout') {
        const inv = d.invoice;
        const st = S.ctx?.settings;
        const tips = d.allowTips ? (st?.tips || [0, 10, 15, 20]) : null;
        const tip = tips ? round2(inv.total * d.tipPct / 100) : 0;
        state = `<div class="dstate" style="background:var(--teal-wash)"><span class="dot"></span><span><b>Ready to pay</b> · ${esc(inv.id)}</span></div>`;
        foot = `<div class="totals"><div><span>Subtotal</span><b>${money(inv.subtotal)}</b></div>${inv.discount > 0 ? `<div class="neg"><span>Discount</span><b>−${money(inv.discount)}</b></div>` : ''}<div><span>Tax</span><b>${money(inv.tax)}</b></div>${tip > 0 ? `<div><span>Tip</span><b>${money(tip)}</b></div>` : ''}<div class="grand"><span>Total</span><b>${money(inv.total + tip)}</b></div></div>
            <div class="seg"><button class="${d.method === 'bank' ? 'on' : ''}" data-act="dispMethod" data-m="bank">${ic('card')}Card</button><button class="${d.method === 'cash' ? 'on' : ''}" data-act="dispMethod" data-m="cash">${ic('cash')}Cash</button></div>
            ${tips ? `<div class="tips">${tips.map((x) => `<button class="${d.tipPct === x ? 'on' : ''}" data-act="dispTip" data-v="${x}">${x ? x + '%' : 'No tip'}</button>`).join('')}</div>` : ''}
            <div style="display:flex;gap:8px"><button class="btn-line btn-lg" data-act="dispDecline">Not now</button><button class="btn-teal btn-lg" style="flex:1" data-act="dispPay" id="dispPayBtn">${ic('check')}Pay ${money(inv.total + tip)}</button></div>`;
    } else if (d.stage === 'done') {
        const r = d.result;
        el.innerHTML = `<div class="dframe"><div class="dshell"><div class="dhead"><div class="mark sm"></div><div class="bar-name"><div class="title-txt">${esc(d.company)}</div><div class="sub">${esc(d.register || 'Checkout')}</div></div></div>
            <div class="success"><div class="ring">${ic('check')}</div><b>Payment complete</b><span>${money(r.charged)} paid by ${r.method === 'cash' ? 'cash' : 'card'}${r.tip > 0 ? ` · thanks for the ${money(r.tip)} tip!` : ''}</span></div>
            <div class="dfoot"><div style="display:flex;gap:8px">${r.receipt ? `<button class="btn-line btn-lg" style="flex:1" data-act="dispReceipt">${ic('receipt')}Receipt</button>` : ''}<button class="btn-teal btn-lg" style="flex:1" data-act="dispDone">Done</button></div></div></div></div>`;
        return;
    }
    el.innerHTML = `<div class="dframe"><div class="dshell">
        <div class="dhead"><div class="mark sm"></div><div class="bar-name" style="min-width:0"><div class="title-txt">${esc(d.company)}</div><div class="sub">${esc(d.register || 'Customer display')}</div></div></div>
        ${state}<div class="dbody">${lines}</div><div class="dfoot">${foot}</div></div></div>`;
}

let displayDoneTimer = null;
function finishDisplay() {
    clearTimeout(displayDoneTimer);
    S.display = null;
    $('#display').classList.add('hidden');
    nui('displayDone');
}

// ═══════════════════════════════════════════════════════════════
// ACTIONS (delegated)
// ═══════════════════════════════════════════════════════════════
const A = {
    modalClose: () => { const m = topModal(); if (m) m.close(null); },
    modalOk: () => { const m = topModal(); if (m && m.ok) m.ok(); },
    tab: (d) => setTab(d.tab),
    refresh: () => refreshContext(),
    toggle: (d, el) => el.classList.toggle('on'),

    // bills / invoices
    billsFilter: (d) => { S.billsFilter = d.f; viewBills(); },
    invoice: (d) => openInvoice(d.id),
    pay: (d) => openPay(d.id),
    dispute: async (d) => {
        const reason = await promptBox({ title: 'Dispute invoice', text: 'The company will review your dispute. You will not be able to pay until it is resolved.', placeholder: 'What is wrong with this invoice?', confirm: 'Submit dispute', required: true, icon: 'flag', max: 250 });
        if (reason === null) return;
        if (await call('disputeInvoice', { invoiceId: d.id, reason })) { toast('Dispute submitted', 'The company has been notified', 'success'); closeAllModals(); refreshContext(); }
    },
    cancelInvoice: async (d) => {
        const reason = await promptBox({ title: 'Cancel invoice', text: 'The recipient will be notified. This cannot be undone.', placeholder: 'Reason (optional)', confirm: 'Cancel invoice', danger: true, icon: 'alert' });
        if (reason === null) return;
        if (await call('cancelInvoice', { invoiceId: d.id, reason })) { toast('Cancelled', `${d.id} was cancelled`, 'success'); afterInvoiceAction(); }
    },
    refund: async (d) => {
        const reason = await promptBox({ title: 'Refund invoice', text: 'The paid amount is taken from the company account and returned to the customer.', placeholder: 'Reason (optional)', confirm: 'Refund', danger: true, icon: 'undo' });
        if (reason === null) return;
        const res = await call('boss:refund', { invoiceId: d.id, reason });
        if (res) { toast('Refunded', `${money(res.amount)} returned to the customer`, 'success'); afterInvoiceAction(); }
    },
    resolve: async (d) => {
        const accept = d.a === 'cancel';
        const ok = await confirmBox({ title: accept ? 'Accept dispute' : 'Reject dispute', text: accept ? 'The invoice will be cancelled.' : 'The invoice goes back to the customer as payable.', confirm: accept ? 'Accept & cancel' : 'Reject dispute', danger: accept });
        if (!ok) return;
        if (await call('boss:resolveDispute', { invoiceId: d.id, action: d.a })) { toast('Dispute resolved', accept ? 'Invoice cancelled' : 'Invoice reinstated', 'success'); afterInvoiceAction(); }
    },
    receiptFromDetail: () => { const m = modalStack.find((x) => x.invoice); if (m) showReceipt(m.invoice, () => {}); },

    // history
    historyFilter: (d) => { S.history.filter = d.f; S.history.rows = []; viewHistory(); },
    historyMore: () => { S.history.page++; loadHistory(true); },

    // new invoice
    orderMode: (d) => { S.order.personal = d.m === 'personal'; S.order.items = []; S.order.discount = 0; viewNew(); },
    productCategory: (d) => { S.order.category = d.f; document.querySelectorAll('[data-act="productCategory"]').forEach((b) => b.classList.toggle('on', b.dataset.f === d.f)); renderProducts(); },
    addProduct: (d) => { const p = orderCompany()?.products.find((x) => x.id === d.id); if (!p) return; addLine({ productId: p.id, name: p.name, price: num(p.price), image: p.image }); updateOrder(); },
    addQuick: (d) => { const q = S.ctx.company.quickBills.find((x) => x.id === d.id); if (!q) return; S.order.personal = false; addLine({ quickBillId: q.id, name: q.label, price: num(q.amount) }); toast('Added to order', q.label, 'success'); setTab('new'); },
    addCustom: () => {
        const name = $('#customName').value.trim(); const price = round2($('#customPrice').value);
        if (!name || price <= 0) { toast('Custom item', 'Enter a name and a price', 'warning'); return; }
        addLine({ name, price, custom: true }); $('#customName').value = ''; $('#customPrice').value = ''; updateOrder();
    },
    qty: (d) => { const it = S.order.items[+d.i]; if (!it) return; it.quantity += +d.d; if (it.quantity <= 0) S.order.items.splice(+d.i, 1); else it.quantity = Math.min(it.quantity, S.ctx.settings.maxQuantity); updateOrder(); },
    clearOrder: () => { S.order.items = []; S.order.discount = 0; S.order.notes = ''; updateOrder(); },
    nearby: () => { S.order.query = ''; loadNearby(); },
    pickRecipient: (d) => {
        S.order.recipient = d.ident ? { type: 'offline', identifier: d.ident, name: d.name } : { type: 'online', id: +d.pid, name: d.name };
        S.order.query = ''; S.order.results = []; renderOrderBody(); renderOrderFoot();
    },
    clearRecipient: () => { S.order.recipient = null; renderOrderBody(); renderOrderFoot(); },
    sendInvoice: () => sendInvoice(),

    // boss
    dashRefresh: () => { S.boss.dash = null; viewDash(); },
    bossFilter: (d) => { S.boss.inv.status = d.f; if (S.tab !== 'cinvoices') setTab('cinvoices'); else viewCompanyInvoices(); },
    bossMore: () => { S.boss.inv.page++; loadBossInvoices(true); },

    // catalog
    catTab: (d) => { S.boss.catTab = d.t; rerenderCatalog(); },
    catAdd: () => { const c = catalogCompany(); if (!c) return; const t = S.boss.catTab; if (t === 'products') productModal(c); else if (t === 'categories') categoryModal(c); else quickModal(c); },
    editProduct: (d) => { const c = catalogCompany(); productModal(c, c.products.find((p) => p.id === d.id)); },
    editCategory: (d) => { const c = catalogCompany(); categoryModal(c, c.categories.find((x) => x.id === d.id)); },
    editQuick: (d) => { const c = catalogCompany(); quickModal(c, c.quickBills.find((x) => x.id === d.id)); },
    deleteProduct: (d) => catalogDelete('catalog:deleteProduct', d.id, 'product'),
    deleteCategory: (d) => catalogDelete('catalog:deleteCategory', d.id, 'category'),
    deleteQuick: (d) => catalogDelete('catalog:deleteQuickBill', d.id, 'quick bill'),
    pickItem: (d) => { const m = topModal(); const input = m && $('#pImage', m.el); if (input) input.value = d.name; const nameInput = m && $('#pName', m.el); if (nameInput && !nameInput.value) nameInput.value = d.label; },

    // admin
    adminReload: () => reloadAdmin(),
    companyNew: () => companyModal(null),
    companyEdit: (d) => companyModal(S.admin.data.companies.find((c) => c.id === d.id)),
    companyCatalog: (d) => { S.admin.catalogCompany = d.id; setTab('acatalog'); },
    companyDelete: async (d) => {
        const c = S.admin.data.companies.find((x) => x.id === d.id);
        const ok = await confirmBox({ title: c.isConfig ? 'Reset company' : 'Delete company', text: c.isConfig ? `Remove in-game edits to ${c.label} and go back to companies.lua?` : `Delete ${c.label}? Existing invoices are kept.`, confirm: c.isConfig ? 'Reset' : 'Delete', danger: true });
        if (!ok) return;
        const list = await call('admin:deleteCompany', { id: d.id });
        if (list) { S.admin.data.companies = list; renderAdmin(); }
    },
    registerAdd: async () => {
        const list = await call('admin:saveRegister', { label: $('#rLabel').value, company: $('#rCompany').value, radius: num($('#rRadius').value, 2) });
        if (list) { S.admin.data.registers = list; toast('Register added', 'Created at your position', 'success'); renderAdmin(); }
    },
    registerDelete: async (d) => {
        if (!await confirmBox({ title: 'Delete register', text: 'Remove this register for everyone?', confirm: 'Delete', danger: true })) return;
        const list = await call('admin:deleteRegister', { id: d.id });
        if (list) { S.admin.data.registers = list; renderAdmin(); }
    },
    registerTeleport: async (d) => { if (await call('admin:teleport', { id: d.id })) toast('Teleported', 'You are at the register', 'success'); },
    registerWaypoint: (d) => { const r = S.admin.data.registers.find((x) => x.id === d.id); if (r) { nui('setWaypoint', r.coords); toast('Waypoint set', r.label, 'success'); } },
    adminInvFilter: (d) => { S.admin.inv.status = d.f; viewAdminInvoices(); },
    adminInvMore: () => { S.admin.inv.page++; loadAdminInvoices(true); },
    logsMore: () => { S.admin.logs.page++; loadLogs(true); },

    // POS
    posCategory: (d) => { S.pos.category = d.f; document.querySelectorAll('[data-act="posCategory"]').forEach((b) => b.classList.toggle('on', b.dataset.f === d.f)); renderPosGrid(); },
    posAdd: (d) => {
        if (posLocked()) { toast('Register', 'Void the checkout to change the order', 'warning'); return; }
        if (S.pos.status === 'paid') { S.pos.items = []; S.pos.discount = 0; }
        if (['paid', 'declined', 'left'].includes(S.pos.status)) S.pos.status = S.pos.customer ? 'viewing' : 'idle';
        const p = S.pos.company.products.find((x) => x.id === d.id); if (!p) return;
        const ex = S.pos.items.find((i) => i.productId === p.id);
        if (ex) ex.quantity++; else S.pos.items.push({ productId: p.id, name: p.name, price: num(p.price), quantity: 1 });
        posChanged();
    },
    posQty: (d) => { const it = S.pos.items[+d.i]; if (!it) return; it.quantity += +d.d; if (it.quantity <= 0) S.pos.items.splice(+d.i, 1); posChanged(); },
    posClear: () => { if (posLocked()) return; S.pos.items = []; S.pos.discount = 0; posChanged(); },
    posNearby: async () => { const list = await call('register:nearby', { registerId: S.pos.register.id }); if (Array.isArray(list)) { S.pos.nearby = list; renderPos(); } },
    posAssign: async (d) => {
        const res = await call('register:assign', { registerId: S.pos.register.id, customerId: +d.pid });
        if (!res) return;
        S.pos.customer = res.customer; S.pos.status = 'viewing'; renderPos(); syncPos();
    },
    posCharge: async () => {
        const btn = $('[data-act="posCharge"]'); if (btn) btn.disabled = true;
        const res = await call('register:charge', { registerId: S.pos.register.id, items: S.pos.items.map((i) => ({ productId: i.productId, quantity: i.quantity })), discount: num(S.pos.discount) });
        if (!res) { if (btn) btn.disabled = false; return; }
        S.pos.invoiceId = res.invoiceId; S.pos.status = 'checkout'; renderPos();
    },
    posVoid: async () => {
        const res = await call('register:next', { registerId: S.pos.register.id });
        if (!res) return;
        Object.assign(S.pos, { status: 'idle', customer: null, invoiceId: null, nearby: res.nearby || [] });
        renderPos(); renderPosGrid();
    },
    posNext: async () => {
        const res = await call('register:next', { registerId: S.pos.register.id });
        if (!res) return;
        Object.assign(S.pos, { status: 'idle', customer: null, invoiceId: null, items: [], discount: 0, nearby: res.nearby || [] });
        renderPos(); renderPosGrid();
    },

    // customer display
    dispMethod: (d) => { S.display.method = d.m; renderDisplay(); },
    dispTip: (d) => { S.display.tipPct = +d.v; renderDisplay(); },
    dispPay: async () => {
        const dsp = S.display; const btn = $('#dispPayBtn'); if (btn) btn.disabled = true;
        const res = await call('display:pay', { method: dsp.method, tip: dsp.allowTips ? round2(dsp.invoice.total * dsp.tipPct / 100) : 0 });
        if (!res) { if (btn) btn.disabled = false; return; }
        dsp.stage = 'done'; dsp.result = res; renderDisplay();
        displayDoneTimer = setTimeout(finishDisplay, 8000);
    },
    dispDecline: () => { S.display = null; $('#display').classList.add('hidden'); nui('displayDecline'); },
    dispDone: () => finishDisplay(),
    dispReceipt: () => {
        clearTimeout(displayDoneTimer);
        const receipt = S.display.result.receipt;
        S.display = null; $('#display').classList.add('hidden');
        S.mode = 'receipt'; S.receiptClose = 'displayDone';
        showReceipt(receipt);
    },
};

async function catalogDelete(rpc, id, label) {
    const c = catalogCompany(); if (!c) return;
    if (!await confirmBox({ title: `Delete ${label}`, text: `Delete this ${label} from ${c.label}?`, confirm: 'Delete', danger: true })) return;
    const res = await call(rpc, { companyId: c.id, id });
    if (res) applyCatalogResult(res);
}

function afterInvoiceAction() {
    closeAllModals();
    if (S.mode === 'billing') refreshContext();
    else if (S.mode === 'admin' && S.tab === 'ainvoices') loadAdminInvoices();
}

// ═══════════════ INPUT HANDLERS ═══════════════
const searchPlayers = debounce(async (q) => {
    if (!q) { S.order.results = []; const r = $('#playerResults'); if (r) r.innerHTML = playerResultsHtml(); return; }
    const data = await call('searchPlayers', { query: q });
    if (S.order.query !== q) return;
    S.order.results = Array.isArray(data) ? data : [];
    const r = $('#playerResults'); if (r) r.innerHTML = playerResultsHtml();
}, 300);
const reloadHistory = debounce(() => loadHistory(), 300);
const reloadBoss = debounce(() => loadBossInvoices(), 300);
const reloadAdminInv = debounce(() => loadAdminInvoices(), 300);
const reloadLogs = debounce(() => loadLogs(), 300);
const showItems = debounce(async (q, m) => {
    const items = await ensureItems();
    const box = m && $('#itemResults', m.el); if (!box) return;
    const ql = q.toLowerCase();
    const list = items.filter((i) => !ql || i.name.toLowerCase().includes(ql) || String(i.label).toLowerCase().includes(ql)).slice(0, 24);
    box.innerHTML = list.length ? list.map((i) => `<button class="mini" data-act="pickItem" data-name="${esc(i.name)}" data-label="${esc(i.label)}"><div class="av" style="overflow:hidden"><img src="${esc(imgUrl(i.name))}" alt="" style="max-width:20px;max-height:20px" onerror="this.remove()"></div><b>${esc(i.label)}</b><span>${esc(i.name)}</span></button>`).join('')
        : '<div class="label-row">No matching items</div>';
}, 200);

const INPUTS = {
    historySearch: (v) => { S.history.search = v; reloadHistory(); },
    productSearch: (v) => { S.order.search = v; renderProducts(); },
    playerSearch: (v) => { S.order.query = v.trim(); searchPlayers(S.order.query); },
    discount: (v) => { const c = orderCompany(); S.order.discount = Math.max(0, Math.min(num(v), c ? num(c.maxDiscount, 100) : 0)); renderOrderFoot(); },
    notes: (v) => { S.order.notes = v; },
    bossSearch: (v) => { S.boss.inv.search = v; reloadBoss(); },
    adminInvSearch: (v) => { S.admin.inv.search = v; reloadAdminInv(); },
    logSearch: (v) => { S.admin.logs.search = v; reloadLogs(); },
    itemSearch: (v) => showItems(v, topModal()),
    payAmount: (v) => { const m = topModal(); if (m && m.payState) { m.payState.amount = v; const pos = document.activeElement; m.render(); const inp = $('[data-input="payAmount"]', m.el); if (inp && pos) { inp.focus(); inp.setSelectionRange(inp.value.length, inp.value.length); } } },
    posSearch: (v) => { S.pos.search = v; renderPosGrid(); },
    posDiscount: (v) => { S.pos.discount = Math.max(0, Math.min(num(v), num(S.pos.company.maxDiscount, 100))); renderPos(); const inp = $('[data-input="posDiscount"]'); if (inp) { inp.focus(); inp.setSelectionRange(inp.value.length, inp.value.length); } syncPos(); },
};
const CHANGES = {
    dueDays: (v) => { S.order.dueDays = v; },
    adminCatalogCompany: (v) => { S.admin.catalogCompany = v; viewAdminCatalog(); },
    adminInvCompany: (v) => { S.admin.inv.companyId = v; loadAdminInvoices(); },
};

// pay modal / misc actions that need the current modal
Object.assign(A, {
    payMethod: (d) => { const m = topModal(); if (m?.payState) { m.payState.method = d.m; m.render(); } },
    payFull: (d) => { const m = topModal(); if (m?.payState) { m.payState.full = d.v === '1'; m.render(); } },
    payTip: (d) => { const m = topModal(); if (m?.payState) { m.payState.tipPct = +d.v; m.payState.tipCustom = null; m.render(); } },
});

document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-act]');
    if (!el || el.disabled) return;
    const fn = A[el.dataset.act];
    if (fn) { e.preventDefault(); fn(el.dataset, el, e); }
});
document.addEventListener('input', (e) => {
    const key = e.target.dataset?.input;
    if (key && INPUTS[key]) INPUTS[key](e.target.value, e.target);
});
document.addEventListener('change', (e) => {
    const key = e.target.dataset?.change;
    if (key && CHANGES[key]) CHANGES[key](e.target.value, e.target);
});
$('#closeBtn').addEventListener('click', () => closeCurrent());

function closeCurrent() {
    if (S.mode === 'pos') {
        S.pos = null; hideShell(); nui('posClose');
    } else if (S.mode === 'billing' || S.mode === 'admin') {
        hideShell(); nui('close');
    }
}

document.addEventListener('keydown', (e) => {
    const typing = ['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName);
    if (e.key === 'Escape') {
        e.preventDefault();
        if (topModal()) { topModal().close(null); return; }
        if (S.display && S.display.stage === 'checkout' && !S.mode) { A.dispDecline(); return; }
        if (S.display && S.display.stage === 'done' && !S.mode) { finishDisplay(); return; }
        closeCurrent();
        return;
    }
    if (e.key === '/' && !typing && S.mode) {
        const input = document.querySelector('#main .search input');
        if (input) { e.preventDefault(); input.focus(); }
    }
    if (e.key === 'Enter' && !typing && topModal()?.ok) { topModal().ok(); }
    else if (e.key === 'Enter' && S.mode === 'billing' && S.tab === 'new' && !typing) { sendInvoice(); }
});

// ═══════════════ MESSAGES FROM LUA ═══════════════
window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};
    switch (action) {
        case 'open': openBilling(data); break;
        case 'openAdmin': openAdmin(data); break;
        case 'close': hideShell(); break;
        case 'toast': toast(data.title, data.message, data.type); break;
        case 'refresh': if (S.mode === 'billing') refreshContext(); else if (S.mode === 'admin') reloadAdmin(); break;
        case 'invoiceNew':
            if (S.mode === 'billing' && S.ctx) {
                S.ctx.invoices.unshift(data); S.ctx.stats.open++; S.ctx.stats.owed = round2(S.ctx.stats.owed + data.remaining);
                if (['home', 'bills'].includes(S.tab)) renderBilling();
            }
            break;
        case 'receipt':
            if (!S.mode) { S.mode = 'receipt'; S.receiptClose = 'close'; }
            showReceipt(data);
            break;
        case 'posOpen': openPos(data); break;
        case 'posState': onPosState(data); break;
        case 'displayOpen': displayOpen(data); break;
        case 'displayUpdate': displayUpdate(data); break;
        case 'displayCheckout': displayCheckout(data); break;
        case 'displayClose': displayClose(); break;
    }
});

// ═══════════════════════════════════════════════════════════════
// BROWSER PREVIEW (only runs outside FiveM: open html/index.html)
// ═══════════════════════════════════════════════════════════════
const Mock = (() => {
    const now = Date.now(); const H = 3600000;
    const company = {
        id: 'burgershot', label: 'Burgershot', shortName: 'BS', job: 'burgershot', taxRate: 0.08, allowDiscounts: true, maxDiscount: 50, allowCustomItems: false, allowTips: true, dueDays: 3,
        categories: [{ id: 'burgers', label: 'Burgers', icon: 'fa-burger' }, { id: 'sides', label: 'Sides', icon: 'fa-bowl-food' }, { id: 'drinks', label: 'Drinks', icon: 'fa-mug-hot' }],
        products: [
            { id: 'bleeder', name: 'Bleeder Burger', price: 8.99, category: 'burgers' }, { id: 'moneyshot', name: 'Money Shot Burger', price: 12.99, category: 'burgers' },
            { id: 'torpedo', name: 'Torpedo', price: 10.49, category: 'burgers' }, { id: 'fries', name: 'Fries', price: 3.99, category: 'sides' },
            { id: 'rings', name: 'Onion Rings', price: 4.49, category: 'sides' }, { id: 'soda', name: 'E-Cola', price: 2.49, category: 'drinks' },
            { id: 'water', name: 'Water', price: 1.99, category: 'drinks' }, { id: 'shake', name: 'Meat Free Shake', price: 5.99, category: 'drinks' },
        ],
        quickBills: [{ id: 'combo1', label: 'Bleeder Combo', amount: 12.99, description: 'Burger + Fries + Drink' }, { id: 'combo2', label: 'Money Shot Combo', amount: 16.99, description: 'Premium Burger + Fries + Drink' }],
    };
    const inv = (id, o) => Object.assign({ id, company: 'Los Santos Customs', companyId: 'mechanic', senderName: 'Theo Kane', targetName: 'John Doe', direction: 'received', items: [{ name: 'Full Repair', price: 1500, quantity: 1 }], subtotal: 1500, tax: 120, discount: 0, total: 1620, lateFee: 0, amountPaid: 0, tip: 0, remaining: 1620, status: 'pending', createdAt: now - 5 * H, dueDate: now + 50 * H, tipsAllowed: true }, o);
    const invoices = [
        inv('INV-7KQ2MZ4P', { status: 'overdue', lateFee: 162, remaining: 1782, dueDate: now - 20 * H, createdAt: now - 80 * H }),
        inv('INV-H3XN8W2D', { company: 'Los Santos Police Department', companyId: 'police', senderName: 'Maya Reyes', items: [{ name: 'Speeding Violation', price: 500, quantity: 1 }, { name: 'Illegal Parking', price: 200, quantity: 1 }], subtotal: 700, tax: 0, total: 700, remaining: 450, amountPaid: 250, status: 'partial', notes: 'Plate 46EEK572 · Vinewood Blvd', tipsAllowed: false }),
        inv('INV-P9TR4LBC', { company: 'Pillbox Medical Center', companyId: 'ambulance', senderName: 'Sam Brooks', items: [{ name: 'Medical Examination', price: 200, quantity: 1 }], subtotal: 200, tax: 0, total: 200, remaining: 200, status: 'disputed', disputeReason: 'I was never treated', tipsAllowed: false }),
    ];
    const recent = [
        inv('INV-B2WQ7ZK4', { direction: 'sent', company: 'Burgershot', targetName: 'Rafael Salas', total: 25.88, status: 'paid', createdAt: now - 0.4 * H }),
        invoices[0], invoices[1],
        inv('INV-M8DD2KXA', { direction: 'sent', company: 'Burgershot', targetName: 'Jenny Pork', total: 41.20, status: 'pending', createdAt: now - 7 * H }),
    ];
    const ctx = {
        player: { name: 'John Doe', job: 'Burgershot', jobName: 'burgershot', grade: 'Manager', cash: 820, bank: 15240.55 },
        company, perms: { canBill: true, canPersonal: true, canRemote: false, isBoss: true, isAdmin: true, canManageCatalog: true, canRefund: true, canDispute: true },
        settings: { currency: '$', version: '2.0.0', defaultTaxRate: 0.08, maxItems: 30, maxQuantity: 100, maxNote: 250, dueDays: 3, customDue: true, maxDueDays: 14, allowPartial: true, minPartial: 50, methods: { bank: true, cash: true }, tips: [0, 10, 15, 20], maxTip: 50, imagePath: 'nui://ox_inventory/web/images/%s.png' },
        invoices, recent, stats: { owed: 2432, open: 3, paid30: 3120.4, sent30: 47, toCollect: 0 },
    };
    const dash = {
        today: 412.6, week: 3988.15, month: 15420.8, tips: 612, outstanding: 284.3, openCount: 6, overdueCount: 1, disputedCount: 1, invoices30: 318, avgTicket: 24.8, balance: 48210.5, banking: 'nayzeee-banking',
        daily: ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'].map((label, i) => ({ key: `2026-10-0${4 + i}`, label, value: [520, 780, 410, 655, 590, 620.55, 412.6][i], count: [21, 33, 17, 26, 24, 25, 16][i] })),
        leaderboard: [{ name: 'John Doe', invoices: 112, collected: 5480.2, tips: 240 }, { name: 'Maya Reyes', invoices: 96, collected: 4610.75, tips: 198 }, { name: 'Theo Kane', invoices: 71, collected: 3302.1, tips: 120 }, { name: 'Sam Brooks', invoices: 39, collected: 2027.75, tips: 54 }],
        recent: recent.map((r) => Object.assign({}, r, { company: 'Burgershot', senderName: 'John Doe' })), company,
    };
    const admin = {
        companies: [Object.assign({ isConfig: true }, company), { id: 'police', label: 'Los Santos Police Department', shortName: 'LSPD', job: 'police', taxRate: 0, products: Array.from({ length: 12 }, (_, i) => ({ id: 'fine_' + i, name: 'Citation ' + (i + 1), price: 100 * (i + 1) })), quickBills: [], categories: [], allowCustomItems: true, isConfig: true }, { id: 'mechanic', label: 'Los Santos Customs', shortName: 'LSC', job: 'mechanic', taxRate: 0.08, products: Array.from({ length: 15 }, (_, i) => ({ id: 'svc_' + i, name: 'Service ' + (i + 1), price: 150 * (i + 1) })), quickBills: [], categories: [], allowDiscounts: true, allowCustomItems: true, allowTips: true, isConfig: true, hasOverride: true }],
        registers: [{ id: 'burgershot_counter1', label: 'Burgershot Counter', company: 'burgershot', companyLabel: 'Burgershot', coords: { x: 197.42, y: -850.75, z: 30.96 }, radius: 2, source: 'config' }],
        stats: { invoicesToday: 64, revenueWeek: 48210.5, outstanding: 9310.4, openCount: 41, disputedCount: 2, pendingPayouts: 320, byCompany: [{ id: 'mechanic', label: 'Los Santos Customs', revenue: 18210 }, { id: 'burgershot', label: 'Burgershot', revenue: 15420.8 }, { id: 'police', label: 'Los Santos Police Department', revenue: 9800 }] },
        system: { framework: 'qbox', banking: 'nayzeee-banking', inventory: 'ox_inventory', version: '2.0.0', imagePath: '' },
    };
    const ok = (data) => ({ ok: true, data });
    const rpc = {
        getContext: () => ok(ctx), getNearby: () => ok([{ id: 12, name: 'Rafael Salas', distance: 1.8 }, { id: 31, name: 'Jenny Pork', distance: 4.2 }]),
        searchPlayers: () => ok([{ type: 'online', id: 12, name: 'Rafael Salas' }]),
        getHistory: () => ok({ rows: recent.concat(invoices), hasMore: false }), getInvoice: (p) => ok(Object.assign({ payments: [], canCancel: false }, [...invoices, ...recent].find((i) => i.id === p.invoiceId))),
        'boss:getDashboard': () => ok(dash), 'boss:getInvoices': () => ok({ rows: dash.recent, hasMore: false }),
        'admin:getData': () => ok(admin), 'admin:getInvoices': () => ok({ rows: invoices, hasMore: false }), 'admin:getLogs': () => ok({ rows: [{ timestamp: now, player: 'John Doe', action: 'invoice_paid', data: { invoice: 'INV-7KQ2MZ4P', amount: 1620 } }], hasMore: false }),
        createInvoice: () => ok({ invoiceId: 'INV-NEW12345', total: 10, targetName: 'Rafael Salas' }),
        payInvoice: (p) => ok({ amount: 100, tip: 0, charged: 100, method: p.method, status: 'paid', remaining: 0 }),
        getItems: () => ok([{ name: 'burger', label: 'Burger' }]),
    };
    return {
        nui: async (event, data) => {
            if (event === 'rpc') return (rpc[data.name] || (() => ok(true)))(data.payload || {});
            return 'ok';
        },
        boot: () => {
            const view = new URLSearchParams(location.search).get('view') || 'billing';
            document.body.style.background = 'radial-gradient(1100px 640px at 50% -8%,#1b2224 0%,transparent 62%),#2a2f33';
            if (view === 'admin') openAdmin(admin);
            else if (view === 'pos') { openPos({ register: admin.registers[0], company, nearby: [{ id: 12, name: 'Rafael Salas', distance: 1.4 }] }); }
            else if (view === 'display') {
                displayOpen({ company: 'Burgershot', register: 'Front Counter', employee: 'John Doe' });
                displayCheckout({ invoice: Object.assign(inv('INV-B2WQ7ZK4', {}), { company: 'Burgershot', items: [{ name: 'Bleeder Burger', price: 8.99, quantity: 2 }, { name: 'Fries', price: 3.99, quantity: 1 }], subtotal: 21.97, tax: 1.76, total: 23.73 }), allowTips: true });
            } else openBilling(Object.assign({}, ctx, { tab: new URLSearchParams(location.search).get('tab') || 'home' }));
        },
    };
})();

if (!IN_GAME) document.addEventListener('DOMContentLoaded', () => Mock.boot());
