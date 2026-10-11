/* ═══════════════════════════════════════════════════════════
   Tuning UI · business, dialogs, install tracker, HUD, sound
   ═══════════════════════════════════════════════════════════ */
'use strict';

/* ═══════════════ DIALOGS ═══════════════ */
const Modal = { owner: null };
Modal.show = function (html, size = '', fromUi = false) {
  const d = $('#dlg');
  d.className = `fr dialog anim-up ${size}`;
  d.innerHTML = html;
  Modal.owner = fromUi ? 'ui' : 'lua';
  $('#modal').hidden = false;
  $$('[data-close]', d).forEach((b) => (b.onclick = () => Modal.hide()));
};
Modal.hide = function (silent) {
  if ($('#modal').hidden) return;
  $('#modal').hidden = true;
  $('#dlg').innerHTML = '';
  if (Modal.owner === 'lua' && !silent) post('modal:close');
  Modal.owner = null;
};
const shell = (title, sub, body, actions = '') => `
  <div class="edge"><div class="shell">
    <header class="bar"><div class="ttl"><b>${title}</b><span>${sub}</span></div><span class="ver">v${esc((CFG && CFG.version) || '1.0.0')}</span><button class="pill-close" data-close>Close</button></header>
    <div class="body scroll">${body}</div>${actions ? `<div class="actions">${actions}</div>` : ''}
  </div></div>`;

const Dialogs = {};

Dialogs.diag = function (d) {
  const live = d.live || {};
  const perf = live.perf || {};
  const lvl = (v) => (v == null || v < 0 ? 'Stock' : 'L' + (v + 1));
  const codes = d.codes || [];
  Modal.show(shell('Diagnostics', `${esc(d.vehicle)} · ${esc(d.plate)}`, `
    <div class="grid3" style="margin-bottom:10px">
      <div class="tile"><small>Odometer</small><b>${Math.round(d.km || 0).toLocaleString('en-US')} km</b></div>
      <div class="tile"><small>Registration</small><b class="${d.registered ? 'teal' : 'amber'}">${d.registered ? 'Registered' : 'Unregistered'}</b></div>
      <div class="tile"><small>Service jobs</small><b>${d.jobs || 0}</b></div>
    </div>
    <div class="sect">Live data</div>
    <div class="card">${meter([['Engine', live.engine], ['Body', live.body], ['Fuel tank', live.tank], ['Fuel', live.fuel], ['Dirt', live.dirt, true]])}</div>
    <div class="grid3" style="margin-top:8px"><div class="tile"><small>Oil</small><b>${live.oil}</b></div><div class="tile"><small>Engine temp</small><b>${live.temp}°</b></div><div class="tile"><small>Turbo</small><b>${live.turbo ? 'Fitted' : 'None'}</b></div></div>
    <div class="sect">Part condition</div>
    <div class="card">${meter(Object.entries(d.wear || {}).map(([k, v]) => [cap(k), v]))}</div>
    <div class="sect">Fault codes</div>
    ${codes.length ? codes.map((c) => `<div class="dtc ${c.sev}"><code>${esc(c.code)}</code><span>${esc(c.text)}</span></div>`).join('') : '<div class="note"><i class="fa-solid fa-circle-check teal"></i><span>No faults stored.</span></div>'}
    <div class="sect">Build</div>
    <div class="chips">
      <span class="tag">Engine ${lvl(perf['11'])}</span><span class="tag">Brakes ${lvl(perf['12'])}</span><span class="tag">Gearbox ${lvl(perf['13'])}</span>
      <span class="tag">Suspension ${lvl(perf['15'])}</span><span class="tag">Armor ${lvl(perf['16'])}</span>
      ${d.ecu ? '<span class="tag t">ECU tuned</span>' : ''}${d.swap ? `<span class="tag t">${esc(d.swap)}</span>` : ''}
      ${d.nitrous ? `<span class="tag t">NOS ${Math.round(d.nitrous.amount || 0)}</span>` : ''}${d.antilag ? '<span class="tag a">Anti-lag</span>' : ''}
      ${d.launch ? '<span class="tag a">Launch control</span>' : ''}${d.airride ? '<span class="tag t">Air ride</span>' : ''}${d.locator ? '<span class="tag">GPS tracker</span>' : ''}
    </div>
    ${d.lastShop ? `<div class="muted" style="margin-top:12px;font-size:11px">Last serviced at ${esc(d.lastShop)} · ${new Date(d.lastTime * 1000).toLocaleDateString()}</div>` : ''}`));
};

Dialogs.police = function (d) {
  const sel = new Set(d.illegal.map((x) => x.id));
  const s = d.summary || {};
  Modal.show(shell('Vehicle inspection', `${esc(d.vehicle)} · ${esc(d.plate)}`, `
    <div class="grid3" style="margin-bottom:10px">
      <div class="tile"><small>Status</small><b class="${d.illegal.length ? 'red' : 'teal'}">${d.illegal.length ? d.illegal.length + ' violation' + (d.illegal.length > 1 ? 's' : '') : 'Road legal'}</b></div>
      <div class="tile"><small>Registration</small><b class="${d.registered ? '' : 'amber'}">${d.registered ? 'On file' : 'Not found'}</b></div>
      <div class="tile"><small>Odometer</small><b>${Math.round(d.km || 0).toLocaleString('en-US')} km</b></div>
    </div>
    <div class="sect">Findings</div>
    ${d.illegal.length ? d.illegal.map((x) => `<div class="chk on" data-id="${x.id}"><span class="box"><i class="fa-solid fa-check"></i></span><span class="grow">${esc(x.label)}</span><span class="tag r">Illegal</span></div>`).join('')
      : '<div class="note"><i class="fa-solid fa-circle-check teal"></i><span>Nothing illegal found.</span></div>'}
    <div class="sect">Recorded</div>
    <div class="chips">
      <span class="tag">Tint ${s.tint}</span><span class="tag">Camber ${(+s.camber || 0).toFixed(1)}°</span><span class="tag">Lowered ${Math.round((s.height || 0) * 1000)} mm</span>
      ${s.nitrous ? '<span class="tag r">Nitrous</span>' : ''}${s.antilag ? '<span class="tag r">Anti-lag</span>' : ''}${s.swap ? `<span class="tag">${esc(s.swap)}</span>` : ''}${s.airride ? '<span class="tag">Air ride</span>' : ''}
    </div>`,
    d.canStrip && d.illegal.length ? '<button class="btn warn" id="pStrip"><i class="fa-solid fa-screwdriver-wrench"></i>Remove selected parts</button>' : ''));
  $$('#dlg .chk').forEach((c) => (c.onclick = () => { const id = c.dataset.id; if (sel.has(id)) sel.delete(id); else sel.add(id); c.classList.toggle('on', sel.has(id)); }));
  const strip = $('#pStrip');
  if (strip) strip.onclick = () => { if (!sel.size) return; Modal.hide(true); post('police:strip', { ids: Array.from(sel) }); };
};

