/**
 * NAYZEEE WorldControl - UI Application
 * discord.gg/nayzeeedev
 */

const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-worldcontrol';

let isOpen = false;
let staticData = null;
let data = null;
let clockAnchor = null;      // { minutes, msPerMinute, frozen, at }
let weatherAnchor = null;    // { nextChangeIn, at }
let restartAnchor = null;    // { remaining, at } (panel)
let bannerAnchor = null;     // { remaining, at } (always-on banner)
let timeDirty = false;       // Admin is editing the Set Time sliders
const dragging = new Set();  // Sliders currently being dragged (don't overwrite them)

const DENSITY_META = {
    pedestrians:    { label: 'Pedestrians',    desc: 'NPC foot traffic',   icon: 'person-walking' },
    vehicles:       { label: 'Vehicles',       desc: 'Traffic on roads',   icon: 'car' },
    parkedCars:     { label: 'Parked Cars',    desc: 'Stationary vehicles', icon: 'square-parking' },
    randomVehicles: { label: 'Random Traffic', desc: 'Spawn rate',         icon: 'shuffle' },
    scenarioPeds:   { label: 'Scenario Peds',  desc: 'Ambient activities', icon: 'people-group' },
};

const SERVICE_META = {
    dispatch:      { label: 'Emergency Dispatch', desc: 'Police, EMS & fire respond' },
    garbageTrucks: { label: 'Garbage Trucks',     desc: 'Random bin lorries' },
    randomBoats:   { label: 'Random Boats',       desc: 'Ambient boats on water' },
    randomTrains:  { label: 'Trains',             desc: 'Ambient freight & metro' },
    randomCops:    { label: 'Cop Patrols',        desc: 'Ambient police cars & peds' },
    wantedLevel:   { label: 'Wanted Level',       desc: 'Players can get stars' },
    distantSirens: { label: 'Distant Sirens',     desc: 'Background siren audio' },
};

const $ = (id) => document.getElementById(id);
const pad = (n) => String(Math.floor(n)).padStart(2, '0');

function esc(value) {
    return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function formatCountdown(seconds) {
    seconds = Math.max(0, Math.ceil(seconds));
    return `${pad(seconds / 60)}:${pad(seconds % 60)}`;
}

function weatherInfo(id) {
    const list = staticData ? staticData.weatherTypes : [];
    return list.find((w) => w.id === id) || { id, label: id, icon: 'cloud' };
}

// ══════════════════════════════════════════════════════════════
// NUI
// ══════════════════════════════════════════════════════════════

function nuiPost(event, payload = {}) {
    return fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
    }).catch(() => {});
}

function action(name, payload = {}) {
    nuiPost('action', { name, data: payload });
}

window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || !msg.action) return;

    switch (msg.action) {
        case 'open':
            if (msg.static) {
                staticData = msg.static;
                renderStatic();
            }
            openUI(msg.data);
            break;
        case 'adminData':
            if (isOpen) renderData(msg.data);
            break;
        case 'close':
            hideUI();
            break;
        case 'toast':
            toast(msg.message, msg.kind);
            break;
        case 'restart':
            setBanner(msg);
            break;
        case 'siren':
            msg.play ? startSiren(msg.volume) : stopSiren();
            break;
    }
});

function openUI(adminData) {
    isOpen = true;
    timeDirty = false;
    renderData(adminData);
    $('app').classList.add('active');
}

function hideUI() {
    isOpen = false;
    closeModal();
    $('app').classList.remove('active');
}

function closeUI() {
    hideUI();
    nuiPost('close');
}

// ══════════════════════════════════════════════════════════════
// STATIC RENDER (built once from config)
// ══════════════════════════════════════════════════════════════

function tile(attrs, icon, label, small) {
    return `<button class="tile-btn" ${attrs}><i class="fas fa-${esc(icon)}"></i><span>${esc(label)}</span>${small ? `<small>${esc(small)}</small>` : ''}</button>`;
}

