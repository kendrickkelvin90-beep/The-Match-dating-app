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
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-match-cron-timestamp, x-match-cron-signature",
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
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-match-cron-timestamp, x-match-cron-signature",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const cronTimestampHeader = req.headers.get("x-match-cron-timestamp") || "";
    const cronSignature = req.headers.get("x-match-cron-signature") || "";
    const body = await req.json().catch(() => null);
    const category = body?.category as Category;
    if (!category || !(category in categories)) {
      return json({ error: "Choose a supported media category." }, 400, origin);
    }
    const requestedLimit = Number.isInteger(body?.limit) ? body.limit : 2;
    const limit = Math.max(1, Math.min(2, requestedLimit));
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    let isCron = false;

    if (cronTimestampHeader || cronSignature) {
      const timestamp = Number(cronTimestampHeader);
      if (!cronTimestampHeader || !cronSignature || !Number.isSafeInteger(timestamp)) {
        return json({ error: "Invalid migration scheduler signature" }, 401, origin);
      }
      const { data: validSignature, error: signatureError } = await admin.rpc(
        "verify_b2_story_migration_cron_signature",
        {
          p_timestamp: timestamp,
          p_category: category,
          p_limit: requestedLimit,
          p_signature: cronSignature,
        },
      );
      if (signatureError || validSignature !== true) {
        return json({ error: "Invalid or expired migration scheduler signature" }, 401, origin);
      }
      isCron = true;
    } else {
      if (!token || token === authHeader) return json({ error: "Authentication required" }, 401, origin);
      const caller = createClient(url, anon, {
        auth: { autoRefreshToken: false, persistSession: false },
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const { data: userData, error: authError } = await caller.auth.getUser(token);
      if (authError || !userData.user) return json({ error: "Invalid session" }, 401, origin);
      const { data: isAdmin, error: adminError } = await caller.rpc("is_match_admin");
      if (adminError || isAdmin !== true) return json({ error: "Admin access required" }, 403, origin);
    }

    if (isCron && category !== "stories") {
      return json({ error: "The automatic scheduler is restricted to Story media." }, 403, origin);
    }
    const config = categories[category];
    const s3 = getStorageClient();
    const bucket = Deno.env.get("B2_BUCKET_NAME")!;

    const { data: priorFailures, error: priorFailuresError } = await admin
      .from("b2_media_migration_failures")
      .select("record_id,attempts,failed_permanently,next_retry_at")
      .eq("category", category);
    if (priorFailuresError) throw new Error("Could not inspect previous migration failures.");
    const nowMs = Date.now();
    const blockedIds = (priorFailures || [])
      .filter((item) => item.failed_permanently ||
        (item.next_retry_at && new Date(item.next_retry_at).getTime() > nowMs))
      .map((item) => String(item.record_id));

    let rowsQuery = admin
      .from(config.table)
      .select("*")
      .not(config.pathColumn, "like", "b2://%")
      .not(config.pathColumn, "is", null);
    if (blockedIds.length) rowsQuery = rowsQuery.not(config.idColumn, "in", `(${blockedIds.join(",")})`);
    // View Once still relies on its existing atomic Supabase access workflow.
    // Keep those files in the private bucket until that workflow is migrated.
    if (category === "chat_media") rowsQuery = rowsQuery.eq("view_once", false);
    if (category === "stories") rowsQuery = rowsQuery.gt("expires_at", new Date().toISOString());
    const { data: rows, error: listError } = await rowsQuery
      .order("created_at", { ascending: true })
      .limit(limit);
    if (listError) {\n      console.error("Could not list legacy media records:", JSON.stringify({ message: listError.message, code: listError.code, details: listError.details, hint: listError.hint }));\n      throw new Error("Could not list legacy media records: " + listError.message);\n    }

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
        const recordId = String(row[config.idColumn] || "");
        if (!ownerId || !recordId) throw new Error("Media owner or record identifier is missing.");
        const objectKey = `users/${ownerId}/${category}/${recordId}-${safeFilename(oldPath)}`;
        const bytes = new Uint8Array(await file.arrayBuffer());
        await s3.send(new PutObjectCommand({
          Bucket: bucket,
          Key: objectKey,
          Body: bytes,
          ContentType: file.type || "application/octet-stream",
          Metadata: {
            "source-bucket": config.bucket,
            "source-path": oldPath.slice(0, 500),
            "source-row": recordId,
          },
        }));
        const { error: updateError } = await admin
          .from(config.table)
          .update({ [config.pathColumn]: `b2://${objectKey}` })
          .eq(config.idColumn, recordId)
          .eq(config.pathColumn, oldPath);
        if (updateError) throw new Error("B2 copy succeeded but the database reference was not changed; retry is safe.");
        migrated++;
      } catch (error) {
        failed++;
        const recordId = String(row[config.idColumn] || "");
        const reason = error instanceof Error ? error.message : "migration failed";
        failures.push(`${recordId}: ${reason}`);
        if (recordId) {
          const { data: previous } = await admin.from("b2_media_migration_failures")
            .select("attempts")
            .eq("category", category)
            .eq("record_id", recordId)
            .maybeSingle();
          const attempts = Number(previous?.attempts || 0) + 1;
          const failedPermanently = attempts >= 5;
          const retryDelayMs = Math.min(6 * 60 * 60 * 1000, 5 * 60 * 1000 * (2 ** (attempts - 1)));
          await admin.from("b2_media_migration_failures").upsert({
            category,
            record_id: recordId,
            attempts,
            last_error: reason.slice(0, 500),
            next_retry_at: failedPermanently ? null : new Date(Date.now() + retryDelayMs).toISOString(),
            failed_permanently: failedPermanently,
            updated_at: new Date().toISOString(),
          }, { onConflict: "category,record_id" });
        }
      }
    }

    let countQuery = admin
      .from(config.table)
      .select(category === "event_posters" ? "event_id" : "id", { count: "exact", head: true })
      .not(config.pathColumn, "like", "b2://%")
      .not(config.pathColumn, "is", null);
    if (category === "chat_media") countQuery = countQuery.eq("view_once", false);
    if (category === "stories") countQuery = countQuery.gt("expires_at", new Date().toISOString());
    const { count: remaining, error: countError } = await countQuery;
    if (countError) throw new Error("Migration ran, but remaining count could not be verified.");
    let excludedViewOnce = 0;
    if (category === "chat_media") {
      const { count, error } = await admin.from("chat_media")
        .select("id", { count: "exact", head: true })
        .eq("view_once", true)
        .not("storage_path", "like", "b2://%");
      if (error) throw new Error("Could not count View Once media excluded from migration.");
      excludedViewOnce = count ?? 0;
    }
    const { count: permanentlyFailed, error: permanentCountError } = await admin
      .from("b2_media_migration_failures")
      .select("record_id", { count: "exact", head: true })
      .eq("category", category)
      .eq("failed_permanently", true);
    if (permanentCountError) throw new Error("Could not verify permanently failed media records.");

    if (isCron && category === "stories") {
      const { error: completionError } = await admin.rpc("complete_b2_story_migration");
      if (completionError) console.error("Story migration batch finished but scheduler state could not be updated.");
    }

    return json({
      success: failed === 0,
      category,
      processed: (rows || []).length,
      migrated,
      failed,
      remaining: remaining ?? null,
      permanentlyFailed: permanentlyFailed ?? 0,
      excludedViewOnce,
      failures,
      note: "Legacy objects are intentionally retained. Delete them only after application reads have been verified.",
    }, 200, origin);
  } catch (error) {
    console.error("B2 media migration failed:", error instanceof Error ? error.message : "unknown error");
    return json({ error: error instanceof Error ? error.message : "Migration failed." }, 500, origin);
  }
});
