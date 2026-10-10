/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V2 · app panel
   vault · settings · pickers
   ═══════════════════════════════════════════════════════════ */
'use strict';

const app = $('#app'), body = $('#appBody');
Object.assign(S, { vault: null, tab: 'profile', lb: 'snatches', sel: null, bountyOpen: null, picker: null });

function setHead(title, sub, status) {
  $('#appTitle').textContent = title;
  $('#appSub').textContent = sub || '';
  $('#appVer').textContent = 'v' + (S.cfg.version || '2.0.0');
  $('#appStatus').innerHTML = status || '';
}

function openApp(view, data) {
  if (view === 'studio') return studioOpen(data || {});
  S.view = view;
  closeModal();
  app.hidden = false;
  app.classList.toggle('sm', view === 'products' || view === 'puton');
  const fr = $('.app-frame'); fr.style.animation = 'none'; void fr.offsetWidth; fr.style.animation = '';
  if (view === 'vault') {
    S.tab = (data && data.tab) || 'profile'; S.sel = null; S.bountyOpen = null;
    if (!TABS.some(([id]) => id === S.tab) && S.tab !== 'settings') S.tab = 'profile';
    body.innerHTML = loading(); loadVault();
  }
  else if (view === 'products') { S.picker = data; renderProducts(); }
  else if (view === 'puton') { S.picker = data; renderPutOn(); }
  clearInterval(S.timer);
  S.timer = setInterval(liveTick, 1000);
}

function closeApp(silent) {
  if (S.view === 'studio') return studioClose(silent);
  if (!S.view) return;
  S.view = null;
  app.hidden = true;
  closeModal();
  clearInterval(S.timer);
  if (!silent) post('close');
}

function loading() { return `<div class="view"><div class="empty"><i class="fa-solid fa-circle-notch fa-spin"></i>Loading</div></div>`; }

app.addEventListener('click', (e) => {
  const b = e.target.closest('[data-act]');
  if (!b || b.disabled) return;
  const act = b.dataset.act, v = b.dataset.v;
  ACT[act] && ACT[act](v, b, e);
});
app.addEventListener('input', (e) => {
  if (e.target.id === 'catQ') {
    S.cat.q = e.target.value;
    const grid = $('.cat-grid'), keep = grid ? grid.closest('.view').scrollTop : 0;
    $('#vview').innerHTML = VIEWS.catalog();
    const n = $('#catQ'); n.focus(); n.setSelectionRange(n.value.length, n.value.length);
    const v = $('#vview'); if (v) v.scrollTop = keep;
    return;
  }
  if (e.target.matches('[data-int]')) e.target.value = e.target.value.replace(/[^\d]/g, '').slice(0, 7);
  if (e.target.matches('[data-pref]')) prefInput(e.target);
});

/* live countdowns */
function liveTick() {
  $$('[data-until]').forEach((n) => {
    const u = Number(n.dataset.until);
    n.textContent = u > serverNow() ? left(u) : (n.dataset.done || '0:00');
  });
}

/* ═══════════════ VAULT ═══════════════ */
async function loadVault() {
  const d = await post('vaultFetch');
  if (!d || S.view !== 'vault') return;
  S.vault = d;
  S.skew = (d.now || Date.now() / 1000) - Date.now() / 1000;
  if (d.version) S.cfg.version = d.version;
  if (S.sel && !arr(d.wigs).some((w) => w.key === S.sel)) S.sel = null;
  await palette();
  renderVault();
}

const TABS = [
  ['profile', 'fa-user', 'Profile'],
  ['wigs', 'fa-box-archive', 'My Wigs'],
  ['catalog', 'fa-book-open', 'Catalog'],
  ['bounties', 'fa-crosshairs', 'Bounties'],
  ['leaders', 'fa-ranking-star', 'Leaderboard'],
  ['feed', 'fa-tower-broadcast', 'City Feed'],
];

function renderVault() {
  const d = S.vault; if (!d) return;
  const me = d.me;
  setHead('Wig Vault', `${me.title} · Level ${me.level} · ${me.name}`, vaultStatus());
  const tabs = TABS;
  const rail = tabs.map(([id, ic, lb]) => {
    let badge = '';
    if (id === 'wigs' && arr(d.wigs).length) badge = `<span class="badge">${arr(d.wigs).length}</span>`;
    if (id === 'bounties' && me.bountyOnMe) badge = `<span class="badge red">${money(me.bountyOnMe)}</span>`;
    return `<button class="rail-btn ${S.tab === id ? 'on' : ''}" data-act="tab" data-v="${id}"><i class="fa-solid ${ic}"></i>${lb}${badge}</button>`;
  }).join('');
  const st = me.stats;
  body.innerHTML = `<div class="rail">
      <div class="who"><div class="av">${esc(initials(me.name))}</div><div class="who-tx"><b>${esc(me.name)}</b><span>${esc(me.title)}</span></div></div>
      ${rail}
      <div class="rail-sep"></div>
      <button class="rail-btn ${S.tab === 'settings' ? 'on' : ''}" data-act="tab" data-v="settings"><i class="fa-solid fa-sliders"></i>Settings</button>
      <div class="rail-foot"><b>${num(st.snatches)}</b> snatched · <b>${num(st.defends)}</b> held<br><b>${money(st.earned)}</b> earned</div>
    </div>
    <div class="view ${S.tab === 'wigs' ? 'split' : ''}" id="vview">${(VIEWS[S.tab] || VIEWS.profile)()}</div>`;
  liveTick();
  paintSwatches(body);
}