function renderStatic() {
    $('versionLabel').textContent = `v${staticData.version}`;

    // Weather
    $('weatherGrid').innerHTML = staticData.weatherTypes
        .map((w) => tile(`data-weather="${esc(w.id)}" title="${esc(w.id)}"`, w.icon, w.label))
        .join('');
    $('weatherGrid').querySelectorAll('[data-weather]').forEach((btn) => {
        btn.addEventListener('click', () => action('setWeather', { weather: btn.dataset.weather }));
    });

    // Quick times
    $('quickTimeGrid').innerHTML = staticData.quickTimes
        .map((t, i) => tile(`data-quick="${i}"`, t.icon, t.label, `${pad(t.hour)}:${pad(t.minute)}`))
        .join('');
    $('quickTimeGrid').querySelectorAll('[data-quick]').forEach((btn) => {
        btn.addEventListener('click', () => {
            const t = staticData.quickTimes[btn.dataset.quick];
            timeDirty = false;
            action('setTime', { hour: t.hour, minute: t.minute });
        });
    });

    // Traffic presets
    $('presetsGrid').innerHTML = staticData.presets
        .map((p) => tile(`data-preset="${esc(p.id)}"`, p.icon, p.label))
        .join('');
    $('presetsGrid').querySelectorAll('[data-preset]').forEach((btn) => {
        btn.addEventListener('click', () => action('trafficPreset', { id: btn.dataset.preset }));
    });

    $('densityModeHint').textContent = staticData.densityMode === 'zero' ? '0.00ms mode' : '';

    // Density sliders
    const max = Math.round(staticData.maxDensity * 100);
    $('densitySliders').innerHTML = Object.entries(DENSITY_META).map(([key, m]) => `
        <div class="slider-item">
            <div class="slider-header">
                <div class="slider-icon ${key}"><i class="fas fa-${m.icon}"></i></div>
                <div class="slider-info"><span class="slider-label">${m.label}</span><span class="slider-desc">${m.desc}</span></div>
                <span class="slider-value" id="${key}Value">100%</span>
            </div>
            <input type="range" class="slider" id="${key}" min="0" max="${max}" value="100">
        </div>`).join('');

    Object.keys(DENSITY_META).forEach((key) => {
        bindSlider(key, (v) => `${v}%`, (v) => action('setDensity', { key, value: v / 100 }));
    });

    // Services
    $('servicesGrid').innerHTML = staticData.services.map((key) => {
        const m = SERVICE_META[key] || { label: key, desc: '' };
        return `
        <div class="toggle-item">
            <div class="toggle-info"><span class="toggle-label">${esc(m.label)}</span><span class="toggle-desc">${esc(m.desc)}</span></div>
            <label class="switch"><input type="checkbox" data-service="${esc(key)}"><span></span></label>
        </div>`;
    }).join('');
    $('servicesGrid').querySelectorAll('[data-service]').forEach((input) => {
        input.addEventListener('change', () => action('setService', { key: input.dataset.service, value: input.checked }));
    });

    // Scenes
    $('scenesGrid').innerHTML = staticData.scenes.map((s) => {
        const parts = [];
        if (s.hour !== undefined) parts.push(`${pad(s.hour)}:${pad(s.minute || 0)}`);
        if (s.weather) parts.push(weatherInfo(s.weather).label);
        return tile(`data-scene="${esc(s.id)}"`, s.icon, s.label, parts.join(' • '));
    }).join('');
    $('scenesGrid').querySelectorAll('[data-scene]').forEach((btn) => {
        btn.addEventListener('click', () => action('scene', { id: btn.dataset.scene }));
    });

    // Restart
    $('restartSection').classList.toggle('hidden', !staticData.restartEnabled);
    $('restartMinutes').value = staticData.restartMinutes;
}

// ══════════════════════════════════════════════════════════════
// DATA RENDER (every server update)
// ══════════════════════════════════════════════════════════════

function setChecked(id, value) {
    const el = $(id);
    if (el) el.checked = !!value;
}

function setSlider(id, value, label) {
    if (dragging.has(id)) return;
    const slider = $(id);
    if (!slider) return;
    slider.value = value;
    $(id + 'Value').textContent = label;
    updateSliderTrack(slider);
}

