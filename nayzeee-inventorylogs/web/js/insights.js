'use strict';
const money = n => (n < 0 ? '-$' : '$') + num(Math.abs(Math.round(n || 0)));
const ACC = { money: 'Cash', cash: 'Cash', bank: 'Bank', black_money: 'Dirty money', crypto: 'Crypto' };

/* ═══ ECONOMY ═══════════════════════════════════════════════════════════ */
page('economy', {
  label: 'Economy', icon: 'fas fa-scale-balanced',
  async enter() { const st = pd('eco'); st.range = st.range || '24h'; st.view = st.view || 'money'; st.by = st.by || 'resource'; await ecoLoad(); },
  render() {
    const st = pd('eco');
    const actions = seg([['money', 'Money'], ['items', 'Items']], st.view, 'ecoView') + seg([['24h', '24h'], ['7d', '7d'], ['30d', '30d']], st.range, 'ecoRange');
    const head = ph('Economy', st.view === 'money' ? 'Where money comes from and where it goes, by script' : 'Which scripts are putting items into the server', actions);
    const d = st.data;
    if (!d) return head + `<div class="content">${loading()}</div>`;
    if (st.view === 'items') {
      const max = Math.max(1, ...d.map(r => r.n));
      return head + `<div class="content">${d.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Script</th><th></th><th class="num">Times</th><th class="num">Items created</th><th class="num">Different items</th><th class="num">Players</th></tr></thead><tbody>
        ${d.map(r => `<tr class="click" data-a="ecoItemOpen" data-v="${esc(r.k)}"><td><b class="mono">${esc(r.k)}</b></td><td style="width:30%"><div class="track"><i style="width:${r.n / max * 100}%"></i></div></td><td class="num">${num(r.n)}</td><td class="num"><b>${num(r.total)}</b></td><td class="num">${num(r.kinds)}</td><td class="num">${num(r.players)}</td></tr>`).join('')}
        </tbody></table></div>` : empty('fas fa-code-branch', 'No items created in this range', 'Item creation logs record which script created each item. Check Config.CreationLogs is on.')}</div>`;
    }
    const t = d.totals || {};
    const net = (t.inflow || 0) - (t.outflow || 0);
    const moved = (t.inflow || 0) + (t.outflow || 0);
    const unPct = moved ? Math.round(t.unattributed / moved * 100) : 0;
    const stat = (lbl, icon, val, sub, c) => `<div class="stat" style="--c:${c}"><div class="lbl"><i class="${icon}"></i>${esc(lbl)}</div><div class="val">${val}</div><div class="sub">${sub}</div></div>`;
    const maxF = Math.max(1, ...(d.flow || []).map(f => Math.max(f.inflow, f.outflow)));
    const label = b => d.bucket === 3600 ? new Date(b * 3600000).toLocaleTimeString('en-US', { hour: 'numeric' }) : new Date(b * 86400000).toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
    const flow = (d.flow || []).length ? `<div class="hist-wrap"><div class="flow">${d.flow.map((f, i) => `<div title="${esc(label(f.b))}: in ${money(f.inflow)}, out ${money(f.outflow)}"><i class="in" style="height:${Math.max(1.5, f.inflow / maxF * 100)}%"></i><i class="out" style="height:${Math.max(1.5, f.outflow / maxF * 100)}%"></i>${i % Math.max(1, Math.ceil(d.flow.length / 7)) === 0 ? `<span>${esc(label(f.b))}</span>` : ''}</div>`).join('')}</div></div>` : empty('fas fa-chart-column', 'No money moved in this range');
    const side = (list, kind) => {
      const max = Math.max(1, ...list.map(r => r.total));
      return list.length ? `<div class="bars">${list.map(r => `<div class="bar-row click" style="grid-template-columns:150px 1fr 96px" data-a="ecoOpen" data-v="${esc(JSON.stringify({ k: r.k, side: kind }))}"><span class="t ell ${st.by === 'resource' ? 'mono' : ''}" title="${esc(r.k)}">${esc(r.k)}</span><div class="track ${kind === 'sink' ? 'red' : ''}"><i style="width:${r.total / max * 100}%"></i></div><span class="n">${money(r.total)}</span></div>`).join('')}</div>` : empty('fas fa-circle-minus', 'Nothing here yet');
    };
    const bridgeNote = !d.bridged && unPct > 0 ? note(`Scripts show as the framework (es_extended, qb-core or qbx_core) until the framework bridge is installed. It's one file and one line, see <b>INSTALL.md → Money sources</b>.`, 'amber') + '<div style="height:14px"></div>' : '';
    return head + `<div class="content"><div class="stack">${bridgeNote}
      <div class="g4">
        ${stat('Money in', 'fas fa-arrow-down', money(t.inflow), `${num(t.n)} changes`, 'var(--teal)')}
        ${stat('Money out', 'fas fa-arrow-up', money(t.outflow), 'spent, removed or paid out', 'var(--red)')}
        ${stat('Net', 'fas fa-scale-balanced', money(net), net > 0 ? 'more money entering than leaving' : 'more money leaving than entering', net > 0 ? 'var(--amber)' : 'var(--blue)')}
        ${stat('Unattributed', 'fas fa-circle-question', unPct + '%', 'of money moved with no script name', unPct > 25 ? 'var(--amber)' : 'var(--teal)')}
      </div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-chart-column"></i>Money in vs out</h3><div class="r legend"><span><i style="background:var(--teal)"></i>In</span><span><i style="background:var(--red)"></i>Out</span></div></div><div class="card-b">${flow}</div></div>
      <div style="display:flex;justify-content:flex-end">${seg([['resource', 'By script'], ['reason', 'By reason']], st.by, 'ecoBy')}</div>
      <div class="g2">
        <div class="card"><div class="card-h"><h3><i class="fas fa-arrow-down" style="color:var(--teal)"></i>Sources</h3><span class="muted" style="font-size:10.5px">where money comes from</span></div><div class="card-b">${side(d.sources || [], 'source')}</div></div>
        <div class="card"><div class="card-h"><h3><i class="fas fa-arrow-up" style="color:var(--red)"></i>Sinks</h3><span class="muted" style="font-size:10.5px">where money goes</span></div><div class="card-b">${side(d.sinks || [], 'sink')}</div></div>
      </div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-wallet"></i>By account</h3></div><div class="card-b np"><table class="tbl"><thead><tr><th>Account</th><th class="num">In</th><th class="num">Out</th><th class="num">Net</th></tr></thead><tbody>${(d.accounts || []).map(a => `<tr><td><b>${esc(ACC[a.account] || a.account)}</b></td><td class="num tteal">${money(a.inflow)}</td><td class="num tred">${money(a.outflow)}</td><td class="num"><b>${money(a.inflow - a.outflow)}</b></td></tr>`).join('') || `<tr><td colspan="4" class="muted">No money moved</td></tr>`}</tbody></table></div></div>
    </div></div>`;
  },
});
async function ecoLoad() {
  const st = pd('eco'); st.data = null; rerender();
  const r = st.view === 'items' ? await rpc('eco:items', { range: st.range }) : await rpc('eco:money', { range: st.range, by: st.by });
  if (!r.ok) return toast(r.err, 'error');
  st.data = r.data;
  if (S.page === 'economy') rerender();
}
A.ecoView = v => { pd('eco').view = v; ecoLoad(); };
A.ecoRange = v => { pd('eco').range = v; ecoLoad(); };
A.ecoBy = v => { pd('eco').by = v; ecoLoad(); };
A.ecoOpen = async v => {
  const st = pd('eco'); const { k, side } = JSON.parse(v);
  const d = await call('eco:moneyDetail', { range: st.range, by: st.by, key: k, side });
  if (!d) return;
  const max = Math.max(1, ...d.breakdown.map(r => r.total));
  infoBox(`${k}`, `
    <div class="g2" style="gap:12px">
      <div class="card"><div class="card-h"><h3><i class="fas fa-list"></i>${st.by === 'reason' ? 'Scripts' : 'Reasons given'}</h3></div><div class="card-b"><div class="bars">${d.breakdown.map(r => `<div class="bar-row" style="grid-template-columns:140px 1fr 90px"><span class="t ell" title="${esc(r.k)}">${esc(r.k)}</span><div class="track ${side === 'sink' ? 'red' : ''}"><i style="width:${r.total / max * 100}%"></i></div><span class="n">${money(r.total)}</span></div>`).join('') || '<span class="muted">None</span>'}</div></div></div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-wallet"></i>Accounts</h3></div><div class="card-b np">${d.accounts.map(a => `<div class="li"><div class="tx"><b>${esc(ACC[a.account] || a.account)}</b></div><div class="rt"><b class="${side === 'sink' ? 'tred' : 'tteal'}">${money(a.total)}</b></div></div>`).join('')}</div></div>
    </div>
    <div class="card"><div class="card-h"><h3><i class="fas fa-users"></i>${side === 'sink' ? 'Who paid' : 'Who received it'}</h3></div><div class="card-b np">${d.players.map(p => `<div class="li click" data-a="ecoPlayerLogs" data-v="${esc(p.identifier || '')}">${av(p.name, 'sm')}<div class="tx"><b>${esc(p.name || 'Unknown')}</b><span class="mono">${esc(p.identifier || '')} · ${num(p.n)} times</span></div><div class="rt"><b class="${side === 'sink' ? 'tred' : 'tteal'}">${money(p.total)}</b></div></div>`).join('') || empty('fas fa-users', 'Nobody')}</div></div>`,
    { size: 'lg', icon: side === 'sink' ? 'fas fa-arrow-up' : 'fas fa-arrow-down', sub: `${side === 'sink' ? 'Money leaving' : 'Money entering'} through ${st.by === 'reason' ? 'this reason' : 'this script'} · last ${st.range}` });
};
A.ecoPlayerLogs = v => { closeModal(null); pd('logs').f = { type: 'money', player: v, range: pd('eco').range === '24h' ? '24h' : pd('eco').range }; go('logs'); };
A.ecoItemOpen = async v => {
  const st = pd('eco');
  const d = await call('eco:itemsDetail', { range: st.range, key: v });
  if (!d) return;
  infoBox(v, `<div class="g2" style="gap:12px">
      <div class="card"><div class="card-h"><h3><i class="fas fa-boxes-stacked"></i>Items it created</h3></div><div class="card-b np" style="max-height:380px;overflow:auto">${d.items.map(i => `<div class="li">${thumb(i.item_name)}<div class="tx"><b>${esc(i.label || i.item_name)}</b><span>${num(i.n)} times</span></div><div class="rt"><b class="tteal">${num(i.total)}</b></div></div>`).join('')}</div></div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-users"></i>Who got them</h3></div><div class="card-b np" style="max-height:380px;overflow:auto">${d.players.map(p => `<div class="li click" data-a="ecoItemPlayer" data-v="${esc(JSON.stringify({ id: p.identifier, res: v }))}">${av(p.name, 'sm')}<div class="tx"><b>${esc(p.name || 'Unknown')}</b><span>${num(p.n)} times</span></div><div class="rt"><b>${num(p.total)}</b></div></div>`).join('')}</div></div></div>`,
    { size: 'xl', icon: 'fas fa-code-branch', sub: `Items created by this script · last ${st.range}` });
};
A.ecoItemPlayer = v => { const { id, res } = JSON.parse(v); closeModal(null); pd('logs').f = { type: 'created', player: id, resource: res, range: pd('eco').range }; go('logs'); };

