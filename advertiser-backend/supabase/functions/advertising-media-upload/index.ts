import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const bucket = Deno.env.get("B2_BUCKET_NAME") ?? "";
const endpoint = Deno.env.get("B2_S3_ENDPOINT") ?? "";
const keyId = Deno.env.get("B2_ADVERTISING_KEY_ID") ?? "";
const appKey = Deno.env.get("B2_ADVERTISING_APPLICATION_KEY") ?? "";
const allowedOrigins = new Set(
  (Deno.env.get("ADVERTISER_ALLOWED_ORIGINS") ?? "https://match.beyondthebinarymedia.online")
    .split(",").map((value) => value.trim()).filter(Boolean),
);
const maxImageBytes = 10 * 1024 * 1024;
const maxVideoBytes = 20 * 1024 * 1024;

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

function bytesStartWith(bytes: Uint8Array, expected: number[]) {
  return expected.every((value, index) => bytes[index] === value);
}

function containsAscii(bytes: Uint8Array, value: string) {
  const needle = new TextEncoder().encode(value);
  outer: for (let i = 0; i <= bytes.length - needle.length; i++) {
    for (let j = 0; j < needle.length; j++) if (bytes[i + j] !== needle[j]) continue outer;
    return true;
  }
  return false;
}

function mp4DurationSeconds(bytes: Uint8Array): number | null {
  // Read the MP4 movie-header duration rather than trusting a browser-supplied
  // duration field. Reject malformed/oversized atoms and unsupported versions.
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  for (let i = 4; i + 24 < bytes.length; i++) {
    if (bytes[i] !== 0x6d || bytes[i+1] !== 0x76 || bytes[i+2] !== 0x68 || bytes[i+3] !== 0x64) continue;
    const atomStart = i - 4;
    const atomSize = view.getUint32(atomStart, false);
    if (atomSize < 24 || atomStart + atomSize > bytes.length) return null;
    const version = bytes[i + 4];
    let timescale = 0;
    let duration = 0;
    if (version === 0 && atomStart + 28 <= bytes.length) {
      timescale = view.getUint32(i + 16, false);
      duration = view.getUint32(i + 20, false);
    } else if (version === 1 && atomStart + 36 <= bytes.length) {
      timescale = view.getUint32(i + 24, false);
      const high = view.getUint32(i + 28, false);
      const low = view.getUint32(i + 32, false);
      duration = high * 4294967296 + low;
    } else {
      return null;
    }
    if (!timescale || !Number.isFinite(duration)) return null;
    return duration / timescale;
  }
  return null;
}

