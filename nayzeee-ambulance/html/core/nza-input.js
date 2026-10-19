/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · input compat for the FiveM NUI browser             window.NZAInput
   Loads before everything else (first <script> in index.html) so its capture listeners
   run first.

   FiveM draws the NUI with an off-screen CEF browser and feeds it mouse input itself.
   Depending on the build that input can differ from a desktop browser:
     · mouse events arrive but Pointer Events (pointerdown / move / up) do not
     · moves report buttons = 0 while a button is held (no button modifiers on moves)
   Every minigame here uses pointer handlers and some read `buttons` during a drag, so
   either quirk makes clicks and drags "do nothing" in game while the browser preview works.

   What this does:
     · tracks the held buttons itself (mousedown / mouseup / pointerdown / pointerup)
     · a trusted move with buttons = 0 while we know a button is held gets the real value
     · a first-button mousedown without the pointerdown a browser always fires right before
       it switches to "synth" mode for the rest of the session: from then on every trusted
       mousedown / mousemove / mouseup is re-dispatched as pointerdown / pointermove /
       pointerup on the same target (pointerId 1, pointerType 'mouse', isPrimary)
   window.NZAInput = { buttons, synth, legacyZoom }  (read-only view for apps: NZAInput.buttons)
   ═══════════════════════════════════════════════════════════ */