Dialogs.locator = function (d) {
  Modal.show(shell('GPS tracker', 'Ping a tracked vehicle', `
    <div class="rows">${d.list.map((v) => `<div class="row"><span class="ic"><i class="fa-solid fa-location-crosshairs"></i></span><span class="tx"><b>${esc(v.plate)}</b><span>${esc(v.model || 'Vehicle')}</span></span>
      <span class="rt"><button class="btn sm" data-p="${esc(v.plate)}"><i class="fa-solid fa-satellite-dish"></i>Ping</button><button class="btn sm pri" data-r="${esc(v.plate)}"><i class="fa-solid fa-route"></i>Route</button></span></div>`).join('')}</div>
    <div id="locRes" style="margin-top:10px"></div>`), 'mini');
  const go = async (plate, route) => {
    const r = await post('locator:ping', { plate, route });
    $('#locRes').innerHTML = r && r.ok ? `<div class="note"><i class="fa-solid fa-location-dot teal"></i><span>Signal found near <b>${esc(r.street)}</b>. Marked on your map.</span></div>`
      : `<div class="note e"><i class="fa-solid fa-signal"></i><span>${esc((r && r.error) || 'No signal.')}</span></div>`;
  };
  $$('#dlg [data-p]').forEach((b) => (b.onclick = () => go(b.dataset.p, false)));
  $$('#dlg [data-r]').forEach((b) => (b.onclick = () => go(b.dataset.r, true)));
};

Dialogs.quote = function (q) {
  let pay = q.payments[0], code = '', pct = 0, left = q.timeout;
  const render = () => {
    const t = q.totals;
    const disc = pct ? Math.floor(t.subtotal * pct / 100) : 0;
    Modal.show(shell('Quote', `${esc(q.shop)} · ${esc(q.mechanic)}`, `
      <div class="grid2" style="margin-bottom:10px"><div class="tile"><small>Vehicle</small><b>${esc(q.label || q.plate)}</b></div><div class="tile"><small>Expires in</small><b id="qLeft">${left}s</b></div></div>
      ${q.lines.map((l) => `<div class="line"><span class="ic"><i class="fa-solid fa-wrench"></i></span><span class="tx"><b>${esc(l.label)}</b></span><span class="pr">${money(l.price)}</span></div>`).join('')}
      <div class="totals" style="margin-top:12px">
        <div><span>Parts</span><b>${money(t.subtotal)}</b></div>
        ${disc ? `<div class="disc"><span>Discount (${pct}%)</span><b>-${money(disc)}</b></div>` : ''}
        ${t.labour ? `<div><span>Labour</span><b>${money(t.labour)}</b></div>` : ''}${t.tax ? `<div><span>Tax</span><b>${money(t.tax)}</b></div>` : ''}
        <div class="grand"><span>Total</span><b>${money(t.total - disc)}</b></div>
      </div>
      ${CFG.discounts ? `<div class="hrow" style="margin-top:12px"><input class="field grow" id="qCode" placeholder="Discount code" value="${esc(code)}"><button class="btn sm" id="qCodeOk">Apply</button></div>` : ''}
      <div class="seg" style="margin-top:10px" id="qPay">${q.payments.map((p) => `<button data-p="${p}" class="${p === pay ? 'on' : ''}">${cap(p)}</button>`).join('')}</div>`,
      '<button class="btn warn" id="qNo">Decline</button><button class="btn pri" id="qYes"><i class="fa-solid fa-check"></i>Accept & pay</button>'), 'mini');
    $$('#qPay button').forEach((b) => (b.onclick = () => { pay = b.dataset.p; $$('#qPay button').forEach((x) => x.classList.toggle('on', x === b)); }));
    const ok = $('#qCodeOk');
    if (ok) ok.onclick = async () => { code = $('#qCode').value.trim(); const r = await post('quote:code', { shopId: q.shopId, code }); pct = r && r.ok ? r.data.percent : 0; if (!pct) flash('Invalid code.'); render(); };
    $('#qNo').onclick = async () => { clearInterval(timer); await post('quote:answer', { id: q.id, accept: false }); Modal.hide(true); };
    $('#qYes').onclick = async () => {
      const r = await post('quote:answer', { id: q.id, accept: true, payment: pay, code: pct ? code : null });
      if (r && r.ok) { clearInterval(timer); Modal.hide(true); } else flash((r && r.error) || 'Payment failed.');
    };
    $$('#dlg [data-close]').forEach((b) => (b.onclick = () => $('#qNo').click()));
  };
  render();
  const timer = setInterval(() => {
    left -= 1;
    const e = $('#qLeft');
    if (!e) return clearInterval(timer);   // closed with Escape or replaced by another dialog
    e.textContent = left + 's';
    if (left <= 0) { clearInterval(timer); Modal.hide(); }
  }, 1000);
};

