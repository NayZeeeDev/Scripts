/* Browser preview only (never runs in game). Open web/index.html#scene through any static server.
   Scenes: #heists #crew #market #fence #profile #board #chat #hud #result #drone #mg-<type> */
(async function () {
    const send = (action, data) => window.postMessage({ action, data }, '*');
    let strings = {};
    try { strings = (await (await fetch('../locales/en.json')).json()).ui || {}; } catch (e) { /* offline */ }

    const heists = [
        ['store', 'Store Robbery', 'small', 'store', 1, 1], ['atm', 'ATM Spree', 'small', 'atm', 1, 1], ['house', 'House Burglary', 'small', 'house', 1, 0],
        ['boosting', 'Car Boosting', 'small', 'car', 2, 1], ['gridhack', 'Phone Network Hack', 'small', 'chip', 1, 0], ['fleeca', 'Fleeca Bank', 'medium', 'vault', 2, 2],
        ['moneytruck', 'Armored Truck', 'medium', 'truck', 2, 2], ['yacht', 'Yacht Raid', 'medium', 'yacht', 3, 2], ['vangelico', 'Vangelico Jewel Heist', 'major', 'diamond', 4, 3],
        ['paleto', 'Blaine County Savings', 'major', 'bank', 5, 3], ['cargoship', 'Cargo Ship', 'major', 'ship', 5, 2], ['pacific', 'Pacific Standard', 'major', 'crown', 8, 4],
    ].map(([id, label, category, icon, level, police], i) => ({
        id, label, category, icon, level, police, members: { min: 1, max: 4 + (i % 4) }, timeLimit: 15 + i * 2, xp: 150 + i * 120,
        money: [2000 + i * 1500, 4000 + i * 2500], cooldown: i === 7 ? 840 : 0, running: i === 5 ? 1 : 0, simultaneous: 2, locked: level > 5,
        featured: id === 'fleeca', playerCooldown: 10, locations: 1 + (i % 6),
        description: 'Crack the vault with a SafePad, breach the inner gate and empty the trolleys before the cops lock the block down.',
        requiredItems: i > 4 ? [{ name: 'safepad', label: 'SafePad', count: 1 }, { name: 'heist_drill', label: 'Heavy Drill', count: 1 }] : [],
        briefing: ['Go to the marked location.', 'Plug a SafePad into the vault panel and crack it.', 'Hack the inner gate, grab the trolleys and drill the lockboxes.', 'Get 200m away to finish.'],
    }));
    const profile = { nickname: 'nayzeee', avatar: 1, level: 7, levelXp: 3200, levelNeed: 5000, xp: 16700, completed: 42, failed: 6, earned: 1284500, perks: { loot: 1.1, speed: 1.1 } };
    const crew = { id: 1, leader: 1, members: [
        { source: 1, nickname: 'nayzeee', avatar: 1, level: 7, ready: true, leader: true },
        { source: 14, nickname: 'Ghost', avatar: 7, level: 4, ready: true, leader: false },
        { source: 22, nickname: 'Vinewood_Vic', avatar: 3, level: 2, ready: false, leader: false },
    ] };

    window.MockData = {
        'heists:list': { ok: true, data: { heists, police: 6, playerCooldown: 0 } },
        'market:data': { ok: true, data: { enabled: true, maxPerItem: 10, categories: [{ id: 'tools', label: 'Tools' }, { id: 'electronics', label: 'Electronics' }, { id: 'explosives', label: 'Explosives' }, { id: 'gear', label: 'Gear' }],
            items: [
                { name: 'lockpick', label: 'Advanced Lockpick', price: 600, category: 'tools', level: 1, used: 'Store, House, Boosting' },
                { name: 'heist_drill', label: 'Heavy Drill', price: 9500, category: 'tools', level: 2, used: 'Fleeca, ATM, Vangelico' },
                { name: 'hacking_device', label: 'Hacking Device', price: 2500, category: 'electronics', level: 1, used: 'ATM, House, Grid Hack' },
                { name: 'safepad', label: 'SafePad', price: 6000, category: 'electronics', level: 2, used: 'Fleeca, Paleto, Pacific' },
                { name: 'heist_laptop', label: 'Encrypted Laptop', price: 12000, category: 'electronics', level: 9, used: 'Pacific, Cartel, Convoy' },
                { name: 'thermite', label: 'Thermite Charge', price: 3000, category: 'explosives', level: 2, used: 'Paleto, Pacific, Train' },
                { name: 'c4_charge', label: 'C4 Charge', price: 7500, category: 'explosives', level: 3, used: 'Bobcat, Money Truck, Convoy, ATM' },
                { name: 'gasmask', label: 'Gas Mask', price: 1500, category: 'gear', level: 2, used: 'Vangelico' },
            ] } },
        'fence:data': { ok: true, data: { near: true, items: [
            { name: 'gold_bar', label: 'Gold Bar', price: 2611, owned: 6 }, { name: 'diamond', label: 'Loose Diamond', price: 1742, owned: 11 },
            { name: 'rolex', label: 'Luxury Watch', price: 671, owned: 3 }, { name: 'painting', label: 'Painting', price: 6210, owned: 1 }, { name: 'coke_brick', label: 'Cocaine Brick', price: 3102, owned: 0 },
        ] } },
        'profile:history': { ok: true, data: [
            { label: 'Pacific Standard', location: 'Pacific Standard Bank', success: 1, payout: 182400, duration: 1712 },
            { label: 'Fleeca Bank', location: 'Fleeca - Legion Square', success: 1, payout: 48310, duration: 642 },
            { label: 'Armored Truck', location: 'Mirror Park Freeway', success: 0, payout: 0, duration: 1500 },
        ] },
        'profile:leaderboard': { ok: true, data: [
            { nickname: 'nayzeee', avatar: 1, level: 12, completed: 212, earned: 9284500 }, { nickname: 'Ghost', avatar: 7, level: 10, completed: 160, earned: 6120000 },
            { nickname: 'Vinewood_Vic', avatar: 3, level: 9, completed: 121, earned: 4100250 }, { nickname: 'Lola', avatar: 5, level: 6, completed: 77, earned: 1999999 },
        ] },
        'chat:history': { ok: true, data: [
            { source: 14, nickname: 'Ghost', avatar: 7, level: 4, text: 'anyone got a spare safepad? doing fleeca in 5', time: 1760000000 },
            { source: 1, nickname: 'nayzeee', avatar: 1, level: 7, text: 'market has them, invite me', time: 1760000060 },
            { source: 22, nickname: 'Vinewood_Vic', avatar: 3, level: 2, text: 'need 3 more for pacific, lvl 8+', time: 1760000120 },
        ] },
    };

    send('init', { ui: { theme: { accent: '#08afa2', accent2: '#0fd4c4', danger: '#e5484d', warning: '#e5a50a' }, hud: { position: 'right', background: 'none', expandKey: 'B', scale: 1 }, notify: { position: 'top-right' }, textui: { position: 'bottom' } }, strings, levels: [] });

    const scene = (location.hash || '#heists').slice(1);
    const menuTabs = ['heists', 'crew', 'market', 'fence', 'profile', 'board', 'chat'];
    if (menuTabs.includes(scene)) {
        send('menu', { open: true, data: { profile, crew, featured: 'fleeca', featuredBonus: { money: 1.25 }, levels: [], tab: scene, serverId: 1 } });
        if (scene === 'heists') setTimeout(() => send('invite', { nickname: 'Ghost', avatar: 7, level: 4, timeout: 45 }), 300);
    } else if (scene === 'hud') {
        document.body.style.background = 'linear-gradient(180deg,#9fb7cc 0%,#c9a27a 38%,#4a5562 39%,#2b333c 70%,#1d2228 100%)';
        send('hud', { show: true, title: 'Fleeca Bank', icon: 'vault', location: 'Fleeca - Legion Square', task: 'Bypass the inner gate', stage: 2, stages: 3, remaining: 1342,
            objectives: [{ label: 'Bypass the gate lock', count: 0, total: 1 }, { label: 'Trolleys', count: 2, total: 4, optional: true }, { label: 'Lockboxes', count: 1, total: 1, done: true }],
            members: crew.members, distance: null, guards: { alive: 2, total: 6 } });
        send('noise', { value: 42 });
        send('textui', { lines: [{ key: 'E', label: 'Grab cash' }, { key: 'G', label: 'Drop' }] });
        send('progress', { label: 'Grabbing cash...', duration: 14000 });
        send('notify', { text: 'Looted: $11,240', kind: 'success' });
        send('notify', { text: 'Silent alarm triggered: Fleeca Bank', kind: 'error' });
        send('notify', { text: 'Bypass the inner gate', kind: 'info' });
        send('delivery', { remaining: 37 });
    } else if (scene === 'result') {
        document.body.style.background = 'linear-gradient(160deg,#5b6b7c,#2b3440 60%,#20262e)';
        send('result', { success: true, label: 'Pacific Standard', duration: 1712, xp: 3000, money: 9250, earned: 182400, leveled: true, level: 9 });
    } else if (scene === 'drone') {
        document.body.style.background = 'linear-gradient(180deg,#43515f,#1f2830)';
        send('drone', { show: true, zones: 3 });
        send('drone', { show: true, altitude: 38, distance: 112, range: 250, inZone: true, remaining: 2, zones: 3 });
    } else if (scene.startsWith('mg-')) {
        document.body.style.background = 'linear-gradient(160deg,#5b6b7c,#2b3440 60%,#20262e)';
        send('minigame', { type: scene.slice(3), difficulty: 2 });
    }
})();
