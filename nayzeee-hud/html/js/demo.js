// Browser preview only (never runs in game). Open html/index.html?veh=car
// Params: veh=car|moto|air|boat|cycle  settings=1  tab=status  season=halloween  edit=1  panel=1  static=1
//         status=<style> speedo=<style> units=kmh
(() => {
  const NH = window.NH;
  NH.demo = () => {
    document.body.classList.add('demo');
    const q = new URLSearchParams(location.search);
    const veh = q.get('veh');
    const still = q.has('static');

    const c = NH.saved;
    if (q.get('season')) c.season = q.get('season');
    if (q.get('status')) c.status.style = q.get('status');
    if (q.get('speedo')) c.speedo.style = q.get('speedo');
    if (q.get('units')) c.units = q.get('units');
    if (q.get('air')) c.air.style = q.get('air');
    if (q.get('info')) c.info.style = q.get('info');
    if (q.get('compass')) c.map.compassStyle = q.get('compass');
    if (q.get('clock')) c.clock.style = q.get('clock');
    if (q.get('sign')) c.map.signStyle = q.get('sign');
    if (q.has('noparticles')) c.particles = false;
    NH.cur = c;

    NH.update({
      h: 78, a: 54, hu: 66, th: 41, st: 88, sr: 22, ox: false, tk: false, vr: 2, rd: false,
      cash: 10000024, bank: 98957647, job: 'Law Enforcement', grd: 'Recruit', id: 1, hs: false,
      hr: 23, mn: 27, dow: 5, wx: 'CLEAR', hdg: 312, dir: 312,
      str: 'Vespucci Boulevard', crs: 'Palomino Ave', zn: 'Vespucci Beach', pst: '1046', lim: 30,
      wp: q.has('weapon') ? 'WEAPON_HEAVYPISTOL' : false, wl: 'Heavy Pistol', clip: 30, ammo: 36,
      radar: !!veh, pz: false,
    });
    if (veh) {
      NH.update({ vm: veh, spd: 268, rpm: 62, gr: 4, fu: 68, en: 92, li: 1, lk: false, ind: 0, eng: true, bl: true, cr: false, hb: veh === 'car', odo: 20072000,
        alt: 3250, agl: 1180, vs: 640, pt: 6, rl: -14, vh: 82, lg: 0 });
    }

    NH.applySettings();
    if (q.has('settings')) { NH.settingsUI.tab = q.get('tab') || 'general'; NH.settingsUI.open(); }
    if (q.has('edit')) { NH.settingsUI.open(); NH.settingsUI.editLayout(true); }
    if (q.has('panel')) NH.panel.open();
    if (still) return;

    let t = 0;
    setInterval(() => {
      t += 0.125;
      const d = { hdg: Math.round((312 + t * 12) % 360), tk: Math.sin(t * 2) > 0.4 };
      if (veh) {
        const s = 0.5 + 0.5 * Math.sin(t / 3);
        Object.assign(d, {
          spd: Math.round(s * 450), rpm: Math.round(25 + s * 70), gr: Math.max(1, Math.round(s * 5)),
          ind: Math.floor(t / 4) % 3 === 1 ? 1 : 0, pt: Math.round(Math.sin(t / 2) * 8), rl: Math.round(Math.sin(t / 3) * 20),
          alt: Math.round(3000 + Math.sin(t / 4) * 400), vs: Math.round(Math.cos(t / 4) * 100) * 10,
        });
      }
      NH.update(d);
    }, 125);
  };
})();
