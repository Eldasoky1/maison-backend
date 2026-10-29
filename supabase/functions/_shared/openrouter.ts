// OpenRouter client shared by the Edge Functions.
// The key is a Supabase secret and never reaches the browser.

export const OPENROUTER_URL =
  Deno.env.get("OPENROUTER_BASE_URL") ?? "https://openrouter.ai/api/v1";

export const MODELS = {
  chat: Deno.env.get("CHAT_MODEL") ?? "anthropic/claude-sonnet-4.5",
  extraction: Deno.env.get("EXTRACTION_MODEL") ?? "anthropic/claude-haiku-4.5",
  embedding: Deno.env.get("EMBEDDING_MODEL") ?? "openai/text-embedding-3-small",
  vision: Deno.env.get("VISION_MODEL") ?? "google/gemini-2.5-flash",
};

export const FALLBACK_MODELS = (Deno.env.get("FALLBACK_MODELS") ?? "")
  .split(",").map((m) => m.trim()).filter(Boolean);

export const DAILY_SPEND_CAP = Number(Deno.env.get("DAILY_SPEND_CAP_USD") ?? "2");

const PRICES: Record<string, { input: number; output: number }> = {
  "anthropic/claude-sonnet-4.5": { input: 3, output: 15 },
  "anthropic/claude-haiku-4.5": { input: 1, output: 5 },
  "openai/gpt-4.1-mini": { input: 0.4, output: 1.6 },
  "openai/gpt-4.1": { input: 2, output: 8 },
  "google/gemini-2.5-flash": { input: 0.3, output: 2.5 },
  "openai/text-embedding-3-small": { input: 0.02, output: 0 },
};

export function estimateCost(model: string, prompt: number, completion: number) {
  const p = PRICES[model] ?? { input: 3, output: 15 };
  return (prompt / 1e6) * p.input + (completion / 1e6) * p.output;
}

export type Msg = { role: "system" | "user" | "assistant" | "tool"; content: string | null; tool_calls?: any[]; tool_call_id?: string };

export async function chat(body: Record<string, unknown>, model = MODELS.chat) {
  const key = Deno.env.get("OPENROUTER_API_KEY");
  if (!key) throw new Error("OPENROUTER_API_KEY is not configured");
  const started = Date.now();
  const res = await fetch(`${OPENROUTER_URL}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://maison.local",
      "X-Title": "Maison",
    },
    body: JSON.stringify({ model, ...body }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data?.error?.message ?? `OpenRouter ${res.status}`);
  return { data, latency: Date.now() - started, model };
}

export async function chatWithFallback(body: Record<string, unknown>, primary = MODELS.chat) {
  const chain = [primary, ...FALLBACK_MODELS.filter((m) => m !== primary)];
  let lastError: unknown;
  for (const model of chain) {
    try {
      return await chat(body, model);
    } catch (error) {
      lastError = error;
      console.error(`model ${model} failed`, error);
    }
  }
  throw lastError;
}