function renderData(d) {
    if (!d || !staticData) return;
    data = d;
    const now = performance.now();

    // ── Header ──
    const current = weatherInfo(d.weather.current);
    $('chipWeather').textContent = current.label;
    $('chipWeatherIcon').className = `fas fa-${current.icon}`;
    $('chipPlayers').textContent = d.players;

    // ── Weather ──
    const w = d.weather;
    $('weatherHeroIcon').innerHTML = `<i class="fas fa-${esc(current.icon)}"></i>`;
    $('weatherHeroLabel').textContent = current.label;
    const badge = $('weatherMethodBadge');
    badge.textContent = w.method === 'real' ? 'Real World' : (w.dynamic ? 'Dynamic' : 'Static');
    badge.className = `hero-badge${w.method === 'real' ? ' real' : ''}`;

    weatherAnchor = w.method === 'game' && w.dynamic && w.nextChangeIn != null ? { nextChangeIn: w.nextChangeIn, at: now } : null;
    if (w.method === 'real') {
        const r = w.real;
        $('weatherHeroSub').textContent = r ? `${r.city}${r.country ? ', ' + r.country : ''} • ${r.description}${r.temp != null ? ` • ${r.temp}°C` : ''}` : 'Fetching real weather...';
    } else if (!w.dynamic) {
        $('weatherHeroSub').textContent = 'Dynamic weather is off - weather stays until changed';
    }

    $('forecastSection').classList.toggle('hidden', w.method !== 'game');
    const forecast = w.forecast || [];
    $('forecastRow').innerHTML = forecast.length ? forecast.map((id, i) => {
        const f = weatherInfo(id);
        const when = !w.dynamic ? `#${i + 1}` : (i === 0 ? 'Next' : `+${i * w.interval}m`);
        return `${i > 0 ? '<div class="forecast-arrow"><i class="fas fa-chevron-right"></i></div>' : ''}
            <div class="forecast-card${i === 0 ? ' next' : ''}"><i class="fas fa-${esc(f.icon)}"></i><span>${esc(f.label)}</span><small>${when}</small></div>`;
    }).join('') : '<div class="forecast-empty">No forecast available</div>';

    $('weatherGrid').querySelectorAll('[data-weather]').forEach((btn) => {
        btn.classList.toggle('active', btn.dataset.weather === w.current);
    });

    setChecked('optDynamic', w.dynamic);
    setChecked('optWeatherInstant', w.instant);
    setChecked('optRealWeather', w.method === 'real');
    $('realWeatherItem').classList.toggle('disabled', !w.realAvailable);
    $('realWeatherDesc').textContent = w.realAvailable ? 'Mirror a real city' : 'Needs an API key in config';
    $('optDynamic').closest('.toggle-item').classList.toggle('disabled', w.method === 'real');
    setSlider('interval', w.interval, `${w.interval}m`);

    // ── Atmosphere ──
    const world = d.world;
    setChecked('optBlackout', world.blackout);
    setChecked('optSnow', world.snowOnGround);
    setAutoSlider('wind', world.wind, (v) => Math.round(v * 10), (v) => (v / 10).toFixed(1));
    setSlider('windDirection', world.windDirection, `${world.windDirection}°`);
    setAutoSlider('rain', world.rain, (v) => Math.round(v * 100), (v) => `${v}%`);

    // ── Time ──
    const t = d.time;
    clockAnchor = {
        minutes: t.hour * 60 + t.minute + (t.second || 0) / 60,
        msPerMinute: t.msPerMinute,
        frozen: t.frozen,
        at: now,
    };
    const isReal = t.method === 'real';
    const timeBadge = $('timeStateBadge');
    timeBadge.textContent = isReal ? 'Real Time' : (t.frozen ? 'Frozen' : 'Running');
    timeBadge.className = `hero-badge${isReal ? ' real' : (t.frozen ? ' frozen' : '')}`;
    const dayLength = Math.round((t.msPerMinute * 1440) / 60000);
    $('clockHeroSub').textContent = isReal ? 'Following the real-world clock' : `Day length ${dayLength} min${t.frozen ? ' • clock stopped' : ''}`;

    setChecked('optFreeze', t.frozen);
    setChecked('optTimeInstant', d.timeInstant);
    setChecked('optRealTime', isReal);
    setSlider('dayLength', dayLength, `${dayLength}m`);
    ['optFreeze', 'dayLength', 'applyTimeBtn', 'hour', 'minute'].forEach((id) => {
        const el = $(id);
        const holder = el.closest('.toggle-item') || el.closest('.slider-item') || el;
        holder.classList.toggle('disabled', isReal);
        if (holder === el) el.style.opacity = isReal ? 0.45 : '';
        el.disabled = isReal;
    });
    $('quickTimeGrid').style.opacity = isReal ? 0.45 : '';
    $('quickTimeGrid').style.pointerEvents = isReal ? 'none' : '';

    if (!timeDirty) {
        setSlider('hour', t.hour, pad(t.hour));
        setSlider('minute', t.minute, pad(t.minute));
        $('timePreview').textContent = `${pad(t.hour)}:${pad(t.minute)}`;
    }

    // ── Traffic ──
    const dens = d.traffic.density;
    Object.keys(DENSITY_META).forEach((key) => {
        const v = Math.round((dens[key] ?? 1) * 100); // ?? keeps 0% as 0% (old version showed 100%)
        setSlider(key, v, `${v}%`);
    });
    $('presetsGrid').querySelectorAll('[data-preset]').forEach((btn) => {
        const p = staticData.presets.find((x) => x.id === btn.dataset.preset);
        const match = p && Object.keys(DENSITY_META).every((k) => Math.abs((p[k] ?? 1) - (dens[k] ?? 1)) < 0.001);
        btn.classList.toggle('active', !!match);
    });
    $('servicesGrid').querySelectorAll('[data-service]').forEach((input) => {
        input.checked = !!d.traffic.services[input.dataset.service];
    });

    // ── Restart ──
    const r = d.restart;
    restartAnchor = r.active ? { remaining: r.remaining, at: now } : null;
    $('restartCard').classList.toggle('active', r.active);
    $('restartStartBtn').classList.toggle('hidden', r.active);
    $('restartCancelBtn').classList.toggle('hidden', !r.active);
    if (!r.active) {
        $('restartStateLabel').textContent = 'Inactive';
        $('restartStateDesc').textContent = 'Auto-starts on txAdmin scheduled restarts';
    }

    // ── Activity ──
    $('logList').innerHTML = d.log.length ? d.log.map((entry) => `
        <div class="log-item">
            <div class="slider-icon accent"><i class="fas fa-${esc(entry.icon)}"></i></div>
            <div class="log-text"><b>${esc(entry.name)}</b> ${esc(entry.text)}</div>
            <span class="log-time">${esc(entry.at)}</span>
        </div>`).join('') : '<div class="log-empty"><i class="fas fa-inbox"></i><br>No changes yet this session</div>';

    tick();
}

