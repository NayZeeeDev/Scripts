// Action registry (SPEC §2.2). Every gateway action maps to the plpgsql function
// `pulse_act_<action with dots → underscores>`; this file only decides who may call it
// and how its params are cleaned before they reach SQL.

import type { JsonObject } from "./types.ts";
import {
  arr,
  bigId,
  bool,
  color,
  faIcon,
  handle,
  httpsUrl,
  imageUrl,
  int,
  Invalid,
  isoTime,
  language,
  nullable,
  num,
  obj,
  oneOf,
  opt,
  record,
  requireOneOf,
  schema,
  slug,
  str,
  tags,
  timeOfDay,
  txId,
  uuid,
  type ValidateContext,
  type ValidationError,
  type Validator,
  withDefault,
} from "./validate.ts";

/**
 * `server`: server-only, no actor (actor ignored if sent).
 * `actor`: needs the vouched player in `body.actor`.
 * `server+actor`: server-initiated (never a client passthrough) but scoped to a player.
 */
export type ActionKind = "server" | "actor" | "server+actor";

export interface ActionDef {
  kind: ActionKind;
  validate: (params: JsonObject, ctx: ValidateContext) => JsonObject | ValidationError;
  /** Validation reads network settings (chat length, image hosts). */
  needsSettings?: boolean;
}

// ---------------------------------------------------------------------------------------------
// Limits (SPEC §2 / §4)

export const LIMITS = {
  title: 120,
  displayName: 40,
  actorName: 64,
  bio: 400,
  panels: 6,
  panelTitle: 60,
  panelBody: 600,
  socials: 8,
  socialValue: 80,
  tags: 6,
  scheduleSlots: 21,
  goals: 5,
  chatHardMax: 500,
  cheerMax: 1_000_000,
  giftMax: 20,
  pollOptionsMin: 2,
  pollOptionsMax: 5,
  pollOption: 60,
  pollQuestion: 120,
  pollDurationMin: 30,
  pollDurationMax: 600,
  cashoutMax: 10_000_000,
  creditMax: 10_000_000,
  reason: 200,
  reportDetails: 500,
  rewardTitle: 60,
  rewardPrompt: 200,
  redeemInput: 200,
  search: 64,
  pointsTickViewers: 2_000,
  bannedWords: 200,
  pageMax: 100,
} as const;

// ---------------------------------------------------------------------------------------------
// Shared rules

const id = uuid;
const reasonText = () => str({ max: LIMITS.reason });
const title = (code = "bad_request") =>
  str({ max: LIMITS.title, tooLongCode: code, emptyCode: code });
const category = slug;
const scene = () => oneOf(["gameplay", "tripod", "handheld", "phone", "orbit"] as const);
const quality = () =>
  obj({
    width: int(16, 7680),
    height: int(16, 7680),
    fps: int(1, 120),
    tier: withDefault(int(0, 3), 0),
    bitrate: opt(int(50, 100_000)),
    filter: opt(str({ max: 24, pattern: /^[a-z0-9_-]+$/, hint: "must be a filter name" })),
  });
const pageLimit = (fallback: number) => withDefault(int(1, LIMITS.pageMax), fallback);
const pageOffset = () => withDefault(int(0, 1_000_000), 0);
const noParams = (): Validator => schema({});

/** chat.send / sparks.cheer bodies depend on settings, so they are checked after the shape. */
function chatText(key: string, required: boolean): (out: JsonObject, ctx: ValidateContext) => void {
  return (out, ctx) => {
    const value = out[key];
    if (!required && (value === undefined || (typeof value === "string" && value.trim() === ""))) {
      delete out[key];
      return;
    }
    out[key] = str({ max: ctx.chatMaxLength, tooLongCode: "too_long", emptyCode: "empty" })(
      value,
      `params.${key}`,
      ctx,
    );
  };
}

