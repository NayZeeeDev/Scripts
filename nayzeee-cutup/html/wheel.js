'use strict';
/* =====================================================================
   CUT UP - race wheel support
   Reads any wheel / pad Windows exposes (DirectInput or XInput) through the
   Gamepad API, maps + calibrates it per device and streams it to the game.
   ===================================================================== */

const WHEEL_PRESETS = {
    generic: { label: 'Generic wheel', rotation: 900, softLock: 540 },
    g29: { label: 'Logitech G29 / G920 / G923', rotation: 900, softLock: 540 },
    t300: { label: 'Thrustmaster T150 / T300 / TX / T-GT', rotation: 1080, softLock: 540 },
    t458: {
        label: 'Thrustmaster Ferrari 458 Spider (Xbox)', rotation: 240, softLock: 240,
        note: 'Xbox One wheel with no official PC driver. If Windows shows it as an Xbox controller, this preset maps it: wheel on the left stick, pedals on the triggers, paddles on the bumpers. Run the Setup wizard if anything is off.',
        map: {
            steer: { src: { type: 'axis', index: 0 } },
            throttle: { src: { type: 'button', index: 7 }, rest: 0, full: 1 },
            brake: { src: { type: 'button', index: 6 }, rest: 0, full: 1 },
            buttons: { shiftUp: 5, shiftDown: 4, handbrake: 0, flash: 1, lookBack: 2, camera: 3, hud: 8, mode: 9 },
        },
    },
    fanatec: { label: 'Fanatec CSL / ClubSport / DD', rotation: 1080, softLock: 540 },
    moza: { label: 'Moza R3 / R5 / R9 / R12', rotation: 900, softLock: 540 },
    simagic: { label: 'Simagic Alpha / Evo', rotation: 900, softLock: 540 },
    pad: {
        label: 'Gamepad (stick steering)', rotation: 1, softLock: 1,
        map: {
            steer: { src: { type: 'axis', index: 0 }, deadzone: .08, gamma: 1.4 },
            throttle: { src: { type: 'button', index: 7 }, rest: 0, full: 1 },
            brake: { src: { type: 'button', index: 6 }, rest: 0, full: 1 },
            buttons: { shiftUp: 5, shiftDown: 4, handbrake: 0, flash: 1, lookBack: 2, camera: 3 },
        },
    },
};

const BUTTON_ACTIONS = [
    ['shiftUp', 'Shift up'], ['shiftDown', 'Shift down'], ['handbrake', 'Handbrake'], ['horn', 'Horn'],
    ['flash', 'Flash high beams'], ['lookBack', 'Look back'], ['camera', 'Cycle camera'], ['hud', 'Toggle HUD'], ['mode', 'Toggle CUT UP'],
    ['gear1', 'Gear 1'], ['gear2', 'Gear 2'], ['gear3', 'Gear 3'], ['gear4', 'Gear 4'], ['gear5', 'Gear 5'], ['gear6', 'Gear 6'], ['gear7', 'Gear 7'], ['gearR', 'Reverse'],
];
const HOLD_ACTIONS = { handbrake: 'h', horn: 'horn', lookBack: 'lb' };

