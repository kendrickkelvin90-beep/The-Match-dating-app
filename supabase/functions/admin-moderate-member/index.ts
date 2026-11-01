import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authHeader = req.headers.get("Authorization");
  if (!url || !anon || !service || !authHeader) return json({ error: "Server configuration or authentication missing" }, 500);

  const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ error: "Authentication required" }, 401);
  const { data: isAdmin, error: adminError } = await caller.rpc("is_match_admin");
  if (adminError || isAdmin !== true) return json({ error: "Admin access denied" }, 403);

  let body: { user_id?: string; action?: string; reason?: string; expires_at?: string | null };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }
  const target = body.user_id;
  const action = body.action;
  const reason = (body.reason || "").trim();
  if (!target || target === user.id) return json({ error: "Invalid target account" }, 400);
  if (!["suspended", "banned", "restored"].includes(action || "")) return json({ error: "Invalid action" }, 400);
  if (action !== "restored" && (reason.length < 3 || reason.length > 1000)) return json({ error: "A reason is required (3–1000 characters)" }, 400);

  const admin = createClient(url, service, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: targetAdmin } = await admin.from("app_admins").select("user_id").eq("user_id", target).maybeSingle();
  if (targetAdmin) return json({ error: "Administrator accounts cannot be moderated here" }, 403);

  let banDuration = "none";
  if (action === "banned") banDuration = "876000h";
  if (action === "suspended") {
    const until = body.expires_at ? new Date(body.expires_at) : null;
    if (!until || Number.isNaN(until.getTime()) || until <= new Date() || until.getTime() > Date.now() + 30 * 86400000) {
      return json({ error: "Choose a suspension expiry within the next 30 days" }, 400);
    }
    banDuration = Math.max(60, Math.ceil((until.getTime() - Date.now()) / 1000)) + "s";
  }

  const { data: rpcData, error: rpcError } = await caller.rpc("admin_set_member_moderation", {
    p_user_id: target,
    p_action: action,
    p_reason: reason || null,
    p_expires_at: action === "suspended" ? body.expires_at : null,
  });
  if (rpcError) return json({ error: rpcError.message }, 400);

  const { error: authError } = await admin.auth.admin.updateUserById(target, { ban_duration: banDuration });
  if (authError) {
    // Revert the moderation record if Auth could not apply the restriction.
    await caller.rpc("admin_set_member_moderation", {
      p_user_id: target, p_action: "restored",
      p_reason: "Automatic rollback: Auth restriction could not be applied",
      p_expires_at: null,
    });
    return json({ error: "Auth restriction failed; database action was rolled back: " + authError.message }, 502);
  }
  return json({ success: true, action, user_id: target });
});