(() => {
  const st = { buttons: 0, synth: false, pdPending: false };
  const BIT = [1, 4, 2, 8, 16];   // MouseEvent.button → buttons bit (0 left, 1 middle, 2 right)
  const bit = b => BIT[b] || 0;

  const fix = (e, value) => {
    if (e.buttons === value) return;
    try { Object.defineProperty(e, 'buttons', { value, configurable: true }); } catch (_) { /* leave it */ }
  };

  function synth(type, e) {
    let ev;
    try {
      ev = new PointerEvent(type, {
        bubbles: true, cancelable: true, composed: true, view: window,
        clientX: e.clientX, clientY: e.clientY, screenX: e.screenX, screenY: e.screenY,
        movementX: e.movementX, movementY: e.movementY,
        ctrlKey: e.ctrlKey, shiftKey: e.shiftKey, altKey: e.altKey, metaKey: e.metaKey,
        button: type === 'pointermove' ? -1 : e.button, buttons: st.buttons,
        pointerId: 1, pointerType: 'mouse', isPrimary: true, width: 1, height: 1, pressure: st.buttons ? 0.5 : 0,
      });
    } catch (_) { return; }
    ev.__nzaSynth = true;
    const target = e.target && e.target.isConnected ? e.target : (document.elementFromPoint(e.clientX, e.clientY) || document.body);
    target.dispatchEvent(ev);
  }

  // real pointer events: the detector, and the buttons kept honest. In synth mode the host's own
  // pointermove / pointerup (if any) are dropped: the re-dispatched ones replace them, no doubles.
  window.addEventListener('pointerdown', e => {
    if (e.__nzaSynth || !e.isTrusted) return;
    if (st.synth) { st.synth = false; console.info('[nza] pointer events arrived: back to native input'); }
    st.pdPending = true;
    st.buttons |= bit(e.button);
    fix(e, st.buttons);
  }, true);
  window.addEventListener('pointerup', e => {
    if (e.__nzaSynth || !e.isTrusted) return;
    if (st.synth) { e.stopImmediatePropagation(); return; }
    st.buttons &= ~bit(e.button);
    fix(e, st.buttons);
  }, true);
  window.addEventListener('pointermove', e => {
    if (e.__nzaSynth || !e.isTrusted) return;
    if (st.synth) { e.stopImmediatePropagation(); return; }
    if (e.buttons) st.buttons = e.buttons; else if (st.buttons) fix(e, st.buttons);
  }, true);

  window.addEventListener('mousedown', e => {
    if (!e.isTrusted) return;
    const b = bit(e.button);
    const first = (st.buttons & ~b) === 0;   // no other button held: a browser fires pointerdown first
    const sawPd = st.pdPending;
    st.pdPending = false;
    if (!st.synth && first && !sawPd) {
      st.synth = true;
      console.info('[nza] no pointer events from the host: re-dispatching mouse input as pointer events');
    }
    st.buttons |= b;
    fix(e, st.buttons);
    if (st.synth) synth(first ? 'pointerdown' : 'pointermove', e);
  }, true);
  window.addEventListener('mousemove', e => {
    if (!e.isTrusted) return;
    if (e.buttons) st.buttons = e.buttons; else if (st.buttons) fix(e, st.buttons);
    if (st.synth) synth('pointermove', e);
  }, true);
  window.addEventListener('mouseup', e => {
    if (!e.isTrusted) return;
    st.buttons &= ~bit(e.button);
    fix(e, st.buttons);
    if (st.synth) synth(st.buttons ? 'pointermove' : 'pointerup', e);
  }, true);

  // a release we never saw (focus went to the game, alt-tab) must not leave a button held
  const reset = () => { st.buttons = 0; st.pdPending = false; };
  window.addEventListener('blur', reset);
  document.addEventListener('visibilitychange', reset);

  /* ── CSS zoom (old Chromium) ──
     Every app section is scaled with CSS zoom (--nza-zoom = screen height / 1080). Chromium before
     128 (FiveM's CEF) returns getBoundingClientRect() inside a zoomed box in UNZOOMED px while mouse
     clientX / clientY are real screen px, so every "where on this element did I click" test lands
     in the wrong place at any resolution but 1080p. Detected once; when it is the old behaviour the
     rect is scaled by the zoom of the element and its ancestors, so all code can assume the new one. */
  let legacyZoom = null;
  function detectZoom() {
    if (legacyZoom !== null || !document.body) return legacyZoom;
    const host = document.createElement('div');
    host.style.cssText = 'position:fixed;left:0;top:0;zoom:2;visibility:hidden;pointer-events:none';
    const probe = document.createElement('div');
    probe.style.cssText = 'position:absolute;left:10px;top:0;width:100px;height:10px';
    host.appendChild(probe);
    document.body.appendChild(host);
    const w = nativeRect.call(probe).width;
    host.remove();
    legacyZoom = Math.abs(w - 100) < 1;   // new: 200
    if (legacyZoom) console.info('[nza] legacy CSS zoom: getBoundingClientRect is scaled to screen px');
    return legacyZoom;
  }
  const nativeRect = Element.prototype.getBoundingClientRect;
  // the zoom chain of an element rarely changes: remembered per element, forgotten on resize
  // (the page zoom follows the window height) and when the config re-applies --nza-zoom
  let zoomCache = new WeakMap();
  const forget = () => { zoomCache = new WeakMap(); };
  window.addEventListener('resize', forget);
  function ancestorZoom(el) {
    const hit = zoomCache.get(el);
    if (hit !== undefined) return hit;
    let z = 1;
    for (let n = el; n; n = n.parentElement) {   // the element's own zoom counts too
      const v = parseFloat(getComputedStyle(n).zoom);
      if (v > 0 && v !== 1) z *= v;
    }
    zoomCache.set(el, z);
    return z;
  }
  Element.prototype.getBoundingClientRect = function () {
    const r = nativeRect.call(this);
    if (!legacyZoom) { if (legacyZoom === null) detectZoom(); if (!legacyZoom) return r; }
    const z = ancestorZoom(this);
    return Math.abs(z - 1) < 1e-4 ? r : new DOMRect(r.x * z, r.y * z, r.width * z, r.height * z);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', detectZoom, { once: true });
  else detectZoom();

  window.NZAInput = {
    get buttons() { return st.buttons; },
    get synth() { return st.synth; },
    get legacyZoom() { return detectZoom(); },
    zoomChanged: forget,
    reset,
  };
})();