const WheelMgr = (() => {
    let cfg = { Enabled: true, SendRate: 16, Rumble: true };
    let profiles = {};
    let timer = null;
    let lastSent = 0, lastPayload = '', inFlight = false;
    let prevButtons = {};
    let lastGear = 0;
    const out = { s: 0, t: 0, b: 0, c: 0, h: false, horn: false, lb: false, on: false, gear: 0 };
    let listener = null;     // active detect

    const pads = () => Array.from(navigator.getGamepads ? navigator.getGamepads() : []).filter(Boolean);
    const padById = id => pads().find(p => p.id === id);

    function blank(gp, presetKey = 'generic') {
        const pre = WHEEL_PRESETS[presetKey] || WHEEL_PRESETS.generic;
        const p = {
            id: gp.id, name: gp.id.replace(/\(.*?\)/g, '').trim() || 'Wheel', enabled: false, preset: presetKey, rumble: true,
            steer: { src: { type: 'axis', index: 0 }, center: 0, invert: false, rotation: pre.rotation, softLock: pre.softLock, sensitivity: 1, deadzone: 0, gamma: 1 },
            throttle: { src: null, rest: -1, full: 1, deadzone: .02, gamma: 1 },
            brake: { src: null, rest: -1, full: 1, deadzone: .02, gamma: 1.2 },
            clutch: { src: null, rest: -1, full: 1, deadzone: .05, gamma: 1 },
            buttons: {},
        };
        applyPreset(p, presetKey);
        return p;
    }

    function applyPreset(p, key) {
        const pre = WHEEL_PRESETS[key];
        if (!pre) return;
        p.preset = key;
        p.steer.rotation = pre.rotation;
        p.steer.softLock = pre.softLock;
        if (pre.map) {
            if (pre.map.steer) Object.assign(p.steer, JSON.parse(JSON.stringify(pre.map.steer)));
            ['throttle', 'brake', 'clutch'].forEach(k => { if (pre.map[k]) Object.assign(p[k], JSON.parse(JSON.stringify(pre.map[k]))); });
            if (pre.map.buttons) p.buttons = Object.assign({}, pre.map.buttons);
        }
    }

    function read(gp, src) {
        if (!gp || !src) return 0;
        if (src.type === 'axis') return gp.axes[src.index] ?? 0;
        const b = gp.buttons[src.index];
        return b ? b.value : 0;
    }

    function pedal(gp, c) {
        if (!c || !c.src) return 0;
        const span = c.full - c.rest;
        if (Math.abs(span) < .05) return 0;
        let v = clamp((read(gp, c.src) - c.rest) / span, 0, 1);
        const dz = c.deadzone || 0;
        v = v <= dz ? 0 : (v - dz) / (1 - dz);
        return Math.pow(v, c.gamma || 1);
    }

    function steering(gp, c) {
        if (!c || !c.src) return 0;
        let v = read(gp, c.src) - (c.center || 0);
        if (c.invert) v = -v;
        v *= (c.rotation / Math.max(1, c.softLock)) * (c.sensitivity || 1);
        const a = Math.abs(v), dz = c.deadzone || 0;
        const m = a <= dz ? 0 : Math.pow(Math.min(1, (a - dz) / (1 - dz)), c.gamma || 1);
        return clamp(Math.sign(v) * m, -1, 1);
    }

    function activeProfile() {
        for (const gp of pads()) {
            const p = profiles[gp.id];
            if (p && p.enabled) return [gp, p];
        }
        return [null, null];
    }

    function pressed(gp, idx) {
        const b = idx !== undefined && idx !== null ? gp.buttons[idx] : null;
        return !!(b && (b.pressed || b.value > .5));
    }

    function tick() {
        if (listener) listen();
        const [gp, p] = activeProfile();
        const ui = window.WheelUI;
        if (!gp || !cfg.Enabled) {
            if (out.on) { out.on = false; send(true); }
            if (ui) ui.live(null, null);
            return;
        }
        out.on = true;
        out.s = +steering(gp, p.steer).toFixed(4);
        out.t = +pedal(gp, p.throttle).toFixed(3);
        out.b = +pedal(gp, p.brake).toFixed(3);
        out.c = +pedal(gp, p.clutch).toFixed(3);

        const btn = p.buttons || {};
        for (const [action, key] of Object.entries(HOLD_ACTIONS)) out[key] = pressed(gp, btn[action]);

        // edges for tap actions + H-shifter
        if (!listener) {
            for (const [action] of BUTTON_ACTIONS) {
                if (HOLD_ACTIONS[action] || action.startsWith('gear')) continue;
                const now = pressed(gp, btn[action]);
                if (now !== !!prevButtons[action]) {
                    if (action === 'flash' || now) post('wheelButton', { action, down: now });
                    prevButtons[action] = now;
                }
            }
            let gear = 0;
            for (let g = 1; g <= 7; g++) if (pressed(gp, btn[`gear${g}`])) gear = g;
            if (pressed(gp, btn.gearR)) gear = -1;
            const hasShifter = Object.keys(btn).some(k => k.startsWith('gear') && btn[k] !== null && btn[k] !== undefined);
            if (hasShifter && gear !== lastGear) { post('wheelButton', { action: 'gear', value: gear }); lastGear = gear; }
            out.gear = gear;
        }
        send(false);
        if (ui) ui.live(gp, out);
    }

    function send(force) {
        const payload = JSON.stringify(out);
        const now = performance.now();
        if (!force && (inFlight || (payload === lastPayload && now - lastSent < 250))) return;
        inFlight = true;
        lastPayload = payload; lastSent = now;
        post('wheelInput', out).finally(() => { inFlight = false; });
    }

    /* ---------- detection ---------- */
    function snapshot(gp) {
        return { axes: Array.from(gp.axes), buttons: gp.buttons.map(b => ({ v: b.value, p: b.pressed })) };
    }

    // kind: 'steer' | 'pedal' | 'button'
    function startListen(gpId, kind, done) {
        const gp = padById(gpId);
        if (!gp) return false;
        listener = { gpId, kind, done, base: snapshot(gp), phase: 'press', best: null, stableSince: 0, started: performance.now() };
        return true;
    }

    function stopListen(result) {
        const l = listener;
        listener = null;
        if (l && l.done) l.done(result);
    }

    function listen() {
        const l = listener;
        const gp = padById(l.gpId);
        if (!gp) return stopListen(null);
        if (performance.now() - l.started > 12000) return stopListen(null);
        const now = performance.now();

        if (l.kind === 'button') {
            for (let i = 0; i < gp.buttons.length; i++) {
                if (gp.buttons[i].pressed && !l.base.buttons[i]?.p) return stopListen({ index: i });
            }
            return;
        }

        if (l.phase === 'press') {
            let best = null;
            gp.axes.forEach((v, i) => {
                const d = v - l.base.axes[i];
                if (!best || Math.abs(d) > Math.abs(best.d)) best = { type: 'axis', index: i, d, v };
            });
            if (l.kind === 'pedal') {
                gp.buttons.forEach((b, i) => {
                    const d = b.value - l.base.buttons[i].v;
                    if (Math.abs(d) > Math.abs(best?.d || 0) && b.value > 0 && b.value < 1.01) best = { type: 'button', index: i, d, v: b.value };
                });
            }
            if (best && Math.abs(best.d) > .45) {
                if (!l.best || l.best.type !== best.type || l.best.index !== best.index) { l.best = best; l.stableSince = now; }
                if (Math.abs(best.v) > Math.abs(l.best.v)) l.best.v = best.v;
                if (now - l.stableSince > 350) {
                    if (l.kind === 'steer') {
                        return stopListen({ src: { type: best.type, index: best.index }, center: l.base.axes[best.index] || 0, invert: best.d < 0 });
                    }
                    l.full = l.best.v;
                    l.phase = 'release';
                    l.stableSince = now;
                    if (window.WheelUI) WheelUI.prompt('Now let go of it');
                }
            } else {
                l.stableSince = now;
            }
            return;
        }

        // pedal released: capture the true resting value (some pedals report 0 until first touched)
        const v = read(gp, { type: l.best.type, index: l.best.index });
        if (Math.abs(v - l.full) > .5) {
            if (!l.restSince) l.restSince = now;
            if (now - l.restSince > 400) {
                return stopListen({ src: { type: l.best.type, index: l.best.index }, rest: v, full: l.full });
            }
        } else {
            l.restSince = 0;
        }
    }

    return {
        configure(c) {
            if (c) cfg = Object.assign(cfg, c);
            clearInterval(timer);
            timer = setInterval(tick, Math.max(8, cfg.SendRate || 16));
        },
        setProfiles(p) { profiles = p && typeof p === 'object' && !Array.isArray(p) ? p : {}; },
        profiles: () => profiles,
        save() { post('wheelSave', { profiles }); },
        pads, padById, blank, applyPreset, read, startListen, stopListen,
        listening: () => !!listener,
        rumble(d) {
            if (!cfg.Rumble) return;
            const [gp, p] = activeProfile();
            const target = gp || pads()[0];
            if (!target || (p && p.rumble === false)) return;
            const act = target.vibrationActuator;
            if (act && act.playEffect) {
                act.playEffect('dual-rumble', { duration: d.duration || 150, strongMagnitude: d.strong || .5, weakMagnitude: d.weak || .5 }).catch(() => {});
            }
        },
    };
})();
window.WheelMgr = WheelMgr;
WheelMgr.configure();

