(() => {
  const NH = window.NH;
  const ic = NH.ic;

  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  // Every style is plain markup with data-i slots and i-<key> classes, so one filler serves them all
  // and each element can be switched off with a no-<key> class on the box.
  const pill = (k, icon) => `<span class="pill i-${k}">${ic(icon)}<b data-i="${k}"></b></span>`;
  const line = (k, icon, inner) => `<div class="ln i-${k}"><span>${inner || `<b data-i="${k}"></b>`}</span>${ic(icon)}</div>`;
  const stackRow = (k, icon, label) => `<div class="ir i-${k}"><div><small>${label}</small><b data-i="${k}"></b></div><span class="cic">${ic(icon)}</span></div>`;
  const tile = (k, icon, inner) => `<div class="tl i-${k}"><div class="tl-t">${inner || `<b data-i="${k}"></b>`}</div><span class="tl-i">${ic(icon)}</span></div>`;
  const when = '<b data-i="date"></b><b data-i="time"></b>';
  const chip = (k, icon) => `<span class="chp i-${k}"><i>${ic(icon)}</i><b data-i="${k}"></b></span>`;

  NH.INFO_STYLES = {
    chips: {
      label: 'Chips',
      html: () => `<div class="inf chips">${chip('cash', 'cash')}${chip('dirty', 'cash')}${chip('bank', 'bank')}${chip('id', 'idcard')}${chip('players', 'users')}${chip('job', 'briefcase')}${chip('gang', 'users')}${chip('time', 'clock')}</div>`,
    },
    pills: {
      label: 'Pills',
      html: () => `<div class="inf pills"><div class="r">${pill('job', 'briefcase')}</div><div class="r">${pill('gang', 'users')}</div>
        <div class="r">${pill('bank', 'bank')}${pill('cash', 'cash')}</div><div class="r">${pill('dirty', 'cash')}</div>
        <div class="r"><span class="pill hs i-pic">${NH.fic('mic', 'mic')}<img data-i="pic" alt=""/></span>${pill('id', 'idcard')}</div></div>`,
    },
    stack: {
      label: 'Stacked',
      html: () => `<div class="inf stack">${stackRow('job', 'briefcase', 'Job')}${stackRow('gang', 'users', 'Gang')}${stackRow('cash', 'cash', 'Cash')}${stackRow('dirty', 'cash', 'Dirty')}${stackRow('bank', 'bank', 'Bank')}${stackRow('id', 'idcard', 'Server ID')}</div>`,
    },
    compact: {
      label: 'Compact',
      html: () => `<div class="inf compact panel"><div class="ic-hd"><span class="ic-pic i-pic"><img data-i="pic" alt=""/></span><div><b data-i="name"></b><small data-i="job"></small></div><span class="ic-id i-id" data-i="id"></span></div>
        <div class="ic-row i-cash">${ic('cash')}<b data-i="cash"></b></div><div class="ic-row i-dirty">${ic('cash')}<b data-i="dirty"></b></div><div class="ic-row i-bank">${ic('bank')}<b data-i="bank"></b></div></div>`,
    },
    list: {
      label: 'List',
      html: () => `<div class="inf list">${line('time', 'clock', when)}${line('job', 'briefcase')}${line('gang', 'users')}${line('cash', 'cash')}${line('dirty', 'cash')}${line('bank', 'bank')}${line('id', 'idcard', '<b data-i="id"></b>')}</div>`,
    },
    sections: {
      label: 'Sections',
      html: () => `<div class="inf sections">
        <div class="sx-top"><span class="i-id">${ic('user')}<b data-i="id"></b></span><span class="i-players">${ic('users')}<b data-i="players"></b></span><span class="i-pic sx-pic"><img data-i="pic" alt=""/></span></div>
        ${line('time', 'clock', when)}
        <small class="sx-h">Job &amp; Gang</small>${line('job', 'briefcase')}${line('gang', 'users')}
        <small class="sx-h">Cash &amp; Bank</small>${line('cash', 'cash')}${line('dirty', 'cash')}${line('bank', 'bank')}</div>`,
    },
    grid: {
      label: 'Grid',
      html: () => `<div class="inf grid">
        <div class="gx panel gx-top">
          <div class="gx-c"><span class="i-id">${ic('user')}<b data-i="id"></b></span><span class="i-players">${ic('users')}<b data-i="players"></b></span></div>
          <i class="gx-sep i-time"></i>
          <div class="gx-c gx-t i-time">${ic('clock')}<div><b data-i="time"></b><small data-i="date"></small></div></div>
          <span class="gx-pic i-pic"><img data-i="pic" alt=""/></span>
        </div>
        <div class="gx panel gx-2">
          <div class="gx-cell i-gang">${ic('users')}<div><small>Gang</small><b data-i="gang"></b></div></div>
          <div class="gx-cell r i-job"><div><small>Job</small><b data-i="job"></b></div>${ic('briefcase')}</div>
          <div class="gx-cell i-cash">${ic('cash')}<div><small>Cash</small><b data-i="cash"></b></div></div>
          <div class="gx-cell r i-bank"><div><small>Bank</small><b data-i="bank"></b></div>${ic('bank')}</div>
          <div class="gx-cell i-dirty">${ic('cash')}<div><small>Dirty</small><b data-i="dirty"></b></div></div>
        </div></div>`,
    },
    tiles: {
      label: 'Tiles',
      html: () => `<div class="inf tiles">${tile('time', 'clock', `<small data-i="date"></small><b data-i="time"></b>`)}${tile('id', 'user', `<small>Server ID</small><b data-i="id"></b>`)}
        ${tile('job', 'briefcase', `<small>Job</small><b data-i="job"></b>`)}${tile('gang', 'users', `<small>Gang</small><b data-i="gang"></b>`)}
        ${tile('cash', 'cash', `<small>Cash</small><b data-i="cash"></b>`)}${tile('dirty', 'cash', `<small>Dirty</small><b data-i="dirty"></b>`)}${tile('bank', 'bank', `<small>Bank</small><b data-i="bank"></b>`)}</div>`,
    },
    profile: {
      label: 'Profile Card',
      html: () => `<div class="inf profile panel">
        <div class="pf-hd"><span class="pf-pic i-pic"><img data-i="pic" alt=""/></span><div class="pf-n"><b data-i="name"></b><small data-i="job"></small></div><span class="pf-id i-id" data-i="id"></span></div>
        <div class="pf-row"><span class="i-cash">${ic('cash')}<b data-i="cash"></b></span><span class="i-bank">${ic('bank')}<b data-i="bank"></b></span><span class="i-dirty">${ic('cash')}<b data-i="dirty"></b></span></div>
        <div class="pf-ft"><span class="i-gang">${ic('users')}<b data-i="gang"></b></span><span class="i-players">${ic('users')}<b data-i="players"></b></span></div></div>`,
    },
  };

  // Values shown by every style
  NH.infoValues = (S, c = NH.cur) => {
    const clock = c.clock;
    let h, m, dom, mon, dow;
    if (clock.source === 'real') { const d = new Date(); h = d.getHours(); m = d.getMinutes(); dom = d.getDate(); mon = d.getMonth(); dow = d.getDay(); }
    else { h = S.hr ?? 12; m = S.mn ?? 0; dom = S.dom ?? 1; mon = S.mon ?? 0; dow = S.dow ?? 5; }
    const mm = String(m).padStart(2, '0');
    const hs = S.hs ? `https://nui-img/${S.hs}/${S.hs}?t=${S.hs}` : '';
    const discord = (c.info.animated && S.ava) || S.av || '';
    const pic = c.info.avatar === 'none' ? '' : c.info.avatar === 'headshot' ? hs : (discord || hs);
    return {
      job: S.grd ? `${S.job || 'Civilian'} - ${S.grd}` : (S.job || 'Civilian'),
      gang: S.gng || 'No Gang',
      name: S.pn || 'Player',
      cash: NH.money(S.cash), bank: NH.money(S.bank), dirty: NH.money(S.dm || 0),
      id: `#${S.id ?? 0}`,
      players: S.pl ? `${S.pl}/${S.plm || S.pl}` : '',
      time: clock.h24 ? `${String(h).padStart(2, '0')}:${mm}` : `${(h % 12) || 12}:${mm} ${h < 12 ? 'AM' : 'PM'}`,
      date: `${dom} ${MONTHS[mon] || ''} ${DOW[dow] || ''}`,
      pic,
    };
  };

  // which elements are switched off for this player / this data
  NH.infoHidden = (S, info) => ({
    job: !info.job, gang: !info.gang || S.gng === false, name: !info.name, cash: !info.cash, bank: !info.bank,
    dirty: !info.dirty || S.dm === false || S.dm === undefined, id: !info.id, players: !info.players || !S.pl,
    time: !info.time, pic: !info.headshot || info.avatar === 'none',
  });

  NH.collectInfo = (el) => {
    const refs = {};
    el.querySelectorAll('[data-i]').forEach(n => (refs[n.dataset.i] = refs[n.dataset.i] || []).push(n));
    return refs;
  };

  NH.fillInfo = (refs, values, last = {}) => {
    for (const k in refs) {
      const v = values[k];
      if (v === undefined || last[k] === v) continue;
      last[k] = v;
      for (const n of refs[k]) {
        if (n.tagName === 'IMG') {
          if (v) n.src = v; else n.removeAttribute('src');
          n.parentNode.classList.toggle('noimg', !v);
        } else n.textContent = v;
      }
    }
    return last;
  };

  NH.DEMO_INFO = { job: 'Law Enforcement', grd: 'Recruit', gng: 'Families', pn: 'Nay Zeee', cash: 10024, bank: 98957, dm: false, id: 7, pl: 42, plm: 128, hr: 14, mn: 50, dom: 6, mon: 7, dow: 3, hs: false, av: false };

  NH.infoPreview = (style) => {
    const wrap = document.createElement('div');
    wrap.className = 'w-info pv-info';
    wrap.innerHTML = (NH.INFO_STYLES[style] || NH.INFO_STYLES.pills).html();
    const box = wrap.firstElementChild;
    const info = Object.assign({}, NH.cur.info);
    const hidden = NH.infoHidden(NH.DEMO_INFO, info);
    for (const k in hidden) box.classList.toggle('no-' + k, hidden[k]);
    if (!NH.S.av && !NH.S.hs) box.classList.add('demo-pic');
    NH.fillInfo(NH.collectInfo(wrap), NH.infoValues(Object.assign({}, NH.DEMO_INFO, { av: NH.S.av, ava: NH.S.ava, hs: NH.S.hs })));
    return wrap;
  };
})();
