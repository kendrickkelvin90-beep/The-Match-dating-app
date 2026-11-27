import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type User } from "npm:@supabase/supabase-js@2";
import { S3Client, GetObjectCommand } from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const allowedOrigins = new Set(
  (Deno.env.get("ADVERTISER_ALLOWED_ORIGINS") ?? "https://match.beyondthebinarymedia.online")
    .split(",").map((value) => value.trim()).filter(Boolean),
);

type Action =
  | "create-campaign"
  | "submit-payment"
  | "list-campaigns"
  | "get-metrics"
  | "get-payment-details"
  | "request-refund"
  | "admin-preview-creative"
  | "admin-list-campaigns"
  | "admin-list-payments"
  | "admin-list-refunds"
  | "admin-record-duplicate-payment"
  | "admin-review-refund"
  | "admin-mark-refund-paid"
  | "admin-confirm-payment"
  | "admin-review-campaign"
  | "admin-set-campaign-state"
  | "admin-overview";

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

function cleanText(value: unknown, max: number) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function validDestination(value: unknown, cta: string) {
  const raw = cleanText(value, 2048);
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.username || url.password) return null;
    if (cta === "whatsapp" && !["wa.me", "api.whatsapp.com", "www.whatsapp.com"].includes(url.hostname.toLowerCase())) return null;
    return url.toString();
  } catch {
    return null;
  }
}

function paymentReference() {
  const bytes = crypto.getRandomValues(new Uint8Array(10));
  const token = Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("").toUpperCase();
  return "TMAD-" + token;
}

async function authenticate(req: Request): Promise<{ user: User; caller: any; admin: any } | null> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  if (!token || token === header || !supabaseUrl || !anonKey || !serviceKey) return null;

  const caller: any = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data, error } = await caller.auth.getUser(token);
  if (error || !data.user || !data.user.email_confirmed_at) return null;

  const admin: any = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  return { user: data.user, caller, admin };
}