/* ============================== WHEEL TAB ============================== */
const WheelUI = (() => {
    let root = null, selected = null, wizard = null;
    let refs = {};

    function profile() {
        if (!selected) return null;
        const all = WheelMgr.profiles();
        if (!all[selected]) {
            const gp = WheelMgr.padById(selected);
            if (!gp) return null;
            all[selected] = WheelMgr.blank(gp, /xbox|xinput/i.test(gp.id) ? 'pad' : 'generic');
        }
        return all[selected];
    }

    const srcLabel = s => !s ? 'Not set' : s.type === 'axis' ? `Axis ${s.index}` : `Button ${s.index} (analog)`;

    function save() { WheelMgr.save(); }

    function devices() {
        const box = el('div', 'devices');
        const list = WheelMgr.pads();
        if (!list.length) {
            box.appendChild(el('div', 'note', 'No wheel or pad found. Plug it in and press any button or turn the wheel so Windows wakes it up. This page checks again on its own.'));
            return box;
        }
        if (!selected || !WheelMgr.padById(selected)) selected = list[0].id;
        list.forEach(gp => {
            const p = WheelMgr.profiles()[gp.id];
            const d = el('div', `device${gp.id === selected ? ' sel' : ''}`, `${ICONS.wheel}<span class="dev-name">${esc(gp.id)}</span>
                <span class="muted">${gp.axes.length} axes · ${gp.buttons.length} buttons</span>${p && p.enabled ? '<span class="badge">ACTIVE</span>' : ''}`);
            d.onclick = () => { selected = gp.id; render(true); };
            box.appendChild(d);
        });
        return box;
    }

    function liveBlock() {
        const box = el('div', 'card wheel-live');
        box.innerHTML = `<svg class="wheel-svg" viewBox="0 0 100 100" id="wl-wheel">
                <circle cx="50" cy="50" r="44" stroke-width="7"/><circle cx="50" cy="50" r="9" stroke-width="4"/>
                <path d="M6 50h35M59 50h35M50 59v35" stroke-width="5"/><path class="mark" d="M50 6v8"/></svg>
            <div>
                <div class="row" style="align-items:flex-end;gap:1.4rem">
                    <div class="pedals">
                        <div class="pedal c"><div class="bar"><i id="wl-c"></i></div>CLU</div>
                        <div class="pedal b"><div class="bar"><i id="wl-b"></i></div>BRK</div>
                        <div class="pedal t"><div class="bar"><i id="wl-t"></i></div>THR</div>
                    </div>
                    <div><small class="muted">Gear</small><div class="gear-live" id="wl-gear">N</div></div>
                    <div class="spacer"><small class="muted">Steering output</small><div class="num" id="wl-steer" style="font-size:1.6rem">0%</div></div>
                </div>
                <div class="raw" id="wl-raw" style="margin-top:.6rem"></div>
            </div>`;
        refs = { wheel: $('#wl-wheel', box), t: $('#wl-t', box), b: $('#wl-b', box), c: $('#wl-c', box), gear: $('#wl-gear', box), steer: $('#wl-steer', box), raw: $('#wl-raw', box) };
        return box;
    }

    function axisRow(label, key, kind) {
        const p = profile();
        const c = p[key];
        const row = el('div', 'map-row', `<b>${label}</b><span class="src ${c.src ? '' : 'none'}">${srcLabel(c.src)}</span>`);
        const det = el('button', 'btn small ghost', 'Detect');
        det.onclick = () => {
            row.classList.add('listening');
            prompt(kind === 'steer' ? 'Turn the wheel to the RIGHT and hold it' : `Press the ${label.toUpperCase()} all the way down`);
            WheelMgr.startListen(selected, kind, res => {
                row.classList.remove('listening');
                prompt(null);
                if (res) { Object.assign(c, res); save(); }
                render(true);
            });
        };
        const clr = el('button', 'btn small ghost', 'Clear');
        clr.onclick = () => { c.src = null; save(); render(true); };
        row.append(det, key === 'steer' ? el('span') : clr);
        return row;
    }

    function numField(label, obj, key, min, max, step, format) {
        const f = el('div', 'field');
        f.innerHTML = `<div class="field-top"><span>${esc(label)}</span><output>${format(obj[key])}</output></div><input type="range" min="${min}" max="${max}" step="${step}" value="${obj[key]}">`;
        const input = $('input', f), outp = $('output', f);
        const paint = () => input.style.setProperty('--fill', `${((input.value - min) / (max - min)) * 100}%`);
        paint();
        input.oninput = () => { obj[key] = parseFloat(input.value); outp.textContent = format(obj[key]); paint(); };
        input.onchange = save;
        return f;
    }

    function switchField(label, obj, key, hint) {
        const f = el('div', 'field', `<div class="field-top"><span>${esc(label)}</span><div class="switch ${obj[key] ? 'on' : ''}"></div></div>${hint ? `<small>${esc(hint)}</small>` : ''}`);
        $('.switch', f).onclick = e => { obj[key] = !obj[key]; e.target.classList.toggle('on', obj[key]); save(); };
        return f;
    }

    function buttons() {
        const p = profile();
        const grid = el('div', 'btn-grid');
        BUTTON_ACTIONS.forEach(([action, label]) => {
            const idx = p.buttons[action];
            const b = el('div', 'btn-map', `<span>${label}</span><b class="${idx === undefined || idx === null ? 'none' : ''}">${idx === undefined || idx === null ? '-' : `B${idx}`}</b>`);
            b.dataset.action = action;
            b.onclick = () => {
                if (WheelMgr.listening()) return;
                b.classList.add('listening');
                prompt(`Press the button for ${label.toUpperCase()}`);
                WheelMgr.startListen(selected, 'button', res => {
                    prompt(null);
                    if (res) { p.buttons[action] = res.index; save(); }
                    render(true);
                });
            };
            b.oncontextmenu = e => { e.preventDefault(); p.buttons[action] = null; save(); render(true); };
            grid.appendChild(b);
        });
        return grid;
    }

    function promptEl() {
        const p = el('div', 'wizard hidden', '<h5></h5><p>Press Esc to cancel</p>');
        p.id = 'wl-prompt';
        return p;
    }

    function prompt(text) {
        const p = root && $('#wl-prompt', root);
        if (!p) return;
        p.classList.toggle('hidden', !text);
        if (text) $('h5', p).textContent = text;
    }

    const WIZARD = [
        { key: 'steer', kind: 'steer', text: 'Turn the wheel to the RIGHT and hold it' },
        { key: 'throttle', kind: 'pedal', text: 'Press the THROTTLE all the way down' },
        { key: 'brake', kind: 'pedal', text: 'Press the BRAKE all the way down' },
        { key: 'clutch', kind: 'pedal', text: 'Press the CLUTCH all the way down', skip: true },
        { key: 'shiftUp', kind: 'button', text: 'Pull the paddle / button for SHIFT UP', skip: true },
        { key: 'shiftDown', kind: 'button', text: 'Pull the paddle / button for SHIFT DOWN', skip: true },
    ];

    function runWizard(step = 0) {
        const p = profile();
        if (step >= WIZARD.length) { wizard = null; p.enabled = true; save(); render(true); return; }
        wizard = step;
        render(true);
        const s = WIZARD[step];
        WheelMgr.startListen(selected, s.kind, res => {
            if (wizard === null) return;
            if (res) {
                if (s.kind === 'button') p.buttons[s.key] = res.index;
                else Object.assign(p[s.key], res);
                save();
                runWizard(step + 1);
            } else if (s.skip) {
                runWizard(step + 1);
            } else {
                wizard = null; render(true);
            }
        });
    }

    function wizardEl() {
        const s = WIZARD[wizard];
        const w = el('div', 'wizard', `<div class="steps">${WIZARD.map((_, i) => `<i class="${i < wizard ? 'done' : ''}"></i>`).join('')}</div>
            <h5>${esc(s.text)}</h5><p>Step ${wizard + 1} of ${WIZARD.length}. Pedals: press fully, then let go.</p>`);
        const row = el('div', 'row', '');
        row.style.justifyContent = 'center';
        if (s.skip) {
            const sk = el('button', 'btn ghost small', 'Skip');
            sk.onclick = () => { WheelMgr.stopListen(null); };
            row.appendChild(sk);
        }
        const c = el('button', 'btn ghost small', 'Cancel');
        c.onclick = () => { wizard = null; WheelMgr.stopListen(null); render(true); };
        row.appendChild(c);
        w.appendChild(row);
        return w;
    }

    function render(rerender) {
        const body = rerender ? root : el('div');
        if (!body) return el('div');
        body.innerHTML = '';
        root = body;
        body.appendChild(UIx.group('Devices', devices()));
        const p = profile();
        if (!p) {
            body.appendChild(el('div', 'note', 'Works with Logitech, Thrustmaster, Fanatec, Moza, Simagic, Xbox wheels and anything else Windows lists as a game controller. There is no force feedback in FiveM, but rumble works on devices that support it.'));
            return body;
        }

        const top = el('div', 'grid2');
        const en = switchField('Use this device', p, 'enabled', 'Turn on to drive with it. Keyboard / pad take over again when it goes idle.');
        const presetF = el('div', 'field', `<div class="field-top"><span>Preset</span></div>`);
        const sel = el('select', 'text-in');
        Object.entries(WHEEL_PRESETS).forEach(([k, v]) => { const o = el('option', '', esc(v.label)); o.value = k; if (k === p.preset) o.selected = true; sel.appendChild(o); });
        sel.onchange = () => { WheelMgr.applyPreset(p, sel.value); save(); render(true); };
        presetF.appendChild(sel);
        top.append(en, presetF);
        body.appendChild(UIx.group('Setup', top));
        const pre = WHEEL_PRESETS[p.preset];
        if (pre && pre.note) body.appendChild(el('div', 'note', esc(pre.note)));

        if (wizard !== null) body.appendChild(UIx.group(null, wizardEl()));
        else {
            const wb = el('button', 'btn', 'Run setup wizard');
            wb.onclick = () => runWizard(0);
            const test = el('button', 'btn ghost', 'Test rumble');
            test.onclick = () => WheelMgr.rumble({ strong: .8, weak: .6, duration: 300 });
            const row = el('div', 'row'); row.append(wb, test);
            body.appendChild(UIx.group(null, row));
        }
        body.appendChild(promptEl());
        body.appendChild(UIx.group('Live', liveBlock()));

        body.appendChild(UIx.group('Steering', axisRow('Steering', 'steer', 'steer'), el('div', '', ''),
            UIx.grid(3,
                numField('Wheel rotation', p.steer, 'rotation', 1, 1440, 1, v => `${Math.round(v)}°`),
                numField('Steering lock used', p.steer, 'softLock', 1, 1440, 1, v => `${Math.round(v)}°`),
                numField('Sensitivity', p.steer, 'sensitivity', .5, 2, .05, v => `${v.toFixed(2)}x`),
                numField('Deadzone', p.steer, 'deadzone', 0, .2, .005, v => `${Math.round(v * 100)}%`),
                numField('Curve', p.steer, 'gamma', .5, 3, .05, v => v.toFixed(2)),
                switchField('Invert', p.steer, 'invert'))));
        body.appendChild(el('div', 'note', 'Wheel rotation is what your wheel is set to in its driver. Steering lock used is how far you turn for full lock in game (lower = quicker steering).'));

        const pedalsG = UIx.group('Pedals');
        [['Throttle', 'throttle'], ['Brake', 'brake'], ['Clutch', 'clutch']].forEach(([label, key]) => {
            pedalsG.appendChild(axisRow(label, key, 'pedal'));
            pedalsG.appendChild(UIx.grid(2,
                numField(`${label} deadzone`, p[key], 'deadzone', 0, .3, .005, v => `${Math.round(v * 100)}%`),
                numField(`${label} curve`, p[key], 'gamma', .5, 3, .05, v => v.toFixed(2))));
        });
        body.appendChild(pedalsG);

        body.appendChild(UIx.group('Buttons & shifter', buttons()));
        body.appendChild(el('div', 'note', 'Click a slot then press the button. Right-click a slot to clear it. Map Gear 1-7 + Reverse for an H-shifter and pick H-Pattern in Driving.'));
        body.appendChild(UIx.group('Extras', UIx.grid(2, switchField('Rumble', p, 'rumble', 'Crashes and insane near misses'))));

        const del = el('button', 'btn ghost', 'Forget this device');
        del.onclick = () => { delete WheelMgr.profiles()[selected]; save(); render(true); };
        body.appendChild(UIx.group(null, del));
        return body;
    }

    let lastPadCount = -1;
    function live(gp, o) {
        if (!root || !State.menuOpen || State.menuTab !== 'wheel') return;
        const count = WheelMgr.pads().length;
        if (count !== lastPadCount) { lastPadCount = count; if (!WheelMgr.listening() && wizard === null) render(true); return; }
        const show = gp || (selected && WheelMgr.padById(selected));
        if (!refs.wheel || !show) return;
        const p = profile();
        if (!o) {
            // device not enabled: preview raw steering so mapping can still be tested
            const raw = WheelMgr.read(show, p?.steer?.src) - (p?.steer?.center || 0);
            o = { s: clamp((p?.steer?.invert ? -raw : raw), -1, 1), t: 0, b: 0, c: 0, gear: 0 };
        }
        const rot = p ? p.steer.rotation : 900;
        refs.wheel.style.transform = `rotate(${o.s * Math.min(rot, Math.max(1, p.steer.softLock)) / 2}deg)`;
        refs.t.style.height = `${o.t * 100}%`;
        refs.b.style.height = `${o.b * 100}%`;
        refs.c.style.height = `${o.c * 100}%`;
        refs.gear.textContent = o.gear === -1 ? 'R' : o.gear || 'N';
        refs.steer.textContent = `${Math.round(o.s * 100)}%`;
        refs.raw.innerHTML = show.axes.map((v, i) => `<span>A${i} ${v.toFixed(2)}</span>`).join('')
            + show.buttons.map((b, i) => (b.pressed || b.value > .05) ? `<span style="color:var(--accent)">B${i} ${b.value.toFixed(2)}</span>` : '').join('');
        if (p) $$('.btn-map', root).forEach(b => {
            const idx = p.buttons[b.dataset.action];
            const bt = idx !== undefined && idx !== null ? show.buttons[idx] : null;
            b.classList.toggle('lit', !!(bt && bt.pressed));
        });
    }

    return {
        render() { root = null; lastPadCount = WheelMgr.pads().length; const r = render(false); return r; },
        live, prompt,
        onHide() { if (wizard !== null || WheelMgr.listening()) { wizard = null; WheelMgr.stopListen(null); } },
        cancelListen() {
            if (wizard !== null || WheelMgr.listening()) { wizard = null; WheelMgr.stopListen(null); render(true); return true; }
            return false;
        },
    };
})();
window.WheelUI = WheelUI;

window.addEventListener('gamepadconnected', () => { if (State.menuOpen && State.menuTab === 'wheel') Menu.renderTab(); });
window.addEventListener('gamepaddisconnected', () => { if (State.menuOpen && State.menuTab === 'wheel') Menu.renderTab(); });
