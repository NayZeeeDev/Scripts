window.NH = window.NH || {};

// Line icons (24x24, stroke = currentColor)
NH.ICONS = {
  sliders: '<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>',
  heart: '<path d="M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z"/>',
  gauge: '<path d="m12 14 4-4"/><path d="M3.3 19a10 10 0 1 1 17.4 0"/>',
  car: '<path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2"/><circle cx="7" cy="17" r="2"/><path d="M9 17h6"/><circle cx="17" cy="17" r="2"/>',
  bike: '<circle cx="5.5" cy="17.5" r="3.5"/><circle cx="18.5" cy="17.5" r="3.5"/><circle cx="15" cy="5" r="1"/><path d="M12 17.5V14l-3-3 4-3 2 3h2"/>',
  plane: '<path d="M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z"/>',
  boat: '<path d="M2 21c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1 .6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M19.4 20A11.6 11.6 0 0 0 21 14l-9-4-9 4c0 2.9.9 5.3 2.8 7.8"/><path d="M19 13V7a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v6M12 10v4M12 2v3"/>',
  map: '<path d="M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3z"/><path d="M9 3v15M15 6v15"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  crosshair: '<circle cx="12" cy="12" r="9"/><path d="M22 12h-4M6 12H2M12 6V2M12 22v-4"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  cloudsun: '<path d="M12 2v2M4.9 4.9l1.4 1.4M20 12h2M19.1 4.9l-1.4 1.4"/><path d="M15.9 13A4 4 0 0 0 8.2 10"/><path d="M13 22H7a5 5 0 1 1 4.9-6H13a3 3 0 0 1 0 6z"/>',
  image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>',
  swap: '<path d="m16 3 4 4-4 4M20 7H4M8 21l-4-4 4-4M4 17h16"/>',
  keyboard: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M6 9h.01M10 9h.01M14 9h.01M18 9h.01M6 13h.01M18 13h.01M8 16h8M10 13h4"/>',
  palette: '<circle cx="13.5" cy="6.5" r="1"/><circle cx="17.5" cy="10.5" r="1"/><circle cx="8.5" cy="7.5" r="1"/><circle cx="6.5" cy="12.5" r="1"/><path d="M12 2a10 10 0 0 0 0 20c.9 0 1.6-.7 1.6-1.7 0-.4-.2-.8-.4-1.1-.3-.3-.4-.7-.4-1.1 0-.9.7-1.7 1.7-1.7h2A5.6 5.6 0 0 0 22 11c0-5-4.5-9-10-9z"/>',
  move: '<path d="M5 9l-3 3 3 3M9 5l3-3 3 3M15 19l-3 3-3-3M19 9l3 3-3 3M2 12h20M12 2v20"/>',
  reset: '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  briefcase: '<rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/>',
  bank: '<path d="M3 22h18M6 18v-7M10 18v-7M14 18v-7M18 18v-7M12 2l9 5H3z"/>',
  cash: '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 12h.01M18 12h.01"/>',
  idcard: '<rect x="2" y="5" width="20" height="14" rx="2"/><circle cx="8" cy="11" r="2"/><path d="M5 16a3 3 0 0 1 6 0M14 10h4M14 14h3"/>',
  fuel: '<path d="M3 22h12M4 9h10M14 22V4a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v18"/><path d="M14 13h2a2 2 0 0 1 2 2v2a2 2 0 0 0 4 0V9.8a2 2 0 0 0-.6-1.4L18 5"/>',
  engine: '<path d="M7 5h6M10 5v3M5 8h9l3 3h2v-2h2v8h-2v-2h-2l-2 3H7l-2-3H3v-4h2z"/>',
  belt: '<circle cx="12" cy="4.5" r="2"/><path d="M8 21v-6l-2-1V9a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v5l-2 1v6"/><path d="M8 8l8 9"/>',
  light: '<path d="M10 6c-3.3 0-6 2.7-6 6s2.7 6 6 6h2V6z"/><path d="M16 8h5M16 12h5M16 16h5"/>',
  lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  unlock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.8-1.2"/>',
  hazard: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9.5 8.5 16h7z"/>',
  warn: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
  arrowL: '<path d="M11 5 4 12l7 7v-4h9V9h-9z"/>',
  arrowR: '<path d="M13 5l7 7-7 7v-4H4V9h9z"/>',
  star: '<path d="m12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z"/>',
  door: '<path d="M4 20V9l6-6h10v17z"/><path d="M4 11h16M15 14h2"/>',
  window: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M12 10v10"/>',
  seat: '<path d="M8 3h4l1.5 10H9.5z"/><path d="M9.5 13H17a2 2 0 0 1 2 2v2H7"/><path d="M9 17l-1 4M17 17l1 4"/>',
  hood: '<path d="M3 15h18v4H3z"/><path d="M5 15l3-8h8l3 8"/>',
  trunk: '<path d="M3 9h18v10H3z"/><path d="M3 9l3-5h12l3 5M9 13h6"/>',
  power: '<path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.8 0"/>',
  bulb: '<path d="M9 18h6M10 22h4M12 2a7 7 0 0 0-4 12.7V16h8v-1.3A7 7 0 0 0 12 2z"/>',
  mic: '<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M19 10v1a7 7 0 0 1-14 0v-1M12 18v4"/>',
  radio: '<path d="M4.9 19.1a10 10 0 0 1 0-14.2M7.8 16.2a6 6 0 0 1 0-8.4M16.2 7.8a6 6 0 0 1 0 8.4M19.1 4.9a10 10 0 0 1 0 14.2"/><circle cx="12" cy="12" r="2"/>',
  bullets: '<path d="M6 20V9l1.5-4L9 9v11zM11 20V9l1.5-4L14 9v11zM16 20V9l1.5-4L19 9v11z"/>',
  compass: '<circle cx="12" cy="12" r="10"/><path d="m16.2 7.8-2.1 6.3-6.3 2.1 2.1-6.3z"/>',
  sparkles: '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>',
  train: '<rect x="5" y="3" width="14" height="14" rx="3"/><path d="M5 11h14M9 21l-2-4M15 21l2-4M9 14h.01M15 14h.01"/>',
  download: '<path d="M12 3v12M7 10l5 5 5-5M5 21h14"/>',
  upload: '<path d="M12 21V9M7 14l5-5 5 5M5 3h14"/>',
  copy: '<rect x="8" y="8" width="13" height="13" rx="2"/><path d="M4 16V5a1 1 0 0 1 1-1h11"/>',
  cog: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  bolt: '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
  eye: '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
};