/* ═══ PLAYER INCOME TAB ═════════════════════════════════════════════════ */
function incomeHtml(d) {
  if (!d) return loading();
  const bars = (list, red) => { const max = Math.max(1, ...list.map(r => r.total)); return list.length ? `<div class="bars">${list.map(r => `<div class="bar-row" style="grid-template-columns:140px 1fr 90px"><span class="t ell mono" title="${esc(r.k)}">${esc(r.k)}</span><div class="track ${red ? 'red' : ''}"><i style="width:${r.total / max * 100}%"></i></div><span class="n">${money(r.total)}</span></div>`).join('')}</div>` : '<span class="muted">Nothing in the last 7 days.</span>'; };
  return `<div class="stack">
    <div class="g2"><div class="card"><div class="card-h"><h3><i class="fas fa-arrow-down" style="color:var(--teal)"></i>Money from</h3><span class="muted" style="font-size:10.5px">last 7 days</span></div><div class="card-b">${bars(d.income || [])}</div></div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-arrow-up" style="color:var(--red)"></i>Money spent on</h3><span class="muted" style="font-size:10.5px">last 7 days</span></div><div class="card-b">${bars(d.spending || [], true)}</div></div></div>
    <div class="card"><div class="card-h"><h3><i class="fas fa-code-branch"></i>Items received, by script</h3></div><div class="card-b np">${(d.items || []).length ? `<div class="tbl-wrap" style="border:0;border-radius:0;max-height:340px"><table class="tbl"><thead><tr><th>Script</th><th>Item</th><th class="num">Times</th><th class="num">Total</th></tr></thead><tbody>${d.items.map(i => `<tr><td class="mono">${esc(i.k)}</td><td><div class="cell">${thumb(i.item_name)}<b>${esc(i.label || i.item_name)}</b></div></td><td class="num">${num(i.n)}</td><td class="num"><b>${num(i.total)}</b></td></tr>`).join('')}</tbody></table></div>` : empty('fas fa-box', 'No created items logged')}</div></div>
  </div>`;
}
{
  // add an "Income" tab to the player view
  const baseTab = A.plTab;
  A.plTab = async v => {
    const st = pd('players');
    if (v !== 'inc') return baseTab(v);
    st.ptab = 'inc'; st.income = null; rerender();
    const r = await rpc('eco:player', { identifier: st.inv.target.charId, range: '7d' });
    st.income = r.ok ? r.data : {};
    rerender();
  };
  const basePane = playerPane;
  playerPane = function () {
    const st = pd('players');
    let html = basePane();
    html = html.replace(/(<div class="tabs">[\s\S]*?)(<\/div>)/, (m, a, b) => a + `<button class="${st.ptab === 'inc' ? 'on' : ''}" data-a="plTab" data-v="inc"><i class="fas fa-sack-dollar"></i>Income</button>` + b);
    if (st.ptab === 'inc' && st.inv && !st.inv.error) html = html.replace(/<div class="content" style="padding-top:14px">[\s\S]*$/, `<div class="content" style="padding-top:14px">${incomeHtml(st.income)}</div>`);
    return html;
  };
}