function setAutoSlider(id, value, toSlider, toLabel) {
    const isAuto = value < 0;
    const slider = $(id);
    slider.classList.toggle('auto', isAuto);
    document.querySelector(`[data-auto="${id}"]`).classList.toggle('active', isAuto);
    if (isAuto) {
        if (!dragging.has(id)) $(id + 'Value').textContent = 'Auto';
        return;
    }
    const v = toSlider(value);
    setSlider(id, v, toLabel(v));
}

// ══════════════════════════════════════════════════════════════
// LIVE TICKERS
// ══════════════════════════════════════════════════════════════

function tick() {
    const now = performance.now();

    if (clockAnchor) {
        let minutes = clockAnchor.minutes;
        if (!clockAnchor.frozen) minutes += (now - clockAnchor.at) / clockAnchor.msPerMinute;
        minutes = ((minutes % 1440) + 1440) % 1440;
        const h = Math.floor(minutes / 60);
        const m = Math.floor(minutes % 60);
        const text = `${pad(h)}:${pad(m)}`;
        $('chipTime').textContent = text;
        $('clockHero').textContent = text;
        const day = h >= 6 && h < 20;
        const icon = $('clockHeroIcon');
        const iconClass = `hero-icon time ${day ? 'day' : 'night'}`;
        if (icon.className !== iconClass) {
            icon.className = iconClass;
            icon.innerHTML = `<i class="fas fa-${day ? 'sun' : 'moon'}"></i>`;
        }
    }

    if (weatherAnchor) {
        const left = weatherAnchor.nextChangeIn - (now - weatherAnchor.at) / 1000;
        $('weatherHeroSub').textContent = `Next change in ${formatCountdown(left)}`;
    }

    if (restartAnchor) {
        const left = restartAnchor.remaining - (now - restartAnchor.at) / 1000;
        $('restartStateLabel').textContent = `Active • ${formatCountdown(left)}`;
        $('restartStateDesc').textContent = 'Storm, blackout and siren are running for every player';
    }

    if (bannerAnchor) {
        const left = bannerAnchor.remaining - (now - bannerAnchor.at) / 1000;
        $('bannerTimer').textContent = formatCountdown(left);
    }
}

setInterval(tick, 250);