function vaultStatus() {
  return `<span><span class="kc">ESC</span>Close</span><span><span class="kc"><i class="fa-solid fa-computer-mouse"></i></span>Select</span><span class="grow"></span><span>Wig Snatch <b>v${esc(S.cfg.version)}</b></span>`;
}

function statusChips(h) {
  const out = [];
  for (const [k, u] of Object.entries(h.status || {})) {
    const s = (S.cfg.statuses || {})[k] || { label: k, color: S.prefs.alert };
    out.push(`<span class="chip" style="${tintVars(s.color)}"><i class="fa-solid ${k === 'burn' ? 'fa-fire' : k === 'lice' ? 'fa-bug' : 'fa-hill-rockslide'}"></i>${esc(s.label)} · <span data-until="${u}">${left(u)}</span></span>`);
  }
  const f = h.face || {};
  if (f.brows) out.push(`<span class="chip t-warning"><i class="fa-solid fa-eye"></i>Eyebrows ${f.brows === 'gone' ? 'shaved' : 'thinned'}${f.u ? ` · <span data-until="${f.u}">${left(f.u)}</span>` : ''}</span>`);
  if (f.beard) out.push(`<span class="chip t-warning"><i class="fa-solid fa-face-smile"></i>Beard ${f.beard === 'gone' ? 'shaved' : 'trimmed'}</span>`);
  if (h.dye) out.push(`<span class="chip"><span class="swatch sm" data-hc="${h.dye.c}"></span>Dyed</span>`);
  return out;
}

function hairCard(me) {
  const h = me.hair || {};
  let icon = 'fa-user', title = 'Natural hair', sub = 'Nothing to report. Keep it that way.', tone = 't-success', action = '';
  if (h.wig) {
    icon = 'fa-masks-theater'; tone = '';
    title = h.wig.label || 'Wearing a wig';
    sub = `${h.wig.cond ?? 100}% condition · if it gets snatched, your ${h.bald ? 'bald head' : 'real hair'} shows`;
    action = `<button class="btn sm" data-act="unwear"><i class="fa-solid fa-arrow-rotate-left"></i>Take off</button>`;
  } else if (h.bald) {
    icon = 'fa-user-slash'; tone = 't-error';
    title = 'Bald';
    sub = h.bald.u > 0 ? `Regrows in <span data-until="${h.bald.u}" data-done="any second">${left(h.bald.u)}</span> · Regrowth Oil speeds it up` : 'It only comes back with Regrowth Oil';
  } else if (h.cut) {
    icon = 'fa-scissors'; tone = 't-info';
    title = { trim: 'Fresh trim', fade: 'Fade', buzz: 'Buzz cut' }[h.cut.kind] || 'Fresh haircut';
    sub = h.cut.u > 0 ? `Grows out in <span data-until="${h.cut.u}">${left(h.cut.u)}</span>` : 'Someone gave you a new look';
  }
  const flags = statusChips(h);
  if (me.glueUntil > serverNow()) flags.push(`<span class="chip t-success"><i class="fa-solid fa-droplet"></i>Glued · <span data-until="${me.glueUntil}">${left(me.glueUntil)}</span></span>`);
  if (me.cooldownUntil > serverNow()) flags.push(`<span class="chip t-warning"><i class="fa-solid fa-hourglass-half"></i>Cooldown · <span data-until="${me.cooldownUntil}" data-done="ready">${left(me.cooldownUntil)}</span></span>`);
  if (me.newUntil > serverNow()) flags.push(`<span class="chip"><i class="fa-solid fa-shield"></i>New player · <span data-until="${me.newUntil}">${left(me.newUntil)}</span></span>`);
  if (me.passive) flags.push(`<span class="chip"><i class="fa-solid fa-dove"></i>Passive</span>`);
  if (me.bountyOnMe) flags.push(`<span class="chip t-error"><i class="fa-solid fa-crosshairs"></i>${money(me.bountyOnMe)} on your head</span>`);
  if (me.stats.streak > 1) flags.push(`<span class="chip t-warning"><i class="fa-solid fa-fire"></i>${me.stats.streak} streak</span>`);
  return `<div class="card"><div class="hair ${tone}"><div class="ti ${tone}" style="${h.wig ? tierStyle(h.wig.tier) : ''}"><i class="fa-solid ${icon}"></i></div>
      <div class="hair-tx"><b>${esc(title)}</b><span>${sub}</span></div>${action}</div>
      ${flags.length ? `<div class="flags">${flags.join('')}</div>` : ''}</div>`;
}