/* ═══ ANTI-DUPE ═════════════════════════════════════════════════════════ */
page('antidupe', {
  label: 'Anti-dupe', icon: 'fas fa-clone',
  badge() { const d = pd('dupe').data; const n = d && d.last ? d.last.dupes.filter(g => g.where.length > 1).length : 0; return n ? `<span class="tally hot">${n}</span>` : ''; },
  async enter() { await dupeLoad(); },
  render() {
    const st = pd('dupe'); const d = st.data;
    const head = ph('Anti-dupe', 'Duplicate serials, sudden item growth and dupe attempts', can('manage') ? btn(st.busy ? 'Scanning…' : 'Scan now', 'dupeScan', 'btn-teal sm', { icon: 'fas fa-magnifying-glass-chart', disabled: st.busy }) : '');
    if (!d) return head + `<div class="content">${loading()}</div>`;
    if (!d.enabled) return head + `<div class="content">${note('Anti-dupe is turned off. Set <b>Config.AntiDupe.enabled = true</b>.', 'amber')}</div>`;
    const L = d.last;
    const groups = L ? L.dupes.filter(g => g.where.length > 1) : [];
    const scanned = L ? L.counts.online + L.counts.offline + L.counts.stashes + L.counts.vehicles : 0;
    const stat = (lbl, icon, val, sub, c) => `<div class="stat" style="--c:${c}"><div class="lbl"><i class="${icon}"></i>${esc(lbl)}</div><div class="val">${val}</div><div class="sub">${sub}</div></div>`;
    const where = (g, w) => {
      const kindLabel = { player: 'Online player', offline: 'Offline character', stash: 'Stash', trunk: 'Trunk', glovebox: 'Glovebox' }[w.kind] || w.kind;
      const open = w.kind === 'player' ? btn('Open', 'dupePlayer', 'xs', { v: JSON.stringify({ id: +w.id }) }) : w.kind === 'offline' ? btn('Open', 'dupePlayer', 'xs', { v: JSON.stringify({ charId: w.id, name: w.id }) }) : S.boot.remoteView ? btn('Open', 'logInv', 'xs', { v: w.id }) : '';
      return `<tr><td>${chip(kindLabel, w.kind === 'player' ? 'teal' : '')}</td><td><b class="mono">${esc(w.label)}</b></td><td class="num">${w.slot ?? '-'}</td><td class="act"><div class="row-btns" style="flex-wrap:nowrap">${open}${can('manage') ? btn('Remove this copy', 'dupeRemove', 'xs btn-red', { v: JSON.stringify({ item: g.item, key: g.key, value: g.value, where: w }) }) : ''}</div></td></tr>`;
    };
    const dupesHtml = groups.length ? groups.map(g => `<div class="dupe-g"><div class="hd">${thumb(g.item)}<div class="tx"><b>${esc(itemLabel(g.item))}</b><span>${esc(g.key)} <span class="mono">${esc(g.value)}</span></span></div><div class="r">${chip(g.where.length + ' copies', 'red', 'fas fa-clone')}</div></div>
        <table class="tbl"><tbody>${g.where.map(w => where(g, w)).join('')}</tbody></table></div>`).join('') : empty('fas fa-shield-halved', L ? 'No duplicates found' : 'No scan yet', L ? `Every ${(d.keys || ['serial']).join(', ')} is unique across ${num(scanned)} inventories.` : 'The first scan runs 90 seconds after start, or press Scan now.');
    const movers = L ? (L.movers || []) : [];
    const moversHtml = movers.length ? `<table class="tbl"><thead><tr><th>Item</th><th class="num">Before</th><th class="num">Now</th><th class="num">Change</th></tr></thead><tbody>${movers.slice(0, 15).map(m => `<tr class="click" data-a="supplyOpen" data-v="${esc(m.item)}"><td><div class="cell">${thumb(m.item)}<b>${esc(itemLabel(m.item))}</b></div></td><td class="num">${num(m.prev)}</td><td class="num">${num(m.total)}</td><td class="num ${m.diff > 0 ? 'tamber' : 'tteal'}"><b>${m.diff > 0 ? '+' : ''}${num(m.diff)}</b> <span class="muted">${m.pct > 0 ? '+' : ''}${m.pct}%</span></td></tr>`).join('')}</tbody></table>` : `<div class="card-b muted" style="font-size:11px">${L ? 'Nothing changed since the previous scan, or this is the first scan.' : 'Waiting for the first scan.'}</div>`;
    const alerts = [...(d.flags || []), ...(d.attempts || []), ...(d.supply || [])].sort((a, b) => b.time - a.time).slice(0, 15);
    return head + `<div class="content"><div class="stack">
      <div class="g4">
        ${stat('Last scan', 'fas fa-clock', L ? ago(L.time) : 'never', L ? `took ${(L.took / 1000).toFixed(1)}s · every ${d.every} min` : '', 'var(--teal)')}
        ${stat('Inventories scanned', 'fas fa-boxes-stacked', num(scanned), L ? `${num(L.counts.online)} online · ${num(L.counts.offline)} offline · ${num(L.counts.stashes)} stashes · ${num(L.counts.vehicles)} vehicles` : '', 'var(--blue)')}
        ${stat('Duplicates', 'fas fa-clone', num(groups.length), 'unique values found more than once', groups.length ? 'var(--red)' : 'var(--teal)')}
        ${stat('Dupe attempts', 'fas fa-person-running', num((d.attempts || []).length), 'rapid back-and-forth moves (latest 20)', (d.attempts || []).length ? 'var(--amber)' : 'var(--teal)')}
      </div>
      <div class="g-dash">
        <div class="card"><div class="card-h"><h3><i class="fas fa-clone"></i>Duplicate items</h3><div class="r">${btn('All dupe logs', 'dupeLogs', 'btn-ghost xs')}</div></div><div class="card-b">${dupesHtml}</div></div>
        <div class="stack">
          <div class="card"><div class="card-h"><h3><i class="fas fa-chart-line"></i>Supply watch</h3><span class="muted" style="font-size:10.5px">since last scan</span></div><div class="card-b np">${moversHtml}</div></div>
          <div class="card"><div class="card-h"><h3><i class="fas fa-bell"></i>Recent alerts</h3></div><div class="card-b np">${alerts.map(l => `<div class="li click" data-a="logOpenRow" data-v="${esc(JSON.stringify(l))}"><div class="tx"><b>${esc(l.item_label || l.item_name)}</b><span>${esc(l.details || '')}</span></div><div class="rt">${badge(l.type)}<br><span style="display:inline-block;margin-top:4px">${ago(l.time)}</span></div></div>`).join('') || empty('fas fa-bell-slash', 'No alerts')}</div></div>
        </div>
      </div>
    </div></div>`;
  },
});
async function dupeLoad() { const r = await rpc('dupe:status'); if (r.ok) { pd('dupe').data = r.data; refreshNav(); if (S.page === 'antidupe') rerender(); } }
A.dupeScan = async () => {
  const st = pd('dupe'); st.busy = true; rerender();
  toast('Scanning every inventory. This can take a few seconds on big servers.', 'info');
  const r = await rpc('dupe:scan');
  st.busy = false;
  if (!r.ok) { toast(r.err, 'error'); rerender(); return; }
  const n = r.data.dupes.filter(g => g.where.length > 1).length;
  toast(n ? `Found ${n} duplicate${n === 1 ? '' : 's'}` : 'No duplicates found', n ? 'warning' : 'success');
  dupeLoad();
};
A.dupeRemove = async v => {
  const x = JSON.parse(v);
  if (!await confirmBox(`Remove this ${itemLabel(x.item)}?`, `Removes the copy with ${x.key} ${x.value} from ${x.where.label}. The other copies stay.`, { ok: 'Remove copy' })) return;
  if (await call('dupe:remove', x, 'Copy removed')) dupeLoad();
};
A.dupePlayer = v => { const t = JSON.parse(v); const st = pd('players'); st.sel = t; st.inv = null; st.ptab = 'inv'; st.mode = t.id ? 'online' : 'search'; go('players'); };
A.dupeLogs = () => { pd('logs').f = { type: 'dupes', range: 'all' }; go('logs'); };
A.supplyOpen = async v => {
  const rows = await call('supply:item', { item: v, days: 7 });
  if (!rows) return;
  const max = Math.max(1, ...rows.map(r => r.total));
  const min = Math.min(...rows.map(r => r.total));
  infoBox(`${itemLabel(v)} on the server`, rows.length ? `<div class="hist-wrap"><div class="hist" style="height:200px">${rows.map((r, i) => `<div title="${esc(date(r.time))}: ${num(r.total)}"><i style="height:${Math.max(2, r.total / max * 100)}%"></i>${i % Math.max(1, Math.ceil(rows.length / 6)) === 0 ? `<span>${esc(date(r.time, false))}</span>` : ''}</div>`).join('')}</div></div>
    <div class="row-btns" style="margin-top:6px">${chip('now ' + num(rows[rows.length - 1].total), 'teal')}${chip('low ' + num(min))}${chip('high ' + num(max))}${btn('Find every copy', 'findItem', 'xs', { v, icon: 'fas fa-magnifying-glass-location' })}</div>`
    : empty('fas fa-chart-line', 'No history yet'), { size: 'lg', icon: 'fas fa-chart-line', sub: 'Total copies across every inventory, last 7 days' });
};

