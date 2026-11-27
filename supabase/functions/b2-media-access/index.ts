import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, GetObjectCommand } from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const allowedOrigins = new Set(["https://match.beyondthebinarymedia.online"]);
const media = {
  stories: { table: "stories", column: "media_url", idColumn: "id" },
  chat_media: { table: "chat_media", column: "storage_path", idColumn: "id" },
  verification_selfies: { table: "verification_requests", column: "selfie_path", idColumn: "id" },
  event_posters: { table: "match_event_poster_assets", column: "storage_path", idColumn: "event_id" },
} as const;

function json(body: unknown, status: number, origin: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
}

function isAdvertiserSession(token: string): boolean {
  try {
    const segment = token.split(".")[1];
    if (!segment) return false;
    const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    return payload.role === "anon" && payload.user_role === "advertiser";
  } catch {
    return false;
  }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") || "";
  if (origin && !allowedOrigins.has(origin)) return json({ error: "Origin not allowed" }, 403, origin);
  if (req.method === "OPTIONS") return new Response("ok", {
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const url = Deno.env.get("SUPABASE_URL") || "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") || "";
    const bucket = Deno.env.get("B2_BUCKET_NAME") || "";
    const endpoint = Deno.env.get("B2_S3_ENDPOINT") || "";
    const keyId = Deno.env.get("B2_KEY_ID") || "";
    const appKey = Deno.env.get("B2_APPLICATION_KEY") || "";
    if (!token || token === authHeader) return json({ error: "Authentication required" }, 401, origin);
    if (!url || !anon || !bucket || !endpoint || !keyId || !appKey) {
      return json({ error: "B2 media access is not configured" }, 500, origin);
    }

    const caller = createClient(url, anon, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: authError } = await caller.auth.getUser(token);
    if (authError || !userData.user) return json({ error: "Invalid session" }, 401, origin);
    if (isAdvertiserSession(token)) return json({ error: "Advertiser accounts cannot access member media." }, 403, origin);

    const body = await req.json().catch(() => null);
    const category = body?.category as keyof typeof media;
    const objectKey = typeof body?.objectKey === "string" ? body.objectKey : "";
    if (!category || !(category in media) || !objectKey || objectKey.length > 500 ||
        !objectKey.startsWith("users/") || objectKey.includes("..") || objectKey.includes("\\\\")) {
      return json({ error: "Invalid media request" }, 400, origin);
    }

    const storagePath = `b2://${objectKey}`;
    const config = media[category];
    const query = new URLSearchParams({
      select: config.idColumn,
      [config.column]: `eq.${storagePath}`,
    });
    const recordResponse = await fetch(
      `${url}/rest/v1/${config.table}?${query.toString()}`,
      { headers: { apikey: anon, Authorization: authHeader, Accept: "application/json" } },
    );
    if (!recordResponse.ok) return json({ error: "Media access denied" }, 403, origin);
    const records = await recordResponse.json();
    if (!Array.isArray(records) || records.length !== 1) {
      return json({ error: "Media not found or access denied" }, 403, origin);
    }

    const host = new URL(endpoint).hostname;
    const region = Deno.env.get("B2_REGION") ||
      host.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
    if (!region) return json({ error: "B2 region is not configured" }, 500, origin);
    const s3 = new S3Client({
      region,
      endpoint,
      forcePathStyle: true,
      credentials: { accessKeyId: keyId, secretAccessKey: appKey },
    });
    const command = new GetObjectCommand({ Bucket: bucket, Key: objectKey });
    const downloadUrl = await getSignedUrl(s3, command, { expiresIn: 120 });
    return json({ downloadUrl, expiresIn: 120 }, 200, origin);
  } catch (error) {
    console.error("B2 media access failed:", error instanceof Error ? error.message : "unknown error");
    return json({ error: "Unable to authorize media access" }, 500, origin);
  }
});