Dialogs.orders = function (d) {
  const pill = { open: 'a', accepted: 't', working: 't', done: '', cancelled: 'r' };
  Modal.show(shell('My tuning orders', 'Parts waiting to be fitted', d.list.map((o) => `
    <div class="ocard"><div class="top"><span class="id">#${o.id}</span><div class="tx"><b>${esc(o.label || o.model || o.plate)}</b><span>${esc(o.shopLabel)} · ${esc(o.plate)}${o.mechanic_name ? ' · ' + esc(o.mechanic_name) : ''}</span></div>
      <span class="tag ${pill[o.status] || ''}">${esc(o.status)}</span><b>${money(o.total)}</b>
      ${o.status === 'open' ? `<button class="btn sm warn" data-c="${o.id}">Cancel</button>` : ''}</div>
      <div class="prog"><i style="width:${o.count ? (o.done / o.count) * 100 : 0}%"></i></div></div>`).join('')), 'mini');
  $$('#dlg [data-c]').forEach((b) => (b.onclick = async () => {
    const r = await post('orders:cancel', { id: +b.dataset.c });
    if (r && r.ok) { flash('Order cancelled and refunded.', 's'); Modal.hide(); } else flash((r && r.error) || 'Could not cancel.');
  }));
};

/* ═══════════════ WORKSHOP PAGES (rendered inside the tablet) ═══════════════ */
const Biz = {
  get d() { return Tab.s && Tab.s.biz; },
  async reload() { await Tab.reloadBiz(); Tab.render(); },
};
async function bizCall(name, data, okMsg) {
  const r = await post(name, data);
  if (r && r.ok) { if (okMsg) Tab.toast(okMsg); return r; }
  Tab.toast((r && r.error) || 'That did not work.', true);
  return null;
}

const bizFlash = (m, k) => (Tab.open ? Tab.toast(m, k !== 's') : flash(m, k));
const BizPages = {};

BizPages.dashboard = function (p, d) {
  const k = d.kpi;
  p.innerHTML = `
    <div class="ph"><h2>Overview<small>Last 14 days of activity</small></h2></div>
    <div class="kgrid">
      <div class="k"><small><i class="fa-solid fa-wallet"></i>Balance</small><b>${money(d.balance)}</b></div>
      <div class="k"><small><i class="fa-solid fa-sun"></i>Today</small><b>${money(k.today)}</b></div>
      <div class="k"><small><i class="fa-solid fa-calendar-week"></i>7 days</small><b>${money(k.week)}</b></div>
      <div class="k"><small><i class="fa-solid fa-car-side"></i>Jobs 7d</small><b>${k.jobs}</b></div>
      <div class="k"><small><i class="fa-solid fa-clipboard-list"></i>Open orders</small><b>${k.orders}</b></div>
      <div class="k"><small><i class="fa-solid fa-user-gear"></i>On duty</small><b>${k.online}</b></div>
    </div>
    <div class="split">
      <div class="panel"><h4><i class="fa-solid fa-chart-column"></i>Revenue<span>daily</span></h4><div class="chart">${chart(d.chart)}</div></div>
      <div class="panel"><h4><i class="fa-solid fa-bullhorn"></i>Announcements</h4>
        ${d.rank.manager ? `<div class="hrow" style="margin-bottom:10px"><input class="field grow" id="annIn" maxlength="${d.annLength}" placeholder="Message the crew"><button class="btn pri sm" id="annGo"><i class="fa-solid fa-paper-plane"></i></button></div>` : ''}
        <div class="feed scroll">${d.announcements.length ? d.announcements.map((a) => `<div class="msg"><b>${esc(a.author)}</b><time>${new Date(a.t * 1000).toLocaleDateString()}</time><p>${esc(a.message)}</p>${d.rank.manager ? `<button class="x" data-del="${a.id}"><i class="fa-solid fa-xmark"></i></button>` : ''}</div>`).join('') : '<div class="muted" style="font-size:11.5px">No announcements.</div>'}</div>
      </div>
    </div>
    <div class="panel" style="margin-top:12px"><h4><i class="fa-solid fa-trophy"></i>Top mechanics</h4>
      ${d.leaderboard.length ? `<table class="tbl"><thead><tr><th>#</th><th>Mechanic</th><th>Parts fitted</th><th style="text-align:right">Earned</th></tr></thead><tbody>${d.leaderboard.map((m, i) => `<tr><td><b class="${i < 3 ? 'teal' : ''}">${i + 1}</b></td><td><div class="hrow">${av(m.avatar, m.name, 'sm')}<b>${esc(m.name)}</b></div></td><td>${m.installs}</td><td style="text-align:right">${money(m.earned)}</td></tr>`).join('')}</tbody></table>` : '<div class="muted" style="font-size:11.5px">No jobs finished yet.</div>'}
    </div>`;
  const go = $('#annGo');
  if (go) go.onclick = async () => { const m = $('#annIn').value.trim(); if (!m) return; if (await bizCall('biz:announce', { message: m }, 'Announcement sent.')) Biz.reload(); };
  $$('[data-del]', p).forEach((b) => (b.onclick = async () => { await bizCall('biz:delAnnounce', { id: +b.dataset.del }); Biz.reload(); }));
};

function chart(rows) {
  const W = 620, H = 190, pad = 22;
  const max = Math.max(1, ...rows.map((r) => r.revenue));
  const bw = (W - pad) / rows.length;
  return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
    ${[0.25, 0.5, 0.75, 1].map((f) => `<line x1="${pad}" x2="${W}" y1="${(H - 20) * (1 - f)}" y2="${(H - 20) * (1 - f)}" stroke="rgba(255,255,255,.05)"/>`).join('')}
    ${rows.map((r, i) => {
      const h = ((H - 24) * r.revenue) / max;
      const x = pad + i * bw + bw * 0.18;
      return `<g><title>${r.day}: ${money(r.revenue)} · ${r.jobs} jobs</title>
        <rect x="${x}" y="${H - 20 - h}" width="${bw * 0.64}" height="${Math.max(h, 1)}" rx="3" fill="${i === rows.length - 1 ? '#0fd4c4' : '#08afa2'}" opacity="${r.revenue ? 0.9 : 0.25}"/>
        ${i % 2 === 0 ? `<text x="${x + bw * 0.32}" y="${H - 4}" fill="#63696d" font-size="10" text-anchor="middle">${r.day}</text>` : ''}</g>`;
    }).join('')}
    <text x="0" y="10" fill="#63696d" font-size="10">${money(max)}</text>
  </svg>`;
}

