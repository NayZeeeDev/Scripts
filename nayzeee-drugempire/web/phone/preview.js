/* Browser preview for the Empire app (outside FiveM). phone/index.html#home|messages|thread|journal|products|contacts|map|dealers|deliveries|rv */
(function () {
  const s = document.createElement('script');
  s.src = '../preview-data.js';
  s.onload = () => {
    const C = window.PREVIEW_CFG;
    const t = Date.now() / 1000;
    const spots = {}; for (const [id, sp] of Object.entries(C.spots)) spots[id] = { label: sp.label, region: sp.region };
    const pins = [
      { kind: 'rv', label: 'Your RV', x: 1981, y: 3779 }, { kind: 'benson', label: 'Uncle Benson', x: 2340, y: 3126 },
      { kind: 'deal', label: 'Deal: Andy', x: 2008, y: 3790, sub: 'Behind the gas station' }, { kind: 'customer', label: 'Doug', x: 1897, y: 3859, sub: 'Blue house' },
      { kind: 'sample', label: 'Sample: Chelsey', x: 1828, y: 3660, sub: "Near the doctor's office" }, { kind: 'drop', label: 'Bins behind the Sandy 24/7', x: 1965, y: 3747, ready: true },
    ];
    const DATA = {
      now: t,
      me: { name: 'Marcus Reed', level: 3, rank: 'Street Rat III', xp: 140, need: 320, nextRank: 'Street Rat IV', stats: { earned: 1840, sold: 46, deals: 12 }, water: 3, cap: 4 },
      threads: [
        { id: 'andy', name: 'Andy', icon: 'user', unread: 1, last: "Yo, can you do 2x OG Kush? behind the gas station. I've got $84.", t: t - 60, msgs: [
          { f: 'them', m: 'Good stuff. Thanks.', t: t - 7200 }, { f: 'them', m: "Yo, can you do 2x OG Kush? behind the gas station. I've got $84.", t: t - 60, deal: 'd7' }] },
        { id: 'benson', name: 'Uncle Benson', icon: 'wheel', unread: 0, last: 'Go in the back of the RV and set up.', t: t - 3600, msgs: [
          { f: 'them', m: "The app's on your phone. Messages, contacts, deliveries, all of it. Don't lose that phone.", t: t - 3700 },
          { f: 'them', m: 'Go in the back of the RV and set up. Pots, soil, seed, water.', t: t - 3600 }] },
      ],
      deals: [{ id: 'd7', cid: 'andy', name: 'Andy', pid: 'ogkush', product: 'OG Kush', qty: 2, price: 84, spot: 'sandy_gas', spotLabel: 'Behind the gas station', exp: t + 900, state: 'offer' }],
      journal: [
        { id: 'contact', title: 'A New Contact', done: true, steps: [{ text: 'Answer the text', done: true }, { text: 'Meet the unknown number', done: true }] },
        { id: 'start', title: 'Getting Started', done: false, steps: [{ text: 'Go inside your RV (rear door)', done: true }, { text: 'Place a pot anywhere in the RV', done: true }, { text: 'Pour soil into the pot', done: false }, { text: 'Plant a weed seed in the pot', done: false }] },
      ],
      products: [
        { id: 'ogkush', base: 'ogkush', kind: 'weed', name: 'OG Kush', effects: ['calming'], value: 42, price: 42, addictive: 0.05 },
        { id: 'm1', base: 'ogkush', kind: 'weed', name: 'Blue Cheese Kush', effects: ['calming', 'energizing', 'sneaky'], value: 59, price: 65, addictive: 0.12 },
        { id: 'meth', base: 'meth', kind: 'meth', name: 'Meth', effects: [], value: 70, price: 70, addictive: 0.6 },
      ],
      contacts: [
        { id: 'andy', name: 'Andy', region: 'sandy', home: 'sandy_gas', standards: 2, favorites: ['sedating', 'munchies', 'smelly'], buys: ['weed'], links: ['doug', 'chelsey'], unlocked: true, rel: 3.6, add: 0.18 },
        { id: 'doug', name: 'Doug', region: 'sandy', home: 'sandy_blue', standards: 1, favorites: ['energizing', 'calming', 'refreshing'], buys: ['weed'], links: ['andy'], unlocked: true, rel: 2.2, add: 0.05 },
        { id: 'chelsey', name: 'Chelsey', region: 'sandy', home: 'sandy_doctor', standards: 2, favorites: ['calming', 'focused', 'gingeritis'], buys: ['weed', 'shroom'], links: ['andy'], unlocked: false, target: true, rel: 2, add: 0 },
      ],
      dealers: Object.entries(C.dealers).map(([id, x]) => ({ id, name: x.name, region: x.region, fee: x.fee, cut: x.cut, unlock: x.unlock, coords: x.coords, hired: id === 'benji', cash: id === 'benji' ? 320 : 0, sold: 0, stock: [], units: id === 'benji' ? 8 : 0, customers: id === 'benji' ? ['doug'] : [], max: 8 })),
      deliveries: {
        shops: C.shops.map((sh) => ({ id: sh.id, label: sh.label, desc: sh.desc, items: sh.items.map((i) => ({ item: i.item, label: C.items[i.item], price: i.price, unlock: i.unlock, locked: i.unlock > 3, rank: 'Street Rat ' + ['I', 'II', 'III', 'IV', 'V'][(i.unlock - 1) % 5] })) })),
        drops: C.drops.map((d) => ({ id: d.id, label: d.label, region: d.region, locked: d.region !== 'sandy', x: d.coords.x, y: d.coords.y })),
        orders: [{ id: 'r3', shop: "Dan's Hardware", total: 40, ready: t + 120, drop: 'sandy_bins', dropLabel: 'Bins behind the Sandy 24/7', done: false }],
        rvFee: 150, accounts: ['bank', 'cash'],
      },
      map: { pins, regions: C.regions.map((r) => ({ id: r.id, label: r.label, x: r.center.x, y: r.center.y, locked: r.unlock > 3 })) },
      rv: { owned: true, exists: true, towFee: 500 },
      effects: C.effects, regions: C.regions, spots, standards: C.standards, quality: C.quality, kinds: C.kinds, drugs: C.drugs,
    };
    window.Mock = { handle(name) { if (name === 'phoneData') return DATA; return { ok: true }; } };
    load().then(() => {
      const v = (location.hash || '#home').slice(1);
      if (v === 'thread') { A.view = 'thread'; A.thread = 'andy'; } else A.view = v;
      render();
    });
  };
  document.body.appendChild(s);
})();
