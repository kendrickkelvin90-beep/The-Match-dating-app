import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, GetObjectCommand } from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const appOrigin = "https://match.beyondthebinarymedia.online";
const projectUrl = Deno.env.get("SUPABASE_URL") ?? "";
const advertiserServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";


const bucket = Deno.env.get("B2_BUCKET_NAME") ?? "";
const endpoint = Deno.env.get("B2_S3_ENDPOINT") ?? "";
const keyId = Deno.env.get("B2_ADVERTISING_KEY_ID") ?? "";
const appKey = Deno.env.get("B2_ADVERTISING_APPLICATION_KEY") ?? "";
const hmacSecret = Deno.env.get("ADVERTISING_ANALYTICS_HMAC_SECRET") ?? "";

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": appOrigin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
      "Cache-Control": "no-store",
    },
  });
}

function jwtRole(token: string): string {
  try {
    const segment = token.split(".")[1];
    if (!segment) return "";
    const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    return typeof payload.role === "string" ? payload.role : "";
  } catch { return ""; }
}

async function verifyMember(req: Request) {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  if (!token || token === header || !projectUrl || !anonKey || jwtRole(token) !== "authenticated") return null;
  const client = createClient(projectUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) return null;
  return { user: data.user, caller: client };
}

async function pseudonymousViewerKey(userId: string) {
  if (!hmacSecret) throw new Error("Analytics signing is not configured");
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(hmacSecret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  // Stable keyed pseudonym is required for a true rolling 24-hour cap across midnight.
  // Raw member IDs are never written to advertising analytics.
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(userId));
  return Array.from(new Uint8Array(signature), (value) => value.toString(16).padStart(2, "0")).join("");
}

function getB2Client() {
  if (!bucket || !endpoint || !keyId || !appKey) throw new Error("Advertising media delivery is not configured");
  const host = new URL(endpoint).hostname;
  const region = Deno.env.get("B2_REGION") || host.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
  if (!region) throw new Error("B2 region is not configured");
  return new S3Client({
    region, endpoint, forcePathStyle: true,
    credentials: { accessKeyId: keyId, secretAccessKey: appKey },
  });
}

async function signObject(s3: S3Client, objectKey: string) {
  if (!objectKey.startsWith("advertising/") || objectKey.includes("..") || objectKey.includes("\\")) {
    throw new Error("Invalid advertising media key");
  }
  return await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: objectKey }), { expiresIn: 120 });
}

