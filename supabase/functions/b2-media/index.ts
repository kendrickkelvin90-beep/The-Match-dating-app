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
  endpointRegion = hostname.match(/^s3\\.([a-z0-9-]+)\\.backblazeb2\\.com$/)?.[1];
} catch {
  endpointRegion = undefined;
}
const region = Deno.env.get("B2_REGION") || endpointRegion || "us-east-005";
const missing = required.filter((key) => !Deno.env.get(key));
if (!region) missing.push("B2_REGION (or a regional Backblaze S3 endpoint)");
const s3 = missing.length === 0 ? new S3Client({
  region: region!,
  endpoint: Deno.env.get("B2_S3_ENDPOINT")!,
  forcePathStyle: true,
  credentials: { accessKeyId: Deno.env.get("B2_KEY_ID")!, secretAccessKey: Deno.env.get("B2_APPLICATION_KEY")! },
}) : null;

async function moderateImageBytes(bytes: Uint8Array, contentType: string) {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new Error("Image moderation is not configured.");
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + 0x8000, bytes.length)));
  const moderation = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST", headers: { "Authorization": "Bearer " + apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({ model: "omni-moderation-latest", input: [{ type: "image_url", image_url: { url: "data:" + contentType + ";base64," + btoa(binary) } }] })
  });
  if (!moderation.ok) throw new Error("Moderation service unavailable.");
  const data = await moderation.json(), result = data?.results?.[0];
  if (!result) throw new Error("Moderation returned an invalid response.");
  if (result.categories?.["sexual/minors"] === true || Number(result.category_scores?.sexual ?? 0) >= 0.85)
    throw new Error("This image appears to contain explicit content that is not allowed.");
}

const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp", "image/gif", "video/mp4", "video/webm", "video/quicktime"]);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (missing.length) { console.error("b2-media configuration missing environment variables", missing); return json({ error: "Storage function is not configured", missing }, 500); }

  let stage = "start";
  try {
    stage = "read-auth-header";
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);

    stage = "verify-session";
    const authResponse = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
      headers: { "apikey": Deno.env.get("SUPABASE_ANON_KEY")!, "Authorization": authHeader },
    });
    if (!authResponse.ok) return json({ error: "Invalid or expired session" }, 401);
    const user = await authResponse.json();
    if (!user?.id) return json({ error: "Unable to identify authenticated user" }, 401);

    const bucket = Deno.env.get("B2_BUCKET_NAME")!;

    const uploadAction = req.headers.get("x-action");
    if (uploadAction === "upload-file") {
      stage = "receive-direct-upload";
      const contentType = (req.headers.get("Content-Type") || "").split(";")[0].trim().toLowerCase();
      if (!["image/jpeg", "image/png", "image/webp"].includes(contentType)) {
        return json({ error: "Use JPG, PNG or WebP only." }, 400);
      }
      const rawName = req.headers.get("x-file-name") || "upload";
      let decodedName = rawName;
      try { decodedName = decodeURIComponent(rawName); } catch { /* keep the supplied safe fallback */ }
      const requestedName = decodedName.split(/[\\\\/]/).pop()!.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 100) || "upload";
      const bytes = new Uint8Array(await req.arrayBuffer());
      if (bytes.length === 0 || bytes.length > 5 * 1024 * 1024) {
        return json({ error: "Each photo must be greater than 0 bytes and no larger than 5 MB." }, 400);
      }
      stage = "moderate-profile-image";\n      await moderateImageBytes(bytes, contentType);\n      const objectKey = `users/${user.id}/${crypto.randomUUID()}-${requestedName}`;
      stage = "upload-to-backblaze";
      await s3.send(new PutObjectCommand({ Bucket: bucket, Key: objectKey, Body: bytes, ContentType: contentType }));
      return json({ objectKey, uploaded: true });
    }

    stage = "parse-request";
    const body = await req.json();
    if (!s3) return json({ error: "Storage client unavailable" }, 500);

    if (body.action === "create-upload-url") {
      stage = "sign-upload";
      const contentType = String(body.contentType || "");
      if (!allowedTypes.has(contentType)) return json({ error: "Unsupported media type" }, 400);
      const requestedName = String(body.fileName || "upload").split(/[\\/]/).pop()!.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 100);
      const objectKey = `users/${user.id}/${crypto.randomUUID()}-${requestedName}`;
      const command = new PutObjectCommand({ Bucket: bucket, Key: objectKey, ContentType: contentType });
      const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });
      return json({ uploadUrl, objectKey, method: "PUT", expiresIn: 300, requiredHeaders: { "Content-Type": contentType } });
    }

    if (body.action === "delete-upload") {
      stage = "delete-failed-upload";
      const objectKey = String(body.objectKey || "");
      if (!objectKey.startsWith(`users/${user.id}/`) || objectKey.includes("..") || objectKey.includes("\\\\") || objectKey.length > 500) return json({ error: "Invalid upload object key" }, 403);
      await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: objectKey }));
      return json({ deleted: true });
    }

    if (body.action === "create-download-url" || body.action === "delete-object") {
      stage = "authorize-existing-photo";
      const objectKey = String(body.objectKey || "");
      if (!objectKey.startsWith("users/") || objectKey.includes("..") || objectKey.includes("\\\\") || objectKey.length > 500) return json({ error: "Invalid object key" }, 400);
      const storagePath = `b2://${objectKey}`;
      const query = new URLSearchParams({ select: "id,user_id", storage_path: `eq.${storagePath}` });
      if (body.action === "delete-object") query.set("user_id", `eq.${user.id}`);
      const recordResponse = await fetch(`${Deno.env.get("SUPABASE_URL")}/rest/v1/profile_photos?${query.toString()}`, {
        headers: { "apikey": Deno.env.get("SUPABASE_ANON_KEY")!, "Authorization": authHeader, "Accept": "application/json" },
      });
      if (!recordResponse.ok) return json({ error: "Could not authorize this photo request" }, 403);
      const records = await recordResponse.json();
      if (!Array.isArray(records) || records.length !== 1) return json({ error: "Photo not found or access denied" }, 403);
      if (body.action === "delete-object") {
        stage = "delete-photo-object";
        await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: objectKey }));
        return json({ deleted: true });
      }
      stage = "sign-download";
      const command = new GetObjectCommand({ Bucket: bucket, Key: objectKey });
      const downloadUrl = await getSignedUrl(s3, command, { expiresIn: 120 });
      return json({ downloadUrl, expiresIn: 120 });
    }
    return json({ error: "Unsupported action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("b2-media failure", { stage, message });
    return json({ error: "Unable to process media request", stage }, 500);
  }
});