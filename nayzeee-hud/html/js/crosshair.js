// Custom crosshair: replaces GTA's reticle while you aim (Lua hides the native one only then).
(() => {
  const NH = window.NH;
  NH.CROSS_STYLES = [['dot', 'Dot'], ['cross', 'Cross'], ['crossdot', 'Cross + Dot'], ['tee', 'T'], ['plus', 'Plus'],
    ['circle', 'Circle'], ['circledot', 'Circle + Dot'], ['chevron', 'Chevron']];
  NH.CROSS_COLORS = ['#ffffff', 'accent', '#08afa2', '#4ade80', '#fde047', '#22d3ee', '#ff4d5e', '#f472b6'];

  const html = '<i class="a t"></i><i class="a r"></i><i class="a b"></i><i class="a l"></i><i class="c"></i><i class="v"></i><i class="d"></i>';

  NH.crossVars = (el, c) => {
    const color = c.color === 'accent' ? 'var(--accent)' : c.color;
    el.className = `xh xs-${c.style}${c.outline ? ' xo' : ''}`;
    el.style.setProperty('--xc', color);
    el.style.setProperty('--xs', `${c.size}px`);
    el.style.setProperty('--xt', `${c.thick}px`);
    el.style.setProperty('--xg', `${c.gap}px`);
    el.style.setProperty('--xa', c.opacity / 100);
  };

  let el = null;
  NH.buildCrosshair = () => {
    el = document.getElementById('xh');
    el.innerHTML = html;
  };
  NH.applyCrosshair = () => {
    if (!el) return;
    const c = NH.cur.crosshair;
    NH.crossVars(el, c);
    NH.renderCrosshair();
  };
  NH.renderCrosshair = () => {
    if (!el) return;
    const c = NH.cur.crosshair;
    const settingsOnCross = NH.settingsUI?.isOpen && NH.settingsUI.tab === 'crosshair';
    el.classList.toggle('on', c.enabled && (!!NH.S.ch || settingsOnCross));
  };

  NH.crossPreview = (style, c) => {
    const d = document.createElement('div');
    d.className = 'xh-pv';
    d.innerHTML = `<div>${html}</div>`;
    NH.crossVars(d.firstChild, Object.assign({}, c, { style }));
    d.firstChild.classList.add('on');
    return d;
  };
})();
