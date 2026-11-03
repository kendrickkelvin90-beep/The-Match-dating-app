import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

function corsFor(req: Request) {
  const origin = req.headers.get("Origin");
  const configured = (Deno.env.get("APP_ALLOWED_ORIGINS") || "https://match.beyondthebinarymedia.online")
    .split(",").map(value => value.trim()).filter(Boolean);
  const allowedOrigin = origin && configured.includes(origin) ? origin : "";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(body: unknown, status = 200, cors: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}


async function sendModerationEmail(email: string, action: string, reason: string, expiresAt: string | null) {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("MODERATION_EMAIL_FROM");
  if (!apiKey || !from) {
    console.warn("Moderation email not sent: RESEND_API_KEY or MODERATION_EMAIL_FROM is not configured.");
    return { sent: false, reason: "email_provider_not_configured" };
  }

  const temporary = action === "suspended";
  const subject = temporary ? "Your The Match account has been temporarily suspended" : "Your The Match account has been permanently banned";
  const expiryText = expiresAt
    ? new Date(expiresAt).toLocaleString("en-NG", { dateStyle: "long", timeStyle: "short", timeZone: "Africa/Lagos" })
    : "";
  const safeReason = reason.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  const html = `<!doctype html><html><body style="margin:0;background:#080808;color:#f5f5f5;font-family:Arial,sans-serif;padding:32px">
    <div style="max-width:600px;margin:auto;border:1px solid #9b7a32;border-radius:14px;padding:28px;background:#111">
      <h1 style="color:#d6b45c;margin-top:0">The Match</h1>
      <h2>${temporary ? "Temporary account suspension" : "Permanent account ban"}</h2>
      <p>Hello,</p>
      <p>${temporary ? "Your account has been temporarily suspended and you cannot access The Match during this period." : "Your account has been permanently banned from The Match and you can no longer access the service."}</p>
      <p><strong>Reason:</strong><br>${safeReason}</p>
      ${temporary ? `<p><strong>Access is scheduled to be restored:</strong><br>${expiryText} (WAT)</p>` : "<p>If you believe this decision was made in error, please contact The Match support team.</p>"}
      <p style="color:#aaa;font-size:12px;margin-top:28px">This is an automated account notice. Please do not reply to this email.</p>
    </div></body></html>`;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to: [email], subject, html }),
  });
  if (!response.ok) {
    const detail = await response.text();
    console.error("Moderation email provider rejected delivery:", response.status, detail.slice(0, 400));
    return { sent: false, reason: "provider_rejected" };
  }
  const result = await response.json();
  return { sent: true, id: result?.id ?? null };
}

function previousBanDuration(previous: { status?: string; expires_at?: string | null } | null) {
  if (previous?.status === "banned") return "876000h";
  if (previous?.status === "suspended" && previous.expires_at) {
    const remaining = new Date(previous.expires_at).getTime() - Date.now();
    if (remaining > 0) return Math.max(1, Math.ceil(remaining / 1000)) + "s";
  }
  return "0s";
}