/** Passes the raw value through to a refine step (still must be present when required). */
function raw(required: boolean): (value: unknown, path: string) => string | undefined {
  return (value, path) => {
    if (value === undefined || value === null) {
      if (required) throw new Invalid(`${path} is required`, "empty");
      return undefined;
    }
    if (typeof value !== "string") throw new Invalid(`${path} must be a string`);
    return value;
  };
}

const panel = () =>
  obj({
    id: opt(str({ max: 40, pattern: /^[A-Za-z0-9_-]+$/, hint: "must be a short id" })),
    title: withDefault(str({ min: 0, max: LIMITS.panelTitle, tooLongCode: "too_long" }), ""),
    body: withDefault(str({ min: 0, max: LIMITS.panelBody, multiline: true, tooLongCode: "too_long" }), ""),
    link: nullable(httpsUrl(300)),
    image: nullable(imageUrl()),
  });

const scheduleSlot = () =>
  obj({
    day: int(0, 6),
    start: timeOfDay(),
    end: timeOfDay(),
    title: withDefault(str({ min: 0, max: 60, tooLongCode: "too_long" }), ""),
  });

const subBadge = () =>
  obj({
    name: str({ max: 24, tooLongCode: "too_long" }),
    icon: faIcon(),
    color: color(),
  });

/**
 * `{ "1": badge, "2": badge, "3": badge }` (partial). A Lua table keyed 1..3 arrives as a JSON
 * array, so `[badge1, badge2, badge3]` is accepted too and re-keyed by tier.
 */
const subBadges = () => {
  const tiers = obj({ "1": opt(subBadge()), "2": opt(subBadge()), "3": opt(subBadge()) });
  return (value: unknown, path: string, ctx: ValidateContext): JsonObject => {
    if (Array.isArray(value) && value.length > 0) {
      if (value.length > 3) throw new Invalid(`${path} must have at most 3 tiers`);
      return tiers(Object.fromEntries(value.map((badge, index) => [String(index + 1), badge])), path, ctx);
    }
    return tiers(value, path, ctx);
  };
};

const goal = () =>
  obj({
    id: opt(uuid()),
    type: oneOf(["followers", "subs", "sparks"] as const),
    title: withDefault(str({ min: 0, max: 60, tooLongCode: "too_long" }), ""),
    target: int(1, 100_000_000),
  });

const reward = () =>
  obj({
    id: opt(uuid()),
    title: str({ max: LIMITS.rewardTitle }),
    cost: int(1, 10_000_000),
    prompt: withDefault(nullable(str({ max: LIMITS.rewardPrompt })), null),
    color: withDefault(color(), "#08afa2"),
    icon: withDefault(faIcon(), "star"),
    cooldown: withDefault(int(0, 86_400), 0),
    maxPerStream: withDefault(int(0, 10_000), 0),
    enabled: withDefault(bool(), true),
    sort: withDefault(int(0, 1_000), 0),
  });

// ---------------------------------------------------------------------------------------------
// Registry

