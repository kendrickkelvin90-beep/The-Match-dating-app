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

  // This metadata value is only an explicit enrollment intent, never an
  // authorization claim. The service-side SQL function independently checks
  // the verified Auth user and rejects anyone with a Match member profile.
  if (user.user_metadata?.the_match_advertiser_registration !== "v1") {
    return response({ error: "This account has not started advertiser registration." }, 403, origin);
  }

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error: enrollError } = await admin.rpc("register_advertiser_account", {
    p_user_id: user.id,
  });
  if (enrollError) {
    const memberAccount = /Match member account/i.test(enrollError.message);
    return response({
      error: memberAccount
        ? "This email already belongs to a Match dating-member account. Please use a separate email for advertising."
        : "Advertiser registration could not be completed. Please try again.",
    }, memberAccount ? 403 : 400, origin);
  }

  return response({
    success: true,
    next_step: "Refresh the advertiser session to receive its separate advertiser access token.",
  }, 200, origin);
});
