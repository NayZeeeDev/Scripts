/**
 * Signal reader maths (no React): the match between the tuned input and the ignition's
 * reference signal. 100% only inside the server's tolerance (the server checks the same).
 */
import type { ReaderPuzzle } from '@/lib/types';

export const FREQ_MIN = 300;
export const FREQ_MAX = 900;

/** shortest angle between two phases, degrees 0..180 */
export function phaseGap(a: number, b: number): number {
  return Math.abs((((a - b + 180) % 360) + 360) % 360 - 180);
}

export function inTolerance(freq: number, phase: number, ref: ReaderPuzzle): boolean {
  const tol = ref.tolerance ?? { frequency: 1.5, phase: 8 };
  return Math.abs(freq - ref.frequency) <= tol.frequency && phaseGap(phase, ref.phase) <= tol.phase;
}

/** 0..100: 100 only inside the tolerance; continuous outside it so the player can climb. */
export function matchOf(freq: number, phase: number, ref: ReaderPuzzle): number {
  if (inTolerance(freq, phase, ref)) return 100;
  const tol = ref.tolerance ?? { frequency: 1.5, phase: 8 };
  const df = Math.max(0, Math.abs(freq - ref.frequency) - tol.frequency);
  const dp = Math.max(0, phaseGap(phase, ref.phase) - tol.phase);
  const f = 0.5 * Math.exp(-df / 160) + 0.5 / (1 + (df / 6) ** 2);
  const p = 0.35 + 0.65 * ((1 + Math.cos((dp * Math.PI) / 180)) / 2);
  return Math.max(0, Math.min(99, Math.floor(99 * f * p)));
}

/** Wave cycles across the screen for a frequency (MHz). */
export const cyclesOf = (freq: number) => freq / 80;

export const wrapPhase = (p: number) => ((Math.round(p) % 360) + 360) % 360;
export const clampFreq = (f: number) => Math.round(Math.max(FREQ_MIN, Math.min(FREQ_MAX, f)) * 10) / 10;

/** A start far from the answer (at least 90 MHz away, phase at least 60 deg off). */
export function startOf(ref: ReaderPuzzle, rnd: () => number = Math.random): { freq: number; phase: number } {
  let freq = FREQ_MIN + rnd() * (FREQ_MAX - FREQ_MIN);
  if (Math.abs(freq - ref.frequency) < 90) freq = ref.frequency + (ref.frequency > 600 ? -1 : 1) * (120 + rnd() * 120);
  let phase = rnd() * 360;
  if (phaseGap(phase, ref.phase) < 60) phase = ref.phase + 120 + rnd() * 120;
  return { freq: clampFreq(freq), phase: wrapPhase(phase) };
}
