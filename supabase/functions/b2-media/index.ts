import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-action, x-file-name",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
const required = ["B2_KEY_ID", "B2_APPLICATION_KEY", "B2_BUCKET_NAME", "B2_S3_ENDPOINT", "SUPABASE_URL", "SUPABASE_ANON_KEY"];
const endpoint = Deno.env.get("B2_S3_ENDPOINT") || "";
let endpointRegion: string | undefined;
try {
  const hostname = new URL(endpoint).hostname.toLowerCase();
  endpointRegion = hostname.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
} catch { endpointRegion = undefined; }
const region = Deno.env.get("B2_REGION") || endpointRegion || "us-east-005";
const missing = required.filter((key) => !Deno.env.get(key));
const s3 = missing.length === 0 ? new S3Client({
  region,
  endpoint: Deno.env.get("B2_S3_ENDPOINT")!,
  forcePathStyle: true,
  credentials: { accessKeyId: Deno.env.get("B2_KEY_ID")!, secretAccessKey: Deno.env.get("B2_APPLICATION_KEY")! },
}) : null;
const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp", "image/gif", "video/mp4", "video/webm", "video/quicktime"]);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (missing.length) return json({ error: "Storage function is not configured" }, 500);

  let stage = "start";
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
    const authResponse = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
      headers: { apikey: Deno.env.get("SUPABASE_ANON_KEY")!, Authorization: authHeader },
    });
    if (!authResponse.ok) return json({ error: "Invalid or expired session" }, 401);
    const user = await authResponse.json();
    if (!user?.id) return json({ error: "Unable to identify authenticated user" }, 401);

    const bucket = Deno.env.get("B2_BUCKET_NAME")!;
    const uploadAction = req.headers.get("x-action");
    if (uploadAction === "upload-file") {
      const contentType = (req.headers.get("Content-Type") || "").split(";")[0].trim().toLowerCase();
      if (!["image/jpeg", "image/png", "image/webp"].includes(contentType)) return json({ error: "Use JPG, PNG or WebP only." }, 400);
      let decodedName = req.headers.get("x-file-name") || "upload";
      try { decodedName = decodeURIComponent(decodedName); } catch { /* retain safe fallback */ }
      const requestedName = decodedName.split(/[\\/]/).pop()!.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 100) || "upload";
      const bytes = new Uint8Array(await req.arrayBuffer());
      if (bytes.length === 0 || bytes.length > 5 * 1024 * 1024) return json({ error: "Each photo must be greater than 0 bytes and no larger than 5 MB." }, 400);
      const objectKey = `users/${user.id}/${crypto.randomUUID()}-${requestedName}`;
      await s3!.send(new PutObjectCommand({ Bucket: bucket, Key: objectKey, Body: bytes, ContentType: contentType }));
      return json({ objectKey, uploaded: true });
    }

    const body = await req.json();
    if (!s3) return json({ error: "Storage client unavailable" }, 500);

    if (body.action === "delete-account-profile-photos") {
      stage = "delete-account-profile-photos";
      const query = new URLSearchParams({ select: "storage_path", user_id: `eq.${user.id}` });
      const recordResponse = await fetch(`${Deno.env.get("SUPABASE_URL")}/rest/v1/profile_photos?${query}`, {
        headers: { apikey: Deno.env.get("SUPABASE_ANON_KEY")!, Authorization: authHeader, Accept: "application/json" },
      });
      if (!recordResponse.ok) return json({ error: "Could not authorize account photo cleanup" }, 403);
      const records = await recordResponse.json();
      if (!Array.isArray(records)) return json({ error: "Invalid account photo records" }, 500);
      const keys = [...new Set(records.map((row: { storage_path?: string }) => row.storage_path)
        .filter((path: unknown): path is string => typeof path === "string" && path.startsWith(`b2://users/${user.id}/`))
        .map((path: string) => path.slice(5)))];
      for (const key of keys) await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
      return json({ deletedCount: keys.length });
    }

    if (body.action === "create-upload-url") {
      const contentType = String(body.contentType || "");
      if (!allowedTypes.has(contentType)) return json({ error: "Unsupported media type" }, 400);
      const requestedName = String(body.fileName || "upload").split(/[\\/]/).pop()!.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 100);
      const objectKey = `users/${user.id}/${crypto.randomUUID()}-${requestedName}`;
      const command = new PutObjectCommand({ Bucket: bucket, Key: objectKey, ContentType: contentType });
      const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });
      return json({ uploadUrl, objectKey, method: "PUT", expiresIn: 300, requiredHeaders: { "Content-Type": contentType } });
    }

    if (body.action === "delete-upload") {
      const objectKey = String(body.objectKey || "");
      if (!objectKey.startsWith(`users/${user.id}/`) || objectKey.includes("..") || objectKey.includes("\\") || objectKey.length > 500) return json({ error: "Invalid upload object key" }, 403);
      await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: objectKey }));
      return json({ deleted: true });
    }

    if (body.action === "create-download-url" || body.action === "delete-object") {
      const objectKey = String(body.objectKey || "");
      if (!objectKey.startsWith("users/") || objectKey.includes("..") || objectKey.includes("\\") || objectKey.length > 500) return json({ error: "Invalid object key" }, 400);
      const query = new URLSearchParams({ select: "id,user_id", storage_path: `eq.b2://${objectKey}` });
      if (body.action === "delete-object") query.set("user_id", `eq.${user.id}`);
      const recordResponse = await fetch(`${Deno.env.get("SUPABASE_URL")}/rest/v1/profile_photos?${query}`, {
        headers: { apikey: Deno.env.get("SUPABASE_ANON_KEY")!, Authorization: authHeader, Accept: "application/json" },
      });
      if (!recordResponse.ok) return json({ error: "Could not authorize this photo request" }, 403);
      const records = await recordResponse.json();
      if (!Array.isArray(records) || records.length !== 1) return json({ error: "Photo not found or access denied" }, 403);
      if (body.action === "delete-object") {
        await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: objectKey }));
        return json({ deleted: true });
      }
      const command = new GetObjectCommand({ Bucket: bucket, Key: objectKey });
      const downloadUrl = await getSignedUrl(s3, command, { expiresIn: 120 });
      return json({ downloadUrl, expiresIn: 120 });
    }
    return json({ error: "Unsupported action" }, 400);
  } catch (error) {
    console.error("b2-media failure", { stage, message: error instanceof Error ? error.message : String(error) });
    return json({ error: "Unable to process media request", stage }, 500);
  }
});