const VIEWS = {
  profile() {
    const d = S.vault, me = d.me, st = me.stats;
    const span = (me.nextXp || me.xp) - me.levelXp;
    const p100 = me.nextXp ? clamp(((me.xp - me.levelXp) / Math.max(1, span)) * 100, 0, 100) : 100;
    const attempts = st.snatches + st.fails;
    const rate = attempts ? Math.round((st.snatches / attempts) * 100) : 0;
    const fights = st.defends + st.snatched;
    const hold = fights ? Math.round((st.defends / fights) * 100) : 0;
    const p = me.perks || {};
    const perk = (label, v, suffix = '%') => `<div class="perk ${v ? '' : 'off'}"><span>${label}</span><b>${v ? '+' + Math.round(v * 100) + suffix : '-'}</b></div>`;
    const best = st.best_tier ? tier(st.best_tier) : null;
    return `
      <div class="hero">
        <div class="mono">${esc(initials(me.name))}</div>
        <div class="hero-tx">
          <small>${esc(me.title)}</small>
          <b>${esc(me.name)}</b>
          <em>${num(me.xp)} reputation${me.nextTitle ? ` · ${num(me.nextXp - me.xp)} to ${esc(me.nextTitle)}` : ' · max title'}</em>
          <div class="xp"><div class="xp-bar"><i style="width:${p100}%"></i></div></div>
        </div>
        <div class="lvl"><span>Level</span><b>${me.level}</b></div>
      </div>
      <div class="sec">${hairCard(me)}</div>
      <div class="sec">
        <div class="sec-h"><h3>Record</h3><span>${best ? `Best pull: <b style="color:${best.color}">${esc(best.label)}</b>` : ''}</span></div>
        <div class="grid4">
          <div class="stat"><span><i class="fa-solid fa-hand"></i>Snatched</span><b>${num(st.snatches)}<small>${rate}% rate</small></b></div>
          <div class="stat"><span><i class="fa-solid fa-shield-halved"></i>Held on</span><b>${num(st.defends)}<small>${hold}%</small></b></div>
          <div class="stat"><span><i class="fa-solid fa-fire"></i>Best streak</span><b>${num(st.best_streak)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-user-slash"></i>Lost hair</span><b>${num(st.snatched)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-sack-dollar"></i>Earned</span><b>${money(st.earned)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-crosshairs"></i>Bounties</span><b>${num(st.bounties_claimed)}<small>${money(st.bounty_earned)}</small></b></div>
          <div class="stat"><span><i class="fa-solid fa-rotate-left"></i>Revenge · Taken back</span><b>${num(st.revenges)}<small>· ${num(st.stolen_back)}</small></b></div>
          <div class="stat"><span><i class="fa-solid fa-scissors"></i>Cuts · Forced</span><b>${num(st.cuts)}<small>· ${num(st.buzzes)}</small></b></div>
          <div class="stat"><span><i class="fa-solid fa-person-running"></i>Tackles</span><b>${num(st.tackles)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-link"></i>Tied up</span><b>${num(st.ties)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-pump-soap"></i>Pranks</span><b>${num(st.products)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-screwdriver-wrench"></i>Wigs made</span><b>${num(st.crafted)}</b></div>
        </div>
      </div>
      <div class="grid2">
        <div class="card"><div class="sec-h"><h3>Perks</h3><span>${esc(me.title)}</span></div>
          <div class="perks">${perk('Shorter cooldown', p.cooldown)}${perk('Bigger minigame zones', p.zone, ' pts')}${perk('Better selling prices', p.sell)}${perk('Tier luck', p.luck)}</div></div>
        <div class="card"><div class="sec-h"><h3>Titles</h3><span>${me.level} / ${arr(d.levels).length}</span></div>
          <div class="perks">${arr(d.levels).slice(Math.max(0, me.level - 2), me.level + 2).map((l) => {
            const idx = arr(d.levels).indexOf(l) + 1;
            return `<div class="perk ${idx <= me.level ? '' : 'off'}"><span>${idx === me.level ? '<i class="fa-solid fa-caret-right" style="color:var(--teal);margin-right:6px"></i>' : ''}${esc(l.title)}</span><b>${num(l.xp)}</b></div>`;
          }).join('')}</div></div>
      </div>`;
  },

  wigs() {
    const d = S.vault, wigs = arr(d.wigs);
    if (!wigs.length) return `<div class="wig-list"><div class="empty"><i class="fa-solid fa-box-open"></i>No wigs yet. Go take some, or make one at a wig table.</div></div>`;
    const sel = wigs.find((w) => w.key === S.sel) || wigs[0];
    S.sel = sel.key;
    const total = wigs.reduce((a, w) => a + (w.value || 0), 0);
    return `<div class="wig-list">
        <div class="sec-h"><h3>${wigs.length} wig${wigs.length === 1 ? '' : 's'}</h3><span>Worth about ${money(total)}${d.appName ? ` · sell them in ${esc(d.appName)}` : ''}</span></div>
        <div class="wig-grid">${wigs.map((w) => goodCard(w, { selected: w.key === sel.key })).join('')}</div>
      </div>
      <div class="detail">${wigDetail(sel)}</div>`;
  },


  catalog() {
    const d = S.vault, cat = d.catalog || {};
    // one entry per hairstyle, named and photographed in the Wig Studio
    const all = arr(d.styles).filter((e) => e && e.key);
    const have = all.filter((e) => cat[e.key]).length;
    const rewards = arr(d.catalogRewards);
    const max = all.length || 1;
    const miles = rewards.map((r) => `<div class="mile ${have >= r.count ? 'got' : ''}" style="left:${Math.min(100, (r.count / max) * 100)}%"><i class="fa-solid ${have >= r.count ? 'fa-check' : 'fa-gift'}"></i><span>${r.count} · ${money(r.money)}</span></div>`).join('');
    const C = S.cat || (S.cat = { show: 'all', g: 'all', q: '' });
    const q = C.q.trim().toLowerCase();
    const list = all.filter((e) => (C.show === 'all' || (C.show === 'found') === !!cat[e.key])
      && (C.g === 'all' || e.m === C.g) && (!q || String(e.name).toLowerCase().includes(q) || String(e.d) === q));
    const seg = (field, opts) => `<div class="seg">${opts.map(([v, l]) => `<button class="${C[field] === v ? 'on' : ''}" data-act="catSet" data-v="${field}:${v}">${l}</button>`).join('')}</div>`;
    const card = (e) => {
      const c = cat[e.key], t = c ? tier(c.tier) : null;
      const img = e.image ? `<img src="${esc(e.image)}" alt="" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('i'),{className:'fa-solid fa-crown'}))">` : '<i class="fa-solid fa-crown"></i>';
      return `<div class="cat ${c ? '' : 'locked'}" ${t ? `style="${tintVars(t.color)}"` : ''}>
        <div class="cat-img">${img}${c ? '' : '<span class="cat-lock"><i class="fa-solid fa-lock"></i></span>'}</div>
        <b>${esc(e.name)}</b>
        <span>${c ? `${esc(t.label)}${c.times > 1 ? ' · x' + c.times : ''}` : 'Not found yet'}</span>
        <small>${e.m === 'm' ? 'Male' : 'Female'} · #${e.d}</small></div>`;
    };
    return `
      <div class="cat-prog">
        <b>${have}<small> / ${all.length}</small></b>
        <div class="miles"><div class="miles-bar"><i style="width:${(have / max) * 100}%"></i></div>${miles}</div>
      </div>
      <div class="note">Every hairstyle in the city is in the book. Snatch it or make it at a wig table to collect it; your best tier for each is kept.</div>
      <div class="cat-bar">${seg('show', [['all', 'All'], ['found', 'Found'], ['missing', 'Missing']])}${seg('g', [['all', 'Everyone'], ['f', 'Female'], ['m', 'Male']])}
        <label class="field"><i class="fa-solid fa-magnifying-glass"></i><input id="catQ" placeholder="Search hairstyles" value="${esc(C.q)}"></label></div>
      <div class="cat-grid">${list.map(card).join('') || `<div class="empty" style="grid-column:1/-1"><i class="fa-solid fa-book-open"></i>${all.length ? 'Nothing matches' : 'No hairstyles yet. An admin fills the book with /wigstudio.'}</div>`}</div>`;
  },

  bounties() {
    const d = S.vault, cfg = d.bountyCfg || {};
    const board = arr(d.bounties), rev = arr(d.revenge);
    const boardHtml = board.length ? board.map((b, i) => `
      <div class="row"><div class="rank ${i < 3 ? 'r' + (i + 1) : ''}">${i + 1}</div>
        <div class="row-tx"><b><span class="dot ${b.online ? 'on' : ''}"></span>${esc(b.name)}</b><span>${b.count} bount${b.count === 1 ? 'y' : 'ies'} · ${esc(arr(b.placers).join(', '))}</span></div>
        <div class="row-val">${money(b.total)}<small>${ago(b.created)}</small></div></div>`).join('')
      : `<div class="empty"><i class="fa-solid fa-crosshairs"></i>Nobody is wanted right now</div>`;
    const revHtml = rev.length ? rev.map((r) => {
      const open = S.bountyOpen === r.identifier;
      return `<div class="row" style="flex-wrap:wrap">
        <div class="row-tx"><b><span class="dot ${r.online ? 'on' : ''}"></span>${esc(r.name)}</b><span>Got you ${r.times}x · ${ago(r.last)}${r.bounty ? ' · ' + money(r.bounty) + ' on them' : ''}</span></div>
        ${cfg.enabled ? `<button class="btn sm ${open ? 'ghost' : 'red'}" data-act="bountyToggle" data-v="${esc(r.identifier)}"><i class="fa-solid ${open ? 'fa-xmark' : 'fa-crosshairs'}"></i>${open ? 'Cancel' : 'Bounty'}</button>` : ''}
        ${open ? `<div style="width:100%"><div class="binput">
            <label class="field"><i class="fa-solid fa-dollar-sign"></i><input id="bAmt" data-int placeholder="${num(cfg.min)} - ${num(cfg.max)}" autofocus></label>
            <button class="btn teal" data-act="bountyPlace" data-v="${esc(r.identifier)}">Place</button></div>
          <div class="note">${Math.round((cfg.fee || 0) * 100)}% fee. Whoever snatches ${esc(r.name)} next collects the rest. Expires and refunds if nobody does.</div></div>` : ''}
      </div>`;
    }).join('') : `<div class="empty"><i class="fa-solid fa-face-smile"></i>Nobody snatched you recently</div>`;
    return `<div class="grid2" style="align-items:start">
      <div><div class="sec-h"><h3>Most wanted</h3><span>${board.length} target${board.length === 1 ? '' : 's'}</span></div><div class="list">${boardHtml}</div></div>
      <div><div class="sec-h"><h3>Who got you</h3><span>Last 24h</span></div><div class="list">${revHtml}</div>
        <div class="note" style="margin-top:10px"><i class="fa-solid fa-rotate-left" style="color:var(--red);margin-right:6px"></i>Snatch them back for revenge rep, or take your exact wig back while it's still on them.</div></div>
    </div>`;
  },

  leaders() {
    const d = S.vault, lbs = d.leaderboards || {};
    const segs = [['snatches', 'Snatches'], ['defends', 'Held on'], ['best_streak', 'Streak'], ['earned', 'Earned'], ['bounty_earned', 'Bounties'], ['crafted', 'Wigs made']];
    const rows = arr(lbs[S.lb]);
    const fmt = (v) => (S.lb === 'earned' || S.lb === 'bounty_earned') ? money(v) : num(v);
    return `<div class="seg">${segs.map(([k, l]) => `<button class="${S.lb === k ? 'on' : ''}" data-act="lb" data-v="${k}">${l}</button>`).join('')}</div>
      <div class="list">${rows.length ? rows.map((r, i) => `
        <div class="row ${r.name === d.me.name ? 'me' : ''}"><div class="rank ${i < 3 ? 'r' + (i + 1) : ''}">${i + 1}</div>
          <div class="row-tx"><b><span class="dot ${r.online ? 'on' : ''}"></span>${esc(r.name)}</b><span>${esc(r.title || '')}</span></div>
          <div class="row-val">${fmt(r.value)}</div></div>`).join('') : `<div class="empty"><i class="fa-solid fa-ranking-star"></i>No one on the board yet</div>`}</div>`;
  },

  feed() {
    const rows = arr(S.vault.feed);
    if (!rows.length) return `<div class="empty"><i class="fa-solid fa-tower-broadcast"></i>The city is quiet</div>`;
    return `<div class="list">${rows.map((f) => {
      let icon = 'fa-hand', color = S.prefs.accent, text = '';
      if (f.kind === 'snatch') { color = tier(f.tier).color; text = `<b>${esc(f.actor_name)}</b> snatched <b>${esc(f.target_name)}</b>'s <em>${esc(f.label || tier(f.tier).label)}</em>${f.amount ? ` and collected ${money(f.amount)}` : ''}`; }
      else if (f.kind === 'steal') { icon = 'fa-rotate-left'; color = tier(f.tier).color; text = `<b>${esc(f.actor_name)}</b> took their <em>${esc(f.label || 'wig')}</em> back from <b>${esc(f.target_name)}</b>`; }
      else if (f.kind === 'buzz') { icon = 'fa-user-slash'; color = S.prefs.alert; text = `<b>${esc(f.actor_name)}</b> gave <b>${esc(f.target_name)}</b> ${f.label === 'bald' ? 'a shaved head' : f.label === 'face' ? 'a shave they didn\'t ask for' : 'a forced ' + esc(f.label || 'cut')}`; }
      else if (f.kind === 'product') { icon = 'fa-pump-soap'; color = '#a873ff'; text = `<b>${esc(f.actor_name)}</b> put <em>${esc(f.label)}</em> in <b>${esc(f.target_name)}</b>'s hair`; }
      else if (f.kind === 'bounty') { icon = 'fa-crosshairs'; color = S.prefs.alert; text = `<b>${esc(f.actor_name)}</b> put <em>${money(f.amount)}</em> on <b>${esc(f.target_name)}</b>`; }
      else if (f.kind === 'claim') { icon = 'fa-sack-dollar'; color = '#e5a50a'; text = `<b>${esc(f.actor_name)}</b> collected <em>${money(f.amount)}</em> for <b>${esc(f.target_name)}</b>`; }
      else return '';
      return `<div class="row feed-row" style="${tintVars(color)}"><div class="ti"><i class="fa-solid ${icon}"></i></div><p>${text}</p><time>${ago(f.created)}</time></div>`;
    }).join('')}</div>`;
  },

  settings() { return settingsView(); },
};

function wigDetail(w) {
  const d = S.vault, t = tier(w.tier);
  const fits = !w.generic && w.fits && w.fits === d.myModel;
  const canRepair = d.hasMeta && !w.generic && w.cond < 100;
  const owners = arr(w.owners);
  const date = w.ts ? new Date(w.ts * 1000).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '-';
  return `<div class="d-head" style="${tintVars(t.color)}">${wigVisual(w, 'd-glyph')}
      <b>${esc(goodTitle(w))}</b><span>${esc(t.label)}${w.generic ? '' : ' · ' + esc(w.lace)}</span></div>
    <div class="kv">
      <div><span>Worth</span><b>${money(w.value)}</b></div>
      <div><span>Condition</span><b style="color:${condColor(w.cond)}">${w.cond}%</b></div>
      ${w.generic ? '' : `<div><span>Fits</span><b>${w.fits === 'm' ? 'Male' : 'Female'} characters</b></div>
      <div><span>Colour</span><b><span class="swatch sm" data-hc="${w.color ?? ''}"></span>${w.dyed ? 'Dyed' : 'Natural'}</b></div>
      <div><span>Serial</span><b>${esc(w.serial)}</b></div>
      ${w.crafted ? `<div><span>Made by</span><b>${esc(w.crafted)}</b></div>` : `<div><span>Snatched by</span><b>${esc(w.by || '-')}</b></div>`}
      <div><span>First seen</span><b>${date}</b></div>`}
    </div>
    ${owners.length ? `<div class="card inset" style="${tintVars(t.color)}"><div class="sec-h" style="margin-bottom:4px"><h3>Provenance</h3><span>${w.hops ? `${w.hops}x stolen` : 'Fresh'}</span></div>
      <div class="chain">${owners.map((o, i) => `<div>${esc(o)}<small>${i === 0 ? (w.crafted ? 'hair from' : 'last worn by') : ''}</small></div>`).join('')}</div></div>` : ''}
    <div class="actions">
      ${w.generic ? '' : `<button class="btn teal wide" data-act="wear" data-v="${esc(w.key)}" ${fits ? '' : 'disabled'}><i class="fa-solid fa-masks-theater"></i>${fits ? 'Wear it' : "Doesn't fit you"}</button>`}
      ${!w.generic && d.putOn ? `<button class="btn wide" data-act="putOnNear" data-v="${esc(w.key)}"><i class="fa-solid fa-hat-wizard"></i>Put it on someone</button>` : ''}
      ${canRepair ? `<button class="btn wide" data-act="repair" data-v="${esc(w.key)}" ${d.me.kits > 0 ? '' : 'disabled'}><i class="fa-solid fa-wand-magic-sparkles"></i>Use wig kit${d.me.kits > 0 ? ` (${d.me.kits})` : ' (none)'}</button>` : ''}
      ${d.trading ? `<button class="btn wide" data-act="offer" data-v="${esc(w.key)}"><i class="fa-solid fa-handshake"></i>Sell or gift to a player</button>` : ''}
    </div>`;
}

/* ═══════════════ SETTINGS ═══════════════ */
const KEY_NAMES = { keyPull: 'Pull / hit', keyMashL: 'Mash left', keyMashR: 'Mash right' };
let capturing = null;

function settingsView() {
  const p = S.prefs, lock = !p.editable;
  const presets = arr(p.presets);
  const colour = (field, label, sub) => `<div class="card set">
      <div class="set-h"><b>${label}</b><span>${sub}</span></div>
      <div class="presets">${presets.map((c) => `<button class="preset ${p[field] === c ? 'on' : ''}" style="background:${c}" data-act="prefSet" data-v="${field}:${c}" ${lock ? 'disabled' : ''}></button>`).join('')}
        <label class="field hex"><span class="swatch sm" style="background:${p[field]}"></span><input value="${esc(p[field])}" maxlength="7" data-pref="${field}" ${lock ? 'disabled' : ''}></label></div></div>`;
  const seg = (field, opts) => `<div class="seg">${opts.map(([v, l]) => `<button class="${String(p[field]) === String(v) ? 'on' : ''}" data-act="prefSet" data-v="${field}:${v}" ${lock ? 'disabled' : ''}>${l}</button>`).join('')}</div>`;
  const sw = (field, label, sub) => `<div class="sw-line"><div><b>${label}</b><span>${sub}</span></div><button class="sw ${p[field] ? 'on' : ''}" data-act="prefToggle" data-v="${field}" ${lock ? 'disabled' : ''}><i></i></button></div>`;
  return `<div class="settings">
    ${lock ? `<div class="card set note-card"><i class="fa-solid fa-lock"></i>The server picked these for everyone.</div>` : ''}
    <div class="grid2">${colour('accent', 'Accent', 'Buttons, bars and your side of the rope')}${colour('alert', 'Alert', 'Errors, danger and the other side')}</div>
    <div class="grid2">
      <div class="card set"><div class="set-h"><b>Size</b><span>${Math.round(p.scale * 100)}%</span></div>
        <input type="range" min="80" max="125" step="5" value="${Math.round(p.scale * 100)}" data-pref="scale" ${lock ? 'disabled' : ''}></div>
      <div class="card set"><div class="set-h"><b>Notifications</b><span>Where ox_lib notifications pop up</span></div>
        ${seg('toastPos', [['top-left', '<i class="fa-solid fa-arrow-up-long" style="transform:rotate(-45deg)"></i>'], ['top-center', '<i class="fa-solid fa-arrow-up-long"></i>'], ['top-right', '<i class="fa-solid fa-arrow-up-long" style="transform:rotate(45deg)"></i>'], ['bottom-left', '<i class="fa-solid fa-arrow-down-long" style="transform:rotate(45deg)"></i>'], ['bottom-right', '<i class="fa-solid fa-arrow-down-long" style="transform:rotate(-45deg)"></i>']])}</div>
    </div>
    <div class="grid2">
      <div class="card set"><div class="set-h"><b>Sound</b><span>${Math.round(p.volume * 100)}%</span></div>
        ${sw('sounds', 'Sounds', 'Minigames, tools and cash')}
        <input type="range" min="0" max="100" step="5" value="${Math.round(p.volume * 100)}" data-pref="volume" ${lock ? 'disabled' : ''}></div>
      <div class="card set"><div class="set-h"><b>Banners</b><span>Snatch announcements</span></div>
        ${seg('banners', [['all', 'Everything'], ['city', 'City only'], ['none', 'Off']])}
        ${sw('reduceMotion', 'Reduce motion', 'Fewer animations')}</div>
    </div>
    <div class="card set"><div class="set-h"><b>Minigame keys</b><span>Click one, then press the key you want</span></div>
      <div class="keys">${Object.entries(KEY_NAMES).map(([f, l]) => `<button class="keybtn ${capturing === f ? 'on' : ''}" data-act="prefKey" data-v="${f}" ${lock ? 'disabled' : ''}><span>${l}</span><span class="kc">${capturing === f ? '...' : esc(keyLabel(p[f]))}</span></button>`).join('')}</div>
      <div class="note">Combo always takes W A S D or the arrows. Struggling while tied or held is A / D.</div></div>
    ${lock ? '' : `<div class="actions row-actions"><button class="btn ghost" data-act="prefReset"><i class="fa-solid fa-rotate-left"></i>Back to server defaults</button></div>`}
  </div>`;
}

let prefT = 0;
function savePrefs() {
  clearTimeout(prefT);
  prefT = setTimeout(async () => {
    const r = await post('prefsSave', S.prefs);
    if (r) applyPrefs(r);
  }, 250);
}
function prefInput(el) {
  const f = el.dataset.pref;
  if (f === 'scale' || f === 'volume') {
    S.prefs[f] = Number(el.value) / 100;
    applyPrefs(S.prefs);
    const lbl = el.closest('.set').querySelector('.set-h span');
    if (lbl) lbl.textContent = el.value + '%';
    return savePrefs();
  }
  if (/^#[0-9a-f]{6}$/i.test(el.value)) { S.prefs[f] = el.value.toLowerCase(); applyPrefs(S.prefs); savePrefs(); }
}
function rerenderSettings() { if (S.tab === 'settings' && $('#vview')) $('#vview').innerHTML = settingsView(); }

/* ═══════════════ PICKERS ═══════════════ */
const FX_ICON = { fallout: 'fa-user-slash', burn: 'fa-fire', lice: 'fa-bug', dirt: 'fa-hill-rockslide', clean: 'fa-shower', regrow: 'fa-seedling' };
function renderProducts() {
  const p = S.picker;
  setHead('Hair products', `Use on ${p.name || 'them'}`, `<span><span class="kc">ESC</span>Close</span>`);
  body.innerHTML = `<div class="view">
    <div class="pills">${p.behind ? '<span class="chip t-success"><i class="fa-solid fa-eye-slash"></i>Behind them</span>' : ''}${p.helpless ? '<span class="chip t-success"><i class="fa-solid fa-link"></i>Restrained</span>' : ''}</div>
    <div class="cuts">${arr(p.products).map((x) => {
      const need = x.requires === 'any' ? 'Anyone' : x.requires === 'behind' ? 'From behind' : 'Restrained only';
      const ok = x.requires === 'any' || p.helpless || (x.requires === 'behind' && p.behind);
      return `<button class="cut ${ok ? '' : 'dim'}" data-act="useProduct" data-v="${esc(x.id)}"><i class="fa-solid ${FX_ICON[x.effect] || 'fa-pump-soap'}"></i><b>${esc(x.label)}</b><span>x${x.count} · ${need}</span></button>`;
    }).join('')}</div>
    <div class="note" style="margin-top:12px">Pranks need you behind them, or them tied, held, tackled, cuffed or with their hands up.</div></div>`;
}
function renderPutOn() {
  const p = S.picker;
  setHead('Put a wig on', p.name || '', `<span><span class="kc">ESC</span>Close</span>`);
  body.innerHTML = `<div class="view"><div class="wig-grid">${arr(p.wigs).map((w) => goodCard(w, { act: 'putOn' })).join('')}</div>
    <div class="note" style="margin-top:12px">They get a prompt to accept. Their old wig goes back into their pockets.</div></div>`;
}


/* ═══════════════ MODAL ═══════════════ */
function modal(html, tint) {
  const m = $('#modal');
  m.innerHTML = `<div class="m-box" style="${tint ? tintVars(tint) : ''}"><div class="ch-frame"><div class="ch-in">${html}</div></div></div>`;
  m.hidden = false;
}
function closeModal() { const m = $('#modal'); m.hidden = true; m.innerHTML = ''; }
$('#modal').addEventListener('click', (e) => { if (e.target.id === 'modal') closeModal(); });

function confirmBox(title, text, okLabel, onOk, tint) {
  modal(`<h4>${title}</h4><p>${text}</p><div class="m-actions"><button class="btn ghost" data-act="mclose">Cancel</button><button class="btn teal" data-act="mok">${okLabel}</button></div>`, tint || S.prefs.accent);
  ACT.mok = () => { closeModal(); onOk(); };
}

let offerState = null;
async function playerPicker(key, mode) {
  const w = arr(S.vault.wigs).find((x) => x.key === key);
  if (!w) return;
  offerState = { key, mode, target: null, gift: false, players: [] };
  modal(`<h4>${mode === 'puton' ? 'Put it on someone' : 'Sell or gift'}</h4><div class="pick"><div class="empty" style="padding:16px"><i class="fa-solid fa-circle-notch fa-spin"></i></div></div>`, goodColor(w));
  let list = arr(await post('nearby', { range: mode === 'puton' ? 3 : undefined }));
  if (mode === 'puton') list = list.filter((p) => !p.model || p.model === w.fits);
  offerState.players = list;
  renderOffer(w);
}
function renderOffer(w) {
  const o = offerState;
  const box = $('.m-box .ch-in'); if (!box) return;
  const puton = o.mode === 'puton';
  box.innerHTML = `<h4>${puton ? 'Put it on someone' : 'Sell or gift'}</h4><p>${esc(goodTitle(w))} · they get a prompt to accept.</p>
    <div class="pick">${o.players.length ? o.players.map((p) => `<button class="${o.target === p.src ? 'on' : ''}" data-act="opick" data-v="${p.src}"><span class="dot on"></span>${esc(p.name)}<small>${p.dist}m</small></button>`).join('')
      : `<div class="empty" style="padding:16px"><i class="fa-solid fa-user-group"></i>${puton ? 'Nobody close enough that it fits' : 'Nobody close enough'}</div>`}</div>
    ${puton ? '' : `<div class="toggle"><span>Gift it (free)</span><button class="sw ${o.gift ? 'on' : ''}" data-act="ogift"><i></i></button></div>
    ${o.gift ? '' : `<div class="binput"><label class="field"><i class="fa-solid fa-dollar-sign"></i><input id="oPrice" data-int placeholder="Price" value="${o.price || ''}"></label></div>`}`}
    <div class="m-actions"><button class="btn ghost" data-act="mclose">Cancel</button><button class="btn teal" data-act="osend" ${o.target ? '' : 'disabled'}><i class="fa-solid fa-paper-plane"></i>${puton ? 'Ask them' : 'Send offer'}</button></div>`;
}

/* ═══════════════ ACTIONS ═══════════════ */
const ACT = {
  close: () => closeApp(),
  mclose: () => closeModal(),
  tab: async (v) => {
    S.tab = v; S.bountyOpen = null; capturing = null;
    if (v === 'wigs' || v === 'catalog') await palette();
    renderVault();
  },
  lb: (v) => { S.lb = v; $('#vview').innerHTML = VIEWS.leaders(); },
  catSet: (v) => { const [f, val] = v.split(':'); S.cat[f] = val; $('#vview').innerHTML = VIEWS.catalog(); },
  wsel: (v) => { S.sel = v; $('#vview').innerHTML = VIEWS.wigs(); paintSwatches(body); },
  wear: (v) => { post('wear', { key: v }); closeApp(true); },
  unwear: () => { post('unwear'); closeApp(true); },
  repair: (v) => { post('repair', { key: v }); },
  offer: (v) => playerPicker(v, 'offer'),
  putOnNear: (v) => playerPicker(v, 'puton'),
  opick: (v) => { const w = arr(S.vault.wigs).find((x) => x.key === offerState.key); offerState.price = ($('#oPrice') || {}).value; offerState.target = Number(v); renderOffer(w); },
  ogift: () => { const w = arr(S.vault.wigs).find((x) => x.key === offerState.key); offerState.price = ($('#oPrice') || {}).value; offerState.gift = !offerState.gift; renderOffer(w); },
  osend: async () => {
    const o = offerState; if (!o || !o.target) return;
    closeModal();
    if (o.mode === 'puton') { post('vaultPutOn', { key: o.key, target: o.target }); closeApp(true); return; }
    const price = o.gift ? 0 : Number(($('#oPrice') || {}).value || 0);
    const r = await post('offer', { target: o.target, key: o.key, price });
    if (r && r.ok) loadVault();
  },
  bountyToggle: (v) => { S.bountyOpen = S.bountyOpen === v ? null : v; $('#vview').innerHTML = VIEWS.bounties(); const i = $('#bAmt'); i && i.focus(); },
  bountyPlace: (v) => {
    const amt = Number(($('#bAmt') || {}).value || 0);
    const cfg = S.vault.bountyCfg || {};
    const r = arr(S.vault.revenge).find((x) => x.identifier === v);
    if (!amt || amt < cfg.min || amt > cfg.max) { toast({ kind: 'error', message: `Bounty must be between ${money(cfg.min)} and ${money(cfg.max)}` }); return; }
    const net = Math.floor(amt * (1 - (cfg.fee || 0)));
    confirmBox('Place bounty', `Pay <b style="color:var(--white)">${money(amt)}</b> to put <b style="color:var(--white)">${money(net)}</b> on ${esc(r ? r.name : 'them')}. Whoever snatches them next collects it.`, 'Place bounty', async () => {
      const res = await post('placeBounty', { identifier: v, amount: amt });
      if (res && res.ok) { S.bountyOpen = null; loadVault(); }
    }, S.prefs.alert);
  },
  // settings
  prefSet: (v) => {
    const i = v.indexOf(':'), f = v.slice(0, i), val = v.slice(i + 1);
    S.prefs[f] = val;
    applyPrefs(S.prefs); savePrefs(); rerenderSettings();
  },
  prefToggle: (v) => { S.prefs[v] = !S.prefs[v]; applyPrefs(S.prefs); savePrefs(); rerenderSettings(); },
  prefKey: (v) => { capturing = v; rerenderSettings(); },
  prefReset: async () => { const r = await post('prefsReset'); if (r) { applyPrefs(r); rerenderSettings(); } },
  // pickers
  useProduct: (v) => { post('productUse', { id: v, target: S.picker.target }); closeApp(true); },
  putOn: (v) => { post('putOn', { key: v, target: S.picker.target }); closeApp(true); },
};

// key capture for settings (runs before other key handling)
function settingsKey(e) {
  if (!capturing || e.type !== 'keydown') return false;
  e.preventDefault();
  if (e.code !== 'Escape') S.prefs[capturing] = e.code;
  capturing = null;
  applyPrefs(S.prefs); savePrefs(); rerenderSettings();
  return true;
}
