/* Minigames. Each one renders into #minigame, owns its listeners/loops while open and
   calls done(true|false) exactly once. Nothing runs when no minigame is open. */
(function () {
    const root = () => document.getElementById('minigame');
    let current = null;
    const T = (k, f) => (window.UIStrings && window.UIStrings[k]) || f;
    const rand = (a, b) => Math.floor(Math.random() * (b - a + 1)) + a;
    const pick = (arr) => arr[rand(0, arr.length - 1)];

    function frame(title, icon, hint, body) {
        root().innerHTML = `
            <div class="mg">
                <div class="mg-head">${Icons.svg(icon)}<h3>${title}</h3><span class="t" id="mg-t"></span></div>
                <div class="mg-hint">${hint}</div>
                <div class="mg-timer"><div id="mg-bar" style="width:100%"></div></div>
                <div id="mg-body">${body}</div>
            </div>`;
        root().classList.remove('hidden');
    }

    /** shared lifecycle: timer bar, key handler, cleanup, result flash */
    function session(seconds, onKey) {
        const s = { finished: false, raf: 0, timers: [], keys: onKey };
        const start = performance.now();
        const total = seconds * 1000;
        const bar = document.getElementById('mg-bar');
        const label = document.getElementById('mg-t');
        const tick = (now) => {
            if (s.finished) return;
            const left = Math.max(0, total - (now - start));
            if (bar) bar.style.width = (left / total * 100) + '%';
            if (label) label.textContent = (left / 1000).toFixed(1) + 's';
            if (left <= 0) return s.end(false);
            if (s.onFrame) s.onFrame(now);
            s.raf = requestAnimationFrame(tick);
        };
        s.raf = requestAnimationFrame(tick);
        s.keyHandler = (e) => { if (!s.finished && s.keys) s.keys(e); };
        s.keyUpHandler = (e) => { if (!s.finished && s.keyUp) s.keyUp(e); };
        window.addEventListener('keydown', s.keyHandler);
        window.addEventListener('keyup', s.keyUpHandler);
        s.later = (fn, ms) => s.timers.push(setTimeout(fn, ms));
        s.end = (ok) => {
            if (s.finished) return;
            s.finished = true;
            cancelAnimationFrame(s.raf);
            s.timers.forEach(clearTimeout);
            window.removeEventListener('keydown', s.keyHandler);
            window.removeEventListener('keyup', s.keyUpHandler);
            const body = document.getElementById('mg-body');
            if (body) body.innerHTML = `<div class="mg-status ${ok ? 'ok' : 'bad'}">${ok ? T('mg_success', 'Access granted') : T('mg_fail', 'Access denied')}</div>`;
            setTimeout(() => { root().classList.add('hidden'); root().innerHTML = ''; current = null; s.done(ok); }, 900);
        };
        return s;
    }

    function strikes(max, used) {
        let h = '';
        for (let i = 0; i < max; i++) h += `<i class="${i < used ? 'x' : ''}"></i>`;
        return `<div class="mg-strikes">${h}</div>`;
    }

    const games = {};

    /* ---------------------------------------------------------- keypad: memorise a code */
    games.keypad = (d, done) => {
        const len = 3 + d;
        const code = Array.from({ length: len }, () => rand(0, 9)).join('');
        let input = '';
        let showing = true;
        frame('Keypad', 'chip', T('mg_keypad', 'Memorise the code'), `
            <div class="kp-display" id="kp">${code}</div>
            <div class="kp-grid">${[1,2,3,4,5,6,7,8,9,'C',0,'OK'].map(k => `<button data-k="${k}">${k}</button>`).join('')}</div>`);
        const s = session(8 + len * 2, null);
        s.done = done;
        const disp = () => { document.getElementById('kp').textContent = input.padEnd(len, '_'); };
        s.later(() => { showing = false; disp(); }, 1400 + len * 260 - d * 150);
        const press = (k) => {
            if (showing) return;
            if (k === 'C') input = input.slice(0, -1);
            else if (k === 'OK') return s.end(input === code);
            else if (input.length < len) input += k;
            disp();
            if (input.length === len) s.later(() => s.end(input === code), 250);
        };
        s.keys = (e) => {
            if (/^[0-9]$/.test(e.key)) press(e.key);
            else if (e.key === 'Backspace') press('C');
            else if (e.key === 'Enter') press('OK');
        };
        root().querySelectorAll('[data-k]').forEach(b => b.onclick = () => press(String(b.dataset.k)));
        return s;
    };

    /* ---------------------------------------------------------- circuit: key sequence */
    games.circuit = (d, done) => {
        const pool = 'QWERASDF'.split('');
        const seq = Array.from({ length: 5 + d * 2 }, () => pick(pool));
        let i = 0;
        frame('Circuit', 'bolt', T('mg_circuit', 'Hit the keys in order'), `<div class="seq" id="seq"></div>`);
        const render = () => {
            document.getElementById('seq').innerHTML = seq.map((k, n) => `<span class="${n < i ? 'done' : n === i ? 'cur' : ''}">${k}</span>`).join('');
        };
        render();
        const s = session(4 + seq.length * (1.1 - d * 0.15), (e) => {
            const k = e.key.toUpperCase();
            if (k.length !== 1 || !/[A-Z]/.test(k)) return;
            if (k === seq[i]) { i++; render(); if (i >= seq.length) s.end(true); }
            else s.end(false);
        });
        s.done = done;
        return s;
    };

    /* ---------------------------------------------------------- typing: type the words */
    const WORDS = ['vault', 'breach', 'cipher', 'kernel', 'proxy', 'tunnel', 'bypass', 'socket', 'shadow', 'payload', 'firewall', 'decrypt', 'override', 'gateway', 'exploit', 'binary', 'trace', 'phantom', 'circuit', 'quantum'];
    games.typing = (d, done) => {
        const words = Array.from({ length: 2 + d }, () => pick(WORDS));
        const target = words.join(' ');
        let typed = '';
        frame('Type breaker', 'chip', T('mg_typing', 'Type the words'), `<div class="typing-words" id="tw"></div><div class="typing-input" id="ti">_</div>`);
        const render = () => {
            let h = '';
            for (let n = 0; n < target.length; n++) {
                const c = target[n] === ' ' ? '&nbsp;' : target[n];
                if (n < typed.length) h += `<span class="${typed[n] === target[n] ? 'ok' : 'bad'}">${c}</span>`;
                else h += `<span class="rest">${c}</span>`;
            }
            document.getElementById('tw').innerHTML = h;
            document.getElementById('ti').textContent = typed + '_';
        };
        render();
        const s = session(target.length * (0.62 - d * 0.08) + 3, (e) => {
            if (e.key === 'Backspace') typed = typed.slice(0, -1);
            else if (e.key.length === 1) typed += e.key.toLowerCase();
            else return;
            render();
            if (typed.length >= target.length) s.end(typed === target);
        });
        s.done = done;
        return s;
    };

    /* ---------------------------------------------------------- safecrack: dial + clicks */
    games.safecrack = (d, done) => {
        const combo = Array.from({ length: 2 + d }, () => rand(0, 99));
        let pos = 0, idx = 0, fails = 0;
        const maxFails = 3;
        let ticks = '';
        for (let n = 0; n < 100; n += 2) ticks += `<span class="${n % 10 === 0 ? 'big' : ''}" style="transform:rotate(${n * 3.6}deg)"></span>`;
        frame('Safe', 'vault', T('mg_safecrack', 'Turn the dial with A / D, Space to lock in'), `
            <div class="dial-wrap"><div class="dial"><div class="face" id="face">${ticks}</div><div class="needle"></div><div class="num" id="num">00</div><div class="ping" id="ping"></div></div></div>
            <div class="locks" id="locks"></div><div id="strk"></div>`);
        const render = () => {
            document.getElementById('face').style.transform = `rotate(${-pos * 3.6}deg)`;
            document.getElementById('num').textContent = String(pos).padStart(2, '0');
            const dist = Math.min(Math.abs(pos - combo[idx]), 100 - Math.abs(pos - combo[idx]));
            document.getElementById('ping').classList.toggle('on', dist <= (3 - d) );
            document.getElementById('locks').innerHTML = combo.map((_, n) => `<i class="${n < idx ? 'on' : ''}">${n < idx ? '✓' : ''}</i>`).join('');
            document.getElementById('strk').innerHTML = strikes(maxFails, fails);
        };
        render();
        const s = session(25 + combo.length * 6, (e) => {
            const k = e.key.toLowerCase();
            if (k === 'a' || k === 'arrowleft') pos = (pos + 99) % 100;
            else if (k === 'd' || k === 'arrowright') pos = (pos + 1) % 100;
            else if (k === ' ' || k === 'enter') {
                const dist = Math.min(Math.abs(pos - combo[idx]), 100 - Math.abs(pos - combo[idx]));
                if (dist <= (3 - d)) { idx++; if (idx >= combo.length) return s.end(true); }
                else { fails++; if (fails >= maxFails) return s.end(false); }
            } else return;
            render();
        });
        s.done = done;
        return s;
    };

    /* ---------------------------------------------------------- lockpick: timing ring */
    games.lockpick = (d, done) => {
        const needed = 2 + d;
        let hits = 0, fails = 0, angle = 0, zone = rand(40, 300), speed = 160 + d * 50, dir = 1;
        const zoneSize = 46 - d * 9;
        frame('Lockpick', 'lock', T('mg_lockpick', 'Press Space when the pick is in the zone'), `
            <div class="lp"><svg viewBox="0 0 220 220">
                <circle cx="110" cy="110" r="90" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="16"/>
                <path id="lp-zone" fill="none" stroke="var(--accent2)" stroke-width="16" stroke-linecap="round"/>
                <line id="lp-needle" x1="110" y1="110" x2="110" y2="18" stroke="#fff" stroke-width="4" stroke-linecap="round"/>
                <circle cx="110" cy="110" r="10" fill="var(--accent)"/>
            </svg></div><div class="mg-strikes" id="lp-pins"></div>`);
        const arc = (a0, a1) => {
            const p = (a) => [110 + 90 * Math.sin(a * Math.PI / 180), 110 - 90 * Math.cos(a * Math.PI / 180)];
            const [x0, y0] = p(a0), [x1, y1] = p(a1);
            return `M ${x0} ${y0} A 90 90 0 0 1 ${x1} ${y1}`;
        };
        const drawZone = () => document.getElementById('lp-zone').setAttribute('d', arc(zone, zone + zoneSize));
        const drawPins = () => {
            let h = '';
            for (let n = 0; n < needed; n++) h += `<i class="${n < hits ? '' : ''}" style="${n < hits ? 'background:var(--success);box-shadow:0 0 8px var(--success)' : ''}"></i>`;
            document.getElementById('lp-pins').innerHTML = h + '&nbsp;' + Array.from({ length: 2 }, (_, n) => `<i class="${n < fails ? 'x' : ''}"></i>`).join('');
        };
        drawZone(); drawPins();
        let last = performance.now();
        const s = session(22, (e) => {
            if (e.key !== ' ' && e.key !== 'Enter') return;
            const a = ((angle % 360) + 360) % 360;
            if (a >= zone && a <= zone + zoneSize) {
                hits++;
                if (hits >= needed) return s.end(true);
                zone = rand(20, 310); dir = -dir; speed += 25; drawZone();
            } else {
                fails++;
                if (fails >= 2) return s.end(false);
            }
            drawPins();
        });
        s.onFrame = (now) => {
            angle += dir * speed * (now - last) / 1000;
            last = now;
            document.getElementById('lp-needle').setAttribute('transform', `rotate(${angle} 110 110)`);
        };
        s.done = done;
        return s;
    };

    /* ---------------------------------------------------------- memory: thermite grid */
    games.memory = (d, done) => {
        const size = 4 + d;
        const count = 4 + d * 2;
        const cells = new Set();
        while (cells.size < count) cells.add(rand(0, size * size - 1));
        const found = new Set();
        let misses = 0, locked = true;
        frame('Thermite', 'fire', T('mg_memory', 'Repeat the pattern'), `
            <div class="mem-grid" id="mem" style="grid-template-columns:repeat(${size},1fr);width:${size * 62}px">
                ${Array.from({ length: size * size }, (_, n) => `<button data-i="${n}"></button>`).join('')}
            </div><div id="mstr"></div>`);
        const btns = [...root().querySelectorAll('#mem button')];
        cells.forEach(i => btns[i].classList.add('show'));
        document.getElementById('mstr').innerHTML = strikes(3, 0);
        const s = session(14 + count, null);
        s.done = done;
        s.later(() => { btns.forEach(b => b.classList.remove('show')); locked = false; }, 2200 - d * 300);
        btns.forEach(b => b.onclick = () => {
            if (locked || s.finished) return;
            const i = Number(b.dataset.i);
            if (found.has(i)) return;
            if (cells.has(i)) {
                found.add(i); b.classList.add('hit');
                if (found.size === cells.size) s.end(true);
            } else {
                b.classList.add('miss'); misses++;
                document.getElementById('mstr').innerHTML = strikes(3, misses);
                if (misses >= 3) s.end(false);
            }
        });
        return s;
    };

    /* ---------------------------------------------------------- drill: depth vs heat */
    games.drill = (d, done) => {
        let depth = 0, heat = 0, pushing = false;
        const hard = Array.from({ length: d + 1 }, () => { const a = rand(15, 80); return [a, a + rand(6, 10)]; });
        frame('Drill', 'target', T('mg_drill', "Hold W to push, release to cool. Don't overheat."), `
            <div class="drill">
                <div class="gauge"><div class="lbl">Depth <b id="dd">0%</b></div><div class="track"><div class="fill" id="df" style="width:0"></div></div></div>
                <div class="gauge heat"><div class="lbl">Heat <b id="dh">0%</b></div><div class="track"><div class="fill" id="dhf" style="width:0"></div></div></div>
                <div class="drill-bit">${hard.map(h => `<div class="hard" style="left:${h[0]}%;width:${h[1] - h[0]}%"></div>`).join('')}<div class="bit" id="bit" style="width:0"></div></div>
            </div>`);
        let last = performance.now();
        const s = session(40 + d * 5, (e) => { const k = e.key.toLowerCase(); if (k === 'w' || k === ' ' || k === 'arrowup') pushing = true; });
        s.keyUp = (e) => { const k = e.key.toLowerCase(); if (k === 'w' || k === ' ' || k === 'arrowup') pushing = false; };
        s.onFrame = (now) => {
            const dt = (now - last) / 1000; last = now;
            const inHard = hard.some(h => depth >= h[0] && depth <= h[1]);
            if (pushing) {
                depth += dt * (inHard ? 3 : 7.5);
                heat += dt * (inHard ? 34 + d * 6 : 15 + d * 4);
            } else {
                heat -= dt * 26;
            }
            heat = Math.max(0, heat); depth = Math.min(100, depth);
            document.getElementById('dd').textContent = Math.floor(depth) + '%';
            document.getElementById('dh').textContent = Math.floor(heat) + '%';
            document.getElementById('df').style.width = depth + '%';
            document.getElementById('dhf').style.width = Math.min(100, heat) + '%';
            document.getElementById('bit').style.width = depth + '%';
            if (heat >= 100) s.end(false);
            else if (depth >= 100) s.end(true);
        };
        s.done = done;
        return s;
    };

    /* ---------------------------------------------------------- datacrack: find the code */
    games.datacrack = (d, done) => {
        const hex = () => Math.floor(Math.random() * 65536).toString(16).toUpperCase().padStart(4, '0');
        const rounds = 1 + d;
        let round = 0, fails = 0, target, cells = [];
        frame('Data crack', 'chip', T('mg_datacrack', 'Find the code in the stream'), `<div class="dc-target" id="dct"></div><div class="dc-grid" id="dcg"></div><div id="dcs"></div>`);
        const build = () => {
            target = hex();
            cells = Array.from({ length: 42 }, hex);
            cells[rand(0, cells.length - 1)] = target;
            document.getElementById('dct').textContent = target;
            const g = document.getElementById('dcg');
            g.innerHTML = cells.map(c => `<button>${c}</button>`).join('');
            g.querySelectorAll('button').forEach(b => b.onclick = () => {
                if (s.finished) return;
                if (b.textContent === target) { round++; if (round >= rounds) return s.end(true); build(); }
                else { fails++; b.style.background = 'rgba(var(--danger-rgb),.4)'; if (fails >= 3) return s.end(false); }
                document.getElementById('dcs').innerHTML = strikes(3, fails);
            });
            document.getElementById('dcs').innerHTML = strikes(3, fails);
        };
        const s = session(12 + rounds * 7 - d * 2, null);
        s.done = done;
        build();
        // the stream shifts every so often
        let shiftAt = performance.now();
        s.onFrame = (now) => {
            if (now - shiftAt < 1700 - d * 250) return;
            shiftAt = now;
            const g = document.getElementById('dcg');
            if (!g) return;
            const btns = g.querySelectorAll('button');
            const first = cells.shift(); cells.push(first);
            btns.forEach((b, n) => { b.textContent = cells[n]; b.style.background = ''; });
        };
        return s;
    };

    window.Minigames = {
        start(type, difficulty, done) {
            if (current) current.end(false);
            const fn = games[type] || games.circuit;
            current = fn(Math.max(1, Math.min(3, difficulty || 2)), done);
        },
        cancel() { if (current) current.end(false); },
        active() { return current !== null; },
        types: Object.keys(games),
    };
})();
