/* ═══════════════════════════════════════════════════════════
   NAYZEEE RADIO · admin (focused)                                      apps/admin/app.js
   The /radioadmin window (client/modules/admin.lua ↔ server/modules/admin.lua).
   Console window: mark + "Radio control", sidebar (Channels · Vehicles · Live + the
   fixed config ranges), status bar with key hints, pending edits and the signature.

   Lua → NUI
     open  { ok, channels, vehicles, jobs, live, limits?, restricted?, current?, me? }
       channels   [{ freq '155.50', access 'open'|'code'|'job', code?, jobs? { police = 0 }, label?, updatedBy? }]
       vehicles   [{ model, label?, range_mult }]
       jobs       [{ name, label, grades [{ grade, label }] }]       (job picker)
       live       { channels [{ freq, label, access, members, vehicles, talkers [{ id, name, callsign, device }] }],
                    jammers [{ id, type, label, owner, ownerId, x, y, z, expires (s), e, placed }], radios }
       limits     { channels, vehicles, jobs, grade, label, model, min, max }
       restricted [{ from, to, label, jobs }]                        (Config ranges, read only)
       current    { model, label, radio } | nil                       (the car the admin sits in)
     close
   NUI → Lua (NZR.post → reply)
     admin:save { channels?, vehicles? } → { ok, channels, vehicles } | { ok = false, error }
                only the lists that were edited are sent (the server keeps a list left out)
     admin:jammerRemove { id }  → { ok }
     admin:live                 → { ok, live }            every 5 s while the Live page is up
     admin:current              → { ok, current }         when the Vehicles page opens
     admin:waypoint { x, y }    → { ok }                  "Mark" on a jammer row
     admin:close                (Esc / Close; the first one warns when edits are pending)

   Strings: locales/en/windows.lua (ui.ad_*), English fallbacks inline for the preview.
   Edits stay in the window until Save. Every row is checked as you type (our wording) and
   Save is refused while a row is wrong. CTRL+S saves. Player text goes through NZR.esc.
   ═══════════════════════════════════════════════════════════ */
