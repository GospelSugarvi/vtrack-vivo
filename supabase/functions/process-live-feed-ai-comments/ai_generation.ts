import {
  type CommentGenerationParams,
  sleep,
  safeString,
} from "./shared.ts";

function isWeakComment(comment: string) {
  const normalized = safeString(comment).replace(/\s+/g, " ");
  if (!normalized) return true;
  if (normalized.length < 6) return true;

  const lowered = normalized.toLowerCase();
  const weakExactPhrases = [
    "mantap",
    "top",
    "keren",
    "gas",
    "lanjut",
    "sip",
    "nice",
    "good",
    "mantap jiwa",
  ];

  if (weakExactPhrases.includes(lowered)) {
    return true;
  }

  const awkwardPatterns = [
    /\bhari hari\b/i,
    /\bkamu punya semangat\b/i,
    /\bsalam dari pusat\b/i,
    /\bjaga ritme\b/i,
    /\bnext deal\b/i,
    /\bnoted ya\b/i,
    /\b(\w+)\s+\1\b/i,
  ];

  if (awkwardPatterns.some((pattern) => pattern.test(normalized))) {
    return true;
  }

  return false;
}

async function generateCommentWithGemini(params: {
  apiKey: string;
  modelName: string;
  systemPrompt: string;
  saleContext: Record<string, unknown>;
  maxChars: number;
  minChars: number;
  temperature: number;
}) {
  async function callGemini(prompt: string) {
    let lastError: Error | null = null;

    for (let requestAttempt = 1; requestAttempt <= 2; requestAttempt += 1) {
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${params.modelName}:generateContent?key=${params.apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            system_instruction: {
              parts: [{ text: params.systemPrompt }],
            },
            contents: [
              {
                role: "user",
                parts: [{ text: prompt }],
              },
            ],
            generationConfig: {
              temperature: params.temperature,
              maxOutputTokens: 120,
            },
          }),
        },
      );

      const rawText = await response.text();
      if (response.ok) {
        return rawText;
      }

      const retryable = response.status === 429 || response.status >= 500;
      lastError = new Error(`Gemini error: ${rawText}`);

      if (!retryable || requestAttempt === 2) {
        throw lastError;
      }

      await sleep(requestAttempt * 800);
    }

    throw lastError ?? new Error("Gemini request failed.");
  }

  const primaryPrompt = `
Konteks penjualan:
${JSON.stringify(params.saleContext, null, 2)}

Tulis satu komentar singkat untuk live feed penjualan berdasarkan konteks di atas.
Batas maksimal ${params.maxChars} karakter.
Gunakan konteks yang memang relevan dari data di atas.
Komentar harus terasa natural seperti rekan tim, bukan template.
Komentar harus jelas maksudnya saat dibaca user biasa, bukan frasa abstrak.
Hindari kalimat seperti "jaga ritme", "next deal", "tetap semangat tim", atau frasa yang terdengar menggantung.
Kalau menyebut angka rupiah atau unit, pakai field yang berakhiran _formatted. Jangan mengubah angka mentah sendiri.
Jangan keluarkan daftar, label, atau penjelasan tambahan.
`;

  const prompts = [
    primaryPrompt,
    `
Konteks penjualan:
${JSON.stringify(params.saleContext, null, 2)}

Tulis ulang satu komentar live feed yang lebih natural dan lebih santai.
Batas maksimal ${params.maxChars} karakter.
Pastikan kalimatnya jelas, konkret, dan enak dibaca.
Jangan terlalu formal. Jangan keluarkan label atau penjelasan tambahan.
`,
  ];

  for (const prompt of prompts) {
    const rawText = await callGemini(prompt);
    const parsed = rawText ? JSON.parse(rawText) : {};
    const text = parsed?.candidates?.[0]?.content?.parts?.[0]?.text;
    const cleaned = safeString(text).replace(/^["'\s]+|["'\s]+$/g, "");
    if (!cleaned) continue;

    const bounded = cleaned.length > params.maxChars
      ? cleaned.slice(0, params.maxChars).trim()
      : cleaned;

    if (!isWeakComment(bounded)) {
      return bounded;
    }
  }

  throw new Error("Gemini returned unusable comment.");
}

export async function generateCommentWithFallbacks(
  params: CommentGenerationParams & { geminiApiKey: string },
) {
  if (!params.geminiApiKey) {
    throw new Error("Gemini API key is required for live feed comments.");
  }

  return await generateCommentWithGemini({
    apiKey: params.geminiApiKey,
    modelName: params.modelName,
    systemPrompt: params.systemPrompt,
    saleContext: params.saleContext,
    minChars: params.minChars,
    maxChars: params.maxChars,
    temperature: params.temperature,
  });
}