const entries: Record<string, ActionDef> = {
  // Server & discovery
  "server.hello": { kind: "server", validate: noParams() },
  "live.poll": { kind: "server", validate: schema({ since: opt(isoTime()) }) },

  // Accounts & profile
  "account.me": {
    kind: "actor",
    validate: schema({
      create: opt(bool()),
      name: opt(str({ max: LIMITS.actorName })),
    }),
  },
  "account.update": {
    kind: "actor",
    needsSettings: true,
    validate: schema(
      {
        handle: opt(handle("handle_invalid")),
        name: opt(str({ max: LIMITS.displayName, tooLongCode: "too_long" })),
        bio: opt(str({ min: 0, max: LIMITS.bio, multiline: true, tooLongCode: "too_long" })),
        avatar: nullable(imageUrl()),
        banner: nullable(imageUrl()),
        accent: opt(color()),
        socials: opt(record({
          keyPattern: /^[a-z0-9_]{1,20}$/,
          keyHint: "must be 1-20 characters of a-z, 0-9 and _",
          maxEntries: LIMITS.socials,
          value: str({ max: LIMITS.socialValue, tooLongCode: "too_long" }),
        })),
        panels: opt(arr(panel(), { max: LIMITS.panels })),
        schedule: opt(arr(scheduleSlot(), { max: LIMITS.scheduleSlots })),
        tags: opt(tags(LIMITS.tags)),
        language: opt(language()),
        mature: opt(bool()),
        pointsName: opt(str({ max: 24, tooLongCode: "too_long" })),
        pointsIcon: opt(faIcon()),
        subBadges: opt(subBadges()),
        goals: opt(arr(goal(), { max: LIMITS.goals })),
        notificationsOn: opt(bool()),
      },
      requireOneOf([
        "handle",
        "name",
        "bio",
        "avatar",
        "banner",
        "accent",
        "socials",
        "panels",
        "schedule",
        "tags",
        "language",
        "mature",
        "pointsName",
        "pointsIcon",
        "subBadges",
        "goals",
        "notificationsOn",
      ]),
    ),
  },
  // Format is judged by SQL so the answer can be { available:false, reason:"invalid" }.
  "account.handle_check": { kind: "actor", validate: schema({ handle: str({ max: 64 }) }) },
  "media.upload": {
    kind: "actor",
    validate: schema(
      {
        kind: oneOf(["avatar", "banner", "thumbnail", "panel"] as const),
        contentType: oneOf(["image/jpeg", "image/png", "image/webp"] as const),
        streamId: opt(uuid()),
      },
      (out) => {
        if (out.kind === "thumbnail" && out.streamId === undefined) {
          throw new Invalid("params.streamId is required for thumbnail uploads");
        }
      },
    ),
  },

  // Browse
  "browse.home": { kind: "actor", validate: noParams() },
  "browse.live": {
    kind: "actor",
    validate: schema({
      category: opt(category()),
      server: opt(slug()),
      sort: withDefault(oneOf(["viewers", "recent"] as const), "viewers"),
      limit: pageLimit(60),
      offset: pageOffset(),
    }),
  },
  "browse.search": { kind: "actor", validate: schema({ q: str({ max: LIMITS.search }) }) },
  "browse.following": { kind: "actor", validate: noParams() },
  "channel.get": {
    kind: "actor",
    validate: schema({ handle: opt(handle()), id: opt(id()) }, requireOneOf(["handle", "id"])),
  },

  // Follow / subs / sparks / wallet
  "follow.set": {
    kind: "actor",
    validate: schema({ channelId: id(), follow: bool(), notify: opt(bool()) }),
  },
  "wallet.get": { kind: "actor", validate: noParams() },
  "sparks.credit": {
    kind: "server+actor",
    validate: schema({
      amount: int(1, LIMITS.creditMax),
      reason: oneOf(["purchase", "card", "admin"] as const),
      money: opt(num(0, 1_000_000_000_000)),
      note: opt(str({ max: LIMITS.reason })),
      // Admin grants (`admin.give_sparks` in Lua) may target an account other than the actor.
      accountId: opt(uuid()),
    }),
  },
  "sparks.cheer": {
    kind: "actor",
    needsSettings: true,
    validate: schema(
      { channelId: id(), amount: int(1, LIMITS.cheerMax), message: raw(false) },
      chatText("message", false),
    ),
  },
  "sub.buy": {
    kind: "actor",
    validate: schema({ channelId: id(), tier: int(1, 3), autoRenew: opt(bool()) }),
  },
  "sub.gift": {
    kind: "actor",
    validate: schema({
      channelId: id(),
      tier: int(1, 3),
      count: int(1, LIMITS.giftMax),
      handle: opt(handle()),
    }),
  },
  "sub.cancel": { kind: "actor", validate: schema({ channelId: id() }) },
  "subs.mine": { kind: "actor", validate: noParams() },
  "cashout.request": {
    kind: "server+actor",
    validate: schema({
      amount: int(1, LIMITS.cashoutMax),
      mode: oneOf(["all", "trusted", "own"] as const),
    }),
  },
  "cashout.refund": { kind: "server+actor", validate: schema({ txId: txId() }) },

  // Streams
  "stream.start": {
    kind: "server+actor",
    validate: schema({
      title: title("title_invalid"),
      category: category(),
      tags: withDefault(tags(LIMITS.tags), []),
      language: withDefault(language(), "en"),
      mature: withDefault(bool(), false),
      scene: withDefault(scene(), "gameplay"),
      vertical: withDefault(bool(), false),
      quality: withDefault(quality(), { width: 1280, height: 720, fps: 30, tier: 0 }),
      micTier: withDefault(int(0, 3), 0),
    }),
  },
  "stream.update": {
    kind: "actor",
    validate: schema(
      {
        streamId: id(),
        title: opt(title("title_invalid")),
        category: opt(category()),
        tags: opt(tags(LIMITS.tags)),
        mature: opt(bool()),
        scene: opt(scene()),
        vertical: opt(bool()),
        quality: opt(quality()),
      },
      requireOneOf(["title", "category", "tags", "mature", "scene", "vertical", "quality"]),
    ),
  },
  "stream.heartbeat": {
    kind: "actor",
    validate: schema({
      streamId: id(),
      viewers: int(0, 10_000_000),
      health: opt(obj({
        bitrate: opt(num(0, 1_000_000)),
        fps: opt(num(0, 240)),
        packetLoss: opt(num(0, 100)),
      })),
    }),
  },
  "stream.end": {
    kind: "actor",
    validate: schema({ streamId: id(), reason: opt(str({ max: 40 })) }),
  },
  "stream.watch": { kind: "actor", validate: schema({ streamId: id() }) },
  "points.tick": {
    kind: "server",
    validate: schema({
      viewers: arr(
        obj({ ref: str({ max: 128, pattern: /^\S+$/, hint: "must not contain spaces" }), streamId: id() }),
        { max: LIMITS.pointsTickViewers },
      ),
    }),
  },

  // Chat & moderation
  "chat.send": {
    kind: "actor",
    needsSettings: true,
    validate: schema({ channelId: id(), body: raw(true) }, chatText("body", true)),
  },
  "chat.history": {
    kind: "actor",
    validate: schema({ channelId: id(), limit: pageLimit(50) }),
  },
  "chat.delete": { kind: "actor", validate: schema({ channelId: id(), messageId: bigId() }) },
  "chat.timeout": {
    kind: "actor",
    validate: schema({
      channelId: id(),
      accountId: id(),
      seconds: int(1, 1_209_600),
      reason: opt(reasonText()),
    }),
  },
  "chat.ban": {
    kind: "actor",
    validate: schema({ channelId: id(), accountId: id(), reason: opt(reasonText()) }),
  },
  "chat.unban": { kind: "actor", validate: schema({ channelId: id(), accountId: id() }) },
  "chat.clear": { kind: "actor", validate: schema({ channelId: id() }) },
  "chat.settings": {
    kind: "actor",
    validate: schema(
      {
        slowMode: opt(int(0, 3_600)),
        followersOnly: opt(int(-1, 129_600)),
        subsOnly: opt(bool()),
        emoteOnly: opt(bool()),
        linksAllowed: opt(bool()),
        bannedWords: opt(arr(str({ max: 40, lower: true }), { max: LIMITS.bannedWords, unique: true })),
      },
      requireOneOf(["slowMode", "followersOnly", "subsOnly", "emoteOnly", "linksAllowed", "bannedWords"]),
    ),
  },
  "mods.list": { kind: "actor", validate: noParams() },
  "mods.set": { kind: "actor", validate: schema({ handle: handle(), mod: bool() }) },
  "bans.list": { kind: "actor", validate: schema({ channelId: opt(id()) }) },
  "user.card": { kind: "actor", validate: schema({ channelId: id(), accountId: id() }) },

  // Interaction
  "rewards.list": { kind: "actor", validate: schema({ channelId: id() }) },
  "rewards.save": { kind: "actor", validate: schema({ reward: reward() }) },
  "rewards.delete": { kind: "actor", validate: schema({ id: id() }) },
  "rewards.redeem": {
    kind: "actor",
    validate: schema({ rewardId: id(), input: opt(str({ max: LIMITS.redeemInput })) }),
  },
  "redemptions.list": {
    kind: "actor",
    validate: schema({ status: opt(oneOf(["pending", "done", "refunded"] as const)) }),
  },
  "redemptions.update": {
    kind: "actor",
    validate: schema({ id: id(), status: oneOf(["done", "refunded"] as const) }),
  },
  "poll.create": {
    kind: "actor",
    validate: schema({
      question: str({ max: LIMITS.pollQuestion }),
      options: arr(str({ max: LIMITS.pollOption }), {
        min: LIMITS.pollOptionsMin,
        max: LIMITS.pollOptionsMax,
      }),
      duration: int(LIMITS.pollDurationMin, LIMITS.pollDurationMax),
    }),
  },
  "poll.vote": {
    kind: "actor",
    validate: schema({ pollId: id(), option: int(0, LIMITS.pollOptionsMax - 1) }),
  },
  "poll.end": { kind: "actor", validate: schema({ pollId: id() }) },
  "raid.start": { kind: "actor", validate: schema({ handle: handle() }) },

  // Dashboard
  "dash.overview": { kind: "actor", validate: schema({ range: withDefault(oneOf([7, 30] as const), 7) }) },
  "dash.followers": { kind: "actor", validate: schema({ offset: pageOffset(), limit: pageLimit(50) }) },
  "dash.subs": { kind: "actor", validate: schema({ offset: pageOffset(), limit: pageLimit(50) }) },
  "activity.list": {
    kind: "actor",
    validate: schema({ limit: pageLimit(50), before: opt(bigId()) }),
  },

  // Reports & admin
  "report.create": {
    kind: "actor",
    validate: schema({
      channelId: id(),
      streamId: opt(id()),
      reason: oneOf(["harassment", "hate", "nsfw", "spam", "cheating", "other"] as const),
      details: opt(str({ max: LIMITS.reportDetails, multiline: true })),
    }),
  },
  "admin.streams": { kind: "server", validate: noParams() },
  "admin.end_stream": {
    kind: "server",
    validate: schema({ streamId: id(), reason: withDefault(reasonText(), "admin") }),
  },
  "admin.ban": {
    kind: "server",
    validate: schema({ accountId: id(), banned: bool(), reason: opt(reasonText()) }),
  },
  "admin.reports": {
    kind: "server",
    validate: schema({ status: opt(oneOf(["open", "reviewed", "dismissed", "actioned"] as const)) }),
  },
  "admin.report_update": {
    kind: "server",
    validate: schema({ id: id(), status: oneOf(["reviewed", "dismissed", "actioned"] as const) }),
  },
  "admin.verify": {
    kind: "server",
    validate: schema(
      { accountId: id(), verified: opt(bool()), partner: opt(bool()) },
      requireOneOf(["verified", "partner"]),
    ),
  },
  "admin.lookup": { kind: "server", validate: schema({ q: str({ max: LIMITS.search }) }) },
};

/** Frozen registry of every action in SPEC §2.2. */
export const ACTIONS: Readonly<Record<string, ActionDef>> = Object.freeze(entries);

/** Registry lookup that ignores inherited keys (`constructor`, `__proto__`, ...). */
export function getAction(name: string): ActionDef | undefined {
  return Object.hasOwn(ACTIONS, name) ? ACTIONS[name] : undefined;
}

/** `chat.send` → `pulse_act_chat_send`. */
export function rpcName(action: string): string {
  return "pulse_act_" + action.replaceAll(".", "_");
}
