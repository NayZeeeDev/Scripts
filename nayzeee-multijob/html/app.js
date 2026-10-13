/* ═══════════════════════════════════════════════════════════════════════════
   NAYZEEE MULTIJOB - JavaScript v1.0.0
   ═══════════════════════════════════════════════════════════════════════════ */

function getResourceName() {
    return window.GetParentResourceName ? window.GetParentResourceName() : 'nayzeee-multijob';
}

function post(endpoint, body) {
    return fetch(`https://${getResourceName()}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body || {})
    });
}

// Same as post() but resolves to the parsed reply ({} on any failure)
function postJson(endpoint, body) {
    return post(endpoint, body).then(res => res.json()).catch(() => ({}));
}

function closeMenu()        { post('close'); }
function refreshData()      { post('refresh'); }
function refreshAdminData() { post('adminRefresh'); }

// ═══════════════════════════════════════════════════════════════════════════
// DATA
// ═══════════════════════════════════════════════════════════════════════════

let menuData = {
    jobs: [], favorites: {}, stats: { jobs: {} }, schedules: [], shifts: [],
    categories: {}, isOnDuty: false, afkPaused: false, isUnemployed: false, dutyTime: 0,
    currentJob: 'unemployed', currentGrade: 0, defaultJob: 'unemployed', maxJobs: 4, locale: {}
};
let adminData = {};
let currentCategory = null;
let currentLeaderboard = 'total_hours';
let lastLeaderboards = {};
let team = null;          // Team tab data for the selected job
let teamJob = null;       // job the Team tab is showing
let hirePick = null;      // server id picked in the hire modal
let playerScope = 'online';
let searchTimer = null;
let searchResults = [];
let dutyInterval = null;
let clockInterval = null;

const PANES = {
    jobs:        ['My jobs', "Every job on your record. Switch between them, clock in and quit the ones you're done with."],
    duty:        ['Duty', 'Clock in to start earning. Your shift time and history are tracked here.'],
    stats:       ['Statistics', 'Everything you have worked and everything it has paid.'],
    schedule:    ['Schedule', 'Set a time and the job switches for you automatically.'],
    leaderboard: ['Rankings', 'How you stack up against everyone else in the city.'],
    team:        ['Team', 'Your staff, who is working and what they have put in. Hire, promote and let people go.']
};

const ADMIN_PANES = {
    'admin-players':   ['Players', 'Everyone online right now. Open a player to add or strip jobs.'],
    'admin-bulk':      ['Bulk actions', 'Apply one job change to a whole group of players at once.'],
    'admin-logs':      ['Action log', 'A running record of every job switch, duty change and staff action.'],
    'admin-analytics': ['Analytics', 'Server-wide employment figures pulled from the job database.']
};

// Which Config.AdminPermissions key unlocks each admin tab
const ADMIN_TAB_PERM = {
    'admin-players': 'viewPlayers',
    'admin-bulk': 'bulkOperations',
    'admin-logs': 'viewLogs',
    'admin-analytics': 'viewAnalytics'
};

function isDefaultJob(name) { return name === menuData.defaultJob; }

// ═══════════════════════════════════════════════════════════════════════════
// THEME — driven by Config.UI
// ═══════════════════════════════════════════════════════════════════════════

function hexToRgb(hex) {
    const h = String(hex || '').replace('#', '');
    if (h.length !== 6) return null;
    return {
        r: parseInt(h.slice(0, 2), 16),
        g: parseInt(h.slice(2, 4), 16),
        b: parseInt(h.slice(4, 6), 16)
    };
}

function shade(hex, amount) {
    const c = hexToRgb(hex);
    if (!c) return hex;
    const f = v => Math.max(0, Math.min(255, Math.round(amount > 0
        ? v + (255 - v) * amount
        : v * (1 + amount))));
    return '#' + [f(c.r), f(c.g), f(c.b)].map(v => v.toString(16).padStart(2, '0')).join('');
}

function alpha(hex, a) {
    const c = hexToRgb(hex);
    if (!c) return hex;
    return `rgba(${c.r},${c.g},${c.b},${a})`;
}

function readable(hex) {
    const c = hexToRgb(hex);
    if (!c) return '#00201d';
    const lum = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) / 255;
    return lum > 0.6 ? '#0a0a0a' : '#ffffff';
}

function applyTheme(ui) {
    if (!ui) return;
    const root = document.documentElement.style;

    if (ui.accent) {
        root.setProperty('--teal', ui.accent);
        root.setProperty('--teal-hi', ui.accentHi || shade(ui.accent, 0.22));
        root.setProperty('--teal-lo', ui.accentLo || shade(ui.accent, -0.3));
        root.setProperty('--teal-wash', alpha(ui.accent, 0.11));
        root.setProperty('--teal-edge', alpha(ui.accent, 0.34));
        root.setProperty('--on-accent', readable(ui.accent));
    }
    if (ui.danger) {
        root.setProperty('--red', ui.danger);
        root.setProperty('--red-lo', ui.dangerLo || shade(ui.danger, -0.3));
        root.setProperty('--red-wash', alpha(ui.danger, 0.11));
        root.setProperty('--red-edge', alpha(ui.danger, 0.34));
    }
    if (ui.background) {
        root.setProperty('--void', ui.background);
        root.setProperty('--base', shade(ui.background, 0.03));
        root.setProperty('--panel', shade(ui.background, 0.06));
        root.setProperty('--raise', shade(ui.background, 0.1));
        root.setProperty('--raise-2', shade(ui.background, 0.14));
        root.setProperty('--inset', shade(ui.background, 0.02));
    }
    const px = v => (typeof v === 'number' ? v + 'px' : v);
    if (ui.width)   root.setProperty('--win-w', px(ui.width));
    if (ui.height)  root.setProperty('--win-h', px(ui.height));
    if (ui.sidebar) root.setProperty('--rail', px(ui.sidebar));

    if (ui.font) {
        root.setProperty('--font', ui.font);
        document.body.style.fontFamily = `'${ui.font}', 'Lexend', system-ui, sans-serif`;
    }
    document.querySelectorAll('.shell').forEach(s => s.classList.toggle('no-grain', ui.grain === false));
    document.querySelectorAll('.main').forEach(m => m.classList.toggle('no-watermark', ui.watermark === false));

    setText('barSub', ui.subtitle);
    document.querySelectorAll('#jobMenu .title-txt').forEach(node => {
        if (ui.title) node.textContent = ui.title;
    });
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

function el(id) { return document.getElementById(id); }
function setText(id, value) { const n = el(id); if (n && value !== undefined && value !== null) n.textContent = value; }
function esc(str) {
    return String(str === undefined || str === null ? '' : str)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function formatNumber(num) {
    num = Number(num) || 0;
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toLocaleString();
}

function formatDuration(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0));
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

function initials(name) {
    const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return '--';
    if (parts.length === 1) return parts[0].slice(0, 2);
    return (parts[0][0] + parts[parts.length - 1][0]);
}

function emptyState(icon, title, copy) {
    return `<div class="empty"><i class="${icon}"></i><b>${esc(title)}</b><span>${esc(copy)}</span></div>`;
}

const ICON = {
    switchTo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4"/><path d="M10 16l4-4-4-4M14 12H4"/></svg>',
    quit:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M10 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4"/><path d="M16 16l4-4-4-4M20 12H10"/></svg>',
    trash:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M5 7h14M10 7V5h4v2M7 7l1 13h8l1-13"/></svg>',
    star:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><path d="M12 3.6l2.6 5.2 5.8.9-4.2 4.1 1 5.7L12 16.8l-5.2 2.7 1-5.7-4.2-4.1 5.8-.9z"/></svg>',
    power:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 3.5v8"/><path d="M7.1 6.6a7 7 0 1 0 9.8 0"/></svg>',
    up:       '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M6 14l6-6 6 6"/></svg>',
    down:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M6 10l6 6 6-6"/></svg>',
    letGo:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16.5 9.5l4 4M20.5 9.5l-4 4"/></svg>'
};

function formatDistance(m) {
    m = Math.max(0, Math.round(Number(m) || 0));
    return m >= 1000 ? (m / 1000).toFixed(1) + ' km' : m + ' m';
}

// ═══════════════════════════════════════════════════════════════════════════
// TOASTS
// ═══════════════════════════════════════════════════════════════════════════

const TOAST_ICON = {
    success: '<path d="M4 12.5 9 17.5 20 6.5"/>',
    error:   '<path d="M12 8v5M12 16.5v.01"/><circle cx="12" cy="12" r="9"/>',
    info:    '<path d="M12 11v5M12 7.5v.01"/><circle cx="12" cy="12" r="9"/>'
};

function toast(title, message, type) {
    const wrap = el('toastWrap');
    if (!wrap) return;

    const node = document.createElement('div');
    node.className = 'toast' + (type === 'error' ? ' err' : '');
    node.innerHTML = `
        <div class="ti"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${TOAST_ICON[type] || TOAST_ICON.info}</svg></div>
        <div><b>${esc(title)}</b><p>${esc(message)}</p></div>`;

    wrap.appendChild(node);
    setTimeout(() => node.remove(), 4000);
}

// ═══════════════════════════════════════════════════════════════════════════
// CONFIRM MODAL
// ═══════════════════════════════════════════════════════════════════════════

function showNuiConfirm(message, onConfirm, opts) {
    opts = opts || {};
    const existing = el('confirmOverlay');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'confirmOverlay';
    overlay.className = 'overlay active';
    overlay.innerHTML = `
        <div class="modal">
            <div class="modal-b">
                <div class="warn"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/></svg></div>
                <div><h4 style="font-size:13.5px;font-weight:600;color:var(--white);margin-bottom:5px;letter-spacing:-.012em">${esc(opts.title || 'Are you sure?')}</h4><p>${esc(message)}</p></div>
            </div>
            <div class="modal-f">
                <button class="btn-line" id="confirmCancel">${esc(opts.cancel || 'Cancel')}</button>
                <button class="btn-red" id="confirmOk">${esc(opts.confirm || 'Confirm')}</button>
            </div>
        </div>`;

    document.body.appendChild(overlay);
    el('confirmCancel').onclick = () => overlay.remove();
    el('confirmOk').onclick = () => { overlay.remove(); if (onConfirm) onConfirm(); };
}

function showNuiAlert(message, title) {
    const existing = el('confirmOverlay');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'confirmOverlay';
    overlay.className = 'overlay active';
    overlay.innerHTML = `
        <div class="modal">
            <div class="modal-b">
                <div class="warn"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 8v5M12 16.5v.01"/><circle cx="12" cy="12" r="9"/></svg></div>
                <div><h4 style="font-size:13.5px;font-weight:600;color:var(--white);margin-bottom:5px">${esc(title || 'Heads up')}</h4><p>${esc(message)}</p></div>
            </div>
            <div class="modal-f"><button class="btn-line" id="confirmCancel">Got it</button></div>
        </div>`;

    document.body.appendChild(overlay);
    el('confirmCancel').onclick = () => overlay.remove();
}

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGE HANDLER
// ═══════════════════════════════════════════════════════════════════════════

function readMenuData(data, base) {
    base = base || {};
    return Object.assign({}, base, {
        jobs: data.jobs || [],
        favorites: data.favorites || {},
        stats: data.stats || { jobs: {} },
        schedules: data.schedules || [],
        shifts: data.shifts || [],
        categories: data.categories || base.categories || {},
        isOnDuty: data.isOnDuty === true,
        afkPaused: data.afkPaused === true,
        isUnemployed: data.isUnemployed === true,
        dutyTime: data.isOnDuty === true ? (Number(data.dutyTime) || 0) : 0,
        currentJob: data.currentJob || data.defaultJob || base.defaultJob || 'unemployed',
        currentGrade: data.currentGrade || 0,
        defaultJob: data.defaultJob || base.defaultJob || 'unemployed',
        maxJobs: data.maxJobs || base.maxJobs || 4,
        playerName: data.playerName || base.playerName || '',
        scheduleEnabled: data.scheduleEnabled !== false,
        scheduleCanCreate: data.scheduleCanCreate !== false,
        maxSchedules: data.maxSchedules || base.maxSchedules || 5,
        leaderboards: data.leaderboards !== false,
        leaderboardCategories: data.leaderboardCategories || base.leaderboardCategories || null,
        bossJobs: data.bossJobs || [],
        dutyPoint: data.dutyPoint || { required: false },
        locale: data.locale || base.locale || {}
    });
}

window.addEventListener('message', (event) => {
    const { action, data, time } = event.data || {};

    switch (action) {
        case 'openMenu':
            if (!data) break;
            menuData = readMenuData(data);
            applyTheme(data.ui);
            openMenu();
            break;

        case 'openAdmin':
            if (!data) break;
            adminData = data;
            applyTheme(data.ui);
            openAdmin();
            break;

        case 'refreshAdmin':
            if (!data) break;
            adminData = Object.assign({}, adminData, data);
            renderAdmin();
            break;

        case 'close':
            closeAll();
            break;

        case 'updateDutyTime':
            if (typeof time === 'number') {
                menuData.dutyTime = time;
                updateDutyTimer(time);
            }
            break;

        case 'updateDutyStatus':
            if (!data) break;
            menuData.isOnDuty = data.isOnDuty === true;
            menuData.afkPaused = data.afkPaused === true;
            menuData.dutyTime = menuData.isOnDuty ? (Number(data.dutyTime) || 0) : 0;
            updateDutyUI();
            updateDutyTimer(menuData.dutyTime);
            break;

        case 'refreshData':
            if (!data) break;
            menuData = readMenuData(data, menuData);
            renderMenu();
            break;

        case 'dutyPoint':
            if (!data) break;
            menuData.dutyPoint = data;
            updateDutyUI();
            break;

        case 'teamChanged':
            if (el('tab-team')?.classList.contains('on')) loadTeam();
            break;

        case 'notify':
            if (data) toast(data.title || 'Job', data.message || '', data.type);
            break;
    }
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;

    const overlay = document.querySelector('.overlay.active');
    if (overlay) {
        if (overlay.id === 'confirmOverlay') overlay.remove();
        else overlay.classList.remove('active');
        return;
    }
    closeMenu();
});

// ═══════════════════════════════════════════════════════════════════════════
// OPEN / CLOSE
// ═══════════════════════════════════════════════════════════════════════════

function openMenu() {
    el('jobMenu').classList.add('active');
    el('adminPanel').classList.remove('active');
    renderMenu();
    startDutyTimer();
    startClock();
}

function openAdmin() {
    el('adminPanel').classList.add('active');
    el('jobMenu').classList.remove('active');
    renderAdmin();
}

function closeAll() {
    el('jobMenu').classList.remove('active');
    el('adminPanel').classList.remove('active');
    document.querySelectorAll('.overlay').forEach(o => {
        if (o.id === 'confirmOverlay') o.remove();
        else o.classList.remove('active');
    });
    stopDutyTimer();
    stopClock();
}

// ═══════════════════════════════════════════════════════════════════════════
// CLOCK
// ═══════════════════════════════════════════════════════════════════════════

function tickClock() {
    const now = new Date();
    setText('headClock', String(now.getHours()).padStart(2, '0') + ':' + String(now.getMinutes()).padStart(2, '0'));
    setText('headDate', now.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' }));
}

function startClock() {
    stopClock();
    tickClock();
    clockInterval = setInterval(tickClock, 15000);
}

function stopClock() {
    if (clockInterval) { clearInterval(clockInterval); clockInterval = null; }
}

// ═══════════════════════════════════════════════════════════════════════════
// RENDER — MENU
// ═══════════════════════════════════════════════════════════════════════════

function renderMenu() {
    renderIdentity();
    renderTotals();
    updateDutyUI();
    updateDutyTimer(menuData.dutyTime || 0);
    renderCategories();
    renderJobs();
    renderStats();
    renderShifts();
    renderSchedules();
    setupNav();
    setupSearch();
    toggleOptionalTabs();
    setupLeaderboardTabs();
}

function toggleOptionalTabs() {
    const sched = document.querySelector('#jobMenu .nav[data-tab="schedule"]');
    const lb = document.querySelector('#jobMenu .nav[data-tab="leaderboard"]');
    if (sched) sched.style.display = menuData.scheduleEnabled === false ? 'none' : '';
    if (lb) lb.style.display = menuData.leaderboards === false ? 'none' : '';

    const newBtn = el('newScheduleBtn');
    if (newBtn) newBtn.style.display = menuData.scheduleCanCreate === false ? 'none' : '';

    const isBoss = (menuData.bossJobs || []).length > 0;
    const teamNav = document.querySelector('#jobMenu .nav[data-tab="team"]');
    if (teamNav) teamNav.style.display = isBoss ? '' : 'none';
    const teamGrp = el('grpTeam');
    if (teamGrp) teamGrp.style.display = isBoss ? '' : 'none';
    setupTeamJobs();

    // a hidden tab can't stay selected
    const active = document.querySelector('#jobMenu .nav.on');
    if (active && active.style.display === 'none') {
        document.querySelector('#jobMenu .nav[data-tab="jobs"]')?.click();
    }
}

function currentJobEntry() {
    return menuData.jobs.find(j => j.name === menuData.currentJob);
}

function renderIdentity() {
    const job = currentJobEntry();
    const label = job?.label || menuData.currentJob || 'Unemployed';
    const grade = job?.gradeLabel || ('Grade ' + (menuData.currentGrade || 0));

    setText('whoName', menuData.playerName || label);
    setText('whoGrade', menuData.playerName ? label : grade);
    setText('whoAvatar', initials(menuData.playerName || label));

    const barStatus = el('barStatus');
    if (barStatus) barStatus.innerHTML = `Working as <b id="barJob">${esc(label)}</b> · ${esc(grade)}`;
}

function realJobs() {
    return menuData.jobs.filter(j => !isDefaultJob(j.name) && !j.untracked);
}

function renderTotals() {
    const held = realJobs().length;
    setText('jobCount', held);
    setText('navJobCount', held);
    setText('jobSlots', 'of ' + (menuData.maxJobs || 4));
    setText('navScheduleCount', (menuData.schedules || []).length);

    let hours = 0, earnings = 0;
    Object.values(menuData.stats?.jobs || {}).forEach(j => {
        hours += (j.totalHours || 0);
        earnings += (j.totalEarnings || 0);
    });

    setText('totalHours', Math.floor(hours) + 'h');
    setText('totalEarned', '$' + formatNumber(earnings));
}

function renderCategories() {
    const container = el('categoryFilters');
    if (!container) return;

    if (currentCategory && !(menuData.categories || {})[currentCategory]) currentCategory = null;

    let html = `<button class="chip-btn ${currentCategory ? '' : 'on'}" data-category="all"><i class="fa-solid fa-layer-group"></i>All</button>`;

    for (const [id, cat] of Object.entries(menuData.categories || {})) {
        const tint = cat.color ? ` style="color:${esc(cat.color)}"` : '';
        html += `<button class="chip-btn ${currentCategory === id ? 'on' : ''}" data-category="${esc(id)}">
            <i class="${esc(cat.icon || 'fa-solid fa-briefcase')}"${tint}></i>${esc(cat.label || id)}
        </button>`;
    }

    container.innerHTML = html;

    container.querySelectorAll('.chip-btn').forEach(btn => {
        btn.onclick = function () {
            container.querySelectorAll('.chip-btn').forEach(b => b.classList.remove('on'));
            this.classList.add('on');
            currentCategory = this.dataset.category === 'all' ? null : this.dataset.category;
            renderJobs();
        };
    });
}

function getJobCategory(jobName) {
    for (const [id, cat] of Object.entries(menuData.categories || {})) {
        if (cat.jobs && cat.jobs.includes(jobName)) return id;
    }
    return 'civilian';
}

function visibleJobs() {
    let jobs = [...menuData.jobs];

    if (currentCategory && menuData.categories[currentCategory]) {
        const catJobs = menuData.categories[currentCategory].jobs || [];
        jobs = jobs.filter(j => catJobs.includes(j.name));
    }

    const search = (el('jobSearch')?.value || '').toLowerCase();
    if (search) {
        jobs = jobs.filter(j =>
            (j.label || '').toLowerCase().includes(search) ||
            (j.name || '').toLowerCase().includes(search)
        );
    }

    // active job first, then favourites, then alphabetical
    const fav = j => (j.favorite ? 1 : 0);
    jobs.sort((a, b) => {
        if (a.name === menuData.currentJob) return -1;
        if (b.name === menuData.currentJob) return 1;
        if (fav(a) !== fav(b)) return fav(b) - fav(a);
        return (a.label || a.name).localeCompare(b.label || b.name);
    });

    return jobs;
}

function renderJobs() {
    const container = el('jobsGrid');
    if (!container) return;

    const jobs = visibleJobs();
    const search = el('jobSearch')?.value || '';

    if (!jobs.length) {
        container.innerHTML = emptyState('fa-solid fa-briefcase', 'No jobs here',
            search ? 'Nothing matches that search. Try a different word.' : 'Jobs you take on will show up in this list.');
        return;
    }

    container.innerHTML = jobs.map(renderJobRow).join('');
    setText('jobsSubhead', jobs.length + (jobs.length === 1 ? ' job on record' : ' jobs on record'));
}

// Job names only ever travel through data-* attributes, never inline JS,
// so a job called  x');doSomething()//  is just text.
function renderJobRow(job) {
    const L = menuData.locale || {};
    const isActive = job.name === menuData.currentJob;
    const isDefault = isDefaultJob(job.name);
    const cat = menuData.categories[getJobCategory(job.name)];
    const icon = cat?.icon || 'fa-solid fa-briefcase';
    const removable = job.removeable === true && !job.untracked && !isDefault;
    const canQuit = isActive && !isDefault;
    const canRemove = removable && !isActive;

    let actions = '';
    if (!isDefault && !job.untracked) {
        const favTitle = job.favorite ? (L.unfavorite || 'Remove from Favorites') : (L.favorite || 'Add to Favorites');
        actions += `<button class="ico fav ${job.favorite ? 'on' : ''}" title="${esc(favTitle)}" data-act="fav">${ICON.star}</button>`;
    }
    if (!isActive) {
        actions += `<button class="ico" title="${esc(L.switch_job || 'Switch to this job')}" data-act="switch">${ICON.switchTo}</button>`;
    }
    if (canQuit) {
        actions += `<button class="ico danger" title="Quit this job" data-act="quit">${ICON.quit}</button>`;
    }
    if (canRemove) {
        actions += `<button class="ico danger" title="${esc(L.remove_job || 'Remove from record')}" data-act="remove">${ICON.trash}</button>`;
    }

    const pay = job.salary ? `$${formatNumber(job.salary)}/pay` : 'No salary';
    const grade = job.gradeLabel || ('Grade ' + (job.grade || 0));

    return `
        <div class="row ${isActive ? 'on' : 'clickable'}" data-job="${esc(job.name)}" ${isActive ? '' : 'data-act="switch"'}>
            <div class="av cat"><i class="${esc(icon)}"></i></div>
            <div class="row-txt">
                <b>${esc(job.label || job.name)}</b>
                <span>${esc(grade)} · ${esc(pay)}</span>
            </div>
            <div class="row-end">
                ${job.untracked ? '<span class="tag off" title="Your job list is full, so this one is not saved">Not saved</span>' : ''}
                ${isActive ? '<span class="tag live">Active</span>' : ''}
                ${actions}
            </div>
        </div>`;
}

function onJobsClick(e) {
    const target = e.target.closest('[data-act]');
    const row = e.target.closest('.row[data-job]');
    if (!target || !row) return;

    const job = row.dataset.job;
    switch (target.dataset.act) {
        case 'switch': switchJob(job); break;
        case 'quit':   quitJob(job); break;
        case 'remove': removeJob(job); break;
        case 'fav':    post('toggleFavorite', { job: job }); break;
    }
}

function renderStats() {
    let hours = 0, earnings = 0, sessions = 0;
    const jobStats = menuData.stats?.jobs || {};

    Object.values(jobStats).forEach(j => {
        hours += (j.totalHours || 0);
        earnings += (j.totalEarnings || 0);
        sessions += (j.sessions || 0);
    });

    setText('statTotalHours', hours.toFixed(1));
    setText('statTotalEarnings', '$' + formatNumber(earnings));
    setText('statJobsHeld', realJobs().length);
    setText('statTotalSessions', sessions);

    const container = el('jobStatsList');
    if (!container) return;

    const sorted = Object.entries(jobStats).sort((a, b) => (b[1].totalHours || 0) - (a[1].totalHours || 0));

    if (!sorted.length) {
        container.innerHTML = emptyState('fa-solid fa-chart-simple', 'Nothing tracked yet',
            'Clock in to a job and your hours and earnings start recording here.');
        return;
    }

    const peak = Math.max(...sorted.map(([, s]) => s.totalHours || 0), 1);

    container.innerHTML = sorted.map(([name, stat]) => {
        const job = menuData.jobs.find(j => j.name === name);
        const pct = Math.max(3, Math.round(((stat.totalHours || 0) / peak) * 100));
        return `
            <div class="bar-row">
                <div class="bar-top">
                    <b>${esc(job?.label || name)}</b>
                    <span>${(stat.totalHours || 0).toFixed(1)}h · <em>$${formatNumber(stat.totalEarnings || 0)}</em></span>
                </div>
                <div class="meter"><i style="width:${pct}%"></i></div>
            </div>`;
    }).join('');
}

function renderShifts() {
    const container = el('shiftHistory');
    if (!container) return;

    const shifts = menuData.shifts || [];

    if (!shifts.length) {
        container.innerHTML = emptyState('fa-solid fa-clock-rotate-left', 'No shifts yet',
            'Once you clock out of a job, the shift shows up here with what it paid.');
        return;
    }

    let liveShown = false;
    container.innerHTML = shifts.map(shift => {
        let when = '';
        try { if (shift.clockIn) when = new Date(shift.clockIn).toLocaleString(); } catch (e) {}

        // only the newest open shift is the one running right now
        const live = !shift.clockOut && !liveShown && menuData.isOnDuty;
        if (live) liveShown = true;
        const duration = live ? menuData.dutyTime : shift.duration;

        return `
            <div class="row">
                <div class="av cat"><i class="fa-solid fa-briefcase"></i></div>
                <div class="row-txt">
                    <b>${esc(shift.jobLabel || shift.job)}</b>
                    <span>${esc(when || 'Unknown start')}</span>
                </div>
                <div class="row-end">
                    <span class="row-val">${esc(formatDuration(duration || 0))}</span>
                    <span class="row-val teal">$${formatNumber(shift.earnings || 0)}</span>
                    ${live ? '<span class="tag live">Active</span>' : ''}
                </div>
            </div>`;
    }).join('');
}

const DAY_NAMES = ['', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function scheduleDays(s) {
    const raw = Array.isArray(s.days) ? s.days : Object.keys(s.days || {}).filter(d => s.days[d]);
    return raw.map(d => parseInt(d, 10)).filter(d => d >= 1 && d <= 7).sort((a, b) => a - b);
}

function renderSchedules() {
    const container = el('schedulesList');
    if (!container) return;

    const schedules = menuData.schedules || [];
    setText('navScheduleCount', schedules.length);

    if (!schedules.length) {
        container.innerHTML = emptyState('fa-solid fa-calendar-days', 'No schedules set',
            'Add one and the job switches for you at that time on the days you pick.');
        return;
    }

    container.innerHTML = schedules.map(s => {
        const days = scheduleDays(s).map(d => DAY_NAMES[d]);
        const time = String(s.hour || 0).padStart(2, '0') + ':' + String(s.minute || 0).padStart(2, '0');
        const on = s.enabled !== false;

        return `
            <div class="row ${on ? '' : 'paused'}" data-sid="${esc(s.id)}">
                <div class="av cat">${esc(time.split(':')[0])}</div>
                <div class="row-txt">
                    <b>${esc(s.jobLabel || s.job)}</b>
                    <span>${esc(time)} · ${esc(days.join(', ') || 'No days selected')}${on ? '' : ' · Paused'}</span>
                </div>
                <div class="row-end">
                    <button class="ico ${on ? 'lit' : ''}" title="${on ? 'Pause schedule' : 'Resume schedule'}" data-sact="toggle">${ICON.power}</button>
                    <button class="ico danger" title="Delete schedule" data-sact="delete">${ICON.trash}</button>
                </div>
            </div>`;
    }).join('');
}

function onSchedulesClick(e) {
    const btn = e.target.closest('[data-sact]');
    const row = e.target.closest('.row[data-sid]');
    if (!btn || !row) return;

    const id = parseInt(row.dataset.sid, 10);
    if (btn.dataset.sact === 'toggle') postJson('toggleSchedule', { id: id });
    if (btn.dataset.sact === 'delete') deleteSchedule(id);
}

function populateScheduleJobDropdown() {
    const select = el('scheduleJob');
    if (!select) return;

    const jobs = menuData.jobs.filter(j => !j.untracked && !isDefaultJob(j.name));
    const fallback = menuData.jobs.find(j => isDefaultJob(j.name));

    if (!jobs.length && !fallback) {
        select.innerHTML = '<option value="">No jobs available</option>';
        return;
    }

    select.innerHTML = jobs.map(j => `<option value="${esc(j.name)}">${esc(j.label || j.name)}</option>`).join('')
        + (fallback ? `<option value="${esc(fallback.name)}">${esc(fallback.label || fallback.name)} (off work)</option>` : '');
}

// ═══════════════════════════════════════════════════════════════════════════
// DUTY
// ═══════════════════════════════════════════════════════════════════════════

// Away from a required clock-in point the button marks it on the map instead
function pointBlocks() {
    const point = menuData.dutyPoint || {};
    if (!point.required || point.inside) return false;
    return menuData.isOnDuty ? point.outRequired === true : true;
}

function toggleDuty() {
    if (isDefaultJob(menuData.currentJob)) return;
    if (pointBlocks()) { post('dutyWaypoint'); return; }
    post(menuData.isOnDuty ? 'clockOut' : 'clockIn');
}

function updateDutyUI() {
    const onDuty = menuData.isOnDuty === true;
    const unemployed = isDefaultJob(menuData.currentJob);

    const hero = el('dutyIndicator');
    const toggle = el('dutyToggleBtn');
    const shiftState = el('shiftState');
    const barDot = el('barDot');
    const job = currentJobEntry();
    const label = job?.label || menuData.currentJob || 'Unemployed';

    if (hero) hero.classList.toggle('on-duty', onDuty);
    if (barDot) barDot.className = 'dot' + (onDuty ? '' : ' idle');

    if (unemployed) {
        const paused = !onDuty;
        setText('dutyStatusText', paused ? 'Paused' : 'Always on duty');
        setText('dutyJobLine', paused ? 'You went idle - move around to clock back in' : `${label} is paid without clocking in`);
        setText('statusHint', paused ? 'Move around to resume your shift' : 'Take a job to start tracking shifts');
        if (toggle) {
            toggle.textContent = paused ? 'Paused' : 'Always on duty';
            toggle.className = 'btn-teal locked';
            toggle.disabled = true;
        }
        if (shiftState) {
            shiftState.className = paused ? 'off' : '';
            shiftState.innerHTML = paused ? '<span class="dot idle"></span>Paused' : '<span class="dot"></span>Always on';
        }
        return;
    }

    const point = menuData.dutyPoint || {};
    const blocked = pointBlocks();

    setText('dutyStatusText', onDuty ? 'On duty' : 'Off duty');
    if (blocked) {
        const where = `${point.label} · ${formatDistance(point.distance)} away`;
        setText('dutyJobLine', (onDuty ? 'Clock out at ' : 'Clock in at ') + where);
        setText('statusHint', `Head to ${point.label} to clock ${onDuty ? 'out' : 'in'}`);
    } else if (point.required && point.inside) {
        setText('dutyJobLine', onDuty ? `Clocked in as ${label} · at ${point.label}` : `At ${point.label} · ready to clock in`);
        setText('statusHint', onDuty ? 'You are earning while clocked in' : 'Clock in to start earning');
    } else {
        setText('dutyJobLine', onDuty ? `Clocked in as ${label}` : `Clocked out · ${label}`);
        setText('statusHint', onDuty ? 'You are earning while clocked in' : 'Clock in to start earning');
    }

    if (toggle) {
        toggle.textContent = blocked ? 'Set waypoint' : (onDuty ? 'Clock out' : 'Clock in');
        toggle.className = 'btn-teal' + (onDuty && !blocked ? ' out' : '');
        toggle.disabled = false;
    }

    if (shiftState) {
        shiftState.className = onDuty ? '' : 'off';
        shiftState.innerHTML = onDuty
            ? '<span class="dot"></span>On duty'
            : '<span class="dot idle"></span>Off duty';
    }
}

function startDutyTimer() {
    stopDutyTimer();
    dutyInterval = setInterval(() => {
        if (menuData.isOnDuty) {
            menuData.dutyTime = (menuData.dutyTime || 0) + 1;
            updateDutyTimer(menuData.dutyTime);
        }
    }, 1000);
}

function stopDutyTimer() {
    if (dutyInterval) { clearInterval(dutyInterval); dutyInterval = null; }
}

function updateDutyTimer(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0));
    const h = String(Math.floor(seconds / 3600)).padStart(2, '0');
    const m = String(Math.floor((seconds % 3600) / 60)).padStart(2, '0');
    const s = String(seconds % 60).padStart(2, '0');
    const text = `${h}:${m}:${s}`;

    setText('dutyTimer', text);
    setText('shiftClock', text);
}

// ═══════════════════════════════════════════════════════════════════════════
// JOB ACTIONS
// ═══════════════════════════════════════════════════════════════════════════

function switchJob(job) {
    post('switchJob', { job: job });
}

function quitJob(job) {
    showNuiConfirm('You will be set back to your default job and lose this one from your record.', () => {
        post('quitJob', { job: job });
    }, { title: 'Quit this job?', confirm: 'Quit job' });
}

function removeJob(job) {
    showNuiConfirm('This job comes off your record. You will have to be hired again to get it back.', () => {
        post('removeJob', { job: job });
    }, { title: 'Remove this job?', confirm: 'Remove' });
}

// ═══════════════════════════════════════════════════════════════════════════
// LEADERBOARDS
// ═══════════════════════════════════════════════════════════════════════════

// Only show the boards Config.Leaderboards.categories lists
function setupLeaderboardTabs() {
    const cats = menuData.leaderboardCategories;
    const buttons = [...document.querySelectorAll('#tab-leaderboard .seg-btn')];
    if (!Array.isArray(cats) || !cats.length) return;

    const ids = cats.map(c => c.id);
    buttons.forEach(btn => {
        const cat = cats.find(c => c.id === btn.dataset.lb);
        btn.style.display = cat ? '' : 'none';
        if (cat) btn.title = cat.label || '';
    });

    if (!ids.includes(currentLeaderboard)) {
        currentLeaderboard = ids.find(id => buttons.some(b => b.dataset.lb === id)) || 'total_hours';
    }
    buttons.forEach(b => b.classList.toggle('on', b.dataset.lb === currentLeaderboard));
}

function loadLeaderboards() {
    const container = el('leaderboardContent');
    if (container) container.innerHTML = skeletonRows(5);

    postJson('getLeaderboards').then(data => {
        lastLeaderboards = data || {};
        renderLeaderboard(lastLeaderboards);
    });
}

function skeletonRows(count) {
    let out = '';
    for (let i = 0; i < count; i++) {
        out += `<div class="row"><div class="av"></div><div class="row-txt"><b style="opacity:.25">Loading</b><span style="opacity:.2">Fetching rankings</span></div></div>`;
    }
    return out;
}

function renderLeaderboard(data) {
    const container = el('leaderboardContent');
    if (!container) return;

    const entries = (data && data[currentLeaderboard]) || [];

    if (!entries.length) {
        container.innerHTML = emptyState('fa-solid fa-trophy', 'No rankings yet',
            'Rankings fill in as players around the city clock hours and earn wages.');
        return;
    }

    container.innerHTML = entries.map((e, i) => {
        const rankClass = i === 0 ? 'gold' : i === 1 ? 'silver' : i === 2 ? 'bronze' : '';
        let value = e.value || 0;

        if (currentLeaderboard === 'total_earnings') value = '$' + formatNumber(value);
        else if (currentLeaderboard === 'total_hours') value = Number(value).toFixed(1) + 'h';

        return `
            <div class="lb ${e.me ? 'me' : ''}">
                <span class="lb-rank ${rankClass}">${i + 1}</span>
                <span class="lb-name">${esc(e.name || 'Unknown worker')}</span>
                ${e.me ? '<span class="tag live">You</span>' : ''}
                <span class="lb-value">${esc(value)}</span>
            </div>`;
    }).join('');
}

// ═══════════════════════════════════════════════════════════════════════════
// SCHEDULE
// ═══════════════════════════════════════════════════════════════════════════

function openScheduleModal() {
    if ((menuData.schedules || []).length >= (menuData.maxSchedules || 5)) {
        showNuiAlert(`You can have up to ${menuData.maxSchedules || 5} schedules. Delete one to add another.`, 'Schedule limit reached');
        return;
    }
    populateScheduleJobDropdown();
    const hour = el('scheduleHour');
    const minute = el('scheduleMinute');
    if (hour) hour.value = 9;
    if (minute) minute.value = 0;
    el('scheduleModal')?.classList.add('active');
}

function closeScheduleModal() {
    el('scheduleModal')?.classList.remove('active');
}

function saveSchedule() {
    const job = el('scheduleJob');

    if (!job || !job.value) {
        showNuiAlert('Pick a job before saving the schedule.', 'No job selected');
        return;
    }

    const hour = parseInt(el('scheduleHour')?.value, 10);
    const minute = parseInt(el('scheduleMinute')?.value, 10);
    if (!(hour >= 0 && hour <= 23) || !(minute >= 0 && minute <= 59)) {
        showNuiAlert('Use an hour from 0 to 23 and a minute from 0 to 59.', 'Time not valid');
        return;
    }

    const days = [];
    document.querySelectorAll('.days input:checked').forEach(cb => days.push(parseInt(cb.value, 10)));

    if (!days.length) {
        showNuiAlert('Pick at least one day for this schedule to run.', 'No days selected');
        return;
    }

    postJson('saveSchedule', { job: job.value, hour: hour, minute: minute, days: days, enabled: true })
        .then(res => { if (res && res.ok) closeScheduleModal(); });
}

function deleteSchedule(id) {
    showNuiConfirm('This schedule stops running and is deleted.', () => {
        postJson('deleteSchedule', { id: id });
    }, { title: 'Delete schedule?', confirm: 'Delete' });
}

// ═══════════════════════════════════════════════════════════════════════════
// TEAM (bosses)
// ═══════════════════════════════════════════════════════════════════════════

function setupTeamJobs() {
    const jobs = menuData.bossJobs || [];
    const select = el('teamJob');
    if (!select) return;

    if (!jobs.some(j => j.name === teamJob)) {
        teamJob = jobs[0]?.name || null;
        team = null;
    }
    select.innerHTML = jobs.map(j => `<option value="${esc(j.name)}" ${j.name === teamJob ? 'selected' : ''}>${esc(j.label)}</option>`).join('');
    select.style.display = jobs.length > 1 ? '' : 'none';
    select.onchange = () => { teamJob = select.value; team = null; loadTeam(); };

    const search = el('teamSearch');
    if (search) search.oninput = () => renderTeam();
}

function loadTeam() {
    if (!teamJob) return;
    if (!team) el('teamList').innerHTML = skeletonRows(4);
    postJson('bossTeam', { job: teamJob }).then(data => {
        team = data && data.members ? data : null;
        renderTeam();
    });
}

function renderTeam() {
    const list = el('teamList');
    if (!list) return;

    if (!team) {
        list.innerHTML = emptyState('fa-solid fa-users', 'Team not available',
            'You need a boss grade in this job to manage its staff.');
        return;
    }

    const c = team.counts || {};
    setText('teamTotal', c.total || 0);
    setText('teamOnline', (c.online || 0) + ' online');
    setText('teamOnDuty', c.onDuty || 0);
    setText('teamWeek', (Number(c.weekHours) || 0).toFixed(1) + 'h');
    setText('navTeamCount', c.total || 0);
    setText('teamTitle', `${team.label} staff`);
    setText('teamSub', `You are ${team.myGradeLabel} · you manage the grades below yours`);

    const hireBtn = el('hireBtn');
    if (hireBtn) hireBtn.style.display = team.permissions?.hire ? '' : 'none';

    const search = (el('teamSearch')?.value || '').toLowerCase();
    const members = (team.members || []).filter(m => !search || String(m.name).toLowerCase().includes(search));

    if (!members.length) {
        list.innerHTML = emptyState('fa-solid fa-users', search ? 'Nobody by that name' : 'No staff yet',
            search ? 'Try a different name.' : 'Hire someone and they show up here.');
        return;
    }

    list.innerHTML = members.map(renderMember).join('');
}

// Next grade up (+1) or down (-1) among the grades the job actually has
function gradeStep(grade, dir) {
    const grades = (team.grades || []).map(g => g.grade);
    const i = grades.indexOf(grade);
    return i === -1 ? undefined : grades[i + dir];
}

function renderMember(m) {
    const perms = team.permissions || {};
    const up = gradeStep(m.grade, 1);
    const down = gradeStep(m.grade, -1);
    const canUp = perms.promote && up !== undefined && up <= team.maxGrade;
    const canDown = perms.promote && down !== undefined;

    const state = m.onDuty ? '<span class="tag live">On duty</span>'
        : m.online ? '<span class="tag idle">Online</span>'
        : '<span class="tag off">Offline</span>';

    let actions = '';
    if (m.canManage) {
        actions = `
            <button class="ico" title="Promote" data-tact="up" ${canUp ? '' : 'disabled'}>${ICON.up}</button>
            <button class="ico" title="Demote" data-tact="down" ${canDown ? '' : 'disabled'}>${ICON.down}</button>
            <button class="ico danger" title="Let go" data-tact="fire" ${perms.fire ? '' : 'disabled'}>${ICON.letGo}</button>`;
    }

    return `
        <div class="row ${m.me ? 'on' : ''}" data-ref="${esc(m.ref)}">
            <div class="av">${esc(initials(m.name))}</div>
            <div class="row-txt">
                <b>${esc(m.name)}</b>
                <span>${esc(m.gradeLabel)} · ${(Number(m.weekHours) || 0).toFixed(1)}h this week · ${(Number(m.totalHours) || 0).toFixed(1)}h total</span>
            </div>
            <div class="row-end">
                ${m.me ? '<span class="tag live">You</span>' : ''}
                ${state}
                ${actions}
            </div>
        </div>`;
}

function onTeamClick(e) {
    const btn = e.target.closest('[data-tact]');
    const row = e.target.closest('.row[data-ref]');
    if (!btn || !row || btn.disabled || !team) return;

    const member = (team.members || []).find(m => m.ref === row.dataset.ref);
    if (!member) return;

    if (btn.dataset.tact === 'up' || btn.dataset.tact === 'down') {
        const grade = gradeStep(member.grade, btn.dataset.tact === 'up' ? 1 : -1);
        if (grade === undefined) return;
        postJson('bossSetGrade', { job: teamJob, ref: member.ref, grade: grade }).then(() => loadTeam());
    }

    if (btn.dataset.tact === 'fire') {
        showNuiConfirm(`${member.name} comes off the ${team.label} roster and loses the job.`, () => {
            postJson('bossFire', { job: teamJob, ref: member.ref }).then(() => loadTeam());
        }, { title: 'Let them go?', confirm: 'Let go' });
    }
}

function openHireModal() {
    if (!team) return;
    hirePick = null;

    const grades = (team.grades || []).filter(g => g.grade <= team.maxGrade);
    el('hireGrade').innerHTML = grades.map(g => `<option value="${esc(g.grade)}">${esc(g.label)}</option>`).join('');
    setText('hireTitle', `Hire for ${team.label}`);
    el('hireModal')?.classList.add('active');
    loadNearby();
}

function closeHireModal() {
    el('hireModal')?.classList.remove('active');
    hirePick = null;
}

function loadNearby() {
    const list = el('hireList');
    if (!list || !teamJob) return;
    list.innerHTML = skeletonRows(2);

    postJson('bossNearby', { job: teamJob }).then(data => {
        const players = (data && data.players) || [];
        const range = Number(data && data.range) || 0;
        setText('hireRange', range > 0 ? `Within ${range} m of you` : 'Everyone online');

        if (!players.some(p => p.id === hirePick && !p.employed)) hirePick = null;

        if (!players.length) {
            list.innerHTML = emptyState('fa-solid fa-user-plus', range > 0 ? 'Nobody close enough' : 'Nobody else online',
                range > 0 ? `Stand within ${range} m of the person you want to hire, then refresh.` : 'There is nobody to hire right now.');
        } else {
            list.innerHTML = players.map(p => `
                <div class="row ${p.employed ? 'paused' : 'clickable'} ${p.id === hirePick ? 'sel' : ''}" data-pid="${esc(p.id)}" data-employed="${p.employed ? 1 : 0}">
                    <div class="av">${esc(initials(p.name))}</div>
                    <div class="row-txt">
                        <b>${esc(p.name)}</b>
                        <span>ID ${esc(p.id)}${p.distance !== undefined && p.distance !== null ? ' · ' + esc(formatDistance(p.distance)) + ' away' : ''}</span>
                    </div>
                    <div class="row-end">${p.employed ? '<span class="tag off">Already staff</span>' : ''}</div>
                </div>`).join('');
        }
        el('hireSend').disabled = hirePick === null;
    });
}

function onHireClick(e) {
    const row = e.target.closest('.row[data-pid]');
    if (!row || row.dataset.employed === '1') return;
    hirePick = parseInt(row.dataset.pid, 10);
    document.querySelectorAll('#hireList .row').forEach(r => r.classList.toggle('sel', r === row));
    el('hireSend').disabled = false;
}

function sendHire() {
    if (hirePick === null || !teamJob) return;
    const grade = parseInt(el('hireGrade')?.value, 10);
    postJson('bossHire', { job: teamJob, target: hirePick, grade: isNaN(grade) ? undefined : grade }).then(res => {
        if (res && res.ok) {
            closeHireModal();
            loadTeam();
        }
    });
}

// ═══════════════════════════════════════════════════════════════════════════
// RENDER — ADMIN
// ═══════════════════════════════════════════════════════════════════════════

function adminCan(perm) {
    const perms = adminData.permissions || {};
    return perms[perm] !== false;
}

function renderAdmin() {
    applyAdminPermissions();
    renderJobOptions();
    renderPlayers();
    renderLogs();
    renderAnalytics();
    renderBulkPlayers();
    setupAdminNav();
    setupSearch();
    setupLogFilter();
    setupPlayerScope();
    applyPlayerSearch();
}

// Hide the tabs this staff member's permissions don't cover
function applyAdminPermissions() {
    let firstVisible = null;
    document.querySelectorAll('#adminPanel .nav').forEach(btn => {
        const perm = ADMIN_TAB_PERM[btn.dataset.atab];
        const allowed = !perm || adminCan(perm);
        btn.style.display = allowed ? '' : 'none';
        if (allowed && !firstVisible) firstVisible = btn;
    });

    const active = document.querySelector('#adminPanel .nav.on');
    if ((!active || active.style.display === 'none') && firstVisible) {
        setupAdminNav();
        firstVisible.click();
    }
}

function renderJobOptions() {
    const list = el('jobOptions');
    if (!list) return;
    list.innerHTML = (adminData.jobs || [])
        .map(j => `<option value="${esc(j.name)}">${esc(j.label || j.name)}</option>`).join('');
}

function setupPlayerScope() {
    document.querySelectorAll('#playerScope .seg-btn').forEach(btn => {
        btn.onclick = function () {
            if (playerScope === this.dataset.scope) return;
            playerScope = this.dataset.scope;
            document.querySelectorAll('#playerScope .seg-btn').forEach(b => b.classList.toggle('on', b === this));

            const all = playerScope === 'all';
            const input = el('playerSearch');
            if (input) { input.value = ''; input.placeholder = all ? 'Name or identifier' : 'Search players'; }
            setText('playersTitle', all ? 'All characters' : 'Online players');
            setText('playersSub', all ? 'Anyone who has played, online or not' : 'Select a player to manage their jobs');
            searchResults = [];
            renderPlayers();
            if (all) input?.focus();
        };
    });
}

function runPlayerSearch() {
    const query = (el('playerSearch')?.value || '').trim();
    const container = el('playersList');
    if (query.length < 2) {
        searchResults = [];
        renderPlayers();
        return;
    }
    container.innerHTML = skeletonRows(3);
    postJson('adminSearch', { query: query }).then(res => {
        if (playerScope !== 'all') return;
        searchResults = (res && res.results) || [];
        renderPlayers();
    });
}

function renderSearchResults(container) {
    const query = (el('playerSearch')?.value || '').trim();
    if (query.length < 2) {
        container.innerHTML = emptyState('fa-solid fa-magnifying-glass', 'Search every character',
            'Type two or more letters of a name, or paste an identifier.');
        return;
    }
    if (!searchResults.length) {
        container.innerHTML = emptyState('fa-solid fa-user-slash', 'No characters found',
            'Nobody matches that name or identifier.');
        return;
    }

    container.innerHTML = searchResults.map(p => `
        <div class="row clickable" data-ident="${esc(p.identifier)}">
            <div class="av">${esc(initials(p.name))}</div>
            <div class="row-txt">
                <b>${esc(p.name || p.identifier)}</b>
                <span class="mono">${esc(p.identifier)}${p.online ? ' · ID ' + esc(p.id) : ''}</span>
            </div>
            <div class="row-end">
                ${p.jobLabel ? `<span class="tag idle">${esc(p.jobLabel)}</span>` : ''}
                <span class="tag ${p.online ? 'live' : 'off'}">${p.online ? 'Online' : 'Offline'}</span>
            </div>
        </div>`).join('');
}

function renderPlayers() {
    const container = el('playersList');
    if (!container) return;

    const players = adminData.players || [];
    setText('navPlayerCount', players.length);
    setText('adminOnline', players.length);

    if (playerScope === 'all') {
        renderSearchResults(container);
        return;
    }

    if (!players.length) {
        container.innerHTML = emptyState('fa-solid fa-users', 'Nobody online',
            'Players appear here as soon as they connect to the server.');
        return;
    }

    container.innerHTML = players.map(p => `
        <div class="row clickable" data-pid="${esc(p.id)}">
            <div class="av">${esc(initials(p.name))}</div>
            <div class="row-txt">
                <b>${esc(p.name || 'Unknown')}</b>
                <span>ID ${esc(p.id)}${p.onDuty ? ' · On duty' : ''}</span>
            </div>
            <div class="row-end">
                <span class="tag ${p.onDuty ? 'live' : 'off'}">${esc(p.jobLabel || p.job || 'None')}</span>
            </div>
        </div>`).join('');
}

function onPlayersClick(e) {
    const row = e.target.closest('.row[data-pid], .row[data-ident]');
    if (!row) return;
    // online rows open by server id, search results by character identifier
    openPlayerModal(row.dataset.ident ? row.dataset.ident : parseInt(row.dataset.pid, 10));
}

const LOG_STYLE = {
    clock_in: '', clock_out: 'mute', job_switch: '', job_added: '',
    admin_add_job: '', admin_set_job: '', admin_remove_job: 'red',
    quit_job: 'red', job_removed: 'red'
};

function renderLogs() {
    const container = el('logsList');
    if (!container) return;

    let logs = adminData.logs || [];
    const filter = el('logFilter')?.value || '';
    if (filter) logs = logs.filter(l => l.action === filter);

    if (!logs.length) {
        container.innerHTML = emptyState('fa-solid fa-clipboard-list', 'Nothing logged',
            'Job switches, clock-ins and staff actions will be listed here.');
        return;
    }

    container.innerHTML = logs.slice(0, 60).map(log => {
        let time = '--:--';
        try { time = new Date(log.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }); } catch (e) {}

        const style = LOG_STYLE[log.action] !== undefined ? LOG_STYLE[log.action] : 'mute';
        const action = String(log.action || 'action').replace(/_/g, ' ');

        let detail = '';
        if (log.job) detail += esc(log.job);
        if (log.details) detail += (detail ? ' · ' : '') + esc(log.details);
        if (log.admin_name) detail += (detail ? ' · ' : '') + 'by ' + esc(log.admin_name);

        return `
            <div class="log">
                <time>${esc(time)}</time>
                <b>${esc(log.player_name || 'Unknown')}</b>
                <p><span class="chip ${style}">${esc(action)}</span>${detail}</p>
            </div>`;
    }).join('');
}

function setupLogFilter() {
    const filter = el('logFilter');
    if (filter) filter.onchange = () => renderLogs();
}

function renderAnalytics() {
    const container = el('analyticsGrid');
    if (!container) return;

    const analytics = adminData.analytics || {};
    const topJobs = analytics.topJobs || [];

    container.innerHTML = `
        <div class="stat">
            <div class="tile"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 5.2a3.5 3.5 0 0 1 0 5.6"/></svg></div>
            <div class="stat-txt"><span>Tracked players</span><b>${formatNumber(analytics.totalPlayers || 0)}</b></div>
        </div>
        <div class="stat">
            <div class="tile"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg></div>
            <div class="stat-txt"><span>Hours worked</span><b>${formatNumber(Math.floor(analytics.totalHours || 0))}</b></div>
        </div>
        <div class="stat">
            <div class="tile"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><rect x="3" y="7" width="18" height="13" rx="2.5"/><path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7"/></svg></div>
            <div class="stat-txt"><span>Jobs in use</span><b>${formatNumber(analytics.jobsInUse || 0)}</b></div>
        </div>`;

    const list = el('analyticsJobs');
    if (!list) return;

    if (!topJobs.length) {
        list.innerHTML = emptyState('fa-solid fa-chart-simple', 'No job data',
            'Figures appear once players start clocking shifts.');
        return;
    }

    const peak = Math.max(...topJobs.map(j => Number(j.hours) || 0), 1);

    list.innerHTML = topJobs.map(j => {
        const hours = Number(j.hours) || 0;
        const pct = Math.max(3, Math.round((hours / peak) * 100));
        return `
            <div class="bar-row">
                <div class="bar-top">
                    <b>${esc(j.label || j.job)}</b>
                    <span><em>${hours.toFixed(1)}h</em>${j.players ? ' · ' + esc(j.players) + (j.players === 1 ? ' player' : ' players') : ''}</span>
                </div>
                <div class="meter"><i style="width:${pct}%"></i></div>
            </div>`;
    }).join('');
}

function renderBulkPlayers() {
    const container = el('bulkPlayerList');
    if (!container) return;

    const players = adminData.players || [];

    if (!players.length) {
        container.innerHTML = emptyState('fa-solid fa-users', 'Nobody online',
            'You need at least one player online to run a bulk action.');
        updateBulkCount();
        return;
    }

    container.innerHTML = players.map(p => `
        <label class="check" data-name="${esc((p.name || '').toLowerCase())}">
            <input type="checkbox" value="${esc(p.id)}" class="bulk-player-cb" onchange="updateBulkCount()">
            <span class="pid">#${esc(p.id)}</span>
            <span class="pname">${esc(p.name || 'Unknown')}</span>
            <span class="pjob">${esc(p.jobLabel || p.job || 'None')}</span>
        </label>`).join('');

    updateBulkCount();
}

function bulkSelectAll(selectAll) {
    document.querySelectorAll('.bulk-player-cb').forEach(cb => {
        const label = cb.closest('.check');
        if (!label || label.style.display !== 'none') cb.checked = selectAll;
    });
    updateBulkCount();
}

function updateBulkCount() {
    setText('bulkSelectedCount', document.querySelectorAll('.bulk-player-cb:checked').length);
}

function executeBulkAction() {
    const action = el('bulkAction')?.value || 'add';
    const job = (el('bulkJob')?.value || '').trim();
    const grade = parseInt(el('bulkGrade')?.value, 10) || 0;

    const playerIds = [];
    document.querySelectorAll('.bulk-player-cb:checked').forEach(cb => playerIds.push(parseInt(cb.value, 10)));

    if (!job) { showNuiAlert('Enter a job name before running the action.', 'No job entered'); return; }
    if (!playerIds.length) { showNuiAlert('Select at least one player.', 'Nobody selected'); return; }

    const verb = action === 'add' ? 'Add' : action === 'remove' ? 'Remove' : 'Set';

    showNuiConfirm(`${verb} "${job}" for ${playerIds.length} ${playerIds.length === 1 ? 'player' : 'players'}. This is written to the log.`, () => {
        postJson('adminBulkAction', { action: action, playerIds: playerIds, job: job, grade: grade })
            .then(() => refreshAdminData());
    }, { title: 'Run bulk action?', confirm: 'Execute' });
}

// ═══════════════════════════════════════════════════════════════════════════
// PLAYER MODAL
// ═══════════════════════════════════════════════════════════════════════════

let modalTarget = null; // server id (online) or identifier (any character)

function openPlayerModal(target) {
    postJson('adminGetPlayer', { target: target }).then(data => {
        if (!data || !data.jobs) {
            showNuiAlert('That player could not be loaded. They may have just left.', 'Request failed');
            return;
        }

        modalTarget = target;
        setText('playerModalName', data.name || 'Player');
        setText('playerModalSub', (data.online ? `Online · ID ${data.id}` : 'Offline') + ` · ${data.identifier}`);

        const content = el('playerModalContent');
        if (!content) return;

        const jobs = data.jobs || [];
        const canEdit = data.canEdit !== false;

        let last = '';
        if (data.lastShift) {
            let when = '';
            try { when = new Date(data.lastShift.clockIn).toLocaleString(); } catch (e) {}
            last = `<div class="sec">Last shift</div>
                <p class="modal-note">${esc(data.lastShift.jobLabel || data.lastShift.job)} · ${esc(when)}${data.lastShift.clockOut ? '' : ' · still open'}</p>`;
        }

        content.innerHTML = `
            <div class="sec">Jobs on record</div>
            ${jobs.length ? jobs.map(j => {
                const active = j.name === data.currentJob;
                return `
                <div class="row ${active ? 'on' : ''}" data-job="${esc(j.name)}" data-grade="${esc(j.grade)}">
                    <div class="av cat"><i class="fa-solid fa-briefcase"></i></div>
                    <div class="row-txt">
                        <b>${esc(j.label || j.name)}</b>
                        <span>${esc(j.gradeLabel || ('Grade ' + j.grade))} · grade ${esc(j.grade)} · ${(Number(j.hours) || 0).toFixed(1)}h worked</span>
                    </div>
                    <div class="row-end">
                        ${active ? `<span class="tag ${data.onDuty ? 'live' : 'idle'}">${data.onDuty ? 'On duty' : 'Active'}</span>` : ''}
                        ${canEdit && !active ? `<button class="ico" title="Make this their active job" data-mact="active">${ICON.switchTo}</button>` : ''}
                        ${canEdit && !j.isDefault ? `<button class="ico danger" title="Remove job" data-mact="remove">${ICON.trash}</button>` : ''}
                    </div>
                </div>`;
            }).join('')
            : emptyState('fa-solid fa-briefcase', 'No jobs assigned', 'This player has nothing on their employment record yet.')}

            ${last}

            ${canEdit ? `
            <div class="sec">Add a job</div>
            <div class="field-row" style="grid-template-columns:1fr 92px">
                <div class="field"><label for="adminAddJobName">Job name</label><input type="text" id="adminAddJobName" list="jobOptions" placeholder="police" autocomplete="off"></div>
                <div class="field"><label for="adminAddJobGrade">Grade</label><input type="number" id="adminAddJobGrade" value="0" min="0"></div>
            </div>
            <button class="btn-teal" data-mact="add">Add job</button>` : ''}`;

        el('playerModal')?.classList.add('active');
    });
}

function onPlayerModalClick(e) {
    const btn = e.target.closest('[data-mact]');
    if (!btn || modalTarget === null) return;

    const row = btn.closest('.row[data-job]');
    if (btn.dataset.mact === 'add') adminAddJob(modalTarget);
    if (btn.dataset.mact === 'remove' && row) adminRemoveJob(modalTarget, row.dataset.job);
    if (btn.dataset.mact === 'active' && row) adminSetActive(modalTarget, row.dataset.job, parseInt(row.dataset.grade, 10));
}

function closePlayerModal() {
    el('playerModal')?.classList.remove('active');
    modalTarget = null;
}

// Reload whatever list the modal was opened from
function afterAdminEdit(target) {
    openPlayerModal(target);
    if (playerScope === 'all') runPlayerSearch();
    refreshAdminData();
}

function adminAddJob(target) {
    const job = (el('adminAddJobName')?.value || '').trim();
    const grade = parseInt(el('adminAddJobGrade')?.value, 10) || 0;

    if (!job) { showNuiAlert('Enter a job name first.', 'No job entered'); return; }

    postJson('adminAddJob', { target: target, job: job, grade: grade }).then(() => afterAdminEdit(target));
}

function adminRemoveJob(target, job) {
    showNuiConfirm(`"${job}" comes off this player's record. If it is their active job they go back to the default job.`, () => {
        postJson('adminRemoveJob', { target: target, job: job }).then(() => afterAdminEdit(target));
    }, { title: 'Remove this job?', confirm: 'Remove' });
}

