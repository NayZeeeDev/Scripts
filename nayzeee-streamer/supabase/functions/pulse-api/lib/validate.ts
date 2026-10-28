// Strict parameter validation (SPEC §4): small composable rules that either return a cleaned
// JSON value or throw `Invalid`. `schema()` turns a shape into an action validator that returns
// the cleaned params (unknown keys dropped) or a `ValidationError`.

import type { Json, JsonObject } from "./types.ts";

/** Returned (never thrown) by action validators. Serialises to the wire error shape. */
export class ValidationError {
  readonly ok = false as const;
  constructor(readonly error: string, readonly message: string) {}

  toJSON(): { ok: false; error: string; message: string } {
    return { ok: false, error: this.error, message: this.message };
  }
}

/** Values validators need from outside the request. */
export interface ValidateContext {
  /** Max chat body length (settings.chatMaxLength, capped at 500). */
  chatMaxLength: number;
  /** settings.imageHosts, lower-cased. */
  imageHosts: readonly string[];
  /** Origin of the project's own public storage (always allowed for images). */
  storageOrigin: string;
}

/** Thrown inside rules; converted to `ValidationError` by `schema()`. */
export class Invalid extends Error {
  constructor(message: string, readonly code: string = "bad_request") {
    super(message);
    this.name = "Invalid";
  }
}

export type Rule<T> = (value: unknown, path: string, ctx: ValidateContext) => T;
export type Shape = Record<string, Rule<Json | undefined>>;
export type Validator = (params: JsonObject, ctx: ValidateContext) => JsonObject | ValidationError;

export const HANDLE_RE = /^[A-Za-z0-9_]{3,20}$/;
export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const COLOR_RE = /^#[0-9a-fA-F]{6}$/;
const BIGINT_ID_RE = /^[1-9][0-9]{0,18}$/;
const SLUG_RE = /^[a-z0-9][a-z0-9_-]{0,39}$/;
const ICON_RE = /^[a-z0-9][a-z0-9-]{0,39}$/;
const LANGUAGE_RE = /^[a-z]{2,3}(-[a-z0-9]{2,8})?$/;
const TIME_RE = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
const TAG_RE = /^[a-z0-9- ]+$/;

// Invisible bidi controls and zero-width spaces (ZWJ/ZWNJ stay: emoji sequences need them).
const INVISIBLE_RE = /[​‪-‮⁠-⁤⁦-⁩﻿]/g;
// deno-lint-ignore no-control-regex
const CONTROL_RUN_RE = /[\u0000-\u001F\u007F-\u009F]+/g;
// deno-lint-ignore no-control-regex
const CONTROL_MULTILINE_RE = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/g;
const RAW_STRING_HARD_LIMIT = 20_000;
const MAX_ISO_LENGTH = 40;

function isAbsent(value: unknown): value is null | undefined {
  return value === undefined || value === null;
}

export function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

function requirePresent(value: unknown, path: string): void {
  if (isAbsent(value)) throw new Invalid(`${path} is required`);
}

/** Number of Unicode code points (matches Postgres `char_length`). */
export function charLength(value: string): number {
  let count = 0;
  for (const _ of value) count++;
  return count;
}

function cleanText(raw: string, multiline: boolean): string {
  let text = raw.normalize("NFC").replace(INVISIBLE_RE, "");
  if (multiline) {
    text = text
      .replace(/\r\n?/g, "\n")
      .replace(/\t/g, " ")
      .replace(CONTROL_MULTILINE_RE, "")
      .replace(/[ ]+\n/g, "\n")
      .replace(/\n{3,}/g, "\n\n");
  } else {
    text = text.replace(CONTROL_RUN_RE, " ");
  }
  return text.trim();
}

// ---------------------------------------------------------------------------------------------
// Modifiers

/** Absent (undefined/null) → omitted from the cleaned output. */
export function opt<T extends Json>(rule: Rule<T>): Rule<T | undefined> {
  return (value, path, ctx) => (isAbsent(value) ? undefined : rule(value, path, ctx));
}

/** undefined → omitted, null (or "" when `emptyAsNull`) → null (clears the field), else validated. */
export function nullable<T extends Json>(rule: Rule<T>, emptyAsNull = true): Rule<T | null | undefined> {
  return (value, path, ctx) => {
    if (value === undefined) return undefined;
    if (value === null) return null;
    if (emptyAsNull && typeof value === "string" && value.trim() === "") return null;
    return rule(value, path, ctx);
  };
}