function getS3() {
  if (!bucket || !endpoint || !keyId || !appKey) throw new Error("Advertising B2 credentials are not configured");
  const host = new URL(endpoint).hostname;
  const region = Deno.env.get("B2_REGION") || host.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
  if (!region) throw new Error("Advertising B2 region is not configured");
  return new S3Client({
    region, endpoint, forcePathStyle: true,
    credentials: { accessKeyId: keyId, secretAccessKey: appKey },
  });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
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

  let uploadedKeys: string[] = [];
  let s3: S3Client | null = null;
  try {
    const header = req.headers.get("Authorization") ?? "";
    const token = header.replace(/^Bearer\s+/i, "");
    if (!token || token === header || !supabaseUrl || !anonKey || !serviceKey) {
      return json({ error: "A verified advertiser session is required." }, 401, origin);
    }
    const caller = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: authData, error: authError } = await caller.auth.getUser(token);
    const user = authData.user;
    if (authError || !user?.email_confirmed_at) return json({ error: "Verify your advertiser email before uploading." }, 401, origin);

    const form = await req.formData();
    const campaignId = String(form.get("campaign_id") ?? "");
    const changeRequestId = String(form.get("change_request_id") ?? "");
    const creative = form.get("creative");
    const poster = form.get("poster");
    if (!campaignId || !(creative instanceof File)) return json({ error: "Campaign and creative file are required." }, 400, origin);

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: campaign, error: campaignError } = await admin.from("advertising_campaigns")
      .select("id,advertiser_id,status,approved_at,go_live_at")
      .eq("id", campaignId).eq("advertiser_id", user.id).maybeSingle();
    if (campaignError || !campaign) return json({ error: "Campaign not found." }, 404, origin);
    if (changeRequestId) {
      const { data: request, error: requestError } = await admin.from("advertising_campaign_change_requests")
        .select("id,status,proposed_creative_id").eq("id", changeRequestId)
        .eq("campaign_id", campaignId).eq("advertiser_id", user.id).maybeSingle();
      if (requestError || !request || request.status !== "pending" || request.proposed_creative_id) {
        return json({ error: "The campaign change request is unavailable for a creative upload." }, 409, origin);
      }
    } else if (campaign.approved_at || campaign.go_live_at ||
        !["awaiting_payment","payment_review","awaiting_approval"].includes(campaign.status)) {
      return json({ error: "Creative changes after approval or launch require an admin-reviewed change request." }, 409, origin);
    }

    const creativeBytes = new Uint8Array(await creative.arrayBuffer());
    const creativeType = creative.type.toLowerCase();
    let kind: "image" | "video";
    let duration: number | null = null;
    let extension: string;
    if (["image/jpeg","image/png","image/webp"].includes(creativeType)) {
      kind = "image";
      if (creativeBytes.byteLength < 16 || creativeBytes.byteLength > maxImageBytes) {
        return json({ error: "Images must be JPG, PNG or WebP and no larger than 10 MB." }, 400, origin);
      }
      const validImage =
        (creativeType === "image/jpeg" && bytesStartWith(creativeBytes, [0xff,0xd8,0xff])) ||
        (creativeType === "image/png" && bytesStartWith(creativeBytes, [0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])) ||
        (creativeType === "image/webp" && bytesStartWith(creativeBytes, [0x52,0x49,0x46,0x46]) && containsAscii(creativeBytes.slice(8,16),"WEBP"));
      if (!validImage) return json({ error: "The image file contents do not match the selected format." }, 400, origin);
      extension = creativeType === "image/jpeg" ? "jpg" : creativeType === "image/png" ? "png" : "webp";
    } else if (creativeType === "video/mp4") {
      kind = "video";
      if (creativeBytes.byteLength < 64 || creativeBytes.byteLength > maxVideoBytes || !containsAscii(creativeBytes.slice(0,64),"ftyp")) {
        return json({ error: "Videos must be valid MP4 files no larger than 20 MB." }, 400, origin);
      }
      duration = mp4DurationSeconds(creativeBytes);
      if (duration === null || duration <= 0 || duration > 30) {
        return json({ error: "The MP4 duration could not be verified or exceeds 30 seconds." }, 400, origin);
      }
      if (!containsAscii(creativeBytes,"avc1") && !containsAscii(creativeBytes,"avc3")) {
        return json({ error: "Video must use H.264 encoding." }, 400, origin);
      }
      if (!(poster instanceof File)) return json({ error: "A poster thumbnail is required for video adverts." }, 400, origin);
      extension = "mp4";
    } else {
      return json({ error: "Unsupported creative type. Upload JPG, PNG, WebP or MP4." }, 400, origin);
    }

    let posterBytes: Uint8Array | null = null;
    let posterExtension: string | null = null;
    if (kind === "video") {
      const posterType = (poster as File).type.toLowerCase();
      posterBytes = new Uint8Array(await (poster as File).arrayBuffer());
      if (!["image/jpeg","image/png","image/webp"].includes(posterType) || posterBytes.byteLength < 16 || posterBytes.byteLength > maxImageBytes) {
        return json({ error: "Poster must be a JPG, PNG or WebP image up to 10 MB." }, 400, origin);
      }
      const validPoster =
        (posterType === "image/jpeg" && bytesStartWith(posterBytes,[0xff,0xd8,0xff])) ||
        (posterType === "image/png" && bytesStartWith(posterBytes,[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])) ||
        (posterType === "image/webp" && bytesStartWith(posterBytes,[0x52,0x49,0x46,0x46]) && containsAscii(posterBytes.slice(8,16),"WEBP"));
      if (!validPoster) return json({ error: "Poster contents do not match the selected image format." }, 400, origin);
      posterExtension = posterType === "image/jpeg" ? "jpg" : posterType === "image/png" ? "png" : "webp";
    }

    s3 = getS3();
    const objectId = crypto.randomUUID();
    const base = `advertising/${user.id}/${campaignId}/${objectId}`;
    const storageKey = `${base}.${extension}`;
    const posterKey = posterExtension ? `${base}-poster.${posterExtension}` : null;
    await s3.send(new PutObjectCommand({
      Bucket: bucket, Key: storageKey, Body: creativeBytes, ContentType: creativeType,
    }));
    uploadedKeys.push(storageKey);
    if (posterKey && posterBytes && poster instanceof File) {
      await s3.send(new PutObjectCommand({
        Bucket: bucket, Key: posterKey, Body: posterBytes, ContentType: poster.type.toLowerCase(),
      }));
      uploadedKeys.push(posterKey);
    }

    const { data: creativeId, error: saveError } = changeRequestId
      ? await admin.rpc("attach_advertising_change_creative", {
          p_advertiser_id: user.id, p_change_request_id: changeRequestId,
          p_creative_type: kind, p_storage_key: storageKey, p_poster_storage_key: posterKey,
          p_content_type: creativeType, p_byte_size: creativeBytes.byteLength,
          p_duration_seconds: duration, p_width: null, p_height: null,
        })
      : await admin.rpc("replace_advertising_creative", {
          p_advertiser_id: user.id, p_campaign_id: campaignId,
          p_creative_type: kind, p_storage_key: storageKey, p_poster_storage_key: posterKey,
          p_content_type: creativeType, p_byte_size: creativeBytes.byteLength,
          p_duration_seconds: duration, p_width: null, p_height: null,
        });
    if (saveError || !creativeId) {
      console.error("Creative metadata write failed:", saveError?.message ?? "No creative id returned");
      for (const key of uploadedKeys) await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key })).catch(() => undefined);
      return json({ error: "Creative upload could not be attached to this campaign." }, 500, origin);
    }

    const previewUrl = await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: storageKey }), { expiresIn: 120 });
    const posterPreviewUrl = posterKey
      ? await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: posterKey }), { expiresIn: 120 })
      : null;
    return json({
      success: true,
      creative_id: creativeId,
      creative_type: kind,
      duration_seconds: duration,
      preview_url: previewUrl,
      poster_preview_url: posterPreviewUrl,
      preview_expires_in: 120,
    }, 201, origin);
  } catch (error) {
    if (s3) {
      for (const key of uploadedKeys) await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key })).catch(() => undefined);
    }
    console.error("Advertising creative upload failed:", error instanceof Error ? error.message : "unknown error");
    return json({ error: "The creative could not be uploaded. Please try again." }, 500, origin);
  }
});
