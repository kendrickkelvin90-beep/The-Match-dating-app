import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, PutObjectCommand } from "npm:@aws-sdk/client-s3";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const bucket = Deno.env.get("B2_BUCKET_NAME") ?? "";
const endpoint = Deno.env.get("B2_S3_ENDPOINT") ?? "";
const keyId = Deno.env.get("B2_ADVERTISING_KEY_ID") ?? "";
const appKey = Deno.env.get("B2_ADVERTISING_APPLICATION_KEY") ?? "";
const allowedOrigins = new Set((Deno.env.get("ADVERTISER_ALLOWED_ORIGINS") ??
  "https://match.beyondthebinarymedia.online").split(",").map((v) => v.trim()).filter(Boolean));

function jwtRole(token: string): string {
  try {
    const segment = token.split(".")[1];
    if (!segment) return "";
    const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    return typeof payload.role === "string" ? payload.role : "";
  } catch { return ""; }
}

function json(body: unknown, status: number, origin: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
      "Cache-Control": "no-store",
    },
  });
}

function starts(bytes: Uint8Array, signature: number[]) {
  return signature.every((value, index) => bytes[index] === value);
}

function getS3() {
  if (!bucket || !endpoint || !keyId || !appKey) throw new Error("Advertising B2 credentials are not configured");
  const host = new URL(endpoint).hostname;
  const region = Deno.env.get("B2_REGION") || host.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
  if (!region) throw new Error("B2 region is not configured");
  return new S3Client({ region, endpoint, forcePathStyle: true, credentials: { accessKeyId: keyId, secretAccessKey: appKey } });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
  if (origin && !allowedOrigins.has(origin)) return json({ error: "Origin not allowed" }, 403, origin);
  if (req.method === "OPTIONS") return new Response("ok", {
    headers: { "Access-Control-Allow-Origin": origin, "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);

  try {
    const header = req.headers.get("Authorization") ?? "";
    const token = header.replace(/^Bearer\s+/i, "");
    if (!token || token === header) return json({ error: "Admin session required." }, 401, origin);
    const caller = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: authData, error: authError } = await caller.auth.getUser(token);
    const user = authData.user;
    if (authError || !authData.user?.email_confirmed_at || jwtRole(token) !== "advertiser") return json({ error: "A verified advertiser admin session is required." }, 401, origin);
    const admin = createClient(supabaseUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
    const { data: adminRow } = await admin.from("advertising_admins").select("user_id").eq("user_id", user.id).maybeSingle();
    if (!adminRow) return json({ error: "Advertising administrator access required." }, 403, origin);

    const form = await req.formData();
    const requestId = String(form.get("request_id") ?? "");
    const file = form.get("file");
    if (!requestId || !(file instanceof File)) return json({ error: "Design request and final artwork file are required." }, 400, origin);
    const { data: request, error: requestError } = await admin.from("advertising_design_requests")
      .select("id,advertiser_id,status").eq("id", requestId).maybeSingle();
    if (requestError || !request) return json({ error: "Design request not found." }, 404, origin);
    if (!["in_progress","first_draft_sent","revision"].includes(request.status)) {
      return json({ error: "The design request is not ready for final artwork delivery." }, 409, origin);
    }

    const bytes = new Uint8Array(await file.arrayBuffer());
    const type = file.type.toLowerCase();
    if (bytes.length < 16 || bytes.length > 10 * 1024 * 1024) return json({ error: "Final artwork must be no larger than 10 MB." }, 400, origin);
    let extension = "";
    const valid =
      type === "image/jpeg" && starts(bytes,[0xff,0xd8,0xff]) ? (extension = "jpg", true) :
      type === "image/png" && starts(bytes,[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]) ? (extension = "png", true) :
      type === "image/webp" && starts(bytes,[0x52,0x49,0x46,0x46]) ? (extension = "webp", true) :
      type === "application/pdf" && starts(bytes,[0x25,0x50,0x44,0x46]) ? (extension = "pdf", true) : false;
    if (!valid) return json({ error: "Upload a valid JPG, PNG, WebP or PDF artwork file." }, 400, origin);

    const s3 = getS3();
    const key = `advertising-designs/${request.advertiser_id}/${requestId}/${crypto.randomUUID()}.${extension}`;
    await s3.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: bytes, ContentType: type }));
    return json({ success: true, delivered_storage_key: key }, 201, origin);
  } catch (error) {
    console.error("Advertising design delivery upload failed:", error instanceof Error ? error.message : "unknown error");
    return json({ error: "Final artwork could not be uploaded." }, 500, origin);
  }
});