/** Absent → `fallback`. */
export function withDefault<T extends Json | undefined, F extends Json>(rule: Rule<T>, fallback: F): Rule<T | F> {
  return (value, path, ctx) => (isAbsent(value) ? structuredClone(fallback) : rule(value, path, ctx));
}

// ---------------------------------------------------------------------------------------------
// Scalars

export interface StrOptions {
  /** Minimum length after cleaning (default 1). */
  min?: number;
  max: number;
  multiline?: boolean;
  lower?: boolean;
  pattern?: RegExp;
  /** Completes "<path> ..." when the pattern fails. */
  hint?: string;
  /** Error codes for specific failures (default `bad_request`). */
  tooLongCode?: string;
  emptyCode?: string;
  invalidCode?: string;
}

export function str(options: StrOptions): Rule<string> {
  const min = options.min ?? 1;
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "string") throw new Invalid(`${path} must be a string`);
    if (value.length > RAW_STRING_HARD_LIMIT) {
      throw new Invalid(`${path} must be at most ${options.max} characters`, options.tooLongCode);
    }
    let text = cleanText(value, options.multiline === true);
    if (options.lower) text = text.toLowerCase();
    const length = charLength(text);
    if (length < min) {
      if (length === 0) throw new Invalid(`${path} must not be empty`, options.emptyCode);
      throw new Invalid(`${path} must be at least ${min} characters`, options.invalidCode);
    }
    if (length > options.max) {
      throw new Invalid(`${path} must be at most ${options.max} characters`, options.tooLongCode);
    }
    if (options.pattern && !options.pattern.test(text)) {
      throw new Invalid(`${path} ${options.hint ?? "has an invalid format"}`, options.invalidCode);
    }
    return text;
  };
}

export function int(min: number, max: number): Rule<number> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "number" || !Number.isInteger(value)) throw new Invalid(`${path} must be an integer`);
    if (value < min || value > max) throw new Invalid(`${path} must be between ${min} and ${max}`);
    return value;
  };
}

export function num(min: number, max: number): Rule<number> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "number" || !Number.isFinite(value)) throw new Invalid(`${path} must be a number`);
    if (value < min || value > max) throw new Invalid(`${path} must be between ${min} and ${max}`);
    return value;
  };
}

export function bool(): Rule<boolean> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "boolean") throw new Invalid(`${path} must be true or false`);
    return value;
  };
}

export function oneOf<const T extends string | number>(values: readonly T[]): Rule<T> {
  const list = values.map((v) => JSON.stringify(v)).join(", ");
  return (value, path) => {
    requirePresent(value, path);
    const match = values.find((candidate) => candidate === value);
    if (match === undefined) throw new Invalid(`${path} must be one of ${list}`);
    return match;
  };
}

/** A uuid string, returned lower-cased. */
export function uuid(): Rule<string> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "string" || !UUID_RE.test(value.trim())) throw new Invalid(`${path} must be a uuid`);
    return value.trim().toLowerCase();
  };
}

/** A bigint row id (chat, activity): positive integer or string of digits, returned as a string. */
export function bigId(): Rule<string> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value === "number" && Number.isSafeInteger(value) && value > 0) return String(value);
    if (typeof value === "string" && BIGINT_ID_RE.test(value.trim())) return value.trim();
    throw new Invalid(`${path} must be a numeric id`);
  };
}

/** A transaction id: a bigint id or a uuid, returned as a string. */
export function txId(): Rule<string> {
  const asBig = bigId();
  return (value, path, ctx) => {
    requirePresent(value, path);
    if (typeof value === "string" && UUID_RE.test(value.trim())) return value.trim().toLowerCase();
    try {
      return asBig(value, path, ctx);
    } catch {
      throw new Invalid(`${path} must be a transaction id`);
    }
  };
}

/** An ISO 8601 timestamp, normalised to UTC `toISOString()`. */
export function isoTime(): Rule<string> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "string" || value.length > MAX_ISO_LENGTH) {
      throw new Invalid(`${path} must be an ISO 8601 timestamp`);
    }
    const ms = Date.parse(value);
    if (Number.isNaN(ms)) throw new Invalid(`${path} must be an ISO 8601 timestamp`);
    return new Date(ms).toISOString();
  };
}

