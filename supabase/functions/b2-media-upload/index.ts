import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, PutObjectCommand, DeleteObjectCommand } from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const allowedOrigins = new Set(["https://match.beyondthebinarymedia.online"]);
const categories = new Set(["stories", "chat_media", "verification_selfies", "event_posters"]);
const maxBytes = 25 * 1024 * 1024;
const allowedTypes = new Set([
  "image/jpeg", "image/png", "image/webp", "image/gif",
  "video/mp4", "video/webm", "video/quicktime",
]);

function response(body: unknown, status: number, origin: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-action, x-category, x-file-name",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") || "";
  if (origin && !allowedOrigins.has(origin)) return response({ error: "Origin not allowed" }, 403, origin);
  if (req.method === "OPTIONS") return new Response("ok", {
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-action, x-category, x-file-name",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405, origin);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\\s+/i, "");
    const url = Deno.env.get("SUPABASE_URL") || "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") || "";
    const bucket = Deno.env.get("B2_BUCKET_NAME") || "";
    const endpoint = Deno.env.get("B2_S3_ENDPOINT") || "";
    const keyId = Deno.env.get("B2_KEY_ID") || "";
    const appKey = Deno.env.get("B2_APPLICATION_KEY") || "";
    if (!token || token === authHeader) return response({ error: "Authentication required" }, 401, origin);
    if (!url || !anon || !bucket || !endpoint || !keyId || !appKey) return response({ error: "B2 upload is not configured" }, 500, origin);

    const caller = createClient(url, anon, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: authError } = await caller.auth.getUser(token);
    if (authError || !userData.user) return response({ error: "Invalid session" }, 401, origin);

    const category = req.headers.get("x-category") || "";
    if (!categories.has(category)) return response({ error: "Unsupported media category" }, 400, origin);

    const endpointHost = new URL(endpoint).hostname;
    const region = Deno.env.get("B2_REGION") || endpointHost.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
    if (!region) return response({ error: "B2 region is not configured" }, 500, origin);
    const s3 = new S3Client({
      region,
      endpoint,
      forcePathStyle: true,
      credentials: { accessKeyId: keyId, secretAccessKey: appKey },
    });

    const action = req.headers.get("x-action") || "create-upload-url";
    if (action === "delete-upload") {
      const body = await req.json().catch(() => null);
      const objectKey = typeof body?.objectKey === "string" ? body.objectKey : "";
      if (!objectKey.startsWith(`users/${userData.user.id}/${category}/`) ||
          objectKey.includes("..") || objectKey.includes("\\\\") || objectKey.length > 500) {
        return response({ error: "Invalid upload object key" }, 403, origin);
      }
      await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: objectKey }));
      return response({ deleted: true }, 200, origin);
    }
    if (action !== "create-upload-url") return response({ error: "Unsupported action" }, 400, origin);

    const body = await req.json().catch(() => null);
    const contentType = typeof body?.contentType === "string" ? body.contentType.toLowerCase() : "";
    if (!allowedTypes.has(contentType)) return response({ error: "Unsupported media type" }, 400, origin);
    const size = Number(body?.size);
    if (!Number.isFinite(size) || size < 1 || size > maxBytes) {
      return response({ error: "Media must be between 1 byte and 25 MB." }, 400, origin);
    }
    const rawName = typeof body?.fileName === "string" ? body.fileName : "media";
    const filename = rawName.split(/[\\\\/]/).pop()!.replace(/[^a-zA-Z0-9._-]/g, "_").slice(-100) || "media";
    const objectKey = `users/${userData.user.id}/${category}/${crypto.randomUUID()}-${filename}`;
    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: objectKey,
      ContentType: contentType,
      ContentLength: size,
    });
    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });
    return response({
      uploadUrl,
      objectKey,
      method: "PUT",
      expiresIn: 300,
      requiredHeaders: { "Content-Type": contentType },
    }, 200, origin);
  } catch (error) {
    console.error("B2 media upload failed:", error instanceof Error ? error.message : "unknown error");
    return response({ error: "Unable to upload media to B2" }, 500, origin);
  }
});
