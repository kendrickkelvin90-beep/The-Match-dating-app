import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, PutObjectCommand } from "npm:@aws-sdk/client-s3";

const allowedOrigins = new Set([
  "https://match.beyondthebinarymedia.online",
]);

const json = (body: unknown, status = 200, origin = "") =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });

const categories = {
  profile_photos: { table: "profile_photos", bucket: "profile-photos", pathColumn: "storage_path", ownerColumn: "user_id", idColumn: "id" },
  stories: { table: "stories", bucket: "story-media", pathColumn: "media_url", ownerColumn: "user_id", idColumn: "id" },
  chat_media: { table: "chat_media", bucket: "chat-media", pathColumn: "storage_path", ownerColumn: "sender_id", idColumn: "id" },
  verification_selfies: { table: "verification_requests", bucket: "verification-selfies", pathColumn: "selfie_path", ownerColumn: "user_id", idColumn: "id" },
  event_posters: { table: "match_event_poster_assets", bucket: "event-posters", pathColumn: "storage_path", ownerColumn: "organiser_id", idColumn: "event_id" },
} as const;

type Category = keyof typeof categories;

const required = [
  "SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY",
  "B2_KEY_ID", "B2_APPLICATION_KEY", "B2_BUCKET_NAME", "B2_S3_ENDPOINT",
];

function getStorageClient() {
  const missing = required.filter((key) => !Deno.env.get(key));
  if (missing.length) throw new Error("Missing server configuration: " + missing.join(", "));
  const endpoint = Deno.env.get("B2_S3_ENDPOINT")!;
  const host = new URL(endpoint).hostname;
  const inferredRegion = host.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
  const region = Deno.env.get("B2_REGION") || inferredRegion;
  if (!region) throw new Error("Set B2_REGION or use a regional Backblaze S3 endpoint.");
  return new S3Client({
    region,
    endpoint,
    forcePathStyle: true,
    credentials: {
      accessKeyId: Deno.env.get("B2_KEY_ID")!,
      secretAccessKey: Deno.env.get("B2_APPLICATION_KEY")!,
    },
  });
}

function safeFilename(path: string) {
  const name = path.split("/").pop() || "media";
  return name.replace(/[^a-zA-Z0-9._-]/g, "_").slice(-100) || "media";
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") || "";
  if (origin && !allowedOrigins.has(origin)) return json({ error: "Origin not allowed" }, 403);
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
    if (!token || token === authHeader) return json({ error: "Authentication required" }, 401, origin);

    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const caller = createClient(url, anon, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData, error: authError } = await caller.auth.getUser(token);
    if (authError || !userData.user) return json({ error: "Invalid session" }, 401, origin);
    const { data: isAdmin, error: adminError } = await caller.rpc("is_match_admin");
    if (adminError || isAdmin !== true) return json({ error: "Admin access required" }, 403, origin);

    const body = await req.json().catch(() => null);
    const category = body?.category as Category;
    if (!category || !(category in categories)) {
      return json({ error: "Choose a supported media category." }, 400, origin);
    }
    const limit = Math.max(1, Math.min(2, Number.isInteger(body?.limit) ? body.limit : 2));
    const config = categories[category];
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const s3 = getStorageClient();
    const bucket = Deno.env.get("B2_BUCKET_NAME")!;

    const { data: rows, error: listError } = await admin
      .from(config.table)
      .select("*")
      .not(config.pathColumn, "like", "b2://%")
      .not(config.pathColumn, "is", null)
      .order("created_at", { ascending: true })
      .limit(limit);
    if (listError) throw new Error("Could not list legacy media records.");

    let migrated = 0;
    let failed = 0;
    const failures: string[] = [];
    for (const row of rows || []) {
      const oldPath = String(row[config.pathColumn] || "");
      if (!oldPath || oldPath.startsWith("b2://")) continue;
      try {
        const { data: file, error: downloadError } = await admin.storage
          .from(config.bucket)
          .download(oldPath);
        if (downloadError || !file || file.size === 0) {
          throw new Error("Legacy object could not be downloaded.");
        }
        if (file.size > 25 * 1024 * 1024) {
          throw new Error("Object exceeds the 25 MB safe migration limit.");
        }
        const ownerId = String(row[config.ownerColumn] || "");
        if (!ownerId) throw new Error("Media owner is missing.");
        const objectKey = `users/${ownerId}/${category}/${row.id}-${safeFilename(oldPath)}`;
        const bytes = new Uint8Array(await file.arrayBuffer());
        await s3.send(new PutObjectCommand({
          Bucket: bucket,
          Key: objectKey,
          Body: bytes,
          ContentType: file.type || "application/octet-stream",
          Metadata: {
            "source-bucket": config.bucket,
            "source-path": oldPath.slice(0, 500),
            "source-row": String(row.id),
          },
        }));
        const { error: updateError } = await admin
          .from(config.table)
          .update({ [config.pathColumn]: `b2://${objectKey}` })
          .eq(config.idColumn, row[config.idColumn])
          .eq(config.pathColumn, oldPath);
        if (updateError) throw new Error("B2 copy succeeded but the database reference was not changed; retry is safe.");
        migrated++;
      } catch (error) {
        failed++;
        failures.push(`${row.id}: ${error instanceof Error ? error.message : "migration failed"}`);
      }
    }

    const { count: remaining, error: countError } = await admin
      .from(config.table)
      .select("id", { count: "exact", head: true })
      .not(config.pathColumn, "like", "b2://%")
      .not(config.pathColumn, "is", null);
    if (countError) throw new Error("Migration ran, but remaining count could not be verified.");

    return json({
      success: failed === 0,
      category,
      processed: (rows || []).length,
      migrated,
      failed,
      remaining: remaining ?? null,
      failures,
      note: "Legacy objects are intentionally retained. Delete them only after application reads have been verified.",
    }, 200, origin);
  } catch (error) {
    console.error("B2 media migration failed:", error instanceof Error ? error.message : "unknown error");
    return json({ error: error instanceof Error ? error.message : "Migration failed." }, 500, origin);
  }
});
