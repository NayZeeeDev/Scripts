// ═══════════════════════════════════════════════════════════════
// NAYZEEE BILLING · UI
// Every player-facing string goes through t(); every dynamic value through esc().
// Actions use data-act delegation, never inline handlers with data.
// ═══════════════════════════════════════════════════════════════
'use strict';

const IN_GAME = typeof GetParentResourceName === 'function';
const RES = IN_GAME ? GetParentResourceName() : 'nayzeee-billing';
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

// ═══════════════ STATE ═══════════════
const S = {
    mode: null,               // billing | pos | paper
    ctx: null,
    account: 'personal',      // personal | society
    page: 'overview',
    locale: {},
    currency: '$', currencyPos: 'before',
    title: 'Billing', brand: 'NAYZEEE', clock: true,
    dash: null,
    tables: {},               // [account:box] = table state
    tpl: null,
    act: { page: 1, search: '', category: '', rows: [], total: 0 },
    perms: null,
    insp: { type: 'citizen', query: '', results: [], jobView: false, subject: null, tab: 'search', table: null, registers: null },
    rail: null,
    pos: null,
    display: null,
    paperClose: 'close',
};

// ═══════════════ NUI ═══════════════
async function nui(event, data = {}) {
    if (!IN_GAME) return Mock.nui(event, data);
    try {
        const r = await fetch(`https://${RES}/${event}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
        return await r.json();
    } catch (e) { return null; }
}
async function api(name, payload = {}) {
    const r = await nui('rpc', { name, payload });
    return r && typeof r === 'object' ? r : { ok: false, error: t('error.no_response', 'No response from server') };
}
async function call(name, payload) {
    const r = await api(name, payload);
    if (!r.ok) { toast(t('label.error', 'Error'), r.error || t('error.generic', 'Something went wrong'), 'error'); return null; }
    return r.data === undefined || r.data === null ? true : r.data;
}

// ═══════════════ UTILS ═══════════════
const esc = (v) => String(v ?? '').replace(/[&<>"'`]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '`': '&#96;' }[m]));
const num = (v, d = 0) => { const n = parseFloat(v); return Number.isFinite(n) ? n : d; };
const r2 = (n) => Math.round((num(n) + Number.EPSILON) * 100) / 100;
function t(key, fallback, vars) {
    let s = S.locale[key] ?? fallback ?? key;
    if (vars) s = s.replace(/\{(\w+)\}/g, (m, k) => (vars[k] !== undefined ? vars[k] : m));
    return s;
}
function money(n) {
    const v = r2(n);
    let s = Math.abs(v).toFixed(2).replace(/\.00$/, '').replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    s = S.currencyPos === 'after' ? s + S.currency : S.currency + s;
    return (v < 0 ? '-' : '') + s;
}
const initials = (n) => esc(String(n || '?').trim().split(/\s+/).map((p) => p[0]).slice(0, 2).join('').toUpperCase());
const pct = (n) => `${r2(num(n) * 100)}%`;
function toDate(v) {
    if (v === null || v === undefined || v === '') return null;
    if (v instanceof Date) return isNaN(v) ? null : v;
    if (typeof v === 'number') return new Date(v);
    const d = new Date(String(v).replace(' ', 'T'));
    return isNaN(d) ? null : d;
}
const fmtDate = (v) => { const d = toDate(v); return d ? d.toLocaleDateString('en-US', { month: 'short', day: '2-digit', year: 'numeric' }) : '—'; };
const fmtLong = (v) => { const d = toDate(v); return d ? d.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) : '—'; };
const fmtTime = (v) => { const d = toDate(v); return d ? d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) : ''; };
function ago(v) {
    const d = toDate(v); if (!d) return '';
    const s = Math.round((Date.now() - d.getTime()) / 1000);
    if (s < 60) return t('time.now', 'just now');
    if (s < 3600) return t('time.m', '{n}m ago', { n: Math.floor(s / 60) });
    if (s < 86400) return t('time.h', '{n}h ago', { n: Math.floor(s / 3600) });
    return t('time.d', '{n}d ago', { n: Math.floor(s / 86400) });
}
function dueIn(v, status) {
    if (status === 'overdue') return { text: t('status.overdue', 'Overdue'), hot: true };
    const d = toDate(v); if (!d) return { text: '' };
    const h = (d.getTime() - Date.now()) / 3600000;
    if (h < 0) return { text: t('status.overdue', 'Overdue'), hot: true };
    if (h < 24) return { text: t('due.hours', 'Due in {n}h', { n: Math.max(1, Math.round(h)) }) };
    const days = Math.round(h / 24);
    return { text: days === 1 ? t('due.tomorrow', 'Due tomorrow') : t('due.days', 'Due in {n} days', { n: days }) };
}
const OPEN = ['pending', 'partial', 'overdue'];
const isOpen = (inv) => OPEN.includes(inv.status);
const STATUS_LABEL = () => ({ pending: t('status.pending', 'Pending'), partial: t('status.partial', 'Partial'), overdue: t('status.overdue', 'Overdue'),
    disputed: t('status.disputed', 'Disputed'), paid: t('status.paid', 'Paid'), cancelled: t('status.cancelled', 'Cancelled'), refunded: t('status.refunded', 'Refunded') });
const st = (s) => `<span class="st ${esc(s)}">${esc(STATUS_LABEL()[s] || s)}</span>`;
function debounce(fn, ms) { let h; return (...a) => { clearTimeout(h); h = setTimeout(() => fn(...a), ms); }; }
function hexRgba(hex, a) {
    const m = /^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i.exec(hex || '');
    if (!m) return null;
    return `rgba(${parseInt(m[1], 16)},${parseInt(m[2], 16)},${parseInt(m[3], 16)},${a})`;
}
function applyColors(c = {}) {
    const root = document.documentElement.style;
    const set = (v, val) => { if (val) root.setProperty(v, val); };
    set('--accent', c.accent); set('--accent-hi', c.accentHi); set('--accent-lo', c.accentLo);
    set('--accent-wash', hexRgba(c.accent, 0.12)); set('--accent-edge', hexRgba(c.accent, 0.36));
    set('--danger', c.danger); set('--danger-wash', hexRgba(c.danger, 0.12)); set('--danger-edge', hexRgba(c.danger, 0.36));
    set('--warning', c.warning); set('--warning-wash', hexRgba(c.warning, 0.12)); set('--warning-edge', hexRgba(c.warning, 0.36));
    set('--success', c.success); set('--success-wash', hexRgba(c.success, 0.12)); set('--success-edge', hexRgba(c.success, 0.36));
    set('--c-received', c.chartReceived); set('--c-paid', c.chartPaid);
    set('--base', c.background); set('--panel', c.panel);
}
function copyText(text) {
    const ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    ta.remove();
    if (!ok && navigator.clipboard) { navigator.clipboard.writeText(text).catch(() => {}); ok = true; }
    toast(ok ? t('toast.copied', 'Reference copied') : t('toast.copy_failed', 'Copy failed'), text, ok ? 'success' : 'error');
}

// ═══════════════ ICONS ═══════════════
const P = {
    grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    inbox: '<path d="M3 13h5l1.5 3h5L16 13h5"/><path d="M5.5 5h13L21 13v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-5l2.5-8z"/>',
    file: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>',
    copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
    history: '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5M12 7v5l3 2"/>',
    users: '<circle cx="9" cy="8" r="3.2"/><path d="M3 20a6 6 0 0 1 12 0M16 4.5a3.2 3.2 0 0 1 0 6.4M17.5 14a6 6 0 0 1 3.5 6"/>',
    userkey: '<circle cx="9" cy="8" r="3.5"/><path d="M3 20a6 6 0 0 1 9.5-4.9"/><circle cx="17.5" cy="15.5" r="2"/><path d="M19 17l2.5 2.5M20.5 18.5l-1 1"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
    plus: '<path d="M12 5v14M5 12h14"/>', minus: '<path d="M5 12h14"/>',
    chevron: '<path d="m6 9 6 6 6-6"/>', chevup: '<path d="m6 15 6-6 6 6"/>', chevl: '<path d="m15 6-6 6 6 6"/>', chevr: '<path d="m9 6 6 6-6 6"/>',
    chevrons: '<path d="m7 13 5-5 5 5M7 18l5-5 5 5"/>',
    x: '<path d="M6 6l12 12M18 6 6 18"/>', check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    doc: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5z"/><path d="M14 3v5h5"/>',
    trend: '<path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/>', trenddown: '<path d="M3 7l6 6 4-4 8 8"/><path d="M15 17h6v-6"/>',
    wallet: '<path d="M4 7a2 2 0 0 1 2-2h12v4"/><path d="M4 7v11a2 2 0 0 0 2 2h14V9H6a2 2 0 0 1-2-2z"/><path d="M16 14.5h.01"/>',
    receive: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18M15 15l2 2 3-3"/>',
    card: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18M7 15h3"/>',
    cash: '<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/>',
    building: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M9 7h1M14 7h1M9 11h1M14 11h1M9 15h1M14 15h1M10 21v-3h4v3"/>',
    user: '<circle cx="12" cy="8" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
    eye: '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
    printer: '<path d="M7 9V3h10v6M7 17H5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-2"/><rect x="7" y="14" width="10" height="7" rx="1"/>',
    ban: '<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6 12.8 12.8"/>',
    filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
    trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
    edit: '<path d="M4 20h4L19 9l-4-4L4 16v4z"/><path d="m13 7 4 4"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    grip: '<circle cx="9" cy="6" r="1"/><circle cx="15" cy="6" r="1"/><circle cx="9" cy="12" r="1"/><circle cx="15" cy="12" r="1"/><circle cx="9" cy="18" r="1"/><circle cx="15" cy="18" r="1"/>',
    alert: '<path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8v.01"/>',
    checkc: '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
    arrowup: '<path d="M12 19V5M6 11l6-6 6 6"/>', arrowdown: '<path d="M12 5v14M6 13l6 6 6-6"/>',
    send: '<path d="M21 3 10 14"/><path d="M21 3l-7 18-4-7-7-4 18-7z"/>',
    flag: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>', undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    save: '<path d="M5 3h11l3 3v13a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M7 3v5h8V3M7 21v-7h10v7"/>',
    hash: '<path d="M5 9h14M5 15h14M10 4 8 20M16 4l-2 16"/>',
    register: '<rect x="3" y="11" width="18" height="10" rx="2"/><path d="M6 11V5h8v6M14 7h4l1 4M7 15h2M11 15h2M15 15h2"/>',
    pin: '<path d="M12 21s-7-6.1-7-11.5a7 7 0 0 1 14 0C19 14.9 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
    crosshair: '<circle cx="12" cy="12" r="7.5"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/><circle cx="12" cy="12" r="1.2"/>',
    teleport: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4"/><circle cx="12" cy="12" r="4"/>',
    refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/>',
    // template picker
    car: '<path d="M3 13l2-5.5A2 2 0 0 1 6.9 6h10.2a2 2 0 0 1 1.9 1.5L21 13v5h-3M3 18v-5h18M6.5 18h11"/><circle cx="7" cy="18" r="1.6"/><circle cx="17" cy="18" r="1.6"/>',
    sparkle: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>',
    wrench: '<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18v3h3l6.3-6.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.4-.6-.6-2.4 2.5-2.5z"/>',
    medkit: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V4h6v3M12 11v5M9.5 13.5h5"/>',
    badge: '<path d="M12 3 4 6v6c0 5 3.4 8.3 8 9 4.6-.7 8-4 8-9V6l-8-3z"/><path d="m9 12 2 2 4-4"/>',
    shield: '<path d="M12 3 4 6v6c0 5 3.4 8.3 8 9 4.6-.7 8-4 8-9V6l-8-3z"/>',
    burger: '<path d="M4 11a8 6 0 0 1 16 0z"/><path d="M3 14h18M5 17h14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2z"/>',
    briefcase: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 13h18"/>',
    activity: '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
    award: '<circle cx="12" cy="9" r="5"/><path d="M8.5 13 7 21l5-3 5 3-1.5-8"/>',
    ticket: '<path d="M3 8a2 2 0 0 0 2-2h14a2 2 0 0 0 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 0-2 2H5a2 2 0 0 0-2-2v-2a2 2 0 0 0 0-4z"/><path d="M13 6v12"/>',
    chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
    bell: '<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 21h4"/>',
    book: '<path d="M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z"/><path d="M5 17a3 3 0 0 1 3-3h11"/>',
    bookopen: '<path d="M2 5h7a3 3 0 0 1 3 3v12a2 2 0 0 0-2-2H2zM22 5h-7a3 3 0 0 0-3 3v12a2 2 0 0 1 2-2h8z"/>',
    calendar: '<rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
    camera: '<path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z"/><circle cx="12" cy="13" r="3.5"/>',
    truck: '<path d="M3 6h11v10H3zM14 9h4l3 3v4h-7"/><circle cx="7" cy="17" r="1.8"/><circle cx="17" cy="17" r="1.8"/>',
    home: '<path d="M3 11 12 4l9 7"/><path d="M5 10v10h14V10M10 20v-6h4v6"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 6l3 3M15 8l2 2"/>',
    tag: '<path d="M3 12V3h9l9 9-9 9-9-9z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
    gift: '<rect x="3" y="8" width="18" height="4"/><path d="M5 12v8h14v-8M12 8v12M12 8S10 3 7.5 4 9 8 12 8zM12 8s2-5 4.5-4S15 8 12 8z"/>',
    coffee: '<path d="M4 9h12v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM16 10h2a2 2 0 0 1 0 4h-2M8 3v3M12 3v3"/>',
    scissors: '<circle cx="6" cy="7" r="2.5"/><circle cx="6" cy="17" r="2.5"/><path d="M8 8.5 20 18M8 15.5 20 6"/>',
    fuel: '<path d="M4 21V5a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v16M3 21h13M15 9h2a2 2 0 0 1 2 2v6a1.5 1.5 0 0 0 3 0V8l-3-3M7 8h5"/>',
    gavel: '<path d="m14 4 6 6M12 6l6 6M10 12l-7 7 2 2 7-7M9 9l6-6 6 6-6 6z"/>',
    heart: '<path d="M12 20s-8-5-8-11a4.5 4.5 0 0 1 8-2.8A4.5 4.5 0 0 1 20 9c0 6-8 11-8 11z"/>',
    star: '<path d="m12 3 2.7 5.6 6.3.9-4.5 4.4 1 6.1L12 17.1 6.5 20l1-6.1L3 9.5l6.3-.9z"/>',
    box: '<path d="M21 8 12 3 3 8v8l9 5 9-5V8z"/><path d="m3 8 9 5 9-5M12 13v8"/>',
    cart: '<path d="M3 4h2l2.5 11h11L21 7H6.5"/><circle cx="9" cy="19" r="1.5"/><circle cx="17" cy="19" r="1.5"/>',
    music: '<path d="M9 18V5l11-2v13"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/>',
    pill: '<rect x="3" y="9" width="18" height="6" rx="3" transform="rotate(-45 12 12)"/><path d="m9 9 6 6"/>',
};
const TEMPLATE_ICONS = ['file', 'car', 'sparkle', 'wrench', 'medkit', 'badge', 'shield', 'burger', 'briefcase', 'activity', 'alert', 'award', 'ticket', 'chart', 'bell', 'book',
    'bookopen', 'building', 'calendar', 'camera', 'truck', 'home', 'key', 'tag', 'gift', 'coffee', 'scissors', 'fuel', 'gavel', 'heart', 'star', 'box', 'cart', 'music', 'pill', 'users'];
