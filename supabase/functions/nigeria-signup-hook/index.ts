import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { createClient } from "npm:@supabase/supabase-js@2";

const configuredSecret = Deno.env.get("BEFORE_USER_CREATED_HOOK_SECRET") ?? "";
const webhookSecret = configuredSecret.startsWith("v1,whsec_")
  ? configuredSecret.slice("v1,whsec_".length)
  : configuredSecret;
const webhook = webhookSecret ? new Webhook(webhookSecret) : null;

async function sha256Email(email: string): Promise<string> {
  const normalized = email.trim().toLowerCase();
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(normalized));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (!webhook) {
    console.error("Signup hook configuration error: missing BEFORE_USER_CREATED_HOOK_SECRET");
    return new Response(JSON.stringify({
      error: { http_code: 500, message: "Signup verification is not configured." }
    }), { status: 500, headers: { "Content-Type": "application/json" } });
  }

  const payload = await req.text();
  let event: { user?: { email?: string | null } };
  try {
    event = webhook.verify(payload, Object.fromEntries(req.headers)) as typeof event;
  } catch (error) {
    console.error("Signup hook signature verification failed:", error);
    return new Response(JSON.stringify({
      error: { http_code: 401, message: "Invalid hook signature." }
    }), { status: 401, headers: { "Content-Type": "application/json" } });
  }

  const email = event.user?.email;
  if (!email || !email.trim()) {
    return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    console.error("Signup hook configuration error: missing Supabase service credentials.");
    return new Response(JSON.stringify({
      error: { http_code: 500, message: "Signup verification is temporarily unavailable." }
    }), { status: 500, headers: { "Content-Type": "application/json" } });
  }

  try {
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const emailHash = await sha256Email(email);
    const { data, error } = await admin
      .from("deleted_account_email_blocks")
      .select("email_hash")
      .eq("email_hash", emailHash)
      .maybeSingle();

    if (error) {
      console.error("Could not check deleted-account blocklist:", error.message);
      return new Response(JSON.stringify({
        error: { http_code: 500, message: "Signup verification is temporarily unavailable. Please try again." }
      }), { status: 500, headers: { "Content-Type": "application/json" } });
    }

    if (data) {
      return new Response(JSON.stringify({
        error: {
          http_code: 403,
          message: "This email address cannot be used to create a new account because its previous account was permanently deleted."
        }
      }), { status: 403, headers: { "Content-Type": "application/json" } });
    }

    // Preserve the existing policy: valid signups from any country are allowed.
    return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (error) {
    console.error("Unexpected deleted-account signup check failure:", error);
    return new Response(JSON.stringify({
      error: { http_code: 500, message: "Signup verification is temporarily unavailable. Please try again." }
    }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});