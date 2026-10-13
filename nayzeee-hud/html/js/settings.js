(() => {
  const NH = window.NH;
  const ic = NH.ic;

  const TABS = [
    { id: 'general', label: 'General', icon: 'sliders', title: 'General', sub: 'Units, scale, colours and sound' },
    { id: 'seasons', label: 'Seasons', icon: 'sparkles', title: 'Seasonal Styles', sub: 'Holiday themes, particles and decorations' },
    { id: 'status', label: 'Player Status', icon: 'heart', title: 'Player Status', sub: 'Health, armor, hunger, thirst, stamina, stress, oxygen & voice' },
    { id: 'voice', label: 'Voice & Radio', icon: 'mic', title: 'Voice & Radio', sub: 'Voice range, talking and your radio channel' },
    { id: 'vehicle', label: 'Cars & Bikes', icon: 'car', title: 'Cars & Bikes', sub: 'Speedometer style and dashboard' },
    { id: 'other', label: 'Air, Sea & Cycles', icon: 'plane', title: 'Air, Sea & Bicycles', sub: 'Flight display, boat units and bicycle computer' },
    { id: 'map', label: 'Map & Compass', icon: 'map', title: 'Map & Compass', sub: 'Minimap, street bar, speed limits and compass' },
    { id: 'info', label: 'Player Info', icon: 'user', title: 'Player Info', sub: 'Job, money, server ID and headshot' },
    { id: 'weapon', label: 'Weapon', icon: 'bullets', title: 'Weapon', sub: 'Weapon name and ammo' },
    { id: 'crosshair', label: 'Crosshair', icon: 'crosshair', title: 'Crosshair', sub: 'Shape, colour and size of your aim' },
    { id: 'notify', label: 'Notifications', icon: 'bell', title: 'Notifications & Prompts', sub: 'Notifications, progress bars and interaction prompts' },
    { id: 'clock', label: 'Weather & Time', icon: 'cloudsun', title: 'Weather & Time', sub: 'Clock, day and weather icon' },
    { id: 'watermark', label: 'Watermark', icon: 'image', title: 'Watermark', sub: 'Server logo and effect' },
    { id: 'io', label: 'Import & Export', icon: 'swap', title: 'Import & Export', sub: 'Share your HUD setup with a code' },
    { id: 'squads', label: 'Squads', icon: 'users', title: 'Squads', sub: 'Team HUD, nametags, map blips and alerts' },
    { id: 'keys', label: 'Keybinds', icon: 'keyboard', title: 'Keybinds', sub: 'Change keys in GTA Settings > Key Bindings > FiveM' },
  ];

  const ACCENTS = ['#08afa2', '#b8f02a', '#22d3ee', '#60a5fa', '#a78bfa', '#f472b6', '#fb7185', '#f97316', '#facc15', '#34d399', '#f5f5f5'];

  const g = (p) => NH.getPath(NH.cur, p);

  // ---- control builders ----
  const sec = (title, body, desc = '') => `<section class="sec"><h4>${title}</h4>${desc ? `<p class="desc">${desc}</p>` : ''}${body}</section>`;
  const toggle = (path, label, desc = '') =>
    `<div class="opt"><div class="opt-t"><b>${label}</b>${desc ? `<small>${desc}</small>` : ''}</div><button class="tg${g(path) ? ' on' : ''}" data-tog="${path}"><i></i></button></div>`;
  const seg = (path, opts, label = '', desc = '') =>
    `<div class="opt">${label ? `<div class="opt-t"><b>${label}</b>${desc ? `<small>${desc}</small>` : ''}</div>` : ''}<div class="segc" data-seg="${path}">${opts.map(([v, l]) => `<button data-val="${v}" class="${String(g(path)) === v ? 'on' : ''}">${l}</button>`).join('')}</div></div>`;
  const range = (path, label, min, max, step, fmt, desc = '') => {
    const v = g(path) ?? 1;
    return `<div class="opt col"><div class="opt-t"><b>${label}</b>${desc ? `<small>${desc}</small>` : ''}</div><div class="rng"><input type="range" min="${min}" max="${max}" step="${step}" value="${v}" data-rng="${path}" data-fmt="${fmt}"/><span>${fmtVal(v, fmt)}</span></div></div>`;
  };
  const fmtVal = (v, fmt) => fmt === 'pct' ? Math.round(v * 100) + '%' : fmt === 'raw%' ? v + '%' : fmt === 'px' ? v + 'px' : String(v);
  const cards = (path, items, cls = '', sel = g(path)) =>
    `<div class="cards ${cls}" data-cards="${path}">${items.map(it => `<button class="card${String(sel) === it.v ? ' on' : ''}" data-val="${it.v}"><div class="pv"${it.pv ? ` data-pv="${it.pv}"` : ''}>${it.html || ''}</div><span>${it.l}</span>${it.sub ? `<small>${it.sub}</small>` : ''}</button>`).join('')}</div>`;
  const chips = (items) => `<div class="chips">${items.map(([path, label, icon]) => `<button class="chip${g(path) ? ' on' : ''}" data-tog="${path}">${icon || ''}${label}</button>`).join('')}</div>`;
  const scaleRange = (id, label = 'Scale') => {
    const v = NH.cur.layout[id]?.s || 1;
    return `<div class="opt col"><div class="opt-t"><b>${label}</b><small>On top of the global HUD scale</small></div><div class="rng"><input type="range" min="0.5" max="2" step="0.05" value="${v}" data-scale="${id}"/><span>${Math.round(v * 100)}%</span></div></div>`;
  };

  // ---- static previews ----
  const PV = {
    sign: (s) => `<div class="sgn ${s}"><small>SPEED<br>LIMIT</small><b>30</b></div>`,
    compass: (s) => s === 'tape'
      ? `<div class="pv-cmp"><i></i><i></i><b>NW</b><i></i><small>330</small><i></i><b class="main">N</b><i></i><small>30</small><i></i><b>NE</b><i></i></div>`
      : `<div class="cmp-rib panel"><b class="cmp-l">NW</b><i></i><span class="cmp-d">312°</span></div>`,
    weapon: (s) => `<div class="wpn w-${s} ${s === 'card' ? 'panel' : ''} pv-wpn"><span class="pv-gun">${ic('crosshair')}</span><b class="wn">Heavy Pistol</b><div class="am">${ic('bullets')}<b class="clip">30</b><i></i><span class="res">36</span></div></div>`,
    watermark: (style, effect) => {
      const w = NH.cfg.watermark, e = NH.esc, show = NH.cur.watermark.show || 'both';
      const logo = show === 'text' ? null : NH.logoSrc;
      const text = logo && show === 'logo' ? '' : `<div class="wm-t"><b data-text="${e(w.title)}">${e(w.title)}</b>${w.subtitle ? `<small>${e(w.subtitle)}</small>` : ''}</div>`;
      return `<div class="wm wm-${style} fx-${effect}">${logo ? `<img src="${e(logo)}" alt=""/>` : ''}${text}</div>`;
    },
  };

  // ---- tabs ----
  const R = {};
  R.general = () =>
    sec('Units', seg('units', [['mph', 'MPH'], ['kmh', 'KM/H']], 'Speed units', 'Also used for speed limit signs')) +
    sec('Size & look',
      range('scale', 'Global HUD scale', 0.6, 1.6, 0.05, 'pct') +
      range('panelAlpha', 'Panel opacity', 0.3, 1, 0.02, 'pct') +
      `<div class="opt col"><div class="opt-t"><b>Accent colour</b><small>Seasonal styles can override this (see Seasons)</small></div>
        <div class="swatches">${ACCENTS.map(c => `<button class="swatch${NH.cur.accent === c ? ' on' : ''}" data-accent="${c}" style="--sw:${c}"></button>`).join('')}
        <input class="hex" data-hex="accent" value="${NH.cur.accent}" maxlength="7" spellcheck="false"/></div></div>`) +
    sec('Sound', toggle('sound', 'HUD sounds', 'Seatbelt click, chime and indicator tick') + range('volume', 'Volume', 0, 1, 0.05, 'pct')) +
    sec('Layout', `<div class="opt"><div class="opt-t"><b>Edit sizes & positions</b><small>Drag any element, scroll to resize, right-click to reset it</small></div><button class="btn-line" data-act="edit">${ic('move')}Edit layout</button></div>` +
      toggle('cinematic', 'Cinematic mode', 'Black bars and no HUD, for screenshots and clips'));

  R.seasons = () =>
    sec('Season', cards('season', [{ v: 'auto', l: 'Automatic', sub: 'Changes with the date', html: `<div class="sw-row">${NH.seasonSwatch(NH.seasonForDate())}</div><small class="sw-now">Now: ${NH.SEASONS[NH.seasonForDate()].label}</small>` },
      ...Object.keys(NH.SEASONS).map(k => ({ v: k, l: NH.SEASONS[k].label, sub: NH.SEASONS[k].dates || 'Your accent colour', html: `<div class="sw-row">${NH.seasonSwatch(k)}</div>` }))], 'c4 season-cards')) +
    sec('Effects',
      toggle('particles', 'Seasonal particles', 'Snow, leaves, hearts, confetti, bats... very light, CSS only') +
      toggle('decor', 'Decorations', 'Little seasonal ornaments on HUD elements') +
      toggle('seasonAccent', 'Use season colours', 'Turn off to keep your own accent colour with seasonal effects'));

  const STAT_COLORS = ['#ff4d5e', '#4d8dff', '#ffad33', '#33c4ff', '#4ade80', '#c084fc', '#5eead4', '#08afa2', '#facc15', '#f472b6', '#f2f4f0'];
  R.status = () =>
    sec('Display', toggle('status.enabled', 'Show player status') + toggle('status.autoHide', 'Smart hide', 'Hide armor & stress at 0 and stamina when full') +
      seg('status.color', [['vibrant', 'Vibrant'], ['accent', 'Accent'], ['mono', 'Mono'], ['custom', 'Custom']], 'Colours', 'Custom lets you pick a colour for every stat below') +
      seg('status.place', [['under', 'Under the minimap'], ['side', 'Beside the minimap']], 'Position', 'Under lifts the minimap a little so the row fits below it') +
      seg('status.dir', [['row', 'Row'], ['col', 'Column']], 'Direction') + scaleRange('status')) +
    sec('Style', cards('status.style', Object.keys(NH.STATUS_STYLES).map(k => ({ v: k, l: NH.STATUS_STYLES[k].label, pv: 'status:' + k })), 'c4')) +
    (NH.cur.status.color === 'custom' ? sec('Stat colours', NH.STATS.map(s => {
      const path = `status.colors.${s.k}`, cur = g(path) || s.c;
      return `<div class="opt"><div class="opt-t"><b>${NH.fic(s.icon)} ${s.label}</b></div><div class="swatches">${STAT_COLORS.concat(STAT_COLORS.includes(s.c) ? [] : [s.c]).map(h =>
        `<button class="swatch${String(cur).toLowerCase() === h ? ' on' : ''}" style="--sw:${h}" data-setval="${path}" data-val="${h}"></button>`).join('')}<input class="hex" data-hex="${path}" value="${cur}" maxlength="7"/></div></div>`;
    }).join(''), 'Pick a colour or type a hex code. Every style uses these.') : '') +
    sec('Shown stats', chips(NH.STATS.map(s => [`status.show.${s.k}`, s.label, NH.fic(s.icon)])));

  R.vehicle = () =>
    sec('Speedometer', cards('speedo.style', Object.keys(NH.SPEEDO_STYLES).filter(k => !NH.CYCLE_ONLY.includes(k)).map(k => ({ v: k, l: NH.SPEEDO_STYLES[k].label, pv: 'speedo:' + k })), 'c3 tall') + scaleRange('speedo')) +
    sec('Dashboard', toggle('speedo.lights', 'Dashboard lights', 'Seatbelt, lights, cruise, lock, engine and indicators') +
      toggle('speedo.chime', 'Seatbelt chime', 'Chimes when driving unbuckled') +
      toggle('speedo.tick', 'Indicator tick sound') +
      toggle('speedo.fuelWarn', 'Low fuel warning', 'Fuel bar blinks under 15%') + scaleRange('dash', 'Dashboard lights scale'));

  R.other = () =>
    sec('Aircraft', cards('air.style', [{ v: 'pfd', l: 'Flight PFD', pv: 'air:pfd' }, { v: 'cards', l: 'Info Cards', pv: 'air:cards' }, { v: 'modern', l: 'Modern', pv: 'air:modern' }, { v: 'off', l: 'Off', html: `<span class="pv-off">${ic('x')}</span>` }], 'c4 tall') + scaleRange('air')) +
    sec('Boats', seg('boat.units', [['kts', 'Knots'], ['main', 'Same as cars']], 'Boat speed units') +
      cards('boat.style', [{ v: 'classic', l: 'Heading & trim', pv: 'boat:classic' }, { v: 'modern', l: 'Modern', pv: 'boat:modern' }], 'c2') +
      toggle('boat.info', 'Show with Heading & trim', 'Heading and how far the bow is up or down, above the speedometer') + scaleRange('boat')) +
    sec('Bicycles', cards('cycle.style', [{ v: 'smartwatch', l: 'Smart Watch', pv: 'speedo:smartwatch' }, { v: 'watch', l: 'Fitness Watch', pv: 'speedo:watch' }, { v: 'car', l: 'Car speedometer', html: `<span class="pv-off">${ic('car')}</span>` }], 'c3 tall'));

  const MAP_FRAMES = [['glass', 'Glass'], ['inset', 'Inset'], ['accent', 'Accent'], ['panel', 'Panel'], ['corners', 'Corners'], ['shadow', 'Shadow'], ['none', 'None']];
  R.map = () =>
    sec('Minimap', seg('map.mode', [['vehicle', 'In vehicles'], ['always', 'Always'], ['never', 'Never']], 'Show minimap') +
      toggle('map.frame', 'Minimap frame', 'Drawn around the radar; follows the shape you pick below') +
      cards('map.frameStyle', MAP_FRAMES.map(([v, l]) => ({ v, l, html: `<div class="pv-map"><div class="pv-radar"></div>${v === 'none' ? '' : '<b class="mf-bz"></b>'}<div class="mf" data-style="${v}"><i></i><i></i><i></i><i></i></div></div>` })), 'c3') +
      seg('map.shape', [['default', 'Default'], ['square', 'Square'], ['circle', 'Circle']], 'Shape', 'The shape of the minimap itself')) +
    sec('Frame fit', range('map.fit.x', 'Left / right', -40, 40, 1, 'px') + range('map.fit.y', 'Up / down', -40, 40, 1, 'px') +
      range('map.fit.w', 'Width', -40, 40, 1, 'px') + range('map.fit.h', 'Height', -40, 40, 1, 'px') +
      `<div class="opt"><div class="opt-t"><b>Reset fit</b></div><button class="btn-line" data-act="fit-reset">${ic('reset')}Reset</button></div>`,
      'Nudge the frame until it sits exactly on your radar (open Edit layout or get in a car to see it). The street bar and speed sign follow.') +
    sec('Street bar', toggle('map.street', 'Street bar', 'Direction, road, zone and postal') + toggle('map.streetOnFoot', 'Show on foot') +
      toggle('map.streetInside', 'Inside the minimap', 'A small street label in the bottom-left of the map instead of a bar above it') + scaleRange('street')) +
    sec('Speed limit', toggle('map.sign', 'Speed limit sign') + toggle('map.blink', 'Blink when speeding') +
      cards('map.signStyle', [{ v: 'us', l: 'US', html: PV.sign('us') }, { v: 'eu', l: 'European', html: PV.sign('eu') }], 'c2') + scaleRange('sign')) +
    sec('Compass', toggle('map.compass', 'Compass') + seg('map.compassWhen', [['always', 'Always'], ['vehicle', 'In vehicles']], 'Show') +
      cards('map.compassStyle', [{ v: 'tape', l: 'Tape', html: PV.compass('tape') }, { v: 'ribbon', l: 'Ribbon', html: PV.compass('ribbon') }], 'c2') + scaleRange('compass'));

  R.info = () =>
    sec('Display', toggle('info.enabled', 'Show player info') + scaleRange('info')) +
    sec('Style', cards('info.style', Object.keys(NH.INFO_STYLES).map(k => ({ v: k, l: NH.INFO_STYLES[k].label, pv: 'info:' + k })), 'c4 tall')) +
    sec('Picture', seg('info.avatar', [['discord', 'Discord'], ['headshot', 'Character'], ['none', 'None']], 'Profile picture', 'Discord uses your server avatar when you have one, and falls back to your character') +
      toggle('info.animated', 'Animated Discord pictures', 'Plays animated (GIF) avatars')) +
    sec('Money', toggle('info.popups', 'Money change popups', 'Shows +$ / -$ under your info when cash or bank changes')) +
    sec('Elements', chips([['info.job', 'Job', ic('briefcase')], ['info.gang', 'Gang', ic('users')], ['info.name', 'Name', ic('user')], ['info.cash', 'Cash', ic('cash')],
      ['info.dirty', 'Dirty money', ic('cash')], ['info.bank', 'Bank', ic('bank')], ['info.id', 'Server ID', ic('idcard')], ['info.players', 'Players online', ic('users')],
      ['info.time', 'Date & time', ic('clock')], ['info.headshot', 'Picture & voice', ic('image2')]]));

  R.weapon = () =>
    sec('Display', toggle('weapon.enabled', 'Show weapon') + toggle('weapon.image', 'Weapon image') + scaleRange('weapon')) +
    sec('Style', cards('weapon.style', [{ v: 'card', l: 'Card', html: PV.weapon('card') }, { v: 'minimal', l: 'Minimal', html: PV.weapon('minimal') }, { v: 'pill', l: 'Pill', html: PV.weapon('pill') }], 'c3 tall'));

  R.voice = () =>
    sec('Display', toggle('voice.enabled', 'Show voice & radio', 'Your voice range, when you’re talking, and your radio channel') +
      seg('voice.when', [['always', 'Always'], ['talking', 'While talking'], ['radio', 'On a radio']], 'Show', 'When the widget is on screen') +
      toggle('voice.label', 'Range name', 'Whisper, Normal, Shouting (or your voice script’s own names)') + scaleRange('voice')) +
    sec('Style', cards('voice.style', NH.VOICE_STYLES.map(([v, l]) => ({ v, l, pv: 'voice:' + v })), 'c4'),
      'Works with pma-voice and SaltyChat. Moves in Edit layout like everything else.');

  R.crosshair = () => {
    if (NH.cfg.crosshair === false) return sec('Crosshair', '<p class="desc">The custom crosshair is turned off on this server.</p>');
    const c = NH.cur.crosshair;
    return sec('Display', toggle('crosshair.enabled', 'Custom crosshair', 'Replaces GTA’s aim dot while you aim a gun (sniper scopes keep their own)') +
        toggle('crosshair.always', 'Show while holding a gun', 'Not just while aiming') + toggle('crosshair.outline', 'Dark outline', 'Easier to see on bright backgrounds')) +
      sec('Style', cards('crosshair.style', NH.CROSS_STYLES.map(([v, l]) => ({ v, l, pv: 'cross:' + v })), 'c4')) +
      sec('Colour', `<div class="swatches">${NH.CROSS_COLORS.map(col => `<button class="swatch${c.color === col ? ' on' : ''}" style="--sw:${col === 'accent' ? 'var(--accent)' : col}" data-setval="crosshair.color" data-val="${col}" title="${col === 'accent' ? 'HUD accent' : col}"></button>`).join('')}</div>`) +
      sec('Size', range('crosshair.size', 'Length', 2, 20, 1, 'px') + range('crosshair.thick', 'Thickness', 1, 5, 1, 'px') +
        range('crosshair.gap', 'Gap', 0, 12, 1, 'px') + range('crosshair.opacity', 'Opacity', 20, 100, 5, 'raw%'));
  };

  R.notify = () =>
    sec('Notifications', cards('ui.notify', NH.NOTIFY_STYLES.map(([v, l]) => ({ v, l, pv: 'notify:' + v })), 'c3 tall') +
      seg('ui.notifyPos', [['right', 'Right'], ['left', 'Left'], ['top', 'Top'], ['bottom', 'Bottom']], 'Position') +
      toggle('ui.notifySound', 'Sound', 'A soft chime when one arrives') +
      `<div class="opt"><div class="opt-t"><b>Try it</b><small>Shows one of each kind</small></div><button class="btn-line" data-act="test-notify">${ic('bell')}Test</button></div>`) +
    sec('Progress bar', cards('ui.progress', NH.PROGRESS_STYLES.map(([v, l]) => ({ v, l, pv: 'progress:' + v })), 'c4') +
      `<div class="opt"><div class="opt-t"><b>Try it</b></div><button class="btn-line" data-act="test-progress">${ic('clock')}Test</button></div>`) +
    sec('Interaction prompt', cards('ui.text', NH.TEXT_STYLES.map(([v, l]) => ({ v, l, pv: 'text:' + v })), 'c3') +
      seg('ui.textPos', [['left', 'Left'], ['right', 'Right'], ['top', 'Top'], ['bottom', 'Bottom']], 'Position', 'Scripts can still pick their own'));

  R.clock = () =>
    sec('Display', toggle('clock.enabled', 'Show clock') + toggle('clock.day', 'Show day') + toggle('clock.h24', '24 hour clock') + toggle('clock.weather', 'Weather icon') +
      seg('clock.source', [['game', 'Game time'], ['real', 'Real time']], 'Time source') + scaleRange('clock')) +
    sec('Style', cards('clock.style', Object.keys(NH.CLOCK_STYLES).map(k => ({ v: k, l: NH.CLOCK_STYLES[k].label, pv: 'clock:' + k })), 'c3'));

  R.watermark = () =>
    sec('Display', toggle('watermark.enabled', 'Show watermark', 'Text is set in config.lua; the logo is the image in nayzeee-hud/html/logo/') +
      seg('watermark.show', [['both', 'Logo & text'], ['logo', 'Logo only'], ['text', 'Text only']], 'Show', NH.logoSrc ? '' : 'No logo found yet: drop logo.png into html/logo/') +
      scaleRange('watermark')) +
    sec('Logo', cards('watermark.style', ['stack', 'badge', 'minimal'].map(s => ({ v: s, l: s[0].toUpperCase() + s.slice(1), html: PV.watermark(s, 'none') })), 'c3')) +
    sec('Effect', cards('watermark.effect', ['none', 'pulse', 'gloss', 'float'].map(e => ({ v: e, l: e[0].toUpperCase() + e.slice(1), html: PV.watermark(NH.cur.watermark.style, e) })), 'c4'));

  // what a HUD code contains, as little chips
  const label = (map, k) => (map && map[k] && map[k].label) || (k ? String(k)[0].toUpperCase() + String(k).slice(1) : '-');
  const ioSummary = (c) => {
    const moved = Object.keys(c.layout || {}).length;
    const items = [
      ['heart', 'Status', label(NH.STATUS_STYLES, c.status && c.status.style)],
      ['gauge', 'Speedometer', label(NH.SPEEDO_STYLES, c.speedo && c.speedo.style)],
      ['user', 'Player info', label(NH.INFO_STYLES, c.info && c.info.style)],
      ['cloudsun', 'Clock', label(NH.CLOCK_STYLES, c.clock && c.clock.style)],
      ['sparkles', 'Season', label(null, c.season)],
      ['move', 'Layout', moved ? `${moved} moved` : 'Default'],
    ];
    const acc = /^#[\da-f]{6}$/i.test(c.accent || '') ? c.accent : '#08afa2';
    return `<div class="io-sum">${items.map(([i, k, v]) => `<span class="io-chip">${ic(i)}<small>${k}</small><b>${NH.esc(v)}</b></span>`).join('')}
      <span class="io-chip">${ic('palette')}<small>Accent</small><i class="io-dot" style="background:${acc}"></i><b>${acc.toUpperCase()}</b></span></div>`;
  };
  NH.ioDecode = (raw) => {
    try {
      const data = JSON.parse(decodeURIComponent(escape(atob(String(raw).trim()))));
      return data && typeof data === 'object' && data.status ? data : null;
    } catch (_) { return null; }
  };

  R.io = () => {
    const code = btoa(unescape(encodeURIComponent(JSON.stringify(NH.cur))));
    return `<div class="io">
      <div class="io-card">
        <div class="io-hd"><span class="io-i">${ic('upload')}</span><div><b>Share your HUD</b><small>Everything you've set up, as one code: styles, colours, layout and squads look</small></div></div>
        ${ioSummary(NH.cur)}
        <div class="io-code"><code id="nh-export">${code}</code><span class="io-len">${code.length.toLocaleString('en-US')} characters</span></div>
        <div class="btns"><button class="btn-teal" data-act="copy">${ic('copy')}<span>Copy code</span></button><small class="io-hint">Send it to a friend; they paste it below.</small></div>
      </div>
      <div class="io-card">
        <div class="io-hd"><span class="io-i in">${ic('download')}</span><div><b>Use a HUD code</b><small>Paste a code to load someone's setup. Nothing changes until you press Save.</small></div></div>
        <div class="io-drop" id="nh-drop"><textarea class="code" id="nh-import" spellcheck="false" placeholder="Paste a HUD code here"></textarea></div>
        <div class="io-check" id="nh-io-check"></div>
        <div class="btns"><button class="btn-teal" data-act="import" id="nh-import-btn" disabled>${ic('download')}Load code</button><button class="btn-line" data-act="io-clear">${ic('x')}Clear</button></div>
      </div></div>`;
  };
  NH.ioCheck = (root) => {
    const ta = root.querySelector('#nh-import'), out = root.querySelector('#nh-io-check'), btn = root.querySelector('#nh-import-btn'), drop = root.querySelector('#nh-drop');
    if (!ta) return;
    const raw = ta.value.trim();
    const data = raw ? NH.ioDecode(raw) : null;
    drop.classList.toggle('ok', !!data);
    drop.classList.toggle('bad', !!raw && !data);
    btn.disabled = !data;
    out.innerHTML = !raw ? '' : data
      ? `<p class="io-ok">${ic('check')}Valid code. This is what it sets:</p>${ioSummary(data)}`
      : `<p class="io-bad">${ic('x')}That isn't a HUD code. Copy the whole code and try again.</p>`;
  };

  // ---- squads player settings (stored by the squads module, edited here) ----
  const TEAM_STYLES = window.TeamHud ? TeamHud.STYLES : [];
  const TEAM_COLORS = ['#ffffff', '#08afa2', '#58a6ff', '#e5484d', '#e5a50a', '#a078ff', '#8bd35a', '#ff7ad9'];
  const sqSw = (key, list) => `<div class="swatches">${list.map(([hex, id]) => {
    const val = id === undefined ? hex : id;
    return `<button class="swatch${String(g('squads.' + key)) === String(val) ? ' on' : ''}" style="--sw:${hex}" data-setval="squads.${key}" data-val="${val}"${id === undefined ? '' : ' data-num="1"'}></button>`;
  }).join('')}</div>`;
  const sqSeg = (key, opts, label, desc, num) =>
    `<div class="opt"><div class="opt-t"><b>${label}</b>${desc ? `<small>${desc}</small>` : ''}</div><div class="segc" data-seg="squads.${key}">${opts.map(([v, l]) =>
      `<button data-val="${v}"${num ? ' data-num="1"' : ''} class="${String(g('squads.' + key)) === String(v) ? 'on' : ''}">${l}</button>`).join('')}</div></div>`;
  const sqRange = (key, label, min, max, step) => {
    const v = g('squads.' + key) ?? min;
    return `<div class="opt col"><div class="opt-t"><b>${label}</b></div><div class="rng"><input type="range" min="${min}" max="${max}" step="${step}" value="${v}" data-rng="squads.${key}" data-fmt="raw%"/><span>${v}%</span></div></div>`;
  };
  const T = (key, label, desc) => toggle('squads.' + key, label, desc);

  // team HUD preview cards: the same renderer and CSS as the live ones in the squads frame
  NH.teamPreview = (style, st = NH.cur.squads || {}) => TeamHud.preview(style, { ...st, imgTpl: NH.cfg.weaponImages });

  R.squads = () => {
    const d = NH.cfg.squadsData;
    if (!d) return sec('Squads', '<p class="desc">The squads module is turned off on this server.</p>');
    const f = d.features || {}, nt = d.nametag || {}, st = NH.cur.squads || {};
    const maxOpts = [[0, 'All'], ...[3, 4, 6, 8].filter(n => n < (d.maxMembers || 8)).map(n => [n, String(n)])];
    let html = '';
    if (f.Hud !== false) {
      html += sec('Team HUD', T('hud', 'Show team HUD', 'Your squad\u2019s health and armour on screen') +
        `<div class="opt"><div class="opt-t"><b>Position</b><small>Moves with the rest of the HUD in Edit layout</small></div><button class="btn-line" data-act="edit">${ic('move')}Edit layout</button></div>`);
      html += sec('Style', cards('squads.hudStyle', TEAM_STYLES.map(([v, l]) => ({ v, l, pv: 'team:' + v })), 'c3 tall', TeamHud.norm(st.hudStyle)));
      html += sec('Look',
        sqSeg('hudAccent', [['squad', 'Squad'], ['teal', 'Teal'], ['health', 'Health'], ['none', 'None']], 'Edge colour', 'Colour on each card\u2019s edge') +
        sqRange('hudScale', 'Size', 70, 130, 5) + sqRange('hudOpacity', 'Background', 0, 100, 5) +
        sqSeg('hudMax', maxOpts, 'Cards shown', '', true) +
        `<div class="opt col"><div class="opt-t"><b>Health bar colour</b></div>${sqSw('hudHealth', TEAM_COLORS.map(h => [h]))}</div>` +
        `<div class="opt col"><div class="opt-t"><b>Armour bar colour</b></div>${sqSw('hudArmor', TEAM_COLORS.map(h => [h]))}</div>`);
      html += sec('Cards', T('hudShowSelf', 'Show your own card', 'Your health and armour at the top') + T('hudAvatars', 'Profile pictures') +
        T('animatedAvatars', 'Animated pictures', 'Play animated Discord avatars') + T('hudArmorBar', 'Armour bar') + T('hudRank', 'Rank name') +
        T('hudKda', 'Kills and deaths') + T('hudWeapon', 'Weapon in hand', 'A picture of the gun each squadmate is holding') +
        T('hudShots', 'Shot flashes', 'Cards flash in time with every shot a squadmate fires, so you can tell who is shooting') +
        T('hudAmmo', 'Ammo', 'Clip and reserve under the gun, with RELOAD and EMPTY warnings') +
        T('hudHits', 'Damage flashes', 'Cards jolt red when that squadmate gets hurt') +
        T('hudVehicle', 'Vehicle', 'What they\u2019re driving or riding in, and which seat') +
        T('hudTalking', 'Voice indicator', 'Shows who is talking, and whether it\u2019s over the radio') + T('hudMinimized', 'Compact cards', 'Smaller cards with less detail'));
    }
    if (f.Tags !== false) {
      html += sec('Nametags', T('tags', 'Show nametags', 'Over your squadmates\u2019 heads') +
        (nt.Name !== false ? T('tagName', 'Player name') : '') + (nt.Tag !== false ? T('tagSquadTag', 'Squad tag') : '') +
        (nt.Role !== false ? T('tagRole', 'Rank name') : '') + (nt.Health !== false ? T('tagHealth', 'Health and armour bar') : '') +
        (f.Affiliations && nt.Allies !== false ? T('tagAllies', 'Allied squads', 'Show tags over allied players too') : '') +
        `<div class="opt col"><div class="opt-t"><b>Tag colour</b></div>${sqSw('tagColor', d.tagColors || [])}</div>`);
    }
    if (f.Blips !== false) {
      html += sec('Map blips', T('blips', 'Show blips', 'Squadmates on your map and radar') +
        (f.SquadBlips ? T('blipUseSquad', 'Use squad colours', 'Each squad shows in the colour it picked') : '') +
        (f.Affiliations ? T('blipAllies', 'Allied squads', 'Show allied players on your map') : '') +
        `<div class="opt col"><div class="opt-t"><b>Blip colour</b><small>Used when squad colours are off</small></div>${sqSw('blipColor', d.blipColors || [])}</div>`);
    }
    html += sec('Alerts', T('chatNotify', 'Chat pop-ups', 'A notification for new squad messages') + T('chatSound', 'Chat sound') +
      (f.Pings !== false ? T('pingNotify', 'Ping pop-ups') + T('pingSound', 'Ping sound') : '') +
      (f.Revive !== false ? T('reviveAlerts', 'Downed alerts', 'Alert and map ping when a squadmate goes down') : '') +
      (f.Combat !== false ? T('killfeed', 'Killfeed', 'Kills against other squads') + T('matchBanner', 'Fight results', 'Banner when a fight is scored') : ''));
    if (d.autoRadio) html += sec('Voice', T('radio', 'Join squad radio automatically', 'You go on your squad\u2019s channel when you join, and back to your old one when you leave'));
    return html;
  };

  R.keys = () => sec('Keys & commands', `<div class="keys">${(NH.cfg.keys.length ? NH.cfg.keys : [
    { label: 'HUD settings', key: '/hud' }, { label: 'Toggle HUD', key: '/togglehud' }, { label: 'Seatbelt', key: 'B' }, { label: 'Cruise / limiter', key: 'Y' },
    { label: 'Vehicle control panel', key: 'F7' }, { label: 'Left indicator', key: 'LEFT' }, { label: 'Right indicator', key: 'RIGHT' }, { label: 'Hazard lights', key: '' }])
    .map(k => `<div class="key"><span>${k.label}</span><kbd>${k.key || 'Unbound'}</kbd></div>`).join('')}</div>`,
    'Keys are FiveM key mappings, so every player can rebind them in GTA Settings > Key Bindings > FiveM.');

  // ---- previews ----
  function fillPreviews(root) {
    root.querySelectorAll('[data-pv]').forEach(pv => {
      const [type, style] = pv.dataset.pv.split(':');
      if (type === 'status') pv.appendChild(NH.status.preview(style, NH.cur.status.color));
      else if (type === 'speedo') {
        const inst = NH.createSpeedo(style, 'MPH');
        NH.updateSpeedo(inst, Object.assign({}, NH.DEMO_SPEEDO, { odo: style === 'classic' ? '012480' : NH.DEMO_SPEEDO.odo }));
        const wrap = document.createElement('div');
        wrap.className = 'pv-speedo';
        wrap.appendChild(inst.el);
        pv.appendChild(wrap);
      } else if (type === 'team') {
        pv.appendChild(NH.teamPreview(style));
      } else if (type === 'voice') {
        const d = document.createElement('div');
        d.innerHTML = NH.voiceHtml(style);
        NH.fillVoice(d.firstElementChild, NH.voiceValues({ vr: 2, vrc: 3, rd: 12, tk: true, rt: style === 'card' }));
        d.firstElementChild.classList.toggle('no-name', !NH.cur.voice.label);
        pv.appendChild(d.firstElementChild);
      } else if (type === 'cross') {
        pv.appendChild(NH.crossPreview(style, NH.cur.crosshair));
      } else if (type === 'notify' || type === 'progress' || type === 'text') {
        pv.innerHTML = NH.uiPreview[type](style);
      } else if (type === 'clock') {
        pv.appendChild(NH.clockPreview(style));
      } else if (type === 'info') {
        pv.appendChild(NH.infoPreview(style));
      } else if (type === 'boat') {
        const inst = NH.createBoat(style);
        NH.updateBoat(inst, NH.DEMO_BOAT);
        pv.appendChild(inst.el);
      } else if (type === 'air') {
        const inst = NH.createAir(style);
        NH.updateAir(inst, NH.DEMO_AIR);
        const wrap = document.createElement('div');
        wrap.className = 'pv-speedo';
        wrap.appendChild(inst.el);
        pv.appendChild(wrap);
      }
    });
    if (window.TeamHud && root.querySelector('.hud.tpv')) TeamHud.demo(root);
    // shrink previews to fit their card
    requestAnimationFrame(() => root.querySelectorAll('.pv').forEach(pv => {
      const inner = pv.firstElementChild;
      if (!inner) return;
      inner.style.transform = '';
      const sx = (pv.clientWidth - 16) / inner.offsetWidth, sy = (pv.clientHeight - 12) / inner.offsetHeight;
      const s = Math.min(1, sx, sy);
      if (s < 1) inner.style.transform = `scale(${s.toFixed(3)})`;
    }));
  }

  // ---- UI ----
  const ui = NH.settingsUI = {
    el: null, tab: 'general', dirty: false, isOpen: false, resetArm: false,

    build() {
      const el = this.el = document.getElementById('settings');
      el.innerHTML = `
        <div class="st-win">
          <aside class="st-side">
            <div class="brand"><span class="brand-i">${ic('cog')}</span><div><b>NAYZEEE HUD</b><small>Customize your HUD</small></div></div>
            <nav>${TABS.map(t => `<button class="nav" data-tab="${t.id}">${ic(t.icon)}<span>${t.label}</span></button>`).join('')}</nav>
            <button class="btn-red reset-all" data-act="reset">${ic('reset')}<span>Reset to default</span></button>
          </aside>
          <main class="st-main">
            <header class="st-hd">
              <div><h3 id="st-title"></h3><small id="st-sub"></small></div>
              <div class="st-act"><span class="unsaved">Unsaved changes</span>
                <button class="btn-line" data-act="edit">${ic('move')}Edit layout</button>
                <button class="btn-line" data-act="revert">Discard</button>
                <button class="btn-teal" data-act="save">${ic('check')}Save changes</button>
                <button class="pill-close" data-act="close">Close</button></div>
            </header>
            <div class="st-body" id="st-body"></div>
          </main>
        </div>`;
      this.body = el.querySelector('#st-body');
      el.addEventListener('click', e => this.onClick(e));
      el.addEventListener('input', e => this.onInput(e));
      el.addEventListener('change', e => this.onChange(e));

      const bar = document.getElementById('editbar');
      bar.innerHTML = `<div class="eb panel"><span class="eb-i">${ic('move')}</span><div><b>Edit layout</b><small>Drag to move · Scroll to resize · Right-click to reset · Team HUD included</small></div>
        <button class="btn-line" data-act="layout-reset">${ic('reset')}Reset layout</button><button class="btn-teal" data-act="layout-done">${ic('check')}Done</button></div>`;
      bar.addEventListener('click', e => {
        const b = e.target.closest('[data-act]');
        if (!b) return;
        if (b.dataset.act === 'layout-reset') {
          NH.cur.layout = {};
          if (NH.cur.squads) { NH.cur.squads.hudPos = false; NH.cur.squads.hudScale = 100; }
          NH.applySettings();
          this.markDirty();
        }
        if (b.dataset.act === 'layout-done') this.editLayout(false);
      });
    },

    open() {
      if (this.isOpen) return;
      this.isOpen = true;
      const sqNav = this.el.querySelector('.nav[data-tab="squads"]');
      if (sqNav) sqNav.style.display = NH.cfg.squadsData ? '' : 'none';
      const xNav = this.el.querySelector('.nav[data-tab="crosshair"]');
      if (xNav) xNav.style.display = NH.cfg.crosshair === false ? 'none' : '';
      if (this.tab === 'crosshair' && NH.cfg.crosshair === false) this.tab = 'general';
      if (this.tab === 'squads' && !NH.cfg.squadsData) this.tab = 'general';
      NH.cur = NH.clone(NH.saved);
      this.dirty = false;
      this.el.classList.add('open');
      document.body.classList.add('settings-open');
      this.setTab(this.tab);
      this.updateDirty();
    },

    close() {
      if (!this.isOpen) return;
      if (NH.editing) this.editLayout(false);
      this.isOpen = false;
      if (this.dirty) { NH.cur = NH.saved; NH.applySettings(); NH.post('preview', NH.saved); }
      NH.cur = NH.saved;
      NH.toSquads?.('hudPreview', false);
      this.el.classList.remove('open');
      document.body.classList.remove('settings-open');
      NH.renderCrosshair?.();
      NH.post('close');
    },

    save() {
      NH.saved = NH.clone(NH.cur);
      NH.post('save', NH.saved);
      if (NH.cfg.squadsData && NH.saved.squads) NH.post('sq_saveSettings', NH.saved.squads);
      this.dirty = false;
      this.updateDirty();
      NH.toast('Settings saved');
    },

    revert() {
      NH.cur = NH.clone(NH.saved);
      NH.applySettings();
      NH.post('preview', NH.cur);
      this.dirty = false;
      this.render();
    },

    markDirty() { this.dirty = true; this.updateDirty(); },
    updateDirty() { this.el.classList.toggle('dirty', this.dirty); },

    setTab(id) {
      this.tab = id;
      NH.renderCrosshair?.();
      NH.toSquads?.('hudPreview', id === 'squads');
      this.el.querySelectorAll('.nav[data-tab]').forEach(n => n.classList.toggle('on', n.dataset.tab === id));
      const t = TABS.find(x => x.id === id);
      this.el.querySelector('#st-title').textContent = t.title;
      this.el.querySelector('#st-sub').textContent = t.sub;
      this.body.scrollTop = 0;
      this.render();
    },

    render() {
      const top = this.body.scrollTop;
      this.body.innerHTML = R[this.tab]();
      fillPreviews(this.body);
      this.body.scrollTop = top;
    },

    change(path, value, rerender = true) {
      NH.setPath(NH.cur, path, value);
      this.markDirty();
      NH.applySettings();
      if (path.startsWith('map.') || path.startsWith('status.') || path.startsWith('crosshair.')) NH.post('preview', NH.cur);
      if (rerender) this.render();
    },

    editLayout(on) {
      NH.editing = on;
      document.body.classList.toggle('editing', on);
      this.el.classList.toggle('hidden', on);
      NH.applySettings();
    },

    onClick(e) {
      const nav = e.target.closest('[data-tab]');
      if (nav) return this.setTab(nav.dataset.tab);
      const tog = e.target.closest('[data-tog]');
      if (tog) return this.change(tog.dataset.tog, !g(tog.dataset.tog));
      const sb = e.target.closest('[data-seg] button');
      if (sb) return this.change(sb.closest('[data-seg]').dataset.seg, sb.dataset.num ? Number(sb.dataset.val) : sb.dataset.val);
      const sv = e.target.closest('[data-setval]');
      if (sv) return this.change(sv.dataset.setval, sv.dataset.num ? Number(sv.dataset.val) : sv.dataset.val);
      const card = e.target.closest('[data-cards] .card');
      if (card) return this.change(card.closest('[data-cards]').dataset.cards, card.dataset.val);
      const sw = e.target.closest('[data-accent]');
      if (sw) return this.change('accent', sw.dataset.accent);
      const act = e.target.closest('[data-act]');
      if (!act) return;
      const a = act.dataset.act;
      if (a === 'fit-reset') { this.change('map.fit', { x: 0, y: 0, w: 0, h: 0 }); NH.place(); return; }
      if (a === 'test-notify') {
        NH.notify({ kind: 'success', title: 'Garage', message: 'Your vehicle is ready at Legion Square.', duration: 5000 });
        setTimeout(() => NH.notify({ kind: 'error', message: 'You do not have enough cash.', duration: 5000 }), 250);
        setTimeout(() => NH.notify({ kind: 'warning', title: 'Storm warning', message: 'Heavy rain coming in from the coast.', duration: 5000 }), 500);
        setTimeout(() => NH.notify({ kind: 'info', title: 'Tip', message: 'Press F1 to open your phone.', duration: 5000 }), 750);
        return;
      }
      if (a === 'test-progress') {
        NH.progress({ label: 'Picking the lock', duration: 4000, cancel: 'X' });
        setTimeout(() => NH.progress({ done: true }), 4000);
        return;
      }
      if (a === 'save') this.save();
      else if (a === 'close') this.close();
      else if (a === 'revert') this.revert();
      else if (a === 'edit') this.editLayout(true);
      else if (a === 'reset') {
        if (!this.resetArm) {
          this.resetArm = true;
          act.classList.add('armed');
          act.querySelector('span').textContent = 'Click again to reset';
          setTimeout(() => { this.resetArm = false; act.classList.remove('armed'); act.querySelector('span').textContent = 'Reset to default'; }, 3000);
          return;
        }
        this.resetArm = false;
        NH.cur = NH.clone(NH.DEFAULTS);
        this.markDirty();
        NH.applySettings();
        NH.post('preview', NH.cur);
        this.render();
        act.classList.remove('armed');
        act.querySelector('span').textContent = 'Reset to default';
      } else if (a === 'copy') {
        const codeEl = this.el.querySelector('#nh-export');
        const ta = document.createElement('textarea');
        ta.value = codeEl.textContent;
        document.body.appendChild(ta);
        ta.select();
        let ok = false;
        try { ok = document.execCommand('copy'); } catch (_) { ok = false; }
        ta.remove();
        if (ok) {
          act.classList.add('done');
          act.querySelector('span').textContent = 'Copied';
          setTimeout(() => { act.classList.remove('done'); const sp = act.querySelector('span'); if (sp) sp.textContent = 'Copy code'; }, 1800);
        } else {
          const r = document.createRange(); r.selectNodeContents(codeEl);
          const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
          NH.toast('Code selected, press Ctrl+C');
        }
      } else if (a === 'io-clear') {
        const ta = this.el.querySelector('#nh-import');
        if (ta) { ta.value = ''; NH.ioCheck(this.el); ta.focus(); }
      } else if (a === 'import') {
        const raw = this.el.querySelector('#nh-import').value.trim();
        try {
          const data = NH.ioDecode(raw);
          if (!data) throw new Error('bad');
          NH.cur = NH.merge(NH.clone(NH.DEFAULTS), data);
          this.markDirty();
          NH.applySettings();
          NH.post('preview', NH.cur);
          this.render();
          NH.toast('HUD code imported, press Save to keep it');
        } catch (_) {
          NH.ioCheck(this.el);
        }
      }
    },

    onInput(e) {
      const t = e.target;
      if (t.id === 'nh-import') { NH.ioCheck(this.el); return; }
      if (t.dataset.rng) {
        const v = +t.value;
        t.nextElementSibling.textContent = fmtVal(v, t.dataset.fmt);
        this.change(t.dataset.rng, v, false);
        if (t.dataset.rng.startsWith('map.fit.')) NH.place();
      } else if (t.dataset.scale) {
        const v = +t.value;
        t.nextElementSibling.textContent = Math.round(v * 100) + '%';
        const L = NH.cur.layout[t.dataset.scale] = NH.cur.layout[t.dataset.scale] || {};
        L.s = v;
        this.markDirty();
        NH.place();
      }
    },

    onChange(e) {
      const t = e.target;
      if (t.dataset.hex && /^#[\da-f]{6}$/i.test(t.value)) this.change(t.dataset.hex, t.value.toLowerCase());
    },
  };
})();
