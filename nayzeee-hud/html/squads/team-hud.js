/* Team HUD cards. One renderer for the squads frame (live cards) and the nayzeee-hud settings (previews):
   both pages load this file and team-hud.css, so a preview is always the real thing. */
(() => {
'use strict';

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const initials = (n) => String(n || '?').trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join('').toUpperCase();

const STYLES = [['cards', 'Classic'], ['slim', 'Slim'], ['frost', 'Frost'], ['loadout', 'Loadout'], ['tactical', 'Tactical'],
  ['arena', 'Arena'], ['rings', 'Rings'], ['heads', 'Heads'], ['tiles', 'Tiles'], ['minimal', 'Minimal']];
// styles from older versions map onto the closest new one
const LEGACY = { bars: 'slim', pills: 'arena', glass: 'frost', stripe: 'slim' };
const norm = (s) => {
  s = LEGACY[s] || s;
  return STYLES.some((x) => x[0] === s) ? s : 'cards';
};

// ─── weapons ───────────────────────────────────────────────
function weaponClass(name) {
  if (!name) return null;
  const n = String(name).toUpperCase().replace(/^WEAPON_/, '');
  if (n === 'UNARMED') return null;
  if (/SNIPER|MARKSMANRIFLE|PRECISIONRIFLE|MUSKET/.test(n)) return 'sniper';
  if (/RPG|LAUNCHER|MINIGUN|RAILGUN|FIREWORK/.test(n)) return 'heavy';
  if (/SHOTGUN/.test(n)) return 'shotgun';
  if (/^(MG|COMBATMG|GUSENBERG)/.test(n)) return 'mg';
  if (/SMG|PDW|MACHINEPISTOL|TECPISTOL/.test(n)) return 'smg';
  if (/RIFLE|CARBINE|BULLPUP/.test(n)) return 'rifle';
  if (/PISTOL|REVOLVER|DOUBLEACTION|STUNGUN|FLAREGUN/.test(n)) return 'pistol';
  if (/GRENADE|MOLOTOV|STICKY|PIPEBOMB|SMOKE|BZGAS|FLARE$|SNOWBALL|BALL$|PROXMINE|ACIDPACKAGE/.test(n)) return 'throw';
  if (/PETROLCAN|EXTINGUISHER|HAZARDCAN|FERTILIZERCAN|PARACHUTE/.test(n)) return 'tool';
  return 'melee';
}

const weaponLabel = (name) => String(name || '').replace(/^WEAPON_/i, '').replace(/_MK2$/i, ' Mk II').replace(/_/g, ' ')
  .toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase());

// side-on silhouettes, muzzle to the right; used when no weapon picture loads
const SIL = {
  pistol: '<path d="M20 6h26l1.5 1.5V11H36l-1 2.5h-3.5L31 12h-2.4l-2.6 10h-7l2.8-11H20z"/><path d="M29.5 12h4l-.8 2.4a3 3 0 0 1-3.2 2" fill="none" stroke="currentColor" stroke-width="1.2"/>',
  smg: '<path d="M4 9h7v4.5H7.5L4.5 16z"/><path d="M11 7.5h31v6.5H32l-1 2h-3.5l-.6-2H24l-2.4 8H16.5l2.4-8H11z"/><path d="M42 9.5h9v2.5h-9z"/><path d="M27.5 14h4.5l-1.2 8.5h-4z"/>',
  rifle: '<path d="M1 8.5h12.5v4.5H8L2.5 16.5z"/><path d="M13.5 7h28v6.5H33l-1.5 1H25l-2.6 7H17.6l2.6-7.5h-6.7z"/><path d="M41.5 8.2h9v4h-9z"/><path d="M50.5 9.3h11v1.8h-11z"/><path d="M27 4.6h8v2.4h-8z"/><path d="M29 14h5.2l-1.8 8.5-4.8-1.2z"/>',
  shotgun: '<path d="M1 9.5l13-1.5v5l-12.5 4z"/><path d="M14 7.5h11v6h-5l-2.2 6h-4.6l2-6H14z"/><path d="M25 8h37v2.6H25z"/><path d="M36 11h14v3.4H36z"/>',
  sniper: '<path d="M1 8.5h13v4.2L3 16.5z"/><path d="M14 7.5h20v5H25l-2.2 7h-4.6l2.2-7H14z"/><path d="M34 9h29v1.8H34z"/><path d="M18 2.6h17v3.6H18z"/><path d="M21 6.2h2v1.3h-2zm9 0h2v1.3h-2z"/><path d="M48 10.8l-3.5 9.5h1.6l3.4-9.5zm2 0l3.4 9.5h1.6l-3.5-9.5z"/>',
  mg: '<path d="M1 8.5h11v4.5H7L2 16.5z"/><path d="M12 6.5h30v7.5H33l-2.4 1H23l-2.4 7h-5l2.4-8H12z"/><path d="M42 8.5h20v2.6H42z"/><path d="M42 7h8v5.5h-8z"/><path d="M25 14h10v6.5H25z"/><path d="M22 3.6h9v2.9h-9z"/>',
  heavy: '<path d="M3 9h50v5.5H3z"/><path d="M53 7.2l10 4.5-10 4.6z"/><path d="M16 14.5h4l-1.4 7h-4zm14 0h4l-1.4 7h-4z"/><path d="M20 5.6h9V9h-9z"/>',
  throw: '<circle cx="32" cy="14.5" r="7.5"/><path d="M29.5 4h5v3.6h-5z"/><path d="M34.5 5.2h6.5v2h-6.5z"/>',
  tool: '<path d="M22 6h20v15H22z"/><path d="M27 2.5h10V6H27z"/><path d="M42 9h8v2.5h-8z"/>',
  melee: '<path d="M4 10h14v3.6H4z"/><path d="M18 8.6h2.4v6.4H18z"/><path d="M20.4 10.2L56 9.2l5 2.5-5 2.3-35.6-.6z"/>',
};

// ammo: c = rounds in the clip, m = clip size, t = total rounds carried (clip included)
function ammoState(v) {
  const m = Number(v.m) || 0;
  if (m <= 0 || v.c == null) return null;
  const c = Math.max(0, Number(v.c) || 0), t = Math.max(c, Number(v.t) || 0);
  const reserve = t - c;
  const low = c <= Math.max(1, Math.floor(m * 0.25));
  const tag = c === 0 ? (reserve > 0 ? 'RELOAD' : 'EMPTY') : '';
  return { c, m, reserve, low, tag };
}
function ammoHtml(v) {
  const s = ammoState(v);
  if (!s) return '<span class="hm-ammo"></span>';
  return `<span class="hm-ammo${s.low ? ' low' : ''}${s.tag ? ' out' : ''}" style="--ac:${Math.round(s.c / s.m * 100)}">${s.tag
    ? `<b>${s.tag}</b>` : `<b>${s.c}</b><s>/</s>${s.reserve}`}<i></i></span>`;
}

function gunHtml(name, tpl, v) {
  const wc = weaponClass(name);
  if (!wc) return ''; // nothing equipped: no gun slot at all
  const src = tpl && /^[A-Z0-9_]+$/i.test(name) ? tpl.replace('%s', String(name).toUpperCase()).replace('%l', String(name).toLowerCase()) : '';
  return `<div class="hm-gun" data-wc="${wc}"><svg class="wsil" viewBox="0 0 64 24" fill="currentColor">${SIL[wc] || SIL.pistol}</svg>${src
    ? `<img class="wimg" src="${esc(src)}" data-fb="${src.includes('docs.fivem.net') ? '' : `https://docs.fivem.net/weapons/${String(name).toUpperCase()}.png`}" alt="" draggable="false" onload="this.parentNode.classList.add('img')" onerror="if(this.dataset.fb){this.src=this.dataset.fb;this.dataset.fb=''}else this.remove()">` : ''}<i class="hm-flash"></i>${ammoHtml(v || {})}</div>`;
}

// ─── vehicles ──────────────────────────────────────────────
const VEH = {
  car: '<path d="M3 15.5l1.8-5A2 2 0 0 1 6.7 9h10.6a2 2 0 0 1 1.9 1.5l1.8 5V18a1 1 0 0 1-1 1h-1.5a1 1 0 0 1-1-1v-1H6.5v1a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/><path d="M3 13.5h18"/>',
  truck: '<path d="M2 6h11v10H2zM13 9h4.5l3.5 3.5V16h-8z"/><circle cx="6" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>',
  bike: '<circle cx="5.5" cy="16" r="3.5"/><circle cx="18.5" cy="16" r="3.5"/><path d="M5.5 16l4-6h5l4 6M9.5 10l-1-3H6M14.5 10l1.5-3h2.5"/>',
  bicycle: '<circle cx="5.5" cy="16" r="3.5"/><circle cx="18.5" cy="16" r="3.5"/><path d="M5.5 16l3.5-7h6l3.5 7M9 9l3 7H5.5M15 9l-1.5-3H11"/>',
  boat: '<path d="M3 15l2 4h14l2-4zM6 15V9h9l3 6M10 9V5"/>',
  plane: '<path d="M21 12.5c0-.8-.7-1.5-1.5-1.5H15L10 4H8l2.5 7H6L4.5 9H3l1 3.5L3 16h1.5L6 14h4.5L8 21h2l5-7h4.5c.8 0 1.5-.7 1.5-1.5z"/>',
  heli: '<path d="M3 5h16M11 5v3M6 12a4 4 0 0 1 4-4h3a5 5 0 0 1 5 5v1H8a2 2 0 0 1-2-2zM18 12h3M10 17v2M15 17v2M8 19h9"/>',
  train: '<path d="M6 3h12a2 2 0 0 1 2 2v10a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V5a2 2 0 0 1 2-2zM4 10h16M8 18l-2 3M16 18l2 3"/>',
};
const vIcon = (k) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${VEH[k] || VEH.car}</svg>`;
function vehHtml(v) {
  if (!v.vk) return '<div class="hm-veh"></div>';
  return `<div class="hm-veh on" data-vk="${esc(v.vk)}">${vIcon(v.vk)}<b>${esc(v.vn || '')}</b><span>${v.vs === 'd' ? 'Driver' : 'Passenger'}</span></div>`;
}
const vehBadge = (v) => `<span class="hm-vb${v.vk ? ' on' : ''}">${v.vk ? vIcon(v.vk) : ''}</span>`;

// ─── icons ─────────────────────────────────────────────────
const IC = {
  crown: '<svg class="hm-crown" viewBox="0 0 24 24" fill="currentColor"><path d="M3 7l4.5 4L12 4l4.5 7L21 7l-2 12H5z"/></svg>',
  mic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></svg>',
  radio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="8" width="14" height="13" rx="2.5"/><path d="M8 8l9-5M9 13h6M9 17h3"/></svg>',
  shots: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M5 9l2-5 2 5v11H5zm5 0l2-5 2 5v11h-4zm5 0l2-5 2 5v11h-4z"/></svg>',
};

// ─── cards ─────────────────────────────────────────────────
// m: { id, name, avatar (url), owner, rank, kills, deaths, down }
// v: { h, a, w (weapon name), wl (label), talk (false | 'mic' | 'radio'), c/m/t (ammo), vk/vn/vs (vehicle kind, name, seat) }
// m.downAt: ms timestamp when they went down (for the bleed-out timer)
// o: settings plus { self, accent, imgTpl }
function card(m, v, o) {
  v = v || {};
  const h = Math.max(0, Math.min(100, v.h ?? 100)), a = Math.max(0, Math.min(100, v.a ?? 0));
  const down = !!m.down;
  const talk = o.hudTalking !== false && v.talk ? v.talk : false;
  const cls = ['hm', down && 'down', o.self && 'self', h <= 25 && !down && 'low', talk && 'talk', talk === 'radio' && 'radio'].filter(Boolean).join(' ');
  const pic = o.hudAvatars !== false
    ? (m.avatar
      ? `<div class="av" data-i="${esc(initials(m.name))}"><img src="${esc(m.avatar)}" alt="" draggable="false" onerror="this.parentNode.textContent=this.parentNode.dataset.i"></div>`
      : `<div class="av">${esc(initials(m.name))}</div>`)
    : '';
  const armor = o.hudArmorBar !== false
    ? `<div class="ha">${[0, 1, 2, 3].map((i) => `<span style="--i:${i}"><i></i></span>`).join('')}</div>` : '';
  const meta = [];
  if (o.hudRank && m.rank) meta.push(`<span class="hm-rank">${esc(m.rank)}</span>`);
  if (o.hudKda) meta.push(`<span class="hm-kda"><b>${m.kills || 0}</b><s>/</s><b>${m.deaths || 0}</b></span>`);
  const gun = o.hudWeapon !== false ? gunHtml(down ? null : v.w, o.imgTpl, v) : '';
  const wl = o.hudWeapon !== false && !down && weaponClass(v.w) ? esc(v.wl || weaponLabel(v.w)) : '';

  return `<div class="${cls}${v.vk ? ' in-veh' : ''}" data-hm="${o.self ? 'self' : esc(m.id)}" data-w="${esc(v.w || '')}" data-vk="${esc(v.vk || '')}"${down && m.downAt ? ` data-dt="${Number(m.downAt)}"` : ''} style="--h:${h};--a:${a}${down ? ";--accent:#e5484d" : o.accent ? `;--accent:${o.accent}` : ''}">
  <i class="hm-fire"></i><i class="hm-hurt"></i>
  <div class="hm-pic">${pic}<svg class="hm-ring" viewBox="0 0 48 48"><circle class="tr" cx="24" cy="24" r="21" pathLength="100"/><circle class="hr" cx="24" cy="24" r="21" pathLength="100"/><circle class="ar" cx="24" cy="24" r="23.4" pathLength="100"/></svg>
    <span class="hm-eq"><i></i><i></i><i></i></span>${vehBadge(v)}
    <svg class="hm-rv" viewBox="0 0 48 48"><circle cx="24" cy="24" r="21" pathLength="100"/></svg></div>
  <div class="hm-body">
    <div class="hm-top">${m.owner ? IC.crown : ''}<b class="hm-name">${esc(m.name)}</b>${o.self ? '<span class="hm-you">YOU</span>' : ''}${meta.join('')}
      <span class="hm-voice">${talk === 'radio' ? IC.radio : IC.mic}<span class="hm-eq"><i></i><i></i><i></i></span></span>
      <span class="hm-shots">${IC.shots}<em>0</em></span><span class="hm-down"><b>DOWN</b><em class="hm-timer"></em></span><em class="hm-pct">${down ? 0 : h}</em></div>
    <div class="hm-bars"><div class="hb"><i class="g"></i><i class="f"></i></div>${armor}</div>
    <div class="hm-wl">${wl}</div>
    ${vehHtml(v)}
  </div>
  ${gun}
</div>`;
}

// classes on the #hud container for a style and the look settings
function hudClass(o) {
  const s = norm(o.hudStyle);
  return ['hud', 's-' + s, o.hudMinimized && 'min', o.hudAccent === 'none' && 'no-accent',
    o.hudWeapon === false && 'no-gun', o.hudAmmo === false && 'no-ammo', o.hudVehicle === false && 'no-veh'].filter(Boolean).join(' ');
}

function applyVars(el, o) {
  el.style.setProperty('--hud-health', o.hudHealth || '#ffffff');
  el.style.setProperty('--hud-armor', o.hudArmor || '#58a6ff');
  el.style.setProperty('--hud-scale', (o.hudScale || 100) / 100);
  el.style.setProperty('--bg-a', (o.hudOpacity ?? 86) / 100);
}

// live updates without re-rendering the card
function patch(el, v, o) {
  if (!el) return;
  const h = Math.max(0, Math.min(100, v.h ?? 100));
  el.style.setProperty('--h', h);
  el.style.setProperty('--a', Math.max(0, Math.min(100, v.a ?? 0)));
  const pct = el.querySelector('.hm-pct');
  if (pct) pct.textContent = el.classList.contains('down') ? 0 : h;
  el.classList.toggle('low', h <= 25 && !el.classList.contains('down'));
  if (v.w !== undefined && (v.w || '') !== el.dataset.w && o.hudWeapon !== false) {
    el.dataset.w = v.w || '';
    el.querySelector('.hm-gun')?.remove();
    const html = gunHtml(el.classList.contains('down') ? null : v.w, o.imgTpl, v);
    if (html) el.insertAdjacentHTML('beforeend', html);
    const wl = el.querySelector('.hm-wl');
    if (wl) wl.textContent = weaponClass(v.w) ? (v.wl || weaponLabel(v.w)) : '';
  } else if (v.c !== undefined || v.m !== undefined) {
    const am = el.querySelector('.hm-ammo');
    if (am) am.outerHTML = ammoHtml(v);
  }
  if (v.vk !== undefined && (v.vk || '') !== el.dataset.vk) {
    el.dataset.vk = v.vk || '';
    el.classList.toggle('in-veh', !!v.vk);
    el.querySelector('.hm-veh').outerHTML = vehHtml(v);
    el.querySelector('.hm-vb').outerHTML = vehBadge(v);
  } else if (v.vk && v.vs !== undefined) {
    const seat = el.querySelector('.hm-veh span');
    if (seat) seat.textContent = v.vs === 'd' ? 'Driver' : 'Passenger';
  }
}

// ─── hits ──────────────────────────────────────────────────
// A squadmate took damage: the card jolts and flashes red, harder for bigger hits.
function hit(el, dmg) {
  if (!el || !el.isConnected) return;
  const big = Number(dmg) >= 25;
  el.classList.remove('hit', 'hit-big');
  void el.offsetWidth;
  el.classList.add('hit');
  if (big) el.classList.add('hit-big');
  clearTimeout(el._hitT);
  el._hitT = setTimeout(() => el.classList.remove('hit', 'hit-big'), 650);
}

// ─── downed: bleed-out timer and revive progress ───────────
let bleedSecs = 0;
const fmtTime = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
function tickTimers() {
  const now = Date.now();
  document.querySelectorAll('.hud .hm.down[data-dt]').forEach((el) => {
    const gone = Math.max(0, (now - Number(el.dataset.dt)) / 1000);
    const t = el.querySelector('.hm-timer');
    if (!t) return;
    if (bleedSecs > 0) {
      const left = Math.max(0, bleedSecs - gone);
      t.textContent = fmtTime(left);
      el.classList.toggle('urgent', left <= 30);
    } else {
      t.textContent = fmtTime(gone);
    }
  });
}
setInterval(tickTimers, 1000);
function setBleed(s) { bleedSecs = Math.max(0, Number(s) || 0); tickTimers(); }

// someone is reviving this card's player: { by, ms } or false to stop
const active = {}; // [card key] = { by, until, ms } so a re-render keeps the ring going
function restoreRevives(root) {
  const now = performance.now();
  for (const key of Object.keys(active)) {
    const r = active[key], left = r.until - now;
    const el = root.querySelector(`[data-hm="${key}"]`);
    if (left <= 0 || (el && !el.classList.contains('down'))) { delete active[key]; continue; }
    if (!el) continue;
    const done = 1 - left / Math.max(500, r.ms || 5000);
    el.classList.add('reviving');
    const tag = el.querySelector('.hm-down b');
    if (tag) tag.textContent = r.by ? `REVIVING · ${r.by}` : 'REVIVING';
    const ring = el.querySelector('.hm-rv circle');
    if (ring) ring.animate([{ strokeDasharray: `${done * 100} 100` }, { strokeDasharray: '100 100' }], { duration: left, fill: 'forwards' });
    clearTimeout(el._rvT);
    el._rvT = setTimeout(() => reviving(el, false), left + 1500);
  }
}
function reviving(el, data) {
  if (!el) return;
  const ring = el.querySelector('.hm-rv circle');
  clearTimeout(el._rvT);
  if (!data) {
    delete active[el.dataset.hm];
    el.classList.remove('reviving');
    if (ring) ring.getAnimations().forEach((a) => a.cancel());
    const tag = el.querySelector('.hm-down b');
    if (tag) tag.textContent = 'DOWN';
    return;
  }
  el.classList.add('reviving');
  active[el.dataset.hm] = { by: data.by, until: performance.now() + Math.max(500, data.ms || 5000), ms: data.ms };
  const tag = el.querySelector('.hm-down b');
  if (tag) tag.textContent = data.by ? `REVIVING · ${data.by}` : 'REVIVING';
  if (ring) {
    ring.getAnimations().forEach((a) => a.cancel());
    ring.animate([{ strokeDasharray: '0 100' }, { strokeDasharray: '100 100' }], { duration: Math.max(500, data.ms || 5000), fill: 'forwards' });
  }
  el._rvT = setTimeout(() => reviving(el, false), Math.max(500, data.ms || 5000) + 1500);
}

function talk(el, t, o) {
  if (!el) return;
  t = o && o.hudTalking === false ? false : t;
  el.classList.toggle('talk', !!t);
  el.classList.toggle('radio', t === 'radio');
  const icon = el.querySelector('.hm-voice svg');
  if (icon && t) icon.outerHTML = t === 'radio' ? IC.radio : IC.mic;
}

// ─── shots ─────────────────────────────────────────────────
// Flash strength and length per weapon class, so a sniper crack reads heavier than an SMG rattle.
const FIRE = {
  pistol: { d: 130, k: 2.5, s: 1 }, smg: { d: 70, k: 1.5, s: 0.8 }, rifle: { d: 90, k: 2, s: 0.95 },
  mg: { d: 85, k: 2.5, s: 1.05 }, shotgun: { d: 260, k: 4.5, s: 1.4 }, sniper: { d: 380, k: 5, s: 1.6 },
  heavy: { d: 480, k: 5, s: 1.75 }, throw: { d: 300, k: 0, s: 1.2 }, tool: { d: 80, k: 0, s: 0.6 }, melee: { d: 120, k: 0, s: 0.7 },
};
const BUFFER = 120;      // ms of jitter buffer, so batched shots keep the rhythm you hear
const IDLE = 1100;       // firing state clears this long after the last shot
const bursts = {};       // [key] = { b, t0 }
const fireState = new WeakMap();

function flash(el) {
  if (!el || !el.isConnected) return;
  const gun = el.querySelector('.hm-gun');
  const p = FIRE[(gun && gun.dataset.wc) || weaponClass(el.dataset.w) || 'pistol'] || FIRE.pistol;
  let st = fireState.get(el);
  if (!st) { st = { n: 0, t: 0 }; fireState.set(el, st); }
  st.n++;
  clearTimeout(st.t);
  el.classList.add('firing');
  const n = el.querySelector('.hm-shots em');
  if (n) n.textContent = st.n;
  st.t = setTimeout(() => { el.classList.remove('firing'); st.n = 0; }, IDLE);

  const ease = 'cubic-bezier(.2,.8,.3,1)';
  el.querySelector('.hm-fire')?.animate([{ opacity: Math.min(1, 0.55 * p.s) }, { opacity: 0 }], { duration: p.d * 2, easing: ease });
  const fx = el.querySelector('.hm-flash');
  fx?.animate([{ opacity: 1, transform: `translateY(-50%) scale(${0.5 * p.s})` }, { opacity: 0, transform: `translateY(-50%) scale(${1.3 * p.s})` }], { duration: p.d, easing: 'ease-out' });
  if (gun && p.k) gun.animate([{ transform: `translateX(-${p.k}px) rotate(-${p.k * 0.6}deg)` }, { transform: 'none' }], { duration: Math.max(90, p.d), easing: ease });
  el.querySelector('.hm-ring')?.animate([{ filter: 'drop-shadow(0 0 5px var(--fire))' }, { filter: 'none' }], { duration: p.d * 2 });
}

// o: offsets in ms from the first shot of burst b; b < 0 plays straight away (your own shots)
function shots(el, key, b, offsets) {
  if (!el || !Array.isArray(offsets)) return;
  const now = performance.now();
  let t0 = now;
  if (b >= 0) {
    const cur = bursts[key];
    if (!cur || cur.b !== b) bursts[key] = { b, t0: now + BUFFER };
    t0 = bursts[key].t0;
  }
  for (const off of offsets) {
    const wait = Math.max(0, t0 + Number(off || 0) - now);
    if (wait < 8) flash(el); else setTimeout(() => flash(el), wait);
  }
}

// ─── settings previews ─────────────────────────────────────
const DEMO = [
  { m: { id: 'pv0', name: 'NayZeee', owner: true, rank: 'Leader', kills: 31, deaths: 14 }, v: { h: 92, a: 75, w: 'WEAPON_CARBINERIFLE', wl: 'Carbine Rifle', c: 24, m: 30, t: 144 }, self: true },
  { m: { id: 'pv1', name: 'Tay Brooks', rank: 'Officer', kills: 27, deaths: 18 }, v: { h: 58, a: 25, w: 'WEAPON_PISTOL50', wl: 'Pistol .50', talk: 'radio', c: 2, m: 9, t: 20 } },
  { m: { id: 'pv2', name: 'Keisha Moore', rank: 'Member', kills: 14, deaths: 9 }, v: { h: 21, a: 0, vk: 'car', vn: 'Sultan RS', vs: 'd' } },
  { m: { id: 'pv3', name: 'Marcus Hill', rank: 'Member', kills: 19, deaths: 16, down: true, downFor: 42 }, v: { h: 0, a: 0 } },
];
// a short firefight that loops in the previews: rifle bursts, pistol taps and a shotgun blast
const DEMO_FIRE = [
  ['self', 0, [0, 92, 184, 276, 368]], ['pv1', 650, [0, 260, 520]], ['self', 1900, [0, 92, 184]],
];

function preview(style, o) {
  const wrap = document.createElement('div');
  const opts = { ...o, hudStyle: style };
  wrap.className = hudClass(opts) + ' tpv';
  applyVars(wrap, opts);
  const now = Date.now();
  wrap.innerHTML = DEMO.map((p) => card(p.m.downFor ? { ...p.m, downAt: now - p.m.downFor * 1000 } : p.m, p.v, { ...opts, self: !!p.self, accent: accentFor(opts, p.v.h, p.m.down), imgTpl: o.imgTpl })).join('');
  return wrap;
}

function accentFor(o, h, down) {
  if (down) return '#e5484d';
  if (o.hudAccent === 'health') return h <= 25 ? '#e5484d' : h <= 60 ? '#e5a50a' : '#08afa2';
  return o.squadColor || '#08afa2';
}

let demoTimer = 0;
function demo(root) {
  clearInterval(demoTimer);
  const run = () => {
    if (!root.isConnected || !root.querySelector('.hud.tpv')) { clearInterval(demoTimer); return; }
    root.querySelectorAll('.hud.tpv').forEach((hud) => {
      for (const [key, at, offs] of DEMO_FIRE) {
        const el = hud.querySelector(`[data-hm="${key}"]`);
        if (el && !el.classList.contains('down')) setTimeout(() => shots(el, '', -1, offs), at);
      }
      const hurt = hud.querySelector('[data-hm="pv2"]');
      if (hurt) setTimeout(() => hit(hurt, 30), 2500);
      const down = hud.querySelector('[data-hm="pv3"]');
      if (down && !down.classList.contains('reviving')) setTimeout(() => reviving(down, { by: 'Tay', ms: 2600 }), 400);
    });
  };
  run();
  demoTimer = setInterval(run, 3200);
}

window.TeamHud = { STYLES, norm, card, hudClass, applyVars, patch, talk, shots, flash, hit, reviving, restoreRevives, setBleed, tickTimers,
  weaponClass, weaponLabel, preview, demo, accentFor };
})();
