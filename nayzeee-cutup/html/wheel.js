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
    cammus: { label: 'Cammus C5 / C12', rotation: 900, softLock: 540 },
    pxn: { label: 'PXN V9 / V10 / V12', rotation: 900, softLock: 540 },
    hori: { label: 'Hori Racing Wheel / Apex', rotation: 270, softLock: 270 },
    tmx: { label: 'Thrustmaster T80 / T128 / TMX', rotation: 900, softLock: 540 },
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

    // A control can live on another USB device (pedals, shifter, handbrake): src.dev is that device's id
    function devFor(main, dev) { return dev && (!main || dev !== main.id) ? padById(dev) : main; }

    function read(gp, src) {
        if (!src) return 0;
        gp = devFor(gp, src.dev);
        if (!gp) return 0;
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

    // bind = button index on the main device (old profiles) or { dev, index }
    function pressed(gp, bind) {
        if (bind === undefined || bind === null) return false;
        const dev = typeof bind === 'object' ? devFor(gp, bind.dev) : gp;
        const b = dev ? dev.buttons[typeof bind === 'object' ? bind.index : bind] : null;
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

    // kind: 'steer' | 'pedal' | 'button'. Listens on every connected device, not just the selected one.
    function startListen(gpId, kind, done) {
        const list = pads();
        if (!list.length) return false;
        const base = {};
        list.forEach(gp => { base[gp.id] = snapshot(gp); });
        listener = { gpId, kind, done, base, phase: 'press', best: null, stableSince: 0, started: performance.now() };
        return true;
    }

    function stopListen(result) {
        const l = listener;
        listener = null;
        if (l && l.done) l.done(result);
    }

    function listen() {
        const l = listener;
        if (performance.now() - l.started > 15000) return stopListen(null);
        const now = performance.now();
        const list = pads().filter(gp => l.base[gp.id]);
        if (!list.length) return stopListen(null);

        if (l.kind === 'button') {
            for (const gp of list) {
                const base = l.base[gp.id];
                for (let i = 0; i < gp.buttons.length; i++) {
                    if (gp.buttons[i].pressed && !base.buttons[i]?.p) return stopListen({ dev: gp.id, index: i });
                }
            }
            return;
        }

        if (l.phase === 'press') {
            let best = null;
            for (const gp of list) {
                const base = l.base[gp.id];
                gp.axes.forEach((v, i) => {
                    const d = v - (base.axes[i] ?? 0);
                    if (!best || Math.abs(d) > Math.abs(best.d)) best = { dev: gp.id, type: 'axis', index: i, d, v, center: base.axes[i] ?? 0 };
                });
                if (l.kind === 'pedal') {
                    gp.buttons.forEach((b, i) => {
                        const d = b.value - (base.buttons[i]?.v ?? 0);
                        if (Math.abs(d) > Math.abs(best?.d || 0) && b.value > 0 && b.value < 1.01) best = { dev: gp.id, type: 'button', index: i, d, v: b.value };
                    });
                }
            }
            if (best && Math.abs(best.d) > .45) {
                const same = l.best && l.best.dev === best.dev && l.best.type === best.type && l.best.index === best.index;
                if (!same) { l.best = best; l.stableSince = now; }
                if (Math.abs(best.v) > Math.abs(l.best.v)) l.best.v = best.v;
                if (now - l.stableSince > 350) {
                    const src = { dev: best.dev, type: best.type, index: best.index };
                    if (l.kind === 'steer') return stopListen({ src, center: best.center || 0, invert: best.d < 0 });
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
        const src = { dev: l.best.dev, type: l.best.type, index: l.best.index };
        const v = read(null, src);
        if (Math.abs(v - l.full) > .5) {
            if (!l.restSince) l.restSince = now;
            if (now - l.restSince > 400) return stopListen({ src, rest: v, full: l.full });
        } else {
            l.restSince = 0;
        }
    }

    // every device the main profile reads from (wheel + linked pedals / shifter / handbrake)
    function linkedDevices(p) {
        const set = new Set();
        if (!p) return set;
        [p.steer, p.throttle, p.brake, p.clutch].forEach(c => { if (c && c.src && c.src.dev) set.add(c.src.dev); });
        Object.values(p.buttons || {}).forEach(b => { if (b && typeof b === 'object' && b.dev) set.add(b.dev); });
        set.delete(p.id);
        return set;
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
        pads, padById, blank, applyPreset, read, pressed, startListen, stopListen, linkedDevices,
        main: () => activeProfile()[1],
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

/* ============================== WHEEL TAB (NayZeee UI) ============================== */
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

    const shortName = id => (id || '').replace(/\s*\(.*?\)\s*/g, ' ').trim().split(' ').slice(0, 3).join(' ') || 'Device';
    const onOther = dev => dev && dev !== selected;
    const srcLabel = s => {
        if (!s) return 'Not set';
        const what = s.type === 'axis' ? `Axis ${s.index}` : `Button ${s.index} · analog`;
        return onOther(s.dev) ? `${shortName(s.dev)} · ${what}` : what;
    };
    const bindLabel = b => {
        if (b === undefined || b === null) return null;
        if (typeof b === 'object') return onOther(b.dev) ? `${shortName(b.dev)} · B${b.index}` : `B${b.index}`;
        return `B${b}`;
    };
    const save = () => WheelMgr.save();
    const objSlider = (label, obj, key, min, max, step, format, desc) =>
        UIx.slider({ label, desc, get: () => obj[key], set: v => { obj[key] = v; }, min, max, step, format, onCommit: save });
    const objToggle = (label, obj, key, desc) =>
        UIx.toggle({ label, desc, get: () => obj[key], set: v => {
            obj[key] = v;
            // only one main device drives; pedals / shifters on other USB devices are linked to it
            if (key === 'enabled' && v) Object.values(WheelMgr.profiles()).forEach(o => { if (o && o !== obj) o.enabled = false; });
            save();
            if (key === 'enabled') { Menu.side(); render(true); }
        } });

    function devices() {
        const list = WheelMgr.pads();
        if (!list.length) {
            return el('div', 'empty', `${ICONS.wheel}<b>No wheel found</b><span>Plug it in, then turn the wheel or press any button so Windows wakes it up. This page checks again on its own.</span>`);
        }
        if (!selected || !WheelMgr.padById(selected)) selected = list[0].id;
        const box = el('div', 'p-body');
        box.style.padding = '0';
        const main = WheelMgr.main();
        const linked = WheelMgr.linkedDevices(main);
        list.forEach(gp => {
            const p = WheelMgr.profiles()[gp.id];
            const isMain = p && p.enabled, isLinked = !isMain && linked.has(gp.id);
            const r = el('div', `row${gp.id === selected ? ' sel' : ''}`, `<div class="av">${ICONS.wheel}</div>
                <div class="row-txt"><b>${esc(gp.id.replace(/\s*\(.*?\)\s*/g, ' ').trim() || gp.id)}</b><span>${gp.axes.length} axes · ${gp.buttons.length} buttons · ${gp.mapping === 'standard' ? 'XInput' : 'DirectInput'}</span></div>
                <span class="tag ${isMain ? 'live' : isLinked ? 'hot' : 'off'}">${isMain ? 'Main' : isLinked ? 'Linked' : 'Off'}</span>`);
            r.style.cursor = 'pointer';
            r.onclick = () => { selected = gp.id; render(true); };
            box.appendChild(r);
        });
        return box;
    }

    function liveBlock() {
        const box = el('div', 'panel');
        box.innerHTML = `<div class="p-head"><div><h2>Live input</h2><p>Turn the wheel and press the pedals to check the mapping</p></div><span class="tag live" id="wl-tag">Reading</span></div>
            <div class="wheel-live">
                <svg class="wheel-svg" viewBox="0 0 100 100" id="wl-wheel"><circle cx="50" cy="50" r="44" stroke-width="7"/><circle cx="50" cy="50" r="9" stroke-width="4"/>
                    <path d="M6 50h35M59 50h35M50 59v35" stroke-width="5"/><path class="mark-l" d="M50 6v9"/></svg>
                <div>
                    <div class="live-read">
                        <div class="pedals">
                            <div class="pedal c"><div class="bar"><i id="wl-c"></i></div>CLU</div>
                            <div class="pedal b"><div class="bar"><i id="wl-b"></i></div>BRK</div>
                            <div class="pedal t"><div class="bar"><i id="wl-t"></i></div>THR</div>
                        </div>
                        <div class="stat-txt"><span>Gear</span><b id="wl-gear">N</b></div>
                        <div class="stat-txt"><span>Steering</span><b id="wl-steer">0%</b></div>
                    </div>
                    <div class="raw" id="wl-raw"></div>
                </div>
            </div>`;
        refs = { wheel: $('#wl-wheel', box), t: $('#wl-t', box), b: $('#wl-b', box), c: $('#wl-c', box), gear: $('#wl-gear', box), steer: $('#wl-steer', box), raw: $('#wl-raw', box) };
        return box;
    }

    function axisRow(label, key, kind) {
        const c = profile()[key];
        const r = el('div', 'row', `<div class="row-txt"><b>${label}</b><span>${kind === 'steer' ? 'Turn right when asked' : 'Press fully, then let go. Works on any connected device.'}</span></div>
            <span class="chip ${c.src ? (onOther(c.src.dev) ? 'hot' : '') : 'off'}">${esc(srcLabel(c.src))}</span><div class="acts"></div>`);
        const det = UIx.btn('btn-ghost', 'Detect', null, () => {
            det.classList.add('listening');
            prompt(kind === 'steer' ? 'Turn the wheel to the RIGHT and hold it' : `Press the ${label.toUpperCase()} all the way down`);
            WheelMgr.startListen(selected, kind, res => {
                prompt(null);
                if (res) { if (res.src && res.src.dev === selected) delete res.src.dev; Object.assign(c, res); save(); }
                render(true);
            });
        });
        $('.acts', r).appendChild(det);
        if (key !== 'steer') $('.acts', r).appendChild(UIx.btn('btn-ghost danger', 'Clear', null, () => { c.src = null; save(); render(true); }));
        return r;
    }

    function buttons() {
        const p = profile();
        const grid = el('div', 'bmap');
        BUTTON_ACTIONS.forEach(([action, label]) => {
            const lbl = bindLabel(p.buttons[action]);
            const b = el('div', 'row', `<div class="row-txt"><b>${label}</b></div><span class="chip ${lbl ? '' : 'off'}">${esc(lbl || 'None')}</span>`);
            b.dataset.action = action;
            b.onclick = () => {
                if (WheelMgr.listening()) return;
                b.classList.add('listening');
                prompt(`Press the button for ${label.toUpperCase()}`);
                WheelMgr.startListen(selected, 'button', res => {
                    prompt(null);
                    if (res) { p.buttons[action] = res.dev === selected ? res.index : { dev: res.dev, index: res.index }; save(); }
                    render(true);
                });
            };
            b.oncontextmenu = e => { e.preventDefault(); p.buttons[action] = null; save(); render(true); };
            grid.appendChild(b);
        });
        return grid;
    }

    function promptEl() {
        const p = el('div', 'inc hidden', `<div class="inc-top"><span class="chip">LISTENING</span><span class="ref" style="font-size:10.5px;color:var(--nz-ink-3)">Esc to cancel</span></div><h3></h3><p>Waiting for your wheel...</p>`);
        p.id = 'wl-prompt';
        return p;
    }

    function prompt(text) {
        const p = root && $('#wl-prompt', root);
        if (!p) return;
        p.classList.toggle('hidden', !text);
        if (text) $('h3', p).textContent = text;
    }

    const WIZARD = [
        { key: 'steer', kind: 'steer', text: 'Turn the wheel to the RIGHT and hold it' },
        { key: 'throttle', kind: 'pedal', text: 'Press the THROTTLE all the way down' },
        { key: 'brake', kind: 'pedal', text: 'Press the BRAKE all the way down' },
        { key: 'clutch', kind: 'pedal', text: 'Press the CLUTCH all the way down', skip: true },
        { key: 'shiftUp', kind: 'button', text: 'Pull the paddle or button for SHIFT UP', skip: true },
        { key: 'shiftDown', kind: 'button', text: 'Pull the paddle or button for SHIFT DOWN', skip: true },
    ];

    function runWizard(step = 0) {
        const p = profile();
        if (step >= WIZARD.length) { wizard = null; p.enabled = true; save(); render(true); Menu.side(); return; }
        wizard = step;
        render(true);
        const s = WIZARD[step];
        WheelMgr.startListen(selected, s.kind, res => {
            if (wizard === null) return;
            if (res) {
                if (s.kind === 'button') p.buttons[s.key] = res.dev === selected ? res.index : { dev: res.dev, index: res.index };
                else { if (res.src && res.src.dev === selected) delete res.src.dev; Object.assign(p[s.key], res); }
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
        const w = el('div', 'modal', `<div class="modal-b"><div class="tile">${ICONS.wheel}</div><div style="flex:1">
            <div class="wizard-steps">${WIZARD.map((_, i) => `<i class="${i < wizard ? 'done' : i === wizard ? 'cur' : ''}"></i>`).join('')}</div>
            <h4>${esc(s.text)}</h4><p>Step ${wizard + 1} of ${WIZARD.length}. Pedals: press fully, then let go so the resting point is saved too.</p></div></div><div class="modal-f"></div>`);
        const f = $('.modal-f', w);
        if (s.skip) f.appendChild(UIx.btn('btn-line', "I don't have one", null, () => WheelMgr.stopListen(null)));
        f.appendChild(UIx.btn('btn-red', 'Cancel', null, () => { wizard = null; WheelMgr.stopListen(null); render(true); }));
        return w;
    }

    function render(rerender) {
        const body = rerender ? root : el('div');
        if (!body) return el('div');
        body.innerHTML = '';
        root = body;
        body.appendChild(UIx.sec('Devices', 'Pick your wheel as the main device. Pedals, a shifter or a handbrake on their own USB link to it on their own: just hit Detect or run the wizard and use them.', devices()));
        const p = profile();
        if (!p) {
            body.appendChild(UIx.sec('Supported', null, el('div', 'inc', `<h3>Any wheel Windows can see</h3><p>Logitech, Thrustmaster, Fanatec, Moza, Simagic, Cammus, PXN, Xbox wheels and pads.
                No force feedback in FiveM, but rumble works on devices that support it.</p>`)));
            return body;
        }
        const presetSel = el('select', 'nz-input');
        presetSel.style.width = '300px';
        Object.entries(WHEEL_PRESETS).forEach(([k, v]) => { const o = el('option', '', esc(v.label)); o.value = k; if (k === p.preset) o.selected = true; presetSel.appendChild(o); });
        presetSel.onchange = () => { WheelMgr.applyPreset(p, presetSel.value); save(); render(true); };
        const setup = UIx.sec('Setup', null,
            objToggle('Main device', p, 'enabled', 'Drive with this one. Keyboard or pad takes over again when it goes idle.'),
            UIx.opt('Preset', 'Sets the rotation, and the mapping for Xbox wheels and pads', presetSel));
        const pre = WHEEL_PRESETS[p.preset];
        if (pre && pre.note) setup.appendChild(el('div', 'inc', `<h3>${esc(pre.label)}</h3><p>${esc(pre.note)}</p>`));
        const acts = el('div', 'actions');
        if (wizard === null) {
            acts.append(UIx.btn('btn-teal', 'Run setup wizard', 'bolt', () => runWizard(0)),
                UIx.btn('btn-line', 'Test rumble', null, () => WheelMgr.rumble({ strong: .8, weak: .6, duration: 300 })));
            setup.appendChild(acts);
        } else {
            setup.appendChild(wizardEl());
        }
        body.appendChild(setup);
        body.appendChild(promptEl());
        body.appendChild(liveBlock());

        const deg = v => `${Math.round(v)}°`, pct = v => `${Math.round(v * 100)}%`;
        body.appendChild(UIx.sec('Steering', 'Rotation is what your wheel is set to in its own driver. Lock used is how far you turn for full lock in game: lower is quicker.',
            axisRow('Steering', 'steer', 'steer'),
            UIx.grid(2,
                objSlider('Wheel rotation', p.steer, 'rotation', 1, 1440, 1, deg),
                objSlider('Steering lock used', p.steer, 'softLock', 1, 1440, 1, deg),
                objSlider('Sensitivity', p.steer, 'sensitivity', .5, 2, .05, v => `${v.toFixed(2)}x`),
                objSlider('Deadzone', p.steer, 'deadzone', 0, .2, .005, pct),
                objSlider('Curve', p.steer, 'gamma', .5, 3, .05, v => v.toFixed(2), 'Above 1 = finer control near centre'),
                objToggle('Invert', p.steer, 'invert'))));

        const ped = UIx.sec('Pedals', null);
        [['Throttle', 'throttle'], ['Brake', 'brake'], ['Clutch', 'clutch']].forEach(([label, key]) => {
            ped.appendChild(axisRow(label, key, 'pedal'));
            ped.appendChild(UIx.grid(2,
                objSlider(`${label} deadzone`, p[key], 'deadzone', 0, .3, .005, pct),
                objSlider(`${label} curve`, p[key], 'gamma', .5, 3, .05, v => v.toFixed(2))));
        });
        body.appendChild(ped);
        body.appendChild(UIx.sec('Buttons & shifter', 'Click a slot, then press the button. Right-click clears it. Map Gear 1-7 and Reverse for an H-shifter, then pick H-Pattern in Driving.', buttons()));
        const fin = el('div', 'actions');
        fin.appendChild(UIx.btn('btn-red', 'Forget this device', 'reset', () => { delete WheelMgr.profiles()[selected]; save(); render(true); Menu.side(); }));
        body.appendChild(UIx.sec('Extras', null, objToggle('Rumble', p, 'rumble', 'Crashes and insane near misses'), fin));
        return body;
    }

    let lastPadCount = -1;
    function live(gp, o) {
        if (!root || !State.menuOpen || State.menuTab !== 'wheel') return;
        const count = WheelMgr.pads().length;
        if (count !== lastPadCount) { lastPadCount = count; if (!WheelMgr.listening() && wizard === null) render(true); return; }
        const show = gp || (selected && WheelMgr.padById(selected));
        const p = profile();
        if (!refs.wheel || !show || !p) return;
        if (!o) {
            const raw = WheelMgr.read(show, p.steer.src) - (p.steer.center || 0);
            o = { s: clamp(p.steer.invert ? -raw : raw, -1, 1), t: 0, b: 0, c: 0, gear: 0 };
            // preview linked pedals even before the device is switched on
            const ped = c => { if (!c || !c.src) return 0; const span = c.full - c.rest; return Math.abs(span) < .05 ? 0 : clamp((WheelMgr.read(show, c.src) - c.rest) / span, 0, 1); };
            o.t = ped(p.throttle); o.b = ped(p.brake); o.c = ped(p.clutch);
        }
        refs.wheel.style.transform = `rotate(${o.s * Math.min(p.steer.rotation, Math.max(1, p.steer.softLock)) / 2}deg)`;
        refs.t.style.height = `${o.t * 100}%`;
        refs.b.style.height = `${o.b * 100}%`;
        refs.c.style.height = `${o.c * 100}%`;
        refs.gear.textContent = o.gear === -1 ? 'R' : o.gear || 'N';
        refs.steer.textContent = `${Math.round(o.s * 100)}%`;
        refs.raw.innerHTML = show.axes.map((v, i) => `<span>A${i} ${v.toFixed(2)}</span>`).join('')
            + show.buttons.map((b, i) => (b.pressed || b.value > .05) ? `<span class="hot">B${i} ${b.value.toFixed(2)}</span>` : '').join('');
        $$('.bmap .row', root).forEach(b => b.classList.toggle('lit', WheelMgr.pressed(show, p.buttons[b.dataset.action])));
    }

    return {
        render() { root = null; lastPadCount = WheelMgr.pads().length; return render(false); },
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
