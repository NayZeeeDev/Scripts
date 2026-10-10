/* Browser preview of every screen (not loaded in game). Open web/index.html#shop through any static server.
   #hud #text #dialogue #ix #choose #place #pack #dry #mix #press #shop #tablet #levelup */
(function () {
    const send = (action, data) => window.postMessage({ action, data }, '*');
    window.Mock = { handle: () => null };
    document.body.style.background = 'radial-gradient(ellipse at 30% 20%, #3b4a3f, #141a17 70%)';

    const effects = {
        calming: { label: 'Calming', mult: 0.1, color: '#fed09b' }, refreshing: { label: 'Refreshing', mult: 0.14, color: '#b2fe98' },
        energizing: { label: 'Energizing', mult: 0.22, color: '#9aef6e' }, sedating: { label: 'Sedating', mult: 0.26, color: '#6b5fd8' },
        gingeritis: { label: 'Gingeritis', mult: 0.2, color: '#fe8829' }, sneaky: { label: 'Sneaky', mult: 0.24, color: '#7b7b7b' },
        thought_provoking: { label: 'Thought-Provoking', mult: 0.44, color: '#fea0cb' }, athletic: { label: 'Athletic', mult: 0.32, color: '#75c8fd' },
    };
    const strains = { ogkush: { label: 'OG Kush', price: 40, bud: 'green' }, sourdiesel: { label: 'Sour Diesel', price: 46, bud: 'lime' }, gdp: { label: 'Granddaddy Purple', price: 58, bud: 'purple' } };
    const quality = [{ id: 0, label: 'Trash', color: '#e5484d' }, { id: 1, label: 'Poor', color: '#e5a50a' }, { id: 2, label: 'Standard', color: '#9ea5aa' }, { id: 3, label: 'Premium', color: '#58a6ff' }, { id: 4, label: 'Heavenly', color: '#e3b341' }];
    const ingredients = {
        nzw_ing_banana: { label: 'Banana', effect: 'gingeritis', rules: { calming: 'sneaky', energizing: 'thought_provoking' } },
        nzw_ing_energydrink: { label: 'Energy Drink', effect: 'athletic', rules: { sedating: 'munchies' } },
    };
    const items = { nzw_pot: 'Plastic Pot', nzw_soil: 'Potting Soil', nzw_wateringcan: 'Watering Can', nzw_trimmers: 'Trimmers', nzw_packstation: 'Packaging Station', nzw_baggie_empty: 'Empty Baggie' };
    const categories = [{ id: 'grow', label: 'Growing', icon: 'pot' }, { id: 'light', label: 'Lights', icon: 'bulb' }, { id: 'seed', label: 'Seeds', icon: 'seed' }, { id: 'proc', label: 'Processing', icon: 'box' }, { id: 'mix', label: 'Mixing', icon: 'flask' }];
    send('init', { ui: {}, effects, quality, items, ingredients, strains, maxEffects: 8, mixSeconds: 6, categories });

    const stacks = [
        { pid: 'ogkush', q: 2, n: 14, name: 'OG Kush', effects: ['calming'], base: 'ogkush', bud: 'green', value: 44 },
        { pid: 'ogkush', q: 3, n: 6, name: 'OG Kush', effects: ['calming'], base: 'ogkush', bud: 'green', value: 44 },
        { pid: 'gdp', q: 2, n: 22, name: 'Granddaddy Purple', effects: ['sedating'], base: 'gdp', bud: 'purple', value: 73 },
        { pid: 'mx1', q: 2, n: 5, name: 'Blue Cheese Kush', effects: ['refreshing', 'gingeritis'], base: 'sourdiesel', bud: 'lime', value: 61 },
    ];
    const shopItems = [
        ['nzw_pot', 'Plastic Pot', 60, 'grow', 0], ['nzw_soil', 'Potting Soil', 25, 'grow', 0], ['nzw_wateringcan', 'Watering Can', 40, 'grow', 0],
        ['nzw_trimmers', 'Trimmers', 30, 'grow', 0], ['nzw_fertilizer', 'Fertilizer', 45, 'grow', 0], ['nzw_speedgrow', 'Speed Growth', 70, 'grow', 2],
        ['nzw_growtent', 'Grow Tent', 1500, 'grow', 3], ['nzw_pgr', 'Plant Growth Regulator', 80, 'grow', 4], ['nzw_soil_premium', 'Premium Potting Soil', 90, 'grow', 6],
        ['nzw_rack', 'Suspension Rack', 450, 'light', 1], ['nzw_light_halogen', 'Halogen Grow Light', 350, 'light', 1], ['nzw_light_led', 'LED Grow Light', 1200, 'light', 5], ['nzw_light_fullspec', 'Full Spectrum Grow Light', 4200, 'light', 11],
    ].map(([item, label, price, cat, level]) => ({ item, label, price, cat, level, locked: level > 3, desc: 'Used to hang grow lights above pots.' }));

    const now = Date.now() / 1000;
    const show = {
        hud: () => send('hud', { quest: { title: 'Steal the RV', text: 'The Ballas are sitting on it at Davis, Carson Ave.' } }),
        text: () => send('text', { from: 'Unknown number', lines: ["Ha! Look at you. The RV's yours now, kid. That's your lab.", "Seeds are in a dead drop. Pin's on your map. Go get 'em."], timeout: 60 }),
        dialogue: () => send('dialogue', { name: 'Uncle Benson', role: 'A man in a wheelchair', text: "Well, well. Nobody finds me by accident. Either you're lost, or you're looking for work.", choices: ['Who are you?', "I'm looking for work."] }),
        ix: () => send('ix', { text: 'Rotate the plant and trim every bud', count: '3/8', keys: [{ key: 'Mouse', label: 'Move' }, { key: 'LMB', label: 'Use' }, { key: 'A D', label: 'Rotate plant' }, { key: 'Esc', label: 'Exit' }] }),
        choose: () => send('panel', { type: 'choose', data: { title: 'Pick a seed', options: [{ item: 'nzw_seed_ogkush', label: 'OG Kush Seed', n: 3 }, { item: 'nzw_seed_gdp', label: 'Granddaddy Purple Seed', n: 1, locked: true, level: 9 }] } }),
        place: () => send('panel', { type: 'place', data: { lab: 'RV', maxGrow: 3, maxObjects: 10, objects: 2, items: [{ item: 'nzw_pot', label: 'Plastic Pot', icon: 'pot', n: 2 }, { item: 'nzw_packstation', label: 'Packaging Station', icon: 'box', n: 1 }, { item: 'nzw_growtent', label: 'Grow Tent', icon: 'tent', n: 1, locked: true, level: 3 }] } }),
        pack: () => send('panel', { type: 'pack', data: { stacks, baggies: 40, jars: 8, jarLevel: 3, level: 5, max: { baggie: 6, jar: 4 }, per: { baggie: 1, jar: 5 } } }),
        dry: () => send('panel', { type: 'dry', data: { stacks, now, max: 4, minutes: 10, capacity: 15, slots: [{ done: now - 5 }, { done: now - 5 }, { done: now + 320 }, { done: now + 320 }, { done: now + 540 }] } }),
        mix: () => send('panel', { type: 'mix', data: { stacks, max: 10, ingredients: [{ item: 'nzw_ing_banana', label: 'Banana', effect: 'gingeritis', n: 12 }, { item: 'nzw_ing_energydrink', label: 'Energy Drink', effect: 'athletic', n: 4, locked: true, level: 9 }] } }),
        press: () => send('panel', { type: 'press', data: { stacks, units: 20 } }),
        shop: () => send('panel', { type: 'shop', data: { items: shopItems, level: 3, money: { cash: 1840, bank: 25300 }, accounts: ['cash', 'bank'], max: 50 } }),
        tablet: () => send('panel', { type: 'tablet', data: {
            level: 7, xp: 640, need: 1280, title: 'Grower', objective: null, accounts: ['cash', 'bank'], towFee: 750, water: 3, capacity: 4,
            labs: [
                { id: 'rv', label: 'RV', icon: 'rv', level: 0, owned: true, maxGrow: 3, maxObjects: 10, entrances: [] },
                { id: 'small', label: 'Small Warehouse', icon: 'warehouse', level: 6, price: 85000, owned: false, maxGrow: 12, maxObjects: 30, entrances: ['Del Perro', 'Cypress Flats', 'Paleto Bay'] },
                { id: 'warehouse', label: 'Weed Warehouse', icon: 'warehouse', level: 15, price: 275000, locked: true, owned: false, maxGrow: 40, maxObjects: 90, entrances: ['Vinewood'] },
            ],
            unlocks: [{ level: 1, label: 'Suspension Rack' }, { level: 1, label: 'Halogen Grow Light' }, { level: 2, label: 'Speed Growth' }, { level: 2, label: 'Sour Diesel Seed' }, { level: 3, label: 'Grow Tent' }, { level: 3, label: 'Empty Jar' }, { level: 4, label: 'Drying Rack' }, { level: 4, label: 'PGR' }, { level: 5, label: 'LED Grow Light' }, { level: 6, label: 'Small Warehouse', kind: 'lab' }, { level: 8, label: 'Mixing Station' }, { level: 11, label: 'Full Spectrum Grow Light' }, { level: 12, label: 'Brick Press' }, { level: 15, label: 'Weed Warehouse', kind: 'lab' }],
        } }),
        labs: () => { show.tablet(); },
        unlocks: () => { show.tablet(); setTimeout(() => document.querySelector('[data-tab="unlocks"]').click(), 50); },
        levelup: () => send('levelup', { level: 6, title: 'Grower', unlocks: ['Small Warehouse', 'Premium Potting Soil'] }),
    };
    const go = () => {
        const k = (location.hash || '#shop').slice(1);
        (show[k] || show.shop)();
        if (k === 'hud' || k === 'ix') { show.hud(); send('notify', { text: 'Trimmed 8 buds', kind: 'success', title: 'Harvest', duration: 60000 }); send('xp', { amount: 62, why: 'Harvest' }); }
    };
    setTimeout(go, 50);
})();