(() => {
  const NZR = window.NZR;
  const { esc, t, icon, clamp } = NZR;
  const CODES = { pocket: 'JX-10', case: 'JX-40', heavy: 'JX-90' };
  const LIVE_EVERY = 5000;
  const ACCESS = ['open', 'code', 'job'];
  const L = (k, f) => t(`ui.ad_${k}`, f);
  const fill = (s, o) => String(s).replace(/\{(\w+)\}/g, (m, k) => (o[k] !== undefined ? o[k] : m));
  const num = (v, d) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
  const fkey = v => NZR.fmt.freq(v);
  // Lua's json can send an empty table as {} instead of []: every list goes through this
  const arr = v => (Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []));
  const FREQ_RE = /^\s*\d{1,3}([.,]\d{1,2})?\s*$/;
  const MODEL_RE = /^[A-Za-z0-9_]+$/;
  let uidN = 0;
  const uid = () => `r${++uidN}`;

  /* ─────────────── state ─────────────── */
  let app = null, root = null, win = null;
  let D = {};                          // the open payload (jobs, limits, restricted, live, current)
  let page = 'channels';
  let ch = [], veh = [];               // working rows
  const flt = { q: '', access: 'all', vq: '' };
  let saving = false;
  let banner = null;                   // { tone, text }
  let modal = null;                    // open NZR.ui.Modal
  let modalKind = '';                  // 'leave' (Esc again closes the window) | 'jam'
  let menuEl = null, menuState = null; // open dropdown
  let menuAt = 0;                      // when it opened (its own scroll-into-view must not close it)
  let liveTimer = 0, tickTimer = 0, liveAt = 0, liveBusy = false;
  let jobIndex = new Map();

  const lim = () => Object.assign({ channels: 300, vehicles: 200, jobs: 16, grade: 20, label: 32, model: 32, min: 1, max: 999.99 }, D.limits || {});
  const q = s => root.querySelector(s);

  /* ─────────────── rows ─────────────── */
  function jobsList(raw) {
    const out = [];
    if (raw && typeof raw === 'object') {
      if (Array.isArray(raw)) raw.forEach(j => {
        if (typeof j === 'string') out.push({ name: j, grade: 0 });
        else if (j && j.name) out.push({ name: String(j.name), grade: Math.max(0, Math.round(num(j.grade, 0))) });
      });
      else Object.keys(raw).forEach(n => out.push({ name: n, grade: Math.max(0, Math.round(num(raw[n], 0))) }));
    }
    return out.sort((a, b) => a.name.localeCompare(b.name));
  }
  const snapCh = r => JSON.stringify([fkey(r.freq) || r.freq.trim(), r.access, r.access === 'code' ? r.code : '',
    r.access === 'job' ? r.jobs.map(j => `${j.name}:${j.grade}`).sort().join(',') : '', r.label.trim()]);
  const snapV = r => JSON.stringify([r.model.trim().toLowerCase(), r.label.trim(), r.range.toFixed(2)]);

  function chRow(c, isNew) {
    const r = {
      uid: uid(), freq: (c && (fkey(c.freq) || String(c.freq ?? ''))) || '',
      access: ACCESS.includes(c && c.access) ? c.access : 'open',
      code: c && c.code !== undefined && c.code !== null ? String(c.code) : '',
      jobs: jobsList(c && c.jobs), label: c && c.label ? String(c.label) : '', by: (c && c.updatedBy) || '',
      deleted: false, reveal: false, orig: null,
    };
    if (!isNew) r.orig = snapCh(r);
    return r;
  }
  function vRow(v, isNew) {
    const r = {
      uid: uid(), model: (v && v.model ? String(v.model) : ''), label: v && v.label ? String(v.label) : '',
      range: clamp(Math.round(num(v && (v.range_mult ?? v.rangeMult ?? v.range), 1) * 20) / 20, 0.5, 3), deleted: false, orig: null,
    };
    if (!isNew) r.orig = snapV(r);
    return r;
  }
  const isEdited = (r, snap) => (r.orig === null ? !r.deleted : (r.deleted || snap(r) !== r.orig));
  const editsCh = () => ch.filter(r => isEdited(r, snapCh)).length;
  const editsV = () => veh.filter(r => isEdited(r, snapV)).length;
  const edits = () => editsCh() + editsV();

  function chToServer(r) {
    const o = { freq: fkey(r.freq), access: r.access };
    if (r.access === 'code') o.code = r.code;
    if (r.access === 'job') { o.jobs = {}; r.jobs.forEach(j => { o.jobs[j.name] = j.grade; }); }
    const lb = r.label.trim();
    if (lb) o.label = lb;
    return o;
  }
  function vToServer(r) {
    const o = { model: r.model.trim().toLowerCase(), range_mult: Math.round(r.range * 100) / 100 };
    const lb = r.label.trim();
    if (lb) o.label = lb;
    return o;
  }

  /* ─────────────── checks (our wording) ─────────────── */
  function restrictedAt(k) {
    if (!k) return null;
    const f = Number(k);
    return (D.restricted || []).find(r => f >= num(r.from, 0) - 1e-6 && f <= num(r.to, 0) + 1e-6) || null;
  }
  function chIssues(r, counts) {
    if (r.deleted) return [];
    const out = [];
    const m = lim();
    const k = fkey(r.freq);
    if (!r.freq.trim()) out.push({ f: 'freq', msg: L('e_freq_empty', 'Type the frequency this rule is for') });
    else if (!FREQ_RE.test(r.freq) || !k || Number(k) < m.min || Number(k) > m.max) {
      out.push({ f: 'freq', msg: fill(L('e_freq', 'Radios tune {min} to {max} MHz, with two decimals at most'), { min: Number(m.min).toFixed(2), max: Number(m.max).toFixed(2) }) });
    } else if ((counts.get(k) || 0) > 1) out.push({ f: 'freq', msg: fill(L('e_dup', '{freq} has more than one rule. Keep one of them'), { freq: k }) });
    if (r.access === 'code' && !/^\d{4}$/.test(r.code)) out.push({ f: 'code', msg: L('e_code', 'The code is four digits, no more, no less') });
    if (r.access === 'job' && !r.jobs.length) out.push({ f: 'jobs', msg: L('e_jobs', 'Add a job, or set the channel back to Open') });
    if (r.access === 'job' && r.jobs.length > m.jobs) out.push({ f: 'jobs', msg: fill(L('e_jobs_max', 'A channel takes {n} jobs at most'), { n: m.jobs }) });
    if (r.label.trim().length > m.label) out.push({ f: 'label', msg: fill(L('e_label', 'Names stop at {n} characters'), { n: m.label }) });
    return out;
  }
  function chNotes(r) {
    if (r.deleted) return [];
    const k = fkey(r.freq);
    const band = FREQ_RE.test(r.freq) ? restrictedAt(k) : null;
    if (!band) return [];
    return [{ msg: fill(L('n_range', 'Sits inside {label} ({from}–{to}). This rule wins over the range here'), { label: band.label || L('range_in', 'a fixed range'), from: num(band.from, 0).toFixed(2), to: num(band.to, 0).toFixed(2) }) }];
  }
  function vIssues(r, counts) {
    if (r.deleted) return [];
    const out = [];
    const m = lim();
    const mdl = r.model.trim();
    if (!mdl) out.push({ f: 'model', msg: L('e_model_empty', 'Type the spawn name of the car') });
    else if (!MODEL_RE.test(mdl) || mdl.length > m.model) out.push({ f: 'model', msg: fill(L('e_model', 'Spawn names use letters, digits and _ only ({n} max)'), { n: m.model }) });
    else if ((counts.get(mdl.toLowerCase()) || 0) > 1) out.push({ f: 'model', msg: fill(L('e_dup_model', '{model} is on the list twice'), { model: mdl.toLowerCase() }) });
    if (r.label.trim().length > m.label) out.push({ f: 'label', msg: fill(L('e_label', 'Names stop at {n} characters'), { n: m.label }) });
    return out;
  }
  function chCounts() {
    const c = new Map();
    ch.forEach(r => { if (r.deleted) return; const k = FREQ_RE.test(r.freq) ? fkey(r.freq) : null; if (k) c.set(k, (c.get(k) || 0) + 1); });
    return c;
  }
  function vCounts() {
    const c = new Map();
    veh.forEach(r => { if (r.deleted) return; const k = r.model.trim().toLowerCase(); if (k) c.set(k, (c.get(k) || 0) + 1); });
    return c;
  }
  function badRows() {
    const cc = chCounts(), vc = vCounts();
    return { ch: ch.filter(r => chIssues(r, cc).length), veh: veh.filter(r => vIssues(r, vc).length) };
  }

  /* ═══════════════ SHELL ═══════════════ */
  function build() {
    root.innerHTML = '<div class="nzr-dim"></div>';
    win = NZR.ui.Win(root, {
      title: L('title', 'Radio control'),
      sub: L('sub', 'Channels · cars · live traffic'),
      nav: navItems(), navValue: page,
      onNav: id => go(id),
      onClose: () => { if (modalUp() && modalKind !== 'leave') { modal.close(); modal = null; } tryClose(); },
    });
    win.el.classList.add('ad');
    win.act.innerHTML = `<button class="btn-line btn-sm ad-discard">${icon('rot-l')}${esc(L('discard', 'Undo all'))}</button>
      <button class="btn-teal btn-sm ad-save">${icon('save')}<span>${esc(L('save', 'Save'))}</span></button>`;
    win.act.querySelector('.ad-save').onclick = () => save();
    win.act.querySelector('.ad-discard').onclick = () => discard();
    win.main.addEventListener('input', onInput);
    win.main.addEventListener('click', onClick);
    win.main.addEventListener('focusout', onBlur);
    win.main.addEventListener('scroll', () => { if (performance.now() - menuAt > 350) closeMenu(); }, true);
  }

  function navItems() {
    const b = badRows();
    const inUse = ((D.live && D.live.channels) || []).length;
    return [
      { group: L('g_rules', 'Rules') },
      { id: 'channels', label: L('nav_channels', 'Channels'), icon: 'frequency', tally: b.ch.length ? `${b.ch.length} !` : ch.filter(r => !r.deleted).length },
      { id: 'vehicles', label: L('nav_vehicles', 'Vehicles'), icon: 'car', tally: b.veh.length ? `${b.veh.length} !` : veh.filter(r => !r.deleted).length },
      { group: L('g_air', 'Right now') },
      { id: 'live', label: L('nav_live', 'Live'), icon: 'broadcast', tally: inUse },
    ];
  }
  function renderSide() {
    if (!win) return;
    win.setNav(navItems(), page);
    const b = badRows();
    win.side.querySelectorAll('.w-nav').forEach(n => {
      const bad = (n.dataset.id === 'channels' && b.ch.length) || (n.dataset.id === 'vehicles' && b.veh.length);
      n.classList.toggle('bad', !!bad);
    });
    const rs = D.restricted || [];
    const box = document.createElement('div');
    box.className = 'ad-fixed';
    box.innerHTML = `<div class="w-grp">${esc(L('g_fixed', 'Fixed in the config'))}</div>` + (rs.length
      ? rs.map(r => `<div class="ad-band"><span class="nzr-mono">${esc(num(r.from, 0).toFixed(2))}<i>–</i>${esc(num(r.to, 0).toFixed(2))}</span><b>${esc(r.label || L('range', 'Fixed range'))}</b><em>${esc(jobsList(r.jobs).map(j => j.name).join(', ') || '-')}</em></div>`).join('')
      : `<p class="ad-none">${esc(L('fixed_none', 'No ranges are locked in the config.'))}</p>`) +
      `<p class="ad-band-note">${esc(L('fixed_note', 'Edit these in config/modules/channels.lua. A rule here for a single frequency wins over them.'))}</p>`;
    win.side.appendChild(box);
  }
  function renderMid() {
    const lv = D.live || {};
    const radios = num(lv.radios, 0), inUse = (lv.channels || []).length;
    const talking = (lv.channels || []).reduce((n, c) => n + ((c.talkers || []).length), 0);
    win.setMid(`<span class="nz-dot${talking ? ' red' : ''}"></span><p>${fill(esc(L('mid', '{r} radios switched on · {c} channels in use')), { r: `<b>${radios}</b>`, c: `<b>${inUse}</b>` })}${talking ? ` · ${fill(esc(L('mid_talk', '{n} talking')), { n: `<b>${talking}</b>` })}` : ''}</p>`);
  }
  function renderStatus() {
    const n = edits();
    const b = badRows();
    const bad = b.ch.length + b.veh.length;
    let pend;
    if (saving) pend = `<span class="ad-pend busy"><i class="spin"></i>${esc(L('st_saving', 'Sending to the server…'))}</span>`;
    else if (!n) pend = `<span class="ad-pend ok"><span class="nz-dot"></span>${esc(L('st_clean', 'Matches the server'))}</span>`;
    else pend = `<span class="ad-pend ${bad ? 'bad' : 'wait'}"><span class="nz-dot ${bad ? 'red' : 'amber'}"></span>${fill(esc(n === 1 ? L('st_edits1', '{n} edit waiting for Save') : L('st_edits', '{n} edits waiting for Save')), { n: `<b>${n}</b>` })}${bad ? ` · ${fill(esc(L('st_bad', '{n} to fix')), { n: `<b>${bad}</b>` })}` : ''}</span>`;
    win.setStatus([{ key: 'ESC', label: L('k_close', 'Close') }, { key: 'CTRL+S', label: L('k_save', 'Save') }, { key: 'CTRL+F', label: L('k_find', 'Find') }], pend);
    const sv = win.act.querySelector('.ad-save'), dc = win.act.querySelector('.ad-discard');
    sv.disabled = saving || !n;
    sv.classList.toggle('busy', saving);
    sv.querySelector('span').textContent = saving ? L('saving', 'Saving') : n ? fill(L('save_n', 'Save {n}'), { n }) : L('save', 'Save');
    dc.style.display = n && !saving ? '' : 'none';
  }
  function refreshChrome() {
    renderSide();
    renderStatus();
    if (banner && banner.kind === 'fix') {
      const b = badRows(), n = b.ch.length + b.veh.length;
      if (!n) setBanner(null);
      else if (n !== banner.n) setBanner(fixBanner(n));
    }
  }

  function go(id) {
    page = id;
    closeMenu();
    renderSide();
    render();
    stopLive();
    if (id === 'live') startLive();
    if (id === 'vehicles' && NZR.inGame) {
      NZR.post('admin:current', {}).then(r => { if (r && r.ok !== false && page === 'vehicles') { D.current = r.current || null; renderCurrent(); } });
    }
  }

  function render() {
    if (!win) return;
    win.main.className = `w-main ad-main pg-${page}`;
    if (page === 'channels') renderChannels();
    else if (page === 'vehicles') renderVehicles();
    else renderLive();
  }

  const bannerHTML = () => (banner ? `<div class="ad-banner ${banner.tone || 'red'}">${icon(banner.tone === 'amber' ? 'alert' : 'error')}<p>${esc(banner.text)}</p><button class="ad-ib" data-act="banner-x" title="${esc(L('dismiss', 'Dismiss'))}">${icon('x')}</button></div>` : '');
  function setBanner(b) {
    banner = b;
    const old = win && win.main.querySelector('.ad-banner');
    if (!win) return;
    const html = bannerHTML();
    if (old) { if (html) old.outerHTML = html; else old.remove(); return; }
    if (html) { const head = win.main.querySelector('.w-head'); if (head) head.insertAdjacentHTML('afterend', html); }
  }

  const counter = (label, value, tone) => `<div class="ad-cnt ${tone || ''}"><b>${esc(String(value))}</b><em>${esc(label)}</em></div>`;

  /* ═══════════════ CHANNELS ═══════════════ */
  function chHeadCounts() {
    const live = ch.filter(r => !r.deleted);
    return `${counter(L('c_rules', 'Rules'), live.length)}${counter(L('c_code', 'Code-locked'), live.filter(r => r.access === 'code').length, 'amber')}${counter(L('c_job', 'Job-only'), live.filter(r => r.access === 'job').length, 'teal')}`;
  }
  function renderChannels() {
    const m = lim();
    const live = ch.filter(r => !r.deleted);
    const n = a => live.filter(r => a === 'all' || r.access === a).length;
    win.main.innerHTML = `
      <div class="w-head"><div><h1>${esc(L('ch_h', 'Channel rules'))}</h1><p>${esc(fill(L('ch_p', 'Lock a single frequency with a 4-digit code or to jobs. Anything not listed is open to everyone from {min} to {max} MHz, apart from the fixed ranges.'), { min: Number(m.min).toFixed(2), max: Number(m.max).toFixed(2) }))}</p></div>
        <div class="ad-cnts" data-cnt="ch">${chHeadCounts()}</div></div>
      ${bannerHTML()}
      <div class="ad-tools">
        <label class="ad-search">${icon('search')}<input class="ad-in" data-f="q" placeholder="${esc(L('ch_find', 'Find a frequency, name or job'))}" value="${esc(flt.q)}" spellcheck="false"></label>
        <div class="seg ad-filter">${['all', 'open', 'code', 'job'].map(a => `<button data-flt="${a}" class="${flt.access === a ? 'on' : ''}">${esc(L(`f_${a}`, { all: 'All', open: 'Open', code: 'Code', job: 'Job' }[a]))}<span>${n(a)}</span></button>`).join('')}</div>
        <button class="btn-line btn-sm" data-act="add-ch">${icon('plus')}${esc(L('ch_add', 'New rule'))}</button>
      </div>
      <div class="ad-table ch">
        <div class="ad-th"><span>${esc(L('th_freq', 'Frequency'))}</span><span>${esc(L('th_access', 'Who gets in'))}</span><span>${esc(L('th_detail', 'Code / jobs'))}</span><span>${esc(L('th_name', 'Name'))}</span><span></span><span></span></div>
        <div class="ad-rows nzr-scroll" data-list="ch"></div>
      </div>`;
    fillChRows();
  }
  function chVisible(r) {
    if (flt.access !== 'all' && r.access !== flt.access && !(r.orig === null)) return false;
    const s = flt.q.trim().toLowerCase();
    if (!s || r.orig === null) return true;
    return (r.freq || '').toLowerCase().includes(s) || r.label.toLowerCase().includes(s) || r.jobs.some(j => j.name.toLowerCase().includes(s) || ((jobIndex.get(j.name) || {}).label || '').toLowerCase().includes(s));
  }
  function fillChRows() {
    const list = q('[data-list="ch"]');
    if (!list) return;
    const rows = ch.filter(chVisible);
    if (!ch.length) {
      list.innerHTML = empty('lock', L('ch_empty', 'No rules yet'), L('ch_empty_sub', 'Every frequency is open. Add a rule to lock one with a code or to a job.'), `<button class="btn-line btn-sm" data-act="add-ch">${icon('plus')}${esc(L('ch_add', 'New rule'))}</button>`);
      return;
    }
    if (!rows.length) { list.innerHTML = empty('search', L('none_match', 'Nothing matches'), L('none_match_sub', 'Try another search or filter.')); return; }
    const cc = chCounts();
    list.innerHTML = rows.map(r => chRowHTML(r, cc)).join('');
  }
  function empty(ic, title, sub, extra) {
    return `<div class="nz-empty ad-empty">${icon(ic)}<b>${esc(title)}</b><span>${esc(sub)}</span>${extra || ''}</div>`;
  }
  function jobLabel(name) { const j = jobIndex.get(name); return j && j.label ? j.label : name; }
  function gradeLabel(name, g) {
    const j = jobIndex.get(name);
    const gr = j && j.grades.find(x => x.grade === g);
    return gr && gr.label ? gr.label : null;
  }
  function chDetail(r) {
    if (r.access === 'open') return `<span class="ad-open">${icon('unlock')}${esc(L('open_txt', 'Anyone can tune in'))}</span>`;
    if (r.access === 'code') {
      return `<span class="ad-code"><span class="ad-codebox"><input class="ad-in nzr-mono" data-f="code" type="${r.reveal ? 'text' : 'password'}" inputmode="numeric" maxlength="4" placeholder="····" value="${esc(r.code)}" autocomplete="off" spellcheck="false">` +
        `<button class="ad-ib" data-act="reveal" title="${esc(r.reveal ? L('hide', 'Hide the code') : L('show', 'Show the code'))}">${icon(r.reveal ? 'eye-off' : 'eye')}</button></span>` +
        `<span class="ad-pins">${[0, 1, 2, 3].map(i => `<i class="${i < r.code.length ? 'on' : ''}"></i>`).join('')}</span></span>`;
    }
    const chips = r.jobs.map(j => {
      const gl = gradeLabel(j.name, j.grade);
      const tip = `${jobLabel(j.name)} · ${fill(L('from_grade', 'grade {g} and up'), { g: j.grade })}${gl ? ` (${gl})` : ''}`;
      return `<span class="ad-jchip" title="${esc(tip)}"><b>${esc(j.name)}</b><button class="gr" data-menu="grade" data-job="${esc(j.name)}">≥ ${j.grade}</button><button class="x" data-act="job-x" data-job="${esc(j.name)}" title="${esc(L('job_rm', 'Take this job off'))}">${icon('x')}</button></span>`;
    }).join('');
    const add = r.jobs.length
      ? `<button class="ad-jadd ic" data-menu="job" title="${esc(L('job_more', 'Add another job'))}">${icon('plus')}</button>`
      : `<button class="ad-jadd" data-menu="job">${icon('plus')}${esc(L('job_add', 'Add a job'))}</button>`;
    return `<span class="ad-jobs">${chips}${add}</span>`;
  }
  function chState(r, issues) {
    if (r.deleted) return `<span class="ad-st del">${esc(L('st_del', 'Removing'))}</span>`;
    if (issues.length) return `<span class="ad-st bad">${icon('alert')}</span>`;
    if (r.orig === null) return `<span class="ad-st new">${esc(L('st_new', 'New'))}</span>`;
    if (snapCh(r) !== r.orig) return `<span class="ad-st chg">${esc(L('st_chg', 'Edited'))}</span>`;
    return '';
  }
  function msgsHTML(issues, notes) {
    if (!issues.length && !notes.length) return '';
    return `<div class="ad-msg">${issues.map(i => `<span class="e">${icon('error')}${esc(i.msg)}</span>`).join('')}${notes.map(n => `<span class="n">${icon('info')}${esc(n.msg)}</span>`).join('')}</div>`;
  }
  function chRowHTML(r, cc) {
    const issues = chIssues(r, cc), notes = issues.length ? [] : chNotes(r);
    const bad = new Set(issues.map(i => i.f));
    const cls = ['ad-row', `acc-${r.access}`, r.deleted ? 'del' : '', r.orig === null ? 'new' : (!r.deleted && snapCh(r) !== r.orig ? 'chg' : ''), issues.length ? 'bad' : ''].join(' ');
    const tip = r.by ? ` title="${esc(fill(L('by', 'Last set by {who}'), { who: r.by }))}"` : '';
    return `<div class="${cls}" data-uid="${r.uid}"${tip}>
      <div class="c-f"><span class="ad-fq ${bad.has('freq') ? 'bad' : ''}"><input class="ad-in nzr-mono" data-f="freq" value="${esc(r.freq)}" maxlength="6" placeholder="000.00" spellcheck="false" ${r.deleted ? 'disabled' : ''}><em>MHz</em></span></div>
      <div class="c-a"><div class="seg ad-acc">${ACCESS.map(a => `<button data-acc="${a}" class="${r.access === a ? 'on' : ''}" ${r.deleted ? 'disabled' : ''}>${icon({ open: 'unlock', code: 'key', job: 'badge' }[a])}${esc(L(`a_${a}`, { open: 'Open', code: 'Code', job: 'Job' }[a]))}</button>`).join('')}</div></div>
      <div class="c-d ${bad.has('code') || bad.has('jobs') ? 'bad' : ''}">${chDetail(r)}</div>
      <div class="c-l"><input class="ad-in ${bad.has('label') ? 'bad' : ''}" data-f="label" value="${esc(r.label)}" maxlength="${lim().label}" placeholder="${esc(L('unnamed', 'Unnamed'))}" spellcheck="false" ${r.deleted ? 'disabled' : ''}></div>
      <div class="c-s">${chState(r, issues)}</div>
      <div class="c-x">${r.deleted ? `<button class="ad-ib" data-act="restore" title="${esc(L('restore', 'Keep this rule'))}">${icon('rot-l')}</button>` : `<button class="ad-ib red" data-act="del" title="${esc(L('del_rule', 'Remove this rule'))}">${icon('trash')}</button>`}</div>
      ${msgsHTML(issues, notes)}
    </div>`;
  }
  // re-check one row in place (keeps the caret where it is while typing)
  function refreshChRow(r, full) {
    const el = r && q(`.ad-row[data-uid="${r.uid}"]`);
    const cc = chCounts();
    if (!el) {
      // nothing to patch in place
    } else if (full) {
      el.outerHTML = chRowHTML(r, cc);
    } else {
      const issues = chIssues(r, cc), notes = issues.length ? [] : chNotes(r);
      const bad = new Set(issues.map(i => i.f));
      el.className = ['ad-row', `acc-${r.access}`, r.deleted ? 'del' : '', r.orig === null ? 'new' : (!r.deleted && snapCh(r) !== r.orig ? 'chg' : ''), issues.length ? 'bad' : ''].join(' ');
      el.querySelector('.ad-fq').classList.toggle('bad', bad.has('freq'));
      el.querySelector('.c-d').classList.toggle('bad', bad.has('code') || bad.has('jobs'));
      el.querySelector('[data-f="label"]').classList.toggle('bad', bad.has('label'));
      el.querySelector('.c-s').innerHTML = chState(r, issues);
      const m = el.querySelector('.ad-msg');
      const html = msgsHTML(issues, notes);
      if (m) { if (html) m.outerHTML = html; else m.remove(); } else if (html) el.insertAdjacentHTML('beforeend', html);
      el.querySelectorAll('.ad-pins i').forEach((p, i) => p.classList.toggle('on', i < r.code.length));
    }
    // a duplicate elsewhere may have appeared or gone away
    ch.forEach(o => {
      if (o === r) return;
      const oe = q(`.ad-row[data-uid="${o.uid}"]`);
      if (!oe) return;
      const isBad = chIssues(o, cc).length > 0;
      if (isBad !== oe.classList.contains('bad')) oe.outerHTML = chRowHTML(o, cc);
    });
    const cnt = q('[data-cnt="ch"]');
    if (cnt) cnt.innerHTML = chHeadCounts();
    const live = ch.filter(x => !x.deleted);
    root.querySelectorAll('.ad-filter button').forEach(b => { const a = b.dataset.flt; const s = b.querySelector('span'); if (s) s.textContent = live.filter(x => a === 'all' || x.access === a).length; });
    refreshChrome();
  }

  /* ═══════════════ VEHICLES ═══════════════ */
  function vHeadCounts() {
    const live = veh.filter(r => !r.deleted);
    const far = live.reduce((m, r) => Math.max(m, r.range), 0);
    const near = live.reduce((m, r) => Math.min(m, r.range), 9);
    return `${counter(L('c_cars', 'Cars listed'), live.length)}${counter(L('c_far', 'Longest reach'), live.length ? `×${far.toFixed(2)}` : '-', 'teal')}${counter(L('c_near', 'Shortest'), live.length ? `×${near.toFixed(2)}` : '-')}`;
  }
  function renderVehicles() {
    win.main.innerHTML = `
      <div class="w-head"><div><h1>${esc(L('v_h', 'Radio cars'))}</h1><p>${esc(L('v_p', 'Cars on this list get the dash head unit on top of the classes and models in the config. Range scales how far their head unit carries: ×1.00 is the normal reach.'))}</p></div>
        <div class="ad-cnts" data-cnt="veh">${vHeadCounts()}</div></div>
      ${bannerHTML()}
      <div class="ad-cur-slot"></div>
      <div class="ad-tools">
        <label class="ad-search">${icon('search')}<input class="ad-in" data-f="vq" placeholder="${esc(L('v_find', 'Find a spawn name or label'))}" value="${esc(flt.vq)}" spellcheck="false"></label>
        <button class="btn-line btn-sm" data-act="add-v">${icon('plus')}${esc(L('v_add', 'New car'))}</button>
      </div>
      <div class="ad-table veh">
        <div class="ad-th"><span>${esc(L('th_model', 'Spawn name'))}</span><span>${esc(L('th_label', 'Label'))}</span><span>${esc(L('th_range', 'Range'))}</span><span></span><span></span></div>
        <div class="ad-rows nzr-scroll" data-list="veh"></div>
      </div>`;
    renderCurrent();
    fillVRows();
  }
  function renderCurrent() {
    const slot = q('.ad-cur-slot');
    if (!slot) return;
    const c = D.current;
    if (!c || !c.model) { slot.innerHTML = ''; return; }
    const model = String(c.model).toLowerCase();
    const listed = veh.some(r => !r.deleted && r.model.trim().toLowerCase() === model);
    const sub = listed ? L('cur_listed', 'Already on this list') : c.radio ? L('cur_radio', 'Has a head unit already through the config, add it to tune its range') : L('cur_none', 'No head unit in it yet');
    slot.innerHTML = `<div class="ad-cur nzr-brk"><span class="nz-tile">${icon('car')}</span>
      <div class="txt"><b>${fill(esc(L('cur_in', 'You are sitting in {car}')), { car: `<em>${esc(c.label || model)}</em>` })}<code class="nzr-mono">${esc(model)}</code></b><span>${esc(sub)}</span></div>
      <button class="${listed ? 'btn-line' : 'btn-teal'} btn-sm" data-act="add-cur" ${listed ? 'disabled' : ''}>${icon(listed ? 'check' : 'plus')}${esc(listed ? L('cur_on', 'On the list') : L('cur_add', 'Add this car'))}</button></div>`;
  }
  function vVisible(r) {
    const s = flt.vq.trim().toLowerCase();
    return !s || r.orig === null || r.model.toLowerCase().includes(s) || r.label.toLowerCase().includes(s);
  }
  function fillVRows() {
    const list = q('[data-list="veh"]');
    if (!list) return;
    if (!veh.length) {
      list.innerHTML = empty('car', L('v_empty', 'No cars listed'), L('v_empty_sub', 'The config decides which cars get a head unit. Add one here to give it a dash radio or a longer reach.'), `<button class="btn-line btn-sm" data-act="add-v">${icon('plus')}${esc(L('v_add', 'New car'))}</button>`);
      return;
    }
    const rows = veh.filter(vVisible);
    if (!rows.length) { list.innerHTML = empty('search', L('none_match', 'Nothing matches'), L('none_match_sub', 'Try another search or filter.')); return; }
    const vc = vCounts();
    list.innerHTML = rows.map(r => vRowHTML(r, vc)).join('');
    rows.forEach(bindSlider);
  }
  function vState(r, issues) {
    if (r.deleted) return `<span class="ad-st del">${esc(L('st_del', 'Removing'))}</span>`;
    if (issues.length) return `<span class="ad-st bad">${icon('alert')}</span>`;
    if (r.orig === null) return `<span class="ad-st new">${esc(L('st_new', 'New'))}</span>`;
    if (snapV(r) !== r.orig) return `<span class="ad-st chg">${esc(L('st_chg', 'Edited'))}</span>`;
    return '';
  }
  function vRowHTML(r, vc) {
    const issues = vIssues(r, vc);
    const bad = new Set(issues.map(i => i.f));
    const cls = ['ad-row', 'v', r.deleted ? 'del' : '', r.orig === null ? 'new' : (!r.deleted && snapV(r) !== r.orig ? 'chg' : ''), issues.length ? 'bad' : ''].join(' ');
    return `<div class="${cls}" data-uid="${r.uid}">
      <div class="c-f"><input class="ad-in nzr-mono ${bad.has('model') ? 'bad' : ''}" data-f="model" value="${esc(r.model)}" maxlength="${lim().model}" placeholder="${esc(L('model_ph', 'spawn name'))}" spellcheck="false" ${r.deleted ? 'disabled' : ''}></div>
      <div class="c-l"><input class="ad-in ${bad.has('label') ? 'bad' : ''}" data-f="vlabel" value="${esc(r.label)}" maxlength="${lim().label}" placeholder="${esc(L('unnamed', 'Unnamed'))}" spellcheck="false" ${r.deleted ? 'disabled' : ''}></div>
      <div class="c-r"><span class="ad-rng" data-slider></span></div>
      <div class="c-s">${vState(r, issues)}</div>
      <div class="c-x">${r.deleted ? `<button class="ad-ib" data-act="restore" title="${esc(L('restore_v', 'Keep this car'))}">${icon('rot-l')}</button>` : `<button class="ad-ib red" data-act="del" title="${esc(L('del_v', 'Take this car off'))}">${icon('trash')}</button>`}</div>
      ${msgsHTML(issues, [])}
    </div>`;
  }
  function bindSlider(r) {
    const el = q(`.ad-row[data-uid="${r.uid}"] [data-slider]`);
    if (!el) return;
    const s = NZR.ui.Slider(el, { min: 0.5, max: 3, step: 0.05, value: r.range, format: v => `×${Number(v).toFixed(2)}`, onChange: v => { r.range = Math.round(v * 20) / 20; refreshVRow(r); } });
    if (r.deleted) s.el.querySelector('input').disabled = true;
  }
  function refreshVRow(r, full) {
    const el = r && q(`.ad-row[data-uid="${r.uid}"]`);
    const vc = vCounts();
    if (el) {
      if (full) { el.outerHTML = vRowHTML(r, vc); bindSlider(r); } else {
        const issues = vIssues(r, vc);
        const bad = new Set(issues.map(i => i.f));
        el.className = ['ad-row', 'v', r.deleted ? 'del' : '', r.orig === null ? 'new' : (!r.deleted && snapV(r) !== r.orig ? 'chg' : ''), issues.length ? 'bad' : ''].join(' ');
        el.querySelector('[data-f="model"]').classList.toggle('bad', bad.has('model'));
        el.querySelector('[data-f="vlabel"]').classList.toggle('bad', bad.has('label'));
        el.querySelector('.c-s').innerHTML = vState(r, issues);
        const m = el.querySelector('.ad-msg');
        const html = msgsHTML(issues, []);
        if (m) { if (html) m.outerHTML = html; else m.remove(); } else if (html) el.insertAdjacentHTML('beforeend', html);
      }
    }
    veh.forEach(o => {
      if (o === r) return;
      const oe = q(`.ad-row[data-uid="${o.uid}"]`);
      if (!oe) return;
      const isBad = vIssues(o, vc).length > 0;
      if (isBad !== oe.classList.contains('bad')) { oe.outerHTML = vRowHTML(o, vc); bindSlider(o); }
    });
    const cnt = q('[data-cnt="veh"]');
    if (cnt) cnt.innerHTML = vHeadCounts();
    renderCurrent();
    refreshChrome();
  }

  /* ═══════════════ LIVE ═══════════════ */
  function renderLive() {
    const lv = D.live || {};
    const chans = lv.channels || [], jams = lv.jammers || [];
    const talking = chans.reduce((n, c) => n + ((c.talkers || []).length), 0);
    const tile = (ic, label, value, tone) => `<div class="w-stat ad-stat ${tone || ''}"><span class="nz-tile ${tone || ''}">${icon(ic)}</span><div><span>${esc(label)}</span><b>${esc(String(value))}</b></div></div>`;
    win.main.innerHTML = `
      <div class="w-head"><div><h1>${esc(L('lv_h', 'Live traffic'))}</h1><p>${esc(L('lv_p', 'Who is on which channel right now, who is talking and every jammer that is out. Refreshes every few seconds.'))}</p></div>
        <div class="ad-upd"><span class="nzr-mono" data-upd>${esc(updText())}</span><button class="btn-line btn-sm" data-act="live">${icon('refresh')}${esc(L('refresh', 'Refresh'))}</button></div></div>
      ${bannerHTML()}
      <div class="w-stats ad-stats">
        ${tile('walkie', L('s_radios', 'Radios switched on'), num(lv.radios, 0))}
        ${tile('frequency', L('s_chans', 'Channels in use'), chans.length)}
        ${tile('mic', L('s_talk', 'Talking now'), talking, talking ? 'red' : 'mute')}
        ${tile('jammer', L('s_jams', 'Jammers out'), jams.length, jams.length ? 'amber' : 'mute')}
      </div>
      <div class="ad-live">
        <section class="w-panel"><div class="w-phead"><div><h2>${esc(L('lv_ch', 'Channels in use'))}</h2><p>${esc(L('lv_ch_p', 'Handhelds and head units tuned in, by frequency'))}</p></div></div>
          <div class="w-pbody nzr-scroll">${chans.length ? chans.map(liveChHTML).join('') : empty('broadcast', L('lv_quiet', 'All quiet'), L('lv_quiet_sub', 'No radio is tuned to a channel right now.'))}</div></section>
        <section class="w-panel"><div class="w-phead"><div><h2>${esc(L('lv_jam', 'Jammers'))}</h2><p>${esc(L('lv_jam_p', 'Placed units, soonest to run out first'))}</p></div></div>
          <div class="w-pbody nzr-scroll" data-list="jam">${jams.length ? jams.map(liveJamHTML).join('') : empty('jammer', L('lv_nojam', 'No jammers out'), L('lv_nojam_sub', 'Nobody has set one down.'))}</div></section>
      </div>`;
  }
  function liveChHTML(c) {
    const k = fkey(c.freq) || String(c.freq);
    const acc = ACCESS.includes(c.access) ? c.access : 'open';
    const tag = { open: ['off', L('a_open', 'Open')], code: ['warn', L('a_code', 'Code')], job: ['live', L('a_job', 'Job')] }[acc];
    const talkers = c.talkers || [];
    return `<div class="w-row ad-lch ${talkers.length ? 'on' : ''}">
      <div class="fq nzr-mono">${esc(k)}<em>MHz</em></div>
      <div class="txt"><b>${esc(c.label || L('unnamed', 'Unnamed'))}</b>
        <span class="tk">${talkers.length ? talkers.map(tk => `<i class="${tk.emergency ? 'em' : ''}">${icon(tk.device === 'vehicle' ? 'car' : 'mic')}${esc(tk.name || `#${tk.id}`)}${tk.callsign ? `<small>${esc(tk.callsign)}</small>` : ''}</i>`).join('') : esc(L('lv_nobody', 'Nobody talking'))}</span></div>
      <span class="nz-tag ${tag[0]}">${esc(tag[1])}</span>
      <span class="ad-n" title="${esc(L('lv_hand', 'Handhelds'))}">${icon('walkie')}<b>${num(c.members, 0)}</b></span>
      <span class="ad-n" title="${esc(L('lv_cars', 'Head units'))}">${icon('car')}<b>${num(c.vehicles, 0)}</b></span>
    </div>`;
  }
  function jamLeft(j) { return Math.max(0, Math.round((num(j._end, 0) - Date.now()) / 1000)); }
  // 'expires' = seconds left when the server answered: turn it into a local end time
  function stamp(lv) {
    const nowS = Date.now() / 1000;
    lv = lv && typeof lv === 'object' ? lv : {};
    lv.channels = arr(lv.channels);
    lv.channels.forEach(c => { c.talkers = arr(c && c.talkers); });
    lv.jammers = arr(lv.jammers);
    lv.jammers.forEach(j => {
      const left = j.expires !== undefined && j.expires !== null ? num(j.expires, 0) : Math.max(0, num(j.e, 0) - nowS);
      j._end = Date.now() + left * 1000;
    });
    return lv;
  }
  function liveJamHTML(j) {
    const code = CODES[j.type] || 'JX';
    const left = jamLeft(j);
    const total = j.placed ? Math.max(1, num(j.e, 0) - num(j.placed, 0)) : 0;
    const frac = total ? clamp(left / total, 0, 1) : null;
    const owner = j.owner ? `${esc(j.owner)}${j.ownerId ? ` <small>#${esc(String(j.ownerId))}</small>` : ` <small>${esc(L('offline', 'offline'))}</small>`}` : esc(L('nobody', 'Unknown'));
    return `<div class="w-row ad-ljam" data-jam="${esc(j.id)}">
      <span class="ad-jcode ${j.type === 'heavy' ? 'hot' : ''}">${esc(code)}</span>
      <div class="txt"><b>${esc(j.label || code)}</b><span>${icon('user')}${owner}</span></div>
      <div class="ad-left"><b class="nzr-mono" data-left>${esc(NZR.fmt.time(left))}</b>${frac !== null ? `<span class="mtr ${frac < 0.2 ? 'red' : 'amber'}"><i style="width:${(frac * 100).toFixed(1)}%"></i></span>` : `<em>${esc(L('left', 'left'))}</em>`}</div>
      <button class="ad-ib" data-act="mark" title="${esc(`${L('mark', 'Set a waypoint')} · ${Math.round(num(j.x, 0))}, ${Math.round(num(j.y, 0))}`)}">${icon('pin')}</button>
      <button class="ad-ib rm" data-act="jam-rm" title="${esc(L('remove_jam', 'Take it down'))}">${icon('trash')}</button>
    </div>`;
  }
  function updText() {
    if (!liveAt) return '';
    const s = Math.max(0, Math.round((Date.now() - liveAt) / 1000));
    return s < 2 ? L('upd_now', 'updated just now') : fill(L('upd_s', 'updated {s}s ago'), { s });
  }
  function setLive(lv) {
    D.live = stamp(lv || { channels: [], jammers: [], radios: 0 });
    liveAt = Date.now();
    renderMid();
    renderSide();
    if (page === 'live') {
      const sc = [...win.main.querySelectorAll('.w-pbody')].map(e => e.scrollTop);
      renderLive();
      win.main.querySelectorAll('.w-pbody').forEach((e, i) => { e.scrollTop = sc[i] || 0; });
    }
  }
  async function pullLive() {
    if (liveBusy) return;
    liveBusy = true;
    const r = await NZR.post('admin:live', {});
    liveBusy = false;
    if (!app || !NZR.isOpen('admin')) return;
    if (r && r.ok && r.live) setLive(r.live);
  }
  function startLive() {
    stopLive();
    liveTimer = setInterval(pullLive, LIVE_EVERY);
    tickTimer = setInterval(() => {
      if (page !== 'live' || !win) return;
      const u = win.main.querySelector('[data-upd]'); if (u) u.textContent = updText();
      ((D.live && D.live.jammers) || []).forEach(j => {
        const el = win.main.querySelector(`[data-jam="${CSS.escape(String(j.id))}"] [data-left]`);
        if (el) el.textContent = NZR.fmt.time(jamLeft(j));
      });
    }, 1000);
  }
  function stopLive() { clearInterval(liveTimer); clearInterval(tickTimer); liveTimer = tickTimer = 0; }

  function removeJammer(id) {
    const j = ((D.live && D.live.jammers) || []).find(x => String(x.id) === String(id));
    if (!j) return;
    const code = CODES[j.type] || 'JX';
    modalKind = 'jam';
    modal = NZR.ui.Modal({
      host: root, icon: 'jammer', tone: 'red',
      title: L('rm_h', 'Take this jammer down?'),
      text: fill(L('rm_t', 'The **{code}** {owner} goes away for everyone. Its owner does not get it back.'), { code, owner: j.owner ? fill(L('rm_of', 'of {name}'), { name: j.owner }) : '' }),
      actions: [{ label: L('keep', 'Leave it'), kind: 'line' }, {
        label: L('remove', 'Remove'), kind: 'red',
        onClick: () => {
          NZR.post('admin:jammerRemove', { id: j.id }).then(r => {
            if (r && r.ok) {
              NZR.toast({ title: L('rm_ok', 'Jammer removed'), message: fill(L('rm_ok_t', '{code} is off the air.'), { code }), type: 'success' });
              D.live.jammers = D.live.jammers.filter(x => x !== j);
              setLive(D.live);
            } else {
              NZR.toast({ title: L('rm_fail', 'Not removed'), message: L('rm_fail_t', 'It may have run out or been taken already.'), type: 'error' });
              pullLive();
            }
          });
        },
      }],
    });
  }

  /* ═══════════════ DROPDOWN (job / grade picker) ═══════════════ */
  function closeMenu() { if (menuEl) menuEl.remove(); menuEl = null; menuState = null; }
  function openMenu(anchor, { title, items, search, placeholder, onPick, onFree }) {
    closeMenu();
    const z = NZR.zoom || 1;
    try { anchor.scrollIntoView({ block: 'nearest' }); } catch (_) { /* old CEF */ }
    const a = anchor.getBoundingClientRect(), rr = root.getBoundingClientRect();
    const wr = (win && win.el ? win.el : root).getBoundingClientRect();
    menuAt = performance.now();
    menuEl = document.createElement('div');
    menuEl.className = 'ad-menu nzr-pop';
    menuEl.innerHTML = `<div class="mh">${esc(title)}</div>${search ? `<label class="ms">${icon('search')}<input class="ad-in" placeholder="${esc(placeholder || '')}" spellcheck="false"></label>` : ''}<div class="ml nzr-scroll"></div>`;
    root.appendChild(menuEl);
    const list = menuEl.querySelector('.ml'), inp = menuEl.querySelector('input');
    menuState = { items, active: 0, shown: items, onPick, onFree };
    const draw = () => {
      const s = inp ? inp.value.trim().toLowerCase() : '';
      menuState.shown = s ? items.filter(i => `${i.v} ${i.label} ${i.sub || ''}`.toLowerCase().includes(s)) : items;
      menuState.active = clamp(menuState.active, 0, Math.max(0, menuState.shown.length - 1));
      list.innerHTML = menuState.shown.length
        ? menuState.shown.map((i, n) => `<button class="mi ${n === menuState.active ? 'act' : ''} ${i.on ? 'on' : ''}" data-i="${n}"><b>${esc(i.label)}</b>${i.sub ? `<em>${esc(i.sub)}</em>` : ''}${i.on ? icon('check') : ''}</button>`).join('')
        : `<p class="me">${esc(onFree && s ? fill(L('menu_free', 'Enter adds "{v}"'), { v: s }) : L('menu_none', 'Nothing left to add'))}</p>`;
    };
    draw();
    list.addEventListener('mousedown', e => e.preventDefault());
    list.addEventListener('click', e => { const b = e.target.closest('.mi'); if (b) pick(Number(b.dataset.i)); });
    if (inp) { inp.addEventListener('input', () => { menuState.active = 0; draw(); }); setTimeout(() => inp.focus(), 0); }
    menuState.draw = draw;
    menuState.input = inp;
    // under the anchor (section px = screen px / zoom), above it when the window has no room
    // below; always kept inside the window
    const x = (a.left - rr.left) / z, yBelow = (a.bottom - rr.top) / z + 6, yAbove = (a.top - rr.top) / z - 6;
    const h = menuEl.offsetHeight, w = menuEl.offsetWidth;
    const top = (wr.top - rr.top) / z + 8, bottom = (wr.bottom - rr.top) / z - 8;
    const left = (wr.left - rr.left) / z + 8, right = (wr.right - rr.left) / z - 8;
    let y = yBelow + h <= bottom ? yBelow : (yAbove - h >= top ? yAbove - h : bottom - h);
    y = clamp(y, top, Math.max(top, bottom - h));
    menuEl.style.left = `${Math.round(clamp(x, left, Math.max(left, right - w)))}px`;
    menuEl.style.top = `${Math.round(y)}px`;
  }
  function pick(n) {
    if (!menuState) return;
    const it = menuState.shown[n];
    const st = menuState;
    if (it) { closeMenu(); st.onPick(it.v); return; }
    const s = st.input ? st.input.value.trim() : '';
    if (st.onFree && s) { closeMenu(); st.onFree(s); }
  }
  function menuKey(e) {
    if (!menuState) return false;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      menuState.active = clamp(menuState.active + (e.key === 'ArrowDown' ? 1 : -1), 0, Math.max(0, menuState.shown.length - 1));
      menuState.draw();
      const a = menuEl.querySelector('.mi.act'); if (a) a.scrollIntoView({ block: 'nearest' });
      return true;
    }
    if (e.key === 'Enter') { pick(menuState.active); return true; }
    return false;
  }
  function jobMenu(anchor, r) {
    const have = new Set(r.jobs.map(j => j.name));
    const items = [...jobIndex.values()].filter(j => !have.has(j.name)).map(j => ({ v: j.name, label: j.label || j.name, sub: j.name }));
    openMenu(anchor, {
      title: L('pick_job', 'Add a job'), items, search: true, placeholder: L('pick_job_ph', 'Find a job'),
      onPick: name => gradeMenu(anchor, r, name, true),
      onFree: name => { const n = name.toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 32); if (n) gradeMenu(anchor, r, n, true); },
    });
  }
  function gradeMenu(anchor, r, name, adding) {
    const j = jobIndex.get(name);
    const m = lim();
    const cur = r.jobs.find(x => x.name === name);
    const grades = j && j.grades.length ? j.grades : Array.from({ length: Math.min(m.grade, 10) + 1 }, (_, g) => ({ grade: g, label: '' }));
    const items = grades.filter(g => g.grade <= m.grade).map(g => ({ v: g.grade, label: `≥ ${g.grade}${g.label ? ` · ${g.label}` : ''}`, sub: g.grade === 0 ? L('every_grade', 'every grade') : '', on: cur && cur.grade === g.grade }));
    const host = document.body.contains(anchor) ? anchor : (q(`.ad-row[data-uid="${r.uid}"] .ad-jadd`) || anchor);
    openMenu(host, {
      title: fill(L('pick_grade', '{job}: lowest grade let in'), { job: (j && j.label) || name }), items,
      onPick: g => {
        if (cur) cur.grade = g; else if (adding) r.jobs.push({ name, grade: g });
        r.jobs.sort((a, b) => a.name.localeCompare(b.name));
        refreshChRow(r, true);
      },
    });
  }

  /* ═══════════════ EVENTS ═══════════════ */
  const rowOf = el => { const e = el.closest('.ad-row'); if (!e) return null; const id = e.dataset.uid; return ch.find(r => r.uid === id) || veh.find(r => r.uid === id) || null; };
  const isCh = r => ch.includes(r);

  function onInput(e) {
    const f = e.target.dataset && e.target.dataset.f;
    if (!f) return;
    if (f === 'q') { flt.q = e.target.value; fillChRows(); return; }
    if (f === 'vq') { flt.vq = e.target.value; fillVRows(); return; }
    const r = rowOf(e.target);
    if (!r) return;
    if (f === 'freq') { const v = e.target.value.replace(/[^0-9.,]/g, ''); if (v !== e.target.value) e.target.value = v; r.freq = v; refreshChRow(r); }
    else if (f === 'code') { const v = e.target.value.replace(/\D/g, '').slice(0, 4); if (v !== e.target.value) e.target.value = v; r.code = v; refreshChRow(r); }
    else if (f === 'label') { r.label = e.target.value; refreshChRow(r); }
    else if (f === 'model') { const v = e.target.value.replace(/\s/g, ''); if (v !== e.target.value) e.target.value = v; r.model = v; refreshVRow(r); }
    else if (f === 'vlabel') { r.label = e.target.value; refreshVRow(r); }
  }
  function onBlur(e) {
    const f = e.target.dataset && e.target.dataset.f;
    if (f !== 'freq') return;
    const r = rowOf(e.target);
    if (!r || !FREQ_RE.test(r.freq)) return;
    const k = fkey(r.freq);
    if (k && k !== r.freq) { r.freq = k; e.target.value = k; refreshChRow(r); }
  }
  function onClick(e) {
    const b = e.target.closest('button');
    if (!b || b.disabled) return;
    const act = b.dataset.act;
    if (b.dataset.flt) {
      flt.access = b.dataset.flt;
      root.querySelectorAll('.ad-filter button').forEach(x => x.classList.toggle('on', x === b));
      fillChRows();
      return;
    }
    if (b.dataset.menu) {
      const r = rowOf(b);
      if (!r) return;
      if (b.dataset.menu === 'job') jobMenu(b, r);
      else gradeMenu(b, r, b.dataset.job, false);
      return;
    }
    if (b.dataset.acc) {
      const r = rowOf(b);
      if (!r || r.access === b.dataset.acc) return;
      r.access = b.dataset.acc;
      sfxKey();
      refreshChRow(r, true);
      if (r.access === 'code' && !r.code) { const i = q(`.ad-row[data-uid="${r.uid}"] [data-f="code"]`); if (i) i.focus(); }
      if (r.access === 'job' && !r.jobs.length) { const a = q(`.ad-row[data-uid="${r.uid}"] .ad-jadd`); if (a) jobMenu(a, r); }
      return;
    }
    if (!act) return;
    const r = rowOf(b);
    switch (act) {
      case 'banner-x': setBanner(null); break;
      case 'add-ch': addChannel(); break;
      case 'add-v': addVehicle(); break;
      case 'add-cur': if (D.current) addVehicle({ model: String(D.current.model).toLowerCase(), label: D.current.label || '', range_mult: 1 }); break;
      case 'reveal': if (r) { r.reveal = !r.reveal; refreshChRow(r, true); } break;
      case 'job-x': if (r) { r.jobs = r.jobs.filter(j => j.name !== b.dataset.job); refreshChRow(r, true); } break;
      case 'del': if (r) removeRow(r); break;
      case 'restore': if (r) { r.deleted = false; isCh(r) ? refreshChRow(r, true) : refreshVRow(r, true); } break;
      case 'live': pullLive(); break;
      case 'mark': {
        const id = b.closest('[data-jam]').dataset.jam;
        const j = ((D.live && D.live.jammers) || []).find(x => String(x.id) === id);
        if (j) NZR.post('admin:waypoint', { x: j.x, y: j.y }).then(res => { if (res && res.ok) NZR.toast({ title: L('wp', 'Waypoint set'), message: fill(L('wp_t', '{code} is marked on your map.'), { code: CODES[j.type] || 'JX' }), type: 'info' }); });
        break;
      }
      case 'jam-rm': removeJammer(b.closest('[data-jam]').dataset.jam); break;
      default: break;
    }
  }
  function sfxKey() { try { NZR.sfx.play('key', { volume: 0.4 }); } catch (_) { /* no audio */ } }

  function addChannel() {
    const m = lim();
    if (ch.filter(r => !r.deleted).length >= m.channels) { setBanner({ tone: 'amber', text: fill(L('e_max_ch', 'That is the limit of {n} rules. Remove one first.'), { n: m.channels }) }); return; }
    const r = chRow({ access: 'code' }, true);
    ch.unshift(r);
    if (flt.access !== 'all' || flt.q) { flt.access = 'all'; flt.q = ''; }
    if (page !== 'channels') go('channels'); else renderChannels();
    refreshChrome();
    const i = q(`.ad-row[data-uid="${r.uid}"] [data-f="freq"]`);
    if (i) i.focus();
  }
  function addVehicle(v) {
    const m = lim();
    if (veh.filter(r => !r.deleted).length >= m.vehicles) { setBanner({ tone: 'amber', text: fill(L('e_max_v', 'That is the limit of {n} cars. Remove one first.'), { n: m.vehicles }) }); return; }
    const r = vRow(v || { range_mult: 1 }, true);
    veh.unshift(r);
    flt.vq = '';
    if (page !== 'vehicles') go('vehicles'); else renderVehicles();
    refreshChrome();
    const i = q(`.ad-row[data-uid="${r.uid}"] [data-f="${v ? 'vlabel' : 'model'}"]`);
    if (i) i.focus();
  }
  function removeRow(r) {
    if (r.orig === null) {   // never saved: just drop it
      const wasCh = isCh(r);
      if (wasCh) { ch = ch.filter(x => x !== r); fillChRows(); refreshChRow(null); } else { veh = veh.filter(x => x !== r); fillVRows(); refreshVRow(null); }
      return;
    }
    r.deleted = true;
    if (isCh(r)) refreshChRow(r, true); else refreshVRow(r, true);
  }

  /* ═══════════════ SAVE / DISCARD / CLOSE ═══════════════ */
  function load(channels, vehicles) {
    if (channels) ch = arr(channels).map(c => chRow(c, false)).sort((a, b) => Number(a.freq) - Number(b.freq));
    if (vehicles) veh = arr(vehicles).map(v => vRow(v, false)).sort((a, b) => a.model.localeCompare(b.model));
  }
  function fixBanner(n) {
    return { tone: 'red', kind: 'fix', n, text: fill(n === 1 ? L('e_fix1', 'One row needs fixing before this can be saved. It is marked in red.') : L('e_fix', '{n} rows need fixing before this can be saved. They are marked in red.'), { n }) };
  }
  async function save() {
    if (saving) return;
    closeMenu();
    const nc = editsCh(), nv = editsV();
    if (!nc && !nv) return;
    const b = badRows();
    if (b.ch.length || b.veh.length) {
      const n = b.ch.length + b.veh.length;
      const target = b.ch.length ? 'channels' : 'vehicles';
      banner = fixBanner(n);
      if (page !== target) go(target); else setBanner(banner);
      if (target === 'channels' && (flt.q || flt.access !== 'all')) { flt.q = ''; flt.access = 'all'; renderChannels(); }
      if (target === 'vehicles' && flt.vq) { flt.vq = ''; renderVehicles(); }
      const first = q(`.ad-row[data-uid="${(b.ch[0] || b.veh[0]).uid}"]`);
      if (first) { first.scrollIntoView({ block: 'center' }); first.classList.remove('flash'); void first.offsetWidth; first.classList.add('flash'); }
      try { NZR.sfx.play('error'); } catch (_) { /* no audio */ }
      return;
    }
    const payload = {};
    if (nc) payload.channels = ch.filter(r => !r.deleted).map(chToServer);
    if (nv) payload.vehicles = veh.filter(r => !r.deleted).map(vToServer);
    saving = true;
    renderStatus();
    let res = null;
    try { res = await NZR.post('admin:save', payload); } catch (_) { res = null; }
    saving = false;
    if (!app || !NZR.isOpen('admin')) return;
    if (res && res.ok) {
      const nextCh = res.channels ? arr(res.channels) : (nc ? payload.channels : null);
      const nextV = res.vehicles ? arr(res.vehicles) : (nv ? payload.vehicles : null);
      if (nextCh) app.base.channels = nextCh;
      if (nextV) app.base.vehicles = nextV;
      load(nextCh, nextV);
      banner = null;
      render();
      refreshChrome();
      const parts = [];
      if (nc) parts.push(fill(L('ok_ch', '{n} channel rules'), { n: ch.length }));
      if (nv) parts.push(fill(L('ok_v', '{n} cars'), { n: veh.length }));
      NZR.toast({ title: L('ok', 'Saved'), message: fill(L('ok_t', '{what} now apply on the whole server.'), { what: parts.join(L('and', ' and ')) }), type: 'success' });
    } else {
      const msg = (res && (res.error || res.reason)) || L('e_save', 'The server did not answer. Nothing was changed, try again.');
      setBanner({ tone: 'red', text: typeof msg === 'string' ? msg : String(msg) });
      refreshChrome();
      try { NZR.sfx.play('error'); } catch (_) { /* no audio */ }
    }
  }
  function discard() {
    closeMenu();
    // rebuild from what the server last gave us (open or the last save)
    load(app.base.channels, app.base.vehicles);
    banner = null;
    render();
    refreshChrome();
  }
  const modalUp = () => !!(modal && modal.el && modal.el.isConnected);
  function tryClose() {
    if (modalUp()) {
      modal.close(); modal = null;
      if (modalKind === 'leave') NZR.close('admin');   // Esc a second time: they meant it
      return;
    }
    const n = edits();
    if (!n || saving) return NZR.close('admin');
    modalKind = 'leave';
    modal = NZR.ui.Modal({
      host: root, icon: 'alert', tone: 'red',
      title: L('leave_h', 'Close without saving?'),
      text: fill(n === 1 ? L('leave_t1', '**1 edit** has not reached the server and is lost if you close now.') : L('leave_t', '**{n} edits** have not reached the server and are lost if you close now.'), { n }),
      actions: [{ label: L('leave_keep', 'Keep editing'), kind: 'line' }, { label: L('leave_go', 'Close anyway'), kind: 'red', onClick: () => { setTimeout(() => NZR.close('admin'), 0); } }],
    });
  }

  // CTRL+S / CTRL+F work even while a text field has the focus
  window.addEventListener('keydown', e => {
    if (!NZR.isOpen('admin') || NZR.stack[NZR.stack.length - 1] !== 'admin') return;
    if (e.ctrlKey && (e.code === 'KeyS' || e.code === 'KeyF')) {
      e.preventDefault();
      if (e.code === 'KeyS') save();
      else { if (page === 'live') go('channels'); const i = q(page === 'vehicles' ? '[data-f="vq"]' : '[data-f="q"]'); if (i) { i.focus(); i.select(); } }
      return;
    }
    if (menuState && menuKey(e)) e.preventDefault();
  }, true);

  /* ═══════════════ APP ═══════════════ */
  app = NZR.app('admin', {
    full: true,
    escClose: false,
    modalKeys: true,
    keys: {
      Escape() {
        if (menuEl) { closeMenu(); return; }
        tryClose();
      },
    },
    init(el) {
      root = el;
      root.addEventListener('mousedown', e => { if (menuEl && !menuEl.contains(e.target) && !e.target.closest('[data-menu]')) closeMenu(); });
    },
    open(data) {
      data = data || {};
      D = {
        jobs: arr(data.jobs), limits: data.limits || {}, restricted: arr(data.restricted),
        live: stamp(data.live || { channels: [], jammers: [], radios: 0 }), current: data.current || null, me: data.me,
      };
      jobIndex = new Map();
      D.jobs.forEach(j => {
        if (!j || !j.name) return;
        const grades = arr(j.grades)
          .map(g => ({ grade: Math.round(num(g && g.grade, NaN)), label: g && g.label ? String(g.label) : '' }))
          .filter(g => Number.isFinite(g.grade)).sort((a, b) => a.grade - b.grade);
        jobIndex.set(String(j.name), { name: String(j.name), label: j.label ? String(j.label) : String(j.name), grades });
      });
      app.base = { channels: arr(data.channels), vehicles: arr(data.vehicles) };
      load(app.base.channels, app.base.vehicles);
      flt.q = ''; flt.access = 'all'; flt.vq = '';
      banner = null; saving = false; page = 'channels'; modal = null;
      liveAt = Date.now();
      build();
      renderMid();
      go('channels');
      refreshChrome();
    },
    close() {
      stopLive();
      closeMenu();
      if (modal && modal.el && modal.el.isConnected) modal.close();
      modal = null;
      if (win) win.destroy();
      win = null;
      root.innerHTML = '';
    },
    preview() {
      const now = Math.floor(Date.now() / 1000);
      const jobs = [
        { name: 'police', label: 'LSPD', grades: [{ grade: 0, label: 'Recruit' }, { grade: 1, label: 'Officer' }, { grade: 2, label: 'Sergeant' }, { grade: 3, label: 'Lieutenant' }, { grade: 4, label: 'Chief' }] },
        { name: 'sheriff', label: 'BCSO', grades: [{ grade: 0, label: 'Deputy' }, { grade: 1, label: 'Senior Deputy' }, { grade: 2, label: 'Sergeant' }, { grade: 3, label: 'Sheriff' }] },
        { name: 'ambulance', label: 'EMS', grades: [{ grade: 0, label: 'Trainee' }, { grade: 1, label: 'Paramedic' }, { grade: 2, label: 'Doctor' }, { grade: 3, label: 'Chief' }] },
        { name: 'fib', label: 'FIB', grades: [{ grade: 0, label: 'Agent' }, { grade: 1, label: 'Special Agent' }, { grade: 2, label: 'Director' }] },
        { name: 'mechanic', label: 'Benny\'s', grades: [{ grade: 0, label: 'Apprentice' }, { grade: 1, label: 'Mechanic' }, { grade: 2, label: 'Boss' }] },
        { name: 'taxi', label: 'Downtown Cab', grades: [{ grade: 0, label: 'Driver' }, { grade: 1, label: 'Dispatcher' }] },
        { name: 'lawyer', label: 'Legal', grades: [{ grade: 0, label: 'Associate' }, { grade: 1, label: 'Partner' }] },
      ];
      const data = {
        ok: true, jobs,
        channels: [
          { freq: '11.00', access: 'job', jobs: { police: 0, sheriff: 0 }, label: 'Joint Ops', updatedBy: 'Maya Reyes (license:4f1c…)' },
          { freq: '12.50', access: 'job', jobs: { police: 2 }, label: 'Command', updatedBy: 'Maya Reyes (license:4f1c…)' },
          { freq: '14.00', access: 'job', jobs: { ambulance: 0 }, label: 'EMS Dispatch' },
          { freq: '21.40', access: 'job', jobs: { fib: 1 }, label: 'Black Ops' },
          { freq: '88.80', access: 'code', code: '4471', label: 'Vagos' },
          { freq: '101.10', access: 'code', code: '0909', label: 'Lost MC' },
          { freq: '155.50', access: 'code', code: '2580', label: 'Night Market' },
          { freq: '312.00', access: 'job', jobs: { mechanic: 0, taxi: 1 }, label: 'Road Crews' },
          { freq: '420.00', access: 'open', label: 'Car Meet' },
          { freq: '5.25', access: 'code', code: '7788', label: 'Court Room' },
        ],
        vehicles: [
          { model: 'police', label: 'Cruiser', range_mult: 1.2 },
          { model: 'police3', label: 'Interceptor', range_mult: 1.35 },
          { model: 'sheriff2', label: 'Sheriff SUV', range_mult: 1.5 },
          { model: 'ambulance', label: 'Ambulance', range_mult: 1.25 },
          { model: 'fbi2', label: 'Unmarked SUV', range_mult: 1.8 },
          { model: 'riot', label: 'Riot Van', range_mult: 2.5 },
          { model: 'towtruck', label: 'Tow Truck', range_mult: 0.9 },
        ],
        live: {
          radios: 23,
          channels: [
            { freq: '11.00', label: 'Joint Ops', access: 'job', members: 6, vehicles: 3, talkers: [{ id: 7, name: 'Maya Reyes', callsign: '2A14', device: 'handheld' }] },
            { freq: '14.00', label: 'EMS Dispatch', access: 'job', members: 3, vehicles: 1, talkers: [] },
            { freq: '88.80', label: 'Vagos', access: 'code', members: 4, vehicles: 0, talkers: [{ id: 31, name: 'Dario Kostas', device: 'handheld' }] },
            { freq: '155.50', label: 'Night Market', access: 'code', members: 2, vehicles: 0, talkers: [] },
            { freq: '420.00', label: 'Car Meet', access: 'open', members: 7, vehicles: 2, talkers: [{ id: 52, name: 'Owen Price', device: 'vehicle' }, { id: 60, name: 'Sam Brooks', callsign: 'K9', device: 'handheld' }] },
            { freq: '600.25', label: '', access: 'open', members: 1, vehicles: 0, talkers: [] },
          ],
          jammers: [
            { id: 'j14', type: 'pocket', label: 'Pocket Jammer', owner: 'Dario Kostas', ownerId: 31, x: 412.6, y: -1630.2, z: 29.3, e: now + 214, placed: now - 686 },
            { id: 'j15', type: 'heavy', label: 'Cabinet Jammer', owner: 'Lena Ortiz', ownerId: null, x: -1120.4, y: -1520.9, z: 4.4, e: now + 1630, placed: now - 1070 },
            { id: 'j16', type: 'case', label: 'Field Jammer', owner: 'Tex Holloway', ownerId: 12, x: 1985.1, y: 3051.7, z: 47.2, e: now + 1290, placed: now - 510 },
          ],
        },
        limits: { channels: 300, vehicles: 200, jobs: 16, grade: 20, label: 32, model: 32, min: 1, max: 999.99 },
        restricted: [{ from: 1.0, to: 10.99, label: 'Emergency', jobs: { police: 0, sheriff: 0, ambulance: 0 } }],
        current: { model: 'police4', label: 'Unmarked Cruiser', radio: true },
        me: 12,
      };
      NZR.mock('admin:save', d => new Promise(res => setTimeout(() => res({
        ok: true,
        channels: d.channels ? d.channels.slice().sort((a, b) => Number(a.freq) - Number(b.freq)) : undefined,
        vehicles: d.vehicles ? d.vehicles.slice().sort((a, b) => a.model.localeCompare(b.model)) : undefined,
      }), 450)));
      NZR.mock('admin:live', () => {
        const lv = JSON.parse(JSON.stringify(data.live));
        lv.radios = 21 + Math.floor(Math.random() * 5);
        lv.channels.forEach(c => { c.members = Math.max(1, c.members + Math.round(Math.random() * 2 - 1)); });
        return { ok: true, live: lv };
      });
      NZR.mock('admin:jammerRemove', d => { data.live.jammers = data.live.jammers.filter(j => j.id !== d.id); return { ok: true }; });
      NZR.mock('admin:current', () => ({ ok: true, current: data.current }));
      NZR.mock('admin:waypoint', () => ({ ok: true }));
      NZR.demo('admin', data);
    },
  });
})();
