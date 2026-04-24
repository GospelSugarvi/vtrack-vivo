import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import {
  type AiSettingsRow,
  clampNumber,
  composePersonaSystemPrompt,
  corsHeaders,
  type JobRow,
  type ReplyJobRow,
  jsonResponse,
  resolveHumanDelayMs,
  safeString,
  sleep,
} from "./shared.ts";
import { buildSaleContext } from "./sale_context.ts";
import { generateCommentWithFallbacks } from "./ai_generation.ts";

function buildFallbackSalesComment(saleContext: Record<string, unknown>) {
  const promotorName = safeString(saleContext["promotor_name"]) || "tim";
  const productName = safeString(saleContext["product_name"]);
  if (productName) {
    return `${promotorName}, ${productName} sudah terjual. Lanjut cari closing berikutnya ya.`;
  }
  return `${promotorName}, jualannya sudah masuk. Lanjut closing berikutnya ya.`;
}

function buildFallbackReplyComment(replyContext: Record<string, unknown>) {
  const actorName = safeString(replyContext["actor_name"]) || "Kak";
  const productName = safeString(replyContext["product_name"]);
  if (productName) {
    return `${actorName}, noted. Semoga closing ${productName} berikutnya makin lancar ya.`;
  }
  return `${actorName}, noted. Semoga closing berikutnya makin lancar ya.`;
}

