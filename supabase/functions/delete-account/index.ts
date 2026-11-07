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
  const markers = [
    "/storage/v1/object/public/" + bucket + "/",
    "/storage/v1/object/sign/" + bucket + "/",
    "/storage/v1/object/authenticated/" + bucket + "/",
  ];
  for (const marker of markers) {
    const index = raw.indexOf(marker);
    if (index >= 0) {
      const path = raw.slice(index + marker.length).split("?")[0];
      try { return decodeURIComponent(path); } catch { return path; }
    }
  }
  if (!raw.startsWith("http://") && !raw.startsWith("https://")) {
    return raw.replace(/^[/]+/, "");
  }
  return null;
}

async function sha256Email(email: string): Promise<string> {
  const normalized = email.trim().toLowerCase();
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(normalized));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
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
      global: { headers: { Authorization: "Bearer " + token } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData.user) return response({ error: "Your session is invalid. Sign in again." }, 401);

    const body = await req.json().catch(() => ({}));
    if (body?.confirm !== "DELETE_MY_ACCOUNT") {
      return response({ error: "Explicit deletion confirmation is required." }, 400);
    }

    const userId = userData.user.id;
    const email = userData.user.email;
    if (!email) return response({ error: "A verified email is required to permanently delete this account." }, 400);

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const [photos, stories, selfies, profile] = await Promise.all([
      admin.from("profile_photos").select("storage_path").eq("user_id", userId),
      admin.from("stories").select("media_url").eq("user_id", userId),
      admin.from("verification_requests").select("selfie_path").eq("user_id", userId),
      admin.from("profiles").select("avatar_url").eq("id", userId).maybeSingle(),
    ]);
    for (const result of [photos, stories, selfies, profile]) {
      if (result.error) {
        console.error("Could not prepare account data cleanup:", result.error.message);
        return response({ error: "Could not prepare deletion. No account data was deleted." }, 500);
      }
    }

    const files: Record<string, Set<string>> = {
      "profile-photos": new Set<string>(),
      "story-media": new Set<string>(),
      "verification-selfies": new Set<string>(),
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

    for (const [bucket, paths] of Object.entries(files)) {
      if (paths.size === 0) continue;
      const { error } = await admin.storage.from(bucket).remove([...paths]);
      if (error) {
        console.error("Storage cleanup failed for bucket", bucket, error.message);
        return response({ error: "Could not safely remove account files. No account data was deleted; please try again or contact support." }, 500);
      }
    }

    // Retain only a normalized email hash to prevent the deleted address being reused.
    const emailHash = await sha256Email(email);
    const { error: blockError } = await admin
      .from("deleted_account_email_blocks")
      .insert({ email_hash: emailHash, source: "self_service_account_deletion" });

    const createdBlock = !blockError;
    if (blockError && blockError.code !== "23505") {
      console.error("Could not record deleted-account block:", blockError.message);
      return response({ error: "Could not safely complete account deletion. Please try again or contact support." }, 500);
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error("Auth account deletion failed:", deleteError.message);
      if (createdBlock) {
        const { error: rollbackError } = await admin
          .from("deleted_account_email_blocks")
          .delete()
          .eq("email_hash", emailHash);
        if (rollbackError) console.error("Could not roll back deletion block after failed deletion:", rollbackError.message);
      }
      return response({ error: "Could not delete your account. Please contact support." }, 500);
    }

    return response({ success: true, message: "Your account and associated database records have been deleted. This email address cannot be used to create another account." });
  } catch (error) {
    console.error("Unexpected account deletion error:", error instanceof Error ? error.message : "Unknown error");
    return response({ error: "Account deletion failed. Please contact support." }, 500);
  }
});