// Filled status icons (also used as CSS masks for the "liquid" style)
NH.FILLED = {
  heart: 'M12 21.2S3.9 16.4 2.4 11.4C1.2 7.6 3.5 4.3 7 4.3c2.1 0 3.6 1.1 5 2.9 1.4-1.8 2.9-2.9 5-2.9 3.5 0 5.8 3.3 4.6 7.1-1.5 5-9.6 9.8-9.6 9.8z',
  shield: 'M12 2.2 20 5v6.1c0 5.2-3.4 9.3-8 10.9-4.6-1.6-8-5.7-8-10.9V5z',
  burger: 'M4 10.2C4 6.6 7.6 4 12 4s8 2.6 8 6.2zM3 12h18v2.8H3zM4 16.6h16V18a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3z',
  drop: 'M12 2.4s-7 7.9-7 12.5a7 7 0 0 0 14 0c0-4.6-7-12.5-7-12.5z',
  bolt: 'M13.5 2 4 14h7l-1.5 8L20 10h-7z',
  brain: 'M9.2 3A3 3 0 0 0 6.3 5.6 3.2 3.2 0 0 0 3.5 9a3.4 3.4 0 0 0-.4 5.5A3.3 3.3 0 0 0 6.4 19a2.9 2.9 0 0 0 4.6 1.6V4.3A2.6 2.6 0 0 0 9.2 3zm5.6 0a3 3 0 0 1 2.9 2.6A3.2 3.2 0 0 1 20.5 9a3.4 3.4 0 0 1 .4 5.5 3.3 3.3 0 0 1-3.3 4.5 2.9 2.9 0 0 1-4.6 1.6V4.3A2.6 2.6 0 0 1 14.8 3z',
  bubbles: 'M7.5 10a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9zm8.5-7a3.2 3.2 0 1 1 0 6.4A3.2 3.2 0 0 1 16 3zm1 9.5a2.7 2.7 0 1 1 0 5.4 2.7 2.7 0 0 1 0-5.4z',
  mic: 'M12 2a3.2 3.2 0 0 0-3.2 3.2v5.6a3.2 3.2 0 0 0 6.4 0V5.2A3.2 3.2 0 0 0 12 2zM5.2 10.2a1 1 0 0 1 2 0 4.8 4.8 0 0 0 9.6 0 1 1 0 0 1 2 0 6.8 6.8 0 0 1-5.8 6.7V20h2.6a1 1 0 0 1 0 2H8.4a1 1 0 0 1 0-2H11v-3.1a6.8 6.8 0 0 1-5.8-6.7z',
};

