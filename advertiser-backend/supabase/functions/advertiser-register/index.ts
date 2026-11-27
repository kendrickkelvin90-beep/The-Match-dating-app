import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const allowedOrigins = new Set(
  (Deno.env.get("ADVERTISER_ALLOWED_ORIGINS") ?? "https://match.beyondthebinarymedia.online")
    .split(",").map((value) => value.trim()).filter(Boolean),
);

function response(body: unknown, status: number, origin: string) {
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

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
  if (origin && !allowedOrigins.has(origin)) return response({ error: "Origin not allowed" }, 403, origin);
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Vary": "Origin",
      },
    });
  }
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405, origin);
  if (!url || !anonKey || !serviceKey) return response({ error: "Registration service is not configured." }, 503, origin);

  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  if (!token || token === header) return response({ error: "Sign in and verify your email first." }, 401, origin);

  const caller = createClient(url, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data, error } = await caller.auth.getUser(token);
  const user = data.user;
  if (error || !user || !user.email_confirmed_at) {
    return response({ error: "A verified advertiser account is required." }, 401, origin);
  }

  // Any verified Match Auth identity may enrol, including an existing dating
  // member. The protected registry, not user-editable metadata, grants access.
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const clean = (value: unknown, max: number) =>
    typeof value === "string" ? value.trim().replace(/[<>]/g, "").slice(0, max) : "";
  const advertiserType = clean(body.advertiser_type, 16);
  const displayName = clean(body.display_name, 140);
  const contactName = clean(body.contact_name, 140);
  const phone = clean(body.phone, 32);
  if (!["individual", "business"].includes(advertiserType) || displayName.length < 2) {
    return response({ error: "Choose Individual or Business / Organisation and enter the advertiser name." }, 400, origin);
  }

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error: enrollError } = await admin.rpc("register_advertiser_account", {
    p_user_id: user.id,
  });
  if (enrollError) {
    console.error("Advertiser enrollment failed:", enrollError.message);
    return response({ error: "Advertiser registration could not be completed. Please try again." }, 400, origin);
  }

  const { error: profileError } = await admin.from("advertiser_profiles").upsert({
    user_id: user.id,
    advertiser_type: advertiserType,
    display_name: displayName,
    contact_name: contactName || null,
    phone: phone || null,
  }, { onConflict: "user_id", ignoreDuplicates: true });
  if (profileError) {
    console.error("Advertiser profile creation failed:", profileError.message);
    return response({ error: "Your advertiser access was enrolled, but the advertiser profile could not be saved. Please retry." }, 500, origin);
  }

  return response({
    success: true,
    advertiser_type: advertiserType,
    display_name: displayName,
    contact_name: contactName,
    phone,
    next_step: "Refresh the session to activate advertiser access.",
  }, 200, origin);
});