function adminSetActive(target, job, grade) {
    postJson('adminSetJob', { target: target, job: job, grade: isNaN(grade) ? undefined : grade }).then(() => afterAdminEdit(target));
}

// ═══════════════════════════════════════════════════════════════════════════
// NAVIGATION
// ═══════════════════════════════════════════════════════════════════════════

function setupNav() {
    document.querySelectorAll('#jobMenu .nav').forEach(btn => {
        btn.onclick = function () {
            const tab = this.dataset.tab;
            if (!tab) return;

            document.querySelectorAll('#jobMenu .nav').forEach(b => b.classList.remove('on'));
            document.querySelectorAll('#jobMenu .pane').forEach(p => p.classList.remove('on'));

            this.classList.add('on');
            el('tab-' + tab)?.classList.add('on');

            const copy = PANES[tab];
            if (copy) { setText('paneTitle', copy[0]); setText('paneDesc', copy[1]); }

            if (tab === 'leaderboard') loadLeaderboards();
            if (tab === 'team') loadTeam();
        };
    });

    document.querySelectorAll('#tab-leaderboard .seg-btn').forEach(btn => {
        btn.onclick = function () {
            document.querySelectorAll('#tab-leaderboard .seg-btn').forEach(b => b.classList.remove('on'));
            this.classList.add('on');
            currentLeaderboard = this.dataset.lb || 'total_hours';
            // every board arrives in one reply - no need to ask again
            renderLeaderboard(lastLeaderboards);
        };
    });
}

