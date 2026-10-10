/* Browser preview of the NUI (only loaded outside FiveM). Open web/index.html#<view> through any
   static server: #hud #text #dialogue #ix #pack #mix #rack #give #place #levelup #all */
(function () {
    const s = document.createElement('script');
    s.src = 'preview-data.js';
    s.onload = start;
    document.body.appendChild(s);

    const send = (action, data) => window.postMessage({ action, data }, '*');
    const STOCK = [
        { pid: 'ogkush', q: 2, n: 14, name: 'OG Kush', base: 'ogkush', effects: ['calming'] },
        { pid: 'mxk2', q: 3, n: 6, name: 'Blue Cheese Kush', base: 'ogkush', effects: ['calming', 'energizing', 'sneaky'] },
        { pid: 'meth', q: 2, n: 10, name: 'Meth', base: 'meth', effects: [] },
    ];
    const LOOSE = STOCK.map((x) => Object.assign({ item: x.base === 'meth' ? 'nz_meth' : 'nz_weed', kind: x.base === 'meth' ? 'meth' : 'weed' }, x));

    window.Mock = {
        handle(name, data) {
            if (name === 'mix:go') return { product: { name: 'Ghost Haze', value: 61 }, first: true, panel: null };
            if (name === 'rack:add' || name === 'rack:take') return null;
            return null;
        },
    };

    function start() {
        document.body.style.background = 'radial-gradient(1200px 700px at 60% 30%, #4b3b5c, #1a1420 60%, #0b0a0e)';
        send('init', window.PREVIEW_CFG);
        const view = (location.hash || '#all').slice(1);
        const V = {
            hud() {
                send('hud', { quest: { title: 'Getting Started', text: 'Pour soil into the pot' }, deals: [
                    { title: 'Deal for Andy', text: '2x OG Kush, Behind the gas station', exp: Date.now() / 1000 + 610 },
                    { title: 'Deal for Doug', text: '2x OG Kush, Blue house', exp: Date.now() / 1000 + 95 },
                    { title: 'Sample for Chelsey', text: "Near the doctor's office", sample: true }] });
                send('notify', { title: 'Deal done', text: 'Andy paid $76', kind: 'success' });
                send('notify', { text: 'The watering can is empty. Fill it at the tap.', kind: 'error' });
                send('sms', { from: 'Doug', text: "Need 3x OG Kush. Meet me blue house? $114 cash." });
            },
            text() {
                send('text', { from: '(555) 0194', lines: ["Hey. Word is you're broke and not too picky about work.", "I can fix the first part. Come see me, I'll send you a pin. Come alone."], timeout: 40 });
            },
            dialogue() {
                send('dialogue', { name: 'Uncle Benson', role: 'Unknown number', text: "Ah. You actually came. Most people ignore strange texts. Smart. Or desperate.", choices: ['Who are you?', 'You said something about money.'] });
            },
            ix() {
                send('ix', { text: 'Pour soil into pot', pct: 42, keys: [{ key: 'Mouse', label: 'Move' }, { key: 'LMB', label: 'Use' }, { key: 'A D', label: 'Rotate view' }, { key: 'Esc', label: 'Exit' }] });
            },
            pack() { send('panel', { type: 'pack', data: { stacks: LOOSE, baggies: 18, jars: 4 } }); },
            mix() {
                send('panel', { type: 'mix', data: { stacks: LOOSE, max: 10, ingredients: [
                    { item: 'nz_cuke', label: 'Cuke', effect: 'energizing', n: 6 }, { item: 'nz_banana', label: 'Banana', effect: 'gingeritis', n: 3 },
                    { item: 'nz_paracetamol', label: 'Paracetamol', effect: 'sneaky', n: 10 }] } });
            },
            rack() {
                const now = Date.now() / 1000;
                send('panel', { type: 'rack', data: { stacks: LOOSE.slice(0, 2), leaves: 12, capacity: 20, now, slots: [{ kind: 'weed', n: 6, done: now + 260 }, { kind: 'coca', n: 8, done: now - 5 }] } });
            },
            give() {
                send('panel', { type: 'give', data: { mode: 'sample', name: 'Chelsey', standards: 2, favorites: ['calming', 'focused', 'gingeritis'], stock: STOCK } });
            },
            place() {
                send('panel', { type: 'place', data: { items: [
                    { item: 'nz_pot', label: 'Plastic Pot', icon: 'pot', n: 2 }, { item: 'nz_tent', label: 'Grow Tent', icon: 'tent', n: 1 },
                    { item: 'nz_packer', label: 'Packaging Station', icon: 'box', n: 1 }, { item: 'nz_chem', label: 'Chemistry Station', icon: 'beaker', n: 1, locked: true, rank: 'Hoodlum III' }] } });
            },
            levelup() { send('levelup', { rank: 'Street Rat III', unlocks: ['Mixing Station', 'Sour Diesel'] }); send('xp', { amount: 34, why: 'Deal' }); },
        };
        if (view === 'all') { V.hud(); V.ix(); } else if (V[view]) V[view]();
    }
})();
