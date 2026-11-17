import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set([
  "https://match.beyondthebinarymedia.online",
]);

function corsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || "";
  const allowed = !origin || allowedOrigins.has(origin);
  return {
    allowed,
    headers: {
      ...(origin && allowed ? { "Access-Control-Allow-Origin": origin } : {}),
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  };
}

function json(body: Record<string, unknown>, status: number, headers: Record<string, string>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req);
  if (!cors.allowed) return json({ error: "Origin not allowed." }, 403, cors.headers);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors.headers });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405, cors.headers);

  try {
    const authorization = req.headers.get("Authorization") || "";
    const token = authorization.replace(/^Bearer\s+/i, "");
    if (!token || token === authorization) {
      return json({ error: "Sign in first." }, 401, cors.headers);
    }

    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) {
      console.error("View Once signing is missing server configuration.");
      return json({ error: "View Once is temporarily unavailable." }, 500, cors.headers);
    }

    const caller = createClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: authData, error: authError } = await caller.auth.getUser(token);
    if (authError || !authData.user) {
      return json({ error: "Your session is invalid. Sign in again." }, 401, cors.headers);
    }

    const body = await req.json().catch(() => null) as { media_id?: unknown } | null;
    const mediaId = typeof body?.media_id === "string" ? body.media_id : "";
    if (!mediaId) return json({ error: "A media ID is required." }, 400, cors.headers);

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Read only enough metadata to prepare a short-lived URL. The atomic RPC
    // below decides which concurrent opener wins; losing callers never receive it.
    const { data: media, error: mediaError } = await admin
      .from("chat_media")
      .select("id, receiver_id, storage_path, view_once, opened_at")
      .eq("id", mediaId)
      .maybeSingle();

    if (mediaError) {
      console.error("Could not inspect View Once media:", mediaError.message);
      return json({ error: "Could not open this media." }, 500, cors.headers);
    }
    if (!media || media.receiver_id !== authData.user.id || media.view_once !== true) {
      return json({ error: "Media not found or access denied." }, 404, cors.headers);
    }
    if (media.opened_at) {
      return json({ error: "This View Once media has already been opened." }, 409, cors.headers);
    }

    const { data: signed, error: signError } = await admin.storage
      .from("chat-media")
      .createSignedUrl(media.storage_path, 60);

    if (signError || !signed?.signedUrl) {
      console.error("Could not sign View Once media:", signError?.message || "No signed URL returned");
      return json({ error: "Could not prepare this media for viewing." }, 500, cors.headers);
    }

    // This SECURITY DEFINER RPC locks the row, rechecks eligibility and marks
    // the receiver's one permitted opening. Only the successful caller receives
    // the signed URL; concurrent/replayed claims are rejected.
    const { data: claimed, error: claimError } = await caller.rpc(
      "claim_view_once_chat_media",
      { p_media_id: mediaId },
    );

    if (claimError || !claimed?.length) {
      return json({
        error: claimError?.message || "This View Once media has already been opened.",
      }, 409, cors.headers);
    }

    return json({
      signedUrl: signed.signedUrl,
      mediaType: claimed[0].media_type,
      expiresIn: 60,
    }, 200, cors.headers);
  } catch (error) {
    console.error("View Once delivery failed:", error instanceof Error ? error.message : "Unknown error");
    return json({ error: "Could not open this media. Please try again." }, 500, cors.headers);
  }
});