function setupAdminNav() {
    document.querySelectorAll('#adminPanel .nav').forEach(btn => {
        btn.onclick = function () {
            const tab = this.dataset.atab;
            if (!tab) return;

            document.querySelectorAll('#adminPanel .nav').forEach(b => b.classList.remove('on'));
            document.querySelectorAll('#adminPanel .pane').forEach(p => p.classList.remove('on'));

            this.classList.add('on');
            el('tab-' + tab)?.classList.add('on');

            const copy = ADMIN_PANES[tab];
            if (copy) { setText('aPaneTitle', copy[0]); setText('aPaneDesc', copy[1]); }
        };
    });
}

function applyPlayerSearch() {
    const search = (el('playerSearch')?.value || '').toLowerCase();
    document.querySelectorAll(playerScope === 'all' ? '#__none' : '#playersList .row').forEach(row => {
        const name = (row.querySelector('b')?.textContent || '').toLowerCase();
        row.style.display = name.includes(search) ? '' : 'none';
    });

    const bulkSearch = (el('bulkSearch')?.value || '').toLowerCase();
    document.querySelectorAll('#bulkPlayerList .check').forEach(label => {
        label.style.display = (label.dataset.name || '').includes(bulkSearch) ? '' : 'none';
    });
}

function setupSearch() {
    const jobSearch = el('jobSearch');
    if (jobSearch) {
        jobSearch.oninput = () => renderJobs();
        // Enter switches to the top result that isn't already active
        jobSearch.onkeydown = (e) => {
            if (e.key !== 'Enter') return;
            const next = visibleJobs().find(j => j.name !== menuData.currentJob);
            if (next) switchJob(next.name);
        };
    }

    const playerSearch = el('playerSearch');
    if (playerSearch) {
        playerSearch.oninput = () => {
            if (playerScope !== 'all') { applyPlayerSearch(); return; }
            // ask the server a moment after typing stops
            clearTimeout(searchTimer);
            searchTimer = setTimeout(runPlayerSearch, 350);
        };
    }

    const bulkSearch = el('bulkSearch');
    if (bulkSearch) bulkSearch.oninput = applyPlayerSearch;
}

// One listener per list, set up once - rows are re-rendered freely
document.addEventListener('DOMContentLoaded', () => {
    el('jobsGrid')?.addEventListener('click', onJobsClick);
    el('schedulesList')?.addEventListener('click', onSchedulesClick);
    el('playersList')?.addEventListener('click', onPlayersClick);
    el('playerModalContent')?.addEventListener('click', onPlayerModalClick);
    el('teamList')?.addEventListener('click', onTeamClick);
    el('hireList')?.addEventListener('click', onHireClick);
});