/* ═══ STAFF LEADERBOARD ═════════════════════════════════════════════════ */
page('staff', {
  label: 'Staff leaderboard', icon: 'fas fa-ranking-star',
  async enter() { const st = pd('staff'); st.range = st.range || '7d'; await staffLoad(); },
  render() {
    const st = pd('staff'); const d = st.data;
    const head = ph('Staff leaderboard', 'Who is doing what with inventories, ranked by number of actions', seg([['24h', '24h'], ['7d', '7d'], ['30d', '30d'], ['all', 'All time']], st.range, 'staffRange'));
    if (!d) return head + `<div class="content">${loading()}</div>`;
    const days = { '24h': 1, '7d': 7, '30d': 30, all: 365 }[st.range] || 7;
    const lim = d.limits || {};
    const rows = d.staff;
    const cell = (n, cls = '') => `<td class="num ${n ? cls : 'muted'}">${n ? num(n) : '-'}</td>`;
    return head + `<div class="content">${rows.length ? `<div class="tbl-wrap"><table class="tbl"><thead><tr><th></th><th>Staff</th><th class="num">Actions</th><th class="num">Gives</th><th class="num">Removals</th><th class="num">Wipes</th><th class="num">Edits</th><th class="num">Rollbacks</th><th class="num">Server-wide</th><th class="num">Items handed out</th><th class="num">Money handed out</th><th>Last active</th><th></th></tr></thead><tbody>
      ${rows.map((s, i) => {
        const hotItems = lim.itemsPerDay && s.items > lim.itemsPerDay * days;
        const hotMoney = lim.moneyPerDay && s.money > lim.moneyPerDay * days;
        return `<tr><td><span class="rank ${i < 3 ? 'r' + (i + 1) : ''}">${i + 1}</span></td><td><div class="cell">${av(s.name, 'sm')}<div class="tx"><b>${esc(s.name)}</b><span class="mono">${esc((s.id || '').slice(0, 22))}</span></div></div></td>
          <td class="num"><b>${num(s.total)}</b></td>${cell(s.gives)}${cell(s.removes)}${cell(s.wipes, 'tred')}${cell(s.edits)}${cell(s.rollbacks, 'tamber')}${cell(s.globals, 'tamber')}
          <td class="num">${s.items ? num(s.items) : '<span class="muted">-</span>'}${hotItems ? ' ' + chip('high', 'amber') : ''}</td>
          <td class="num">${s.money ? money(s.money) : '<span class="muted">-</span>'}${hotMoney ? ' ' + chip('high', 'amber') : ''}</td>
          <td>${esc(ago(s.last))}</td><td class="act">${btn('History', 'staffHistory', 'xs', { v: s.name })}</td></tr>`;
      }).join('')}</tbody></table></div>
      <div class="pager"><span>"High" means more than ${num(lim.itemsPerDay || 0)} items or ${money(lim.moneyPerDay || 0)} a day on average (Config.StaffBoard).</span></div>`
      : empty('fas fa-ranking-star', 'No staff actions in this range')}</div>`;
  },
});
async function staffLoad() { const st = pd('staff'); st.data = null; rerender(); const r = await rpc('staff:board', { range: st.range }); if (r.ok) { st.data = r.data; if (S.page === 'staff') rerender(); } else toast(r.err, 'error'); }
A.staffRange = v => { pd('staff').range = v; staffLoad(); };
A.staffHistory = v => { pd('audit').q = v; go('audit'); };