/** Channel handle `^[A-Za-z0-9_]{3,20}$` (case kept; uniqueness is case-insensitive in SQL). */
export function handle(invalidCode = "bad_request"): Rule<string> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "string") throw new Invalid(`${path} must be a string`, invalidCode);
    const text = value.trim();
    if (!HANDLE_RE.test(text)) {
      throw new Invalid(`${path} must be 3-20 characters of letters, numbers and underscores`, invalidCode);
    }
    return text;
  };
}

/** `#RRGGBB`, returned lower-cased. */
export function color(): Rule<string> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "string" || !COLOR_RE.test(value.trim())) {
      throw new Invalid(`${path} must be a hex color like #08afa2`);
    }
    return value.trim().toLowerCase();
  };
}

/** Font Awesome icon name without the `fa-` prefix (a leading `fa-` is stripped). */
export function faIcon(): Rule<string> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "string") throw new Invalid(`${path} must be a string`);
    let name = value.trim().toLowerCase();
    if (name.startsWith("fa-")) name = name.slice(3);
    if (!ICON_RE.test(name)) throw new Invalid(`${path} must be a Font Awesome icon name like "bolt"`);
    return name;
  };
}

/** Lower-case slug for categories and servers. */
export function slug(): Rule<string> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "string") throw new Invalid(`${path} must be a string`);
    const text = value.trim().toLowerCase();
    if (!SLUG_RE.test(text)) throw new Invalid(`${path} must be a slug (a-z, 0-9, - and _, max 40)`);
    return text;
  };
}

/** Language code like `en` or `pt-br`. */
export function language(): Rule<string> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "string") throw new Invalid(`${path} must be a string`);
    const text = value.trim().toLowerCase();
    if (!LANGUAGE_RE.test(text)) throw new Invalid(`${path} must be a language code like "en"`);
    return text;
  };
}

/** `HH:MM` 24h clock time. */
export function timeOfDay(): Rule<string> {
  return (value, path) => {
    requirePresent(value, path);
    if (typeof value !== "string" || !TIME_RE.test(value.trim())) throw new Invalid(`${path} must be a time "HH:MM"`);
    return value.trim();
  };
}

function parseUrl(value: unknown, path: string, max: number, code: string): URL {
  requirePresent(value, path);
  if (typeof value !== "string") throw new Invalid(`${path} must be a URL string`);
  const text = value.trim();
  if (text.length > max) throw new Invalid(`${path} must be at most ${max} characters`, "too_long");
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    throw new Invalid(`${path} must be an absolute URL`, code);
  }
  if (url.username || url.password) throw new Invalid(`${path} must not contain credentials`, code);
  return url;
}

/** True when `hostname` is on the network image allowlist (`*.x` / `.x` entries match subdomains). */
export function hostAllowed(hostname: string, allowlist: readonly string[]): boolean {
  const host = hostname.toLowerCase();
  for (const raw of allowlist) {
    const entry = raw.trim().toLowerCase();
    if (!entry) continue;
    if (entry.startsWith("*.")) {
      if (host.endsWith(entry.slice(1))) return true;
    } else if (entry.startsWith(".")) {
      if (host.endsWith(entry)) return true;
    } else if (host === entry) {
      return true;
    }
  }
  return false;
}

/** Image URL: on the project's storage origin, or https on a host from settings.imageHosts. */
export function imageUrl(max = 500): Rule<string> {
  return (value, path, ctx) => {
    const url = parseUrl(value, path, max, "bad_image_host");
    if (ctx.storageOrigin && url.origin === ctx.storageOrigin) return url.href;
    if (url.protocol !== "https:") throw new Invalid(`${path} must be an https URL`, "bad_image_host");
    if (!hostAllowed(url.hostname, ctx.imageHosts)) {
      throw new Invalid(`${path} host "${url.hostname}" is not an allowed image host`, "bad_image_host");
    }
    return url.href;
  };
}

/** Any https link (panels). */
export function httpsUrl(max = 300): Rule<string> {
  return (value, path) => {
    const url = parseUrl(value, path, max, "bad_request");
    if (url.protocol !== "https:") throw new Invalid(`${path} must be an https URL`);
    return url.href;
  };
}

// ---------------------------------------------------------------------------------------------
// Containers

export interface ArrOptions {
  min?: number;
  max: number;
  /** Drop duplicate items (compared by JSON). */
  unique?: boolean;
}

