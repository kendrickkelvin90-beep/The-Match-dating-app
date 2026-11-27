import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, HeadObjectCommand } from "npm:@aws-sdk/client-s3";

const cors = {
  "Access-Control-Allow-Origin": "https://match.beyondthebinarymedia.online",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const reply = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });

const configs = [
  { category: "profile_photos", table: "profile_photos", bucket: "profile-photos", path: "storage_path", id: "id", activeOnly: false },
  { category: "stories", table: "stories", bucket: "story-media", path: "media_url", id: "id", activeOnly: false },
  { category: "verification_selfies", table: "verification_requests", bucket: "verification-selfies", path: "selfie_path", id: "id", activeOnly: false },
  { category: "event_posters", table: "match_event_poster_assets", bucket: "event-posters", path: "storage_path", id: "event_id", activeOnly: false },
] as const;

function isAdvertiserSession(token: string): boolean {
  try {
    const segment = token.split(".")[1];
    if (!segment) return false;
    const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    return payload.role === "anon" && payload.user_role === "advertiser";
  } catch { return false; }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "POST only" }, 405);
  try {
    const auth = req.headers.get("Authorization") || "";
    if (!auth.startsWith("Bearer ")) return reply({ error: "Sign-in required" }, 401);
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const caller = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: user, error: userError } = await caller.auth.getUser();
    if (userError || !user.user) return reply({ error: "Invalid session" }, 401);
    const sessionToken = auth.startsWith("Bearer ") ? auth.slice(7) : "";
    if (isAdvertiserSession(sessionToken)) return reply({ error: "Advertiser accounts cannot use member storage cleanup." }, 403);
    const { data: isAdmin, error: adminError } = await caller.rpc("is_match_admin");
    if (adminError || isAdmin !== true) return reply({ error: "Administrator access required" }, 403);

    const body = await req.json().catch(() => ({}));
    const execute = body.action === "execute" && body.confirm === "DELETE_ONLY_VERIFIED_SUPABASE_COPIES";
    if (body.action !== "dry-run" && !execute) return reply({ error: "Use action dry-run, or the exact confirmation phrase for execution." }, 400);

    const missing = ["B2_KEY_ID","B2_APPLICATION_KEY","B2_BUCKET_NAME","B2_S3_ENDPOINT"].filter(k => !Deno.env.get(k));
    if (missing.length) return reply({ error: "B2 configuration missing", missing }, 500);
    const endpoint = Deno.env.get("B2_S3_ENDPOINT")!;
    const region = Deno.env.get("B2_REGION") || new URL(endpoint).hostname.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
    if (!region) return reply({ error: "Could not determine B2 region" }, 500);
    const s3 = new S3Client({ region, endpoint, forcePathStyle: true, credentials: {
      accessKeyId: Deno.env.get("B2_KEY_ID")!, secretAccessKey: Deno.env.get("B2_APPLICATION_KEY")!
    }});
    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
    const results: any[] = [];
    let totalCandidates = 0, totalDeleted = 0, totalBytes = 0;

    for (const cfg of configs) {
      let from = 0, checked = 0, eligible = 0, deleted = 0, bytes = 0, missingB2 = 0, missingLegacy = 0, provenanceMismatch = 0, errors = 0;
      const examples: string[] = [];
      while (true) {
        let q = admin.from(cfg.table).select(`${cfg.id},${cfg.path}`).like(cfg.path, "b2://%").range(from, from + 99);
        if (cfg.category === "stories") q = q.lt("expires_at", new Date().toISOString());
        const { data: rows, error } = await q;
        if (error) throw new Error(`Could not read ${cfg.table}: ${error.message}`);
        if (!rows?.length) break;
        for (const row of rows as any[]) {
          checked++;
          const key = String(row[cfg.path] || "").replace(/^b2:\/\//, "");
          if (!key || key.includes("..") || key.startsWith("/") || key.length > 900) { provenanceMismatch++; continue; }
          try {
            const head = await s3.send(new HeadObjectCommand({ Bucket: Deno.env.get("B2_BUCKET_NAME")!, Key: key }));
            const md = head.Metadata || {};
            const sourcePath = md["source-path"] || "";
            const sourceBucket = md["source-bucket"] || "";
            const sourceRow = md["source-row"] || "";
            if (sourceBucket !== cfg.bucket || !sourcePath || sourceRow !== String(row[cfg.id])) { provenanceMismatch++; continue; }
            const { data: old, error: oldErr } = await admin.storage.from(cfg.bucket).list(sourcePath.split("/").slice(0,-1).join("/"), { search: sourcePath.split("/").pop(), limit: 100 });
            if (oldErr) { errors++; continue; }
            const exactExists = (old || []).some((o: any) => o.name === sourcePath.split("/").pop());
            if (!exactExists) { missingLegacy++; continue; }
            const size = Number(head.ContentLength || 0);
            eligible++; bytes += size; totalCandidates++; totalBytes += size;
            if (examples.length < 5) examples.push(sourcePath);
            if (execute) {
              const { error: removeError } = await admin.storage.from(cfg.bucket).remove([sourcePath]);
              if (removeError) { errors++; continue; }
              deleted++; totalDeleted++;
            }
          } catch (e) {
            const msg = e instanceof Error ? e.message : String(e);
            if (/NotFound|NoSuchKey|404/i.test(msg)) missingB2++;
            else errors++;
          }
        }
        from += rows.length;
        if (rows.length < 100) break;
      }
      results.push({ category: cfg.category, checkedB2References: checked, safeCandidates: eligible, deleted, bytesEligible: bytes, missingB2, missingLegacy, provenanceMismatch, errors, samplePaths: examples });
    }
    return reply({ mode: execute ? "execute" : "dry-run", results, totalCandidates, totalDeleted, totalBytes, protected: ["all chat-media originals including View Once", "active stories", "unmatched or unverified storage objects", "all database and Auth records"] });
  } catch (e) {
    return reply({ error: e instanceof Error ? e.message : "Cleanup failed" }, 500);
  }
});