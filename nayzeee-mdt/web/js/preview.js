/* ═══════════════════════════════════════════════════════════════════════════
   BROWSER PREVIEW
   Only loaded when web/index.html is opened outside the game. It answers the
   tablet's requests with sample data so the UI can be checked in a browser.
   It is not listed in fxmanifest.lua, so it never ships to players.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  document.body.style.background = "#1b2330 url('img/wallpaper-grid.svg') center/cover";

  const now = () => new Date().toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
  const me = {
    identifier: 'char1:preview', name: 'Jordan Hale', department: 'police', deptLabel: 'Los Santos Police Department',
    deptShort: 'LSPD', deptSub: 'Mobile Data Terminal', rank: 'Sergeant', badge: 'LSPD-4K21', callsign: 'L-12',
    onDuty: true, status: 'available', dutySeconds: 86000, medical: false
  };

  const charges = [
    { id: 'speeding_1', label: 'Speeding (1-15 over)', class: 'infraction', category: 'Traffic', fine: 250, jail: 0, points: 1 },
    { id: 'reckless', label: 'Reckless driving', class: 'misdemeanor', category: 'Traffic', fine: 1200, jail: 10, points: 4 },
    { id: 'evading', label: 'Evading a peace officer', class: 'felony', category: 'Traffic', fine: 4000, jail: 30, points: 6 },
    { id: 'burglary', label: 'Burglary', class: 'felony', category: 'Property', fine: 5000, jail: 45 },
    { id: 'grand_theft', label: 'Grand theft auto', class: 'felony', category: 'Property', fine: 6000, jail: 50 },
    { id: 'assault', label: 'Assault', class: 'misdemeanor', category: 'Persons', fine: 2000, jail: 20 },
    { id: 'agg_assault', label: 'Aggravated assault', class: 'felony', category: 'Persons', fine: 6500, jail: 55 },
    { id: 'poss_2', label: 'Possession with intent', class: 'felony', category: 'Narcotics', fine: 5000, jail: 45 },
    { id: 'ccw', label: 'Carrying a concealed weapon', class: 'misdemeanor', category: 'Weapons', fine: 2000, jail: 20 },
    { id: 'resist', label: 'Resisting arrest', class: 'misdemeanor', category: 'Justice', fine: 1500, jail: 15 }
  ];

  const config = {
    version: '2.0.0', currency: '$',
    callTypes: [
      { id: 'shooting', label: 'Shooting', group: 'crime', priority: 1, code: '10-71', icon: 'shield' },
      { id: 'store', label: 'Store robbery', group: 'crime', priority: 1, code: '10-90', icon: 'cash' },
      { id: 'theft', label: 'Vehicle theft', group: 'crime', priority: 2, code: '10-31', icon: 'car' },
      { id: 'traffic', label: 'Traffic collision', group: 'traffic', priority: 2, code: '10-50', icon: 'car' },
      { id: 'suspicious', label: 'Suspicious person', group: 'crime', priority: 3, code: '10-66', icon: 'user' },
      { id: 'backup', label: 'Officer needs help', group: 'panic', priority: 1, code: '10-78', icon: 'alert' }
    ],
    unitStatus: [
      { id: 'available', label: 'Available', tone: 'teal' }, { id: 'enroute', label: 'En route', tone: 'amber' },
      { id: 'onscene', label: 'On scene', tone: 'amber' }, { id: 'busy', label: 'Busy', tone: 'red' },
      { id: 'break', label: 'On break', tone: 'off' }
    ],
    charges,
    chargeClasses: { infraction: { label: 'Infraction', tone: 'teal' }, misdemeanor: { label: 'Misdemeanor', tone: 'amber' }, felony: { label: 'Felony', tone: 'red' } },
    warrantTypes: [{ id: 'arrest', label: 'Arrest warrant' }, { id: 'search', label: 'Search warrant' }],
    evidenceTypes: [{ id: 'weapon', label: 'Weapon' }, { id: 'narcotics', label: 'Narcotics' }, { id: 'physical', label: 'Physical' }],
    lockers: ['Evidence Locker A-05', 'Evidence Locker B-12'],
    licences: [{ id: 'drive', label: 'Driver licence' }, { id: 'weapon', label: 'Firearm licence' }],
    mapBounds: { minX: -6235.0, maxX: 6435.0, minY: -4510.0, maxY: 8810.0 },
    mapEnabled: true, mapStyle: 'midnight',
    mapStyles: [
      { id: 'atlas', label: 'Atlas', file: 'img/atlas.webp' }, { id: 'midnight', label: 'Midnight', file: 'img/midnight.webp' },
      { id: 'satellite', label: 'Satellite', file: 'img/satellite.webp' }, { id: 'grid', label: 'Grid', file: false }
    ],
    maxUnits: 8, emergency: '911',
    departments: { police: { short: 'LSPD', callsignPrefix: 'L' }, sheriff: { short: 'LSSD', callsignPrefix: 'S' } },
    linkTypes: [{ id: 'citizen', label: 'Citizen', icon: 'user' }, { id: 'vehicle', label: 'Vehicle', icon: 'car' }, { id: 'incident', label: 'Incident', icon: 'file' }],
    weaponList: [{ name: 'weapon_pistol', label: 'Pistol' }, { name: 'weapon_smg', label: 'SMG' }],
    photos: false, cameraModels: [{ model: 'prop_cctv_cam_01a', label: 'Standard CCTV' }],
    staff: true, statsDays: 30, maxCharges: 25, maxCitizens: 10, bulletinDays: 7, panicEnabled: true,
    tenCodes: [
      { code: '10-4', label: 'Acknowledged' }, { code: '10-8', label: 'In service' }, { code: '10-20', label: 'Location' },
      { code: '10-38', label: 'Traffic stop' }, { code: '10-80', label: 'Pursuit in progress' }, { code: '10-99', label: 'Officer needs emergency help' }
    ],
    tablet: {
      lockScreen: 'first', wallpaper: 'nayzeee',
      wallpapers: [
        { id: 'nayzeee', label: 'NAYZEEE', file: 'img/wallpaper.svg' },
        { id: 'hex', label: 'Hex grid', file: 'img/wallpaper-grid.svg' }
      ]
    }
  };

  const officers = [
    { identifier: 'char1:preview', name: 'Jordan Hale', callsign: 'L-12', rank: 'Sergeant', department: 'police', status: 'available', street: 'Vespucci Blvd', x: 200, y: -900 },
    { identifier: 'char1:b', name: 'Ava Morales', callsign: 'L-21', rank: 'Officer', department: 'police', status: 'enroute', street: 'Strawberry Ave', x: 120, y: -1350 },
    { identifier: 'char1:c', name: 'Marcus Reed', callsign: 'S-04', rank: 'Deputy', department: 'sheriff', status: 'onscene', street: 'Route 68', x: 1700, y: 3600 }
  ];

  const calls = [
    { id: 7, ref: 'DISP-0007', type: 'store', title: 'Store robbery in progress', code: '10-90', priority: 1, status: 'assigned',
      street: 'Innocence Blvd / Grove St', x: 25, y: -1345, detail: 'Two suspects, one armed with a pistol. Clerk hit the silent alarm.',
      caller: '24/7 alarm', plate: '46EEK572', ageSeconds: 140,
      units: [{ identifier: 'char1:b', name: 'Ava Morales', callsign: 'L-21', department: 'police', status: 'enroute' }] },
    { id: 6, ref: 'DISP-0006', type: 'traffic', title: 'Traffic collision', code: '10-50', priority: 2, status: 'pending',
      street: 'Del Perro Fwy', x: -1300, y: -600, detail: 'Two vehicle collision, blocking the left lane.', caller: 'Anonymous', ageSeconds: 610, units: [] },
    { id: 5, ref: 'DISP-0005', type: 'suspicious', title: 'Suspicious person', code: '10-66', priority: 3, status: 'onscene',
      street: 'Paleto Blvd', x: -150, y: 6400, detail: 'Male loitering by the bank for over an hour.', caller: 'Bank teller', ageSeconds: 1900,
      units: [{ identifier: 'char1:c', name: 'Marcus Reed', callsign: 'S-04', department: 'sheriff', status: 'onscene' }] }
  ];

  const citizens = [
    { id: 'CZ4K9A2M1P', name: 'Tyrell Banks', first: 'Tyrell', last: 'Banks', dob: '1994-03-12', gender: 'Male', phone: '555-0192', job: 'Mechanic',
      flags: [{ label: 'Known to carry', tone: 'red' }], licences: { drive: 'valid', weapon: 'revoked' }, fingerprint: 'FP7KX2M9QA1', dna: 'DNA2MF8KQ0ZP' },
    { id: 'CZ7Q2W8E5R', name: 'Maria Chen', first: 'Maria', last: 'Chen', dob: '1988-11-02', gender: 'Female', phone: '555-0144', job: 'Doctor', flags: [], licences: { drive: 'valid' } },
    { id: 'CZ1T6Y3U9I', name: 'Dwayne Fox', first: 'Dwayne', last: 'Fox', dob: '1979-07-21', gender: 'Male', phone: '555-0177', job: 'Unemployed',
      flags: [{ label: 'Gang affiliated', tone: 'amber' }], licences: { drive: 'suspended' } }
  ];

  const vehicles = [
    { id: 1, plate: '46EEK572', model: 'sultan', type: 'Sedan', colour: 'Black', vin: 'VIN8KQ2M7XA0P1', ownerId: 'CZ4K9A2M1P', ownerName: 'Tyrell Banks', insurance: 'expired', registration: 'valid', stolen: true, impounded: false },
    { id: 2, plate: 'LSPD 012', model: 'police3', type: 'Car', colour: 'White', vin: 'VIN1Q2W3E4R5T6', ownerName: 'LSPD', insurance: 'valid', registration: 'valid', stolen: false, impounded: false }
  ];

  const page = (rows, p) => ({ ok: true, rows, page: p || 1, pages: 1, total: rows.length });
  let notes = [];

  const handlers = {
    'nz_mdt:dashboard': () => ({
      ok: true,
      counts: { openIncidents: 4, activeWarrants: 2, activeBolos: 1, openCalls: calls.length, evidenceOut: 1 },
      stats: { days: 30, arrests: 18, citations: 41, filed: 63, closed: 44, clearance: 69, revenue: 184500, myReports: 9 },
      incidents: [
        { id: 12, ref: 'INC-000012', title: 'Armed robbery — 24/7 Grove St', location: 'Grove St', status: 'open', stamp: now() },
        { id: 11, ref: 'INC-000011', title: 'DUI traffic stop', location: 'Vinewood Blvd', status: 'closed', stamp: now() }
      ],
      warrants: [{ id: 3, citizen_id: 'CZ4K9A2M1P', citizen_name: 'Tyrell Banks', title: 'Arrest — armed robbery', issued_by: 'Sgt. Hale', stamp: now() }],
      announcements: [{ id: 1, title: 'Shift briefing moved to 18:00', body: 'All units report to Mission Row briefing room. Pursuit policy refresh.', pinned: 1, author: 'Capt. Ross', stamp: now() }],
      officers, calls,
      me: { onDuty: me.onDuty, status: me.status, callsign: me.callsign, badge: me.badge, shiftMinutes: 47, totalHours: 23 }
    }),
    'nz_mdt:dispatch:board': () => ({ ok: true, calls, officers }),
    'nz_mdt:bolo:list': () => ({ ok: true, rows: [{ id: 2, title: 'Black Sultan — armed robbery suspects', kind: 'vehicle', plate: '46EEK572', model: 'sultan', detail: 'Two suspects, armed. Do not approach alone.', priority: 1, status: 'active', issuedBy: 'Sgt. Hale', stamp: now(), expiresIn: 70 }] }),
    'nz_mdt:warrant:list': () => ({ ok: true, rows: [{ id: 3, citizenId: 'CZ4K9A2M1P', citizen: 'Tyrell Banks', type: 'arrest', title: 'Arrest — armed robbery', detail: 'Identified on CCTV at the Grove St 24/7.', charges: [{ id: 'burglary', label: 'Burglary' }], status: 'active', issuedBy: 'Sgt. Hale', stamp: now(), expiresIn: 29 }] }),
    'nz_mdt:incident:list': () => page([
      { id: 12, ref: 'INC-000012', title: 'Armed robbery — 24/7 Grove St', location: 'Grove St', primary_name: 'Tyrell Banks', charge_count: 3, total_fine: 13000, total_jail: 115, status: 'open', stamp: now(), created_by: 'Jordan Hale' },
      { id: 11, ref: 'INC-000011', title: 'DUI traffic stop', location: 'Vinewood Blvd', primary_name: 'Dwayne Fox', charge_count: 1, total_fine: 2500, total_jail: 20, status: 'closed', stamp: now(), created_by: 'Ava Morales' }
    ]),
    'nz_mdt:incident:get': () => ({ ok: true,
      incident: { id: 12, ref: 'INC-000012', title: 'Armed robbery — 24/7 Grove St', detail: 'Suspect entered at 21:04 and produced a pistol.\nFled north in a black Sultan.', location: 'Grove St', status: 'open', total_fine: 13000, total_jail: 115, created_by: 'Jordan Hale', created_stamp: '11/10/2026, 21:30', primary_name: 'Tyrell Banks', dispatch_ref: 'DISP-0007' },
      people: [{ citizen_id: 'CZ4K9A2M1P', name: 'Tyrell Banks', role: 'suspect' }],
      charges: [{ charge_id: 'burglary', label: 'Burglary', class: 'felony', counts: 1, fine: 5000, jail: 45, reduced: 0, citizen_id: 'CZ4K9A2M1P' }],
      evidence: [{ id: 4, ref: 'EV-0004', description: 'Pistol, black', type: 'weapon', locker: 'Evidence Locker A-05', status: 'in' }],
      notes: [], photos: [], links: [] }),
    'nz_mdt:evidence:list': () => page([{ id: 4, ref: 'EV-0004', description: 'Pistol, black, serial filed', type: 'weapon', location: 'Grove St', locker: 'Evidence Locker A-05', collectedBy: 'Jordan Hale', status: 'in', incidentRef: 'INC-000012' }]),
    'nz_mdt:evidence:get': () => ({ ok: true, evidence: { id: 4, ref: 'EV-0004', description: 'Pistol, black, serial filed', type: 'weapon', location: 'Grove St', locker: 'Evidence Locker A-05', collectedBy: 'Jordan Hale', status: 'in', incidentRef: 'INC-000012', stamp: now() }, chain: [{ action: 'collected', actor: 'Jordan Hale', note: 'Grove St', stamp: now() }], notes: [], photos: [], links: [] }),
    'nz_mdt:citizen:list': () => page(citizens),
    'nz_mdt:citizen:profile': (id) => {
      const c = citizens.find(x => x.id === id) || citizens[0];
      return { ok: true, citizen: c, vehicles: vehicles.filter(v => v.ownerId === c.id), weapons: [], properties: [],
        warrants: c.id === 'CZ4K9A2M1P' ? [{ id: 3, type: 'arrest', title: 'Arrest — armed robbery', status: 'active', issued_by: 'Sgt. Hale', stamp: now() }] : [],
        incidents: [{ id: 12, ref: 'INC-000012', title: 'Armed robbery', status: 'open', total_fine: 13000, total_jail: 115, stamp: now() }],
        charges: [{ label: 'Burglary', class: 'felony', counts: 1, fine: 5000, jail: 45 }],
        record: { charges: 1, fine: 5000, jail: 45, wanted: c.id === 'CZ4K9A2M1P' },
        notes: [{ id: 1, author: 'Ava Morales', stamp: now(), visibility: 'department', body: 'Drives a black Sultan.', mine: false }], photos: [], links: [] };
    },
    'nz_mdt:vehicle:list': () => page(vehicles),
    'nz_mdt:vehicle:profile': (plate) => {
      const v = vehicles.find(x => x.plate === plate) || vehicles[0];
      return { ok: true, vehicle: v, owner: citizens.find(c => c.id === v.ownerId), bolos: [{ id: 2, title: 'Black Sultan — robbery suspects', status: 'active', issued_by: 'Sgt. Hale', stamp: now() }], notes: [], photos: [], links: [] };
    },
    'nz_mdt:weapon:list': () => page([{ id: 1, serial: 'WP8K2M4X9Q', label: 'Combat Pistol', weapon: 'weapon_combatpistol', ownerName: 'Maria Chen', status: 'registered' }]),
    'nz_mdt:property:list': () => page([{ id: 1, label: '4562 Grove Street', address: 'Grove St, Davis', type: 'residential', owner_name: 'Tyrell Banks', owner_id: 'CZ4K9A2M1P' }]),
    'nz_mdt:officer:roster': () => ({ ok: true, rows: officers.map(o => Object.assign({ onDuty: true, totalHours: 23, shiftMinutes: 47, badge: 'LSPD-' + o.callsign }, o)) }),
    'nz_mdt:announce:list': () => ({ ok: true, rows: [{ id: 1, title: 'Shift briefing moved to 18:00', body: 'All units report to Mission Row briefing room.\nPursuit policy refresh.', pinned: 1, author: 'Capt. Ross', stamp: now() }] }),
    'nz_mdt:audit:list': () => page([{ actor: 'Jordan Hale', department: 'police', action: 'citizen.view', subject: 'citizen', subject_id: 'CZ4K9A2M1P', detail: 'Profile opened', stamp: now() }]),
    'nz_mdt:camera:list': () => ({ ok: true, placeable: true, models: config.cameraModels, rows: [
      { id: 'cam_pacific', label: 'Pacific Standard Bank', model: 'prop_cctv_cam_01a', departments: [], status: 'online', fixed: true },
      { id: 'CAM-8K2M4X', label: 'Grove St corner', model: 'prop_cctv_cam_01a', departments: ['police'], status: 'destroyed', fixed: false }] }),
    'nz_mdt:search': (term) => ({ ok: true, rows: citizens.filter(c => c.name.toLowerCase().includes(String(term).toLowerCase())).map(c => ({ kind: 'citizen', id: c.id, title: c.name, sub: `${c.dob} · ${c.phone}` }))
      .concat(vehicles.filter(v => v.plate.toLowerCase().includes(String(term).toLowerCase())).map(v => ({ kind: 'vehicle', id: v.plate, title: v.plate, sub: v.model, hot: v.stolen }))) }),
    'nz_mdt:photo:status': () => ({ ok: true, ready: false, reason: 'Photo capture is switched off in the config.' }),
    'nz_mdt:duty:toggle': () => { me.onDuty = !me.onDuty; return { ok: true, onDuty: me.onDuty, msg: me.onDuty ? 'You are on duty.' : 'You are off duty.' }; },
    'nz_mdt:duty:status': (s) => ({ ok: true, msg: `Status set to ${s}.` })
  };

  window.MDT_PREVIEW = {
    request(name, args) {
      const fn = handlers[name];
      return Promise.resolve(fn ? fn.apply(null, args) : { ok: true, msg: `${name} (preview)` });
    },
    raw(endpoint, body) {
      if (endpoint === 'myLocation') return Promise.resolve({ ok: true, street: 'Vespucci Blvd / Alta St', x: 200, y: -900, z: 30 });
      if (endpoint === 'nearbyPlate') return Promise.resolve({ ok: true, plate: '46EEK572', model: 'sultan' });
      if (endpoint === 'notepad:get') return Promise.resolve({ ok: true, notes });
      if (endpoint === 'notepad:set') { notes = (body && body.notes) || []; return Promise.resolve({ ok: true }); }
      return Promise.resolve({ ok: true });
    }
  };

  const params = new URLSearchParams(location.search);
  window.postMessage({
    action: 'open',
    data: { me, perms: ['view.dispatch', 'view.bolo', 'view.warrant', 'view.incident', 'view.charge', 'view.evidence', 'view.citizen',
      'view.vehicle', 'view.weapon', 'view.property', 'view.officer', 'view.camera', 'view.announcement', 'view.audit',
      'dispatch.create', 'dispatch.assign', 'dispatch.close', 'bolo.create', 'bolo.edit', 'bolo.resolve', 'bolo.delete',
      'warrant.create', 'warrant.edit', 'warrant.execute', 'incident.create', 'incident.edit', 'incident.close', 'incident.delete',
      'evidence.create', 'evidence.checkout', 'citizen.create', 'citizen.edit', 'citizen.note', 'citizen.licence',
      'vehicle.create', 'vehicle.edit', 'vehicle.flag', 'weapon.create', 'property.create', 'officer.callsign', 'officer.manage',
      'announcement.create', 'photo.take', 'link.create', 'link.remove', 'camera.place', 'camera.manage'], config },
    settings: { lockAnimation: params.get('lock') !== '0', bootConsole: params.get('boot') !== '0' }
  }, '*');

  if (params.get('app')) setTimeout(() => window.postMessage({ action: 'openApp', app: params.get('app') }, '*'), 200);
  if (params.get('widget')) {
    setTimeout(() => {
      window.postMessage({ action: 'close' }, '*');
      window.postMessage({ action: 'widget', open: true, data: { calls, panics: {}, index: 0, keys: { prev: 'LEFT', next: 'RIGHT', accept: 'U' }, position: 'top-left', me: me.identifier, pos: { x: 200, y: -900 } } }, '*');
    }, 300);
  }
})();
