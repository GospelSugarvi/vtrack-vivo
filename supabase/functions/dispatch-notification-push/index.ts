import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9.15.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type NotificationRow = {
  id: string;
  recipient_user_id: string;
  title: string;
  body: string;
  category: string | null;
  type: string | null;
  action_route: string | null;
  action_params: Record<string, unknown> | null;
  payload: Record<string, unknown> | null;
};

type DeviceTokenRow = {
  id: string;
  user_id: string;
  fcm_token: string;
  platform: string | null;
  is_active: boolean | null;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function getAccessToken() {
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? "";
  const privateKey = (Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "").replaceAll(
    "\\n",
    "\n",
  );

  if (!clientEmail || !privateKey) {
    throw new Error("Firebase service account env is missing");
  }

  const jwtClient = new JWT({
    email: clientEmail,
    key: privateKey,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });

  const { access_token } = await jwtClient.authorize();
  if (!access_token) {
    throw new Error("Failed to get Firebase access token");
  }

  return access_token;
}

async function sendFcmMessage(
  accessToken: string,
  notification: NotificationRow,
  deviceToken: string,
) {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
  if (!projectId) {
    throw new Error("FIREBASE_PROJECT_ID is missing");
  }

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          notification: {
            title: notification.title,
            body: notification.body,
          },
          data: {
            notification_id: notification.id,
            category: notification.category ?? "system",
            type: notification.type ?? "system",
            action_route: notification.action_route ?? "",
            action_params: JSON.stringify(notification.action_params ?? {}),
            payload: JSON.stringify(notification.payload ?? {}),
          },
          android: {
            priority: "high",
            notification: {
              channel_id: "vtrack_general",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        },
      }),
    },
  );

  const responseText = await response.text();
  let responseJson: Record<string, unknown> = {};

  try {
    responseJson = responseText ? JSON.parse(responseText) : {};
  } catch (_) {
    responseJson = { raw: responseText };
  }

  if (!response.ok) {
    throw new Error(JSON.stringify(responseJson));
  }

  return responseJson;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Supabase env is missing");
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const requestBody = await req.json().catch(() => ({}));
    const notificationId = `${requestBody.notification_id ?? ""}`.trim();
    const batchSize = Math.min(
      Math.max(Number(requestBody.batch_size ?? 20), 1),
      100,
    );

    let notificationQuery = supabaseAdmin
      .from("app_notifications")
      .select(
        "id, recipient_user_id, title, body, category, type, action_route, action_params, payload",
      )
      .is("archived_at", null)
      .is("sent_push_at", null)
      .eq("status", "unread")
      .order("created_at", { ascending: true })
      .limit(batchSize);

    if (notificationId) {
      notificationQuery = supabaseAdmin
        .from("app_notifications")
        .select(
          "id, recipient_user_id, title, body, category, type, action_route, action_params, payload",
        )
        .eq("id", notificationId)
        .limit(1);
    }

    const { data: notifications, error: notificationError } =
      await notificationQuery;

    if (notificationError) {
      throw new Error(notificationError.message);
    }

    const rows = (notifications ?? []) as NotificationRow[];
    if (rows.length === 0) {
      return jsonResponse({
        success: true,
        dispatched: 0,
        message: "No eligible notifications found",
      });
    }

    const accessToken = await getAccessToken();
    const results: Array<Record<string, unknown>> = [];

    for (const notification of rows) {
      const { data: preferenceRows } = await supabaseAdmin
        .from("notification_preferences")
        .select("push_enabled")
        .eq("user_id", notification.recipient_user_id)
        .limit(1);

      const pushEnabled =
        preferenceRows == null ||
        preferenceRows.length === 0 ||
        preferenceRows[0]["push_enabled"] !== false;

      if (!pushEnabled) {
        await supabaseAdmin
          .from("app_notifications")
          .update({
            push_status: "skipped_disabled",
            sent_push_at: new Date().toISOString(),
          })
          .eq("id", notification.id);

        results.push({
          notification_id: notification.id,
          status: "skipped_disabled",
        });
        continue;
      }

      const { data: tokens, error: tokenError } = await supabaseAdmin
        .from("user_device_tokens")
        .select("id, user_id, fcm_token, platform, is_active")
        .eq("user_id", notification.recipient_user_id)
        .eq("is_active", true);

      if (tokenError) {
        throw new Error(tokenError.message);
      }

      const deviceTokens = (tokens ?? []) as DeviceTokenRow[];
      if (deviceTokens.length == 0) {
        await supabaseAdmin
          .from("app_notifications")
          .update({
            push_status: "skipped_no_device",
            sent_push_at: new Date().toISOString(),
          })
          .eq("id", notification.id);

        results.push({
          notification_id: notification.id,
          status: "skipped_no_device",
        });
        continue;
      }

      let sentCount = 0;

      for (const device of deviceTokens) {
        try {
          const providerResponse = await sendFcmMessage(
            accessToken,
            notification,
            device.fcm_token,
          );

          await supabaseAdmin.from("notification_deliveries").insert({
            notification_id: notification.id,
            device_token_id: device.id,
            channel: "fcm",
            provider: "firebase",
            status: "sent",
            provider_message_id: `${providerResponse["name"] ?? ""}`,
            provider_response: providerResponse,
            attempted_at: new Date().toISOString(),
            delivered_at: new Date().toISOString(),
          });

          sentCount += 1;
        } catch (error) {
          const message = error instanceof Error ? error.message : `${error}`;
          await supabaseAdmin.from("notification_deliveries").insert({
            notification_id: notification.id,
            device_token_id: device.id,
            channel: "fcm",
            provider: "firebase",
            status: "failed",
            provider_response: {},
            error_message: message,
            attempted_at: new Date().toISOString(),
          });
        }
      }

      await supabaseAdmin
        .from("app_notifications")
        .update({
          push_status: sentCount > 0 ? "sent" : "failed",
          sent_push_at: new Date().toISOString(),
        })
        .eq("id", notification.id);

      results.push({
        notification_id: notification.id,
        status: sentCount > 0 ? "sent" : "failed",
        delivered_devices: sentCount,
      });
    }

    return jsonResponse({
      success: true,
      dispatched: results.length,
      results,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : `${error}`;
    return jsonResponse({ success: false, error: message }, 400);
  }
});