BizPages.callouts = async function (p) {
  p.innerHTML = '<div class="ph"><h2>Roadside callouts<small>Fix them on the spot, or tow wrecks back to the shop</small></h2><button class="btn sm" id="cRef"><i class="fa-solid fa-rotate"></i>Refresh</button></div><div id="cList"></div>';
  $('#cRef').onclick = () => BizPages.callouts(p);
  const list = (await post('biz:callouts')) || [];
  const box = $('#cList');
  if (!box) return;
  box.innerHTML = list.length ? `<div class="rows">${list.map((c) => `
    <div class="row"><span class="ic"><i class="fa-solid ${c.icon}"></i></span><span class="tx"><b>${esc(c.fault)} ${c.kind === 'tow' ? '<span class="tag a" style="display:inline;margin-left:6px">Tow · flatbed</span>' : '<span class="tag" style="display:inline;margin-left:6px">Roadside fix</span>'}</b><span>${c.taken ? 'Taken by ' + esc(c.takenBy) : 'Waiting ' + Math.max(1, Math.round(c.age / 60)) + ' min'}</span></span>
      <span class="rt"><b class="teal">${money(c.reward)}</b><button class="ibtn" data-w="${c.x},${c.y}" title="Waypoint"><i class="fa-solid fa-location-dot"></i></button>
      ${!c.taken ? `<button class="btn sm pri" data-t="${c.id}">Accept</button>` : ''}</span></div>`).join('')}</div>`
    : '<div class="empty"><i class="fa-solid fa-truck-pickup"></i><b>All quiet</b><span>New callouts come in every few minutes.</span></div>';
  $$('[data-t]', box).forEach((b) => (b.onclick = async () => { const r = await post('biz:takeCallout', { id: +b.dataset.t }); if (!r || !r.ok) bizFlash((r && r.error) || 'Taken already.'); }));
  $$('[data-w]', box).forEach((b) => (b.onclick = () => { const [x, y] = b.dataset.w.split(',').map(Number); post('biz:waypoint', { x, y }); bizFlash('Waypoint set.', 's'); }));
};

BizPages.employees = function (p, d) {
  const grades = d.grades || [];
  const gname = (g) => (grades.find((x) => x.level === g) || {}).label || 'Grade ' + g;
  p.innerHTML = `
    <div class="ph"><h2>Employees<small>${d.employees.length} on the payroll</small></h2><button class="btn pri sm" id="eHire"><i class="fa-solid fa-user-plus"></i>Hire nearby</button></div>
    <table class="tbl"><thead><tr><th>Name</th><th>Grade</th><th>Status</th><th style="text-align:right">Actions</th></tr></thead><tbody>
    ${d.employees.map((e) => `<tr><td><div class="hrow">${av(e.avatar, e.name)}<b>${esc(e.name)}</b></div></td>
      <td>${d.rank.boss ? `<select class="field" style="height:30px;width:170px" data-g="${esc(e.identifier)}">${grades.map((g) => `<option value="${g.level}" ${g.level === e.grade ? 'selected' : ''} ${g.level > d.me.grade ? 'disabled' : ''}>${esc(g.label)}</option>`).join('')}</select>` : esc(gname(e.grade))}</td>
      <td><span class="dotst ${e.online ? 'on' : ''}"></span>${e.online ? (e.onDuty === false ? 'Off duty' : 'On duty') : 'Offline'}</td>
      <td><div class="act">${d.rank.boss ? `<input class="field" style="width:100px;height:28px" type="number" min="1" max="${d.maxBonus}" placeholder="Bonus" data-bv="${esc(e.identifier)}"><button class="btn sm" data-b="${esc(e.identifier)}"><i class="fa-solid fa-gift"></i></button><button class="btn sm warn" data-f="${esc(e.identifier)}">Fire</button>` : ''}</div></td></tr>`).join('')}
    </tbody></table>`;
  $$('[data-g]', p).forEach((s) => (s.onchange = async () => { await bizCall('biz:grade', { identifier: s.dataset.g, grade: +s.value }, 'Grade updated.'); Biz.reload(); }));
  $$('[data-b]', p).forEach((b) => (b.onclick = async () => { const v = +$(`[data-bv="${b.dataset.b}"]`, p).value; if (v > 0) { await bizCall('biz:bonus', { identifier: b.dataset.b, amount: v }, 'Bonus paid.'); Biz.reload(); } }));
  $$('[data-f]', p).forEach((b) => (b.onclick = async () => {
    if (b.dataset.confirm !== '1') { b.dataset.confirm = '1'; b.textContent = 'Confirm'; return; }
    await bizCall('biz:fire', { identifier: b.dataset.f }, 'Employee let go.'); Biz.reload();
  }));
  $('#eHire').onclick = async () => {
    const list = (await post('biz:nearby')) || [];
    Modal.show(shell('Hire', 'People within 10 metres', list.length ? `<div class="rows">${list.map((x) => `<button class="row" data-h="${x.id}"><span class="ic"><i class="fa-solid fa-user"></i></span><span class="tx"><b>${esc(x.name)}</b><span>${esc(x.job || '')}</span></span><i class="fa-solid fa-user-plus chev"></i></button>`).join('')}</div>` : '<div class="empty"><i class="fa-solid fa-user-slash"></i><b>Nobody nearby</b></div>'), 'mini', true);
    $$('#dlg [data-h]').forEach((b) => (b.onclick = async () => { Modal.hide(true); await bizCall('biz:hire', { target: +b.dataset.h }, 'Hired.'); Biz.reload(); }));
  };
};