// ══════════════════════════════════════════════════════════════
// SLIDERS
// ══════════════════════════════════════════════════════════════

function updateSliderTrack(slider) {
    const percent = ((slider.value - slider.min) / (slider.max - slider.min)) * 100;
    slider.style.background = `linear-gradient(to right, #08afa2 0%, #08afa2 ${percent}%, #1c2128 ${percent}%, #1c2128 100%)`;
}

function bindSlider(id, label, onCommit) {
    const slider = $(id);
    if (!slider) return;
    updateSliderTrack(slider);

    slider.addEventListener('input', () => {
        dragging.add(id);
        $(id + 'Value').textContent = label(Number(slider.value));
        slider.classList.remove('auto');
        updateSliderTrack(slider);
    });

    slider.addEventListener('change', () => {
        dragging.delete(id);
        onCommit(Number(slider.value));
    });
}

// ══════════════════════════════════════════════════════════════
// CONFIRM MODAL
// ══════════════════════════════════════════════════════════════

let confirmCallback = null;

function confirmAction(title, text, cb) {
    $('confirmTitle').textContent = title;
    $('confirmText').textContent = text;
    confirmCallback = cb;
    $('confirmModal').classList.remove('hidden');
}

function closeModal() {
    confirmCallback = null;
    $('confirmModal').classList.add('hidden');
}

// ══════════════════════════════════════════════════════════════
// RESTART BANNER + SIREN (always on, no focus)
// ══════════════════════════════════════════════════════════════

function setBanner(msg) {
    if (msg.active) {
        bannerAnchor = { remaining: msg.remaining, at: performance.now() };
        $('bannerTitle').textContent = msg.title || 'Tsunami Warning';
        $('bannerText').textContent = msg.message || '';
        $('restartBanner').classList.remove('hidden');
        tick();
    } else {
        bannerAnchor = null;
        $('restartBanner').classList.add('hidden');
    }
}

let siren = null;

// Synthesised air-raid style siren (no audio files needed)
function startSiren(volume = 0.25) {
    if (siren) return;
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = ctx.createOscillator();
        osc.type = 'sawtooth';
        osc.frequency.value = 620;

        const lfo = ctx.createOscillator();
        lfo.frequency.value = 0.16;
        const lfoGain = ctx.createGain();
        lfoGain.gain.value = 300;
        lfo.connect(lfoGain).connect(osc.frequency);

        const filter = ctx.createBiquadFilter();
        filter.type = 'lowpass';
        filter.frequency.value = 1300;

        const gain = ctx.createGain();
        gain.gain.setValueAtTime(0, ctx.currentTime);
        gain.gain.linearRampToValueAtTime(Math.max(0, Math.min(1, volume)), ctx.currentTime + 3);

        osc.connect(filter).connect(gain).connect(ctx.destination);
        osc.start();
        lfo.start();
        siren = { ctx, gain };
    } catch (e) {
        siren = null;
    }
}

function stopSiren() {
    if (!siren) return;
    const { ctx, gain } = siren;
    siren = null;
    gain.gain.cancelScheduledValues(ctx.currentTime);
    gain.gain.setValueAtTime(gain.gain.value, ctx.currentTime);
    gain.gain.linearRampToValueAtTime(0, ctx.currentTime + 1.5);
    setTimeout(() => ctx.close().catch(() => {}), 1700);
}

// ══════════════════════════════════════════════════════════════
// TOASTS
// ══════════════════════════════════════════════════════════════

const TOAST_ICONS = { success: 'circle-check', error: 'circle-xmark', warning: 'triangle-exclamation', info: 'circle-info' };

function toast(message, kind = 'info') {
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.innerHTML = `<i class="fas fa-${TOAST_ICONS[kind] || TOAST_ICONS.info}"></i><span>${esc(message)}</span>`;
    $('toastStack').appendChild(el);
    setTimeout(() => {
        el.classList.add('out');
        setTimeout(() => el.remove(), 300);
    }, 4000);
}