async function fetchLatestSalesCommentSettings(
  supabaseAdmin: ReturnType<typeof createClient>,
) {
  const { data, error } = await supabaseAdmin
    .from("ai_feature_settings")
    .select("enabled, config_json")
    .eq("feature_key", "live_feed_sales_comment")
    .maybeSingle();

  if (error) {
    throw error;
  }

  return {
    enabled: data?.enabled === true,
    enableReplyThreads:
      ((data?.config_json ?? {})["enable_reply_threads"] ?? true) !== false,
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY") ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Supabase env is missing.");
    }
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const body = await req.json().catch(() => ({}));
    const batchSize = clampNumber(body.batch_size, 5, 1, 20);

    const { data: settingsRow, error: settingsError } = await supabaseAdmin
      .from("ai_feature_settings")
      .select("enabled, model_name, system_prompt, config_json")
      .eq("feature_key", "live_feed_sales_comment")
      .maybeSingle();

    if (settingsError) {
      throw settingsError;
    }

    const settings = settingsRow as AiSettingsRow | null;
    if (settings == null || settings.enabled !== true) {
      return jsonResponse({
        success: true,
        processed: 0,
        skipped: 0,
        message: "AI Sales Comment disabled.",
      });
    }

    const config = settings.config_json ?? {};
    const systemPersonaId = safeString(config["system_persona_id"]);
    let personaUserId = safeString(config["persona_user_id"]);
    let personaDisplayName = "";
    let personaMetadata: Record<string, unknown> = {};

    if (systemPersonaId) {
      const { data: personaRow, error: personaError } = await supabaseAdmin
        .from("system_personas")
        .select("linked_user_id, is_active, display_name, persona_code, metadata_json")
        .eq("id", systemPersonaId)
        .maybeSingle();

      if (personaError) {
        throw personaError;
      }
      if (personaRow?.is_active !== true) {
        return jsonResponse({
          success: true,
          processed: 0,
          skipped: 0,
          message: "Configured system persona is inactive.",
        });
      }
      personaUserId = safeString(personaRow?.linked_user_id);
      personaDisplayName = safeString(personaRow?.display_name);
      personaMetadata = (personaRow?.metadata_json ?? {}) as Record<string, unknown>;
    }

    if (!personaUserId) {
      return jsonResponse({
        success: true,
        processed: 0,
        skipped: 0,
        message: "Persona user is not configured.",
      });
    }

    const { data: personaUserRow, error: personaUserError } = await supabaseAdmin
      .from("users")
      .select("full_name")
      .eq("id", personaUserId)
      .maybeSingle();

    if (personaUserError) {
      throw personaUserError;
    }

    const personaUserFullName = safeString(personaUserRow?.full_name);
    const personaTitle = safeString(personaMetadata["persona_title"]);
    const personaIdentitySummary = safeString(personaMetadata["identity_summary"]);
    const personaBackgroundStory = safeString(personaMetadata["background_story"]);
    const personaRelationshipToTeam = safeString(personaMetadata["relationship_to_team"]);
    const personaSpeakingStyle = safeString(personaMetadata["speaking_style"]);
    const personaToneExamples = safeString(personaMetadata["tone_examples"]);
    const personaDontSay = safeString(personaMetadata["dont_say"]);

    const delaySeconds = clampNumber(config["delay_seconds"], 25, 0, 300);
    const minChars = clampNumber(config["min_output_chars"], 28, 16, 120);
    const maxChars = clampNumber(config["max_output_chars"], 160, 60, 280);
    const temperature = clampNumber(config["temperature"], 0.9, 0, 1.2);
    const modelName = safeString(settings.model_name) || "gemini-2.5-flash";
    const systemPrompt = composePersonaSystemPrompt(
      safeString(settings.system_prompt),
      {
        displayName: personaDisplayName || personaUserFullName,
        title: personaTitle,
        identitySummary: personaIdentitySummary,
        backgroundStory: personaBackgroundStory,
        relationshipToTeam: personaRelationshipToTeam,
        speakingStyle: personaSpeakingStyle,
        toneExamples: personaToneExamples,
        dontSay: personaDontSay,
      },
    );

    const { data: jobs, error: jobsError } = await supabaseAdmin
      .from("ai_sales_comment_jobs")
      .select("id, sale_id, attempt_count")
      .eq("status", "pending")
      .order("created_at")
      .limit(batchSize);

    if (jobsError) {
      throw jobsError;
    }

    const pendingJobs = (jobs ?? []) as JobRow[];
    const { data: replyJobs, error: replyJobsError } = await supabaseAdmin
      .from("ai_feed_comment_reply_jobs")
      .select("id, sale_id, source_comment_id, attempt_count, persona_user_id")
      .eq("status", "pending")
      .order("created_at")
      .limit(batchSize);

    if (replyJobsError) {
      throw replyJobsError;
    }

    const pendingReplyJobs = (replyJobs ?? []) as ReplyJobRow[];
    let processed = 0;
    let skipped = 0;
    const errors: Array<Record<string, string>> = [];

    for (const job of pendingJobs) {
      const { error: lockError } = await supabaseAdmin
        .from("ai_sales_comment_jobs")
        .update({
          status: "processing",
          attempt_count: (job.attempt_count ?? 0) + 1,
        })
        .eq("id", job.id)
        .eq("status", "pending");

      if (lockError) {
        errors.push({ job_id: job.id, error: lockError.message });
        continue;
      }

      try {
        const { data: saleRow, error: saleError } = await supabaseAdmin
          .from("sales_sell_out")
          .select(`
            id,
            promotor_id,
            store_id,
            variant_id,
            price_at_transaction,
            payment_method,
            leasing_provider,
            customer_type,
            notes,
            transaction_date,
            created_at
          `)
          .eq("id", job.sale_id)
          .maybeSingle();

        if (saleError || !saleRow) {
          throw new Error(saleError?.message ?? "Sale data not found.");
        }

        const existing = await supabaseAdmin
          .from("feed_comments")
          .select("id")
          .eq("sale_id", job.sale_id)
          .eq("user_id", personaUserId)
          .is("deleted_at", null)
          .limit(1)
          .maybeSingle();

        if (existing.data?.id) {
          await supabaseAdmin
            .from("ai_sales_comment_jobs")
            .update({
              status: "skipped",
              persona_user_id: personaUserId,
              processed_at: new Date().toISOString(),
              last_error: "Persona comment already exists for this sale.",
            })
            .eq("id", job.id);
          skipped += 1;
          continue;
        }

        const { saleContext } = await buildSaleContext(supabaseAdmin, saleRow as Record<string, unknown>);

        const commentDelayMs = resolveHumanDelayMs(delaySeconds, "comment");
        if (commentDelayMs > 0) {
          await sleep(commentDelayMs);
        }

        const latestSettings = await fetchLatestSalesCommentSettings(
          supabaseAdmin,
        );
        if (!latestSettings.enabled) {
          await supabaseAdmin
            .from("ai_sales_comment_jobs")
            .update({
              status: "skipped",
              persona_user_id: personaUserId,
              processed_at: new Date().toISOString(),
              last_error: "AI Sales Comment disabled before comment insert.",
            })
            .eq("id", job.id);
          skipped += 1;
          continue;
        }

        let generatedComment = "";
        try {
          if (!geminiApiKey) {
            throw new Error("Gemini API key is missing.");
          }
          generatedComment = await generateCommentWithFallbacks({
            geminiApiKey,
            modelName,
            systemPrompt,
            saleContext,
            minChars,
            maxChars,
            temperature,
          });
        } catch (_) {
          generatedComment = buildFallbackSalesComment(saleContext);
        }

        const { data: insertedComment, error: insertError } = await supabaseAdmin
          .from("feed_comments")
          .insert({
            sale_id: job.sale_id,
            user_id: personaUserId,
            comment_text: generatedComment,
          })
          .select("id")
          .single();

        if (insertError) {
          throw insertError;
        }

        await supabaseAdmin
          .from("ai_sales_comment_jobs")
          .update({
            status: "completed",
            persona_user_id: personaUserId,
            prompt_snapshot: systemPrompt,
            input_context_json: saleContext,
            generated_comment: generatedComment,
            feed_comment_id: insertedComment.id,
            processed_at: new Date().toISOString(),
            last_error: null,
          })
          .eq("id", job.id);

        processed += 1;
      } catch (error) {
        await supabaseAdmin
          .from("ai_sales_comment_jobs")
          .update({
            status: "failed",
            persona_user_id: personaUserId,
            processed_at: new Date().toISOString(),
            last_error: error instanceof Error ? error.message : String(error),
          })
          .eq("id", job.id);

        errors.push({
          job_id: job.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    for (const job of pendingReplyJobs) {
      const { error: lockError } = await supabaseAdmin
        .from("ai_feed_comment_reply_jobs")
        .update({
          status: "processing",
          attempt_count: (job.attempt_count ?? 0) + 1,
        })
        .eq("id", job.id)
        .eq("status", "pending");

      if (lockError) {
        errors.push({ job_id: job.id, error: lockError.message });
        continue;
      }

      try {
        const personaId = safeString(job.persona_user_id) || personaUserId;
        if (!personaId) {
          throw new Error("Persona user is not configured.");
        }

        const existingReply = await supabaseAdmin
          .from("feed_comments")
          .select("id")
          .eq("sale_id", job.sale_id)
          .eq("parent_comment_id", job.source_comment_id)
          .eq("user_id", personaId)
          .is("deleted_at", null)
          .limit(1)
          .maybeSingle();

        if (existingReply.data?.id) {
          await supabaseAdmin
            .from("ai_feed_comment_reply_jobs")
            .update({
              status: "completed",
              reply_comment_id: existingReply.data.id,
              persona_user_id: personaId,
              processed_at: new Date().toISOString(),
              last_error: null,
            })
            .eq("id", job.id);
          skipped += 1;
          continue;
        }

        const { data: sourceComment, error: sourceCommentError } = await supabaseAdmin
          .from("feed_comments")
          .select(`
            id,
            sale_id,
            comment_text,
            created_at,
            user_id
          `)
          .eq("id", job.source_comment_id)
          .maybeSingle();

        if (sourceCommentError || !sourceComment) {
          throw new Error(sourceCommentError?.message ?? "Source comment not found.");
        }

        const actorId = safeString(sourceComment["user_id"]);
        let actorUser: Record<string, unknown> = {};
        if (actorId) {
          const { data: actorRow } = await supabaseAdmin
            .from("users")
            .select("full_name, nickname")
            .eq("id", actorId)
            .maybeSingle();
          actorUser = (actorRow ?? {}) as Record<string, unknown>;
        }

        let sale: Record<string, unknown> = {};
        const saleId = safeString(sourceComment["sale_id"]) || job.sale_id;
        if (saleId) {
          const { data: saleRow } = await supabaseAdmin
            .from("sales_sell_out")
            .select(`
              id,
              price_at_transaction,
              transaction_date,
              stores(store_name),
              product_variants(ram_rom, products(model_name))
            `)
            .eq("id", saleId)
            .maybeSingle();
          sale = (saleRow ?? {}) as Record<string, unknown>;
        }

        const store = (sale["stores"] ?? {}) as Record<string, unknown>;
        const variant = (sale["product_variants"] ?? {}) as Record<string, unknown>;
        const product = (variant["products"] ?? {}) as Record<string, unknown>;
        const replyContext = {
          actor_name: safeString(actorUser["nickname"]) || safeString(actorUser["full_name"]),
          comment_text: safeString(sourceComment["comment_text"]),
          store_name: safeString(store["store_name"]),
          product_name: [
            safeString(product["model_name"]),
            safeString(variant["ram_rom"]),
          ].filter(Boolean).join(" "),
          transaction_date: sourceComment["created_at"],
        };

        const replyDelayMs = resolveHumanDelayMs(delaySeconds, "reply");
        if (replyDelayMs > 0) {
          await sleep(replyDelayMs);
        }

        const latestSettings = await fetchLatestSalesCommentSettings(
          supabaseAdmin,
        );
        if (!latestSettings.enabled || !latestSettings.enableReplyThreads) {
          await supabaseAdmin
            .from("ai_feed_comment_reply_jobs")
            .update({
              status: "skipped",
              persona_user_id: personaId,
              processed_at: new Date().toISOString(),
              last_error: !latestSettings.enabled
                ? "AI Sales Comment disabled before reply insert."
                : "Reply threads disabled before reply insert.",
            })
            .eq("id", job.id);
          skipped += 1;
          continue;
        }

        let generatedReply = "";
        try {
          if (!geminiApiKey) {
            throw new Error("Gemini API key is missing.");
          }
          generatedReply = await generateCommentWithFallbacks({
            geminiApiKey,
            modelName,
            systemPrompt: `${systemPrompt}\n\nKonteks baru: ini adalah balasan persona di thread komentar live feed. Balasan harus terasa menanggapi komentar user secara natural.`,
            saleContext: replyContext,
            minChars: Math.max(12, minChars - 4),
            maxChars: Math.max(40, maxChars - 20),
            temperature,
          });
        } catch (_) {
          generatedReply = buildFallbackReplyComment(replyContext);
        }

        const { data: insertedReply, error: insertReplyError } = await supabaseAdmin
          .from("feed_comments")
          .insert({
            sale_id: job.sale_id,
            user_id: personaId,
            parent_comment_id: job.source_comment_id,
            comment_text: generatedReply,
            metadata_json: { source: "ai_reply" },
          })
          .select("id")
          .single();

        if (insertReplyError) {
          throw insertReplyError;
        }

        await supabaseAdmin
          .from("ai_feed_comment_reply_jobs")
          .update({
            status: "completed",
            persona_user_id: personaId,
            generated_comment: generatedReply,
            reply_comment_id: insertedReply.id,
            processed_at: new Date().toISOString(),
            last_error: null,
          })
          .eq("id", job.id);

        processed += 1;
      } catch (error) {
        await supabaseAdmin
          .from("ai_feed_comment_reply_jobs")
          .update({
            status: "failed",
            processed_at: new Date().toISOString(),
            last_error: error instanceof Error ? error.message : String(error),
          })
          .eq("id", job.id);

        errors.push({
          job_id: job.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    if (pendingJobs.length == 0 && pendingReplyJobs.length == 0) {
      return jsonResponse({
        success: true,
        processed: 0,
        skipped: 0,
        message: "No pending jobs.",
      });
    }

    return jsonResponse({
      success: true,
      processed,
      skipped,
      errors,
    });
  } catch (error) {
    return jsonResponse(
      {
        success: false,
        message: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});