BizPages.discounts = function (p, d) {
  let pct = d.discounts.percentages[0], uses = d.discounts.uses[0];
  p.innerHTML = `
    <div class="ph"><h2>Discount codes<small>Hand them out to regulars and events</small></h2></div>
    <div class="split"><div>
      ${d.codes.length ? `<table class="tbl"><thead><tr><th>Code</th><th>Discount</th><th>Uses left</th><th>By</th><th></th></tr></thead><tbody>${d.codes.map((c) => `<tr><td><b>${esc(c.code)}</b></td><td class="teal">${c.percent}%</td><td>${c.uses}</td><td class="dim">${esc(c.created_by || '')}</td><td><div class="act"><button class="ibtn" data-cp="${esc(c.code)}"><i class="fa-regular fa-copy"></i></button><button class="ibtn" data-x="${esc(c.code)}"><i class="fa-solid fa-trash"></i></button></div></td></tr>`).join('')}</tbody></table>`
        : '<div class="empty"><i class="fa-solid fa-tags"></i><b>No active codes</b></div>'}
    </div>
    <div class="panel"><h4><i class="fa-solid fa-plus"></i>New code</h4>
      <span class="lbl">Discount</span><div class="chips" id="dPct">${d.discounts.percentages.map((x) => `<button class="chip ${x === pct ? 'on' : ''}" data-v="${x}">${x}%</button>`).join('')}</div>
      <span class="lbl" style="margin-top:14px">Uses</span><div class="chips" id="dUses">${d.discounts.uses.map((x) => `<button class="chip ${x === uses ? 'on' : ''}" data-v="${x}">${x}</button>`).join('')}</div>
      <button class="btn pri wide" style="margin-top:16px" id="dGen"><i class="fa-solid fa-wand-magic-sparkles"></i>Generate</button>
    </div></div>`;
  const pick = (id, set) => $$(`#${id} .chip`).forEach((c) => (c.onclick = () => { set(+c.dataset.v); $$(`#${id} .chip`).forEach((x) => x.classList.toggle('on', x === c)); }));
  pick('dPct', (v) => (pct = v));
  pick('dUses', (v) => (uses = v));
  $('#dGen').onclick = async () => { const r = await bizCall('biz:createCode', { percent: pct, uses }); if (r) { copyText(r.data); bizFlash(`Code ${r.data} created and copied.`, 's'); Biz.reload(); } };
  $$('[data-cp]', p).forEach((b) => (b.onclick = () => { copyText(b.dataset.cp); bizFlash('Copied.', 's'); }));
  $$('[data-x]', p).forEach((b) => (b.onclick = async () => { await bizCall('biz:deleteCode', { code: b.dataset.x }); Biz.reload(); }));
};

BizPages.finance = function (p, d) {
  let margin = d.margin, comm = d.commission, labour = d.labour;
  p.innerHTML = `
    <div class="ph"><h2>Finance<small>Account, pricing and payouts</small></h2></div>
    <div class="split"><div>
      <div class="panel"><h4><i class="fa-solid fa-wallet"></i>Workshop account<span>${money(d.balance)}</span></h4>
        <div class="hrow"><input class="field grow" type="number" min="1" id="fAmt" placeholder="Amount"><button class="btn" id="fDep"><i class="fa-solid fa-arrow-down"></i>Deposit</button><button class="btn pri" id="fWd"><i class="fa-solid fa-arrow-up"></i>Withdraw</button></div>
      </div>
      <div class="panel" style="margin-top:12px"><h4><i class="fa-solid fa-receipt"></i>Transactions</h4>
        ${(d.tx || []).length ? `<table class="tbl"><tbody>${d.tx.map((t) => `<tr><td><span class="tag">${esc(t.kind)}</span></td><td class="dim">${esc(t.actor || '')}${t.note ? ' · ' + esc(t.note) : ''}</td><td class="muted">${new Date(t.t * 1000).toLocaleDateString()}</td><td style="text-align:right"><b class="${t.amount >= 0 ? 'teal' : 'red'}">${t.amount >= 0 ? '+' : ''}${money(t.amount)}</b></td></tr>`).join('')}</tbody></table>` : '<div class="muted" style="font-size:11.5px">No transactions yet.</div>'}
      </div></div>
      <div class="panel"><h4><i class="fa-solid fa-sliders"></i>Rates</h4><div class="stack" id="fRates"></div>
        <button class="btn pri wide" style="margin-top:16px" id="fSave"><i class="fa-solid fa-floppy-disk"></i>Save rates</button></div>
    </div>`;
  const rates = $('#fRates');
  rates.appendChild(range({ label: 'Price margin', min: d.marginRange[0], max: d.marginRange[1], step: 1, value: margin, fmt: (x) => (x > 0 ? '+' : '') + x + '%', hint: 'Applied to every part sold here.', onInput: (x) => (margin = x) }));
  rates.appendChild(range({ label: 'Mechanic commission', min: d.commissionRange[0], max: d.commissionRange[1], step: 1, value: comm, fmt: (x) => x + '%', hint: 'Share of each finished order paid to the mechanic.', onInput: (x) => (comm = x) }));
  if (d.labourRange) rates.appendChild(range({ label: 'Labour rate', min: d.labourRange[0], max: d.labourRange[1], step: 25, value: labour, fmt: (x) => money(x) + ' / part', hint: 'Charged per fitted part on top of the parts price.', onInput: (x) => (labour = x) }));
  $('#fSave').onclick = async () => { if (await bizCall('biz:rates', { margin, commission: comm, labour }, 'Rates saved.')) Biz.reload(); };
  const amt = () => Math.floor(+$('#fAmt').value || 0);
  $('#fDep').onclick = async () => { if (amt() > 0 && await bizCall('biz:deposit', { amount: amt() }, 'Deposited.')) Biz.reload(); };
  $('#fWd').onclick = async () => { if (amt() > 0 && await bizCall('biz:withdraw', { amount: amt() }, 'Withdrawn.')) Biz.reload(); };
};

