import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ONESIGNAL_APP_ID = "c5deb192-536d-4498-ba4b-b973d50d5ba6";
const ONESIGNAL_API_URL = "https://api.onesignal.com/notifications";
const RESEND_API_URL = "https://api.resend.com/emails";
const APP_URL = "https://match.beyondthebinarymedia.online/";
const EMAIL_FROM = "The Match <noreply@beyondthebinarymedia.online>";
const ACCOUNT_EMAIL_TYPES = new Set([
  "verification_rejected",
  "premium_welcome",
  "membership_payment_rejected",
]);

function reply(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function getServiceRoleJwt(req: Request): string | null {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  const payload = token.split(".")[1];
  if (!payload) return null;
  try {
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    if (claims.role !== "service_role" || claims.ref !== "rxbdmgzmwhjnkcclyrcq") return null;
    // Supabase gateway verifies the JWT signature because verify_jwt is enabled.
    return token;
  } catch {
    return null;
  }
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character] ?? character);
}

async function sendMembershipEmail(
  userId: string,
  notificationId: string,
  type: string,
  title: string,
  body: string,
  serviceRoleJwt: string,
): Promise<void> {
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  if (!resendKey) throw new Error("RESEND_API_KEY is not configured.");
  if (!supabaseUrl) throw new Error("SUPABASE_URL is not configured.");
  if (!serviceRoleJwt) throw new Error("SUPABASE_SERVICE_ROLE_KEY is unavailable for the Auth Admin lookup.");
  if (!notificationId) throw new Error("Membership email requires a notification ID for idempotency.");

  // Look up the recipient server-side. Never accept an email address from the webhook payload.
  const userResponse = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(userId)}`,
    {
      headers: {
        "apikey": serviceRoleJwt,
        "Authorization": `Bearer ${serviceRoleJwt}`,
      },
    },
  );
  if (!userResponse.ok) {
    const detail = (await userResponse.text()).slice(0, 300);
    throw new Error(`Could not retrieve membership email recipient (${userResponse.status}): ${detail}`);
  }

  const user = await userResponse.json();
  const email = typeof user?.email === "string" ? user.email.trim() : "";
  if (!email) throw new Error("The member account does not have an email address.");

  const safeTitle = escapeHtml(title);
  const safeBody = escapeHtml(body);
  const subject = type === "membership_payment_rejected"
    ? "Update about your membership payment - The Match"
    : title.slice(0, 150);

  const html = `
    <div style="margin:0;padding:32px 16px;background:#080808;font-family:Arial,Helvetica,sans-serif;color:#f5f5f5">
      <div style="max-width:560px;margin:0 auto;border:1px solid #80652d;border-radius:16px;background:#111;padding:28px">
        <div style="font-size:12px;letter-spacing:3px;color:#d5b45c;font-weight:bold">THE MATCH</div>
        <h1 style="font-size:22px;line-height:1.35;margin:22px 0 14px;color:#f5d77b">${safeTitle}</h1>
        <p style="font-size:15px;line-height:1.7;color:#e7e2d7;white-space:pre-line">${safeBody}</p>
        <a href="${APP_URL}" style="display:inline-block;margin-top:18px;padding:12px 20px;border-radius:8px;background:#c5a34e;color:#090909;text-decoration:none;font-weight:bold">Open The Match</a>
        <p style="font-size:12px;line-height:1.6;color:#999;margin-top:28px">This is an account notification from The Match. Please do not reply to this automated email.</p>
      </div>
    </div>`;

  const emailResponse = await fetch(RESEND_API_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${resendKey}`,
      "Content-Type": "application/json",
      // The same notification can be retried by the database webhook without sending duplicates.
      "Idempotency-Key": `the-match/membership-notification/${notificationId}`,
    },
    body: JSON.stringify({
      from: EMAIL_FROM,
      to: [email],
      subject,
      html,
      text: `${title}\n\n${body}\n\nOpen The Match: ${APP_URL}`,
    }),
  });

  if (!emailResponse.ok) {
    const detail = (await emailResponse.text()).slice(0, 500);
    throw new Error(`Resend rejected membership email (${emailResponse.status}): ${detail}`);
  }
  const result = await emailResponse.json();
  console.log("Membership email accepted by Resend:", result?.id ?? "accepted", "type:", type);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply({ error: "Method not allowed." }, 405);

  // Database Webhooks send the project secret in the apikey header.
  const serviceRoleJwt = getServiceRoleJwt(req);
  if (!serviceRoleJwt) return reply({ error: "Unauthorized webhook." }, 401);

  try {
    const payload = await req.json();
    if (
      payload?.type !== "INSERT" ||
      payload?.schema !== "public" ||
      payload?.table !== "notifications"
    ) {
      return reply({ ignored: true, reason: "Unsupported database event." });
    }

    const notification = payload.record;
    const userId = typeof notification?.user_id === "string" ? notification.user_id : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId)) {
      return reply({ ignored: true, reason: "Missing or invalid recipient." });
    }
    const title = String(notification?.title ?? "New activity on The Match").slice(0, 120);
    const body = String(notification?.body ?? "You have a new notification.").slice(0, 500);
    const notificationId = String(notification?.id ?? "");
    const type = String(notification?.type ?? "activity").slice(0, 80);

    const failures: string[] = [];
    const oneSignalKey = Deno.env.get("ONESIGNAL_REST_API_KEY");

    if (oneSignalKey) {
      const pushResponse = await fetch(ONESIGNAL_API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Key ${oneSignalKey}`,
        },
        body: JSON.stringify({
          app_id: ONESIGNAL_APP_ID,
          target_channel: "push",
          include_aliases: { external_id: [userId] },
          headings: { en: title },
          contents: { en: body },
          url: APP_URL,
          data: { notification_id: notificationId, type },
          idempotency_key: notificationId || undefined,
        }),
      });

      if (!pushResponse.ok) {
        const responseText = await pushResponse.text();
        console.error("OneSignal push request failed:", pushResponse.status, responseText.slice(0, 500));
        failures.push("push");
      }
    } else {
      console.error("ONESIGNAL_REST_API_KEY is not configured; push was skipped.");
      failures.push("push");
    }

    if (ACCOUNT_EMAIL_TYPES.has(type)) {
      try {
        await sendMembershipEmail(userId, notificationId, type, title, body, serviceRoleJwt);
      } catch (error) {
        console.error("Membership email delivery failed:", error);
        failures.push("email");
      }
    }

    // Returning a failure lets Supabase retry the webhook. Both providers receive
    // stable idempotency keys, so a successful channel is not duplicated on retry.
    if (failures.length) {
      return reply({ error: "One or more notification channels failed.", failed_channels: failures }, 502);
    }
    return reply({ success: true, push: Boolean(oneSignalKey), email: ACCOUNT_EMAIL_TYPES.has(type) });
  } catch (error) {
    console.error("Notification webhook failed:", error);
    return reply({ error: "Could not process notification event." }, 500);
  }
});
