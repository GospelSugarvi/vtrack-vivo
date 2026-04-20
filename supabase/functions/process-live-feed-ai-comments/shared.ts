export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export type AiSettingsRow = {
  enabled: boolean;
  model_name: string;
  system_prompt: string;
  config_json: Record<string, unknown> | null;
};

export type JobRow = {
  id: string;
  sale_id: string;
  attempt_count: number | null;
};

export type ReplyJobRow = {
  id: string;
  sale_id: string;
  source_comment_id: string;
  attempt_count: number | null;
  persona_user_id: string | null;
};

export type CommentGenerationParams = {
  modelName: string;
  systemPrompt: string;
  saleContext: Record<string, unknown>;
  maxChars: number;
  minChars: number;
  temperature: number;
};

export function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function randomIntBetween(min: number, max: number) {
  if (max <= min) return min;
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

export function resolveHumanDelayMs(baseDelaySeconds: number, mode: "comment" | "reply") {
  const safeBase = Math.max(0, Math.round(baseDelaySeconds));
  if (safeBase <= 0) return 0;

  const minDelay = safeBase;
  const maxDelay = mode === "reply"
    ? safeBase + 2
    : safeBase + 3;

  return randomIntBetween(minDelay, maxDelay) * 1000;
}

export function safeString(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

export function preferredDisplayName(
  row: Record<string, unknown> | null | undefined,
  fallback = "User",
) {
  const nickname = safeString(row?.["nickname"]);
  const fullName = safeString(row?.["full_name"]);
  return nickname || fullName || fallback;
}

export function toFiniteNumber(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function remainingValue(target: unknown, actual: unknown) {
  return Math.max(toFiniteNumber(target) - toFiniteNumber(actual), 0);
}

export function formatRupiahShort(value: unknown) {
  const amount = toFiniteNumber(value);
  if (amount >= 1000000000) {
    return `Rp ${(amount / 1000000000).toFixed(1).replace(/\.0$/, "")} miliar`;
  }
  if (amount >= 1000000) {
    return `Rp ${(amount / 1000000).toFixed(1).replace(/\.0$/, "")} juta`;
  }
  if (amount >= 1000) {
    return `Rp ${(amount / 1000).toFixed(1).replace(/\.0$/, "")} ribu`;
  }
  return `Rp ${Math.round(amount)}`;
}

export function formatUnitCount(value: unknown) {
  const amount = Math.round(toFiniteNumber(value));
  return `${amount} unit`;
}

export function composePersonaSystemPrompt(
  basePrompt: string,
  personaProfile: {
    displayName: string;
    title: string;
    identitySummary: string;
    backgroundStory: string;
    relationshipToTeam: string;
    speakingStyle: string;
    toneExamples: string;
    dontSay: string;
  },
) {
  const profileLines = [
    safeString(personaProfile.displayName)
      ? `Nama persona: ${safeString(personaProfile.displayName)}.`
      : "",
    safeString(personaProfile.relationshipToTeam)
      ? `Relasi dengan tim: ${safeString(personaProfile.relationshipToTeam)}.`
      : "",
    safeString(personaProfile.speakingStyle)
      ? `Gaya bicara: ${safeString(personaProfile.speakingStyle)}.`
      : "",
    "Tulis natural seperti rekan satu tim, bukan template mesin.",
  ].filter(Boolean);

  return [basePrompt.trim(), profileLines.join("\n")].filter(Boolean).join("\n\n").trim();
}

export function clampNumber(value: unknown, fallback: number, min: number, max: number) {
  const parsed = Number(value);
  if (Number.isNaN(parsed)) return fallback;
  return Math.min(Math.max(parsed, min), max);
}