async function stableScore(input: string) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(bytes), (value) => value.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
  if (origin && origin !== appOrigin) return json({ error: "Origin not allowed" }, 403);
  if (req.method === "OPTIONS") return new Response("ok", {
    headers: {
      "Access-Control-Allow-Origin": appOrigin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const memberAuth = await verifyMember(req);
    if (!memberAuth) return json({ error: "A valid Match member session is required." }, 401);
    const { user, caller } = memberAuth;
    if (!projectUrl || !advertiserServiceKey) return json({ error: "Advertising service is not configured." }, 503);
    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) return json({ error: "Invalid request." }, 400);
    const service = createClient(projectUrl, advertiserServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const viewerKey = await pseudonymousViewerKey(user.id);
    const action = typeof body.action === "string" ? body.action : "";

    if (action === "record-event") {
      const campaignId = typeof body.campaign_id === "string" ? body.campaign_id : "";
      const eventType = typeof body.event_type === "string" ? body.event_type : "";
      if (!campaignId || !["impression","click"].includes(eventType)) {
        return json({ error: "Invalid advertising event." }, 400);
      }
      const { data, error } = await service.rpc("record_advertising_event", {
        p_campaign_id: campaignId,
        p_viewer_day_key: viewerKey,
        p_event_type: eventType,
      });
      if (error) return json({ error: "Advertising event could not be recorded." }, 500);
      return json({ recorded: data === true }, 200);
    }

    if (action !== "get-ad") return json({ error: "Unsupported action." }, 400);

    // Match Plus is explicitly ad-free. Check the authoritative membership row
    // with the member JWT; fail closed if the entitlement cannot be verified.
    const [legacyMembership, matchPlusMembership] = await Promise.all([
      caller.from("premium_memberships")
        .select("premium_until").eq("user_id", user.id).gt("premium_until", new Date().toISOString()).maybeSingle(),
      caller.rpc("match_plus_active_tier"),
    ]);
    if (legacyMembership.error || matchPlusMembership.error) {
      return json({ ad: null, reason: "membership_check_unavailable" }, 200);
    }
    if (legacyMembership.data || matchPlusMembership.data) {
      return json({ ad: null, reason: "ad_free_membership" }, 200);
    }

    if (!bucket || !endpoint || !keyId || !appKey) return json({ ad: null, reason: "media_unavailable" }, 200);

    const now = new Date().toISOString();
    const { data: rows, error } = await service.from("advertising_campaigns")
      .select("id,advertiser_id,headline,description,cta,destination_url,ends_at,advertising_creatives!inner(creative_type,storage_key,poster_storage_key,duration_seconds,content_type,is_current)")
      .eq("status", "active")
      .eq("payment_status", "confirmed")
      .not("approved_at", "is", null)
      .lte("go_live_at", now)
      .gt("ends_at", now)
      .eq("advertising_creatives.is_current", true)
      .limit(250);
    if (error) {
      console.error("Eligible advertising campaign query failed:", error.message);
      return json({ ad: null, reason: "inventory_unavailable" }, 200);
    }
    if (!rows?.length) return json({ ad: null, reason: "no_eligible_campaigns" }, 200);

    const impressionLookback = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { data: seenRows, error: seenError } = await service.from("advertising_impressions")
      .select("campaign_id,recorded_at")
      .eq("viewer_day_key", viewerKey)
      .gte("recorded_at", impressionLookback)
      .order("recorded_at", { ascending: false })
      .limit(100);
    if (seenError) return json({ ad: null, reason: "rotation_unavailable" }, 200);
    const seen = new Set((seenRows ?? []).map((row) => row.campaign_id));
    const excludedIds = Array.isArray(body.exclude_campaign_ids) ? body.exclude_campaign_ids.filter((value) => typeof value === "string").slice(0, 50) : [];
    const slotIndex = Number.isInteger(body.slot_index) ? Number(body.slot_index) : 0;
    let eligible = rows.filter((row) => !seen.has(row.id) && !excludedIds.includes(row.id));
    if (!eligible.length) return json({ ad: null, reason: "daily_frequency_limit" }, 200);

    const recentCampaignIds = (seenRows ?? []).slice(0, 3).map((row) => row.campaign_id);
    if (recentCampaignIds.length) {
      const { data: recentCampaigns } = await service.from("advertising_campaigns")
        .select("id,advertiser_id").in("id", recentCampaignIds);
      const recentAdvertisers = new Set((recentCampaigns ?? []).map((row) => row.advertiser_id));
      const spaced = eligible.filter((row) => !recentAdvertisers.has(row.advertiser_id));
      if (spaced.length) eligible = spaced;
    }

    const scored = await Promise.all(eligible.map(async (row) => ({
      row,
      score: await stableScore(viewerKey + ":" + slotIndex + ":" + row.id),
    })));
    scored.sort((a, b) => a.score.localeCompare(b.score));
    const selected = scored[0].row;
    const creative = Array.isArray(selected.advertising_creatives)
      ? selected.advertising_creatives[0] : selected.advertising_creatives;
    if (!creative?.storage_key) return json({ ad: null, reason: "creative_unavailable" }, 200);

    const s3 = getB2Client();
    const creativeUrl = await signObject(s3, creative.storage_key);
    const posterUrl = creative.poster_storage_key ? await signObject(s3, creative.poster_storage_key) : null;
    return json({
      ad: {
        campaign_id: selected.id,
        label: "Sponsored",
        headline: selected.headline,
        description: selected.description,
        cta: selected.cta,
        destination_url: selected.destination_url,
        creative_type: creative.creative_type,
        creative_url: creativeUrl,
        poster_url: posterUrl,
        duration_seconds: creative.duration_seconds,
        ends_at: selected.ends_at,
      },
    }, 200);
  } catch (error) {
    console.error("Member ad-serving failure:", error instanceof Error ? error.message : "unknown error");
    return json({ ad: null, reason: "temporarily_unavailable" }, 200);
  }
});