export function arr<T extends Json>(item: Rule<T>, options: ArrOptions): Rule<T[]> {
  const min = options.min ?? 0;
  return (value, path, ctx) => {
    requirePresent(value, path);
    if (!Array.isArray(value)) throw new Invalid(`${path} must be an array`);
    if (value.length > options.max) throw new Invalid(`${path} must have at most ${options.max} items`);
    const out: T[] = [];
    const seen = new Set<string>();
    value.forEach((raw, index) => {
      const cleaned = item(raw, `${path}[${index}]`, ctx);
      if (options.unique) {
        const key = JSON.stringify(cleaned);
        if (seen.has(key)) return;
        seen.add(key);
      }
      out.push(cleaned);
    });
    if (out.length < min) throw new Invalid(`${path} must have at least ${min} items`);
    return out;
  };
}

/**
 * Lua's JSON encoder turns an empty table into `[]`, so an empty array is accepted wherever an
 * object is expected.
 */
export function asObject(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value) && value.length === 0) return {};
  return isPlainObject(value) ? value : null;
}

/** Plain object with a fixed shape. Unknown keys are dropped. */
export function obj(shape: Shape): Rule<JsonObject> {
  const keys = Object.keys(shape);
  return (input, path, ctx) => {
    requirePresent(input, path);
    const value = asObject(input);
    if (!value) throw new Invalid(`${path} must be an object`);
    const out: JsonObject = {};
    for (const key of keys) {
      const raw = Object.hasOwn(value, key) ? value[key] : undefined;
      const cleaned = shape[key](raw, `${path}.${key}`, ctx);
      if (cleaned !== undefined) out[key] = cleaned;
    }
    return out;
  };
}

const FORBIDDEN_KEYS = new Set(["__proto__", "constructor", "prototype"]);

export interface RecordOptions {
  keyPattern: RegExp;
  keyHint: string;
  maxEntries: number;
  /** Entries whose cleaned value is "" are dropped. */
  value: Rule<string>;
}

/** Free-form `{ key: string }` map (socials). Keys are lower-cased. */
export function record(options: RecordOptions): Rule<JsonObject> {
  return (input, path, ctx) => {
    requirePresent(input, path);
    const value = asObject(input);
    if (!value) throw new Invalid(`${path} must be an object`);
    const entries: [string, string][] = [];
    for (const [rawKey, rawValue] of Object.entries(value)) {
      const key = rawKey.trim().toLowerCase();
      if (!options.keyPattern.test(key) || FORBIDDEN_KEYS.has(key)) {
        throw new Invalid(`${path} key "${rawKey.slice(0, 40)}" ${options.keyHint}`);
      }
      if (isAbsent(rawValue) || (typeof rawValue === "string" && rawValue.trim() === "")) continue;
      entries.push([key, options.value(rawValue, `${path}.${key}`, ctx)]);
    }
    if (entries.length > options.maxEntries) {
      throw new Invalid(`${path} must have at most ${options.maxEntries} entries`);
    }
    return Object.fromEntries(entries);
  };
}

/** Up to `max` tags of `[a-z0-9- ]`, each ≤ 20 characters; lower-cased and de-duplicated. */
export function tags(max = 6): Rule<string[]> {
  return arr(
    str({ max: 20, lower: true, pattern: TAG_RE, hint: "may only contain a-z, 0-9, - and spaces" }),
    { max, unique: true },
  );
}

// ---------------------------------------------------------------------------------------------
// Action validators

/**
 * Builds an action validator from a shape. `refine` runs on the cleaned params for
 * cross-field rules and may throw `Invalid`.
 */
export function schema(shape: Shape, refine?: (out: JsonObject, ctx: ValidateContext) => void): Validator {
  const rule = obj(shape);
  return (params, ctx) => {
    try {
      const out = rule(params, "params", ctx);
      refine?.(out, ctx);
      return out;
    } catch (err) {
      if (err instanceof Invalid) return new ValidationError(err.code, err.message);
      throw err;
    }
  };
}

/** Requires at least one of `keys` in the cleaned output. */
export function requireOneOf(keys: readonly string[]): (out: JsonObject) => void {
  return (out) => {
    if (!keys.some((key) => out[key] !== undefined)) {
      throw new Invalid(`params must include at least one of: ${keys.join(", ")}`);
    }
  };
}
