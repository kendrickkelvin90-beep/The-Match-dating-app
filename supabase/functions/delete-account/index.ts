import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function storagePath(value: unknown, bucket: string): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const raw = value.trim();
  if (raw.startsWith("b2://")) return null;
  const markers = [
    `/storage/v1/object/public/${bucket}/`,
    `/storage/v1/object/sign/${bucket}/`,
    `/storage/v1/object/authenticated/${bucket}/`,
  ];
  for (const marker of markers) {
    const index = raw.indexOf(marker);
    if (index >= 0) {
      const path = raw.slice(index + marker.length).split("?")[0];
      try { return decodeURIComponent(path); } catch { return path; }
    }
  }
  if (!raw.startsWith("http://") && !raw.startsWith("https://")) {
    return raw.replace(/^\/+/, "");
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return response({ error: "Use POST." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token || token === authHeader) return response({ error: "Sign in first." }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) {
      console.error("Missing required Supabase function environment variables.");
      return response({ error: "Account deletion is temporarily unavailable." }, 500);
    }

    const userClient = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData.user) return response({ error: "Your session is invalid. Sign in again." }, 401);

    const body = await req.json().catch(() => ({}));
    if (body?.confirm !== "DELETE_MY_ACCOUNT") {
      return response({ error: "Explicit deletion confirmation is required." }, 400);
    }

    const userId = userData.user.id;
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const [photos, stories, selfies, profile, chatMedia] = await Promise.all([
      admin.from("profile_photos").select("storage_path").eq("user_id", userId),
      admin.from("stories").select("media_url").eq("user_id", userId),
      admin.from("verification_requests").select("selfie_path").eq("user_id", userId),
      admin.from("profiles").select("avatar_url").eq("id", userId).maybeSingle(),
      admin.from("chat_media").select("storage_path").or(`sender_id.eq.${userId},receiver_id.eq.${userId}`),
    ]);
    for (const result of [photos, stories, selfies, profile, chatMedia]) {
      if (result.error) {
        console.error("Could not prepare account data cleanup:", result.error.message);
        return response({ error: "Could not prepare deletion. No account data was deleted." }, 500);
      }
    }

    const files: Record<string, Set<string>> = {
      "profile-photos": new Set<string>(),
      "story-media": new Set<string>(),
      "verification-selfies": new Set<string>(),
      "chat-media": new Set<string>(),
    };
    for (const row of photos.data || []) {
      const path = storagePath(row.storage_path, "profile-photos");
      if (path) files["profile-photos"].add(path);
    }
    const avatar = storagePath(profile.data?.avatar_url, "profile-photos");
    if (avatar) files["profile-photos"].add(avatar);
    for (const row of stories.data || []) {
      const path = storagePath(row.media_url, "story-media");
      if (path) files["story-media"].add(path);
    }
    for (const row of selfies.data || []) {
      const path = storagePath(row.selfie_path, "verification-selfies");
      if (path) files["verification-selfies"].add(path);
    }
    for (const row of chatMedia.data || []) {
      const path = storagePath(row.storage_path, "chat-media");
      if (path) files["chat-media"].add(path);
    }

    // B2 deletion derives the owner from this same authenticated session.
    const b2Response = await fetch(`${url}/functions/v1/b2-media`, {
      method: "POST",
      headers: {
        "apikey": anonKey,
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ action: "delete-account-profile-photos" }),
    });
    const b2Result = await b2Response.json().catch(() => ({}));
    if (!b2Response.ok || b2Result?.error) {
      console.error("Backblaze account media cleanup failed:", b2Result?.error || b2Response.status);
      return response({ error: "Could not safely remove your external profile photos. Your account has not been deleted; please try again or contact support." }, 500);
    }

    for (const [bucket, paths] of Object.entries(files)) {
      if (paths.size === 0) continue;
      const { error } = await admin.storage.from(bucket).remove([...paths]);
      if (error) {
        console.error("Storage cleanup failed for bucket", bucket, error.message);
        return response({ error: "Could not safely remove account files. Your account has not been deleted; please try again or contact support." }, 500);
      }
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error("Auth account deletion failed:", deleteError.message);
      return response({ error: "Could not delete your account. Please contact support." }, 500);
    }

    return response({
      success: true,
      message: "Your account and associated database records have been deleted.",
      mediaCleanup: {
        backblazeProfilePhotos: b2Result?.deletedCount ?? 0,
        supabaseObjects: Object.values(files).reduce((count, paths) => count + paths.size, 0),
      },
    });
  } catch (error) {
    console.error("Unexpected account deletion error:", error instanceof Error ? error.message : "Unknown error");
    return response({ error: "Account deletion failed. Please contact support." }, 500);
  }
});
