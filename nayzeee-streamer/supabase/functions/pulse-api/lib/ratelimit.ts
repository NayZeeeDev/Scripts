// In-memory token buckets (SPEC §4): one limiter per policy, one bucket per key.
// Buckets live in insertion order and are touched on use, so the oldest idle key is evicted
// first when the key cap is reached.

export interface TakeResult {
  allowed: boolean;
  /** Milliseconds until `cost` tokens are available again (0 when allowed). */
  retryAfterMs: number;
}

interface Bucket {
  tokens: number;
  at: number;
}

export class TokenBuckets {
  readonly #buckets = new Map<string, Bucket>();

  /**
   * @param rate tokens refilled per second
   * @param burst bucket capacity
   * @param maxKeys keys kept in memory before the least recently used one is dropped
   */
  constructor(readonly rate: number, readonly burst: number, readonly maxKeys = 10_000) {
    if (!(rate > 0) || !(burst >= 1)) throw new RangeError("TokenBuckets needs rate > 0 and burst >= 1");
  }

  take(key: string, nowMs: number, cost = 1): TakeResult {
    let bucket = this.#buckets.get(key);
    if (bucket) {
      this.#buckets.delete(key);
      const elapsedSec = Math.max(0, nowMs - bucket.at) / 1000;
      bucket.tokens = Math.min(this.burst, bucket.tokens + elapsedSec * this.rate);
      bucket.at = nowMs;
    } else {
      bucket = { tokens: this.burst, at: nowMs };
    }
    this.#buckets.set(key, bucket);
    while (this.#buckets.size > this.maxKeys) {
      const oldest = this.#buckets.keys().next();
      if (oldest.done) break;
      this.#buckets.delete(oldest.value);
    }
    if (bucket.tokens >= cost) {
      bucket.tokens -= cost;
      return { allowed: true, retryAfterMs: 0 };
    }
    return { allowed: false, retryAfterMs: Math.ceil(((cost - bucket.tokens) / this.rate) * 1000) };
  }

  get size(): number {
    return this.#buckets.size;
  }
}

/** Per server: 40 requests/s, burst 80. */
export function serverLimiter(): TokenBuckets {
  return new TokenBuckets(40, 80, 5_000);
}

/** Per actor (server + ref) for `chat.send`: 1 message/s, burst 3. */
export function chatLimiter(): TokenBuckets {
  return new TokenBuckets(1, 3, 50_000);
}