BizPages.upgrades = function (p, d) {
  p.innerHTML = `<div class="ph"><h2>Equipment<small>Unlock more services for your workshop</small></h2><span class="tag t">Balance ${money(d.balance)}</span></div>
    <div class="upg">${(d.upgrades || []).map((u) => `<div class="upc ${u.owned ? 'owned' : ''}"><span class="ic"><i class="fa-solid ${u.icon}"></i></span><b>${esc(u.label)}</b>
      <span>Unlocks: ${(u.unlocks || []).map((x) => esc(CFG.parts[x] ? CFG.parts[x].label : cap(x))).join(', ')}</span>
      ${u.owned ? '<span class="tag t" style="align-self:flex-start">Installed</span>' : d.rank.boss ? `<button class="btn pri" data-u="${u.key}">Buy ${money(u.price)}</button>` : `<span class="tag">${money(u.price)}</span>`}</div>`).join('')}</div>`;
  $$('[data-u]', p).forEach((b) => (b.onclick = async () => { if (await bizCall('biz:buyUpgrade', { key: b.dataset.u }, 'Equipment installed.')) Biz.reload(); }));
};


/* ═══════════════ INSTALL TRACKER ═══════════════ */
const Inst = {
  last: null,
  state(s) {
    $('#inst').hidden = false;
    $('#instTitle').textContent = `Order #${s.id}`;
    $('#instSub').textContent = `${s.label || ''} · ${s.plate}${s.customer ? ' · ' + s.customer : ''}`;
    $('#instCount').textContent = `${s.done}/${s.total}`;
    $('#instStep').textContent = s.step || 'Ready';
    $('#instHelp').textContent = s.help || '';
    $('#instBar').style.width = (s.total ? (s.done / s.total) * 100 : 0) + '%';
    const miss = $('#instMiss');
    miss.hidden = !(s.missing && s.missing.length);
    if (!miss.hidden) miss.innerHTML = `<b><i class="fa-solid fa-box-open"></i> Missing parts</b>${s.missing.map((m) => `<span class="tag r">${esc(m.label || m)}${m.need - m.have > 1 ? ' x' + (m.need - m.have) : ''}</span>`).join('')}`;
    const list = $('#instList');
    list.innerHTML = s.items.map((i) => `<div class="it ${i.done ? 'done' : ''} ${i.id === s.current ? 'cur' : ''}"><i class="st fa-solid fa-check"></i><span>${esc(i.label)}</span>${!i.done && i.needs && i.needs.length ? `<em class="nd">${i.needs.map((n) => esc(n.label || n)).join(', ')}</em>` : ''}</div>`).join('');
    // keep the current (or next) step in view
    const cur = $('.it.cur', list) || $('.it:not(.done)', list);
    if (cur && Inst.last !== (s.current || '') + s.done) {
      Inst.last = (s.current || '') + s.done;
      const top = cur.offsetTop - list.clientHeight / 2 + cur.clientHeight / 2;
      list.scrollTo({ top: Math.max(0, top), behavior: 'smooth' });
    }
  },
  close() { $('#inst').hidden = true; Inst.last = null; },
};

/* ═══════════════ HUD ═══════════════ */
const Hud = { toastTimer: null };
(() => { $('#nosCells').innerHTML = '<i></i>'.repeat(12); })();
Hud.nitrous = function (d) {
  const n = $('#nos');
  n.hidden = !d.show;
  if (!d.show) return;
  const pct = clamp(d.pct || 0, 0, 1);
  $('#nosPct').textContent = Math.round(pct * 100) + '%';
  $$('#nosCells i').forEach((c, i) => c.classList.toggle('on', i < Math.ceil(pct * 12)));
  n.classList.toggle('boost', !!(d.boosting || d.purging));
  n.classList.toggle('low', pct < 0.2);
};
Hud.perf = function (d) {
  const p = $('#perf');
  p.hidden = !d.show;
  if (!d.show) return;
  $('#perfLabel').textContent = d.label || '';
  $('#perfTime').textContent = d.time != null ? d.time.toFixed(d.final ? 3 : 2) + 's' : '--';
  $('#perfState').textContent = d.final ? 'Final time' : d.state || (d.speed != null ? `${d.speed} ${d.units}` : '');
  $('#perfBar').style.width = (d.progress != null ? clamp(d.progress, 0, 1) * 100 : d.final ? 100 : 0) + '%';
  $('#perfRes').innerHTML = d.final && d.rank ? `<span class="tag t">Rank #${d.rank}</span>${d.pb ? '<span class="tag a">Personal best</span>' : ''}` : '';
};
Hud.testdrive = function (d) {
  $('#td').hidden = !d.show;
  if (!d.show) return;
  $('#tdLeft').textContent = d.left + 's';
  $('#tdDist').textContent = `${d.dist} / ${d.radius} m from the shop`;
};
Hud.gear = function (d) {
  const g = $('#gear');
  g.hidden = !d.show;
  if (!d.show) return;
  $('#gearMode').textContent = d.manual ? 'MANUAL' : 'AUTO';
  $('#gearN').textContent = d.gear === 0 ? 'R' : d.gear == null ? 'N' : d.gear;
  g.classList.toggle('red', !!d.redline);
};
Hud.toast = function (d) {
  const t = $('#toast');
  clearTimeout(Hud.toastTimer);
  if (d.hide) { t.hidden = true; return; }
  $('#toastIc').className = 'fa-solid ' + (d.icon || 'fa-circle-info');
  $('#toastTx').textContent = d.text || '';
  t.hidden = false;
  if (!d.hold) Hud.toastTimer = setTimeout(() => (t.hidden = true), 2200);
};

