import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ONESIGNAL_APP_ID = "c5deb192-536d-4498-ba4b-b973d50d5ba6";
const ONESIGNAL_API_URL = "https://api.onesignal.com/notifications";
const APP_URL = "https://match.beyondthebinarymedia.online/";

function reply(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function getSupabaseSecretKey(): string | null {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;

  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    return typeof keys.default === "string" ? keys.default : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply({ error: "Method not allowed." }, 405);

  // Supabase Database Webhooks send the project secret key in the apikey header.
  // Keep JWT verification disabled for this database-to-function webhook and
  // validate the key here instead.
  const expectedKey = getSupabaseSecretKey();
  const suppliedKey = req.headers.get("apikey");
  if (!expectedKey || !suppliedKey || suppliedKey !== expectedKey) {
    return reply({ error: "Unauthorized webhook." }, 401);
  }

  const oneSignalKey = Deno.env.get("ONESIGNAL_REST_API_KEY");
  if (!oneSignalKey) {
    console.error("ONESIGNAL_REST_API_KEY is not configured.");
    return reply({ error: "Push delivery is not configured." }, 503);
  }

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
    if (notification?.is_read === true) {
      return reply({ ignored: true, reason: "Notification is already read." });
    }

    const title = String(notification?.title ?? "New activity on The Match").slice(0, 120);
    const body = String(notification?.body ?? "You have a new notification.").slice(0, 500);
    const notificationId = String(notification?.id ?? "");
    const type = String(notification?.type ?? "activity").slice(0, 80);

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
      return reply({ error: "Push provider rejected the notification." }, 502);
    }

    const result = await pushResponse.json();
    return reply({ success: true, id: result?.id ?? null });
  } catch (error) {
    console.error("Notification push handler failed:", error);
    return reply({ error: "Could not process notification event." }, 500);
  }
});
