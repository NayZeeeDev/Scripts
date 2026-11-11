/**
 * The fob beep (Web Audio, no asset): two short sine chirps. Only for presses the game does not
 * already beep for (Lua sends FobPress.beep, honouring the player's fobBeep setting).
 */
let ctx: AudioContext | null = null;

export function fobBeep(panic = false) {
  try {
    const Ctor = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctor) return;
    ctx = ctx ?? new Ctor();
    if (ctx.state === 'suspended') void ctx.resume();
    const start = ctx.currentTime + 0.01;
    const tones = panic ? [1480, 1180, 1480] : [2100, 2650];
    tones.forEach((hz, i) => {
      const osc = ctx!.createOscillator();
      const gain = ctx!.createGain();
      const t0 = start + i * 0.085;
      osc.type = 'sine';
      osc.frequency.setValueAtTime(hz, t0);
      gain.gain.setValueAtTime(0.0001, t0);
      gain.gain.exponentialRampToValueAtTime(0.06, t0 + 0.008);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.07);
      osc.connect(gain).connect(ctx!.destination);
      osc.start(t0);
      osc.stop(t0 + 0.08);
    });
  } catch {
    /* audio is a nicety */
  }
}