/* ═══════════════ SOUND (install files + synthesised effects) ═══════════════ */
const Sfx = { ctx: null, loops: {} };
Sfx.ac = function () { if (!Sfx.ctx) Sfx.ctx = new (window.AudioContext || window.webkitAudioContext)(); return Sfx.ctx; };
Sfx.noise = function (ac, secs) {
  const buf = ac.createBuffer(1, Math.floor(ac.sampleRate * secs), ac.sampleRate);
  const ch = buf.getChannelData(0);
  for (let i = 0; i < ch.length; i++) ch[i] = Math.random() * 2 - 1;
  const src = ac.createBufferSource();
  src.buffer = buf;
  return src;
};
Sfx.files = {};
Sfx.play = function ({ name, file, volume = 0.5, stop }) {
  if (file) {
    try {
      const a = new Audio(`sounds/${file}.ogg`);
      a.volume = clamp(volume, 0, 1);
      a.play().catch(() => {});
    } catch (e) {}
    return;
  }
  let ac;
  try { ac = Sfx.ac(); } catch (e) { return; }
  const now = ac.currentTime;
  const out = ac.createGain();
  out.gain.value = volume;
  out.connect(ac.destination);
  if (stop) { const l = Sfx.loops[name]; if (l) { l.g.gain.setTargetAtTime(0, now, 0.12); l.src.stop(now + 0.6); delete Sfx.loops[name]; } return; }

  if (name === 'hiss' || name === 'purge') {
    const len = name === 'purge' ? 2 : 1.2;
    const src = Sfx.noise(ac, len);
    const bp = ac.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 5200; bp.Q.value = 0.6;
    const g = ac.createGain();
    src.connect(bp).connect(g).connect(out);
    if (name === 'purge') {
      src.loop = true;
      g.gain.setValueAtTime(0, now); g.gain.linearRampToValueAtTime(0.9, now + 0.08);
      Sfx.loops.purge = { src, g };
    } else {
      g.gain.setValueAtTime(0.9, now); g.gain.exponentialRampToValueAtTime(0.001, now + 1.1);
      src.stop(now + 1.2);
    }
    src.start(now);
  } else if (name === 'bov') {
    const src = Sfx.noise(ac, 0.5);
    const bp = ac.createBiquadFilter(); bp.type = 'bandpass'; bp.Q.value = 2.2;
    bp.frequency.setValueAtTime(3800, now); bp.frequency.exponentialRampToValueAtTime(900, now + 0.4);
    const g = ac.createGain();
    g.gain.setValueAtTime(0.0, now); g.gain.linearRampToValueAtTime(1, now + 0.02); g.gain.exponentialRampToValueAtTime(0.001, now + 0.45);
    src.connect(bp).connect(g).connect(out);
    src.start(now); src.stop(now + 0.5);
  } else if (name === 'crackle') {
    for (let i = 0; i < 3 + Math.floor(Math.random() * 3); i++) {
      const t = now + i * (0.03 + Math.random() * 0.06);
      const src = Sfx.noise(ac, 0.08);
      const lp = ac.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900 + Math.random() * 900;
      const g = ac.createGain();
      g.gain.setValueAtTime(1.4, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.07);
      src.connect(lp).connect(g).connect(out);
      src.start(t); src.stop(t + 0.08);
    }
  } else if (name === 'ping') {
    [880, 1320].forEach((f, i) => {
      const o = ac.createOscillator(); o.type = 'sine'; o.frequency.value = f;
      const g = ac.createGain(); const t = now + i * 0.12;
      g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(0.4, t + 0.01); g.gain.exponentialRampToValueAtTime(0.001, t + 0.35);
      o.connect(g).connect(out); o.start(t); o.stop(t + 0.4);
    });
  }
};

/* ═══════════════ REMOTES: lighting controller / stancer kit ═══════════════ */
const Remote = { open: false, d: null, v: null };
Remote.send = throttle((v) => post('remote:' + Remote.d.kind, v), 80);
Remote.show = function (d) {
  Remote.open = true;
  Remote.d = d;
  $('#remote').hidden = false;
  $('#rTitle').textContent = d.kind === 'lighting' ? 'Lighting controller' : 'Stancer kit';
  $('#rSub').textContent = `${d.label} · ${d.plate}`;
  const body = $('#rBody');
  body.innerHTML = '';
  if (d.kind === 'lighting') {
    const v = Remote.v = { l: !!d.l, r: !!d.r, f: !!d.f, b: !!d.b, color: d.color, pattern: d.pattern, speed: d.speed };
    const car = el(`<div class="car-top"><div class="body"></div><button class="side s-f" data-s="f"></button><button class="side s-b" data-s="b"></button><button class="side s-l" data-s="l"></button><button class="side s-r" data-s="r"></button></div>`);
    const all = el(`<div class="chips" style="justify-content:center;margin-bottom:12px"><button class="chip" data-all="1">All on</button><button class="chip" data-all="0">All off</button></div>`);
    const presets = el(`<div class="swatches" style="margin-bottom:12px">${d.presets.map((x) => `<button class="swatch" data-h="${x}" style="background:${x}"></button>`).join('')}</div>`);
    const holder = el('<div></div>');
    const pats = el(`<div style="margin-top:14px"><div class="sect">Mode</div><div class="rgrid">${d.patterns.map((p) => `<button data-p="${p[0]}" ${!d.canPattern && p[0] !== 'static' ? 'disabled' : ''}><i class="fa-solid fa-wave-square"></i>${esc(p[1])}</button>`).join('')}</div>${!d.canPattern ? '<div class="hint muted" style="font-size:10.5px;margin-top:8px">Modes need the Underglow Mode upgrade from a tuning shop.</div>' : ''}</div>`);
    const sp = range({ label: 'Speed', min: 1, max: 10, step: 1, value: v.speed, onInput: (x) => { v.speed = x; paint(); } });
    sp.style.marginTop = '12px';
    [car, all, presets, holder, pats, sp].forEach((x) => body.appendChild(x));
    const paint = () => {
      car.style.setProperty('--glow', rgb2hex(v.color));
      $$('.side', car).forEach((s) => s.classList.toggle('on', !!v[s.dataset.s]));
      $$('[data-p]', pats).forEach((b) => b.classList.toggle('on', b.dataset.p === v.pattern));
      Remote.send(v);
    };
    const pk = Picker(holder, v.color, (c) => { v.color = c; paint(); });
    $$('.side', car).forEach((s) => (s.onclick = () => { v[s.dataset.s] = !v[s.dataset.s]; paint(); }));
    $$('[data-all]', all).forEach((b) => (b.onclick = () => { const on = b.dataset.all === '1'; v.l = v.r = v.f = v.b = on; paint(); }));
    $$('.swatch', presets).forEach((s) => (s.onclick = () => { v.color = hex2rgb(s.dataset.h); pk.set(v.color); paint(); }));
    $$('[data-p]', pats).forEach((b) => (b.onclick = () => { v.pattern = b.dataset.p; paint(); }));
    paint();
  } else {
    const v = Remote.v = { stance: Object.assign({}, d.stance), height: d.height };
    const mm = (x) => (x >= 0 ? '+' : '') + Math.round(x * 1000) + ' mm';
    const deg = (x) => x.toFixed(1) + '°';
    const card = el('<div class="card stack"></div>');
    [['oF', 'Front track', d.offset, mm], ['oR', 'Rear track', d.offset, mm], ['cF', 'Front camber', d.camber, deg], ['cR', 'Rear camber', d.camber, deg]].forEach(([k, label, lim, fmt]) => {
      card.appendChild(range({ label, min: lim.min, max: lim.max, step: lim.step, value: v.stance[k] || 0, fmt, onInput: (x) => { v.stance[k] = x; Remote.send(v); } }));
    });
    body.appendChild(card);
    const hc = el('<div class="card" style="margin-top:8px"></div>');
    if (d.airride) hc.innerHTML = '<div class="note"><i class="fa-solid fa-wind"></i><span>Air ride fitted: use Page Up / Page Down while driving for height.</span></div>';
    else hc.appendChild(range({ label: 'Ride height', min: d.heightRange.min, max: d.heightRange.max, step: d.heightRange.step, value: v.height, fmt: (x) => (x === 0 ? 'Stock' : (x > 0 ? '-' : '+') + Math.abs(Math.round(x * 1000)) + ' mm'), onInput: (x) => { v.height = x; Remote.send(v); } }));
    body.appendChild(hc);
  }
  $('#rFoot').innerHTML = '<button class="btn" id="rCancel"><i class="fa-solid fa-rotate-left"></i>Cancel</button><button class="btn pri" id="rSave"><i class="fa-solid fa-floppy-disk"></i>Save to car</button>';
  $('#rCancel').onclick = Remote.cancel;
  $('#rSave').onclick = async () => {
    const r = await post('remote:' + d.kind, Object.assign({}, Remote.v, { save: true }));
    if (!r || !r.ok) flash((r && r.error) || 'Could not save.');
  };
};
Remote.hide = () => { Remote.open = false; Remote.d = null; $('#remote').hidden = true; };
Remote.cancel = () => post('remote:cancel');
$('#rClose').onclick = Remote.cancel;

