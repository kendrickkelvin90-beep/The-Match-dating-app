import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function isAdvertiserSession(token: string): boolean {
  try {
    const segment = token.split(".")[1];
    if (!segment) return false;
    const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    return payload.role === "anon" && payload.user_role === "advertiser";
  } catch {
    return false;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const respond = (body: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method !== "POST") return respond({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const geoapifyKey = Deno.env.get("GEOAPIFY_API_KEY");
  if (!supabaseUrl || !supabaseAnonKey || !geoapifyKey) {
    return respond({ error: "Server configuration is incomplete" }, 500);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return respond({ error: "Authentication required" }, 401);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return respond({ error: "Invalid session" }, 401);
    if (isAdvertiserSession(authorization.slice(7))) return respond({ error: "Advertiser accounts cannot use member location services." }, 403);

  let body: { latitude?: unknown; longitude?: unknown };
  try {
    body = await req.json();
  } catch {
    return respond({ error: "Invalid JSON body" }, 400);
  }

  const latitude = Number(body.latitude);
  const longitude = Number(body.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return respond({ error: "Valid latitude and longitude are required" }, 400);
  }

  try {
    const url = new URL("https://api.geoapify.com/v1/geocode/reverse");
    url.searchParams.set("lat", String(latitude));
    url.searchParams.set("lon", String(longitude));
    url.searchParams.set("format", "json");
    url.searchParams.set("apiKey", geoapifyKey);
    const response = await fetch(url.toString());
    if (!response.ok) {
      console.error("Geoapify reverse geocoding failed:", response.status);
      return respond({ error: "Could not look up current location" }, 502);
    }

    const result = await response.json();
    const properties = result?.results?.[0] ?? result?.features?.[0]?.properties;
    if (!properties) return respond({ city: null, state: null, country: null });

    // Prefer a neighbourhood-scale label; fall back to a town/city when Geoapify
    // does not provide a more local area. Never return a street or house address.
    const localArea =
      properties.suburb ??
      properties.neighbourhood ??
      properties.neighborhood ??
      properties.quarter ??
      properties.district ??
      null;

    return respond({
      city: localArea ?? properties.city ?? properties.town ?? properties.village ?? properties.municipality ?? null,
      state: properties.state ?? properties.region ?? null,
      country: properties.country ?? null,
    });
  } catch (error) {
    console.error("Reverse geocoding error:", error);
    return respond({ error: "Reverse geocoding request failed" }, 502);
  }
});