Deno.serve(async (req: Request) => {
  const cors = corsFor(req);
  const origin = req.headers.get("Origin");
  if (origin && !cors["Access-Control-Allow-Origin"]) {
    return json({ error: "Origin not allowed" }, 403, { "Vary": "Origin" });
  }
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, cors);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!url || !anon || !service || !token || token === authHeader) {
      return json({ error: "Authentication or server configuration is missing." }, 401, cors);
    }

    const caller = createClient(url, anon, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData, error: userError } = await caller.auth.getUser(token);
    if (userError || !userData.user) return json({ error: "Your session is invalid. Please sign in again." }, 401, cors);

    const { data: isAdmin, error: adminCheckError } = await caller.rpc("is_match_admin");
    if (adminCheckError || isAdmin !== true) return json({ error: "Admin access denied." }, 403, cors);

    const body = await req.json().catch(() => null) as {
      user_id?: string; action?: string; reason?: string; expires_at?: string | null;
    } | null;
    if (!body) return json({ error: "Invalid request body." }, 400, cors);

    const targetId = typeof body.user_id === "string" ? body.user_id : "";
    const action = body.action || "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    if (!targetId || targetId === userData.user.id) return json({ error: "You cannot moderate your own account." }, 400, cors);
    if (!["suspended", "banned", "restored"].includes(action)) return json({ error: "Invalid moderation action." }, 400, cors);
    if (reason.length < 3 || reason.length > 500) return json({ error: "Enter a reason between 3 and 500 characters." }, 400, cors);

    let expiresAt: string | null = null;
    let banDuration = "0s";
    if (action === "banned") {
      banDuration = "876000h"; // Supabase Auth's documented 100-year ban duration.
    } else if (action === "suspended") {
      const parsed = body.expires_at ? new Date(body.expires_at) : null;
      if (!parsed || Number.isNaN(parsed.getTime()) || parsed.getTime() <= Date.now() ||
          parsed.getTime() > Date.now() + 30 * 86400000) {
        return json({ error: "Choose a suspension expiry within the next 30 days." }, 400, cors);
      }
      expiresAt = parsed.toISOString();
      banDuration = Math.max(1, Math.ceil((parsed.getTime() - Date.now()) / 1000)) + "s";
    }

    const admin = createClient(url, service, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: adminTarget, error: adminTargetError } = await admin
      .from("app_admins").select("user_id").eq("user_id", targetId).maybeSingle();
    if (adminTargetError) return json({ error: "Could not verify the target account's admin status." }, 500, cors);
    if (adminTarget) return json({ error: "Administrator accounts cannot be moderated here." }, 403, cors);

    const { data: targetUser, error: targetUserError } = await admin.auth.admin.getUserById(targetId);
    if (targetUserError || !targetUser.user) return json({ error: "The selected member account could not be found." }, 404, cors);

    const { data: previous, error: previousError } = await admin
      .from("member_moderation").select("status,expires_at").eq("user_id", targetId).maybeSingle();
    if (previousError) return json({ error: "Could not read the current moderation status." }, 500, cors);

    // Apply the Auth restriction first so a successful action blocks future logins/refreshes.
    // If the database audit write fails, restore the previous Auth restriction.
    const { error: authError } = await admin.auth.admin.updateUserById(targetId, { ban_duration: banDuration });
    if (authError) return json({ error: "Supabase Auth could not apply this restriction: " + authError.message }, 502, cors);

    const { data: recorded, error: recordError } = await admin.rpc("record_member_moderation", {
      p_user_id: targetId,
      p_action: action,
      p_reason: reason,
      p_expires_at: expiresAt,
      p_actor_id: userData.user.id,
    });

    if (recordError || recorded?.success !== true) {
      const rollbackDuration = previousBanDuration(previous);
      const { error: rollbackError } = await admin.auth.admin.updateUserById(targetId, {
        ban_duration: rollbackDuration,
      });
      if (rollbackError) {
        console.error("Moderation rollback failed:", rollbackError.message);
        return json({ error: "The moderation record could not be saved and Auth rollback needs administrator review." }, 500, cors);
      }
      return json({ error: recordError?.message || "The moderation record could not be saved. The previous account restriction was restored." }, 400, cors);
    }

    let emailDelivery: { sent: boolean; reason?: string; id?: string | null } = { sent: false, reason: "not_applicable" };
    if (action === "suspended" || action === "banned") {
      const recipientEmail = targetUser.user.email;
      if (recipientEmail) {
        try {
          emailDelivery = await sendModerationEmail(recipientEmail, action, reason, expiresAt);
        } catch (emailError) {
          console.error("Moderation email delivery failed:", emailError instanceof Error ? emailError.message : "Unknown error");
          emailDelivery = { sent: false, reason: "delivery_error" };
        }
      } else {
        emailDelivery = { sent: false, reason: "member_email_missing" };
      }
    }

    return json({ success: true, user_id: targetId, action, expires_at: expiresAt, email_delivery: emailDelivery });
  } catch (error) {
    console.error("Member moderation failed:", error instanceof Error ? error.message : "Unknown error");
    return json({ error: "Member moderation could not be completed. Please try again." }, 500, cors);
  }
});