/* ═══════════════ MESSAGE ROUTER ═══════════════ */
const Router = {
  init: (d) => { CFG = d; },
  'menu:open': (d) => Tune.open(d),
  'menu:close': () => Tune.hide(),
  'menu:quoteAnswer': (d) => Tune.quoteAnswer(d),
  'menu:hotspots': (d) => Hot.render(Array.isArray(d) ? d : []),
  'tablet:open': (d) => Tab.show(d),
  'tablet:close': () => Tab.hide(),
  'tablet:refresh': (d) => Tab.refresh(d),
  'tablet:message': (d) => Tab.message(d),
  'tablet:avatar': (d) => Tab.avatar(d),
  'editor:open': (d) => Ed.show(d),
  'editor:close': () => Ed.hide(),
  'editor:hide': (d) => $('#editorx').classList.toggle('away', d === true),
  'editor:walk': (d) => Ed.walk(d === true),
  'obj:set': (d) => Obj.set(d),
  'obj:clear': () => Obj.clear(),
  'remote:open': (d) => Remote.show(d),
  'remote:close': () => Remote.hide(),
  'install:state': (d) => Inst.state(d),
  'install:close': () => Inst.close(),
  'diag:open': (d) => Dialogs.diag(d),
  'police:open': (d) => Dialogs.police(d),
  'locator:open': (d) => Dialogs.locator(d),
  'quote:open': (d) => Dialogs.quote(d),
  'orders:mine': (d) => Dialogs.orders(d),
  'modal:hide': () => Modal.hide(true),
  'hud:nitrous': (d) => Hud.nitrous(d),
  'hud:perf': (d) => Hud.perf(d),
  'hud:testdrive': (d) => Hud.testdrive(d),
  'hud:toast': (d) => Hud.toast(d),
  'hud:gear': (d) => Hud.gear(d),
  sound: (d) => Sfx.play(d),
};

window.addEventListener('message', (e) => {
  const m = e.data;
  if (!m || !m.action || !Router[m.action]) return;
  if (!CFG && m.action !== 'init') return;
  try { Router[m.action](m.data || {}); } catch (err) { console.error('[tuning ui]', m.action, err); }
});

post('ready');

/* ═══════════════ OBJECTIVE TRACKER (supply runs, tow jobs) ═══════════════ */
const Obj = { t: null, end: 0 };
Obj.set = function (d) {
  const box = $('#obj');
  box.hidden = false;
  if (d.left != null) Obj.end = Date.now() + d.left * 1000; else Obj.end = 0;
  $('#objIc').className = 'fa-solid ' + (d.icon || 'fa-list-check');
  $('#objTitle').textContent = d.title || '';
  $('#objList').innerHTML = (d.steps || []).map((s) => `<li class="${s.state}"><span class="ck">${s.state === 'done' ? '<i class="fa-solid fa-check"></i>' : ''}</span><span>${esc(s.label)}</span>${s.of ? `<em>${s.n || 0}/${s.of}</em>` : ''}</li>`).join('');
  clearInterval(Obj.t);
  Obj.tick();
  if (Obj.end) Obj.t = setInterval(Obj.tick, 1000);
};
Obj.tick = function () {
  const ot = $('#objTime');
  if (!Obj.end) { ot.textContent = ''; return; }
  const left = Math.max(0, Math.round((Obj.end - Date.now()) / 1000));
  ot.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`;
  ot.classList.toggle('low', left < 120);
};
Obj.clear = function () { clearInterval(Obj.t); $('#obj').hidden = true; };