async function requireAdmin(admin: any, userId: string) {
  const { data, error } = await admin.from("advertising_admins")
    .select("user_id").eq("user_id", userId).maybeSingle();
  return !error && !!data;
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

  try {
    const auth = await authenticate(req);
    if (!auth) return json({ error: "A verified advertiser session is required." }, 401, origin);
    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) return json({ error: "Invalid request body." }, 400, origin);
    const action = cleanText(body.action, 48) as Action;
    const { user, caller, admin } = auth;

    if (action === "create-campaign") {
      const profile = await admin.from("advertiser_profiles")
        .select("user_id").eq("user_id", user.id).maybeSingle();
      if (profile.error || !profile.data) return json({ error: "Complete your advertiser profile before creating a campaign." }, 400, origin);

      const headline = cleanText(body.headline, 90);
      const description = cleanText(body.description, 500);
      const cta = cleanText(body.cta, 24);
      const destination = validDestination(body.destination_url, cta);
      const packageDays = Number(body.package_days);
      const startMode = cleanText(body.start_mode, 16);
      const scheduledRaw = body.scheduled_start_at;
      const scheduledAt = scheduledRaw ? new Date(String(scheduledRaw)) : null;
      if (headline.length < 3 || !description || !destination ||
          !["learn_more","visit_website","contact_us","whatsapp"].includes(cta) ||
          ![7,14,30].includes(packageDays) ||
          !["immediate","scheduled"].includes(startMode) ||
          (startMode === "immediate" && scheduledRaw) ||
          (startMode === "scheduled" && (!scheduledAt || Number.isNaN(scheduledAt.getTime()) || scheduledAt.getTime() <= Date.now()))) {
        return json({ error: "Please check the campaign details, package and start date." }, 400, origin);
      }

      const bankName = Deno.env.get("ADVERTISING_BANK_NAME") ?? "";
      const accountName = Deno.env.get("ADVERTISING_ACCOUNT_NAME") ?? "";
      const accountNumber = Deno.env.get("ADVERTISING_ACCOUNT_NUMBER") ?? "";
      if (!bankName || !accountName || !/^\d{10}$/.test(accountNumber)) {
        return json({ error: "Advertising bank-transfer instructions have not been configured yet." }, 503, origin);
      }

      const reference = paymentReference();
      const deadline = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
      const { data, error } = await admin.rpc("create_advertising_campaign", {
        p_advertiser_id: user.id,
        p_headline: headline,
        p_description: description,
        p_cta: cta,
        p_destination_url: destination,
        p_package_days: packageDays,
        p_start_mode: startMode,
        p_scheduled_start_at: scheduledAt?.toISOString() ?? null,
        p_payment_reference: reference,
        p_payment_deadline_at: deadline,
      });
      if (error || !Array.isArray(data) || !data[0]) {
        console.error("Campaign creation failed:", error?.message ?? "No campaign returned");
        return json({ error: "The campaign could not be created. Please try again." }, 500, origin);
      }
      return json({
        campaign: data[0],
        bank_transfer: { bank_name: bankName, account_name: accountName, account_number: accountNumber },
        payment_deadline_at: deadline,
      }, 201, origin);
    }

    if (action === "submit-payment") {
      const campaignId = cleanText(body.campaign_id, 64);
      const transferReference = cleanText(body.bank_transfer_reference, 120);
      const amount = Number(body.amount_ngn);
      const receiptKey = body.receipt_storage_key == null ? null : cleanText(body.receipt_storage_key, 500);
      if (!campaignId || transferReference.length < 4 || !Number.isInteger(amount)) {
        return json({ error: "Enter the campaign, exact package amount and bank transfer reference." }, 400, origin);
      }
      const { data, error } = await admin.rpc("submit_advertising_payment", {
        p_advertiser_id: user.id,
        p_campaign_id: campaignId,
        p_amount_ngn: amount,
        p_bank_transfer_reference: transferReference,
        p_receipt_storage_key: receiptKey,
      });
      if (error) {
        const duplicate = /duplicate key|unique constraint/i.test(error.message);
        return json({ error: duplicate ? "This bank transfer reference has already been submitted." : "Payment details could not be submitted. Check the campaign deadline and amount." }, duplicate ? 409 : 400, origin);
      }
      return json({ success: true, payment_id: data, status: "submitted", note: "Your transfer is awaiting manual confirmation. Uploading a receipt does not itself confirm payment." }, 200, origin);
    }

    if (action === "list-campaigns") {
      const { data, error } = await caller.from("advertising_campaigns")
        .select("id,headline,description,package_days,package_price_ngn,start_mode,scheduled_start_at,payment_reference,payment_deadline_at,payment_status,status,go_live_at,ends_at,created_at,advertising_payments(id,status,amount_ngn)")
        .eq("advertiser_id", user.id).order("created_at", { ascending: false }).limit(100);
      if (error) return json({ error: "Campaigns could not be loaded." }, 500, origin);
      return json({ campaigns: data ?? [] }, 200, origin);
    }


    if (action === "get-payment-details") {
      const campaignId = cleanText(body.campaign_id, 64);
      if (!campaignId) return json({ error: "Campaign ID is required." }, 400, origin);
      const { data: campaign, error } = await admin.from("advertising_campaigns")
        .select("id,advertiser_id,package_price_ngn,payment_reference,payment_deadline_at,payment_status,status")
        .eq("id", campaignId).eq("advertiser_id", user.id).maybeSingle();
      if (error || !campaign) return json({ error: "Campaign not found." }, 404, origin);
      if (campaign.payment_status !== "awaiting_payment" || campaign.status !== "awaiting_payment" ||
          new Date(campaign.payment_deadline_at).getTime() <= Date.now()) {
        return json({ error: "This campaign is no longer awaiting payment. Refresh your campaign status." }, 409, origin);
      }
      const bankName = Deno.env.get("ADVERTISING_BANK_NAME") ?? "";
      const accountName = Deno.env.get("ADVERTISING_ACCOUNT_NAME") ?? "";
      const accountNumber = Deno.env.get("ADVERTISING_ACCOUNT_NUMBER") ?? "";
      if (!bankName || !accountName || !/^\\d{10}$/.test(accountNumber)) {
        return json({ error: "Advertising bank-transfer instructions have not been configured yet." }, 503, origin);
      }
      return json({
        campaign: { campaign_id: campaign.id, payment_reference: campaign.payment_reference, amount_ngn: campaign.package_price_ngn },
        bank_transfer: { bank_name: bankName, account_name: accountName, account_number: accountNumber },
        payment_deadline_at: campaign.payment_deadline_at,
      }, 200, origin);
    }


    if (action === "request-refund") {
      const paymentId = cleanText(body.payment_id, 64);
      const reason = cleanText(body.reason, 500);
      if (!paymentId || reason.length < 3) return json({ error: "Select a payment and enter a refund reason." }, 400, origin);
      const { data, error } = await admin.rpc("request_advertising_refund", {
        p_advertiser_id: user.id, p_payment_id: paymentId, p_reason: reason,
      });
      if (error) return json({ error: "This payment is not currently eligible for a refund request." }, 400, origin);
      return json({ success: true, refund_id: data, status: "requested" }, 201, origin);
    }

    if (action === "get-metrics") {
      const campaignId = cleanText(body.campaign_id, 64);
      if (!campaignId) return json({ error: "Campaign ID is required." }, 400, origin);
      const { data, error } = await caller.rpc("get_my_advertising_campaign_metrics", { p_campaign_id: campaignId });
      if (error) return json({ error: "Campaign metrics are unavailable." }, 403, origin);
      return json({ metrics: data?.[0] ?? null }, 200, origin);
    }

    const isAdmin = await requireAdmin(admin, user.id);
    if (!isAdmin) return json({ error: "Advertising administrator access is required." }, 403, origin);


    if (action === "admin-preview-creative") {
      const campaignId = cleanText(body.campaign_id, 64);
      if (!campaignId) return json({ error: "Campaign ID is required." }, 400, origin);
      const { data: campaign, error } = await admin.from("advertising_campaigns")
        .select("id,advertising_creatives(creative_type,storage_key,poster_storage_key,is_current)")
        .eq("id", campaignId).maybeSingle();
      if (error || !campaign) return json({ error: "Campaign creative not found." }, 404, origin);
      const creative = Array.isArray(campaign.advertising_creatives)
        ? campaign.advertising_creatives.find((item) => item.is_current) ?? campaign.advertising_creatives[0]
        : campaign.advertising_creatives;
      if (!creative?.storage_key) return json({ error: "No creative is attached to this campaign." }, 404, origin);
      const bucket = Deno.env.get("B2_BUCKET_NAME") ?? "";
      const endpoint = Deno.env.get("B2_S3_ENDPOINT") ?? "";
      const keyId = Deno.env.get("B2_ADVERTISING_KEY_ID") ?? "";
      const appKey = Deno.env.get("B2_ADVERTISING_APPLICATION_KEY") ?? "";
      if (!bucket || !endpoint || !keyId || !appKey) return json({ error: "Advertising media is not configured." }, 503, origin);
      const host = new URL(endpoint).hostname;
      const region = Deno.env.get("B2_REGION") || host.match(/^s3\\.([a-z0-9-]+)\\.backblazeb2\\.com$/)?.[1];
      if (!region) return json({ error: "B2 region is not configured." }, 503, origin);
      const s3 = new S3Client({ region, endpoint, forcePathStyle: true, credentials: { accessKeyId: keyId, secretAccessKey: appKey } });
      const previewUrl = await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: creative.storage_key }), { expiresIn: 120 });
      const posterUrl = creative.poster_storage_key
        ? await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: creative.poster_storage_key }), { expiresIn: 120 })
        : null;
      return json({ creative_type: creative.creative_type, preview_url: previewUrl, poster_url: posterUrl, expires_in: 120 }, 200, origin);
    }

    if (action === "admin-list-campaigns") {
      const { data, error } = await admin.from("advertising_campaigns")
        .select("*,advertiser_profiles(display_name,advertiser_type,phone),advertising_creatives(creative_type,storage_key,poster_storage_key,content_type,byte_size,duration_seconds)")
        .order("created_at", { ascending: false }).limit(250);
      if (error) return json({ error: "Campaign queue could not be loaded." }, 500, origin);
      return json({ campaigns: data ?? [] }, 200, origin);
    }

    if (action === "admin-list-payments") {
      const { data, error } = await admin.from("advertising_payments")
        .select("*,advertising_campaigns(headline,payment_reference,package_days),advertiser_profiles(display_name,phone)")
        .order("submitted_at", { ascending: false }).limit(250);
      if (error) return json({ error: "Payment queue could not be loaded." }, 500, origin);
      return json({ payments: data ?? [] }, 200, origin);
    }


    if (action === "admin-list-refunds") {
      const { data, error } = await admin.from("advertising_refunds")
        .select("*,advertising_campaigns(headline),advertising_profiles:advertiser_profiles(display_name,phone)")
        .order("requested_at", { ascending: false }).limit(250);
      if (error) return json({ error: "Refund queue could not be loaded." }, 500, origin);
      return json({ refunds: data ?? [] }, 200, origin);
    }

    if (action === "admin-record-duplicate-payment") {
      const campaignId = cleanText(body.campaign_id, 64);
      const advertiserId = cleanText(body.advertiser_id, 64);
      const amount = Number(body.amount_ngn);
      const transferReference = cleanText(body.bank_transfer_reference, 120);
      const note = cleanText(body.admin_note, 500);
      if (!campaignId || !advertiserId || !Number.isInteger(amount) || amount <= 0 || transferReference.length < 4) {
        return json({ error: "Campaign, advertiser, amount and verified transfer reference are required." }, 400, origin);
      }
      const { data, error } = await admin.rpc("admin_record_duplicate_advertising_payment", {
        p_admin_id: user.id, p_campaign_id: campaignId, p_advertiser_id: advertiserId,
        p_amount_ngn: amount, p_bank_transfer_reference: transferReference, p_admin_note: note,
      });
      if (error) return json({ error: "The duplicate transfer could not be recorded." }, 400, origin);
      return json({ success: true, payment_id: data, status: "duplicate" }, 201, origin);
    }

    if (action === "admin-review-refund") {
      const refundId = cleanText(body.refund_id, 64);
      const approve = body.approve === true;
      const reason = cleanText(body.reason, 500);
      if (!refundId || (!approve && reason.length < 3)) return json({ error: "Refund and rejection reason are required." }, 400, origin);
      const { data, error } = await admin.rpc("admin_review_advertising_refund", {
        p_admin_id: user.id, p_refund_id: refundId, p_approve: approve, p_reason: reason,
      });
      if (error) return json({ error: "Refund review could not be saved." }, 400, origin);
      return json({ success: true, status: data }, 200, origin);
    }

    if (action === "admin-mark-refund-paid") {
      const refundId = cleanText(body.refund_id, 64);
      const transferReference = cleanText(body.bank_transfer_reference, 120);
      if (!refundId || transferReference.length < 4) return json({ error: "Refund ID and outgoing bank transfer reference are required." }, 400, origin);
      const { data, error } = await admin.rpc("admin_mark_advertising_refund_paid", {
        p_admin_id: user.id, p_refund_id: refundId, p_bank_transfer_reference: transferReference,
      });
      if (error) return json({ error: "Refund payout could not be recorded." }, 400, origin);
      return json({ success: data === true }, 200, origin);
    }

    if (action === "admin-confirm-payment") {
      const paymentId = cleanText(body.payment_id, 64);
      if (!paymentId) return json({ error: "Payment ID is required." }, 400, origin);
      const { data, error } = await admin.rpc("admin_confirm_advertising_payment", {
        p_admin_id: user.id, p_payment_id: paymentId, p_admin_note: cleanText(body.admin_note, 500),
      });
      if (error) return json({ error: "Payment could not be confirmed. Verify the actual bank transaction and amount." }, 400, origin);
      return json({ success: !!data }, 200, origin);
    }

    if (action === "admin-review-campaign") {
      const campaignId = cleanText(body.campaign_id, 64);
      const approve = body.approve === true;
      const reason = cleanText(body.reason, 500);
      if (!campaignId || (!approve && reason.length < 3)) return json({ error: "A campaign and, when rejecting, a reason are required." }, 400, origin);
      const { data, error } = await admin.rpc("admin_review_advertising_campaign", {
        p_admin_id: user.id, p_campaign_id: campaignId, p_approve: approve, p_reason: reason,
      });
      if (error) return json({ error: "Campaign review could not be saved." }, 400, origin);
      return json({ success: true, status: data }, 200, origin);
    }

    if (action === "admin-set-campaign-state") {
      const campaignId = cleanText(body.campaign_id, 64);
      const stateAction = cleanText(body.state_action, 12);
      if (!campaignId || !["pause","resume"].includes(stateAction)) return json({ error: "Choose a valid campaign action." }, 400, origin);
      const { data, error } = await admin.rpc("admin_set_advertising_campaign_state", {
        p_admin_id: user.id, p_campaign_id: campaignId, p_action: stateAction,
      });
      if (error) return json({ error: "Campaign state could not be changed." }, 400, origin);
      return json({ success: true, status: data }, 200, origin);
    }

    if (action === "admin-overview") {
      const [campaigns, payments] = await Promise.all([
        admin.from("advertising_campaigns").select("id,status", { count: "exact" }),
        admin.from("advertising_payments").select("amount_ngn,status", { count: "exact" }).eq("status", "confirmed"),
      ]);
      if (campaigns.error || payments.error) return json({ error: "Advertising overview could not be loaded." }, 500, origin);
      const revenue = (payments.data ?? []).reduce((sum, item) => sum + Number(item.amount_ngn || 0), 0);
      return json({
        campaigns_total: campaigns.count ?? 0,
        confirmed_payments: payments.count ?? 0,
        confirmed_revenue_ngn: revenue,
      }, 200, origin);
    }

    return json({ error: "Unsupported action." }, 400, origin);
  } catch (error) {
    console.error("Advertising API failure:", error instanceof Error ? error.message : "unknown error");
    return json({ error: "The advertising service is temporarily unavailable." }, 500, origin);
  }
});
