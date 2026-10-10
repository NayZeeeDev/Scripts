/* nayzeee drug empire - inline SVG icon set (shared with the heistpack) - no image files, scales with font-size, coloured with currentColor */
(function () {
    const P = {
        // navigation
        target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
        users: '<path d="M16 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 18.5V20"/><circle cx="10" cy="8" r="3.5"/><path d="M20 20v-1.5a3.5 3.5 0 0 0-2.5-3.35"/><path d="M15.5 4.65a3.5 3.5 0 0 1 0 6.7"/>',
        cart: '<circle cx="9" cy="20" r="1.4"/><circle cx="18" cy="20" r="1.4"/><path d="M2.5 3h3l2.4 11.2a2 2 0 0 0 2 1.6h7.6a2 2 0 0 0 2-1.5L21 7.5H6.4"/>',
        bag: '<path d="M8 7V6a4 4 0 0 1 8 0v1"/><path d="M5 7h14l-1 13H6z"/><path d="M12 11v5M10 12.5c0-.8.9-1.5 2-1.5s2 .7 2 1.5-.9 1.2-2 1.5-2 .7-2 1.5.9 1.5 2 1.5 2-.7 2-1.5"/>',
        user: '<circle cx="12" cy="8" r="4"/><path d="M4 21v-1a6 6 0 0 1 6-6h4a6 6 0 0 1 6 6v1"/>',
        trophy: '<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3"/>',
        chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20.5l1.4-4.6A8 8 0 1 1 21 12z"/>',
        // heists
        store: '<path d="M3 9l1.5-5h15L21 9"/><path d="M4 9v11h16V9"/><path d="M3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0"/><path d="M10 20v-5h4v5"/>',
        atm: '<rect x="3" y="4" width="18" height="16" rx="2"/><rect x="7" y="7" width="10" height="5" rx="1"/><path d="M8 16h8M8 19h8"/>',
        house: '<path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
        car: '<path d="M5 17H3v-5l2-5h11l3 5h2v5h-2"/><circle cx="7.5" cy="17" r="2"/><circle cx="16.5" cy="17" r="2"/><path d="M9.5 17h5M5 12h14"/>',
        chip: '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
        vault: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="12" cy="12" r="5"/><path d="M12 7v2M12 15v2M7 12h2M15 12h2"/><path d="M3 8h-1M3 16h-1"/>',
        truck: '<path d="M2 6h12v10H2z"/><path d="M14 9h4l4 4v3h-8"/><circle cx="6" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>',
        yacht: '<path d="M2 18c2 1.5 4 1.5 6 0s4-1.5 6 0 4 1.5 6 0"/><path d="M4 15l2-5h12l2 5z"/><path d="M8 10V6h7l2 4"/>',
        barn: '<path d="M3 21V10l9-6 9 6v11z"/><path d="M8 21v-7h8v7M8 14l8 7M16 14l-8 7"/>',
        gun: '<path d="M3 8h17v4h-5l-1 2h-3l-1 2H6l1-4H3z"/><path d="M20 8l1-2"/>',
        diamond: '<path d="M6 3h12l4 6-10 12L2 9z"/><path d="M2 9h20M9 3l3 18 3-18"/>',
        bank: '<path d="M3 21h18M4 10h16M12 3l9 5H3z"/><path d="M6 10v8M10 10v8M14 10v8M18 10v8"/>',
        shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
        container: '<rect x="2" y="6" width="20" height="12" rx="1"/><path d="M6 6v12M10 6v12M14 6v12M18 6v12"/>',
        train: '<rect x="5" y="3" width="14" height="14" rx="3"/><path d="M5 11h14M9 21l-2-3M15 21l2-3"/><circle cx="9" cy="14" r="1"/><circle cx="15" cy="14" r="1"/>',
        plane: '<path d="M2 13l8-2 4-8h2l-1 8 6 2v2l-6-1-1 6 2 2v1l-4-1-4 1v-1l2-2-1-6-7 1z"/>',
        convoy: '<path d="M1 7h9v8H1zM10 10h3l2 3v2h-5"/><circle cx="4" cy="17" r="1.6"/><circle cx="12" cy="17" r="1.6"/><path d="M16 9h4l3 3v3h-7z"/><circle cx="19" cy="17" r="1.6"/>',
        skull: '<path d="M12 3a8 8 0 0 0-8 8c0 3 1.5 4.5 3 5.5V20h10v-3.5c1.5-1 3-2.5 3-5.5a8 8 0 0 0-8-8z"/><circle cx="9" cy="11" r="1.6"/><circle cx="15" cy="11" r="1.6"/><path d="M10 20v-2M14 20v-2"/>',
        ship: '<path d="M2 20c2 1 4 1 6 0s4-1 6 0 4 1 6 0"/><path d="M3 16l1.5-5h15L21 16"/><path d="M6 11V7h5v4M13 11V5h4v6"/>',
        crown: '<path d="M3 7l4 4 5-6 5 6 4-4-2 12H5z"/><path d="M5 19h14"/>',
        mask: '<path d="M3 7c3-1 6-1 9 1 3-2 6-2 9-1 0 6-2 10-5 10-2 0-3-2-4-2s-2 2-4 2c-3 0-5-4-5-10z"/><path d="M7 11h3M14 11h3"/>',
        // misc
        siren: '<path d="M7 18v-6a5 5 0 0 1 10 0v6"/><path d="M5 18h14v3H5zM12 3v2M4.2 6.2l1.4 1.4M19.8 6.2l-1.4 1.4"/>',
        clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
        star: '<path d="M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z"/>',
        lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
        check: '<path d="M5 12l5 5L20 7"/>',
        x: '<path d="M6 6l12 12M18 6L6 18"/>',
        bolt: '<path d="M13 2L4 14h7l-1 8 9-12h-7z"/>',
        fire: '<path d="M12 22c4 0 7-3 7-7 0-4-3-6-4-10-2 2-3 4-3 6-1-1-2-2-2-4-3 2-5 5-5 8 0 4 3 7 7 7z"/>',
        ghost: '<path d="M5 21V11a7 7 0 0 1 14 0v10l-2.5-2-2.3 2-2.2-2-2.2 2-2.3-2z"/><circle cx="9.5" cy="11" r="1"/><circle cx="14.5" cy="11" r="1"/>',
        eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
        spade: '<path d="M12 3C8 8 4 10 4 14a4 4 0 0 0 7 2.6V19l-2 2h6l-2-2v-2.4A4 4 0 0 0 20 14c0-4-4-6-8-11z"/>',
        coin: '<circle cx="12" cy="12" r="9"/><path d="M14.5 9.5c-.4-1-1.4-1.5-2.5-1.5-1.4 0-2.5.8-2.5 2s1.1 1.6 2.5 2 2.5.8 2.5 2-1.1 2-2.5 2c-1.1 0-2.1-.5-2.5-1.5M12 6.5v1.5M12 16v1.5"/>',
        send: '<path d="M22 2L11 13M22 2l-7 20-4-9-9-4z"/>',
        plus: '<path d="M12 5v14M5 12h14"/>',
        minus: '<path d="M5 12h14"/>',
        crosshair: '<circle cx="12" cy="12" r="9"/><path d="M12 3v4M12 17v4M3 12h4M17 12h4"/>',
        // drug empire
        leaf: '<path d="M12 21v-7"/><path d="M12 14C8 14 4 11 4 5c4 0 8 2 8 9z"/><path d="M12 14c4 0 8-3 8-9-4 0-8 2-8 9z"/><path d="M12 14c-2-3-2-7 0-11 2 4 2 8 0 11z"/>',
        crystal: '<path d="M8 3h8l4 6-8 12L4 9z"/><path d="M4 9h16M12 21L9 9l3-6 3 6z"/>',
        shroom: '<path d="M3 12a9 7 0 0 1 18 0z"/><path d="M9 12v6a3 3 0 0 0 6 0v-6"/><circle cx="9" cy="8.5" r="1"/><circle cx="14.5" cy="7.5" r="1"/>',
        powder: '<path d="M3 18c3-5 6-7 9-7s6 2 9 7z"/><path d="M8 7l1-3M12 6V3M16 7l-1-3"/>',
        pot: '<path d="M5 9h14l-2 11H7z"/><path d="M4 6h16v3H4z"/><path d="M12 6V3"/>',
        tent: '<path d="M4 21V4h16v17"/><path d="M8 21V8h8v13"/><path d="M4 4h16"/><path d="M8 10h8"/>',
        bulb: '<path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-4 10.5c.7.7 1 1.5 1 2.5h6c0-1 .3-1.8 1-2.5A6 6 0 0 0 12 3z"/>',
        box: '<path d="M3 7l9-4 9 4v10l-9 4-9-4z"/><path d="M3 7l9 4 9-4M12 11v10"/>',
        rack: '<path d="M4 4h16M4 20h16M6 4v16M18 4v16"/><path d="M8 8v3M11 8v4M14 8v3M8 14v3M11 14v2M14 14v3"/>',
        flask: '<path d="M9 3h6M10 3v6L4 19a1.5 1.5 0 0 0 1.3 2h13.4A1.5 1.5 0 0 0 20 19l-6-10V3"/><path d="M7 14h10"/>',
        beaker: '<path d="M6 3h12M7 3v15a3 3 0 0 0 3 3h4a3 3 0 0 0 3-3V3"/><path d="M7 12h10"/>',
        oven: '<rect x="3" y="3" width="18" height="18" rx="2"/><rect x="6" y="9" width="12" height="9" rx="1"/><path d="M7 6h1M11 6h1M15 6h2"/>',
        cauldron: '<path d="M4 10h16l-1.5 7a4 4 0 0 1-4 3h-5a4 4 0 0 1-4-3z"/><path d="M3 10h18M8 7c0-2 2-2 2-4M14 7c0-2 2-2 2-4"/>',
        syringe: '<path d="M18 2l4 4M16 4l4 4M19 5l-11 11-3 1 1-3L17 3"/><path d="M8 16l-3 3M10 9l2 2M13 6l2 2"/>',
        droplet: '<path d="M12 3s7 7.5 7 12a7 7 0 0 1-14 0c0-4.5 7-12 7-12z"/>',
        msg: '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20.5l1.4-4.6A8 8 0 1 1 21 12z"/><path d="M8 11h8M8 14h5"/>',
        book: '<path d="M4 4h6a3 3 0 0 1 2 1 3 3 0 0 1 2-1h6v15h-6a2 2 0 0 0-2 2 2 2 0 0 0-2-2H4z"/><path d="M12 5v16"/>',
        phone: '<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M11 18h2"/>',
        handshake: '<path d="M11 17l2 2a1.4 1.4 0 0 0 2-2"/><path d="M14 14l2.5 2.5a1.4 1.4 0 0 0 2-2L15 11l-2 1a2 2 0 0 1-2-3l3-3 3 1 4-1v8"/><path d="M3 7l4-1 3 1"/><path d="M3 15V7M7 18l-3-3"/>',
        scissors: '<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M8.1 8.1L20 20M8.1 15.9L20 4"/>',
        wheel: '<circle cx="9" cy="16" r="5"/><circle cx="9" cy="16" r="1"/><path d="M14 16h3l2-6h2M9 11V4h4"/>',
        unknown: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 0 1 4.8 1c0 1.7-2.3 2-2.3 3.5M12 17h.01"/>',
        crew: '<path d="M16 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 18.5V20"/><circle cx="10" cy="8" r="3.5"/><path d="M19 8v6M16 11h6"/>',
        tool: '<path d="M14.7 6.3a4 4 0 0 0 5 5L21 13l-8 8-3-3 6.3-6.3"/><path d="M14.7 6.3L12 3.6a4 4 0 0 0-5.7 5.7l2.7 2.7L3 18v3h3l6.3-6.3"/>',
        back: '<path d="M15 18l-6-6 6-6"/>',
        chev: '<path d="M9 18l6-6-6-6"/>',
        pin: '<path d="M12 22s7-6.5 7-12a7 7 0 0 0-14 0c0 5.5 7 12 7 12z"/><circle cx="12" cy="10" r="2.5"/>',
        cash: '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M6 9v.01M18 15v.01"/>',
        rv: '<path d="M2 17V6a1 1 0 0 1 1-1h13l4 5h1a1 1 0 0 1 1 1v6h-2"/><circle cx="7" cy="17" r="2"/><circle cx="17" cy="17" r="2"/><path d="M9 17h6M5 9h4v3H5zM12 9h3v8"/>',
        grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
        map: '<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
    };

    function svg(name, cls) {
        const body = P[name] || P.mask;
        return `<svg class="ico ${cls || ''}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
    }

    const AVATARS = ['mask', 'skull', 'crown', 'bolt', 'diamond', 'fire', 'ghost', 'star', 'eye', 'crosshair', 'spade', 'coin'];

    /** square avatar tile (NAYZEEE .av). cls: '' | 'teal' | 'red' */
    function avatar(n, size, cls) {
        const icon = AVATARS[((n || 1) - 1) % AVATARS.length];
        const s = size ? `width:${size}px;height:${size}px;` : '';
        return `<div class="av ${cls || ''}" style="${s}">${svg(icon)}</div>`;
    }

    window.Icons = { svg, avatar, count: AVATARS.length };
})();
