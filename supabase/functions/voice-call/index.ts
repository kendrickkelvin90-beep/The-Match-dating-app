import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { AccessToken } from "npm:livekit-server-sdk@2.19.2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt || jwt === authHeader) return reply({ error: "Sign in is required." }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const livekitKey = Deno.env.get("LIVEKIT_API_KEY");
    const livekitSecret = Deno.env.get("LIVEKIT_API_SECRET");
    const livekitUrl = Deno.env.get("LIVEKIT_URL");
    if (!supabaseUrl || !anonKey || !serviceKey || !livekitKey || !livekitSecret || !livekitUrl) {
      console.error("Voice call function is missing required environment configuration.");
      return reply({ error: "Calling is not configured yet. Please contact support." }, 503);
    }

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
    if (authError || !authData.user) return reply({ error: "Your session is invalid. Please sign in again." }, 401);
    const userId = authData.user.id;

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");
    const callId = typeof body.call_id === "string" ? body.call_id : "";

    async function canCall(otherId: string) {
      if (!otherId || otherId === userId) return false;
      const [forward, reverse, blocks] = await Promise.all([
        admin.from("likes").select("liker_id").eq("liker_id", userId).eq("liked_id", otherId).maybeSingle(),
        admin.from("likes").select("liker_id").eq("liker_id", otherId).eq("liked_id", userId).maybeSingle(),
        admin.from("member_blocks").select("blocker_id").or(
          `and(blocker_id.eq.${userId},blocked_id.eq.${otherId}),and(blocker_id.eq.${otherId},blocked_id.eq.${userId})`
        ).limit(1),
      ]);
      if (forward.error || reverse.error || blocks.error) throw new Error("Could not verify match and block status.");
      return !!forward.data && !!reverse.data && (blocks.data?.length ?? 0) === 0;
    }

    if (action === "start") {
      const calleeId = typeof body.callee_id === "string" ? body.callee_id : "";
      if (!/^[0-9a-f-]{36}$/i.test(calleeId)) return reply({ error: "Choose a valid member to call." }, 400);
      if (!(await canCall(calleeId))) return reply({ error: "Calls are available only between mutual matches who have not blocked each other." }, 403);

      const { data: existing, error: existingError } = await admin
        .from("call_sessions").select("id")
        .or(`and(caller_id.eq.${userId},callee_id.eq.${calleeId}),and(caller_id.eq.${calleeId},callee_id.eq.${userId})`)
        .in("status", ["ringing", "accepted"]).limit(1).maybeSingle();
      if (existingError) throw existingError;
      if (existing) return reply({ error: "There is already an active call between these members." }, 409);

      const { data, error } = await admin.from("call_sessions").insert({
        caller_id: userId, callee_id: calleeId, call_type: "voice", status: "ringing",
      }).select("id,caller_id,callee_id,call_type,status,created_at").single();
      if (error) throw error;
      return reply({ call: data });
    }

    if (!/^[0-9a-f-]{36}$/i.test(callId)) return reply({ error: "A valid call ID is required." }, 400);
    const { data: call, error: callError } = await admin
      .from("call_sessions").select("*").eq("id", callId).maybeSingle();
    if (callError) throw callError;
    if (!call || (call.caller_id !== userId && call.callee_id !== userId)) {
      return reply({ error: "Call not found." }, 404);
    }

    const otherId = call.caller_id === userId ? call.callee_id : call.caller_id;

    if (action === "accept") {
      if (call.callee_id !== userId || call.status !== "ringing") return reply({ error: "This call can no longer be accepted." }, 409);
      if (!(await canCall(otherId))) {
        await admin.from("call_sessions").update({ status: "ended", ended_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", callId);
        return reply({ error: "This call is unavailable because the match or block status changed." }, 403);
      }
      const { data, error } = await admin.from("call_sessions")
        .update({ status: "accepted", updated_at: new Date().toISOString() })
        .eq("id", callId).eq("status", "ringing")
        .select("id,status").maybeSingle();
      if (error) throw error;
      if (!data) return reply({ error: "The call was already answered or cancelled." }, 409);
      return reply({ call: data });
    }

    if (action === "mute") {
      if (call.status !== "accepted") return reply({ error: "Mute controls are available only during a connected call." }, 409);
      const muted = body.muted === true;
      const muteColumn = call.caller_id === userId ? "caller_muted" : "callee_muted";
      const { error } = await admin.from("call_sessions").update({
        [muteColumn]: muted,
        updated_at: new Date().toISOString(),
      }).eq("id", callId).eq("status", "accepted");
      if (error) throw error;
      return reply({ call: { id: callId, [muteColumn]: muted } });
    }

    if (action === "reject" || action === "end") {
      if (action === "reject" && (call.callee_id !== userId || call.status !== "ringing")) {
        return reply({ error: "Only the invited member can reject a ringing call." }, 403);
      }
      if (action === "end" && !["ringing", "accepted"].includes(call.status)) {
        return reply({ error: "This call has already ended." }, 409);
      }
      const nextStatus = action === "reject" ? "rejected" : "ended";
      const { error } = await admin.from("call_sessions").update({
        status: nextStatus, ended_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      }).eq("id", callId);
      if (error) throw error;
      return reply({ call: { id: callId, status: nextStatus } });
    }

    if (action === "token") {
      if (call.status !== "accepted") return reply({ error: "The other member must accept before you can join." }, 403);
      if (!(await canCall(otherId))) {
        await admin.from("call_sessions").update({ status: "ended", ended_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", callId);
        return reply({ error: "This call is no longer available." }, 403);
      }
      const roomName = `the-match-call-${call.id}`;
      const token = new AccessToken(livekitKey, livekitSecret, {
        identity: userId,
        ttl: "10m",
      });
      token.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
      });
      return reply({ server_url: livekitUrl, participant_token: await token.toJwt() });
    }

    return reply({ error: "Unsupported call action." }, 400);
  } catch (error) {
    console.error("Voice call request failed:", error);
    return reply({ error: "The call request could not be completed. Please try again." }, 500);
  }
});
