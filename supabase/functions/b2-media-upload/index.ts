import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { S3Client, PutObjectCommand, DeleteObjectCommand, GetBucketCorsCommand, PutBucketCorsCommand } from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const allowedOrigins = new Set(["https://match.beyondthebinarymedia.online"]);
const categories = new Set(["stories", "chat_media", "verification_selfies", "event_posters"]);
const maxBytes = 25 * 1024 * 1024;
const referenceTables: Record<string, { table: string; column: string }> = {
  stories: { table: "stories", column: "media_url" },
  chat_media: { table: "chat_media", column: "storage_path" },
  verification_selfies: { table: "verification_requests", column: "selfie_path" },
  event_posters: { table: "match_event_poster_assets", column: "storage_path" },
};

async function moderateStoryImageBytes(bytes: Uint8Array, contentType: string) {
 const apiKey=Deno.env.get("OPENAI_API_KEY"); if(!apiKey) throw new Error("Image moderation is not configured.");
 let binary=""; for(let i=0;i<bytes.length;i+=0x8000) binary+=String.fromCharCode(...bytes.subarray(i,Math.min(i+0x8000,bytes.length)));
 const moderation=await fetch("https://api.openai.com/v1/moderations",{method:"POST",headers:{"Authorization":"Bearer "+apiKey,"Content-Type":"application/json"},body:JSON.stringify({model:"omni-moderation-latest",input:[{type:"image_url",image_url:{url:"data:"+contentType+";base64,"+btoa(binary)}}]})});
 if(!moderation.ok) throw new Error("Moderation service unavailable."); const data=await moderation.json(),result=data?.results?.[0];if(!result)throw new Error("Moderation returned an invalid response.");
 if(result.categories?.["sexual/minors"]===true||Number(result.category_scores?.sexual??0)>=0.85)throw new Error("This image appears to contain explicit content that is not allowed.");
}

const allowedTypes = new Set([
  "image/jpeg", "image/png", "image/webp", "image/gif",
  "video/mp4", "video/webm", "video/quicktime",
]);

