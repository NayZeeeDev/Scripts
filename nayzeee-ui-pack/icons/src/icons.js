/* ═══════════════════════════════════════════════════════════
   NAYZEEE ICONS · source
   Edit icons here, then run:  node icons/build.js
   Grid: 24×24, live area 2–22, stroke 1.75, round caps, mitred joins (keeps chamfers crisp).
   House style: corners are chamfered instead of rounded, and
   "container" shapes (phones, cards, boxes, screens) take a bigger
   bottom-right cut — the same silhouette as the NAYZEEE mark.
   Wrap one detail in A() to make it the accent in duotone mode.
   ═══════════════════════════════════════════════════════════ */

const n = v => +(+v).toFixed(2);
const P = d => `<path d="${d}"/>`;
const C = (cx, cy, r) => `<circle cx="${cx}" cy="${cy}" r="${r}"/>`;
const D = (cx, cy, r = 1.1) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="currentColor" stroke="none"/>`;
// accent: the one detail that turns teal in duotone mode
const A = el => el.replace(/^<(\w+)/, '<$1 class="a"');
// chamfered rectangle; br = the signature bottom-right cut
const R = (x, y, w, h, k = 1.5, br = k) =>
  P(`M${n(x + k)} ${y}H${n(x + w - k)}L${n(x + w)} ${n(y + k)}V${n(y + h - br)}L${n(x + w - br)} ${n(y + h)}H${n(x + k)}L${x} ${n(y + h - k)}V${n(y + k)}Z`);
const OCT = 'M8.3 3h7.4L21 8.3v7.4L15.7 21H8.3L3 15.7V8.3z';
const CAR = 'M5 16.5H2.5V13l2.8-1.2 3.2-4.3h6.8l3.7 4.3 2.5.9v3.8H19M9 16.5h6M5.3 11.8h13.5M12 7.5v4.3';

const I = [];
const add = (cat, name, svg, fa = [], tags = '') => I.push({ cat, name, svg: [].concat(svg).join(''), fa, tags });

/* ── Interface ── */
let c = 'Interface';
add(c, 'arrow-up', P('M12 20V4M5.5 10.5 12 4l6.5 6.5'), ['arrow-up']);
add(c, 'arrow-down', P('M12 4v16M5.5 13.5 12 20l6.5-6.5'), ['arrow-down']);
add(c, 'arrow-l', P('M20 12H4M10.5 5.5 4 12l6.5 6.5'), ['arrow-left'], 'arrow left back');
add(c, 'arrow-r', P('M4 12h16M13.5 5.5 20 12l-6.5 6.5'), ['arrow-right'], 'arrow right next');
add(c, 'arrow-ur', P('M6 18 18 6M8 6h10v10'), ['arrow-up-right-from-square'], 'external diagonal');
add(c, 'chev-u', P('m5 15 7-7 7 7'), ['chevron-up', 'angle-up']);
add(c, 'chev-d', P('m5 9 7 7 7-7'), ['chevron-down', 'angle-down', 'caret-down']);
add(c, 'chev-l', P('m15 5-7 7 7 7'), ['chevron-left', 'angle-left']);
add(c, 'chev-r', P('m9 5 7 7-7 7'), ['chevron-right', 'angle-right', 'caret-right']);
add(c, 'x', P('M6 6l12 12M18 6 6 18'), ['xmark', 'times', 'close', 'x'], 'close cancel');
add(c, 'check', P('M4 12.5 9.5 18 20 6'), ['check'], 'done ok tick');
add(c, 'plus', P('M12 5v14M5 12h14'), ['plus', 'add'], 'add new');
add(c, 'minus', P('M5 12h14'), ['minus'], 'remove');
add(c, 'search', [C(10.5, 10.5, 6.5), A(P('m15.5 15.5 5 5'))], ['magnifying-glass', 'search'], 'find');
add(c, 'filter', P('M4 6h16M7 12h10M10 18h4'), ['bars-staggered'], 'filter lines');
add(c, 'funnel', P('M3.5 4.5h17l-6.5 8v6l-4 2v-8z'), ['filter'], 'filter');
add(c, 'sliders', [P('M4 7h10M18 7h2M4 17h4M12 17h8'), A(C(16, 7, 2)), C(10, 17, 2)], ['sliders'], 'settings controls');
add(c, 'menu', P('M4 6h16M4 12h16M4 18h10'), ['bars', 'navicon'], 'hamburger');
add(c, 'more', [D(6, 12, 1.5), D(12, 12, 1.5), D(18, 12, 1.5)], ['ellipsis', 'ellipsis-h'], 'dots options');
add(c, 'more-v', [D(12, 6, 1.5), D(12, 12, 1.5), D(12, 18, 1.5)], ['ellipsis-vertical', 'ellipsis-v'], 'dots options');
add(c, 'grid', [R(3, 3, 7.5, 7.5, 1.2), R(13.5, 3, 7.5, 7.5, 1.2), R(3, 13.5, 7.5, 7.5, 1.2), A(R(13.5, 13.5, 7.5, 7.5, 1.2, 3.2))], ['grip', 'table-cells-large', 'th-large'], 'apps dashboard');
add(c, 'list', [D(4.5, 6, 1.2), D(4.5, 12, 1.2), D(4.5, 18, 1.2), P('M9 6h11M9 12h11M9 18h7')], ['list', 'list-ul']);
add(c, 'edit', [P('M14.5 4.5l5 5L9 20H4v-5z'), A(P('M12.5 6.5l5 5'))], ['pen', 'pencil', 'edit', 'pen-to-square'], 'pencil write');
add(c, 'trash', [P('M4 6.5h16M9 6.5V4h6v2.5M6 6.5l1 13.5h10l1-13.5'), A(P('M10 10.5v6M14 10.5v6'))], ['trash', 'trash-can', 'trash-alt'], 'delete bin');
add(c, 'copy', [R(8, 8, 12, 12, 1.5, 3.5), P('M16 8V5.5L14.5 4H5.5L4 5.5v9L5.5 16H8')], ['copy', 'clone'], 'duplicate');
add(c, 'save', [P('M4 5.5 5.5 4H16l4 4v10.5L18.5 20h-13L4 18.5z'), P('M8 4v4.5h7V4'), A(P('M7.5 20v-6h9v6'))], ['floppy-disk', 'save'], 'floppy');
add(c, 'download', [P('M12 4v11M7 10.5l5 5 5-5'), A(P('M4 20h16'))], ['download']);
add(c, 'upload', [P('M12 15V4M7 8.5l5-5 5 5'), A(P('M4 20h16'))], ['upload']);
add(c, 'lock', [R(5, 10.5, 14, 10, 1.5, 3.5), P('M8 10.5V8a4 4 0 0 1 8 0v2.5'), A(P('M12 14.5v2.5'))], ['lock'], 'locked secure');
add(c, 'unlock', [R(5, 10.5, 14, 10, 1.5, 3.5), P('M8 10.5V8a4 4 0 0 1 7.7-1.5'), A(P('M12 14.5v2.5'))], ['lock-open', 'unlock'], 'unlocked open');
add(c, 'eye', [P('M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z'), A(C(12, 12, 3))], ['eye'], 'view show spectate');
add(c, 'eye-off', [P('M9.9 5.8A9.6 9.6 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-2.6 3.4M6.2 7.2A16 16 0 0 0 2.5 12s3.5 6.5 9.5 6.5a9 9 0 0 0 4.8-1.4M10 10a3 3 0 0 0 4 4'), A(P('M4 4l16 16'))], ['eye-slash'], 'hide invisible');
add(c, 'bell', [P('M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15z'), A(P('M10 21h4'))], ['bell'], 'notification alert');
add(c, 'info', [P(OCT), A(P('M12 11v5.5')), D(12, 7.8)], ['circle-info', 'info-circle', 'info'], 'information');
add(c, 'alert', [P('M10.3 4 2.6 17.5A1.9 1.9 0 0 0 4.3 20.5h15.4a1.9 1.9 0 0 0 1.7-3L13.7 4a2 2 0 0 0-3.4 0z'), A(P('M12 9.5v4.5')), D(12, 17)], ['triangle-exclamation', 'exclamation-triangle', 'warning'], 'warning');
add(c, 'error', [P(OCT), A(P('M12 7.5v5.5')), D(12, 16.3)], ['circle-exclamation', 'exclamation-circle'], 'danger');
add(c, 'help', [P(OCT), A(P('M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6')), D(12, 16.8)], ['circle-question', 'question-circle', 'question'], 'question');
add(c, 'success', [P(OCT), A(P('M8 12.2l2.8 2.8L16 9.5'))], ['circle-check', 'check-circle'], 'ok done');
add(c, 'home', [P('M3.5 11 12 4l8.5 7'), P('M5.5 9.5V20h5v-5.5h3V20h5V9.5')], ['house', 'home'], 'house');
add(c, 'refresh', P('M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6'), ['rotate-right', 'arrows-rotate', 'refresh', 'sync'], 'reload');
add(c, 'rot-l', P('M4 4v5h5M4.6 9A8 8 0 1 1 6 17'), ['rotate-left', 'undo'], 'rotate undo');
add(c, 'rot-r', P('M20 4v5h-5M19.4 9A8 8 0 1 0 18 17'), ['rotate-right', 'redo'], 'rotate redo');
add(c, 'history', [P('M3.5 12a8.5 8.5 0 1 0 2.5-6M3.5 4v4.5H8'), A(P('M12 7.5V12l3 2'))], ['clock-rotate-left', 'history'], 'recent past');
add(c, 'external', [P('M13.5 4H20v6.5M20 4l-9 9'), P('M18 14v4.5L16.5 20h-11L4 18.5v-11L5.5 6H10')], ['up-right-from-square', 'external-link'], 'open link');
add(c, 'link', P('M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1'), ['link', 'chain'], 'url');
add(c, 'login', [P('M14 4h4.5L20 5.5v13L18.5 20H14'), A(P('M10 16l4-4-4-4M14 12H4'))], ['right-to-bracket', 'sign-in'], 'enter join');
add(c, 'logout', [P('M10 4H5.5L4 5.5v13L5.5 20H10'), A(P('M16 16l4-4-4-4M20 12H9'))], ['right-from-bracket', 'sign-out'], 'exit leave');
add(c, 'power', [P('M7 6a7.5 7.5 0 1 0 10 0'), A(P('M12 3v8'))], ['power-off'], 'on off engine');
add(c, 'clock', [C(12, 12, 9), A(P('M12 7v5l3.5 2'))], ['clock'], 'time');
add(c, 'timer', [C(12, 13.5, 7.5), P('M9.5 2.5h5'), A(P('M12 9.5v4l2.5 1.5'))], ['stopwatch', 'hourglass'], 'countdown');
add(c, 'calendar', [R(3.5, 5, 17, 15.5, 1.5, 3.5), P('M3.5 10h17M8 3v4M16 3v4'), A(R(7, 13, 3, 3, .5))], ['calendar', 'calendar-days'], 'date');
add(c, 'star', P('m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.8l-5.2 2.8 1-5.8-4.3-4.1 5.9-.9z'), ['star'], 'favourite');
add(c, 'cog', [P('M10.3 3h3.4l.6 2.4 1.6.9 2.4-.7 1.7 2.9-1.8 1.7v1.6l1.8 1.7-1.7 2.9-2.4-.7-1.6.9-.6 2.4h-3.4l-.6-2.4-1.6-.9-2.4.7-1.7-2.9 1.8-1.7v-1.6L3.6 8.5l1.7-2.9 2.4.7 1.6-.9z'), A(C(12, 12, 3))], ['gear', 'cog', 'gears'], 'settings');
add(c, 'swap', P('M7 4 3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7'), ['right-left', 'exchange', 'arrows-left-right'], 'transfer exchange');
add(c, 'sortd', [P('M7 4v16M3.5 16.5 7 20l3.5-3.5'), A(P('M13 6h8M13 12h6M13 18h3'))], ['arrow-down-wide-short', 'sort-amount-down'], 'sort descending');
add(c, 'sortu', [P('M7 20V4M3.5 7.5 7 4l3.5 3.5'), A(P('M13 6h3M13 12h6M13 18h8'))], ['arrow-up-wide-short', 'sort-amount-up'], 'sort ascending');
add(c, 'play', P('M7 4.5v15l12-7.5z'), ['play'], 'start');
add(c, 'pause', P('M8 5v14M16 5v14'), ['pause']);
add(c, 'target', [C(12, 12, 8), C(12, 12, 4), A(D(12, 12, 1.4)), P('M12 2v3M12 19v3M2 12h3M19 12h3')], ['crosshairs', 'bullseye'], 'aim crosshair');
add(c, 'flag', [P('M5 21V4'), A(P('M5 4h12l-2.5 4.5L17 13H5'))], ['flag'], 'report mark');
add(c, 'ruler', [R(2.5, 8, 19, 8, 1.5, 3), A(P('M7 8v3.5M10.5 8v2M14 8v3.5M17.5 8v2'))], ['ruler', 'ruler-horizontal'], 'height measure');
add(c, 'percent', [P('M5 19 19 5'), C(7, 7, 2.5), A(C(17, 17, 2.5))], ['percent'], 'discount tax');
add(c, 'keyboard', [R(2.5, 6, 19, 12, 1.5, 3), A(P('M7 14.5h10')), D(6.5, 10, .9), D(10, 10, .9), D(13.5, 10, .9), D(17, 10, .9)], ['keyboard'], 'keys input');
add(c, 'mouse', [P('M12 3a6 6 0 0 1 6 6v6a6 6 0 0 1-12 0V9a6 6 0 0 1 6-6z'), A(P('M12 7v3.5'))], ['computer-mouse', 'mouse'], 'click');

/* ── People ── */
c = 'People';
add(c, 'user', [C(12, 8, 4), P('M4.5 20.5a7.5 7.5 0 0 1 15 0')], ['user'], 'player profile');
add(c, 'users', [C(9, 8, 3.2), P('M3 20a6 6 0 0 1 12 0'), A(P('M15.5 4.8a3.2 3.2 0 0 1 0 6.4M17.5 14.2A6 6 0 0 1 21 20'))], ['users', 'user-group'], 'players group team');
add(c, 'user-plus', [C(9.5, 8, 3.8), P('M3 20.5a6.5 6.5 0 0 1 13 0'), A(P('M19 8v6M16 11h6'))], ['user-plus'], 'hire add invite');
add(c, 'user-x', [C(9.5, 8, 3.8), P('M3 20.5a6.5 6.5 0 0 1 13 0'), A(P('M17 8.5l4 4M21 8.5l-4 4'))], ['user-xmark', 'user-times', 'user-minus'], 'fire kick remove');
add(c, 'person', [C(12, 4.8, 2.2), P('M12 7.5v7M7.5 10.5h9'), A(P('M12 14.5 9 21M12 14.5l3 6.5'))], ['person', 'male', 'child'], 'body ped');
add(c, 'id', [R(2.5, 5, 19, 14, 1.5, 3.5), C(8.5, 11, 2.2), P('M5.5 16.2a3 3 0 0 1 6 0'), A(P('M14 10h4.5M14 13.5h3'))], ['id-card', 'address-card'], 'identity license');
add(c, 'badge', [P('M12 3 5 6v5c0 4.5 3 8 7 10 4-2 7-5.5 7-10V6z'), A(P('m12 8.5 1.1 2.2 2.4.4-1.7 1.7.4 2.4-2.2-1.1-2.2 1.1.4-2.4-1.7-1.7 2.4-.4z'))], ['shield-halved', 'certificate'], 'police sheriff job');
add(c, 'crown', [P('M3.5 8 7.5 12 12 5l4.5 7 4-4-1.5 10.5h-14z'), A(P('M5.5 21h13'))], ['crown'], 'owner vip admin');
add(c, 'face', [P('M12 3C8 3 5.5 6 5.5 10.5c0 5 3 10.5 6.5 10.5s6.5-5.5 6.5-10.5C18.5 6 16 3 12 3z'), D(9.5, 10.5, .9), D(14.5, 10.5, .9), A(P('M10 15.5c1.2.8 2.8.8 4 0'))], ['face-smile', 'user-astronaut'], 'head appearance');
add(c, 'smile', [C(12, 12, 9), D(9, 9.8, .9), D(15, 9.8, .9), A(P('M8.5 14a4.5 4.5 0 0 0 7 0'))], ['face-smile', 'smile'], 'emote happy');
add(c, 'hand', P('M8 13V5.5a1.5 1.5 0 0 1 3 0V11M11 10V4.5a1.5 1.5 0 0 1 3 0V11M14 10.5V6a1.5 1.5 0 0 1 3 0v7c0 4.5-2.5 8-6.5 8-2.5 0-4-1.3-5.5-3.5L3.5 14a1.5 1.5 0 0 1 2.5-1.5L8 15'), ['hand', 'hand-paper'], 'use interact stop');
add(c, 'wave', P('M7 11V6.5a1.5 1.5 0 0 1 3 0V11M10 10.5V4.5a1.5 1.5 0 0 1 3 0V11M13 11V6a1.5 1.5 0 0 1 3 0v7c0 4.5-2.5 8-6 8-2.5 0-4-1.3-5.5-3.5L3 14.5M18 3.5c1.5.8 2.5 2.2 2.8 4'), ['hand-wave', 'hands'], 'emote hello');
add(c, 'walk', [C(13, 4.5, 1.8), P('m9 21 2.5-6 2.5 2.5V21M8 12l2-4.5 3.5 1 2 3.5 2.5 1M11.5 15 13 8.5')], ['person-walking', 'walking'], 'walkstyle');
add(c, 'sit', [C(9, 4.5, 1.8), P('M9 8v6h6l2 6M9 11h5'), A(P('M5 21h14'))], ['chair'], 'emote seat');
add(c, 'dance', [C(12, 4.5, 1.8), P('M6 9l6 1 5-3M12 10v5l-3 6M12 15l4 2 1 4')], ['person-running'], 'emote');

/* ── Status & HUD ── */
c = 'Status';
add(c, 'heart', P('M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.4a4.3 4.3 0 0 1 7.5 2.4C19.5 15.4 12 20 12 20z'), ['heart'], 'health hp');
add(c, 'pulse', [P('M3 12.5h3.5l2-5 3.5 10 2.5-7 1.5 2H21')], ['heart-pulse', 'wave-square'], 'vitals ems');
add(c, 'shield', P('M12 3 4.5 5.5v6c0 4.6 3.2 8 7.5 9.5 4.3-1.5 7.5-4.9 7.5-9.5v-6z'), ['shield'], 'armor armour');
add(c, 'shield-check', [P('M12 3 4.5 5.5v6c0 4.6 3.2 8 7.5 9.5 4.3-1.5 7.5-4.9 7.5-9.5v-6z'), A(P('m8.5 12 2.5 2.5 4.5-5'))], ['shield-check', 'user-shield'], 'secure verified admin');
add(c, 'food', [P('M4 11a8 6 0 0 1 16 0z'), A(P('M3.5 14.5h17')), P('M5 18.5h14l1-1.5H4z')], ['burger', 'hamburger', 'utensils'], 'hunger eat');
add(c, 'drop', P('M12 3.5s6 6.6 6 11a6 6 0 0 1-12 0c0-4.4 6-11 6-11z'), ['droplet', 'tint', 'water'], 'thirst water');
add(c, 'bolt', P('M13 3 5 13.5h6L10 21l8-10.5h-6z'), ['bolt', 'bolt-lightning'], 'stamina energy power');
add(c, 'brain', P('M9 4.5a3 3 0 0 0-3 3 3 3 0 0 0-2 5 3 3 0 0 0 2 5 3 3 0 0 0 6 1.5V6a2 2 0 0 0-3-1.5zM15 4.5a3 3 0 0 1 3 3 3 3 0 0 1 2 5 3 3 0 0 1-2 5 3 3 0 0 1-6 1.5'), ['brain'], 'stress mind');
add(c, 'thermo', [P('M10 4.5a2 2 0 0 1 4 0v9.5a4 4 0 1 1-4 0z'), A(P('M12 10v7'))], ['temperature-half', 'thermometer'], 'temperature');
add(c, 'wind', [P('M3 8h11a3 3 0 1 0-3-3'), A(P('M3 12h15a3 3 0 1 1-3 3')), P('M3 16h7')], ['wind'], 'oxygen weather');
add(c, 'mic', [R(9, 3, 6, 11, 2.5), P('M5.5 11a6.5 6.5 0 0 0 13 0'), A(P('M12 17.5V21'))], ['microphone'], 'voice talk');
add(c, 'mic-off', [P('M15 9.5V5.5a3 3 0 0 0-5.9-.8M9 9v2a3 3 0 0 0 5 2.2M5.5 11a6.5 6.5 0 0 0 10.6 5M18.5 11a6.5 6.5 0 0 1-.6 2.7M12 17.5V21'), A(P('M4 4l16 16'))], ['microphone-slash'], 'muted');
add(c, 'volume', [P('M4 9.5h3.5L12 5.5v13l-4.5-4H4z'), A(P('M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11'))], ['volume-high', 'volume-up'], 'sound audio');
add(c, 'mute', [P('M4 9.5h3.5L12 5.5v13l-4.5-4H4z'), A(P('M16 9.5l5 5M21 9.5l-5 5'))], ['volume-xmark', 'volume-mute'], 'silent');
add(c, 'seat', [P('M5.5 3h4.5l2 10h6.5L20 14.5V20H7.5z'), A(P('M7 7.5l11 6'))], ['user-slash'], 'seatbelt belt');
add(c, 'signal', [P('M5 19v-3M10 19v-6M15 19v-9'), A(P('M20 19V6'))], ['signal'], 'ping network');
add(c, 'wifi', [P('M3 9a13 13 0 0 1 18 0M6 12.5a8.5 8.5 0 0 1 12 0M9 16a4 4 0 0 1 6 0'), A(D(12, 19.5, 1.2))], ['wifi'], 'network internet');
add(c, 'battery', [R(2.5, 8, 17, 8, 1.2, 2.5), P('M21.5 11v2'), A(P('M5.5 11v2M8.5 11v2M11.5 11v2'))], ['battery-three-quarters', 'battery'], 'charge power');
add(c, 'gauge', [P('M4.5 17a8.5 8.5 0 1 1 15 0'), A(P('m12 13 4-4')), D(12, 13, 1.3)], ['gauge', 'tachometer-alt', 'gauge-high'], 'speed speedometer');

/* ── Vehicles ── */
c = 'Vehicles';
add(c, 'car', [P(CAR), A(C(7, 16.5, 2)), C(17, 16.5, 2)], ['car', 'car-side'], 'vehicle');
add(c, 'taxi', [P(CAR), A(R(10, 4, 4, 2.4, .5)), C(7, 16.5, 2), C(17, 16.5, 2)], ['taxi', 'cab'], 'cab job');
add(c, 'truck', [R(2.5, 6, 11, 10.5, 1, 1), P('M13.5 9.5h4l3 3.5v3.5h-7'), A(C(6.5, 17.5, 2)), C(17, 17.5, 2)], ['truck'], 'trucker delivery lorry');
add(c, 'motorbike', [C(5.5, 16.5, 3.2), A(C(18.5, 16.5, 3.2)), P('M5.5 16.5h6l3-5.5H8l-2 2.5M14.5 11l4 5.5M14.5 11l-1-3.5h3')], ['motorcycle'], 'bike');
add(c, 'bicycle', [C(5.5, 16.5, 3.5), C(18.5, 16.5, 3.5), A(P('M5.5 16.5H12L9.5 9H16l2.5 7.5M5.5 16.5 9.5 9M12 16.5 16 9')), P('M9.5 9 9 7M7.5 7h3M16 9l-.8-2.5H17')], ['bicycle'], 'bmx');
add(c, 'boat', [P('M3 15h18l-2.5 4.5h-13z'), A(P('M12 3v12M12 4l6 8h-6'))], ['ship', 'sailboat'], 'sea water');
add(c, 'heli', [P('M5 4.5h15M12.5 4.5v3'), P('M8.5 7.5h6.5a5 5 0 0 1 5 5V15h-8.5a3 3 0 0 1-3-3z'), A(P('M15 7.5V11h5')), P('M8.5 10.5H3M3 8.5v4M10.5 19h10M12.5 15v4M18 15v4')], ['helicopter'], 'air');
add(c, 'plane', P('M21 12c0-1-1-1.5-2-1.5h-5L9 3H7l2.5 7.5H5L3.5 8.5H2l1 3.5-1 3.5h1.5L5 13.5h4.5L7 21h2l5-7.5h5c1 0 2-.5 2-1.5z'), ['plane'], 'air flight airport');
add(c, 'fuel', [P('M5 20V5.5L6.5 4h7L15 5.5V20M3.5 20h13'), A(P('M5 10h10')), P('M15 8h1.5L18.5 10v6.5a1.5 1.5 0 0 0 3 0V9l-3-3')], ['gas-pump'], 'gas petrol station');
add(c, 'key', [C(8, 15, 4), A(P('m11 12 8.5-8.5M16 7l2.5 2.5M14 9l2 2'))], ['key'], 'keys lock');
add(c, 'engine', P('M4 10v6M4 13h2M6 9h3V7h5v2h2l2 2h2v6h-2l-2 2H8l-2-2V9z'), ['engine', 'gears'], 'motor');
add(c, 'wheel', [C(12, 12, 9), A(C(12, 12, 3)), P('M12 3v6M12 15v6M3 12h6M15 12h6')], ['life-ring', 'circle-dot'], 'tyre tire rim');
add(c, 'wrench', P('M15 4.5a4.5 4.5 0 0 0-5.6 5.6L4 15.5V20h4.5l5.4-5.4a4.5 4.5 0 0 0 5.6-5.6L17 11.5 13.5 11 13 7.5z'), ['wrench', 'screwdriver-wrench'], 'repair mechanic fix');
add(c, 'garage', [P('M3 9.5 12 4l9 5.5V20H3z'), A(P('M7 20v-7h10v7M7 15.5h10M7 18h10'))], ['warehouse', 'garage'], 'park storage');
add(c, 'light', P('M14 6c-4 0-6 2.5-6 6s2 6 6 6h2V6zM3 8h3M3 12h3M3 16h3'), ['lightbulb'], 'headlights');
add(c, 'door', [P('M6 21V4.5L7.5 3h9L18 4.5V21M3.5 21h17'), A(P('M14.5 12v.5'))], ['door-open', 'door-closed'], 'enter house');
add(c, 'window', [R(4, 4, 16, 16, 1.5, 3), A(P('M4 12h16M12 4v16'))], ['window-maximize', 'border-all'], 'glass');
add(c, 'hood', [P('M3.5 13.5 6 8h12l2.5 5.5V18h-17z'), A(P('M6 8 9 3.5h6L18 8')), D(7, 14.5, 1.1), D(17, 14.5, 1.1)], ['car-rear'], 'bonnet');
add(c, 'trunk', [P('M3 10h18v8H3zM5 10l2-4h10l2 4'), A(P('M10 14h4'))], ['box-open'], 'boot storage');
add(c, 'nav', P('M12 3 19 20l-7-4-7 4z'), ['location-arrow', 'compass'], 'gps navigate');
add(c, 'route', [C(6, 18, 2.5), A(C(18, 6, 2.5)), P('M8.5 18H15a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h6.5')], ['route', 'road'], 'waypoint path');
add(c, 'siren', [P('M6 17v-5a6 6 0 0 1 12 0v5'), R(4, 17, 16, 3.5, 1), A(P('M12 2.5V4M4.5 5.5l1 1M19.5 5.5l-1 1M2.5 11.5H4M20 11.5h1.5'))], ['bell-concierge', 'land-mine-on'], 'emergency dispatch alarm');

/* ── Jobs & crafting ── */
c = 'Jobs';
add(c, 'medkit', [R(3.5, 6, 17, 14.5, 1.5, 3.5), P('M9 6V4h6v2'), A(P('M12 10v6.5M8.75 13.25h6.5'))], ['kit-medical', 'medkit', 'briefcase-medical'], 'ems doctor first aid');
add(c, 'cuff', [C(7, 14, 4), C(17, 14, 4), A(P('M10.5 12.5h3')), P('M7 10V7.5L8.5 6h7L17 7.5V10')], ['handcuffs'], 'police arrest');
add(c, 'flame', P('M12 21a6 6 0 0 0 6-6c0-4.5-4-6.5-4.5-11-2.5 2-4.5 4.5-4.5 7.5a3 3 0 0 1-1.5-2.5C6.5 10.5 6 13 6 15a6 6 0 0 0 6 6z'), ['fire', 'fire-flame-curved'], 'fire burn');
add(c, 'box', [P('M3.5 7.5 12 3l8.5 4.5v9L12 21l-8.5-4.5z'), A(P('M3.5 7.5 12 12l8.5-4.5M12 12v9'))], ['box', 'cube', 'box-archive'], 'package delivery item');
add(c, 'crate', [R(3.5, 3.5, 17, 17, 1, 3.5), A(P('M3.5 9.5h17M3.5 14.5h17')), P('M9 3.5v6M15 14.5v6')], ['boxes-stacked', 'pallet'], 'storage stash');
add(c, 'fish', [P('M3 12c3-4.5 9-6 13.5-2L21 7v10l-4.5-3C12 18 6 16.5 3 12z'), A(D(7.5, 11, 1))], ['fish'], 'fishing');
add(c, 'pickaxe', [P('M4 9.5C8.5 4.5 15.5 4 20 8'), A(P('M13 6.3 5.5 21'))], ['hammer', 'pickaxe'], 'mining');
add(c, 'leaf', [P('M5 19C5 10 10 5 20 4c-1 10-6 15-15 15z'), A(P('M5 19 13 11'))], ['leaf', 'seedling'], 'farming weed plant');
add(c, 'chef', [P('M7 13.5A4 4 0 0 1 8 5.7a4.5 4.5 0 0 1 8 0 4 4 0 0 1 1 7.8V20H7z'), A(P('M7 17h10'))], ['utensils', 'kitchen-set'], 'cook restaurant');
add(c, 'pan', [P('M2.5 10.5h14a6 6 0 0 1-6 6h-2a6 6 0 0 1-6-6z'), A(P('M16.5 11.5H22')), P('M7 4.5c0 1.5 1 1.5 1 3M11 4.5c0 1.5 1 1.5 1 3')], ['bowl-food'], 'cook kitchen');
add(c, 'gavel', [P('M14.5 3 21 9.5l-3 3L11.5 6z'), A(P('M14 9.5 4 19.5')), P('M3 21h9')], ['gavel'], 'lawyer judge court');
add(c, 'hammer', [P('M14 4l6 6-2.5 2.5-6-6z'), A(P('M12.7 8.8 3.5 18a1.8 1.8 0 0 0 2.5 2.5l9.2-9.2'))], ['hammer'], 'build craft');
add(c, 'scissors', [C(6, 6.5, 2.5), C(6, 17.5, 2.5), A(P('M8 8.2 20 18M8 15.8 20 6'))], ['scissors'], 'barber cut');
add(c, 'briefcase', [R(3, 7, 18, 13, 1.5, 3.5), P('M8.5 7V5.5L10 4h4l1.5 1.5V7'), A(P('M3 12.5h18'))], ['briefcase'], 'job work business');
add(c, 'camera', [P('M4 8h3l1.5-2.5h7L17 8h3v9.5L18.5 19h-14.5z'), A(C(12, 13, 3.5))], ['camera'], 'photo news');
add(c, 'flask', [P('M9 3h6M10 3v6l-5.5 9.5A1.7 1.7 0 0 0 6 21h12a1.7 1.7 0 0 0 1.5-2.5L14 9V3'), A(P('M7 15h10'))], ['flask', 'vial'], 'lab chemistry drug');
add(c, 'ingot', [P('M3.5 18.5h17l-3-8h-11z'), A(P('M7.5 10.5l1-3.5h7l1 3.5'))], ['bars-progress'], 'gold metal bar');
add(c, 'spring', [P('M7 4h10M7 20h10'), A(P('M17 4 7 7.5l10 3.5-10 3.5 10 3.5'))], ['bars'], 'part coil');
add(c, 'chip', [R(6, 6, 12, 12, 1.5, 3), A(R(9.5, 9.5, 5, 5, .8)), P('M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3')], ['microchip'], 'electronics hack');
add(c, 'scale', [P('M12 4v16M8 20h8M5 7h14'), P('M5 7l-3 6a3 3 0 0 0 6 0z'), A(P('M19 7l-3 6a3 3 0 0 0 6 0z'))], ['scale-balanced', 'balance-scale'], 'weight law');
add(c, 'barrel', [P('M6 3.5h12c1 3 1.5 5.5 1.5 8.5s-.5 5.5-1.5 8.5H6C5 17.5 4.5 15 4.5 12S5 6.5 6 3.5z'), A(P('M5 8h14M5 16h14'))], ['oil-can', 'drum'], 'oil storage');
add(c, 'ammo', [P('M5 20V10a2 2 0 0 1 4 0v10M10 20V8a2 2 0 0 1 4 0v12M15 20V10a2 2 0 0 1 4 0v10'), A(P('M3.5 20.5h17'))], ['person-rifle'], 'bullets rounds');
add(c, 'powder', [P('M9 3h6M10 3v3.5L6 11v8.5L7.5 21h9l1.5-1.5V11l-4-4.5V3'), A(P('M6 14h12'))], ['sack-xmark', 'jar'], 'bag chemical');
add(c, 'drill', [R(3, 7, 12, 7, 1, 1), P('M15 9h4M15 12h4'), A(P('M19 10.5h2.5')), P('M6 14l-1 7h4l1-7')], ['screwdriver'], 'tool heist');

/* ── Money ── */
c = 'Money';
add(c, 'cash', [R(2.5, 6, 19, 12, 1.5, 3), A(C(12, 12, 2.5)), D(6, 9.5, .9), D(18, 14.5, .9)], ['money-bill', 'money-bill-wave'], 'money dollars');
add(c, 'card', [R(2.5, 5, 19, 14, 1.5, 3.5), P('M2.5 10h19'), A(P('M6.5 15h4'))], ['credit-card'], 'bank payment');
add(c, 'bank', [P('M3 9.5 12 4l9 5.5'), A(P('M4.5 10v8M9.5 10v8M14.5 10v8M19.5 10v8')), P('M3 20.5h18')], ['building-columns', 'university', 'landmark'], 'finance');
add(c, 'wallet', [P('M18 7.5V5.5L16.5 4h-11L4 5.5v13L5.5 20h12.5l2-2v-9L18.5 7.5H5.5'), A(D(16, 13.75, 1.2))], ['wallet'], 'money');
add(c, 'coin', [C(12, 12, 8.5), A(P('M12 6.5v11M14.5 8.8h-3.3a1.7 1.7 0 0 0 0 3.4h1.6a1.7 1.7 0 0 1 0 3.4H9.5'))], ['coins', 'circle-dollar-to-slot', 'dollar-sign'], 'dollar money');
add(c, 'receipt', [P('M6 3h12v18l-2.5-1.5L13 21l-2.5-1.5L8 21l-2-1.5z'), A(P('M9 8h6M9 12h6M9 16h3'))], ['receipt', 'file-invoice'], 'bill invoice');
add(c, 'chart', [P('M4 20.5h16'), R(5.5, 12, 3, 8.5, .6), A(R(10.5, 6, 3, 14.5, .6)), R(15.5, 14, 3, 6.5, .6)], ['chart-column', 'chart-bar'], 'stats graph');
add(c, 'trend-up', [P('M3 17l6-6 4 4 8-8'), A(P('M15 7h6v6'))], ['arrow-trend-up', 'chart-line'], 'profit increase');
add(c, 'trend-down', [P('M3 7l6 6 4-4 8 8'), A(P('M15 17h6v-6'))], ['arrow-trend-down'], 'loss decrease');
add(c, 'dep', [P('M12 3v11M7.5 9.5 12 14l4.5-4.5'), A(P('M4 14v4.5L5.5 20h13l1.5-1.5V14'))], ['money-bill-transfer', 'piggy-bank'], 'deposit');
add(c, 'wd', [P('M12 14V3M7.5 7.5 12 3l4.5 4.5'), A(P('M4 14v4.5L5.5 20h13l1.5-1.5V14'))], ['hand-holding-dollar'], 'withdraw');
add(c, 'cart', [P('M3 4h2.2l2.1 10.5a1.5 1.5 0 0 0 1.5 1.2h8.4a1.5 1.5 0 0 0 1.5-1.1L20.5 8H6'), A(D(9.5, 19.5, 1.4)), D(17, 19.5, 1.4)], ['cart-shopping', 'shopping-cart'], 'shop basket');
add(c, 'bag', [P('M5 8h14l-1 12.5H6z'), A(P('M9 8V6.5a3 3 0 0 1 6 0V8'))], ['bag-shopping', 'shopping-bag'], 'shop store');
add(c, 'tag', [P('M3.5 12.5V4h8.5l8.5 8.5-8.5 8.5z'), A(C(8, 8.5, 1.3))], ['tag', 'tags'], 'price label');
add(c, 'gem', [P('M7 4h10l4 5-9 11L3 9z'), A(P('M3 9h18M9.5 4 8 9l4 11 4-11-1.5-5'))], ['gem', 'diamond'], 'jewel heist');
add(c, 'store', [P('M4 9.5 5.5 4h13L20 9.5'), P('M4 9.5a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0 2.7 2.7 0 0 0 5.3 0M5.5 12v8.5h13V12'), A(P('M10 20.5v-5h4v5'))], ['store', 'shop'], 'shop market');

/* ── Items ── */
c = 'Items';
add(c, 'phone', [R(6.5, 2.5, 11, 19, 1.5, 3), A(P('M10.5 18.5h3'))], ['mobile-screen', 'mobile', 'phone'], 'mobile cell');
add(c, 'call', P('M5 4h4l1.5 4.5-2.5 1.5a11 11 0 0 0 6 6l1.5-2.5L20 15v4a1.5 1.5 0 0 1-1.5 1.5A16.5 16.5 0 0 1 3.5 5.5 1.5 1.5 0 0 1 5 4z'), ['phone', 'phone-flip'], 'call ring');
add(c, 'radio', [R(5, 8, 14, 13, 1.5, 3), P('M8 8l7-5'), A(P('M9 12h6M9 15.5h2'))], ['walkie-talkie', 'radio'], 'comms');
add(c, 'pistol', [P('M3 7h15.5L20 8.5V11h-5.5l-1.5 2.5h-3l-1.5 6H4.5l1.8-8.5H3z'), A(P('M10 13.5h3'))], ['gun'], 'weapon gun firearm');
add(c, 'knife', [A(P('M3.5 20.5 10 14')), P('M10 14 20.5 3.5c.5 4-2.5 8.5-6.5 11.5z')], ['utensils', 'knife'], 'weapon blade');
add(c, 'bandage', [P('m4.9 13.4 8.5-8.5a3.5 3.5 0 0 1 5 5l-8.5 8.5a3.5 3.5 0 0 1-5-5z'), A(P('M10.5 10.5h.01M13.5 13.5h.01M10.5 13.5h.01M13.5 10.5h.01'))], ['band-aid', 'bandage'], 'heal medical');
add(c, 'pill', [P('m5.5 18.5-.5-.5a4.2 4.2 0 0 1 0-6L12 5a4.2 4.2 0 0 1 6 6l-7 7a4.2 4.2 0 0 1-5.5.5z'), A(P('m8.5 8.5 7 7'))], ['pills', 'capsules', 'prescription-bottle'], 'medicine drug');
add(c, 'syringe', [P('M14.5 4.5l5 5M17 7l-9.5 9.5H5v-2.5L14.5 4.5'), A(P('M11 8l1.5 1.5M8.5 10.5 10 12')), P('M5 19l-2 2')], ['syringe'], 'injection adrenaline');
add(c, 'bottle', [P('M10 2.5h4M10.5 2.5v4L8 10v10.5L9.5 21h5l1.5-1.5V10l-2.5-3.5v-4'), A(P('M8 14h8'))], ['bottle-water', 'wine-bottle'], 'drink');
add(c, 'coffee', [P('M5 9h11v6.5A4.5 4.5 0 0 1 11.5 20h-2A4.5 4.5 0 0 1 5 15.5z'), P('M16 11h1.5a2.5 2.5 0 0 1 0 5H16'), A(P('M8.5 3.5V6M12.5 3.5V6'))], ['mug-hot', 'coffee'], 'drink cafe');
add(c, 'laptop', [R(4.5, 4.5, 15, 11, 1, 2.5), A(P('M2 19.5h20'))], ['laptop'], 'computer hack');
add(c, 'usb', [R(7, 9, 10, 12, 1, 2.5), R(9, 3, 6, 6, .6), A(P('M10.5 5.5h.01M13.5 5.5h.01'))], ['usb', 'hard-drive'], 'drive data');
add(c, 'keycard', [R(6, 2.5, 12, 19, 1.5, 3.5), P('M10 6.5h4'), A(R(9, 11, 6, 4.5, .6))], ['id-badge'], 'access security');
add(c, 'backpack', [P('M8 7V5.5L9.5 4h5L16 5.5V7'), R(5, 7, 14, 14, 2, 4), A(R(8.5, 13, 7, 4.5, .8))], ['backpack', 'suitcase'], 'bag inventory');
add(c, 'dice', [R(4, 4, 16, 16, 2, 4), D(8.5, 8.5, 1.3), A(D(12, 12, 1.3)), D(15.5, 15.5, 1.3)], ['dice', 'dice-three'], 'casino gamble');
add(c, 'note', [P('M5 4h14v11l-5 5H5z'), A(P('M14 20v-5h5')), P('M9 9h6M9 12.5h4')], ['note-sticky', 'sticky-note'], 'notes memo');
add(c, 'file', [P('M14 3H6.5L5 4.5v15L6.5 21h11l1.5-1.5V8z'), A(P('M14 3v5h5'))], ['file', 'file-lines'], 'document report');
add(c, 'clipboard', [R(5, 4, 14, 17, 1.5, 3), P('M9 3h6v3H9z'), A(P('M9 12h6M9 16h4'))], ['clipboard', 'clipboard-list'], 'report checklist');
add(c, 'palette', [P('M12 3.5a8.5 8.5 0 0 0 0 17c1.2 0 1.8-.8 1.8-1.7 0-1.4-1.2-1.6-1.2-2.8 0-.9.7-1.5 1.6-1.5h2.3a4 4 0 0 0 4-4C20.5 6.8 16.7 3.5 12 3.5z'), A(D(7.5, 11, 1.1)), D(10, 7.5, 1.1), D(14.5, 7.5, 1.1)], ['palette'], 'paint colour');

/* ── Clothing ── */
c = 'Clothing';
add(c, 'shirt', P('M8.5 3.5 4 6l1.5 4.5L7 10v10.5h10V10l1.5.5L20 6l-4.5-2.5a3.5 3.5 0 0 1-7 0z'), ['shirt', 'tshirt'], 'clothes top');
add(c, 'tank', P('M8.5 3v3.5a3.5 3.5 0 0 0 7 0V3M8.5 3 6 4.5V21h12V4.5L15.5 3'), ['vest'], 'undershirt top');
add(c, 'pants', [P('M6 3h12l1.5 18h-5L12 10l-2.5 11h-5z'), A(P('M6.3 6.5h11.4'))], ['person-dress'], 'legs trousers');
add(c, 'shoe', [P('M3 17v-6l3-1 3 3 5 1 6 1.5a2 2 0 0 1 1 1.5H3z'), A(P('M3 19.5h18'))], ['shoe-prints'], 'feet');
add(c, 'hat', [P('M6 16.5 7.5 8a2 2 0 0 1 2-1.5h5a2 2 0 0 1 2 1.5L18 16.5'), A(P('M3 17c3-1.5 15-1.5 18 0'))], ['hat-cowboy', 'graduation-cap'], 'cap head');
add(c, 'glasses', [C(6.5, 14, 3.5), A(C(17.5, 14, 3.5)), P('M10 14h4M3 14l1-5M21 14l-1-5')], ['glasses'], 'eyewear');
add(c, 'mask', [P('M4 8c3-2 13-2 16 0v4c0 4-4 7-8 7s-8-3-8-7z'), A(P('M8 11.5h2M14 11.5h2'))], ['mask', 'masks-theater'], 'face cover');
add(c, 'glove', P('M7 21v-5.5L4.6 11.7a1.5 1.5 0 0 1 2.5-1.6L8 11.5V5.5a1.5 1.5 0 0 1 3 0V10V4.5a1.5 1.5 0 0 1 3 0V10V6a1.5 1.5 0 0 1 3 0v9l-2 6z'), ['mitten'], 'arms hands');
add(c, 'chain', [P('M5 4c0 7 3 11 7 11s7-4 7-11'), A(P('m12 15-2 2.5 2 3 2-3z'))], ['link'], 'necklace accessory');
add(c, 'hanger', [P('M12 7.5a2 2 0 1 0-2-2'), A(P('M12 7.5V9L3.4 15.2a1 1 0 0 0 .6 1.8h16a1 1 0 0 0 .6-1.8L12 9'))], ['shirt'], 'outfit wardrobe');

/* ── World ── */
c = 'World';
add(c, 'pin', [P('M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z'), A(C(12, 10, 2.3))], ['location-dot', 'map-marker-alt', 'map-pin'], 'location marker blip');
add(c, 'map', [P('M9 4 3 6.5v13L9 17l6 2.5 6-2.5v-13L15 6.5z'), A(P('M9 4v13M15 6.5v13'))], ['map', 'map-location'], 'gps area');
add(c, 'compass', [C(12, 12, 9), A(P('m15.5 8.5-2 5-5 2 2-5z'))], ['compass'], 'direction heading');
add(c, 'building', [R(4, 3, 10, 18, 1, 1), P('M14 9h5.5L21 10.5V21M2.5 21h19'), A(P('M7.5 7h3M7.5 11h3M7.5 15h3'))], ['building', 'city'], 'apartment office');
add(c, 'hospital', [R(4, 6, 16, 15, 1.5, 3.5), P('M9 6V3h6v3'), A(P('M12 10v6M9 13h6'))], ['hospital'], 'ems pillbox');
add(c, 'sun', [A(C(12, 12, 4)), P('M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4')], ['sun'], 'weather day');
add(c, 'moon', P('M20 14.5A8.5 8.5 0 1 1 9.5 4a7 7 0 0 0 10.5 10.5z'), ['moon'], 'night weather');
add(c, 'cloud', P('M7 18.5h10a4 4 0 0 0 .5-8 6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 18.5z'), ['cloud'], 'weather');
add(c, 'rain', [P('M7 14.5h10a4 4 0 0 0 .5-8 6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 14.5z'), A(P('M8 17.5 7 20M12 17.5 11 20M16 17.5 15 20'))], ['cloud-rain'], 'weather storm');
add(c, 'tree', [P('M12 3 5.5 12.5H9L5 17h14l-4-4.5h3.5z'), A(P('M12 17v4'))], ['tree'], 'park nature');
add(c, 'mail', [R(3, 5.5, 18, 13, 1.5, 3), A(P('m3.5 7 8.5 6 8.5-6'))], ['envelope'], 'email inbox');
add(c, 'message', [P('M4 5h16v11H9l-5 4z'), A(P('M8 9.5h8M8 12.5h5'))], ['message', 'comment'], 'chat sms');
add(c, 'send', P('M21 3 10.5 13.5M21 3l-6.5 18-4-7.5L3 9.5z'), ['paper-plane', 'send'], 'give share');
add(c, 'broadcast', [A(D(12, 12, 1.5)), P('M8.5 15.5a5 5 0 0 1 0-7M15.5 8.5a5 5 0 0 1 0 7M5.5 18.5a9 9 0 0 1 0-13M18.5 5.5a9 9 0 0 1 0 13')], ['tower-broadcast', 'podcast'], 'radio news live');
add(c, 'bell-ring', [P('M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15z'), A(P('M10 21h4M3 9a7 7 0 0 1 2-4M21 9a7 7 0 0 0-2-4'))], ['bell'], 'alarm ring');

/* ── Admin ── */
c = 'Admin';
add(c, 'terminal', [R(2.5, 4, 19, 16, 1.5, 3.5), P('M6.5 9.5l3 2.5-3 2.5'), A(P('M12 15h5'))], ['terminal'], 'console command');
add(c, 'code', [P('M8 7l-5 5 5 5M16 7l5 5-5 5'), A(P('M14 4.5l-4 15'))], ['code'], 'developer script');
add(c, 'bug', [P('M8 9a4 4 0 0 1 8 0v5a4 4 0 0 1-8 0z'), A(P('M12 9v9')), P('M9 5.5 7.5 4M15 5.5 16.5 4M4 12h4M16 12h4M4.5 17.5 8 16M19.5 17.5 16 16M4.5 7 8 9M19.5 7 16 9')], ['bug'], 'error debug');
add(c, 'database', [P('M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3z'), P('M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6'), A(P('M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3'))], ['database'], 'sql storage');
add(c, 'server', [R(3, 3.5, 18, 7, 1), R(3, 13.5, 18, 7, 1, 3), A(D(7, 7, 1.1)), D(7, 17, 1.1), P('M11 7h6M11 17h6')], ['server'], 'host');
add(c, 'ban', [C(12, 12, 9), A(P('M5.6 5.6l12.8 12.8'))], ['ban', 'user-slash'], 'block banned');
add(c, 'teleport', [P('M4 18.5c0-1.4 3.6-2.5 8-2.5s8 1.1 8 2.5-3.6 2.5-8 2.5-8-1.1-8-2.5z'), A(P('M12 14V3M8 7l4-4 4 4'))], ['location-crosshairs'], 'tp goto');

// aliases — extra class names that point at an icon
const ALIAS = {
  'arrow-left': 'arrow-l', 'arrow-right': 'arrow-r', 'chevron-up': 'chev-u', 'chevron-down': 'chev-d', 'chevron-left': 'chev-l', 'chevron-right': 'chev-r',
  close: 'x', settings: 'cog', gear: 'cog', delete: 'trash', health: 'heart', armor: 'shield', hunger: 'food', thirst: 'drop', stamina: 'bolt', stress: 'brain',
  money: 'cash', ems: 'medkit', police: 'badge', mechanic: 'wrench', warning: 'alert', spectate: 'eye', location: 'pin', vehicle: 'car', weapon: 'pistol',
  inventory: 'backpack', job: 'briefcase', fire: 'flame', water: 'drop', gold: 'ingot', speed: 'gauge', seatbelt: 'seat', voice: 'mic', notify: 'bell',
};

module.exports = { icons: I, alias: ALIAS };