NH.ic = (name, cls = '') => `<svg class="ic ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${NH.ICONS[name] || ''}</svg>`;
NH.fic = (name, cls = '') => `<svg class="fi ${cls}" viewBox="0 0 24 24"><path d="${NH.FILLED[name] || ''}"/></svg>`;
NH.svgUrl = (svg) => `url('data:image/svg+xml,${encodeURIComponent(svg).replace(/'/g, '%27')}')`;
NH.maskUrl = (name) => NH.svgUrl(`<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='${NH.FILLED[name]}'/></svg>`);

// Coloured weather icons
NH.weatherIcon = (wx, night) => {
  const sun = '<circle cx="12" cy="12" r="4.6" fill="#ffc83d"/><g stroke="#ffc83d" stroke-width="1.8" stroke-linecap="round"><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/></g>';
  const moon = '<path d="M14.5 3.2a8.5 8.5 0 1 0 6.3 11.6A7 7 0 0 1 14.5 3.2z" fill="#ffab2e"/>';
  const smallSun = '<circle cx="17" cy="7" r="3.2" fill="#ffc83d"/>';
  const smallMoon = '<path d="M17.5 3.2a4 4 0 1 0 3.3 5.9 3.3 3.3 0 0 1-3.3-5.9z" fill="#ffab2e"/>';
  const cloud = (c = '#8ec5ff') => `<path d="M17 19H7.5a4.5 4.5 0 1 1 1-8.9A5.5 5.5 0 0 1 19 11.5 3.8 3.8 0 0 1 17 19z" fill="${c}"/>`;
  const small = night ? smallMoon : smallSun;
  switch (wx) {
    case 'EXTRASUNNY': case 'CLEAR': case 'NEUTRAL':
      return night ? moon : sun;
    case 'CLOUDS': case 'CLEARING':
      return small + cloud();
    case 'OVERCAST':
      return cloud('#a9c4e4');
    case 'RAIN': case 'RAIN_HALLOWEEN':
      return small + cloud('#7fb2f0') + '<g stroke="#4ea1ff" stroke-width="1.8" stroke-linecap="round"><path d="M9 20.5l-.8 2M13 20.5l-.8 2M17 20.5l-.8 2"/></g>';
    case 'THUNDER':
      return cloud('#8fa8cc') + '<path d="M13 17l-3 4h2.5l-1 3 3.5-4.5H12.5l1-2.5z" fill="#ffd23d"/>';
    case 'SNOW': case 'SNOWLIGHT': case 'BLIZZARD': case 'XMAS': case 'SNOW_HALLOWEEN':
      return small + cloud('#cfe4ff') + '<g fill="#fff"><circle cx="9" cy="21.5" r="1"/><circle cx="13" cy="22.5" r="1"/><circle cx="17" cy="21.5" r="1"/></g>';
    case 'SMOG': case 'FOGGY': case 'HALLOWEEN':
      return small + '<g stroke="#b9c3cf" stroke-width="2" stroke-linecap="round"><path d="M3 12h13M5 16h15M3 20h12"/></g>';
    default:
      return night ? moon : sun;
  }
};
