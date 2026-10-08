/* ═══════════════════════════════════════════════════════════
   Message router: game client → UI
   ═══════════════════════════════════════════════════════════ */
(() => {
  const S = NZ.state;
  const TYPE = { market: 'Market', limit: 'Limit', stop: 'Stop', trail: 'Trailing stop' };
  const KIND = { error: 'err', success: 'ok', warning: 'warn' };
  const quietCancel = (reason) => /^(OCO|Flatten|Account reset)/.test(reason || '');

  const H = {
    open(d) {
      NZ.load(d.boot);
      S.device = d.device;
      S.open = true;
      NZ.os.open(d.device);
    },

    shutdown() { NZ.os.shutdown(); },
    hint(d) { NZ.hint(d); },

    toast(d) {
      NZ.toast({ title: d.title || (S.cfg.ui && S.cfg.ui.brand) || 'NZ Trader', text: d.text, kind: KIND[d.kind] || 'info' });
    },

    quotes(d) { NZ.onQuotes(d); },

    account(d) {
      if (!d) return;
      S.accounts[d.type] = d;
      NZ.emit('account');
    },

    fill(d) {
      NZ.sound.play('fill');
      const pnl = d.realized ? ` · P&L ${NZ.signed(d.realized)}` : '';
      NZ.toast({
        title: `Order filled · ${d.acc === 'live' ? 'Live' : 'Paper'}`,
        text: `${d.side === 'buy' ? 'Bought' : 'Sold'} ${NZ.qty(d.qty)} ${d.sym} @ ${NZ.px(d.price)}${pnl}`,
      });
      NZ.emit('fill', d);
    },

    order(d) {
      const what = `${d.side.toUpperCase()} ${TYPE[d.type] || d.type} ${NZ.qty(d.qty)} ${d.sym}`;
      if (d.kind === 'working') {
        NZ.sound.play('place');
        NZ.toast({ kind: 'info', title: 'Order working', text: what, life: 3000 });
      } else if (d.kind === 'cancelled') {
        if (quietCancel(d.reason)) return;
        NZ.sound.play('cancel');
        NZ.toast({ kind: 'info', title: 'Order cancelled', text: what, life: 3000 });
      } else {
        NZ.sound.play('reject');
        NZ.toast({ kind: 'err', title: d.kind === 'expired' ? 'Order expired' : 'Order rejected', text: `${what} — ${d.reason || ''}` });
      }
    },

    alert(d) {
      S.alerts = S.alerts.filter((a) => a.id !== d.id);
      NZ.sound.play('alert');
      NZ.toast({ kind: 'warn', title: `Price alert · ${d.sym}`, text: `${d.sym} ${d.cond === 'above' ? 'rose above' : 'fell below'} ${NZ.px(d.price)} — last ${NZ.px(d.last)}`, life: 7000 });
      NZ.emit('alerts');
    },

    margin(d) {
      NZ.sound.play('margin');
      NZ.toast({ kind: 'err', title: 'Margin call', text: `Equity fell below maintenance on your ${d.acc} account. All positions were liquidated.`, life: 9000 });
    },

    news(d) {
      S.news.unshift(d);
      if (S.news.length > 40) S.news.pop();
      S.unreadNews++;
      const mine = d.symbol && (S.watch.includes(d.symbol) || S.focus === d.symbol || NZ.position(d.symbol));
      if (S.open && (mine || d.kind === 'earnings' || d.kind === 'macro')) {
        NZ.sound.play('news');
        const label = { earnings: 'Earnings', macro: 'Macro', halt: 'Trading halt' }[d.kind] || d.symbol;
        NZ.toast({ kind: d.impact < 0 || d.kind === 'halt' ? 'warn' : 'info', title: `Newswire · ${label}`, text: d.text, life: 6500 });
      }
      NZ.emit('news', d);
    },

    calendar(d) { S.cal = d || []; NZ.emit('calendar'); },

    session(d) {
      S.session = d;
      NZ.emit('session');
      NZ.toast({ kind: d.code === 'closed' ? 'warn' : 'info', title: NZ.sessionLabel(), text: NZ.sessionNext() });
    },

    halt(d) {
      const m = S.by[d.sym];
      if (!m) return;
      m.halt = d.until;
      NZ.emit('halt');
      if (!d.until && (d.sym === S.focus || NZ.position(d.sym))) {
        NZ.toast({ kind: 'info', title: `${d.sym} resumed`, text: 'Trading has resumed after the volatility pause.' });
      }
    },

    rollover(prevs) {
      prevs.forEach((p, i) => { const m = S.syms[i]; if (m) { m.prev = p; m.open = p; } });
      NZ.toast({ kind: 'info', title: 'New trading day', text: 'Day P&L and daily changes have reset.' });
      NZ.emit('quotes');
    },
  };

  addEventListener('message', (e) => {
    const m = e.data;
    if (m && H[m.action]) H[m.action](m.data);
  });
})();