const TEMPLATE_COLORS = ['blue', 'red', 'amber', 'teal', 'cyan', 'violet', 'gray', 'rainbow'];
const ic = (n) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${P[n] || P.file}</svg>`;
const ticon = (icon, color, lg) => `<span class="ticon ${lg ? 'lg' : ''} c-${esc(TEMPLATE_COLORS.includes(color) ? color : 'gray')}">${ic(icon)}</span>`;

// ═══════════════ TOASTS ═══════════════
function toast(title, message, type = 'info') {
    const box = $('#toasts');
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.innerHTML = `<div class="ti">${ic(type === 'error' ? 'info' : type === 'warning' ? 'alert' : type === 'success' ? 'check' : 'bell')}</div><div><b>${esc(title)}</b><p>${esc(message)}</p></div>`;
    box.appendChild(el);
    while (box.children.length > 4) box.firstChild.remove();
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 220); }, 4600);
}

// ═══════════════ MODALS ═══════════════
const stack = [];
function openModal(html, opts = {}) {
    const o = document.createElement('div');
    o.className = 'overlay';
    o.innerHTML = html;
    $('#modals').appendChild(o);
    const m = { el: o, onClose: opts.onClose };
    m.close = (v) => { const i = stack.indexOf(m); if (i >= 0) stack.splice(i, 1); o.remove(); if (m.onClose) m.onClose(v); };
    o.addEventListener('mousedown', (e) => { if (e.target === o) m.close(null); });
    stack.push(m);
    const f = o.querySelector('[autofocus]'); if (f) setTimeout(() => f.focus(), 30);
    return m;
}
const topModal = () => stack[stack.length - 1];
const closeModals = () => { while (stack.length) stack[stack.length - 1].close(null); };
const mh = (title, sub, icon) => `<div class="mh">${icon ? `<div class="tile sm teal">${ic(icon)}</div>` : ''}<div><h4>${title}</h4>${sub ? `<p>${sub}</p>` : ''}</div><button class="ibtn x" data-act="mClose">${ic('x')}</button></div>`;

function confirmBox({ title, text, ok = t('btn.confirm', 'Confirm'), danger = false, icon = 'alert' }) {
    return new Promise((res) => {
        const m = openModal(`<div class="modal w380">${mh(esc(title), '', icon)}<div class="mb"><p class="copy">${esc(text)}</p></div>
            <div class="mf"><button class="btn line" data-act="mClose">${t('btn.cancel', 'Cancel')}</button><button class="btn ${danger ? 'red' : 'pri'}" data-act="mOk">${esc(ok)}</button></div></div>`,
            { onClose: (v) => res(v === true) });
        m.ok = () => m.close(true);
    });
}
function promptBox({ title, text, placeholder = '', ok = t('btn.submit', 'Submit'), danger = false, required = false, icon = 'edit', max = 200 }) {
    return new Promise((res) => {
        const m = openModal(`<div class="modal">${mh(esc(title), '', icon)}<div class="mb">${text ? `<p class="copy">${esc(text)}</p>` : ''}
            <div class="field"><textarea id="pIn" maxlength="${max}" placeholder="${esc(placeholder)}" autofocus></textarea></div></div>
            <div class="mf"><button class="btn line" data-act="mClose">${t('btn.cancel', 'Cancel')}</button><button class="btn ${danger ? 'red' : 'pri'}" data-act="mOk">${esc(ok)}</button></div></div>`,
            { onClose: (v) => res(typeof v === 'string' ? v : null) });
        m.ok = () => {
            const v = $('#pIn', m.el).value.trim();
            if (required && v.length < 5) { toast(t('label.required', 'Required'), t('toast.reason_needed', 'Please add a short reason'), 'warning'); return; }
            m.close(v);
        };
    });
}

// ═══════════════ POPOVERS / DROPDOWNS / CONTEXT MENU ═══════════════
let openPop = null; // { el, onClose }
function closePop() { if (openPop) { const p = openPop; openPop = null; p.el.remove(); if (p.owner) p.owner.classList.remove('open', 'on'); if (p.onClose) p.onClose(); } }
function showPop(owner, html, cls, onClose) {
    closePop();
    const el = document.createElement('div');
    el.className = `pop ${cls}`;
    el.innerHTML = html;
    owner.appendChild(el);
    owner.classList.add('open');
    openPop = { el, owner, onClose };
    return el;
}

const DD = {}; // key -> { options, value, onChange, search }
function dd(key, cfg) {
    DD[key] = cfg;
    const o = (cfg.options || []).find((x) => String(x.value) === String(cfg.value));
    const icon = o && o.icon ? ticon(o.icon, o.color) : (cfg.icon ? `<span class="ico" style="color:var(--ink-3)">${ic(cfg.icon)}</span>` : '');
    return `<div class="dd" data-dd-wrap="${esc(key)}"><button class="dd-btn" data-act="ddOpen" data-key="${esc(key)}" ${cfg.disabled ? 'disabled' : ''}>${icon}
        <span class="v ${o ? '' : 'ph'}">${esc(o ? o.label : cfg.placeholder || t('label.select', 'Select'))}</span>${ic('chevron')}</button></div>`;
}
function ddOptions(key, query = '') {
    const cfg = DD[key];
    const q = query.toLowerCase();
    const list = (cfg.options || []).filter((o) => !q || String(o.label).toLowerCase().includes(q) || String(o.sub || '').toLowerCase().includes(q));
    if (!list.length) return `<div class="dd-empty">${esc(cfg.empty || t('label.no_results', 'No results'))}</div>`;
    return list.map((o) => `<button class="dd-opt ${String(o.value) === String(cfg.value) ? 'on' : ''}" data-act="ddPick" data-key="${esc(key)}" data-v="${esc(o.value)}">
        ${o.icon ? ticon(o.icon, o.color) : ''}${o.dot !== undefined ? `<span class="dot ${o.dot ? 'on' : ''}"></span>` : ''}
        <span style="flex:1;min-width:0">${esc(o.label)}${o.sub ? `<small>${esc(o.sub)}</small>` : ''}</span>${String(o.value) === String(cfg.value) ? `<svg class="ck" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${P.check}</svg>` : ''}</button>`).join('');
}

function ctxMenu(x, y, head, items) {
    closePop();
    const el = document.createElement('div');
    el.className = 'ctx';
    el.innerHTML = (head ? `<div class="hd"><b>${esc(head[0])}</b><span>${esc(head[1])}</span></div>` : '')
        + items.filter(Boolean).map((i) => `<button class="${i.danger ? 'danger' : ''}" data-act="${esc(i.act)}" data-id="${esc(i.id)}">${ic(i.icon)}${esc(i.label)}</button>`).join('');
    document.body.appendChild(el);
    const w = el.offsetWidth, h = el.offsetHeight;
    el.style.left = Math.min(x, window.innerWidth - w - 8) + 'px';
    el.style.top = Math.min(y, window.innerHeight - h - 8) + 'px';
    openPop = { el };
}

// ═══════════════ SHELL ═══════════════
function perm(p) { return S.ctx?.society?.perms?.[p] === true; }
function pages() {
    const soc = S.account === 'society';
    const canInspect = S.ctx?.isAdmin || perm('inspect');
    return {
        overview: !soc || perm('overview'),
        received: !soc || perm('view_received'),
        sent: !soc || perm('view_sent') || perm('create'),
        templates: !soc || perm('templates_view') || perm('create'),
        activity: !soc || perm('activity'),
        permissions: soc && perm('permissions'),
        inspect: canInspect,
        admin: S.ctx?.isAdmin === true,
    };
}
function canCreate() { return S.account === 'society' ? perm('create') : S.ctx?.settings?.personalEnabled; }

function renderSide() {
    const av = pages();
    const soc = S.account === 'society' && S.ctx.society;
    const dash = S.dash && S.dash.account === S.account ? S.dash : null;
    const tally = dash ? dash.due : 0;
    const nav = (id, icon, label, extra = '') => av[id] ? `<button class="nav ${S.page === id ? 'on' : ''}" data-act="go" data-page="${id}">${ic(icon)}<span class="nl">${esc(label)}</span>${extra}</button>` : '';
    const grp = (label) => `<div class="grp"><span>${esc(label)}</span></div>`;
    const mgmt = nav('activity', 'history', t('nav.activity', 'Activity')) + nav('permissions', 'userkey', t('nav.permissions', 'Permissions'));
    const tools = nav('inspect', 'search', t('nav.inspect', 'Inspect'));
    const adminNav = nav('admin', 'shield', t('nav.admin', 'Billing Admin'));
    const p = S.ctx.player;
    const bal = soc ? S.ctx.society.balance : p.bank;
    const sub = soc ? `${S.ctx.society.label}${S.ctx.society.group ? ' · ' + S.ctx.society.group.label : ''}` : [p.job, p.grade].filter(Boolean).join(' · ');
    $('#side').innerHTML = `
        <div class="side-top">
            <div class="who"><span class="av lg">${initials(p.name)}</span><div><b>${esc(p.name)}</b><span>${esc(sub)}</span></div></div>
            <div class="pulse"><span id="sideClock">${esc(clockText())}</span>${sideStatus(dash)}</div>
        </div>
        <div class="nav-scroll">
            ${grp(t('nav.general', 'General'))}${nav('overview', 'grid', t('nav.overview', 'Overview'))}
            ${grp(t('nav.invoices', 'Invoices'))}
            ${nav('received', 'inbox', t('nav.received', 'Received'), tally ? `<span class="tally hot">${tally}</span>` : '')}
            ${nav('sent', 'file', t('nav.sent', 'Sent'))}${nav('templates', 'copy', t('nav.templates', 'Templates'))}
            ${mgmt ? grp(t('nav.management', 'Management')) + mgmt : ''}
            ${tools ? grp(t('nav.tools', 'Tools')) + tools : ''}
            ${adminNav ? grp(t('nav.admin_group', 'Admin')) + adminNav : ''}
        </div>
        <div class="side-foot">
            <div class="qa" id="acctWrap"><button class="acct" data-act="acctToggle">
                <span class="acct-top"><span class="tile sm ${soc ? 'blue' : 'teal'}">${ic(soc ? 'building' : 'user')}</span><span class="acct-name"><small>${t('acct.account', 'Account')}</small>${soc ? esc(S.ctx.society.short || S.ctx.society.label) : t('acct.personal', 'Personal Billing')}</span>${S.ctx.society ? '<span class="chev">' + ic('chevron') + '</span>' : ''}</span>
                <span class="acct-bal"><span>${t('acct.balance', 'Balance')}</span><b>${bal === null || bal === undefined ? '—' : money(bal)}</b></span></button></div>
        </div>`;
}

function clockText() { return new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }); }
function sideStatus(dash) {
    if (!dash) return `<span class="ps"><span class="dot on"></span>${t('side.online', 'Online')}</span>`;
    const overdue = (dash.alerts || []).filter((a) => a.status === 'overdue' && a.direction === 'received').length;
    if (overdue) return `<span class="ps bad"><span class="dot overdue"></span>${t('side.overdue', '{n} overdue', { n: overdue })}</span>`;
    if (dash.due) return `<span class="ps warn"><span class="dot pending"></span>${t('side.to_pay', '{n} to pay', { n: dash.due })}</span>`;
    return `<span class="ps ok"><span class="dot on"></span>${t('side.clear', 'All paid up')}</span>`;
}

function renderTop() {
    const soc = S.account === 'society' && S.ctx.society;
    const p = S.ctx.player;
    const bal = soc ? S.ctx.society.balance : p.bank;
    $('#top').innerHTML = `
        <div class="top-brand"><div class="mark"></div><div><b><span>${esc(S.brand)}</span>${esc(S.title)}</b><small>${esc(soc ? S.ctx.society.label : t('top.personal', 'Personal billing'))}</small></div></div>
        <div class="top-bar">
            <span class="signed"><span class="dot on"></span>${t('top.signed_in', 'Signed in as')} <b>${esc(p.name)}</b></span>
            ${S.ctx.settings && S.ctx.settings.version ? `<span class="ver">v${esc(S.ctx.settings.version)}</span>` : ''}
            <div class="top-right">
                <span class="wallet"><span>${t('top.cash', 'Cash')}</span><b>${money(p.cash)}</b></span>
                <span class="wallet"><span>${soc ? t('top.society', 'Society') : t('top.bank', 'Bank')}</span><b class="acc">${bal === null || bal === undefined ? '—' : money(bal)}</b></span>
                <button class="pill-close" data-act="close">${t('btn.close', 'Close')}</button>
            </div>
        </div>`;
}

function renderKeys(list) {
    const keys = list || [
        ['ESC', t('keys.close', 'Close')],
        canCreate() && ['N', t('keys.new', 'New invoice')],
        S.ctx.settings.payByReference && ['R', t('keys.ref', 'Pay by reference')],
        S.ctx.society && ['S', t('keys.switch', 'Switch account')],
        ['1–9', t('keys.pages', 'Jump to page')],
    ];
    $('#keys').innerHTML = keys.filter(Boolean).map(([k, l]) => `<span><kbd>${esc(k)}</kbd>${esc(l)}</span>`).join('')
        + `<span class="keys-r">${esc(S.brand)} ${esc(S.title)}</span>`;
}
setInterval(() => { const c = $('#sideClock'); if (c) c.textContent = clockText(); }, 15000);

const PAGE_META = () => {
    const soc = S.account === 'society' && S.ctx.society;
    const name = soc ? S.ctx.society.label : '';
    return {
        received: [t('nav.received', 'Received'), soc ? t('page.received_soc', 'Invoices billed to {name}', { name }) : t('page.received', 'Invoices billed to you')],
        sent: [t('nav.sent', 'Sent'), soc ? t('page.sent_soc', 'Invoices issued by {name}', { name }) : t('page.sent', 'Invoices you have issued')],
        templates: [t('nav.templates', 'Templates'), soc ? t('page.templates_soc', 'Saved items for {name}', { name }) : t('page.templates', 'Saved items for faster invoicing')],
        activity: [t('nav.activity', 'Activity'), t('page.activity', 'Every invoice, payment and change, newest first')],
        permissions: [t('nav.permissions', 'Permissions'), t('page.permissions', 'Who can do what at {name}', { name })],
        inspect: [t('nav.inspect', 'Inspect'), t('page.inspect', 'Look up the billing history of a citizen or society')],
        admin: [t('nav.admin', 'Billing Admin'), t('page.admin', 'Place and manage cash registers for every society')],
    };
};
function pageActions(page) {
    const soc = S.account === 'society';
    const out = [];
    if (page === 'received' || page === 'overview') {
        if (S.ctx.settings.payByReference) out.push(`<button class="btn line md" data-act="payRef">${ic('hash')}${t('btn.pay_ref', 'Pay by reference')}</button>`);
        const due = S.dash && S.dash.account === S.account ? S.dash.due : 1;
        if (!soc || perm('pay')) out.push(`<button class="btn line md" data-act="payAll" ${due ? '' : 'disabled'}>${ic('card')}${t('btn.pay_all', 'Pay All')}</button>`);
    }
    if ((page === 'sent' || page === 'overview') && canCreate()) out.push(`<button class="btn pri md" data-act="create">${ic('plus')}${t('btn.new_invoice', 'New Invoice')}</button>`);
    return out.join('');
}
function phead(title, sub, actions) {
    return `<div class="phead"><div><h2>${title}</h2>${sub ? `<p>${sub}</p>` : ''}</div>${actions ? `<div class="phead-act">${actions}</div>` : ''}</div>`;
}

function setPage(html) {
    let head = '';
    if (S.mode === 'billing' && S.page !== 'overview') {
        const m = PAGE_META()[S.page];
        if (m) head = phead(esc(m[0]), esc(m[1]), pageActions(S.page));
    }
    $('#page').innerHTML = `<div class="wm-wrap"><div class="wm"></div></div>${head}${html}`;
}

function go(page) {
    const av = pages();
    if (!av[page]) page = Object.keys(av).find((k) => av[k]) || 'received';
    S.page = page;
    closeRail(); closePop();
    renderSide(); renderTop(); renderKeys();
    ({ overview: pageOverview, received: () => pageTable('received'), sent: () => pageTable('sent'), templates: pageTemplates, activity: pageActivity, permissions: pagePermissions, inspect: pageInspect, admin: pageAdmin }[page] || pageOverview)();
}

function emptyState(icon, title, text) {
    return `<div class="empty"><div class="eico">${ic(icon)}</div><b>${esc(title)}</b>${text ? `<span>${esc(text)}</span>` : ''}</div>`;
}
const skel = (n = 5, h = 40) => Array.from({ length: n }, () => `<div class="sk" style="height:${h}px;margin:6px 0"></div>`).join('');

// ═══════════════ OPEN / CONTEXT ═══════════════
function open(data) {
    S.ctx = data.ctx;
    S.mode = 'billing';
    if (S.account === 'society' && !S.ctx.society) S.account = 'personal';
    S.tables = {}; S.dash = null; S.tpl = null; S.perms = null;
    $('#frame').classList.remove('hidden');
    go(data.page || 'overview');
    handleExtra(data.extra);
}
function handleExtra(extra) {
    if (!extra) return;
    if (extra.invoiceId) openRail(extra.invoiceId);
    if (extra.payRef !== undefined) payByReference(extra.payRef);
    if (extra.create) createInvoice(extra.create.recipientId);
    if (extra.registers && S.ctx.isAdmin && S.page !== 'admin') { S.insp.registers = null; go('admin'); }
}
async function refreshCtx() {
    if (S.mode !== 'billing') return;
    const r = await api('getContext');
    if (!r.ok) return;
    S.ctx = r.data;
    if (S.account === 'society' && !S.ctx.society) S.account = 'personal';
    Object.values(S.tables).forEach((tb) => { tb.stale = true; });
    S.dash = null;
    go(S.page);
    if (S.rail) openRail(S.rail.id, true);
}
function hide() {
    $('#frame').classList.add('hidden');
    S.mode = null;
    closeModals(); closePop(); closeRail();
}
function closeUI() {
    if (S.mode === 'pos') { S.pos = null; hide(); nui('posClose'); return; }
    hide(); nui('close');
}

// ═══════════════ OVERVIEW ═══════════════
function moneyShort(n) {
    const v = Math.abs(num(n));
    let s;
    if (v >= 1e6) s = `${r2(v / 1e6).toFixed(v >= 1e7 ? 0 : 1)}M`;
    else if (v >= 1e3) s = `${(v / 1e3).toFixed(v >= 1e4 ? 0 : 1)}k`;
    else s = String(Math.round(v));
    s = s.replace(/\.0(?=[kM])/, '');
    return (n < 0 ? '-' : '') + (S.currencyPos === 'after' ? `${s} ${S.currency}` : `${S.currency}${s}`);
}
function fmtWhen(v) {
    const d = toDate(v); if (!d) return '';
    const today = new Date(); const y = new Date(); y.setDate(today.getDate() - 1);
    const same = (a, b) => a.toDateString() === b.toDateString();
    if (same(d, today)) return `${t('time.today', 'Today')} ${fmtTime(d)}`;
    if (same(d, y)) return `${t('time.yesterday', 'Yesterday')} ${fmtTime(d)}`;
    return `${d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} ${fmtTime(d)}`;
}
const DAYS = () => [t('day.0', 'Sun'), t('day.1', 'Mon'), t('day.2', 'Tue'), t('day.3', 'Wed'), t('day.4', 'Thu'), t('day.5', 'Fri'), t('day.6', 'Sat')];

async function pageOverview() {
    setPage(`<div class="phead"><div><div class="sk" style="height:26px;width:280px"></div><div class="sk" style="height:12px;width:340px;margin-top:10px"></div></div></div>
        <div class="grid-4">${Array.from({ length: 4 }, () => '<div class="card kpi"><div class="sk" style="width:40px;height:40px"></div><div style="flex:1"><div class="sk" style="height:11px;width:50%"></div><div class="sk" style="height:22px;width:70%;margin-top:8px"></div></div></div>').join('')}</div>
        <div class="grid-ov"><div class="card pad">${skel(5, 34)}</div><div class="card pad">${skel(6, 34)}</div></div>`);
    if (!S.dash || S.dash.account !== S.account) {
        const d = await call('dashboard:get', { account: S.account });
        if (!d || S.page !== 'overview') return;
        S.dash = d; S.nx = 0;
        renderSide();
    }
    const d = S.dash;
    const soc = S.account === 'society' && S.ctx.society;
    const p = S.ctx.player;
    const hr = new Date().getHours();
    const greet = hr < 5 ? t('dash.evening', 'Good evening, {name}') : hr < 12 ? t('dash.morning', 'Good morning, {name}') : hr < 18 ? t('dash.afternoon', 'Good afternoon, {name}') : t('dash.evening', 'Good evening, {name}');
    const first = String(p.name || '').split(' ')[0];
    const bal = soc ? S.ctx.society.balance : (d.balance ?? p.bank);
    const overdue = d.alerts.filter((a) => a.status === 'overdue' && a.direction === 'received').length;
    const wk = d.weeks || [];
    const wDelta = (key) => (wk.length >= 2 ? pctChange(wk[wk.length - 1][key], wk[wk.length - 2][key]) : null);
    const deltaTxt = (v) => (v === null ? t('dash.this_week', 'This week') : `<span class="${v >= 0 ? 'up' : 'down'}">${v >= 0 ? '+' : ''}${v}%</span> ${t('dash.vs_last', 'vs last week')}`);
    const kpi = (icon, tone, label, value, sub, cls = '') => `<div class="card kpi ${cls}"><div class="tile lg ${tone}">${ic(icon)}</div><div class="kv"><span>${label}</span><b>${value}</b><small>${sub}</small></div></div>`;
    const kpis = soc ? [
        kpi('building', 'teal', t('dash.soc_balance', 'Society balance'), bal === null || bal === undefined ? '—' : money(bal), esc(S.ctx.society.label)),
        kpi('receive', 'amber', t('dash.owed_to', 'Owed to {name}', { name: esc(S.ctx.society.short || S.ctx.society.label) }), money(d.receivable || 0), t('dash.owed_sub', 'Open invoices you issued')),
        kpi('arrowdown', 'teal', t('dash.money_in', 'Money in'), money(d.receivedWeek), deltaTxt(wDelta('received'))),
        kpi('arrowup', 'red', t('dash.to_pay', 'To pay'), money(d.unpaid), t('dash.open_n', '{n} open · {o} overdue', { n: d.due, o: overdue }), d.unpaid > 0 ? 'hot' : ''),
    ] : [
        kpi('wallet', 'teal', t('dash.bank_balance', 'Bank balance'), bal === null || bal === undefined ? '—' : money(bal), t('dash.personal_acct', 'Personal account')),
        kpi('alert', 'red', t('dash.outstanding', 'Outstanding'), money(d.unpaid), t('dash.open_n', '{n} open · {o} overdue', { n: d.due, o: overdue }), d.unpaid > 0 ? 'hot' : ''),
        kpi('arrowdown', 'teal', t('dash.money_in', 'Money in'), money(d.receivedWeek), deltaTxt(wDelta('received'))),
        kpi('arrowup', 'blue', t('dash.money_out', 'Money out'), money(d.paidWeek), deltaTxt(wDelta('paid'))),
    ];
    const subline = soc ? t('dash.sub_soc', 'Invoices, payments and cashflow for {name}.', { name: esc(S.ctx.society.label) })
        : t('dash.sub', 'Your invoices, payments and cashflow in one place.');
    setPage(`${phead(esc(greet.replace('{name}', first)), subline, pageActions('overview'))}
        <div class="grid-4">${kpis.join('')}</div>
        <div class="grid-ov">
            <div class="ov-col">
                <div class="card cf" id="cf"></div>
                <div class="card"><div class="ch"><div><h3>${t('dash.latest', 'Latest activity')}</h3><p>${soc ? t('dash.across_soc', 'Across {name}', { name: esc(S.ctx.society.label) }) : t('dash.across', 'Across Personal billing')}</p></div>
                    ${pages().activity ? `<button class="btn line sm" data-act="go" data-page="activity">${ic('chart')}${t('btn.see_all', 'See all')}</button>` : ''}</div>
                    <div class="txl">${d.recent.length ? d.recent.slice(0, 5).map(txRow).join('') : emptyState('history', t('dash.no_recent', 'No activity yet'), t('dash.no_recent_sub', 'Invoices and payments show up here.'))}</div></div>
            </div>
            <div class="card nx" id="nx"></div>
        </div>`);
    renderWeekly();
    renderNext();
}

function pctChange(now, before) {
    now = num(now); before = num(before);
    if (before <= 0) return now > 0 ? 100 : 0;
    return Math.round(((now - before) / before) * 100);
}

function txRow(r) {
    const map = {
        payment_in: ['arrowdown', 'teal', t('tx.payment_in', 'Payment received'), 'pos'],
        payment_out: ['arrowup', 'red', t('tx.payment_out', 'Invoice paid'), 'neg'],
        created: ['send', 'blue', t('tx.created', 'Invoice sent'), ''],
        invoice_in: ['inbox', 'amber', t('tx.invoice_in', 'Invoice received'), ''],
        cancelled: ['ban', 'gray', t('tx.cancelled', 'Invoice cancelled'), 'void'],
    }[r.kind] || ['file', 'gray', '', ''];
    const sign = map[3] === 'pos' ? '+ ' : map[3] === 'neg' ? '− ' : '';
    return `<div class="txr" data-act="view" data-id="${r.id}"><div class="tile ${map[1]}">${ic(map[0])}</div>
        <div class="tx"><b>${esc(map[2])}${r.name ? ' · ' + esc(r.name) : ''}</b><span>${esc(fmtWhen(r.at))} · <span class="mono">${esc(r.ref)}</span></span></div>
        <span class="txa ${map[3]}">${sign}${money(r.amount)}</span></div>`;
}

// Weekly summary: banking-style bars, received and paid side by side for each of the last 7 days, today highlighted
function renderWeekly() {
    const el = $('#cf'); const d = S.dash; if (!el || !d) return;
    const series = d.series || [];
    const days = DAYS();
    const max = Math.max(1, ...series.map((x) => Math.max(num(x.received), num(x.paid))));
    const h = (v) => (num(v) <= 0 ? 6 : Math.max(10, Math.round((num(v) / max) * 100)));
    const recv = series.reduce((s, x) => s + num(x.received), 0), paid = series.reduce((s, x) => s + num(x.paid), 0);
    const deltaBadge = `<span class="badge ${d.delta >= 0 ? 'ok' : 'bad'}">${ic(d.delta >= 0 ? 'trend' : 'trenddown')}${d.delta >= 0 ? '+' : ''}${d.delta}%</span>`;
    const bar = (cls, v, label) => `<div class="wb ${cls} ${num(v) <= 0 ? 'quiet' : ''}" style="height:${h(v)}%" title="${esc(label)}: ${esc(money(v))}"><span class="wb-pill">${esc(moneyShort(v))}</span></div>`;
    el.innerHTML = `<div class="ch"><div><h3>${t('dash.weekly', 'Weekly Summary')}</h3><p>${t('dash.weekly_sub', 'Received vs paid over the last 7 days')}</p></div>
            <div class="ch-r"><div class="wk-legend"><span><i class="r"></i>${t('dash.legend_received', 'Received')}</span><span><i class="p"></i>${t('dash.legend_paid', 'Paid')}</span></div></div></div>
        <div class="wk-top"><b>${money(recv)}</b>${deltaBadge}<span class="wk-paid">${t('dash.legend_paid', 'Paid')} <b>${money(paid)}</b></span></div>
        <div class="wk-bars" role="img" aria-label="${esc(series.map((x) => `${days[x.dow]}: ${t('dash.legend_received', 'Received')} ${money(x.received)}, ${t('dash.legend_paid', 'Paid')} ${money(x.paid)}`).join('; '))}">
            ${series.map((x, i) => `<div class="wk-col ${i === series.length - 1 ? 'cur' : ''}"><div class="wk-pair">
                ${bar('r', x.received, t('dash.legend_received', 'Received'))}${bar('p', x.paid, t('dash.legend_paid', 'Paid'))}</div>
                <span class="wk-x">${esc(days[x.dow])}</span></div>`).join('')}
        </div>`;
}

// Up next: the open invoices as a ticket you can flip through, most urgent first
function renderNext() {
    const el = $('#nx'); const d = S.dash; if (!el || !d) return;
    const list = d.alerts || [];
    const i = Math.min(Math.max(S.nx || 0, 0), Math.max(list.length - 1, 0)); S.nx = i;
    const inv = list[i];
    const head = `<div class="ch"><div><h3>${t('nx.title', 'Up next')}</h3><p>${t('nx.sub', 'Open invoices, most urgent first')}</p></div></div>`;
    if (!inv) {
        el.innerHTML = `${head}<div class="nx-stage"><div class="ticket gray"><div class="tk-top"><span class="tk-chip">${ic('checkc')}</span><span class="tk-tag">${t('nx.clear', 'All clear')}</span></div>
            <div class="tk-amt">${money(0)}</div><div class="tk-reason">${t('nx.none', 'No open invoices')}</div><div class="tk-cut"></div>
            <div class="tk-bot"><div><small>${t('nx.status', 'Status')}</small><b>${t('side.clear', 'All paid up')}</b></div></div></div></div>
            <div class="nx-empty">${t('nx.none_sub', 'New and overdue invoices appear here so you can pay or follow up quickly.')}</div>
            ${canCreate() ? `<button class="btn pri block" data-act="create">${ic('plus')}${t('btn.new_invoice', 'New Invoice')}</button>` : ''}`;
        return;
    }
    const sent = inv.direction === 'sent';
    const due = dueIn(inv.dueDate, inv.status);
    const dueTs = toDate(inv.dueDate);
    const soon = inv.status !== 'overdue' && dueTs && dueTs.getTime() - Date.now() < 864e5;
    const tone = sent ? 'blue' : inv.status === 'overdue' ? 'red' : soon ? 'amber' : 'teal';
    const tag = sent ? t('nx.owed', 'Owed to you') : inv.status === 'overdue' ? t('status.overdue', 'Overdue') : soon ? t('nx.due_soon', 'Due soon') : (STATUS_LABEL()[inv.status] || inv.status);
    const owed = num(inv.total) + num(inv.lateFee);
    const paidPct = owed > 0 ? Math.min(100, Math.round((num(inv.amountPaid) / owed) * 100)) : 0;
    const dd = dueTs;
    const canPay = !sent && isOpen(inv) && (S.account === 'personal' || perm('pay'));
    el.innerHTML = `${head}
        <div class="nx-stage"><div class="ticket ${tone}" data-act="view" data-id="${inv.id}">
            <div class="tk-top"><span class="tk-chip">${ic(sent ? 'send' : 'doc')}</span><span class="tk-from">${esc(sent ? inv.recipient : inv.sender)}</span><span class="tk-tag">${esc(tag)}</span></div>
            <div class="tk-amt">${money(inv.remaining)}</div>
            <div class="tk-reason">${esc(inv.reason || '')}</div>
            <div class="tk-cut"></div>
            <div class="tk-bot"><div><small>${sent ? t('nx.billed_to', 'Billed to') : t('nx.billed_by', 'Billed by')}</small><b>${esc(sent ? inv.recipient : (inv.senderType === 'society' && inv.senderName ? inv.senderName : inv.sender))}</b></div>
                <div class="r"><small>${t('nx.due', 'Due')}</small><b>${dd ? dd.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit' }) : '—'}</b></div></div>
        </div></div>
        <div class="nx-ctl">
            <button class="ibtn" data-act="view" data-id="${inv.id}" title="${t('btn.view', 'View')}">${ic('eye')}</button>
            <button class="ibtn" data-act="copyRef" data-ref="${esc(inv.ref)}" title="${t('btn.copy', 'Copy')}">${ic('copy')}</button>
            <button class="ibtn" data-act="nxMove" data-v="-1" ${i === 0 ? 'disabled' : ''}>${ic('chevup')}</button>
            <button class="ibtn" data-act="nxMove" data-v="1" ${i >= list.length - 1 ? 'disabled' : ''}>${ic('chevron')}</button>
            <span class="nx-pos">${i + 1}/${list.length}</span>
            ${canCreate() ? `<button class="ibtn" data-act="create" title="${t('btn.new_invoice', 'New Invoice')}">${ic('plus')}</button>` : ''}
        </div>
        <div class="nx-rows">
            <div><span>${t('nx.type', 'Type')}</span><b>${inv.senderType === 'society' ? t('nx.society_invoice', 'Society invoice') : t('nx.personal_invoice', 'Personal invoice')}</b></div>
            <div><span>${sent ? t('nx.to', 'To') : t('nx.from', 'From')}</span><b class="ell">${esc(sent ? inv.recipient : inv.sender)}</b></div>
            <div><span>${t('nx.status', 'Status')}</span><b class="stt ${esc(inv.status)}">${esc(STATUS_LABEL()[inv.status] || inv.status)}</b></div>
            <div><span>${t('nx.paid', 'Paid')}</span><span class="nx-prog"><i style="width:${paidPct}%"></i></span><b>${moneyShort(inv.amountPaid)} / ${moneyShort(owed)}</b></div>
            <div><span>${t('nx.due', 'Due')}</span><b class="${due.hot ? 'hot' : ''}">${esc(due.text)}</b></div>
        </div>
        <div class="row2"><button class="btn line" data-act="view" data-id="${inv.id}">${t('nx.details', 'View details')}</button>
            ${canPay ? `<button class="btn pri" data-act="pay" data-id="${inv.id}">${t('nx.pay_now', 'Pay now')}</button>` : `<button class="btn line" data-act="print" data-id="${inv.id}" ${S.ctx.settings.print ? '' : 'disabled'}>${t('menu.print', 'Print')}</button>`}</div>
        <div class="nx-ref"><button class="refbox mono" data-act="copyRef" data-ref="${esc(inv.ref)}">${esc(inv.ref)}</button><button class="ibtn lg" data-act="copyRef" data-ref="${esc(inv.ref)}" title="${t('btn.copy', 'Copy')}">${ic('copy')}</button></div>`;
}

// ═══════════════ RECEIVED / SENT ═══════════════
function tableState(box) {
    const key = `${S.account}:${box}`;
    if (!S.tables[key]) S.tables[key] = { box, page: 1, search: '', statuses: [], due: 'all', rows: [], total: 0, counts: {}, selected: new Map(), loaded: false };
    return S.tables[key];
}
const payableRow = (inv) => inv.direction === 'received' && isOpen(inv) && (S.account === 'personal' || perm('pay'));

async function loadTable(tb) {
    const data = await call('invoices:list', { account: S.account, box: tb.box, page: tb.page, search: tb.search, statuses: tb.statuses, due: tb.due });
    if (!data) return;
    Object.assign(tb, { rows: data.rows, total: data.total, counts: data.counts, pageSize: data.pageSize, loaded: true, stale: false });
    if (S.page === tb.box) renderTableBody(tb);
}

function pageTable(box) {
    const tb = tableState(box);
    const received = box === 'received';
    const active = tb.statuses.length + (tb.due !== 'all' ? 1 : 0);
    setPage(`<div class="card tcard">
        <div class="tbar">
            <label class="search">${ic('search')}<input data-input="tSearch" placeholder="${t('label.search', 'Search...')}" value="${esc(tb.search)}"></label>
            ${received ? `<div class="selbox" id="selbox"></div>` : ''}
            <div class="r">${active ? `<button class="link" data-act="fReset">${t('filter.reset_filters', 'Reset filters')}</button>` : ''}
                <div style="position:relative"><button class="fbtn ${active ? 'on' : ''}" data-act="fOpen">${ic('filter')}${t('filter.filters', 'Filters')}${ic('chevron')}${active ? `<span class="n">${active}</span>` : ''}</button></div>
</div>
        </div>
        <div class="tscroll" id="tbody">${skel(7, 44)}</div>
        <div class="tfoot" id="tfoot"></div></div>`);
    renderSelBox(tb);
    if (!tb.loaded || tb.stale) loadTable(tb); else renderTableBody(tb);
}

function renderSelBox(tb) {
    const el = $('#selbox'); if (!el) return;
    const total = [...tb.selected.values()].reduce((s, i) => s + i.remaining, 0);
    el.innerHTML = `<span><b>${tb.selected.size}</b> ${t('table.selected', 'selected')}</span><span><b>${money(total)}</b></span>
        <button data-act="paySelected" ${tb.selected.size ? '' : 'disabled'}>${ic('card')}${t('btn.pay_selected', 'Pay Selected')}</button>`;
}

function renderTableBody(tb) {
    const body = $('#tbody'), foot = $('#tfoot'); if (!body) return;
    const received = tb.box === 'received';
    if (!tb.rows.length) {
        body.innerHTML = emptyState(received ? 'inbox' : 'file', received ? t('table.empty_received', 'No invoices received') : t('table.empty_sent', 'No invoices sent'),
            tb.search || tb.statuses.length ? t('table.empty_filtered', 'Nothing matches these filters.') : t('table.empty_sub', 'Invoices will show up here as soon as they arrive.'));
    } else {
        const payable = tb.rows.filter(payableRow);
        const allOn = payable.length && payable.every((r) => tb.selected.has(r.id));
        body.innerHTML = `<table class="t"><thead><tr>
            ${received ? `<th class="cbx-col"><span class="cbx ${allOn ? 'on' : ''} ${payable.length ? '' : 'dis'}" data-act="selAll">${ic('check')}</span></th>` : ''}
            <th>${received ? t('table.sender', 'Sender') : t('table.recipient', 'Recipient')}</th><th>${t('table.reason', 'Reason')}</th><th class="r">${t('table.amount', 'Amount')}</th>
            <th>${t('table.due', 'Due Date')}</th><th>${t('table.status', 'Status')}</th><th>${received ? t('table.received', 'Received') : t('table.created', 'Created')}</th></tr></thead><tbody>
            ${tb.rows.map((r) => {
                const can = payableRow(r);
                const who = received ? r.sender : r.recipient;
                return `<tr data-act="row" data-id="${r.id}" class="${tb.selected.has(r.id) ? 'sel' : ''} ${['cancelled', 'refunded'].includes(r.status) ? 'dim' : ''}">
                    ${received ? `<td class="cbx-col"><span class="cbx ${tb.selected.has(r.id) ? 'on' : ''} ${can ? '' : 'dis'}" data-act="sel" data-id="${r.id}">${ic('check')}</span></td>` : ''}
                    <td class="b ell">${esc(who)}${r.senderType === 'society' && received && r.senderName ? `<span class="sub">${esc(r.senderName)}</span>` : ''}</td>
                    <td class="ell">${esc(r.reason || '')}<span class="sub mono">${esc(r.ref)}</span></td>
                    <td class="amt">${money(isOpen(r) || r.status === 'disputed' ? r.remaining : r.total + r.lateFee)}${r.lateFee > 0 ? `<span class="sub" style="color:var(--danger)">+${money(r.lateFee)} ${t('label.late_fee_short', 'late')}</span>` : ''}</td>
                    <td><b>${esc(fmtDate(r.dueDate))}</b><span class="sub">${esc(fmtTime(r.dueDate))}</span></td>
                    <td>${st(r.status)}</td><td>${esc(ago(r.createdAt))}</td></tr>`;
            }).join('')}</tbody></table>`;
    }
    const size = tb.pageSize || 8;
    const pagesN = Math.max(1, Math.ceil(tb.total / size));
    const from = tb.total ? (tb.page - 1) * size + 1 : 0, to = Math.min(tb.total, tb.page * size);
    foot.innerHTML = `<span>${t('table.showing', 'Showing {from}–{to} of {total}', { from, to, total: tb.total })}</span><div class="pager">${pager(tb.page, pagesN, 'tPage')}</div>`;
    renderSelBox(tb);
}

function pager(page, pagesN, act) {
    const btn = (p, label = p) => `<button class="${p === page ? 'on' : ''}" data-act="${act}" data-p="${p}">${label}</button>`;
    let out = `<button data-act="${act}" data-p="${page - 1}" ${page <= 1 ? 'disabled' : ''}>${t('table.prev', 'Prev')}</button>`;
    const set = new Set([1, pagesN, page - 1, page, page + 1].filter((p) => p >= 1 && p <= pagesN));
    let last = 0;
    [...set].sort((a, b) => a - b).forEach((p) => { if (p - last > 1) out += '<span class="gap">…</span>'; out += btn(p); last = p; });
    return out + `<button data-act="${act}" data-p="${page + 1}" ${page >= pagesN ? 'disabled' : ''}>${t('table.next', 'Next')}</button>`;
}

function filterPop(owner, tb, onApply) {
    const draft = { statuses: [...tb.statuses], due: tb.due };
    const statuses = [['overdue'], ['pending'], ['partial'], ['disputed'], ['paid'], ['cancelled']];
    const render = () => `<h5>${t('table.status', 'Status')}</h5>
        ${statuses.map(([s]) => `<button class="fopt" data-act="fStatus" data-s="${s}"><span class="cbx ${draft.statuses.includes(s) ? 'on' : ''}">${ic('check')}</span><span class="dot ${s}"></span>${esc(STATUS_LABEL()[s])}<span class="n">${tb.counts?.[s] ?? ''}</span></button>`).join('')}
        <div class="fsep"></div><h5>${t('table.due', 'Due Date')}</h5>
        <div class="seg">${[['all', t('filter.all', 'All')], ['today', t('filter.today', 'Today')], ['3d', t('filter.3d', '3 Days')], ['7d', t('filter.7d', '7 Days')]].map(([v, l]) => `<button class="${draft.due === v ? 'on' : ''}" data-act="fDue" data-v="${v}">${l}</button>`).join('')}</div>
        <div class="fact"><button class="btn line" data-act="fClear">${t('filter.reset', 'Reset')}</button><button class="btn soft" data-act="fApply">${t('filter.apply', 'Apply')}</button></div>`;
    const el = showPop(owner, render(), 'filters');
    el.draft = draft; el.rerender = () => { el.innerHTML = render(); }; el.apply = () => { closePop(); onApply(draft); };
}

// ═══════════════ DETAIL RAIL ═══════════════
function paperHtml(inv, opts = {}) {
    const items = (inv.items || []).map((i) => `<div class="ln"><span>${esc(i.label)}${num(i.quantity, 1) > 1 ? ` <span class="qty">×${esc(i.quantity)}</span>` : ''}</span><b>${money(num(i.amount) * num(i.quantity, 1))}</b></div>`).join('');
    const remainingRow = isOpen(inv) || inv.status === 'disputed';
    const foot = inv.status === 'paid' ? t('paper.paid_on', 'Paid on {date}', { date: fmtLong(inv.paidAt) })
        : inv.status === 'cancelled' ? t('paper.cancelled', 'This invoice was cancelled')
            : inv.status === 'refunded' ? t('paper.refunded', 'This invoice was refunded')
                : inv.status === 'overdue' ? t('paper.overdue', 'Payment was due on {date}', { date: fmtLong(inv.dueDate) })
                    : t('paper.pending_until', 'Payment pending until {date}', { date: fmtLong(inv.dueDate) });
    return `<div class="paper"><span class="stamp ${esc(inv.status)}">${esc(STATUS_LABEL()[inv.status] || inv.status)}</span>
        <h2>${t('paper.invoice', 'Invoice')} #${esc(inv.id)}</h2>
        <div class="ref">${t('paper.ref', 'REF. ID')}: <span class="mono">${esc(inv.ref)}</span><button data-act="copyRef" data-ref="${esc(inv.ref)}" title="${t('btn.copy', 'Copy')}">${ic('copy')}</button></div>
        <div class="meta"><span>${t('paper.received', 'Received')}:</span><b>${esc(fmtLong(inv.createdAt))}</b>
            <span>${t('paper.due', 'Due')}:</span><b>${esc(fmtLong(inv.dueDate))}</b>
            <span>${t('paper.to', 'To')}:</span><b>${esc(inv.recipient)}</b>
            <span>${t('paper.from', 'From')}:</span><b>${esc(inv.sender)}${inv.senderType === 'society' && inv.senderName && !opts.short ? ` · ${esc(inv.senderName)}` : ''}</b></div>
        <div class="ln h"><span>${t('paper.description', 'Description')}</span><span>${t('paper.amount', 'Amount')}</span></div>${items}
        <div class="sep"></div>
        <div class="ln"><span>${t('paper.subtotal', 'Subtotal')}</span><b>${money(inv.subtotal)}</b></div>
        <div class="ln"><span>${t('paper.vat', 'VAT ({rate})', { rate: pct(inv.vatRate) })}</span><b>${money(inv.vat)}</b></div>
        ${inv.lateFee > 0 ? `<div class="ln"><span>${t('paper.late_fee', 'Late fee')}</span><b>${money(inv.lateFee)}</b></div>` : ''}
        ${inv.amountPaid > 0 && remainingRow ? `<div class="ln"><span>${t('paper.paid', 'Paid')}</span><b>−${money(inv.amountPaid)}</b></div>` : ''}
        ${inv.tip > 0 ? `<div class="ln"><span>${t('paper.tip', 'Tip')}</span><b>${money(inv.tip)}</b></div>` : ''}
        <div class="sep"></div>
        <div class="ln total"><span>${remainingRow ? t('paper.remaining', 'REMAINING') : t('paper.total', 'TOTAL')}</span><span>${money(remainingRow ? inv.remaining : inv.total + inv.lateFee)}</span></div>
        <div class="foot">${esc(foot)}</div></div>`;
}

async function openRail(id, silent) {
    const inv = await call('invoices:get', { id, account: S.account });
    if (!inv) return;
    S.rail = inv;
    const notes = [
        inv.notes ? `<div class="note"><b>${t('detail.notes', 'Notes')}</b>${esc(inv.notes)}</div>` : '',
        inv.disputeReason ? `<div class="note violet"><b>${t('detail.dispute', 'Dispute')}</b>${esc(inv.disputeReason)}</div>` : '',
        inv.cancelReason ? `<div class="note red"><b>${inv.status === 'refunded' ? t('detail.refund_reason', 'Refund reason') : t('detail.cancel_reason', 'Cancellation reason')}</b>${esc(inv.cancelReason)}</div>` : '',
    ].join('');
    const pays = (inv.payments || []).length ? `<div class="field"><span class="lbl">${t('detail.payments', 'Payments')}</span>${inv.payments.map((p) => `<div class="tl ${p.kind === 'refund' ? 'refund' : ''}">
        <div><b>${money(Math.abs(p.amount))}</b> ${p.kind === 'refund' ? t('detail.refunded', 'refunded') : p.kind === 'autocollect' ? t('detail.collected', 'auto-collected') : t('detail.paid_by', 'paid by')} ${esc(p.payer || '')} · ${esc(p.method)}${num(p.tip) > 0 ? ` · ${money(p.tip)} ${t('label.tip', 'tip')}` : ''}</div><span>${esc(fmtDate(p.createdAt))}</span></div>`).join('')}</div>` : '';
    const acts = [];
    if (inv.payOptions) acts.push(`<button class="btn pri" data-act="pay" data-id="${inv.id}">${ic('card')}${t('btn.pay_amount', 'Pay {amount}', { amount: money(inv.remaining) })}</button>`);
    if (inv.canResolve) {
        acts.push(`<button class="btn line" data-act="resolve" data-id="${inv.id}" data-a="reject">${t('btn.reject_dispute', 'Reject dispute')}</button>`);
        acts.push(`<button class="btn soft" data-act="resolve" data-id="${inv.id}" data-a="accept">${t('btn.accept_dispute', 'Accept dispute')}</button>`);
    }
    if (inv.canDispute) acts.push(`<button class="btn line" data-act="dispute" data-id="${inv.id}">${ic('flag')}${t('btn.dispute', 'Dispute')}</button>`);
    if (inv.canPrint) acts.push(`<button class="btn line" data-act="print" data-id="${inv.id}">${ic('printer')}${t('btn.print', 'Print')}</button>`);
    if (inv.canRefund) acts.push(`<button class="btn red" data-act="refund" data-id="${inv.id}">${ic('undo')}${t('btn.refund', 'Refund')}</button>`);
    if (inv.canCancel) acts.push(`<button class="btn red" data-act="cancel" data-id="${inv.id}">${ic('ban')}${t('btn.cancel_invoice', 'Cancel invoice')}</button>`);
    if (inv.canDelete) acts.push(`<button class="btn red" data-act="adminDelete" data-id="${inv.id}">${ic('trash')}${t('btn.delete', 'Delete')}</button>`);
    $('#rail').innerHTML = `${silent ? '' : '<div class="rail-shade" data-act="railClose"></div>'}<div class="rail" ${silent ? 'style="animation:none"' : ''}>
        <div class="rail-h"><div class="tile sm teal">${ic('doc')}</div><div><h4>${esc(inv.reason || t('paper.invoice', 'Invoice'))}</h4></div><button class="ibtn" style="margin-left:auto" data-act="railClose">${ic('x')}</button></div>
        <div class="rail-b">${paperHtml(inv)}
            <div class="kv" style="margin-top:6px"><div><span>${t('detail.issued_by', 'Issued by')}</span><b>${esc(inv.senderName)}</b></div><div><span>${t('detail.method', 'Paid with')}</span><b>${esc(inv.method ? (inv.method === 'society' ? t('label.society_account', 'Society account') : inv.method) : '—')}</b></div>
            ${inv.paidBy ? `<div><span>${t('detail.paid_by_label', 'Paid by')}</span><b>${esc(inv.paidBy)}</b></div>` : ''}<div><span>${t('detail.due_status', 'Due')}</span><b>${esc(dueIn(inv.dueDate, inv.status).text || '—')}</b></div></div>
            ${notes}${pays}</div>
        ${acts.length ? `<div class="rail-f">${acts.join('')}</div>` : ''}</div>`;
    if (silent) $('.rail-shade') || $('#rail').insertAdjacentHTML('afterbegin', '<div class="rail-shade" data-act="railClose" style="animation:none"></div>');
}
function closeRail() { S.rail = null; const r = $('#rail'); if (r) r.innerHTML = ''; }

// ═══════════════ PAY ═══════════════
async function payInvoice(id, preset) {
    const inv = preset || (S.rail && S.rail.id === id ? S.rail : await call('invoices:get', { id, account: S.account }));
    if (!inv || !inv.payOptions) { if (inv) toast(t('label.error', 'Error'), t('error.cannot_pay', 'You cannot pay this invoice'), 'error'); return; }
    const st_ = S.ctx.settings;
    const methods = ['society', 'bank', 'cash'].filter((m) => inv.payOptions[m]);
    const state = { method: S.account === 'society' && methods.includes('society') ? 'society' : (methods.find((m) => m !== 'society') || methods[0]), full: true, amount: inv.remaining, tip: 0 };
    const tipsOk = st_.tips && inv.tipsAllowed;
    const partialOk = st_.allowPartial && inv.remaining > st_.minPartial;
    const balanceOf = (m) => m === 'cash' ? S.ctx.player.cash : m === 'bank' ? S.ctx.player.bank : S.ctx.society?.balance;
    const m = openModal(`<div class="modal w600">${mh(t('pay.title', 'Pay invoice'), `${esc(inv.ref)} · ${esc(inv.sender)}`, 'card')}<div class="mb" id="payB"></div>
        <div class="mf"><span class="l" id="payWarn" style="color:var(--danger)"></span><button class="btn line" data-act="mClose">${t('btn.cancel', 'Cancel')}</button><button class="btn pri" data-act="mOk" id="payGo">${ic('check')}${t('btn.confirm_payment', 'Confirm payment')}</button></div></div>`);
    const render = () => {
        const amount = state.full ? inv.remaining : r2(Math.min(inv.remaining, Math.max(0, num(state.amount))));
        const tip = tipsOk ? r2(inv.total * state.tip / 100) : 0;
        const charge = r2(amount + tip);
        const bal = balanceOf(state.method);
        $('#payB', m.el).innerHTML = `
            <div class="kv"><div><span>${t('pay.total', 'Invoice total')}</span><b>${money(inv.total + inv.lateFee)}</b></div><div><span>${t('pay.remaining', 'Remaining')}</span><b>${money(inv.remaining)}</b></div></div>
            <div class="field"><span class="lbl">${t('pay.method', 'Pay with')}</span><div class="seg big">${methods.map((k) => `<button class="${state.method === k ? 'on' : ''}" data-act="pMethod" data-m="${k}">
                ${ic(k === 'cash' ? 'cash' : k === 'bank' ? 'card' : 'building')}${k === 'cash' ? t('label.cash_cap', 'Cash') : k === 'bank' ? t('label.bank_cap', 'Bank') : t('label.society_account', 'Society account')}
                <small>${balanceOf(k) === null || balanceOf(k) === undefined ? '' : money(balanceOf(k))}</small></button>`).join('')}</div></div>
            ${partialOk ? `<div class="field"><span class="lbl">${t('pay.amount', 'Amount')}</span><div class="seg"><button class="${state.full ? 'on' : ''}" data-act="pFull" data-v="1">${t('pay.full', 'Full amount')}</button><button class="${!state.full ? 'on' : ''}" data-act="pFull" data-v="0">${t('pay.installment', 'Installment')}</button></div>
                ${!state.full ? `<input class="input" type="number" min="${st_.minPartial}" max="${inv.remaining}" step="0.01" data-input="pAmount" value="${esc(state.amount)}" style="margin-top:8px"><span class="hint">${t('pay.min', 'Minimum {amount}', { amount: money(Math.min(st_.minPartial, inv.remaining)) })}</span>` : ''}</div>` : ''}
            ${tipsOk ? `<div class="field"><span class="lbl">${t('pay.tip', 'Add a tip')}</span><div class="tips">${st_.tips.map((x) => `<button class="${state.tip === x ? 'on' : ''}" data-act="pTip" data-v="${x}">${x ? x + '%' : t('pay.no_tip', 'No tip')}</button>`).join('')}</div></div>` : ''}
            <div class="payline"><div><span>${t('pay.you_pay', 'You pay')}</span>${tip > 0 ? `<span style="display:block">${t('pay.incl_tip', 'incl. {amount} tip', { amount: money(tip) })}</span>` : ''}</div><b>${money(charge)}</b></div>`;
        const short = bal !== null && bal !== undefined && bal < charge;
        $('#payWarn', m.el).textContent = short ? t('pay.insufficient', 'Insufficient balance') : '';
        $('#payGo', m.el).disabled = short || amount <= 0;
        state.computed = { amount, tip };
    };
    m.pay = state; m.render = render; render();
    m.ok = async () => {
        $('#payGo', m.el).disabled = true;
        const res = await call('invoices:pay', { id: inv.id, ref: inv.ref, method: state.method, amount: state.full ? null : state.computed.amount, tip: state.computed.tip });
        if (!res) { $('#payGo', m.el).disabled = false; return; }
        m.close();
        toast(res.status === 'paid' ? t('toast.paid', 'Invoice paid') : t('toast.installment', 'Installment paid'),
            t('toast.paid_body', '{amount} paid · {ref}', { amount: money(res.charged), ref: inv.ref }), 'success');
        closeModals();
        if (S.mode === 'paper') { hidePaper(); return; }
        refreshCtx();
    };
}

async function payMany(ids, total) {
    const methods = S.account === 'society' ? ['society'] : Object.entries(S.ctx.settings.methods || {}).filter(([, v]) => v).map(([k]) => k);
    const state = { method: methods[0] };
    const m = openModal(`<div class="modal">${mh(t('pay.many_title', 'Pay {n} invoices', { n: ids.length }), '', 'card')}<div class="mb" id="pmB"></div>
        <div class="mf"><button class="btn line" data-act="mClose">${t('btn.cancel', 'Cancel')}</button><button class="btn pri" data-act="mOk">${ic('check')}${t('btn.pay_amount', 'Pay {amount}', { amount: money(total) })}</button></div></div>`);
    const render = () => {
        $('#pmB', m.el).innerHTML = `<p class="copy">${t('pay.many_text', 'Each selected invoice is paid in full. Payment stops if your balance runs out.')}</p>
            ${methods.length > 1 ? `<div class="seg big">${methods.map((k) => `<button class="${state.method === k ? 'on' : ''}" data-act="pmMethod" data-m="${k}">${ic(k === 'cash' ? 'cash' : 'card')}${k === 'cash' ? t('label.cash_cap', 'Cash') : t('label.bank_cap', 'Bank')}<small>${money(k === 'cash' ? S.ctx.player.cash : S.ctx.player.bank)}</small></button>`).join('')}</div>` : ''}
            <div class="payline"><span>${t('pay.total_selected', 'Total')}</span><b>${money(total)}</b></div>`;
    };
    m.pm = state; m.render = render; render();
    m.ok = async () => {
        const res = await call('invoices:payMany', { ids, method: state.method });
        if (!res) return;
        m.close();
        toast(t('toast.bulk', 'Bulk payment'), t('toast.bulk_body', '{n} paid · {amount}{failed}', { n: res.paid, amount: money(res.total), failed: res.failed.length ? ' · ' + t('toast.bulk_failed', '{n} failed', { n: res.failed.length }) : '' }), res.failed.length ? 'warning' : 'success');
        Object.values(S.tables).forEach((tb) => tb.selected.clear());
        refreshCtx();
    };
}

// ═══════════════ PAY BY REFERENCE ═══════════════
function payByReference(prefill = '') {
    const m = openModal(`<div class="modal w600">${mh(t('ref.title', 'Pay Reference'), t('ref.sub', 'Look up an invoice by its reference before paying'), 'hash')}
        <div class="mb"><div style="display:flex;gap:8px"><input class="input mono" id="refIn" maxlength="24" placeholder="LSPD-7KQ2MZ4P" value="${esc(prefill)}" autofocus style="text-transform:uppercase">
            <button class="ibtn" style="width:36px;height:36px" data-act="refLookup">${ic('search')}</button></div><div id="refOut"></div></div>
        <div class="mf"><button class="btn line" data-act="mClose">${t('btn.cancel', 'Cancel')}</button><button class="btn pri" data-act="mOk" id="refPay" disabled>${t('btn.pay_invoice', 'Pay Invoice')}</button></div></div>`);
    m.lookup = async () => {
        const ref = $('#refIn', m.el).value.trim();
        if (!ref) return;
        const inv = await call('invoices:lookup', { ref });
        const out = $('#refOut', m.el);
        if (!inv) { out.innerHTML = ''; m.inv = null; $('#refPay', m.el).disabled = true; return; }
        m.inv = inv;
        out.innerHTML = `<div class="card pad" style="background:var(--inset);display:flex;flex-direction:column;gap:12px">
            <div class="row3"><div><span class="hint">${t('ref.issued_by', 'Issued by')}</span><div style="font-weight:600;color:var(--white);margin-top:3px">${esc(inv.sender)}</div></div>
                <div><span class="hint">${t('ref.expires', 'Expires')}</span><div style="font-weight:600;color:var(--white);margin-top:3px">${esc(fmtDate(inv.dueDate))}</div></div>
                <div style="text-align:right"><span class="hint">${t('table.status', 'Status')}</span><div style="margin-top:3px">${st(inv.status)}</div></div></div>
            <div><span class="hint">${t('ref.billed_to', 'Billed to')} · <b style="color:var(--ink)">${esc(inv.recipient)}</b></span></div>
            <div class="totals">${inv.items.map((i) => `<div><span>${esc(i.label)}${num(i.quantity, 1) > 1 ? ' ×' + esc(i.quantity) : ''}</span><b>${money(num(i.amount) * num(i.quantity, 1))}</b></div>`).join('')}
                <div style="border-top:1px solid var(--line-soft);padding-top:6px"><span>${t('paper.subtotal', 'Subtotal')}</span><b>${money(inv.subtotal)}</b></div>
                <div><span>${t('paper.vat', 'VAT ({rate})', { rate: pct(inv.vatRate) })}</span><b>${money(inv.vat)}</b></div>
                ${inv.lateFee > 0 ? `<div><span>${t('paper.late_fee', 'Late fee')}</span><b>${money(inv.lateFee)}</b></div>` : ''}
                <div class="grand"><span>${isOpen(inv) ? t('paper.remaining_cap', 'Remaining') : t('paper.total_cap', 'Total')}</span><b>${money(isOpen(inv) ? inv.remaining : inv.total + inv.lateFee)}</b></div></div></div>`;
        $('#refPay', m.el).disabled = !inv.payOptions;
    };
    m.ok = () => { if (m.inv && m.inv.payOptions) payInvoice(m.inv.id, m.inv); };
    if (prefill) m.lookup();
}

// ═══════════════ CREATE INVOICE ═══════════════
async function createInvoice(recipientId) {
    if (!canCreate()) return;
    const soc = S.account === 'society';
    const [tpl, nearby] = await Promise.all([call('templates:list', { account: S.account }), call('getNearby')]);
    if (!tpl) return;
    const templates = (tpl.templates || []).filter((x) => x.items.length);
    const vat = soc ? S.ctx.society.vatRate : S.ctx.settings.personalVat;
    const allowCustom = soc ? S.ctx.society.allowCustom : S.ctx.settings.personalCustom;
    const societies = (S.ctx.societies || []).filter((s) => s.billable && (!soc || s.id !== S.ctx.society.id));
    const state = { type: 'citizen', recipient: recipientId ? String(recipientId) : '', template: templates[0] ? String(templates[0].id) : '', item: '', items: [], custom: false, due: '', notes: '', nearby: nearby || [] };
    const m = openModal(`<div class="modal w680">${mh(t('create.title', 'Create Invoice'), soc ? t('create.as_society', 'Billing as {name}', { name: esc(S.ctx.society.label) }) : t('create.as_personal', 'Personal invoice'), 'send')}
        <div class="mb" id="ciB"></div><div class="mf"><button class="btn line" data-act="mClose">${t('btn.cancel', 'Cancel')}</button><button class="btn pri" data-act="mOk" id="ciGo">${t('btn.create_invoice', 'Create Invoice')}</button></div></div>`);
    const tplById = (id) => templates.find((x) => String(x.id) === String(id));
    const render = () => {
        const tp = tplById(state.template);
        const recOpts = state.type === 'citizen'
            ? state.nearby.map((p) => ({ value: p.id, label: p.name, sub: t('create.nearby_sub', 'ID {id} · {d}m', { id: p.id, d: p.distance }) }))
            : societies.map((s) => ({ value: s.id, label: s.label, sub: s.short }));
        const totals = state.items.reduce((s, i) => s + i.amount * i.quantity, 0);
        const vatAmt = r2(totals * vat);
        const canSociety = soc || S.ctx.settings.personalSocietyRecipients;
        $('#ciB', m.el).innerHTML = `
            <div class="row2">
                <div class="field"><span class="lbl">${t('create.recipient_type', 'Recipient Type')}</span><div class="seg">
                    <button class="${state.type === 'citizen' ? 'on' : ''}" data-act="ciType" data-v="citizen">${ic('user')}${t('create.citizen', 'Citizen')}</button>
                    <button class="${state.type === 'society' ? 'on' : ''}" data-act="ciType" data-v="society" ${canSociety ? '' : 'disabled'}>${ic('building')}${t('create.society', 'Society')}</button></div></div>
                <div class="field"><span class="lbl" style="display:flex;justify-content:space-between">${t('create.recipient', 'Recipient')}${state.type === 'citizen' ? `<button class="link" data-act="ciNearby" style="text-transform:none;letter-spacing:0">${t('btn.refresh', 'Refresh')}</button>` : ''}</span>
                    ${dd('ciRecipient', { value: state.recipient, options: recOpts, placeholder: state.type === 'citizen' ? t('create.pick_citizen', 'Select a citizen') : t('create.pick_society', 'Select a society'), search: true,
                        empty: state.type === 'citizen' ? t('create.nobody', 'Nobody nearby') : t('label.no_results', 'No results'), onChange: (v) => { state.recipient = v; render(); } })}</div>
            </div>
            <div class="field"><span class="lbl">${t('create.items', 'Invoice Items')}</span>
                <div style="display:grid;grid-template-columns:1.2fr 1.2fr auto;gap:8px">
                    ${dd('ciTpl', { value: state.template, options: templates.map((x) => ({ value: x.id, label: x.name, icon: x.icon, color: x.color })), placeholder: t('create.pick_template', 'Template'), onChange: (v) => { state.template = v; state.item = ''; render(); } })}
                    ${dd('ciItem', { value: state.item, options: (tp ? tp.items : []).map((i) => ({ value: i.id, label: i.label, sub: money(i.amount) })), placeholder: t('create.pick_item', 'Select an item'), search: true, onChange: (v) => { state.item = v; render(); } })}
                    <button class="btn soft" data-act="ciAdd" ${state.item ? '' : 'disabled'}>${ic('plus')}${t('btn.add_item', 'Add Item')}</button></div></div>
            <div class="card" style="background:var(--inset)">
                <table class="t"><thead><tr><th>${t('create.name', 'Name')}</th><th style="width:90px">${t('create.qty', 'Qty')}</th><th class="r">${t('create.value', 'Value')}</th><th class="r" style="width:60px">${t('create.actions', 'Actions')}</th></tr></thead>
                <tbody>${state.items.length ? state.items.map((i, idx) => `<tr style="cursor:default"><td class="b">${esc(i.label)}${i.custom ? ` <span class="badge mute" style="height:18px">${t('create.custom', 'custom')}</span>` : ''}</td>
                    <td><div class="stepper" style="width:max-content"><button data-act="ciQty" data-i="${idx}" data-d="-1">${ic('minus')}</button><span>${i.quantity}</span><button data-act="ciQty" data-i="${idx}" data-d="1">${ic('plus')}</button></div></td>
                    <td class="amt">${money(i.amount * i.quantity)}</td><td class="r"><button class="ibtn sm danger" data-act="ciDel" data-i="${idx}">${ic('trash')}</button></td></tr>`).join('')
                    : `<tr style="cursor:default"><td colspan="4" style="height:auto">${emptyState('doc', t('create.no_items', 'No items in this invoice'), t('create.no_items_sub', 'Select an item above or add a custom item to get started'))}</td></tr>`}</tbody></table>
                ${state.custom ? `<div style="display:grid;grid-template-columns:1fr 130px auto auto;gap:8px;padding:10px 12px;border-top:1px solid var(--line-hair)">
                    <input class="input" id="ciCName" maxlength="60" placeholder="${t('create.custom_name', 'Reason')}" autofocus><input class="input" id="ciCAmt" type="number" min="0" step="0.01" placeholder="${t('create.custom_amount', 'Amount')}">
                    <button class="btn pri" data-act="ciCustomAdd">${t('btn.add', 'Add')}</button><button class="ibtn" style="height:36px;width:36px" data-act="ciCustomToggle">${ic('x')}</button></div>` : ''}
                <div style="display:flex;align-items:center;gap:10px;padding:10px 12px;border-top:1px solid var(--line-hair)">
                    ${allowCustom && !state.custom ? `<button class="btn soft" data-act="ciCustomToggle">${ic('plus')}${t('btn.add_custom', 'Add Custom Item')}</button>` : ''}
                    <span style="margin-left:auto;color:var(--ink-2)">${t('create.subtotal_vat', 'Subtotal + VAT ({rate})', { rate: pct(vat) })}</span><b style="color:var(--white);font-size:15px">${money(totals + vatAmt)}</b></div>
            </div>
            <div class="row2">
                ${S.ctx.settings.customDue ? `<div class="field"><span class="lbl">${t('create.due', 'Due in')}</span>${dd('ciDue', { value: state.due, options: [{ value: '', label: t('create.due_default', 'Default ({n} days)', { n: soc ? S.ctx.society.dueDays : S.ctx.settings.dueDays }) }]
                    .concat(Array.from({ length: S.ctx.settings.maxDueDays }, (_, k) => ({ value: k + 1, label: t('create.days', '{n} day(s)', { n: k + 1 }) }))), onChange: (v) => { state.due = v; render(); } })}</div>` : '<div></div>'}
                <div class="field"><span class="lbl">${t('create.notes', 'Notes')}</span><input class="input" data-input="ciNotes" maxlength="${S.ctx.settings.maxNote}" placeholder="${t('create.notes_ph', 'Add an optional note to this invoice...')}" value="${esc(state.notes)}"></div>
            </div>`;
        $('#ciGo', m.el).disabled = !state.recipient || !state.items.length;
    };
    m.ci = state; m.render = render;
    m.addTemplateItem = () => {
        const tp = tplById(state.template); const it = tp && tp.items.find((i) => i.id === state.item);
        if (!it) return;
        const ex = state.items.find((i) => i.template === tp.id && i.item === it.id);
        if (ex) ex.quantity = Math.min(S.ctx.settings.maxQuantity, ex.quantity + 1);
        else state.items.push({ template: tp.id, item: it.id, label: it.label, amount: num(it.amount), quantity: 1 });
        state.item = ''; render();
    };
    m.addCustom = () => {
        const name = $('#ciCName', m.el).value.trim(); const amount = r2($('#ciCAmt', m.el).value);
        if (!name || amount <= 0) { toast(t('label.error', 'Error'), t('error.custom_item', 'Enter a reason and an amount'), 'warning'); return; }
        state.items.push({ label: name, amount, quantity: 1, custom: true }); state.custom = false; render();
    };
    m.ok = async () => {
        $('#ciGo', m.el).disabled = true;
        const res = await call('invoices:create', {
            account: S.account, recipient: { type: state.type, id: state.recipient }, notes: state.notes, dueDays: state.due ? num(state.due) : null,
            items: state.items.map((i) => (i.custom ? { label: i.label, amount: i.amount, quantity: i.quantity } : { template: i.template, item: i.item, quantity: i.quantity })),
        });
        if (!res) { $('#ciGo', m.el).disabled = false; return; }
        m.close();
        toast(t('toast.created', 'Invoice sent'), t('toast.created_body', '{ref} · {amount} to {name}', { ref: res.ref, amount: money(res.total), name: res.recipient }), 'success');
        refreshCtx();
    };
    render();
}

// ═══════════════ TEMPLATES ═══════════════
async function pageTemplates(reload) {
    if (!S.tpl || S.tpl.account !== S.account || reload) {
        setPage(`<div class="card pad">${skel(6, 44)}</div>`);
        const d = await call('templates:list', { account: S.account });
        if (!d || S.page !== 'templates') return;
        const prev = S.tpl && S.tpl.account === S.account ? S.tpl.active : null;
        S.tpl = Object.assign(d, { account: S.account, active: prev, search: '', editing: null });
    }
    const T = S.tpl;
    if (!T.templates.find((x) => String(x.id) === String(T.active))) T.active = T.templates[0] ? T.templates[0].id : null;
    const cur = T.templates.find((x) => String(x.id) === String(T.active));
    const editable = cur && !cur.global && T.canEdit;
    const q = T.search.toLowerCase();
    const items = cur ? cur.items.filter((i) => !q || i.label.toLowerCase().includes(q)) : [];
    setPage(`<div class="card tcard">
        <div class="tabs"><div class="tabs-scroll">${T.templates.map((x) => `<button class="tab ${String(x.id) === String(T.active) ? 'on' : ''}" data-act="tplTab" data-id="${esc(x.id)}">${ticon(x.icon, x.color)}${esc(x.name)}</button>`).join('')}</div>
            ${T.canCreate ? `<button class="newtab" data-act="tplNew">${ic('plus')}${t('tpl.new', 'New Template')}</button>` : ''}</div>
        ${cur ? `<div class="thead"><h3>${esc(cur.name)}</h3><span class="badge mute">${t('tpl.total_items', '{n} Total Items', { n: cur.items.length })}</span>
            ${cur.global ? `<span class="badge acc">${t('tpl.global', 'Global')}</span>` : ''}${editable ? `<button class="ibtn sm" data-act="tplEdit" title="${t('tpl.settings', 'Template settings')}">${ic('gear')}</button>` : ''}
            <div class="r"><label class="search">${ic('search')}<input data-input="tplSearch" placeholder="${t('label.search', 'Search...')}" value="${esc(T.search)}"></label></div></div>
            <div class="tsub">${cur.global ? t('tpl.global_sub', 'Read-only template available to everyone') : editable ? t('tpl.manage_sub', 'Manage items in this template · drag to reorder') : t('tpl.view_sub', 'Items in this template')}</div>
            <div class="items" id="tplItems">${items.length ? items.map((i) => itemRow(i, editable)).join('') : ''}${T.editing === 'new' ? itemEditRow({ id: '', label: '', amount: '' }) : ''}
                ${!items.length && T.editing !== 'new' ? emptyState('box', t('tpl.no_items', 'No items yet'), editable ? t('tpl.no_items_sub', 'Add the first item to this template.') : '') : ''}</div>
            ${editable ? `<button class="addbar" data-act="tplAddItem">${ic('plus')}${t('btn.add_item', 'Add Item')}</button>` : ''}`
        : emptyState('copy', t('tpl.none', 'No templates yet'), T.canCreate ? t('tpl.none_sub', 'Create a template to bill with pre-configured items.') : '')}</div>`);
}
function itemRow(i, editable) {
    if (S.tpl.editing === i.id) return itemEditRow(i);
    return `<div class="irow" ${editable ? `draggable="true" data-drag="${esc(i.id)}"` : ''}>${editable ? `<span class="grip">${ic('grip')}</span>` : ''}<b>${esc(i.label)}</b><span class="amt">${money(i.amount)}</span>
        ${editable ? `<button class="ibtn sm" data-act="tplItemEdit" data-id="${esc(i.id)}">${ic('edit')}</button><button class="ibtn sm danger" data-act="tplItemDel" data-id="${esc(i.id)}">${ic('trash')}</button>` : ''}</div>`;
}
function itemEditRow(i) {
    return `<div class="irow edit"><input class="input" id="tiLabel" maxlength="60" value="${esc(i.label)}" placeholder="${t('tpl.item_name', 'Item name')}" autofocus>
        <input class="input" id="tiAmount" type="number" min="0" step="0.01" value="${esc(i.amount)}" placeholder="${t('tpl.item_amount', 'Amount')}" style="width:140px">
        <button class="btn pri" data-act="tplItemSave" data-id="${esc(i.id)}">${ic('check')}${t('btn.save', 'Save')}</button><button class="ibtn" data-act="tplItemCancel">${ic('x')}</button></div>`;
}
function templateModal(tpl) {
    const state = { name: tpl ? tpl.name : '', icon: tpl ? tpl.icon : 'activity', color: tpl ? tpl.color : 'blue', q: '' };
    const m = openModal(`<div class="modal w600">${mh(tpl ? t('tpl.edit_title', 'Edit Template') : t('tpl.create_title', 'Create New Template'), '', '')}<div class="mb" id="tmB"></div>
        <div class="mf">${tpl && S.tpl.canDelete ? `<div class="l"><button class="btn red" data-act="tplDelete">${ic('trash')}${t('btn.delete', 'Delete')}</button></div>` : ''}
            <button class="btn line" data-act="mClose">${t('btn.cancel', 'Cancel')}</button><button class="btn pri" data-act="mOk">${tpl ? t('btn.save', 'Save') : t('tpl.create', 'Create Template')}</button></div></div>`);
    const render = (keepFocus) => {
        const icons = TEMPLATE_ICONS.filter((n) => !state.q || n.includes(state.q.toLowerCase()));
        $('#tmB', m.el).innerHTML = `<div class="field"><span class="lbl">${t('tpl.name', 'Template Name')}</span><input class="input" data-input="tmName" maxlength="60" value="${esc(state.name)}" placeholder="${t('tpl.name_ph', 'Ex: Business Licenses')}" ${keepFocus ? '' : 'autofocus'}></div>
            <div class="row2"><div class="field"><span class="lbl">${t('tpl.icon', 'Icon')}</span><label class="search" style="width:100%">${ic('search')}<input data-input="tmIconQ" value="${esc(state.q)}" placeholder="${t('tpl.search_icons', 'Search icons...')}"></label>
                <div class="icon-grid">${icons.map((n) => `<button class="${state.icon === n ? 'on' : ''}" data-act="tmIcon" data-v="${n}" title="${n}">${ic(n)}</button>`).join('')}</div></div>
            <div class="field"><span class="lbl">${t('tpl.color', 'Color')}</span><div class="swatches">${TEMPLATE_COLORS.map((c) => `<button class="c-${c} ${state.color === c ? 'on' : ''}" data-act="tmColor" data-v="${c}"></button>`).join('')}</div>
                <span class="lbl" style="margin-top:8px">${t('tpl.preview', 'Live Preview')}</span><div><span class="preview-chip">${ticon(state.icon, state.color)}${esc(state.name || t('tpl.name_ph', 'Ex: Business Licenses'))}</span></div></div></div>`;
    };
    m.tm = state; m.render = render; render();
    m.ok = async () => {
        if (!state.name.trim()) { toast(t('label.error', 'Error'), t('error.template_name', 'Give the template a name'), 'warning'); return; }
        const res = await call('templates:save', { account: S.account, template: { id: tpl ? tpl.id : null, name: state.name, icon: state.icon, color: state.color } });
        if (!res) return;
        m.close();
        S.tpl.active = res.id;
        pageTemplates(true);
    };
}

// ═══════════════ ACTIVITY ═══════════════
const ACTIONS = () => ({
    invoice_created: ['invoice', t('act.badge.created', 'Created'), 'send'], invoice_received: ['invoice', t('act.badge.received', 'Received'), 'inbox'],
    invoice_paid: ['payment', t('act.badge.paid', 'Paid Invoice'), 'card'], payment_received: ['payment', t('act.badge.payment', 'Payment'), 'receive'],
    invoice_collected: ['payment', t('act.badge.collected', 'Collected'), 'wallet'], invoice_refunded: ['payment', t('act.badge.refund', 'Refund'), 'undo'],
    invoice_cancelled: ['danger', t('act.badge.cancelled', 'Cancelled'), 'ban'], invoice_disputed: ['dispute', t('act.badge.dispute', 'Dispute'), 'flag'],
    dispute_rejected: ['dispute', t('act.badge.dispute', 'Dispute'), 'flag'], invoice_printed: ['invoice', t('act.badge.print', 'Print'), 'printer'],
    template_created: ['template', t('act.badge.template', 'Template'), 'copy'], template_updated: ['template', t('act.badge.template', 'Template'), 'copy'],
    template_deleted: ['template', t('act.badge.template', 'Template'), 'copy'], item_added: ['item', t('act.badge.item', 'Item'), 'box'],
    item_updated: ['item', t('act.badge.item', 'Item'), 'box'], item_deleted: ['item', t('act.badge.item', 'Item'), 'box'],
    member_assigned: ['perm', t('act.badge.permission', 'Permission'), 'userkey'], group_updated: ['perm', t('act.badge.permission', 'Permission'), 'userkey'],
    group_created: ['perm', t('act.badge.permission', 'Permission'), 'userkey'], group_deleted: ['perm', t('act.badge.permission', 'Permission'), 'userkey'],
    cash_collected: ['payment', t('act.badge.cash', 'Cash'), 'cash'],
});
const BADGE_CLS = { invoice: 'acc', payment: 'ok', danger: 'bad', dispute: 'warn', template: 'mute', item: 'warn', perm: 'mute' };
function activityText(r) {
    const d = r.data || {};
    const amt = d.amount !== undefined ? money(d.amount) : '';
    const map = {
        invoice_created: [t('act.t.created', 'Created invoice for {target}', { target: d.target || '' }), `${d.ref || ''} · ${amt}`],
        invoice_received: [t('act.t.received', 'Invoice received from {from}', { from: d.from || '' }), `${d.ref || ''} · ${amt}`],
        invoice_paid: [t('act.t.paid', 'Paid invoice for {target}', { target: d.target || '' }), `${t('label.amount', 'Amount')}: ${amt}${d.tip ? ' + ' + money(d.tip) : ''}`],
        payment_received: [t('act.t.payment', 'Payment from {from}', { from: d.from || '' }), `${d.ref || ''} · ${amt}`],
        invoice_collected: [t('act.t.collected', 'Overdue invoice collected'), `${d.ref || ''} · ${amt}`],
        invoice_refunded: [t('act.t.refunded', 'Refunded {target}', { target: d.target || '' }), `${d.ref || ''} · ${amt}`],
        invoice_cancelled: [t('act.t.cancelled', 'Cancelled invoice for {target}', { target: d.target || '' }), `${d.ref || ''}${d.reason ? ' · ' + d.reason : ''}`],
        invoice_disputed: [t('act.t.disputed', 'Disputed an invoice'), `${d.ref || ''} · ${d.reason || ''}`],
        dispute_rejected: [t('act.t.rejected', 'Rejected a dispute'), d.ref || ''],
        invoice_printed: [t('act.t.printed', 'Printed an invoice'), d.ref || ''],
        template_created: [t('act.t.tpl_created', 'Created a template'), d.name || ''], template_updated: [t('act.t.tpl_updated', 'Updated a template'), d.name || ''],
        template_deleted: [t('act.t.tpl_deleted', 'Deleted a template'), d.name || ''],
        item_added: [t('act.t.item_added', 'Added an item'), `${d.name || ''}${d.template ? ' · ' + d.template : ''}`],
        item_updated: [t('act.t.item_updated', 'Updated an item'), `${d.name || ''}${amt ? ' · ' + amt : ''}`],
        item_deleted: [t('act.t.item_deleted', 'Deleted an item'), d.name || ''],
        member_assigned: [t('act.t.member', 'Moved {name} to {group}', { name: d.name || '', group: d.group || '' }), ''],
        group_updated: [t('act.t.group_updated', 'Updated group permissions'), d.group || ''], group_created: [t('act.t.group_created', 'Created a group'), d.group || ''],
        group_deleted: [t('act.t.group_deleted', 'Deleted a group'), d.group || ''], cash_collected: [t('act.t.cash', 'Collected cash at the bank'), amt],
    };
    return map[r.action] || [r.action.replace(/_/g, ' '), ''];
}
async function loadActivity() {
    const A = S.act;
    const d = await call('activity:list', { account: S.account, page: A.page, search: A.search, category: A.category });
    if (!d) return;
    Object.assign(A, d, { loaded: true });
    renderActivity();
}
function pageActivity() {
    const A = S.act;
    if (A.account !== S.account) Object.assign(A, { account: S.account, page: 1, search: '', category: '', loaded: false });
    setPage(`<div class="card tcard"><div class="tbar"><label class="search">${ic('search')}<input data-input="actSearch" placeholder="${t('label.search', 'Search...')}" value="${esc(A.search)}"></label>
        <div class="r"><div style="position:relative"><button class="fbtn ${A.category ? 'on' : ''}" data-act="actFilter">${ic('filter')}${t('filter.filters', 'Filters')}${ic('chevron')}${A.category ? '<span class="n">1</span>' : ''}</button></div></div></div>
        <div class="tscroll" id="actBody">${skel(7, 44)}</div><div class="tfoot" id="actFoot"></div></div>`);
    loadActivity();
}
function renderActivity() {
    const A = S.act; const body = $('#actBody'); if (!body) return;
    const acts = ACTIONS();
    body.innerHTML = A.rows.length ? `<table class="t"><thead><tr><th>${t('act.date', 'Date')}</th><th>${t('act.user', 'User')}</th><th>${t('act.action', 'Action')}</th><th>${t('act.details', 'Details')}</th></tr></thead><tbody>
        ${A.rows.map((r) => { const a = acts[r.action] || ['mute', r.action, 'file']; const [title, sub] = activityText(r);
            return `<tr style="cursor:default"><td><b>${esc(fmtDate(r.timestamp))}</b><span class="sub">${esc(fmtTime(r.timestamp))}</span></td><td class="b">${esc(r.player)}</td>
                <td><span class="badge ${BADGE_CLS[a[0]] || 'mute'}">${esc(a[1])}</span></td><td class="ell" style="max-width:360px"><b>${esc(title)}</b><span class="sub">${esc(sub)}</span></td></tr>`; }).join('')}</tbody></table>`
        : emptyState('history', t('act.empty', 'No activity yet'), t('act.empty_sub', 'Invoices, payments and changes are recorded here.'));
    const size = A.pageSize || 8; const n = Math.max(1, Math.ceil(A.total / size));
    $('#actFoot').innerHTML = `<span>${t('table.showing', 'Showing {from}–{to} of {total}', { from: A.total ? (A.page - 1) * size + 1 : 0, to: Math.min(A.total, A.page * size), total: A.total })}</span><div class="pager">${pager(A.page, n, 'actPage')}</div>`;
}

// ═══════════════ PERMISSIONS ═══════════════
async function pagePermissions(fresh) {
    if (!S.perms || fresh) {
        setPage(`<div class="card pad">${skel(3, 50)}</div><div class="card pad">${skel(4, 40)}</div>`);
        const d = await call('perms:get');
        if (!d || S.page !== 'permissions') return;
        const keep = S.perms || {};
        S.perms = Object.assign(d, { member: keep.member || '', memberGroup: '', editing: keep.editing || null, draft: null });
    }
    renderPermissions();
}
function renderPermissions() {
    const Pm = S.perms;
    const member = Pm.members.find((x) => x.identifier === Pm.member);
    const groupOpts = Pm.groups.map((g) => ({ value: g.id, label: g.label }));
    const editing = Pm.groups.find((g) => g.id === Pm.editing);
    if (editing && !Pm.draft) Pm.draft = Object.assign({}, editing.perms);
    const accLabel = { full: t('perm.full', 'Full Access'), high: t('perm.high', 'High Access'), normal: t('perm.normal', 'Normal Access'), limited: t('perm.limited', 'Limited Access') };
    setPage(`<div class="card"><div class="pbar">
            <div><span class="lbl">${t('perm.select_employee', 'Select Employee')}</span>${dd('pmMember', { value: Pm.member, search: true, placeholder: t('perm.pick_employee', 'Select an employee'),
                options: Pm.members.map((x) => ({ value: x.identifier, label: x.name + (x.isMe ? ` (${t('label.you', 'you')})` : ''), sub: `${x.gradeLabel || ''} · ${(Pm.groups.find((g) => g.id === x.group) || {}).label || x.group}`, dot: x.online })),
                onChange: (v) => { Pm.member = v; const mm = Pm.members.find((x) => x.identifier === v); Pm.memberGroup = mm ? mm.group : ''; renderPermissions(); } })}</div>
            <div><span class="lbl">${t('perm.current_group', 'Current Group')}</span>${dd('pmGroup', { value: Pm.memberGroup || (member ? member.group : ''), options: groupOpts, disabled: !member, placeholder: t('perm.pick_group', 'Select a group'), onChange: (v) => { Pm.memberGroup = v; renderPermissions(); } })}</div>
            <div><span class="lbl">${t('perm.action', 'Action')}</span><button class="btn soft" data-act="pmApply" ${member && Pm.memberGroup && Pm.memberGroup !== member.group ? '' : 'disabled'}>${ic('save')}${t('perm.apply', 'Apply Group')}</button></div></div></div>
        <div class="card"><div class="card-h"><span class="lbl" style="letter-spacing:.08em;text-transform:uppercase;font-size:10px;color:var(--ink-3)">${t('perm.groups', 'Groups')}</span>
            <div class="r"><button class="ibtn sm" data-act="gScroll" data-d="-1">${ic('chevl')}</button><button class="ibtn sm" data-act="gScroll" data-d="1">${ic('chevr')}</button></div></div>
            <div class="card-b"><div class="gscroll" id="gscroll">${Pm.groups.map((g) => `<button class="gcard ${Pm.editing === g.id ? 'on' : ''}" data-act="pmEdit" data-id="${esc(g.id)}">${ticon(g.icon, g.color, true)}
                <div><b>${esc(g.label)}</b><span class="acc-badge acc-${esc(g.access)}">${esc(accLabel[g.access] || g.access)}</span></div></button>`).join('')}
                <button class="gcard add" data-act="pmNewGroup">${ic('plus')}${t('perm.new_group', 'New group')}</button></div></div></div>
        <div class="card tcard" style="min-height:280px"><div class="card-h"><span class="lbl" style="letter-spacing:.08em;text-transform:uppercase;font-size:10px;color:var(--ink-3)">${t('perm.permissions', 'Permissions')}</span>
            ${editing ? `<div class="r"><button class="ibtn sm" data-act="pmGroupSettings">${ic('gear')}</button></div>` : ''}</div>
            <div class="card-b" style="flex:1">${editing ? `<div class="grid-3">${Pm.sections.map((s) => {
                const on = s.perms.filter((p) => Pm.draft[p.key]).length;
                return `<div class="psec"><div class="psec-h"><b>${esc(t('perm.section.' + s.id, s.label))}</b><span>${on}/${s.perms.length}</span></div>
                    ${s.perms.map((p) => `<button class="pcheck" data-act="pmToggle" data-k="${esc(p.key)}"><span class="cbx ${Pm.draft[p.key] ? 'on' : ''}">${ic('check')}</span>${esc(t('perm.key.' + p.key, p.label))}</button>`).join('')}</div>`;
            }).join('')}</div>` : emptyState('lock', t('perm.select_group', 'Select a group to view permissions'), t('perm.select_group_sub', 'Choose a group from the list above to manage permissions'))}</div>
            <div class="pfoot">${t('perm.editing', 'Editing Group')}: <b>${esc(editing ? editing.label : t('label.none', 'None'))}</b>
                <div class="r">${editing && !editing.builtin ? `<button class="btn red" data-act="pmDeleteGroup">${ic('trash')}${t('btn.delete', 'Delete')}</button>` : ''}
                <button class="btn soft" data-act="pmSave" ${editing ? '' : 'disabled'}>${ic('save')}${t('perm.save', 'Save Changes')}</button></div></div></div>`);
}
function groupModal(g) {
    const state = { label: g ? g.label : '', icon: g ? g.icon : 'users', color: g ? g.color : 'gray', access: g ? g.access : 'normal' };
    const m = openModal(`<div class="modal w600">${mh(g ? t('perm.group_settings', 'Group settings') : t('perm.new_group', 'New group'), '', 'userkey')}<div class="mb" id="gmB"></div>
        <div class="mf"><button class="btn line" data-act="mClose">${t('btn.cancel', 'Cancel')}</button><button class="btn pri" data-act="mOk">${t('btn.save', 'Save')}</button></div></div>`);
    const render = () => {
        $('#gmB', m.el).innerHTML = `<div class="row2"><div class="field"><span class="lbl">${t('perm.group_name', 'Group name')}</span><input class="input" data-input="gmLabel" maxlength="40" value="${esc(state.label)}" autofocus></div>
            <div class="field"><span class="lbl">${t('perm.access', 'Access level')}</span><div class="seg">${['full', 'high', 'normal', 'limited'].map((a) => `<button class="${state.access === a ? 'on' : ''}" data-act="gmAccess" data-v="${a}">${esc(t('perm.acc.' + a, a))}</button>`).join('')}</div></div></div>
            <div class="row2"><div class="field"><span class="lbl">${t('tpl.icon', 'Icon')}</span><div class="icon-grid">${TEMPLATE_ICONS.map((n) => `<button class="${state.icon === n ? 'on' : ''}" data-act="gmIcon" data-v="${n}">${ic(n)}</button>`).join('')}</div></div>
            <div class="field"><span class="lbl">${t('tpl.color', 'Color')}</span><div class="swatches">${TEMPLATE_COLORS.map((c) => `<button class="c-${c} ${state.color === c ? 'on' : ''}" data-act="gmColor" data-v="${c}"></button>`).join('')}</div></div></div>`;
    };
    m.gm = state; m.render = render; render();
    m.ok = async () => {
        const perms = g ? (S.perms.editing === g.id && S.perms.draft ? S.perms.draft : g.perms) : {};
        const res = await call('perms:saveGroup', { group: { id: g ? g.id : null, label: state.label, icon: state.icon, color: state.color, access: state.access, perms } });
        if (!res) return;
        m.close();
        const editing = S.perms.editing;
        Object.assign(S.perms, res, { draft: null, editing: g ? editing : (res.groups[res.groups.length - 1] || {}).id });
        renderPermissions();
    };
}

// ═══════════════ INSPECT ═══════════════
function pageInspect() {
    const I = S.insp;
    const admin = S.ctx.isAdmin;
    const tabs = `<div class="seg" style="width:230px"><button class="${I.type === 'citizen' ? 'on' : ''}" data-act="iType" data-v="citizen">${ic('user')}${t('insp.citizen', 'Citizen')}</button>
        <button class="${I.type === 'society' ? 'on' : ''}" data-act="iType" data-v="society">${ic('building')}${t('insp.society', 'Society')}</button></div>`;
    if (I.subject) return renderProfile();
    setPage(`<div class="card tcard"><div class="tbar">${tabs}
        <div style="position:relative" id="iSearchWrap"><label class="search">${ic('search')}<input data-input="iSearch" placeholder="${t('label.search', 'Search...')}" value="${esc(I.query)}" autofocus></label></div>
        <div class="r">${admin && S.ctx.society ? `<button class="btn ${I.jobView ? 'soft' : 'line'}" data-act="iJobView">${ic('userkey')}${t('insp.job_view', 'Job View')}</button>` : ''}</div></div>
        ${emptyState('search', I.type === 'citizen' ? t('insp.select_citizen', 'Select a Citizen') : t('insp.select_society', 'Select a Society'),
            I.type === 'citizen' ? t('insp.select_citizen_sub', 'Enter a name or identifier above to find a citizen profile') : t('insp.select_society_sub', 'Search for a society to see its billing history'))}</div>`);
    if (I.type === 'society' && !I.query) inspectSearch('');
}
const inspectSearch = debounce(async (q) => {
    const I = S.insp;
    const res = await call('inspect:search', { type: I.type, query: q });
    I.results = Array.isArray(res) ? res : [];
    const wrap = $('#iSearchWrap'); if (!wrap || S.page !== 'inspect') return;
    if (!I.results.length && !q) { closePop(); return; }
    showPop(wrap, I.results.length ? I.results.map((r) => `<button class="dd-opt" data-act="iPick" data-id="${esc(r.id)}" data-name="${esc(r.name)}">
        ${I.type === 'society' ? `<span class="av">${initials(r.short)}</span>` : `<span class="dot ${r.online ? 'on' : ''}"></span>`}<span style="flex:1;min-width:0">${esc(r.name)}<small class="mono">${esc(r.id)}${r.serverId ? ' · ID ' + esc(r.serverId) : ''}</small></span></button>`).join('')
        : `<div class="dd-empty">${t('label.no_results', 'No results')}</div>`, 'results');
}, 250);
async function loadProfile() {
    const I = S.insp; const tb = I.table;
    const d = await call('inspect:profile', { type: I.subject.type, id: I.subject.id, jobView: I.jobView, page: tb.page, search: tb.search, statuses: tb.statuses, due: tb.due });
    if (!d) return;
    Object.assign(tb, { rows: d.rows, total: d.total, counts: d.counts, pageSize: d.pageSize, loaded: true });
    I.profile = d;
    renderProfile();
}
function renderProfile() {
    const I = S.insp; const d = I.profile; const tb = I.table;
    if (!d) { setPage(`<div class="card pad">${skel(6, 44)}</div>`); loadProfile(); return; }
    const active = tb.statuses.length + (tb.due !== 'all' ? 1 : 0);
    const size = tb.pageSize || 8; const n = Math.max(1, Math.ceil(tb.total / size));
    setPage(`<div style="display:flex;align-items:center;gap:10px"><button class="back" data-act="iBack">${ic('chevl')}${t('insp.back', 'Back to search')}</button>
            <span style="margin-left:auto" class="inspecting">${ic('eye')}${t('insp.inspecting', 'Inspecting {name}', { name: esc(d.subject.name) })}${d.subject.identifier ? ` <span class="mono" style="opacity:.75">(${esc(d.subject.identifier)})</span>` : ''}</span>
            ${d.canClear ? `<button class="btn red" data-act="iClear">${ic('trash')}${t('insp.clear', 'Clear records')}</button>` : ''}</div>
        <div class="grid-${d.subject.balance !== undefined && d.subject.balance !== null ? 4 : 3}">
            <div class="card stat">${ic('doc')}<span>${t('insp.total', 'Total Invoices')}</span><b>${d.stats.total}</b></div>
            <div class="card stat ${d.stats.outstanding > 0 ? 'hot' : ''}">${ic('alert')}<span>${t('insp.outstanding', 'Outstanding')}</span><b>${money(d.stats.outstanding)}</b></div>
            <div class="card stat">${ic('checkc')}<span>${t('insp.paid', 'Total Paid')}</span><b>${money(d.stats.paid)}</b></div>
            ${d.subject.balance !== undefined && d.subject.balance !== null ? `<div class="card stat">${ic('wallet')}<span>${t('acct.balance', 'Balance')}</span><b>${money(d.subject.balance)}</b></div>` : ''}</div>
        <div class="card tcard"><div class="tbar"><h3 style="font-size:14px;font-weight:600;color:var(--white)">${t('insp.history', 'Invoice History')}</h3>${d.subject.scoped ? `<span class="badge acc">${t('insp.job_view', 'Job View')}</span>` : ''}
            <div class="r"><label class="search">${ic('search')}<input data-input="iTSearch" placeholder="${t('label.search', 'Search...')}" value="${esc(tb.search)}"></label>
                <div style="position:relative"><button class="fbtn ${active ? 'on' : ''}" data-act="iFilter">${ic('filter')}${t('filter.filters', 'Filters')}${ic('chevron')}${active ? `<span class="n">${active}</span>` : ''}</button></div></div></div>
            <div class="tscroll">${tb.rows.length ? `<table class="t"><thead><tr><th>${t('insp.type', 'Type')}</th><th>${t('insp.party', 'Sender / Recipient')}</th><th>${t('table.reason', 'Reason')}</th><th class="r">${t('table.amount', 'Amount')}</th><th>${t('table.due', 'Due Date')}</th><th class="r">${t('table.status', 'Status')}</th></tr></thead><tbody>
                ${tb.rows.map((r) => `<tr data-act="iRow" data-id="${r.id}"><td><span class="type ${r.direction === 'sent' ? 'sent' : ''}">${r.direction === 'sent' ? t('insp.sent', 'Sent') : t('insp.received', 'Received')}</span></td>
                    <td class="b ell">${esc(r.direction === 'sent' ? r.recipient : r.sender)}</td><td class="ell">${esc(r.reason || '')}<span class="sub mono">${esc(r.ref)}</span></td><td class="amt">${money(r.total + r.lateFee)}</td>
                    <td>${esc(fmtDate(r.dueDate))}</td><td class="r">${st(r.status)}</td></tr>`).join('')}</tbody></table>` : emptyState('doc', t('insp.no_history', 'No invoices'), '')}</div>
            <div class="tfoot"><span>${t('table.showing', 'Showing {from}–{to} of {total}', { from: tb.total ? (tb.page - 1) * size + 1 : 0, to: Math.min(tb.total, tb.page * size), total: tb.total })}</span><div class="pager">${pager(tb.page, n, 'iPage')}</div></div></div>`);
}
async function pageAdmin() {
    const I = S.insp;
    if (!I.registers) { setPage(`<div class="card pad">${skel(4, 44)}</div>`); I.registers = await call('admin:registers') || []; if (S.page !== 'admin') return; }
    const socOpts = (S.ctx.societies || []).map((s) => ({ value: s.id, label: s.label }));
    const props = S.ctx.settings.registerProps || [];
    I.regSociety = I.regSociety || (socOpts[0] || {}).value;
    I.regMode = I.regMode || (props.length ? 'prop' : 'point');
    I.regModel = I.regModel || (props[0] || {}).model;
    I.regRadius = I.regRadius || S.ctx.settings.registerRadius || 1;
    const modes = [
        ['prop', 'box', t('reg.mode_prop', 'Spawn prop'), t('reg.mode_prop_sub', 'No till here yet')],
        ['point', 'crosshair', t('reg.mode_point', 'Existing register'), t('reg.mode_point_sub', 'Mark the till in the map')],
        ['here', 'pin', t('reg.mode_here', 'My position'), t('reg.mode_here_sub', 'Where you stand')],
    ].filter(([m]) => m !== 'prop' || props.length);
    const how = {
        prop: t('reg.how_prop', 'The till follows your crosshair, or press H to hold it in your hands. Scroll rotates it (Shift for fine steps), E places it, G cancels.'),
        point: t('reg.how_point', 'Aim the ball at the existing till: that spot becomes the third-eye target. Scroll sets the radius, E places it, G cancels.'),
        here: t('reg.how_here', 'Adds the register where you are standing right now.'),
    }[I.regMode];
    const typeOf = (r) => (r.model ? `<span class="badge acc">${ic('box')}${esc((props.find((p) => p.model === r.model) || {}).label || r.model)}</span>` : `<span class="badge mute">${ic('crosshair')}${t('reg.type_point', 'Map till')}</span>`);
    const regs = I.registers;
    const kpi = (icon, tone, label, value, sub) => `<div class="card kpi"><div class="tile lg ${tone}">${ic(icon)}</div><div class="kv"><span>${label}</span><b>${value}</b><small>${sub}</small></div></div>`;
    setPage(`<div class="grid-4">
            ${kpi('register', 'teal', t('adm.registers', 'Registers'), regs.length, t('adm.registers_sub', 'Across all societies'))}
            ${kpi('box', 'blue', t('adm.props', 'Spawned tills'), regs.filter((r) => r.model).length, t('adm.props_sub', 'Placed with Spawn prop'))}
            ${kpi('crosshair', 'amber', t('adm.points', 'Map tills'), regs.filter((r) => !r.model).length, t('adm.points_sub', 'Existing registers marked'))}
            ${kpi('building', 'gray', t('adm.societies', 'Societies covered'), new Set(regs.map((r) => r.society)).size, t('adm.societies_sub', 'of {n} configured', { n: socOpts.length }))}
        </div>
        <div class="card"><div class="ch"><div><h3>${t('adm.new_register', 'New register')}</h3><p>${t('adm.new_register_sub', 'Pick how to place it, then aim and confirm in-game')}</p></div></div><div class="card-b" style="gap:14px;padding-top:14px">
            <div class="reg-modes">${modes.map(([m, icon, label, sub]) => `<button class="reg-mode ${I.regMode === m ? 'on' : ''}" data-act="regMode" data-v="${m}"><span class="tile ${I.regMode === m ? 'teal' : 'gray'}">${ic(icon)}</span><span><b>${label}</b><small>${sub}</small></span></button>`).join('')}</div>
            <div class="reg-form ${I.regMode === 'prop' ? 'with-prop' : ''}">
                <div class="field"><label>${t('reg.label', 'Label')}</label><input id="rLabel" maxlength="100" placeholder="${t('reg.label_ph', 'Front counter')}" value="${esc(I.regLabel || '')}"></div>
                <div class="field"><label>${t('reg.society', 'Society')}</label>${dd('regSociety', { value: I.regSociety, options: socOpts, onChange: (v) => { I.regLabel = $('#rLabel').value; I.regSociety = v; pageAdmin(); } })}</div>
                ${I.regMode === 'prop' ? `<div class="field"><label>${t('reg.prop', 'Prop')}</label>${dd('regModel', { value: I.regModel, options: props.map((p) => ({ value: p.model, label: p.label, sub: p.model })), onChange: (v) => { I.regLabel = $('#rLabel').value; I.regModel = v; } })}</div>` : ''}
                <div class="field"><label>${t('reg.radius', 'Radius (m)')}</label><input id="rRadius" type="number" min="0.5" max="10" step="0.25" value="${esc(I.regRadius)}"></div>
                <button class="btn pri md" data-act="regAdd">${ic(I.regMode === 'here' ? 'pin' : 'crosshair')}${I.regMode === 'here' ? t('reg.add_here', 'Add at my position') : t('reg.start', 'Start placing')}</button>
            </div>
            <div class="reg-hint">${ic('info')}<span>${esc(how)}</span></div></div></div>
        <div class="card" style="flex:none"><div class="ch"><div><h3>${t('adm.all_registers', 'All registers')}</h3><p>${t('adm.all_registers_sub', 'Teleport, set a waypoint, move or remove')}</p></div></div><div class="tscroll">${I.registers.length ? `<table class="t"><thead><tr><th>${t('reg.label', 'Label')}</th><th>${t('reg.society', 'Society')}</th><th>${t('reg.type', 'Type')}</th><th>${t('reg.coords', 'Coords')}</th><th>${t('reg.radius', 'Radius (m)')}</th><th>${t('reg.source', 'Source')}</th><th></th></tr></thead><tbody>
            ${I.registers.map((r) => `<tr style="cursor:default"><td class="b">${esc(r.label)}</td><td>${esc(r.societyLabel)}</td><td>${typeOf(r)}</td><td class="mono">${num(r.coords.x).toFixed(1)}, ${num(r.coords.y).toFixed(1)}, ${num(r.coords.z).toFixed(1)}</td><td>${esc(r.radius)}</td>
                <td>${r.source === 'config' ? `<span class="badge mute">config</span>` : `<span class="badge acc">${t('reg.ingame', 'in-game')}</span>`}</td>
                <td class="r"><span style="display:inline-flex;gap:6px"><button class="ibtn sm" data-act="regWaypoint" data-id="${esc(r.id)}" title="${t('reg.waypoint', 'Waypoint')}">${ic('pin')}</button><button class="ibtn sm" data-act="regTeleport" data-id="${esc(r.id)}" title="${t('reg.teleport', 'Teleport')}">${ic('teleport')}</button>
                ${r.source !== 'config' ? `<button class="ibtn sm" data-act="regMove" data-id="${esc(r.id)}" title="${t('reg.move', 'Move')}">${ic('crosshair')}</button><button class="ibtn sm danger" data-act="regDelete" data-id="${esc(r.id)}">${ic('trash')}</button>` : ''}</span></td></tr>`).join('')}</tbody></table>`
        : emptyState('register', t('reg.none', 'No registers'), t('reg.none_sub', 'Add one above or define them in config.lua'))}</div></div>`);
}

// Register placement key bar (bottom centre, shown while the billing window is closed)
function placeHud(d) {
    const el = $('#placeHud');
    if (!d || !Array.isArray(d.keys)) { el.classList.add('hidden'); el.innerHTML = ''; return; }
    el.innerHTML = d.keys.map((k) => `<span class="${k.off ? 'off' : ''}"><kbd class="${k.wide ? 'wide' : ''}">${esc(k.k)}</kbd>${esc(k.l)}</span>`).join('');
    el.classList.remove('hidden');
}

// ═══════════════ PAPER (item use) ═══════════════
function showPaper(inv) {
    if (S.mode !== 'billing') S.mode = 'paper';
    S.paperInv = inv;
    openModal(`<div class="modal w380" style="background:transparent;border:0;box-shadow:none;overflow:visible"><div style="padding:4px">${paperHtml(inv, { short: true })}</div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:16px"><button class="btn line lg" data-act="mClose">${t('paper.close', 'Close Preview')}</button>
        <button class="btn pri lg" data-act="paperPay" ${inv.payOptions ? '' : 'disabled'}>${t('btn.pay_invoice', 'Pay Invoice')}</button></div></div>`,
        { onClose: () => { if (S.mode === 'paper' && !stack.length) hidePaper(); } });
}
function hidePaper() { if (S.mode === 'paper') { S.mode = null; closeModals(); nui('close'); } }

// ═══════════════ POS ═══════════════
function openPos(data) {
    S.pos = { register: data.register, menu: data.menu || [], vat: num(data.vatRate), nearby: data.nearby || [], customer: null, items: [], status: 'idle', cat: data.menu && data.menu[0] ? data.menu[0].id : null, search: '' };
    S.mode = 'pos';
    $('#frame').classList.remove('hidden');
    $('#side').innerHTML = `<div class="nav-scroll"><div class="grp"><span>${t('pos.menu', 'Menu')}</span></div>
        ${S.pos.menu.map((c) => `<button class="nav ${S.pos.cat === c.id ? 'on' : ''}" data-act="posCat" data-id="${esc(c.id)}">${ticon(c.icon, c.color)}${esc(c.name)}</button>`).join('')}</div>`;
    $('#top').innerHTML = `<div class="top-brand"><div class="mark"></div><div><b><span>${esc(S.brand)}</span>POS</b><small>${esc(data.register.societyLabel)}</small></div></div>
        <div class="top-bar"><span class="signed"><span class="dot on"></span><b>${esc(data.register.label)}</b></span><span class="ver">${t('pos.vat', 'VAT {rate}', { rate: pct(S.pos.vat) })}</span>
        <div class="top-right"><button class="pill-close" data-act="close">${t('pos.close', 'Close register')}</button></div></div>`;
    renderKeys([['ESC', t('pos.close', 'Close register')]]);
    setPage(`<div class="pos-grid"><div class="card tcard"><div class="tbar"><label class="search">${ic('search')}<input data-input="posSearch" placeholder="${t('label.search', 'Search...')}"></label></div>
        <div class="card-b" style="flex:1;overflow:hidden"><div class="menu-grid" id="posMenu"></div></div></div>
        <div class="card tcard"><div class="card-h"><h3>${t('pos.order', 'Order')}</h3><div class="r"><button class="ibtn sm danger" data-act="posClear">${ic('trash')}</button></div></div>
            <div class="card-b" style="flex:1;overflow-y:auto" id="posBody"></div><div class="card-b" id="posFoot" style="border-top:1px solid var(--line-hair)"></div></div></div>`);
    renderPosMenu(); renderPos();
}
function posCatSync() { $$('#side .nav').forEach((b) => b.classList.toggle('on', b.dataset.id === String(S.pos.cat))); }
function renderPosMenu() {
    const p = S.pos; const el = $('#posMenu'); if (!el) return;
    const q = p.search.toLowerCase();
    const cats = q ? p.menu : p.menu.filter((c) => String(c.id) === String(p.cat));
    const items = cats.flatMap((c) => c.items.map((i) => ({ ...i, template: c.id }))).filter((i) => !q || i.label.toLowerCase().includes(q));
    el.innerHTML = items.length ? items.map((i) => { const ex = p.items.find((x) => x.template === i.template && x.item === i.id);
        return `<button class="mitem" data-act="posAdd" data-t="${esc(i.template)}" data-i="${esc(i.id)}">${ex ? `<span class="q">${ex.quantity}</span>` : ''}<b>${esc(i.label)}</b><span>${money(i.amount)}</span></button>`; }).join('')
        : `<div style="grid-column:1/-1">${emptyState('box', t('pos.empty_menu', 'No items'), t('pos.empty_menu_sub', 'Add templates for this society to fill the menu.'))}</div>`;
}
const posLocked = () => S.pos.status === 'checkout';
function renderPos() {
    const p = S.pos; const body = $('#posBody'), foot = $('#posFoot'); if (!body) return;
    let html = `<div class="field"><span class="lbl" style="display:flex;justify-content:space-between">${t('pos.customer', 'Customer')}${!p.customer ? `<button class="link" data-act="posNearby" style="text-transform:none;letter-spacing:0">${t('btn.refresh', 'Refresh')}</button>` : ''}</span>`;
    html += p.customer ? `<div class="lrow"><span class="av">${initials(p.customer.name)}</span><div class="tx"><b>${esc(p.customer.name)}</b><span>${t('pos.watching', 'Watching the customer display')}</span></div></div>`
        : (p.nearby.length ? p.nearby.map((n) => `<button class="lrow click" style="width:100%;text-align:left" data-act="posAssign" data-id="${n.id}"><span class="av gray">${initials(n.name)}</span><div class="tx"><b>${esc(n.name)}</b><span>${esc(n.distance)}m</span></div></button>`).join('')
            : `<div class="hint" style="padding:6px 2px">${t('pos.nobody', 'No customers at the counter')}</div>`);
    html += `</div><div class="field"><span class="lbl">${t('pos.items', 'Items')}</span>`;
    html += p.items.length ? p.items.map((it, idx) => `<div class="line"><div class="tx"><b>${esc(it.label)}</b><span>${money(it.amount)}</span></div>
        <div class="stepper"><button data-act="posQty" data-i="${idx}" data-d="-1" ${posLocked() ? 'disabled' : ''}>${ic('minus')}</button><span>${it.quantity}</span><button data-act="posQty" data-i="${idx}" data-d="1" ${posLocked() ? 'disabled' : ''}>${ic('plus')}</button></div>
        <span class="amt" style="font-weight:600;color:var(--white);min-width:60px;text-align:right">${money(it.amount * it.quantity)}</span></div>`).join('')
        : `<div class="hint" style="padding:6px 2px">${t('pos.tap_items', 'Tap menu items to add them')}</div>`;
    body.innerHTML = html + '</div>';
    const sub = p.items.reduce((s, i) => s + i.amount * i.quantity, 0); const vat = r2(sub * p.vat);
    const line = { idle: ['', t('pos.st_idle', 'Select a customer at the counter')], viewing: ['', t('pos.st_viewing', '{name} can see the order', { name: p.customer ? p.customer.name : '' })],
        checkout: ['wait', t('pos.st_checkout', 'Waiting for payment of {amount}', { amount: money(sub + vat) })],
        paid: ['ok', p.lastPaid ? t('pos.st_paid', '{name} paid {amount}', { name: p.lastPaid.customer || '', amount: money(p.lastPaid.amount + (p.lastPaid.tip || 0)) }) : ''],
        declined: ['bad', t('pos.st_declined', 'The customer declined')], left: ['bad', t('pos.st_left', 'The customer left')] }[p.status];
    let btn;
    if (p.status === 'checkout') btn = `<button class="btn red lg block" data-act="posVoid">${t('pos.void', 'Void checkout')}</button>`;
    else if (p.status === 'paid') btn = `<button class="btn pri lg block" data-act="posNext">${t('pos.next', 'Next customer')}</button>`;
    else btn = `<button class="btn pri lg block" data-act="posCharge" ${p.customer && p.items.length ? '' : 'disabled'}>${ic('card')}${t('pos.charge', 'Charge {amount}', { amount: money(sub + vat) })}</button>`;
    foot.innerHTML = `<div class="totals"><div><span>${t('paper.subtotal', 'Subtotal')}</span><b>${money(sub)}</b></div><div><span>${t('paper.vat', 'VAT ({rate})', { rate: pct(p.vat) })}</span><b>${money(vat)}</b></div>
        <div class="grand"><span>${t('paper.total_cap', 'Total')}</span><b>${money(sub + vat)}</b></div></div><div class="status-line ${line[0]}"><span class="dot ${line[0] === 'ok' ? 'paid' : line[0] === 'wait' ? 'pending' : line[0] === 'bad' ? 'overdue' : ''}"></span>${esc(line[1])}</div>${btn}`;
}
const posItems = () => S.pos.items.map((i) => ({ template: i.template, item: i.item, quantity: i.quantity }));
const syncPos = debounce(async () => { if (!S.pos) return; const r = await api('register:update', { registerId: S.pos.register.id, items: posItems() }); if (!r.ok) toast(t('label.error', 'Error'), r.error, 'error'); }, 150);
function posChanged() { renderPos(); renderPosMenu(); syncPos(); }
function onPosState(s) {
    const p = S.pos; if (!p) return;
    if (s.status === 'paid') { Object.assign(p, { status: 'paid', lastPaid: s, customer: null }); toast(t('toast.paid', 'Invoice paid'), t('pos.st_paid', '{name} paid {amount}', { name: s.customer || '', amount: money(s.amount + (s.tip || 0)) }), 'success'); }
    else { Object.assign(p, { status: s.status, customer: null }); call('register:nearby', { registerId: p.register.id }).then((l) => { if (Array.isArray(l) && S.pos) { S.pos.nearby = l; renderPos(); } }); }
    renderPos();
}

// ═══════════════ CUSTOMER DISPLAY ═══════════════
let dispTimer = null;
function displayOpen(d) { clearTimeout(dispTimer); S.display = { society: d.society, register: d.register, employee: d.employee, items: [], totals: {}, stage: 'order', method: 'bank', tip: 0 }; renderDisplay(); }
function displayUpdate(d) { if (!S.display) return; S.display.items = d.items || []; S.display.totals = d; renderDisplay(); }
function displayCheckout(d) {
    clearTimeout(dispTimer);
    if (!S.display) S.display = { society: d.invoice.sender, register: '', employee: d.invoice.senderName, method: 'bank', tip: 0 };
    Object.assign(S.display, { stage: 'checkout', invoice: d.invoice, items: d.invoice.items });
    renderDisplay();
}
function displayClose() { if (S.display && S.display.stage === 'done') return; S.display = null; $('#display').classList.add('hidden'); }
function renderDisplay() {
    const d = S.display, el = $('#display'); if (!d) return;
    el.classList.remove('hidden');
    const head = `<div class="dhead"><div class="mark"></div><div><b>${esc(d.society)}</b><span>${esc(d.register || t('disp.title', 'Customer display'))}</span></div></div>`;
    if (d.stage === 'done') {
        const r = d.result;
        el.innerHTML = `<div class="dpanel">${head}<div class="success"><div class="ring">${ic('check')}</div><b>${t('disp.complete', 'Payment complete')}</b><span>${money(r.charged)} · ${r.method === 'cash' ? t('label.cash_cap', 'Cash') : t('label.card', 'Card')}</span></div>
            <div class="dfoot"><button class="btn pri lg block" data-act="dispDone">${t('btn.done', 'Done')}</button></div></div>`;
        return;
    }
    const lines = (d.items || []).map((i) => `<div class="line"><div class="tx"><b>${esc(i.label)}</b><span>${money(i.amount)} × ${esc(i.quantity)}</span></div><span style="font-weight:600;color:var(--white)">${money(i.amount * i.quantity)}</span></div>`).join('')
        || `<div class="hint" style="text-align:center;padding:20px 0">${t('disp.waiting', 'Waiting for items...')}</div>`;
    let foot;
    if (d.stage === 'checkout') {
        const inv = d.invoice; const tipsOn = inv.tipsAllowed; const tip = tipsOn ? r2(inv.total * d.tip / 100) : 0;
        foot = `<div class="totals"><div><span>${t('paper.subtotal', 'Subtotal')}</span><b>${money(inv.subtotal)}</b></div><div><span>${t('paper.vat', 'VAT ({rate})', { rate: pct(inv.vatRate) })}</span><b>${money(inv.vat)}</b></div>
            ${tip ? `<div><span>${t('paper.tip', 'Tip')}</span><b>${money(tip)}</b></div>` : ''}<div class="grand"><span>${t('paper.total_cap', 'Total')}</span><b>${money(inv.total + tip)}</b></div></div>
            <div class="seg"><button class="${d.method === 'bank' ? 'on' : ''}" data-act="dMethod" data-v="bank">${ic('card')}${t('label.card', 'Card')}</button><button class="${d.method === 'cash' ? 'on' : ''}" data-act="dMethod" data-v="cash">${ic('cash')}${t('label.cash_cap', 'Cash')}</button></div>
            ${tipsOn ? `<div class="tips">${[0, 10, 15, 20].map((x) => `<button class="${d.tip === x ? 'on' : ''}" data-act="dTip" data-v="${x}">${x ? x + '%' : t('pay.no_tip', 'No tip')}</button>`).join('')}</div>` : ''}
            <div style="display:flex;gap:8px"><button class="btn line lg" data-act="dDecline">${t('disp.not_now', 'Not now')}</button><button class="btn pri lg" style="flex:1" data-act="dPay" id="dPay">${t('btn.pay_amount', 'Pay {amount}', { amount: money(inv.total + tip) })}</button></div>`;
    } else {
        const tt = d.totals || {};
        foot = `<div class="totals"><div><span>${t('paper.subtotal', 'Subtotal')}</span><b>${money(tt.subtotal)}</b></div><div><span>${t('paper.vat', 'VAT ({rate})', { rate: pct(tt.vatRate) })}</span><b>${money(tt.vat)}</b></div>
            <div class="grand"><span>${t('paper.total_cap', 'Total')}</span><b>${money(tt.total)}</b></div></div><div class="dhint"><span class="key">BACKSPACE</span>${t('disp.leave', 'Leave the counter')}</div>`;
    }
    el.innerHTML = `<div class="dpanel">${head}<div class="dstate"><span class="dot ${d.stage === 'checkout' ? 'pending' : 'on'}"></span>${d.stage === 'checkout' ? t('disp.ready', 'Ready to pay') : t('disp.served_by', 'Served by {name}', { name: esc(d.employee) })}</div>
        <div class="dbody">${lines}</div><div class="dfoot">${foot}</div></div>`;
}
function finishDisplay() { clearTimeout(dispTimer); S.display = null; $('#display').classList.add('hidden'); nui('displayDone'); }

// ═══════════════ ACTIONS ═══════════════
const A = {
    mClose: () => { const m = topModal(); if (m) m.close(null); },
    mOk: () => { const m = topModal(); if (m && m.ok) m.ok(); },
    close: () => closeUI(),
    go: (d) => go(d.page),
    qaToggle: (d, el) => {
        const wrap = $('#qa');
        if (openPop && openPop.owner === wrap) { closePop(); return; }
        const items = [];
        if (canCreate()) items.push(`<button class="qa-item" data-act="create">${ic('plus')}<span><b>${t('qa.create', 'Create Invoice')}</b><span>${t('qa.create_sub', 'Create a new invoice')}</span></span></button>`);
        if (S.ctx.settings.payByReference) items.push(`<button class="qa-item" data-act="payRef">${ic('card')}<span><b>${t('qa.pay_ref', 'Pay by Reference')}</b><span>${t('qa.pay_ref_sub', 'Pay an invoice by reference')}</span></span></button>`);
        showPop(wrap, `<div class="ttl">${t('nav.quick_actions', 'Quick Actions')}</div>${items.join('') || `<div class="dd-empty">${t('qa.none', 'Nothing available')}</div>`}`, 'qa-menu');
    },
    acctToggle: () => {
        if (!S.ctx.society) return;
        const wrap = $('#acctWrap');
        if (openPop && openPop.owner === wrap) { closePop(); return; }
        showPop(wrap, `<div class="ttl">${t('acct.switch', 'Switch account')}</div>
            <button class="qa-item" data-act="acct" data-v="personal">${ic('user')}<span><b>${t('acct.personal', 'Personal Billing')}</b><span>${money(S.ctx.player.bank)}</span></span></button>
            <button class="qa-item" data-act="acct" data-v="society">${ic('building')}<span><b>${esc(S.ctx.society.label)}</b><span>${S.ctx.society.balance !== null && S.ctx.society.balance !== undefined ? money(S.ctx.society.balance) : esc(S.ctx.society.group ? S.ctx.society.group.label : '')}</span></span></button>`, 'qa-menu acct-menu');
    },
    acct: (d) => { closePop(); if (S.account === d.v) return; S.account = d.v; S.dash = null; S.tpl = null; go(S.page); },
    create: () => { closePop(); createInvoice(); },
    payRef: () => { closePop(); payByReference(''); },
    payAll: async () => {
        const tb = tableState('received');
        const res = await call('invoices:list', { account: S.account, box: 'received', page: 1, pageSize: 50, statuses: ['pending', 'partial', 'overdue'] });
        if (!res || !res.rows.length) return;
        const rows = res.rows.filter(payableRow);
        payMany(rows.map((r) => r.id), rows.reduce((s, r) => s + r.remaining, 0));
        tb.stale = true;
    },
    // dropdowns
    ddOpen: (d, el) => {
        const wrap = el.closest('.dd');
        if (openPop && openPop.owner === wrap) { closePop(); return; }
        const cfg = DD[d.key];
        const pop = showPop(wrap, `${cfg.search ? `<div class="s"><input data-input="ddSearch" data-key="${esc(d.key)}" placeholder="${t('label.search', 'Search...')}"></div>` : ''}<div class="dd-items">${ddOptions(d.key)}</div>`, 'dd-list');
        const s = pop.querySelector('input'); if (s) setTimeout(() => s.focus(), 20);
    },
    ddPick: (d) => { const cfg = DD[d.key]; closePop(); if (cfg) { cfg.value = d.v; if (cfg.onChange) cfg.onChange(d.v); } },
    // tables
    fOpen: (d, el) => {
        const tb = tableState(S.page);
        const wrap = el.parentElement;
        if (openPop && openPop.owner === wrap) { closePop(); return; }
        filterPop(wrap, tb, (draft) => { Object.assign(tb, draft, { page: 1 }); tb.selected.clear(); pageTable(tb.box); loadTable(tb); });
    },
    fStatus: (d) => { const p = openPop && openPop.el; if (!p || !p.draft) return; const i = p.draft.statuses.indexOf(d.s); if (i >= 0) p.draft.statuses.splice(i, 1); else p.draft.statuses.push(d.s); p.rerender(); },
    fDue: (d) => { const p = openPop && openPop.el; if (!p || !p.draft) return; p.draft.due = d.v; p.rerender(); },
    fClear: () => { const p = openPop && openPop.el; if (!p || !p.draft) return; p.draft.statuses = []; p.draft.due = 'all'; p.rerender(); },
    fApply: () => { const p = openPop && openPop.el; if (p && p.apply) p.apply(); },
    fReset: () => { const tb = tableState(S.page); Object.assign(tb, { statuses: [], due: 'all', page: 1 }); pageTable(tb.box); loadTable(tb); },
    tPage: (d) => { const tb = tableState(S.page); tb.page = +d.p; loadTable(tb); },
    sel: (d, el, e) => {
        e.stopPropagation();
        const tb = tableState(S.page); const row = tb.rows.find((r) => r.id === +d.id);
        if (!row || !payableRow(row)) return;
        if (tb.selected.has(row.id)) tb.selected.delete(row.id); else tb.selected.set(row.id, row);
        renderTableBody(tb);
    },
    selAll: (d, el, e) => {
        e.stopPropagation();
        const tb = tableState(S.page); const payable = tb.rows.filter(payableRow);
        const all = payable.every((r) => tb.selected.has(r.id));
        payable.forEach((r) => { if (all) tb.selected.delete(r.id); else tb.selected.set(r.id, r); });
        renderTableBody(tb);
    },
    paySelected: () => { const tb = tableState(S.page); const rows = [...tb.selected.values()]; if (rows.length) payMany(rows.map((r) => r.id), rows.reduce((s, r) => s + r.remaining, 0)); },
    row: (d, el, e) => {
        const tb = tableState(S.page); const r = tb.rows.find((x) => x.id === +d.id); if (!r) return;
        const sent = tb.box === 'sent';
        ctxMenu(e.clientX, e.clientY, [r.reason || r.ref, money(r.remaining || r.total)], [
            { act: 'view', id: r.id, icon: 'eye', label: t('menu.view', 'View Invoice') },
            !sent && payableRow(r) && { act: 'pay', id: r.id, icon: 'card', label: t('menu.pay', 'Pay Invoice') },
            S.ctx.settings.print && { act: 'print', id: r.id, icon: 'printer', label: t('menu.print', 'Print Invoice') },
            sent && isOpen(r) && r.amountPaid === 0 && { act: 'cancel', id: r.id, icon: 'ban', label: t('menu.cancel', 'Cancel Invoice'), danger: true },
        ]);
    },
    view: (d) => { closePop(); openRail(+d.id); },
    railClose: () => closeRail(),
    copyRef: (d) => copyText(d.ref),
    nxMove: (d) => { S.nx = (S.nx || 0) + Number(d.v); renderNext(); },
    pay: (d) => { closePop(); payInvoice(+d.id); },
    paperPay: () => { if (S.paperInv) payInvoice(S.paperInv.id, S.paperInv); },
    print: async (d) => { closePop(); if (await call('invoices:print', { id: +d.id })) toast(t('toast.printed', 'Invoice printed'), t('toast.printed_body', 'A copy was added to your pockets'), 'success'); },
    cancel: async (d) => {
        closePop();
        const reason = await promptBox({ title: t('menu.cancel', 'Cancel Invoice'), text: t('confirm.cancel', 'The recipient is notified. This cannot be undone.'), placeholder: t('confirm.reason_opt', 'Reason (optional)'), ok: t('btn.cancel_invoice', 'Cancel invoice'), danger: true, icon: 'ban' });
        if (reason === null) return;
        if (await call('invoices:cancel', { id: +d.id, reason })) { toast(t('toast.cancelled', 'Invoice cancelled'), '', 'success'); closeRail(); refreshCtx(); }
    },
    dispute: async (d) => {
        const reason = await promptBox({ title: t('btn.dispute', 'Dispute'), text: t('confirm.dispute', 'The sender reviews your dispute. You cannot pay until it is resolved.'), placeholder: t('confirm.dispute_ph', 'What is wrong with this invoice?'), required: true, icon: 'flag', max: 250 });
        if (reason === null) return;
        if (await call('invoices:dispute', { id: +d.id, reason })) { toast(t('toast.disputed', 'Dispute submitted'), '', 'success'); refreshCtx(); }
    },
    resolve: async (d) => {
        const accept = d.a === 'accept';
        if (!await confirmBox({ title: accept ? t('btn.accept_dispute', 'Accept dispute') : t('btn.reject_dispute', 'Reject dispute'), text: accept ? t('confirm.accept', 'The invoice is cancelled (or refunded if money was paid).') : t('confirm.reject', 'The invoice becomes payable again.'), danger: accept })) return;
        if (await call('invoices:resolve', { id: +d.id, action: d.a })) { toast(t('toast.resolved', 'Dispute resolved'), '', 'success'); refreshCtx(); }
    },
    refund: async (d) => {
        const reason = await promptBox({ title: t('btn.refund', 'Refund'), text: t('confirm.refund', 'Everything paid is returned to whoever paid it, out of the society account.'), placeholder: t('confirm.reason_opt', 'Reason (optional)'), ok: t('btn.refund', 'Refund'), danger: true, icon: 'undo' });
        if (reason === null) return;
        const r = await call('invoices:refund', { id: +d.id, reason });
        if (r) { toast(t('toast.refunded', 'Refunded'), money(r.amount), 'success'); refreshCtx(); }
    },
    adminDelete: async (d) => {
        closePop();
        if (!await confirmBox({ title: t('btn.delete', 'Delete'), text: t('confirm.delete', 'Delete this invoice record permanently?'), danger: true, ok: t('btn.delete', 'Delete') })) return;
        if (await call('admin:delete', { id: +d.id })) { toast(t('toast.deleted', 'Deleted'), '', 'success'); closeRail(); if (S.insp.subject) { S.insp.profile = null; renderProfile(); } else refreshCtx(); }
    },
    // pay modal
    pMethod: (d) => { const m = topModal(); if (m && m.pay) { m.pay.method = d.m; m.render(); } },
    pFull: (d) => { const m = topModal(); if (m && m.pay) { m.pay.full = d.v === '1'; m.render(); } },
    pTip: (d) => { const m = topModal(); if (m && m.pay) { m.pay.tip = +d.v; m.render(); } },
    pmMethod: (d) => { const m = topModal(); if (m && m.pm) { m.pm.method = d.m; m.render(); } },
    refLookup: () => { const m = topModal(); if (m && m.lookup) m.lookup(); },
    // create modal
    ciType: (d) => { const m = topModal(); if (!m || !m.ci) return; m.ci.type = d.v; m.ci.recipient = ''; m.render(); },
    ciNearby: async () => { const m = topModal(); if (!m || !m.ci) return; const l = await call('getNearby'); m.ci.nearby = Array.isArray(l) ? l : []; m.render(); },
    ciAdd: () => { const m = topModal(); if (m && m.addTemplateItem) m.addTemplateItem(); },
    ciQty: (d) => { const m = topModal(); if (!m || !m.ci) return; const it = m.ci.items[+d.i]; if (!it) return; it.quantity += +d.d; if (it.quantity <= 0) m.ci.items.splice(+d.i, 1); else it.quantity = Math.min(it.quantity, S.ctx.settings.maxQuantity); m.render(); },
    ciDel: (d) => { const m = topModal(); if (!m || !m.ci) return; m.ci.items.splice(+d.i, 1); m.render(); },
    ciCustomToggle: () => { const m = topModal(); if (!m || !m.ci) return; m.ci.custom = !m.ci.custom; m.render(); if (m.ci.custom) setTimeout(() => { const i = $('#ciCName', m.el); if (i) i.focus(); }, 20); },
    ciCustomAdd: () => { const m = topModal(); if (m && m.addCustom) m.addCustom(); },
    // templates
    tplTab: (d) => { S.tpl.active = d.id; S.tpl.editing = null; S.tpl.search = ''; pageTemplates(); },
    tplNew: () => templateModal(null),
    tplEdit: () => templateModal(S.tpl.templates.find((x) => String(x.id) === String(S.tpl.active))),
    tplDelete: async () => {
        if (!await confirmBox({ title: t('btn.delete', 'Delete'), text: t('confirm.tpl_delete', 'Delete this template and its items?'), danger: true, ok: t('btn.delete', 'Delete') })) return;
        if (await call('templates:delete', { account: S.account, id: S.tpl.active })) { closeModals(); S.tpl.active = null; pageTemplates(true); }
    },
    tplAddItem: () => { S.tpl.editing = 'new'; pageTemplates(); const el = $('#tplItems'); if (el) el.scrollTop = el.scrollHeight; },
    tplItemEdit: (d) => { S.tpl.editing = d.id; pageTemplates(); },
    tplItemCancel: () => { S.tpl.editing = null; pageTemplates(); },
    tplItemSave: async (d) => {
        const res = await call('templates:saveItem', { account: S.account, templateId: S.tpl.active, item: { id: d.id || null, label: $('#tiLabel').value, amount: num($('#tiAmount').value) } });
        if (!res) return;
        const cur = S.tpl.templates.find((x) => String(x.id) === String(S.tpl.active)); cur.items = res; S.tpl.editing = null; pageTemplates();
    },
    tplItemDel: async (d) => {
        if (!await confirmBox({ title: t('btn.delete', 'Delete'), text: t('confirm.item_delete', 'Delete this item?'), danger: true, ok: t('btn.delete', 'Delete') })) return;
        const res = await call('templates:deleteItem', { account: S.account, templateId: S.tpl.active, itemId: d.id });
        if (res) { S.tpl.templates.find((x) => String(x.id) === String(S.tpl.active)).items = res; pageTemplates(); }
    },
    tmIcon: (d) => { const m = topModal(); if (m && m.tm) { m.tm.icon = d.v; m.render(true); } },
    tmColor: (d) => { const m = topModal(); if (m && m.tm) { m.tm.color = d.v; m.render(true); } },
    // activity
    actPage: (d) => { S.act.page = +d.p; loadActivity(); },
    actFilter: (d, el) => {
        const wrap = el.parentElement;
        if (openPop && openPop.owner === wrap) { closePop(); return; }
        const cats = [['', t('filter.all', 'All')], ['invoice', t('act.cat.invoice', 'Invoices')], ['payment', t('act.cat.payment', 'Payments')], ['template', t('act.cat.template', 'Templates')], ['item', t('act.cat.item', 'Items')], ['permission', t('act.cat.permission', 'Permissions')]];
        showPop(wrap, `<h5>${t('act.category', 'Category')}</h5>${cats.map(([v, l]) => `<button class="fopt" data-act="actCat" data-v="${v}"><span class="cbx ${S.act.category === v ? 'on' : ''}">${ic('check')}</span>${esc(l)}</button>`).join('')}`, 'filters');
    },
    actCat: (d) => { closePop(); S.act.category = d.v; S.act.page = 1; pageActivity(); },
    // permissions
    pmApply: async () => {
        const Pm = S.perms;
        const res = await call('perms:assign', { identifier: Pm.member, group: Pm.memberGroup });
        if (!res) return;
        Object.assign(Pm, res); Pm.memberGroup = ''; toast(t('toast.group_applied', 'Group applied'), '', 'success'); renderPermissions();
    },
    pmEdit: (d) => { S.perms.editing = d.id; S.perms.draft = null; renderPermissions(); },
    pmToggle: (d) => { const dr = S.perms.draft; if (!dr) return; dr[d.k] = !dr[d.k]; renderPermissions(); },
    pmSave: async () => {
        const Pm = S.perms; const g = Pm.groups.find((x) => x.id === Pm.editing); if (!g) return;
        const res = await call('perms:saveGroup', { group: { id: g.id, label: g.label, icon: g.icon, color: g.color, access: g.access, perms: Pm.draft } });
        if (!res) return;
        Object.assign(Pm, res, { draft: null }); toast(t('toast.saved', 'Saved'), g.label, 'success'); renderPermissions();
    },
    pmNewGroup: () => groupModal(null),
    pmGroupSettings: () => groupModal(S.perms.groups.find((x) => x.id === S.perms.editing)),
    pmDeleteGroup: async () => {
        if (!await confirmBox({ title: t('btn.delete', 'Delete'), text: t('confirm.group_delete', 'Delete this group? Its members go back to their default group.'), danger: true, ok: t('btn.delete', 'Delete') })) return;
        const res = await call('perms:deleteGroup', { id: S.perms.editing });
        if (res) { Object.assign(S.perms, res, { editing: null, draft: null }); renderPermissions(); }
    },
    gScroll: (d) => { const el = $('#gscroll'); if (el) el.scrollLeft += (+d.d) * 220; },
    gmAccess: (d) => { const m = topModal(); if (m && m.gm) { m.gm.access = d.v; m.render(); } },
    gmIcon: (d) => { const m = topModal(); if (m && m.gm) { m.gm.icon = d.v; m.render(); } },
    gmColor: (d) => { const m = topModal(); if (m && m.gm) { m.gm.color = d.v; m.render(); } },
    // inspect
    iType: (d) => { Object.assign(S.insp, { type: d.v, tab: 'search', subject: null, query: '', results: [] }); closePop(); pageInspect(); },
    iJobView: () => { S.insp.jobView = !S.insp.jobView; pageInspect(); },
    iPick: (d) => {
        closePop();
        Object.assign(S.insp, { subject: { type: S.insp.type, id: d.id, name: d.name }, profile: null, table: { page: 1, search: '', statuses: [], due: 'all', rows: [], total: 0, counts: {} } });
        renderProfile();
    },
    iBack: () => { S.insp.subject = null; S.insp.profile = null; pageInspect(); },
    iPage: (d) => { S.insp.table.page = +d.p; loadProfile(); },
    iFilter: (d, el) => {
        const wrap = el.parentElement;
        if (openPop && openPop.owner === wrap) { closePop(); return; }
        filterPop(wrap, S.insp.table, (draft) => { Object.assign(S.insp.table, draft, { page: 1 }); loadProfile(); });
    },
    iRow: (d, el, e) => {
        const r = S.insp.table.rows.find((x) => x.id === +d.id); if (!r) return;
        ctxMenu(e.clientX, e.clientY, [r.reason || r.ref, money(r.total)], [
            { act: 'view', id: r.id, icon: 'eye', label: t('menu.view', 'View Invoice') },
            S.ctx.isAdmin && isOpen(r) && r.amountPaid === 0 && { act: 'cancel', id: r.id, icon: 'ban', label: t('menu.cancel', 'Cancel Invoice'), danger: true },
            S.ctx.isAdmin && S.ctx.settings.adminDelete && { act: 'adminDelete', id: r.id, icon: 'trash', label: t('btn.delete', 'Delete'), danger: true },
        ]);
    },
    iClear: async () => {
        const s = S.insp.profile.subject;
        if (!await confirmBox({ title: t('insp.clear', 'Clear records'), text: t('confirm.clear', 'Delete every invoice sent or received by {name}? This cannot be undone.', { name: s.name }), danger: true, ok: t('insp.clear', 'Clear records') })) return;
        const r = await call('admin:clear', { identifier: s.identifier });
        if (r) { toast(t('toast.cleared', 'Records cleared'), t('toast.cleared_body', '{n} invoice(s) deleted', { n: r.deleted }), 'success'); S.insp.profile = null; renderProfile(); }
    },
    regMode: (d) => { S.insp.regLabel = $('#rLabel').value; S.insp.regRadius = num($('#rRadius').value, S.insp.regRadius); S.insp.regMode = d.v; pageAdmin(); },
    regAdd: async () => {
        const I = S.insp;
        const label = $('#rLabel').value.trim(); const radius = num($('#rRadius').value, 1);
        I.regLabel = label; I.regRadius = radius;
        if (!label) { toast(t('label.error', 'Error'), t('error.register_label', 'Give the register a label'), 'error'); return; }
        if (!I.regSociety) { toast(t('label.error', 'Error'), t('error.pick_society', 'Pick a society'), 'error'); return; }
        if (I.regMode === 'here') {
            const list = await call('admin:addRegister', { label, society: I.regSociety, radius });
            if (list) { I.registers = list; I.regLabel = ''; toast(t('toast.register_added', 'Register added'), '', 'success'); pageAdmin(); }
            return;
        }
        I.regLabel = ''; I.registers = null;
        nui('placeRegister', { mode: I.regMode, label, society: I.regSociety, radius, model: I.regMode === 'prop' ? I.regModel : null });
    },
    regMove: (d) => {
        const r = (S.insp.registers || []).find((x) => x.id === d.id); if (!r) return;
        S.insp.registers = null;
        nui('placeRegister', { id: r.id, mode: r.model ? 'prop' : 'point', label: r.label, society: r.society, radius: r.radius, model: r.model || null, heading: r.heading });
    },
    regDelete: async (d) => {
        if (!await confirmBox({ title: t('btn.delete', 'Delete'), text: t('confirm.register_delete', 'Remove this register for everyone?'), danger: true, ok: t('btn.delete', 'Delete') })) return;
        const list = await call('admin:deleteRegister', { id: d.id }); if (list) { S.insp.registers = list; pageAdmin(); }
    },
    regTeleport: async (d) => { if (await call('admin:teleport', { id: d.id })) toast(t('toast.teleported', 'Teleported'), '', 'success'); },
    regWaypoint: (d) => { const r = (S.insp.registers || []).find((x) => x.id === d.id); if (r) { nui('setWaypoint', r.coords); toast(t('toast.waypoint', 'Waypoint set'), r.label, 'success'); } },
    // POS
    posCat: (d) => { S.pos.cat = isNaN(+d.id) ? d.id : +d.id; posCatSync(); renderPosMenu(); },
    posAdd: (d) => {
        const p = S.pos;
        if (posLocked()) { toast(t('label.error', 'Error'), t('pos.locked', 'Void the checkout to change the order'), 'warning'); return; }
        if (p.status === 'paid') p.items = [];
        if (['paid', 'declined', 'left'].includes(p.status)) p.status = p.customer ? 'viewing' : 'idle';
        const cat = p.menu.find((c) => String(c.id) === String(d.t)); const it = cat && cat.items.find((i) => i.id === d.i); if (!it) return;
        const ex = p.items.find((x) => String(x.template) === String(cat.id) && x.item === it.id);
        if (ex) ex.quantity++; else p.items.push({ template: cat.id, item: it.id, label: it.label, amount: num(it.amount), quantity: 1 });
        posChanged();
    },
    posQty: (d) => { const it = S.pos.items[+d.i]; if (!it) return; it.quantity += +d.d; if (it.quantity <= 0) S.pos.items.splice(+d.i, 1); posChanged(); },
    posClear: () => { if (posLocked()) return; S.pos.items = []; posChanged(); },
    posNearby: async () => { const l = await call('register:nearby', { registerId: S.pos.register.id }); if (Array.isArray(l)) { S.pos.nearby = l; renderPos(); } },
    posAssign: async (d) => { const r = await call('register:assign', { registerId: S.pos.register.id, customerId: +d.id }); if (!r) return; S.pos.customer = r.customer; S.pos.status = 'viewing'; renderPos(); syncPos(); },
    posCharge: async () => {
        const r = await call('register:charge', { registerId: S.pos.register.id, items: posItems() });
        if (!r) return; S.pos.status = 'checkout'; renderPos();
    },
    posVoid: async () => { const r = await call('register:next', { registerId: S.pos.register.id }); if (!r) return; Object.assign(S.pos, { status: 'idle', customer: null, nearby: r.nearby || [] }); renderPos(); },
    posNext: async () => { const r = await call('register:next', { registerId: S.pos.register.id }); if (!r) return; Object.assign(S.pos, { status: 'idle', customer: null, items: [], nearby: r.nearby || [] }); renderPos(); renderPosMenu(); },
    // display
    dMethod: (d) => { S.display.method = d.v; renderDisplay(); },
    dTip: (d) => { S.display.tip = +d.v; renderDisplay(); },
    dPay: async () => {
        const ds = S.display; const b = $('#dPay'); if (b) b.disabled = true;
        const r = await call('display:pay', { method: ds.method, tip: ds.invoice.tipsAllowed ? r2(ds.invoice.total * ds.tip / 100) : 0 });
        if (!r) { if (b) b.disabled = false; return; }
        ds.stage = 'done'; ds.result = r; renderDisplay(); dispTimer = setTimeout(finishDisplay, 6000);
    },
    dDecline: () => { S.display = null; $('#display').classList.add('hidden'); nui('displayDecline'); },
    dispDone: () => finishDisplay(),
};

// ═══════════════ INPUTS ═══════════════
const reloadTable = debounce(() => { const tb = tableState(S.page); tb.page = 1; loadTable(tb); }, 300);
const reloadAct = debounce(() => { S.act.page = 1; loadActivity(); }, 300);
const reloadProfile = debounce(() => { S.insp.table.page = 1; loadProfile(); }, 300);
const INPUTS = {
    tSearch: (v) => { tableState(S.page).search = v; reloadTable(); },
    actSearch: (v) => { S.act.search = v; reloadAct(); },
    iSearch: (v) => { S.insp.query = v; inspectSearch(v); },
    iTSearch: (v) => { S.insp.table.search = v; reloadProfile(); },
    tplSearch: (v) => { S.tpl.search = v; const el = $('#tplItems'); const cur = S.tpl.templates.find((x) => String(x.id) === String(S.tpl.active)); if (el && cur) el.innerHTML = cur.items.filter((i) => !v || i.label.toLowerCase().includes(v.toLowerCase())).map((i) => itemRow(i, !cur.global && S.tpl.canEdit)).join(''); },
    ddSearch: (v, el) => { const box = el.closest('.pop').querySelector('.dd-items'); if (box) box.innerHTML = ddOptions(el.dataset.key, v); },
    pAmount: (v) => { const m = topModal(); if (m && m.pay) { m.pay.amount = v; m.render(); const i = $('[data-input="pAmount"]', m.el); if (i) { i.focus(); i.setSelectionRange(i.value.length, i.value.length); } } },
    ciNotes: (v) => { const m = topModal(); if (m && m.ci) m.ci.notes = v; },
    tmName: (v) => { const m = topModal(); if (m && m.tm) { m.tm.name = v; const c = $('.preview-chip', m.el); if (c) c.lastChild.textContent = v || t('tpl.name_ph', 'Ex: Business Licenses'); } },
    tmIconQ: (v) => { const m = topModal(); if (m && m.tm) { m.tm.q = v; m.render(true); const i = $('[data-input="tmIconQ"]', m.el); if (i) { i.focus(); i.setSelectionRange(v.length, v.length); } } },
    gmLabel: (v) => { const m = topModal(); if (m && m.gm) m.gm.label = v; },
    posSearch: (v) => { S.pos.search = v; renderPosMenu(); },
};

document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-act]');
    if (openPop && (!el || !openPop.el.contains(el)) && !(el && openPop.owner && openPop.owner.contains(el))) {
        if (!e.target.closest('.pop') && !e.target.closest('.ctx')) closePop();
    }
    if (!el || el.disabled) return;
    const fn = A[el.dataset.act];
    if (fn) { e.preventDefault(); fn(el.dataset, el, e); }
});
document.addEventListener('input', (e) => { const k = e.target.dataset && e.target.dataset.input; if (k && INPUTS[k]) INPUTS[k](e.target.value, e.target); });
document.addEventListener('keydown', (e) => {
    const typing = ['INPUT', 'TEXTAREA'].includes(document.activeElement && document.activeElement.tagName);
    if (e.key === 'Escape') {
        e.preventDefault();
        if (openPop) { closePop(); return; }
        if (topModal()) { topModal().close(null); return; }
        if (S.rail) { closeRail(); return; }
        if (S.display && S.display.stage === 'checkout' && !S.mode) { A.dDecline(); return; }
        if (S.display && S.display.stage === 'done' && !S.mode) { finishDisplay(); return; }
        if (S.mode === 'paper') { hidePaper(); return; }
        if (S.mode) closeUI();
        return;
    }
    if (S.mode === 'billing' && !typing && !topModal() && !openPop && !e.ctrlKey && !e.altKey && !e.metaKey && !e.repeat) {
        const k = e.key.toLowerCase();
        if (k === 'n' && canCreate()) { e.preventDefault(); createInvoice(); return; }
        if (k === 'r' && S.ctx.settings.payByReference) { e.preventDefault(); payByReference(''); return; }
        if (k === 's' && S.ctx.society) { e.preventDefault(); A.acct({ v: S.account === 'society' ? 'personal' : 'society' }); return; }
        if (/^[1-9]$/.test(k)) {
            const av = pages(); const order = ['overview', 'received', 'sent', 'templates', 'activity', 'permissions', 'inspect', 'admin'].filter((x) => av[x]);
            const target = order[Number(k) - 1];
            if (target) { e.preventDefault(); go(target); }
            return;
        }
    }
    if (e.key === 'Enter') {
        if (document.activeElement && document.activeElement.id === 'refIn') { e.preventDefault(); A.refLookup(); return; }
        if (document.activeElement && ['tiLabel', 'tiAmount'].includes(document.activeElement.id)) { e.preventDefault(); const b = $('[data-act="tplItemSave"]'); if (b) A.tplItemSave(b.dataset); return; }
        if (document.activeElement && ['ciCName', 'ciCAmt'].includes(document.activeElement.id)) { e.preventDefault(); A.ciCustomAdd(); return; }
        if (!typing && topModal() && topModal().ok) { topModal().ok(); }
    }
});

// drag & drop reorder (templates)
let dragId = null;
document.addEventListener('dragstart', (e) => { const r = e.target.closest('[data-drag]'); if (!r) return; dragId = r.dataset.drag; r.classList.add('dragging'); e.dataTransfer.effectAllowed = 'move'; });
document.addEventListener('dragend', (e) => { const r = e.target.closest('[data-drag]'); if (r) r.classList.remove('dragging'); $$('.irow.over').forEach((x) => x.classList.remove('over')); });
document.addEventListener('dragover', (e) => { const r = e.target.closest('[data-drag]'); if (!r || !dragId) return; e.preventDefault(); $$('.irow.over').forEach((x) => x !== r && x.classList.remove('over')); r.classList.add('over'); });
document.addEventListener('drop', async (e) => {
    const r = e.target.closest('[data-drag]'); if (!r || !dragId || r.dataset.drag === dragId) return;
    e.preventDefault();
    const cur = S.tpl.templates.find((x) => String(x.id) === String(S.tpl.active));
    const from = cur.items.findIndex((i) => i.id === dragId), to = cur.items.findIndex((i) => i.id === r.dataset.drag);
    const [moved] = cur.items.splice(from, 1); cur.items.splice(to, 0, moved);
    dragId = null; pageTemplates();
    const res = await call('templates:reorder', { account: S.account, templateId: cur.id, order: cur.items.map((i) => i.id) });
    if (res) cur.items = res;
});

// ═══════════════ MESSAGES ═══════════════
window.addEventListener('message', (ev) => {
    const { action, data } = ev.data || {};
    switch (action) {
        case 'init':
            S.locale = data.locale || {}; S.currency = data.currency || '$'; S.currencyPos = data.currencyPosition || 'before';
            S.title = data.title || 'Billing'; S.brand = data.brand || 'NAYZEEE'; S.clock = data.clock !== false;
            applyColors(data.colors); break;
        case 'open': open(data); break;
        case 'navigate': if (data.page) go(data.page); handleExtra(data.extra); break;
        case 'close': hide(); break;
        case 'toast': toast(data.title, data.message, data.type); break;
        case 'refresh': refreshCtx(); break;
        case 'paper': showPaper(data); break;
        case 'posOpen': openPos(data); break;
        case 'posState': onPosState(data); break;
        case 'displayOpen': displayOpen(data); break;
        case 'displayUpdate': displayUpdate(data); break;
        case 'displayCheckout': displayCheckout(data); break;
        case 'displayClose': displayClose(); break;
        case 'placeHud': placeHud(data); break;
    }
});
if (IN_GAME) nui('uiReady');

// ═══════════════════════════════════════════════════════════════
// BROWSER PREVIEW - open html/index.html?page=overview (only outside FiveM)
// ═══════════════════════════════════════════════════════════════
const Mock = (() => {
    const now = Date.now(), H = 3600000;
    const inv = (id, o) => Object.assign({ id, ref: 'PDM-' + id + 'K7QZ', senderType: 'personal', sender: 'Joe Doe', senderName: 'Joe Doe', recipientType: 'citizen', recipient: 'Nine Films', direction: 'received',
        reason: 'Car sale', items: [{ label: 'Car sale', amount: 5800, quantity: 1 }], subtotal: 5800, vatRate: 0.25, vat: 1450, total: 7250, lateFee: 0, amountPaid: 0, tip: 0, remaining: 7250,
        status: 'pending', createdAt: now - 16 * H, dueDate: now + 30 * H, tipsAllowed: true }, o);
    const received = [
        inv(91, {}),
        inv(90, { sender: 'Pillbox Medical Center', senderType: 'society', senderName: 'Sam Brooks', reason: 'Hospital admission', items: [{ label: 'Hospital admission', amount: 1200, quantity: 1 }], subtotal: 1200, vatRate: 0, vat: 0, total: 1200, remaining: 1200, createdAt: now - 22 * H }),
        inv(89, { sender: 'Pillbox Medical Center', senderType: 'society', senderName: 'Maya Reyes', reason: 'Hospital admission', subtotal: 1200, vat: 0, vatRate: 0, total: 1200, remaining: 1200, createdAt: now - 23 * H, status: 'overdue', dueDate: now - 4 * H, lateFee: 120 }),
        inv(88, { sender: 'Los Santos Customs', senderType: 'society', reason: 'Engine repair', subtotal: 740.74, vat: 59.26, vatRate: 0.08, total: 800, remaining: 800, createdAt: now - 26 * H }),
        inv(87, { sender: 'Los Santos Police Department', senderType: 'society', reason: 'Jumping a red light', total: 380, remaining: 0, amountPaid: 380, status: 'paid', paidAt: now - 20 * H, createdAt: now - 30 * H }),
        inv(86, { sender: 'Lucas Reed', reason: 'Gardening', total: 240, remaining: 0, amountPaid: 240, status: 'paid', createdAt: now - 31 * H }),
        inv(85, { sender: 'Los Santos Police Department', senderType: 'society', reason: 'High speed', total: 550, remaining: 550, amountPaid: 0, status: 'disputed', createdAt: now - 33 * H }),
    ];
    const sent = [
        inv(84, { direction: 'sent', recipient: 'Joe Doe', reason: 'Used Vehicle', total: 1, status: 'cancelled' }),
        inv(83, { direction: 'sent', recipient: 'Joe Doe', reason: 'Multiple Reasons', total: 107000, remaining: 107000 }),
        inv(82, { direction: 'sent', recipient: 'Mia Chen', reason: 'New Vehicle', total: 28000, status: 'paid' }),
        inv(81, { direction: 'sent', recipient: 'Noah Evans', reason: 'Custom paint', total: 2200, remaining: 2200 }),
        inv(80, { direction: 'sent', recipient: 'Mia Chen', reason: 'Down payment', total: 5000, remaining: 2500, amountPaid: 2500, status: 'partial' }),
    ];
    const ctx = {
        player: { name: 'Jordan Vale', job: 'Premium Deluxe Motorsport', grade: 'Manager', cash: 3975, bank: 48210, toCollect: 0 },
        society: { id: 'cardealer', label: 'Nine Films', short: 'NF', perms: Object.fromEntries(['view_received', 'view_sent', 'create', 'cancel', 'print', 'refund', 'disputes', 'templates_view', 'templates_create', 'templates_edit', 'templates_delete', 'overview', 'activity', 'permissions', 'pay', 'inspect', 'register'].map((k) => [k, true])),
            group: { id: 'manager', label: 'Manager' }, balance: 335445, vatRate: 0.25, allowCustom: true, dueDays: 3 },
        isAdmin: true,
        societies: [{ id: 'police', label: 'Los Santos Police Department', short: 'LSPD', billable: true }, { id: 'ambulance', label: 'Pillbox Medical Center', short: 'PMC', billable: true }, { id: 'mechanic', label: 'Los Santos Customs', short: 'LSC', billable: true }],
        settings: { version: '1.0.0', personalEnabled: true, personalCustom: true, personalSocietyRecipients: true, personalVat: 0, dueDays: 7, customDue: true, maxDueDays: 30, maxItems: 25, maxQuantity: 100, maxNote: 250,
            methods: { bank: true, cash: true }, allowPartial: true, minPartial: 50, payByReference: true, disputes: true, tips: [0, 10, 15, 20], maxTip: 50, print: true, pageSize: 7, banking: 'nayzeee-banking', adminDelete: true, adminClear: true, registerRadius: 1,
            registerProps: [{ model: 'prop_till_01', label: 'Till (classic)' }, { model: 'prop_till_02', label: 'Till (modern)' }, { model: 'prop_till_03', label: 'Till (compact)' }] },
    };
    const days = [5, 6, 0, 1, 2, 3, 4];
    const dash = { account: 'personal', due: 3, unpaid: 2000, paidWeek: 188050, receivedWeek: 270475, delta: 44,
        series: days.map((dow, i) => ({ key: `2026-10-${30 + i > 31 ? '0' + (i - 1) : 30 + i}`, dow, received: [42000, 28000, 21000, 46000, 61000, 38000, 34475][i], paid: [30000, 33000, 26000, 18000, 39000, 24000, 18050][i] })),
        weeks: Array.from({ length: 12 }, (_, i) => ({ key: new Date(now - (11 - i) * 7 * 24 * H - 6 * 24 * H).toISOString().slice(0, 10),
            received: [118000, 96000, 0, 142000, 131000, 88000, 0, 154000, 176000, 162000, 187600, 270475][i], paid: [90000, 74000, 41000, 0, 99000, 120000, 64000, 81000, 133000, 101000, 130500, 188050][i] })),
        alerts: [inv(89, { sender: 'Pillbox Medical Center', senderType: 'society', senderName: 'Maya Reyes', reason: 'Hospital admission', total: 1200, remaining: 1320, lateFee: 120, status: 'overdue', dueDate: now - 4 * H, ref: 'PMC-7KQ2MZ4P' }),
            inv(88, { sender: 'Los Santos Customs', senderType: 'society', senderName: 'Tyrone Banks', reason: 'Engine repair', total: 800, amountPaid: 300, remaining: 500, status: 'partial', dueDate: now + 18 * H, ref: 'LSC-A1B2C3D4' }),
            inv(79, { sender: 'Joe Doe', remaining: 850, total: 850, reason: 'Gardening', dueDate: now + 6 * 24 * H }), inv(77, { direction: 'sent', recipient: 'Mia Chen', reason: 'Down payment', total: 5000, amountPaid: 2500, remaining: 2500, status: 'partial', dueDate: now + 7 * 24 * H })],
        recent: [{ kind: 'payment_out', id: 1, ref: 'PDM-1A', name: 'Lucas Reed', amount: 240, at: now - 0.53 * H }, { kind: 'payment_out', id: 2, ref: 'PDM-2B', name: 'Mia Chen', amount: 300, at: now - 2 * H },
            { kind: 'payment_in', id: 3, ref: 'PDM-3C', name: 'Noah Evans', amount: 2200, at: now - 3 * H }, { kind: 'created', id: 4, ref: 'PDM-4D', name: 'Sofia Turner', amount: 640, at: now - 4 * H }, { kind: 'invoice_in', id: 5, ref: 'LSC-A1B2C3D4', name: 'Los Santos Customs', amount: 800, at: now - 27 * H }], balance: 48210 };
    const templates = [
        { id: 1, name: 'Vehicle Sales', icon: 'car', color: 'blue', items: [{ id: 'a', label: 'Trade-in Adjustment', amount: 8500 }, { id: 'b', label: 'Performance Package', amount: 12000 }, { id: 'c', label: 'Used Vehicle', amount: 32000 }, { id: 'd', label: 'New Vehicle', amount: 85000 }] },
        { id: 2, name: 'Paperwork & Fees', icon: 'file', color: 'teal', items: [{ id: 'e', label: 'Registration', amount: 1500 }] },
        { id: 3, name: 'Extras & After-sales', icon: 'sparkle', color: 'violet', items: [{ id: 'f', label: 'Custom Paint', amount: 2200 }] },
        { id: 'g1', name: 'Services', icon: 'briefcase', color: 'gray', items: [{ id: 'i1', label: 'Labour (1 hour)', amount: 150 }], global: true },
    ];
    const perms = { society: 'Nine Films', sections: [
        { id: 'invoices', label: 'Invoices', perms: [{ key: 'view_received', label: 'View received invoices' }, { key: 'view_sent', label: 'View sent invoices' }, { key: 'create', label: 'Create invoices' }, { key: 'cancel', label: 'Cancel invoices' }, { key: 'print', label: 'Print invoices' }] },
        { id: 'templates', label: 'Templates', perms: [{ key: 'templates_view', label: 'View templates' }, { key: 'templates_create', label: 'Create templates' }, { key: 'templates_edit', label: 'Edit templates' }, { key: 'templates_delete', label: 'Delete templates' }] },
        { id: 'management', label: 'Management', perms: [{ key: 'overview', label: 'View overview & balance' }, { key: 'activity', label: 'View activity logs' }, { key: 'permissions', label: 'Manage permissions' }, { key: 'pay', label: 'Pay invoices' }, { key: 'inspect', label: 'Inspect players & societies' }] }],
        groups: [{ id: 'manager', label: 'Manager', access: 'full', icon: 'shield', color: 'blue', perms: ctx.society.perms, builtin: true }, { id: 'finance', label: 'Finance', access: 'high', icon: 'chevrons', color: 'cyan', perms: { view_received: true, pay: true }, builtin: true },
            { id: 'sales', label: 'Business Sales', access: 'normal', icon: 'chevron', color: 'violet', perms: { create: true }, builtin: true }, { id: 'showroom', label: 'Showroom Sales', access: 'limited', icon: 'users', color: 'amber', perms: { register: true } }],
        members: [{ identifier: 'char1:abc', name: 'Joe Doe1g', grade: 2, gradeLabel: 'Salesman', online: true, group: 'sales' }, { identifier: 'char1:def', name: 'Mia Chen', grade: 3, gradeLabel: 'Manager', online: false, group: 'manager' }] };
    const ok = (data) => ({ ok: true, data });
    const page = (rows, p) => ({ rows: rows.slice(((p.page || 1) - 1) * 7, (p.page || 1) * 7), total: rows.length, page: p.page || 1, pageSize: 7, counts: { pending: 5, partial: 1, overdue: 1, disputed: 1, paid: 23, cancelled: 2 } });
    const detail = (id) => { const i = [...received, ...sent, ...dash.alerts].find((x) => x.id === id) || received[0]; return Object.assign({}, i, { payOptions: isOpen(i) && i.direction === 'received' ? { bank: true, cash: true } : null, canCancel: i.direction === 'sent' && isOpen(i), canPrint: true, canDispute: i.direction === 'received' && isOpen(i), payments: i.amountPaid ? [{ payer: 'Mia Chen', amount: i.amountPaid, tip: 0, method: 'bank', kind: 'payment', createdAt: now - 3 * H }] : [] }); };
    const rpc = {
        getContext: () => ok(ctx), getNearby: () => ok([{ id: 12, name: 'Joe Doe1g', distance: 1.8 }, { id: 31, name: 'Mia Chen', distance: 4.2 }]),
        'dashboard:get': () => ok(dash), 'invoices:list': (p) => ok(page(p.box === 'sent' ? sent : received, p)), 'invoices:get': (p) => ok(detail(p.id)), 'invoices:lookup': () => ok(detail(91)),
        'templates:list': () => ok({ templates, canCreate: true, canEdit: true, canDelete: true }),
        'activity:list': () => ok({ rows: [{ timestamp: now - 26 * H, player: 'Nine Films', action: 'template_created', data: { name: 'Extras & After-sales' } }, { timestamp: now - 26 * H, player: 'Nine Films', action: 'item_added', data: { name: "Car's Plates", template: 'Paperwork & Fees' } },
            { timestamp: now - 27 * H, player: 'Nine Films', action: 'invoice_paid', data: { target: 'Joe Doe1g', amount: 107000 } }, { timestamp: now - 28 * H, player: 'Jordan Vale', action: 'invoice_created', data: { target: 'Mia Chen', ref: 'PDM-K2', amount: 5000 } }], total: 10, page: 1, pageSize: 7 }),
        'perms:get': () => ok(perms), 'inspect:search': () => ok([{ id: 'I6NH41BE', name: 'Joe Doe1g', online: true, serverId: 12 }]),
        'inspect:profile': (p) => ok(Object.assign(page([...received.slice(0, 3).map((r) => Object.assign({}, r, { direction: 'received' })), ...sent.slice(1, 3)], p), { subject: { type: 'citizen', id: 'I6NH41BE', name: 'Joe Doe1g', identifier: 'I6NH41BE' }, stats: { total: 36, outstanding: 13100, paid: 122680 }, canClear: true })),
        'admin:registers': () => ok([{ id: 'r1', label: 'PDM Front Desk', society: 'cardealer', societyLabel: 'Nine Films', coords: { x: -56.2, y: -1097.4, z: 26.4 }, radius: 2, source: 'config' },
            { id: 'r2', label: 'Burgershot Counter 2', society: 'burgershot', societyLabel: 'Burgershot', coords: { x: 196.12, y: -852.3, z: 31.02 }, radius: 1, heading: 160, model: 'prop_till_01', source: 'db' }]),
        'invoices:pay': () => ok({ charged: 100, status: 'paid', method: 'bank' }), 'invoices:payMany': () => ok({ paid: 2, failed: [], total: 2400 }), 'invoices:create': () => ok({ ref: 'PDM-NEW1', total: 100, recipient: 'Joe' }),
    };
    return {
        nui: async (ev, data) => (ev === 'rpc' ? (rpc[data.name] || (() => ok(true)))(data.payload || {}) : 'ok'),
        boot: () => {
            document.body.style.background = 'radial-gradient(1100px 640px at 50% -8%,#1b2224 0%,transparent 62%),#22272b';
            const q = new URLSearchParams(location.search);
            if (q.get('view') === 'paper') { showPaper(detail(91)); return; }
            if (q.get('view') === 'place') { placeHud({ keys: [{ k: 'E', l: 'Place' }, { k: 'H', l: 'Hold in hand' }, { k: 'G', l: 'Cancel' }, { k: 'Scroll', l: 'Rotate', wide: true }] }); return; }
            if (q.get('view') === 'display') { displayOpen({ society: 'Burgershot', register: 'Front Counter', employee: 'Jordan Vale' }); displayCheckout({ invoice: Object.assign(inv(1, {}), { items: [{ label: 'Bleeder Burger', amount: 8.99, quantity: 2 }], subtotal: 17.98, vatRate: 0.08, vat: 1.44, total: 19.42 }) }); return; }
            if (q.get('view') === 'pos') { openPos({ register: { id: 'r1', label: 'Burgershot Counter', societyLabel: 'Burgershot' }, vatRate: 0.08, menu: templates.slice(0, 3), nearby: [{ id: 3, name: 'Rafael Salas', distance: 1.2 }] }); return; }
            S.account = q.get('account') || 'personal';
            open({ ctx, page: q.get('page') || 'overview' });
            if (q.get('modal') === 'create') createInvoice();
            if (q.get('modal') === 'ref') payByReference('PDM-91K7QZ');
            if (q.get('modal') === 'tpl') templateModal(null);
            if (q.get('rail')) openRail(+q.get('rail'));
        },
    };
})();
if (!IN_GAME) document.addEventListener('DOMContentLoaded', () => Mock.boot());
