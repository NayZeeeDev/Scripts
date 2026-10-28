// Supabase Storage helpers: signed direct uploads and public URLs for the `pulse-media` bucket.
//
// The uploader (NUI) sends a raw `PUT <uploadUrl>` with the image bytes as the body and exactly
// the headers returned here, matching what storage-js `uploadToSignedUrl` sends for a non-Blob
// body: `content-type`, `x-upsert` and `cache-control: max-age=3600`. No auth header is needed:
// the signed token in the URL authorises the write (valid 2 hours).

import type { SignedUpload, StorageApi } from "./types.ts";

export const MEDIA_BUCKET = "pulse-media";
const CACHE_CONTROL = "max-age=3600";

/** Thrown when Storage refuses to sign an upload. */
export class StorageFailure extends Error {
  constructor(message: string) {
    super(message);
    this.name = "StorageFailure";
  }
}

interface SignedUploadResult {
  data: { signedUrl: string; token: string; path: string } | null;
  error: { message: string } | null;
}

/** The part of a supabase-js client this module uses. */
export interface StorageClientLike {
  storage: {
    from(bucket: string): {
      createSignedUploadUrl(path: string, options?: { upsert: boolean }): Promise<SignedUploadResult>;
    };
  };
}

function encodePath(path: string): string {
  return path.split("/").map((segment) => encodeURIComponent(segment)).join("/");
}

function originOf(url: string): string {
  return new URL(url).origin;
}

/**
 * @param supabaseUrl SUPABASE_URL
 * @param publicUrl optional public origin override (PULSE_PUBLIC_URL) for setups where
 *   SUPABASE_URL is an internal address (local `supabase start` uses http://kong:8000).
 */
export function createStorage(client: StorageClientLike, supabaseUrl: string, publicUrl?: string): StorageApi {
  const publicOrigin = originOf(publicUrl?.trim() || supabaseUrl);
  const rewriteOrigin = publicUrl?.trim() ? publicOrigin : null;

  const publicUrlFor = (bucket: string, path: string): string =>
    `${publicOrigin}/storage/v1/object/public/${encodeURIComponent(bucket)}/${encodePath(path)}`;

  return {
    publicBase: `${publicOrigin}/storage/v1/object/public/${MEDIA_BUCKET}`,

    publicUrl: publicUrlFor,

    async signedUpload(bucket: string, path: string, contentType: string, upsert: boolean): Promise<SignedUpload> {
      const { data, error } = await client.storage.from(bucket).createSignedUploadUrl(path, { upsert });
      if (error || !data?.signedUrl) {
        throw new StorageFailure(`Could not sign upload: ${error?.message ?? "no URL returned"}`);
      }
      let uploadUrl = data.signedUrl;
      if (rewriteOrigin) {
        const signed = new URL(uploadUrl);
        uploadUrl = rewriteOrigin + signed.pathname + signed.search;
      }
      return {
        uploadUrl,
        headers: {
          "content-type": contentType,
          "x-upsert": upsert ? "true" : "false",
          "cache-control": CACHE_CONTROL,
        },
      };
    },
  };
}
