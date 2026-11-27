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
  | "complete-profile"
  | "create-campaign"
  | "request-campaign-change"
  | "admin-list-campaign-changes"
  | "admin-review-campaign-change"
  | "submit-payment"
  | "list-campaigns"
  | "get-metrics"
  | "get-payment-details"
  | "cancel-campaign"
  | "request-refund"
  | "create-design-request"
  | "list-design-requests"
  | "submit-design-payment"
  | "request-design-revision"
  | "get-design-delivery"
  | "admin-preview-creative"
  | "admin-preview-change-creative"
  | "admin-list-campaigns"
  | "admin-list-payments"
  | "admin-list-refunds"
  | "admin-list-design-requests"
  | "admin-confirm-design-payment"
  | "admin-update-design-request"
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

function isAdvertiserToken(token: string): boolean {
  try {
    const segment = token.split(".")[1];
    if (!segment) return false;
    const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    return ["anon", "authenticated"].includes(payload.role) && payload.user_role === "advertiser";
  } catch {
    return false;
  }
}

async function authenticate(req: Request): Promise<{ user: User; caller: any; admin: any; isAdvertiser: boolean; isMatchAdmin: boolean } | null> {
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
  const isAdvertiser = isAdvertiserToken(token);
  let isMatchAdmin = false;
  if (!isAdvertiser) {
    const { data: adminRow, error: adminError } = await admin.from("app_admins")
      .select("user_id").eq("user_id", data.user.id).maybeSingle();
    isMatchAdmin = !adminError && !!adminRow;
  }
  if (!isAdvertiser && !isMatchAdmin) return null;
  return { user: data.user, caller, admin, isAdvertiser, isMatchAdmin };
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
    const { user, caller, admin, isAdvertiser, isMatchAdmin } = auth;
    const adminAction = action.startsWith("admin-");
    const campaignsOpen = Deno.env.get("ADVERTISING_CAMPAIGNS_OPEN") === "true";
    const campaignSubmissionActions = new Set<Action>([
      "create-campaign", "request-campaign-change", "submit-payment",
      "create-design-request", "submit-design-payment",
    ]);
    if (!campaignsOpen && campaignSubmissionActions.has(action)) {
      return json({ error: "Campaign submissions and advertising payments are not open yet. Your advertiser account remains available." }, 403, origin);
    }
    if (!isAdvertiser && !(isMatchAdmin && adminAction)) {
      return json({ error: "A verified advertiser session is required for this action." }, 403, origin);
    }

    if (action === "complete-profile") {
      const memberProfile = await admin.from("profiles").select("id").eq("id", user.id).maybeSingle();
      if (memberProfile.error) return json({ error: "Account type could not be verified. Please try again." }, 503, origin);
      const metadata = user.user_metadata ?? {};
      const existing = await admin.from("advertiser_profiles").select("user_id").eq("user_id", user.id).maybeSingle();
      if (existing.error) return json({ error: "Advertiser profile could not be checked." }, 500, origin);
      const suppliedType = cleanText(body.advertiser_type ?? metadata.advertiser_type, 16);
      const suppliedName = cleanText(body.display_name ?? metadata.display_name, 140);
      if (existing.data && !suppliedType && !suppliedName && body.contact_name === undefined && body.phone === undefined) {
        return json({ success: true }, 200, origin);
      }
      const advertiserType = suppliedType;
      const displayName = suppliedName || cleanText(user.email?.split("@")[0], 140);
      const contactName = cleanText(body.contact_name ?? metadata.contact_name, 140) || null;
      const phone = cleanText(body.phone ?? metadata.phone, 32) || null;
      if (!["individual", "business"].includes(advertiserType) || displayName.length < 2) {
        return json({ error: "Please complete your advertiser name and account type." }, 400, origin);
      }
      if (existing.data) {
        const update: Record<string, unknown> = {};
        if (suppliedType) update.advertiser_type = advertiserType;
        if (suppliedName) update.display_name = displayName;
        if (body.contact_name !== undefined || metadata.contact_name !== undefined) update.contact_name = contactName;
        if (body.phone !== undefined || metadata.phone !== undefined) update.phone = phone;
        if (Object.keys(update).length) {
          const { error } = await admin.from("advertiser_profiles").update(update).eq("user_id", user.id);
          if (error) return json({ error: "Advertiser profile could not be updated." }, 500, origin);
        }
      } else {
        const { error } = await admin.from("advertiser_profiles").insert({
          user_id: user.id, advertiser_type: advertiserType, display_name: displayName, contact_name: contactName, phone,
        });
        if (error) return json({ error: "Advertiser profile could not be created." }, 500, origin);
      }
      return json({ success: true }, 200, origin);
    }
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
        .select("id,headline,description,cta,destination_url,package_days,package_price_ngn,start_mode,scheduled_start_at,payment_reference,payment_deadline_at,payment_status,status,go_live_at,ends_at,created_at,advertising_payments(id,status,amount_ngn),advertising_creatives(id,is_current,creative_type),advertising_campaign_change_requests(id,status,advertiser_reason,admin_reason,proposed_creative_id,created_at,reviewed_at)")
        .eq("advertiser_id", user.id).order("created_at", { ascending: false }).limit(100);
      if (error) return json({ error: "Campaigns could not be loaded." }, 500, origin);
      return json({ campaigns: data ?? [] }, 200, origin);
    }



    if (action === "request-campaign-change") {
      const campaignId = cleanText(body.campaign_id, 64);
      const headline = cleanText(body.headline, 90) || null;
      const description = cleanText(body.description, 500) || null;
      const cta = cleanText(body.cta, 24) || null;
      const destination = body.destination_url ? validDestination(body.destination_url, cta || "learn_more") : null;
      if (cta && !body.destination_url) {
        const { data: existingCampaign, error: existingCampaignError } = await admin.from("advertising_campaigns")
          .select("destination_url").eq("id", campaignId).eq("advertiser_id", user.id).maybeSingle();
        if (existingCampaignError || !existingCampaign || !validDestination(existingCampaign.destination_url, cta)) {
          return json({ error: "The existing destination is not valid for the selected call to action. Submit an updated HTTPS destination too." }, 400, origin);
        }
      }
      const startMode = cleanText(body.start_mode, 16) || null;
      const scheduledAt = body.scheduled_start_at ? new Date(String(body.scheduled_start_at)) : null;
      const reason = cleanText(body.reason, 500);
      if (!campaignId || reason.length < 3 || (body.destination_url && !destination) ||
          (startMode && startMode !== "scheduled") ||
          (body.scheduled_start_at && (!scheduledAt || Number.isNaN(scheduledAt.getTime()) || scheduledAt.getTime() <= Date.now()))) {
        return json({ error: "Check the requested changes and include a reason." }, 400, origin);
      }
      const { data, error } = await admin.rpc("request_advertising_campaign_change", {
        p_advertiser_id: user.id, p_campaign_id: campaignId,
        p_headline: headline, p_description: description, p_cta: cta,
        p_destination_url: destination, p_start_mode: startMode,
        p_scheduled_start_at: scheduledAt?.toISOString() ?? null, p_reason: reason,
      });
      if (error) return json({ error: "A change request could not be submitted. Ensure the campaign is paid, approved and has no pending request." }, 400, origin);
      return json({ success: true, change_request_id: data, status: "pending" }, 201, origin);
    }

    if (action === "cancel-campaign") {
      const campaignId = cleanText(body.campaign_id, 64);
      if (!campaignId) return json({ error: "Campaign ID is required." }, 400, origin);
      const { data, error } = await admin.rpc("cancel_unpaid_advertising_campaign", {
        p_advertiser_id: user.id, p_campaign_id: campaignId,
      });
      if (error) return json({ error: "Only unpaid campaign reservations can be cancelled for free." }, 400, origin);
      return json({ success: data === true }, 200, origin);
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
      if (!bankName || !accountName || !/^\d{10}$/.test(accountNumber)) {
        return json({ error: "Advertising bank-transfer instructions have not been configured yet." }, 503, origin);
      }
      return json({
        campaign: { campaign_id: campaign.id, payment_reference: campaign.payment_reference, amount_ngn: campaign.package_price_ngn },
        bank_transfer: { bank_name: bankName, account_name: accountName, account_number: accountNumber },
        payment_deadline_at: campaign.payment_deadline_at,
      }, 200, origin);
    }




    if (action === "list-design-requests") {
      const { data, error } = await caller.from("advertising_design_requests")
        .select("id,service_type,fee_ngn,status,agreed_delivery_at,revisions_allowed,revisions_used,created_at,delivered_storage_key,advertising_design_payments(id,status,payment_reference,amount_ngn)")
        .eq("advertiser_id", user.id).order("created_at", { ascending: false }).limit(100);
      if (error) return json({ error: "Design requests could not be loaded." }, 500, origin);
      return json({ requests: data ?? [] }, 200, origin);
    }

    if (action === "create-design-request") {
      const serviceType = cleanText(body.service_type, 16);
      const campaignId = body.campaign_id ? cleanText(body.campaign_id, 64) : null;
      const brief = cleanText(body.brief, 3000);
      if (!["basic","premium","redesign"].includes(serviceType) || brief.length < 10) {
        return json({ error: "Choose a design package and describe the artwork you need." }, 400, origin);
      }
      const bankName = Deno.env.get("ADVERTISING_BANK_NAME") ?? "";
      const accountName = Deno.env.get("ADVERTISING_ACCOUNT_NAME") ?? "";
      const accountNumber = Deno.env.get("ADVERTISING_ACCOUNT_NUMBER") ?? "";
      if (!bankName || !accountName || !/^\d{10}$/.test(accountNumber)) {
        return json({ error: "Advertising bank-transfer instructions have not been configured yet." }, 503, origin);
      }
      const reference = "TMAD-DESIGN-" + paymentReference().slice(5);
      const { data, error } = await admin.rpc("create_advertising_design_request", {
        p_advertiser_id: user.id, p_service_type: serviceType,
        p_campaign_id: campaignId, p_brief: brief, p_payment_reference: reference,
      });
      if (error || !Array.isArray(data) || !data[0]) return json({ error: "Design request could not be created." }, 400, origin);
      return json({
        request: data[0],
        bank_transfer: { bank_name: bankName, account_name: accountName, account_number: accountNumber },
      }, 201, origin);
    }

    if (action === "submit-design-payment") {
      const paymentId = cleanText(body.payment_id, 64);
      const transferReference = cleanText(body.bank_transfer_reference, 120);
      if (!paymentId || transferReference.length < 4) return json({ error: "Enter the design payment reference from your bank transfer." }, 400, origin);
      const { data, error } = await admin.rpc("submit_advertising_design_payment", {
        p_advertiser_id: user.id, p_payment_id: paymentId, p_bank_transfer_reference: transferReference,
      });
      if (error) return json({ error: "Design payment details could not be submitted." }, 400, origin);
      return json({ success: data === true, status: "submitted" }, 200, origin);
    }

    if (action === "request-design-revision") {
      const requestId = cleanText(body.request_id, 64);
      if (!requestId) return json({ error: "Design request ID is required." }, 400, origin);
      const { data, error } = await admin.rpc("advertiser_request_design_revision", {
        p_advertiser_id: user.id, p_request_id: requestId,
      });
      if (error) return json({ error: "No revision is currently available for this design request." }, 400, origin);
      return json({ success: true, revisions_used: data }, 200, origin);
    }

    if (action === "get-design-delivery") {
      const requestId = cleanText(body.request_id, 64);
      if (!requestId) return json({ error: "Design request ID is required." }, 400, origin);
      const { data: request, error } = await admin.from("advertising_design_requests")
        .select("id,status,delivered_storage_key").eq("id", requestId)
        .eq("advertiser_id", user.id).maybeSingle();
      if (error || !request || request.status !== "completed" || !request.delivered_storage_key) {
        return json({ error: "The finished artwork is not available yet." }, 404, origin);
      }
      const bucket = Deno.env.get("B2_ADVERTISING_BUCKET_NAME") ?? "";
      const endpoint = Deno.env.get("B2_S3_ENDPOINT") ?? "";
      const keyId = Deno.env.get("B2_ADVERTISING_KEY_ID") ?? "";
      const appKey = Deno.env.get("B2_ADVERTISING_APPLICATION_KEY") ?? "";
      if (!bucket || !endpoint || !keyId || !appKey) return json({ error: "Design delivery is not configured." }, 503, origin);
      const host = new URL(endpoint).hostname;
      const region = Deno.env.get("B2_REGION") || host.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
      if (!region) return json({ error: "B2 region is not configured." }, 503, origin);
      const s3 = new S3Client({ region, endpoint, forcePathStyle: true, credentials: { accessKeyId: keyId, secretAccessKey: appKey } });
      const url = await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: request.delivered_storage_key }), { expiresIn: 300 });
      return json({ download_url: url, expires_in: 300 }, 200, origin);
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
      const { data, error } = await admin.rpc("get_advertising_campaign_metrics", {
        p_campaign_id: campaignId,
        p_advertiser_id: user.id,
      });
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
        ? campaign.advertising_creatives.find((item: { is_current: boolean }) => item.is_current) ?? campaign.advertising_creatives[0]
        : campaign.advertising_creatives;
      if (!creative?.storage_key) return json({ error: "No creative is attached to this campaign." }, 404, origin);
      const bucket = Deno.env.get("B2_ADVERTISING_BUCKET_NAME") ?? "";
      const endpoint = Deno.env.get("B2_S3_ENDPOINT") ?? "";
      const keyId = Deno.env.get("B2_ADVERTISING_KEY_ID") ?? "";
      const appKey = Deno.env.get("B2_ADVERTISING_APPLICATION_KEY") ?? "";
      if (!bucket || !endpoint || !keyId || !appKey) return json({ error: "Advertising media is not configured." }, 503, origin);
      const host = new URL(endpoint).hostname;
      const region = Deno.env.get("B2_REGION") || host.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
      if (!region) return json({ error: "B2 region is not configured." }, 503, origin);
      const s3 = new S3Client({ region, endpoint, forcePathStyle: true, credentials: { accessKeyId: keyId, secretAccessKey: appKey } });
      const previewUrl = await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: creative.storage_key }), { expiresIn: 120 });
      const posterUrl = creative.poster_storage_key
        ? await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: creative.poster_storage_key }), { expiresIn: 120 })
        : null;
      return json({ creative_type: creative.creative_type, preview_url: previewUrl, poster_url: posterUrl, expires_in: 120 }, 200, origin);
    }

    if (action === "admin-preview-change-creative") {
      const requestId = cleanText(body.change_request_id, 64);
      if (!requestId) return json({ error: "Change request ID is required." }, 400, origin);
      const { data: request, error: requestError } = await admin.from("advertising_campaign_change_requests")
        .select("id,campaign_id,proposed_creative_id,status").eq("id", requestId).maybeSingle();
      if (requestError || !request || request.status !== "pending" || !request.proposed_creative_id) {
        return json({ error: "No pending replacement creative is attached to this request." }, 404, origin);
      }
      const { data: creative, error: creativeError } = await admin.from("advertising_creatives")
        .select("creative_type,storage_key,poster_storage_key").eq("id", request.proposed_creative_id)
        .eq("campaign_id", request.campaign_id).maybeSingle();
      if (creativeError || !creative) return json({ error: "Replacement creative not found." }, 404, origin);
      const bucket = Deno.env.get("B2_ADVERTISING_BUCKET_NAME") ?? "";
      const endpoint = Deno.env.get("B2_S3_ENDPOINT") ?? "";
      const keyId = Deno.env.get("B2_ADVERTISING_KEY_ID") ?? "";
      const appKey = Deno.env.get("B2_ADVERTISING_APPLICATION_KEY") ?? "";
      if (!bucket || !endpoint || !keyId || !appKey) return json({ error: "Advertising media is not configured." }, 503, origin);
      const host = new URL(endpoint).hostname;
      const region = Deno.env.get("B2_REGION") || host.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
      if (!region) return json({ error: "B2 region is not configured." }, 503, origin);
      const s3 = new S3Client({ region, endpoint, forcePathStyle: true, credentials: { accessKeyId: keyId, secretAccessKey: appKey } });
      const previewUrl = await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: creative.storage_key }), { expiresIn: 120 });
      const posterUrl = creative.poster_storage_key
        ? await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: creative.poster_storage_key }), { expiresIn: 120 })
        : null;
      return json({ creative_type: creative.creative_type, preview_url: previewUrl, poster_url: posterUrl, expires_in: 120 }, 200, origin);
    }

    if (action === "admin-list-campaign-changes") {
      const { data, error } = await admin.from("advertising_campaign_change_requests")
        .select("*,advertising_campaigns(headline,status,package_days),advertiser_profiles(display_name,phone)")
        .order("created_at", { ascending: false }).limit(250);
      if (error) return json({ error: "Campaign change queue could not be loaded." }, 500, origin);
      return json({ requests: data ?? [] }, 200, origin);
    }

    if (action === "admin-review-campaign-change") {
      const requestId = cleanText(body.change_request_id, 64);
      const approve = body.approve === true;
      const reason = cleanText(body.reason, 500);
      if (!requestId || (!approve && reason.length < 3)) return json({ error: "A change request and rejection reason are required." }, 400, origin);
      const { data, error } = await admin.rpc("admin_review_advertising_campaign_change", {
        p_admin_id: user.id, p_change_request_id: requestId, p_approve: approve, p_reason: reason,
      });
      if (error) return json({ error: "Campaign change review could not be saved." }, 400, origin);
      return json({ success: true, status: data }, 200, origin);
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



    if (action === "admin-list-design-requests") {
      const { data, error } = await admin.from("advertising_design_requests")
        .select("*,advertiser_profiles(display_name,phone),advertising_design_payments(id,amount_ngn,status,bank_transfer_reference,payment_reference)")
        .order("created_at", { ascending: false }).limit(250);
      if (error) return json({ error: "Design service queue could not be loaded." }, 500, origin);
      return json({ requests: data ?? [] }, 200, origin);
    }

    if (action === "admin-confirm-design-payment") {
      const paymentId = cleanText(body.payment_id, 64);
      if (!paymentId) return json({ error: "Design payment ID is required." }, 400, origin);
      const { data, error } = await admin.rpc("admin_confirm_advertising_design_payment", {
        p_admin_id: user.id, p_payment_id: paymentId, p_admin_note: cleanText(body.admin_note, 500),
      });
      if (error) return json({ error: "Design payment could not be confirmed." }, 400, origin);
      return json({ success: data === true }, 200, origin);
    }

    if (action === "admin-update-design-request") {
      const requestId = cleanText(body.request_id, 64);
      const status = cleanText(body.status, 24);
      const deliveryAt = body.delivery_at ? new Date(String(body.delivery_at)) : null;
      if (!requestId || !["in_progress","first_draft_sent","completed","cancelled"].includes(status) ||
          (body.delivery_at && (!deliveryAt || Number.isNaN(deliveryAt.getTime())))) {
        return json({ error: "Invalid design request update." }, 400, origin);
      }
      const { data, error } = await admin.rpc("admin_update_advertising_design_request", {
        p_admin_id: user.id, p_request_id: requestId, p_status: status,
        p_delivery_at: deliveryAt?.toISOString() ?? null,
        p_delivered_storage_key: cleanText(body.delivered_storage_key, 500) || null,
        p_admin_note: cleanText(body.admin_note, 1000),
      });
      if (error) return json({ error: "Design request status could not be updated." }, 400, origin);
      return json({ success: true, status: data }, 200, origin);
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
      const { data, error } = await admin.rpc("get_advertising_admin_overview", { p_admin_id: user.id });
      if (error) return json({ error: "Advertising overview could not be loaded." }, 500, origin);
      return json(data?.[0] ?? {
        campaigns_total: 0,
        active_campaigns: 0,
        pending_campaigns: 0,
        confirmed_campaign_payments: 0,
        confirmed_design_payments: 0,
        design_service_revenue_ngn: 0,
        confirmed_revenue_ngn: 0,
      }, 200, origin);
    }

    return json({ error: "Unsupported action." }, 400, origin);
  } catch (error) {
    console.error("Advertising API failure:", error instanceof Error ? error.message : "unknown error");
    return json({ error: "The advertising service is temporarily unavailable." }, 500, origin);
  }
});
