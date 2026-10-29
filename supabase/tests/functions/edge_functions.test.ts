import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { estimateCost, chatWithFallback, MODELS } from "../../functions/_shared/openrouter.ts";
import { TOOL_DEFINITIONS, runTool, applyPreference, type ToolCtx } from "../../functions/_shared/tools.ts";

// ── Test 1: OpenRouter Pricing & Cost Estimation ────────────────────────────
Deno.test("estimateCost computes correct token pricing", () => {
  // anthropic/claude-sonnet-4.5: $3 / 1M prompt, $15 / 1M completion
  const cost = estimateCost("anthropic/claude-sonnet-4.5", 1000, 500);
  // (1000/1e6)*3 + (500/1e6)*15 = 0.003 + 0.0075 = 0.0105
  assertEquals(Number(cost.toFixed(6)), 0.0105);

  // openai/text-embedding-3-small: $0.02 / 1M prompt, $0 completion
  const embCost = estimateCost("openai/text-embedding-3-small", 10000, 0);
  // (10000/1e6)*0.02 = 0.0002
  assertEquals(Number(embCost.toFixed(6)), 0.0002);
});

// ── Test 2: Tool Definitions Integrity ──────────────────────────────────────
Deno.test("TOOL_DEFINITIONS contains exactly the 8 required AI advisor tools", () => {
  const toolNames = TOOL_DEFINITIONS.map((t) => t.function.name).sort();
  const expectedNames = [
    "add_to_collection",
    "explain_match",
    "get_preferences",
    "get_property",
    "propose_preference_updates",
    "request_viewing",
    "search_properties",
    "send_inquiry",
  ].sort();

  assertEquals(toolNames, expectedNames);
});

// ── Test 3: Tool Execution with Mock Supabase Client ─────────────────────────
Deno.test("runTool handles search_properties with mock rpc result", async () => {
  const mockRows = [
    {
      reference_code: "MR-101",
      title: "Hôtel Particulier",
      price: 2650000,
      currency_code: "EUR",
      listing_type: "sale",
      bedrooms: 4,
      area_sqm: 218,
      neighborhood_name: "Le Marais",
      neighborhood_slug: "le-marais",
      primary_style_name: "Haussmannian",
      match_score: 0.92,
      reasons: ["Matches taste for Haussmannian", "In Le Marais"],
    },
  ];

  const mockSupabase: any = {
    rpc: async (fn: string, _args: any) => {
      if (fn === "match_properties") {
        return { data: mockRows, error: null };
      }
      return { data: null, error: new Error("unknown rpc") };
    },
  };

  const ctx: ToolCtx = {
    supabase: mockSupabase,
    clientId: "b0000000-0000-4000-8000-000000000001",
    messageId: "m1",
  };

  const result = await runTool(ctx, "search_properties", {
    listing_type: "sale",
    min_bedrooms: 3,
  });

  assertEquals(result.ok, true);
  assertEquals(result.data?.length, 1);
  assertEquals(result.data?.[0].reference, "MR-101");
  assertEquals(result.data?.[0].match_score, 0.92);
});

// ── Test 4: propose_preference_updates Confidence Thresholds ────────────────
Deno.test("propose_preference_updates discards updates below 0.50 confidence", async () => {
  const insertedRows: any[] = [];
  const mockSupabase: any = {
    from: (table: string) => ({
      insert: (payload: any) => {
        insertedRows.push(payload);
        return {
          select: () => ({
            single: async () => ({
              data: { id: "u1", field_path: payload.field_path, status: payload.status },
              error: null,
            }),
          }),
        };
      },
    }),
  };

  const ctx: ToolCtx = {
    supabase: mockSupabase,
    clientId: "b0000000-0000-4000-8000-000000000001",
    messageId: "m1",
  };

  const result = await runTool(ctx, "propose_preference_updates", {
    updates: [
      { field_path: "min_bedrooms", proposed_value: "4", confidence: 0.45 },
      { field_path: "min_bedrooms", proposed_value: "4", confidence: 0.88 },
      { field_path: "budget_max", proposed_value: "3500000", confidence: 0.90 }, // needs confirm!
    ],
  });

  assertEquals(result.ok, true);
  // First is discarded
  assertEquals(result.data?.[0].status, "discarded");
  // Second has confidence >= 0.85 and is not budget -> applied
  assertEquals(result.data?.[1].status, "applied");
  // Third is budget_max -> needs confirmation so pending despite >= 0.85
  assertEquals(result.data?.[2].status, "pending");
});

// ── Test 5: OpenRouter Fallback Mechanism ────────────────────────────────────
Deno.test("chatWithFallback throws descriptive error if OPENROUTER_API_KEY is not set", async () => {
  const origKey = Deno.env.get("OPENROUTER_API_KEY");
  Deno.env.delete("OPENROUTER_API_KEY");

  await assertRejects(
    async () => {
      await chatWithFallback({ messages: [{ role: "user", content: "hello" }] });
    },
    Error,
    "OPENROUTER_API_KEY is not configured"
  );

  if (origKey) Deno.env.set("OPENROUTER_API_KEY", origKey);
});