// ══════════════════════════════════════════════════════════════
// EVENT LISTENERS
// ══════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
    $('closeBtn').addEventListener('click', closeUI);

    // Tabs (remember the last one)
    const showTab = (tab) => {
        document.querySelectorAll('.nav-btn').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
        document.querySelectorAll('.tab').forEach((s) => s.classList.toggle('active', s.id === `tab-${tab}`));
        try { localStorage.setItem('nwc:tab', tab); } catch (e) { /* storage unavailable */ }
    };
    document.querySelectorAll('.nav-btn').forEach((btn) => btn.addEventListener('click', () => showTab(btn.dataset.tab)));
    try {
        const saved = localStorage.getItem('nwc:tab');
        if (saved && $(`tab-${saved}`)) showTab(saved);
    } catch (e) { /* storage unavailable */ }

    // Weather
    $('skipBtn').addEventListener('click', () => action('skipWeather'));
    $('rerollBtn').addEventListener('click', () => action('rerollForecast'));
    $('optDynamic').addEventListener('change', (e) => action('weatherOptions', { dynamic: e.target.checked }));
    $('optWeatherInstant').addEventListener('change', (e) => action('weatherOptions', { instant: e.target.checked }));
    $('optRealWeather').addEventListener('change', (e) => action('weatherOptions', { method: e.target.checked ? 'real' : 'game' }));
    bindSlider('interval', (v) => `${v}m`, (v) => action('weatherOptions', { interval: v }));

    // Atmosphere
    $('optBlackout').addEventListener('change', (e) => action('setWorld', { blackout: e.target.checked }));
    $('optSnow').addEventListener('change', (e) => action('setWorld', { snowOnGround: e.target.checked }));
    bindSlider('wind', (v) => (v / 10).toFixed(1), (v) => action('setWorld', { wind: v / 10 }));
    bindSlider('windDirection', (v) => `${v}°`, (v) => action('setWorld', { windDirection: v }));
    bindSlider('rain', (v) => `${v}%`, (v) => action('setWorld', { rain: v / 100 }));
    document.querySelectorAll('[data-auto]').forEach((btn) => {
        btn.addEventListener('click', () => action('setWorld', { [btn.dataset.auto]: -1 }));
    });

    // Time
    const previewTime = () => {
        $('timePreview').textContent = `${pad($('hour').value)}:${pad($('minute').value)}`;
    };
    bindSlider('hour', (v) => { timeDirty = true; setTimeout(previewTime); return pad(v); }, () => { timeDirty = true; previewTime(); });
    bindSlider('minute', (v) => { timeDirty = true; setTimeout(previewTime); return pad(v); }, () => { timeDirty = true; previewTime(); });
    $('applyTimeBtn').addEventListener('click', () => {
        timeDirty = false;
        action('setTime', { hour: Number($('hour').value), minute: Number($('minute').value) });
    });
    $('optFreeze').addEventListener('change', (e) => action('timeOptions', { frozen: e.target.checked }));
    $('optTimeInstant').addEventListener('change', (e) => action('timeOptions', { instant: e.target.checked }));
    $('optRealTime').addEventListener('change', (e) => action('timeOptions', { method: e.target.checked ? 'real' : 'game' }));
    bindSlider('dayLength', (v) => `${v}m`, (v) => action('timeOptions', { msPerMinute: Math.round((v * 60000) / 1440) }));

    // Traffic
    $('purgeBtn').addEventListener('click', () => action('purge'));
    $('resetTrafficBtn').addEventListener('click', () => {
        confirmAction('Reset traffic?', 'All densities and ambient services go back to the config defaults for every player.', () => action('resetTraffic'));
    });

    // Events
    $('lightningBtn').addEventListener('click', () => action('lightning'));
    document.querySelectorAll('.number-input [data-step]').forEach((btn) => {
        btn.addEventListener('click', () => {
            const input = $('restartMinutes');
            input.value = Math.max(1, Math.min(60, (Number(input.value) || 5) + Number(btn.dataset.step)));
        });
    });
    $('restartStartBtn').addEventListener('click', () => {
        const minutes = Math.max(1, Math.min(60, Number($('restartMinutes').value) || 5));
        confirmAction('Start restart warning?', `Every player gets a ${minutes} minute storm, blackout and siren countdown.`, () => action('restartStart', { minutes }));
    });
    $('restartCancelBtn').addEventListener('click', () => action('restartCancel'));

    // Modal
    $('confirmNo').addEventListener('click', closeModal);
    $('confirmYes').addEventListener('click', () => {
        const cb = confirmCallback;
        closeModal();
        if (cb) cb();
    });

    // Escape closes the modal first, then the panel
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape' || !isOpen) return;
        if (!$('confirmModal').classList.contains('hidden')) closeModal();
        else closeUI();
    });
});