function response(body: unknown, status: number, origin: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-action, x-category, x-file-name",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") || "";
  if (origin && !allowedOrigins.has(origin)) return response({ error: "Origin not allowed" }, 403, origin);
  if (req.method === "OPTIONS") return new Response("ok", {
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-action, x-category, x-file-name",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405, origin);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const url = Deno.env.get("SUPABASE_URL") || "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") || "";
    const bucket = Deno.env.get("B2_BUCKET_NAME") || "";
    const endpoint = Deno.env.get("B2_S3_ENDPOINT") || "";
    const keyId = Deno.env.get("B2_KEY_ID") || "";
    const appKey = Deno.env.get("B2_APPLICATION_KEY") || "";
    if (!token || token === authHeader) return response({ error: "Authentication required" }, 401, origin);
    if (!url || !anon || !bucket || !endpoint || !keyId || !appKey) return response({ error: "B2 upload is not configured" }, 500, origin);

    const caller = createClient(url, anon, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: authError } = await caller.auth.getUser(token);
    if (authError || !userData.user) return response({ error: "Invalid session" }, 401, origin);

    const category = req.headers.get("x-category") || "";
    if (!categories.has(category)) return response({ error: "Unsupported media category" }, 400, origin);

    const endpointHost = new URL(endpoint).hostname;
    const region = Deno.env.get("B2_REGION") || endpointHost.match(/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/)?.[1];
    if (!region) return response({ error: "B2 region is not configured" }, 500, origin);
    const s3 = new S3Client({
      region,
      endpoint,
      forcePathStyle: true,
      credentials: { accessKeyId: keyId, secretAccessKey: appKey },
    });
    // Accept small browser uploads through this authenticated function so
    // Android browsers do not need to perform a cross-origin PUT to B2.
    const binaryAction = req.headers.get("x-action") || "create-upload-url";
    if (binaryAction === "upload-binary") {
      const contentType = (req.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
      if (!allowedTypes.has(contentType)) return response({ error: "Unsupported media type" }, 400, origin);
      const declaredSizeHeader = req.headers.get("content-length");
      const declaredSize = declaredSizeHeader === null ? null : Number(declaredSizeHeader);
      if (declaredSize !== null && (!Number.isFinite(declaredSize) || declaredSize < 1 || declaredSize > maxBytes)) {
        return response({ error: "Media must be between 1 byte and 25 MB." }, 400, origin);
      }
      const bytes = new Uint8Array(await req.arrayBuffer());
      if (!bytes.byteLength || bytes.byteLength > maxBytes || (declaredSize !== null && bytes.byteLength !== declaredSize)) {
        return response({ error: "Upload size is invalid." }, 400, origin);
      }
      const rawName = req.headers.get("x-file-name") || "media";
      const filename = rawName.split(/[\\/]/).pop()!.replace(/[^a-zA-Z0-9._-]/g, "_").slice(-100) || "media";
      if (category === "stories") { if (!contentType.startsWith("image/")) return response({ error: "Story videos cannot be uploaded until video moderation is supported." }, 400, origin); await moderateStoryImageBytes(bytes, contentType); }
      const objectKey = `users/${userData.user.id}/${category}/${crypto.randomUUID()}-${filename}`;
      await s3.send(new PutObjectCommand({
        Bucket: bucket,
        Key: objectKey,
        Body: bytes,
        ContentType: contentType,
      }));
      return response({ objectKey, storagePath: "b2://" + objectKey }, 200, origin);
    }


    // Read the active S3 CORS policy for diagnostics. Never expose credentials.
    try {
      const cors = await s3.send(new GetBucketCorsCommand({ Bucket: bucket }));
      console.info("B2 S3 CORS diagnostic:", JSON.stringify((cors.CORSRules || []).map((rule) => ({
        allowedOrigins: rule.AllowedOrigins || [],
        allowedMethods: rule.AllowedMethods || [],
        allowedHeaders: rule.AllowedHeaders || [],
        exposeHeaders: rule.ExposeHeaders || [],
      }))));
    } catch (corsError) {
      console.error("B2 S3 CORS diagnostic unavailable:", corsError instanceof Error ? corsError.message : "unknown error");
    }

    const action = req.headers.get("x-action") || "create-upload-url";
    // The simple Backblaze console rule did not update the S3-compatible CORS
    // policy. Repair only that S3 policy, and only when the signed-in caller
    // is a verified Match admin. Keep the bucket private and the origin narrow.
    if (action === "create-upload-url") {
      const { data: isAdmin } = await caller.rpc("is_match_admin");
      if (isAdmin === true) {
        const currentCors = await s3.send(new GetBucketCorsCommand({ Bucket: bucket }));
        const rules = currentCors.CORSRules || [];
        const hasPutForOrigin = rules.some((rule) =>
          (rule.AllowedOrigins || []).includes("https://match.beyondthebinarymedia.online") &&
          (rule.AllowedMethods || []).includes("PUT") &&
          (rule.AllowedHeaders || []).some((header) => header === "*" || header.toLowerCase() === "content-type")
        );
        if (!hasPutForOrigin) {
          await s3.send(new PutBucketCorsCommand({
            Bucket: bucket,
            CORSConfiguration: {
              CORSRules: [{
                AllowedOrigins: ["https://match.beyondthebinarymedia.online"],
                AllowedMethods: ["GET", "HEAD", "PUT"],
                AllowedHeaders: ["*"],
                ExposeHeaders: ["ETag"],
                MaxAgeSeconds: 3600,
              }],
            },
          }));
          console.info("B2 S3 CORS policy repaired for The Match origin.");
        }
      }
    }
    if (action === "delete-upload") {
      const body = await req.json().catch(() => null);
      const objectKey = typeof body?.objectKey === "string" ? body.objectKey : "";
      if (!objectKey.startsWith(`users/${userData.user.id}/${category}/`) ||
          objectKey.includes("..") || objectKey.includes("\\\\") || objectKey.length > 500) {
        return response({ error: "Invalid upload object key" }, 403, origin);
      }
      // Do not allow cleanup to delete an object while any database row
      // still references it. This prevents a member from breaking a live asset.
      const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
      if (!serviceKey) return response({ error: "Safe cleanup is not configured" }, 500, origin);
      const service = createClient(url, serviceKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      const reference = referenceTables[category];
      const { count, error: referenceError } = await service
        .from(reference.table)
        .select(reference.column, { count: "exact", head: true })
        .eq(reference.column, `b2://${objectKey}`);
      if (referenceError) return response({ error: "Could not verify whether this upload is still in use" }, 500, origin);
      if ((count || 0) > 0) return response({ error: "This media is still attached to an active record" }, 409, origin);
      await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: objectKey }));
      return response({ deleted: true }, 200, origin);
    }
    if (action !== "create-upload-url") return response({ error: "Unsupported action" }, 400, origin);
    if (category === "stories") return response({ error: "Stories must use the inspected binary upload route." }, 400, origin);

    const body = await req.json().catch(() => null);
    const contentType = typeof body?.contentType === "string" ? body.contentType.toLowerCase() : "";
    if (!allowedTypes.has(contentType)) return response({ error: "Unsupported media type" }, 400, origin);
    const size = Number(body?.size);
    if (!Number.isFinite(size) || size < 1 || size > maxBytes) {
      return response({ error: "Media must be between 1 byte and 25 MB." }, 400, origin);
    }
    const rawName = typeof body?.fileName === "string" ? body.fileName : "media";
    const filename = rawName.split(/[\\\\/]/).pop()!.replace(/[^a-zA-Z0-9._-]/g, "_").slice(-100) || "media";
    const objectKey = `users/${userData.user.id}/${category}/${crypto.randomUUID()}-${filename}`;
    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: objectKey,
      ContentType: contentType,
    });
    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });
    return response({
      uploadUrl,
      objectKey,
      method: "PUT",
      expiresIn: 300,
      requiredHeaders: { "Content-Type": contentType },
    }, 200, origin);
  } catch (error) {
    console.error("B2 media upload failed:", error instanceof Error ? error.message : "unknown error");
    return response({ error: "Unable to upload media to B2" }, 500, origin);
  }
});
