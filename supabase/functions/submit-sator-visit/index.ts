import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type VisitPhotoPayload = {
  file_name?: string;
  content_type?: string;
  base64_data?: string;
};

const MAX_PHOTO_COUNT = 2;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const MAX_PHOTO_MB = 5;
const CLOUDINARY_CLOUD_NAME = "dkkbwu8hj";
const CLOUDINARY_UPLOAD_PRESET = "vtrack_uploads";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse(
        { success: false, message: "Missing authorization header." },
        401,
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      throw new Error("Supabase env is missing.");
    }

    const token = authHeader.replace("Bearer ", "").trim();
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const supabaseUser = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse(
        { success: false, message: "Unauthorized." },
        401,
      );
    }

    const { data: profile, error: profileError } = await supabaseAdmin
      .from("users")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profileError || !["sator", "spv"].includes(`${profile?.role ?? ""}`)) {
      return jsonResponse(
        { success: false, message: "Hanya sator atau spv yang dapat submit visit." },
        403,
      );
    }

    const body = await req.json().catch(() => ({}));
    const storeId = `${body.store_id ?? ""}`.trim();
    const targetSatorId = `${body.target_sator_id ?? ""}`.trim();
    const notes = `${body.notes ?? ""}`.trim();
    const visitAt = `${body.visit_at ?? new Date().toISOString()}`.trim();
    const photos = Array.isArray(body.photos)
      ? (body.photos as VisitPhotoPayload[])
      : [];

    if (!storeId) {
      return jsonResponse(
        { success: false, message: "store_id wajib diisi." },
        400,
      );
    }

    if (photos.length === 0) {
      return jsonResponse(
        { success: false, message: "Minimal 1 foto visit diperlukan." },
        400,
      );
    }
    if (photos.length > MAX_PHOTO_COUNT) {
      return jsonResponse(
        {
          success: false,
          message: `Maksimal ${MAX_PHOTO_COUNT} foto visit per submit.`,
        },
        400,
      );
    }

    const uploadedUrls: string[] = [];
    for (let index = 0; index < photos.length; index += 1) {
      const photo = photos[index] ?? {};
      const base64Data = `${photo.base64_data ?? ""}`.trim();
      if (!base64Data) {
        return jsonResponse(
          { success: false, message: `Foto ke-${index + 1} tidak valid.` },
          400,
        );
      }

      const fileName = `${photo.file_name ?? `${Date.now()}_${index}.jpg`}`.trim();
      const contentType = `${photo.content_type ?? "image/jpeg"}`.trim() ||
        "image/jpeg";
      const normalizedBase64 = base64Data.replace(/^data:[^;]+;base64,/, "");
      const bytes = Uint8Array.from(atob(normalizedBase64), (char) =>
        char.charCodeAt(0)
      );
      if (bytes.byteLength > MAX_PHOTO_BYTES) {
        return jsonResponse(
          {
            success: false,
            message:
              `Ukuran foto ke-${index + 1} melebihi batas ${MAX_PHOTO_MB} MB.`,
          },
          400,
        );
      }
      const formData = new FormData();
      formData.append(
        "file",
        new Blob([bytes], { type: contentType }),
        fileName,
      );
      formData.append("upload_preset", CLOUDINARY_UPLOAD_PRESET);
      formData.append("folder", `vtrack/visits/${user.id}/${storeId}`);

      const uploadResponse = await fetch(
        `https://api.cloudinary.com/v1_1/${CLOUDINARY_CLOUD_NAME}/image/upload`,
        {
          method: "POST",
          body: formData,
        },
      );
      const uploadPayload = await uploadResponse.json().catch(() => ({}));
      if (!uploadResponse.ok) {
        const cloudinaryMessage =
          `${uploadPayload?.error?.message ?? uploadPayload?.message ?? "Cloudinary upload gagal."}`;
        throw new Error(cloudinaryMessage);
      }
      const secureUrl = `${uploadPayload?.secure_url ?? ""}`.trim();
      if (secureUrl.isEmpty) {
        throw new Error("Cloudinary tidak mengembalikan URL foto.");
      }
      uploadedUrls.push(secureUrl);
    }

    const { data: submitResult, error: submitError } = await supabaseUser.rpc(
      "submit_scoped_visit",
      {
        p_store_id: storeId,
        p_photo_urls: uploadedUrls,
        p_notes: notes || null,
        p_visit_at: visitAt,
        p_target_sator_id: targetSatorId || null,
      },
    );

    if (submitError) {
      throw new Error(submitError.message);
    }

    return jsonResponse({
      success: true,
      photo_urls: uploadedUrls,
      result: submitResult,
    });
  } catch (error) {
    return jsonResponse(
      {
        success: false,
        message: error instanceof Error ? error.message : "Unknown error",
      },
      400,
    );
  }
});
