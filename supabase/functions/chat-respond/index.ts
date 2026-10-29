import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, preflight, sseHeaders } from "../_shared/http.ts";
import {
  MODELS,
  DAILY_SPEND_CAP,
  estimateCost,
  chatWithFallback,
  type Msg,
} from "../_shared/openrouter.ts";
import { TOOL_DEFINITIONS, runTool, applyPreference, type ToolCtx } from "../_shared/tools.ts";

const SYSTEM_PROMPT = `You are Maison's AI luxury real estate advisor.
Maison is an AI-personalized luxury real estate platform.
Tone: calm, editorial, sophisticated, discreet, and precise. Avoid buzzwords, neon hyperbole, or sales pressure.

CRITICAL GROUNDING RULES:
1. Price, area, bedrooms, address, and availability may ONLY be quoted directly from tool results returned in the current turn.
2. Never invent, extrapolate, or hallucinate properties, addresses, or specifications.
3. If an detail is not present in a tool result, clearly state that you will verify it with the listing agent.
4. Never provide legal, tax, or mortgage advice. Refer the client to qualified specialists.
5. NEVER infer, discuss, or record protected characteristics (race, religion, national origin, family status, disability, sex, etc.).
6. When recommending properties, always use 'search_properties' or 'get_property' and cite the exact reference code (e.g. MR-101).
7. Tailor recommendations to the client's stated taste and preferences. Use 'get_preferences' when helpful.
`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return preflight();
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(supabaseUrl, supabaseServiceKey);

  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const clientId = user.id;

  let body: { conversation_id?: string; message?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const conversationId = body.conversation_id;
  const userText = (body.message ?? "").trim();

  if (!conversationId || !userText) {
    return new Response(JSON.stringify({ error: "conversation_id and message are required" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Verify conversation belongs to client
  const { data: conv, error: convError } = await adminClient
    .from("conversations")
    .select("id, title, summary, client_id")
    .eq("id", conversationId)
    .single();

  if (convError || !conv || conv.client_id !== clientId) {
    return new Response(JSON.stringify({ error: "Conversation not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Check daily spend cap
  const { data: clientConvs } = await adminClient
    .from("conversations")
    .select("id")
    .eq("client_id", clientId);
  const convIds = (clientConvs ?? []).map((c) => c.id);

  let dailySpend = 0;
  if (convIds.length > 0) {
    const { data: msgs } = await adminClient
      .from("messages")
      .select("id")
      .in("conversation_id", convIds);
    const msgIds = (msgs ?? []).map((m) => m.id);
    if (msgIds.length > 0) {
      const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
      const { data: recentCalls } = await adminClient
        .from("llm_calls")
        .select("cost_usd")
        .in("message_id", msgIds)
        .gte("created_at", oneDayAgo);
      dailySpend = (recentCalls ?? []).reduce((acc, row) => acc + Number(row.cost_usd || 0), 0);
    }
  }

  // Save the incoming user message
  const { data: userMessageRecord, error: userMsgErr } = await adminClient
    .from("messages")
    .insert({
      conversation_id: conversationId,
      role: "user",
      content: userText,
    })
    .select("id")
    .single();

  if (userMsgErr || !userMessageRecord) {
    return new Response(JSON.stringify({ error: "Failed to persist user message" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const userMsgId = userMessageRecord.id;

  // Prepare SSE stream
  const responseStream = new TransformStream();
  const writer = responseStream.writable.getWriter();
  const encoder = new TextEncoder();

  const sendEvent = async (event: string, data: unknown) => {
    const payload = typeof data === "string" ? data : JSON.stringify(data);
    await writer.write(encoder.encode(`event: ${event}\ndata: ${payload}\n\n`));
  };

  // Run processing in background and stream results
  (async () => {
    try {
      if (dailySpend >= DAILY_SPEND_CAP) {
        const capNotice =
          "You have reached your daily AI advisor usage cap ($2.00). Please return tomorrow or contact our advisory team directly.";
        await sendEvent("token", { token: capNotice });

        await adminClient.from("messages").insert({
          conversation_id: conversationId,
          role: "assistant",
          content: capNotice,
        });

        await sendEvent("done", "[DONE]");
        await writer.close();
        return;
      }

      // Fetch last 12 messages for history
      const { data: historyRows } = await adminClient
        .from("messages")
        .select("role, content")
        .eq("conversation_id", conversationId)
        .order("created_at", { ascending: true })
        .limit(12);

      const conversationHistory: Msg[] = (historyRows ?? []).map((m) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      }));

      const systemPromptWithSummary = conv.summary
        ? `${SYSTEM_PROMPT}\n\nClient Conversation Context/Summary: ${conv.summary}`
        : SYSTEM_PROMPT;

      const llmMessages: Msg[] = [
        { role: "system", content: systemPromptWithSummary },
        ...conversationHistory,
      ];

      // Tool call loop
      let iteration = 0;
      const MAX_ITERATIONS = 4;
      const timeoutMs = 25000;
      const startTime = Date.now();
      let assistantText = "";

      const toolCtx: ToolCtx = {
        supabase: adminClient,
        clientId,
        messageId: userMsgId,
      };

      while (iteration < MAX_ITERATIONS && Date.now() - startTime < timeoutMs) {
        iteration++;

        const completion = await chatWithFallback({
          messages: llmMessages,
          tools: TOOL_DEFINITIONS,
          max_tokens: 1024,
          temperature: 0.3,
        }, MODELS.chat);

        const choice = completion.data?.choices?.[0];
        const msg = choice?.message;
        const usage = completion.data?.usage;
        const promptTokens = usage?.prompt_tokens ?? 0;
        const completionTokens = usage?.completion_tokens ?? 0;
        const cost = estimateCost(completion.model, promptTokens, completionTokens);

        // Log LLM call
        await adminClient.from("llm_calls").insert({
          message_id: userMsgId,
          feature: "chat",
          model_id: completion.model,
          prompt_tokens: promptTokens,
          completion_tokens: completionTokens,
          cost_usd: cost,
          latency_ms: completion.latency,
          status: "success",
        });

        if (msg?.tool_calls && msg.tool_calls.length > 0) {
          // Model requested tool calls
          llmMessages.push(msg);

          for (const tc of msg.tool_calls) {
            const toolName = tc.function?.name;
            let toolArgs = {};
            try {
              toolArgs = JSON.parse(tc.function?.arguments || "{}");
            } catch {
              toolArgs = {};
            }

            const toolStart = Date.now();
            let toolResult: any;
            let toolStatus: "success" | "error" = "success";

            try {
              toolResult = await runTool(toolCtx, toolName, toolArgs);
            } catch (err: any) {
              toolStatus = "error";
              toolResult = { ok: false, error: err.message ?? "Tool failed" };
            }

            const toolDuration = Date.now() - toolStart;

            // Log tool execution
            await adminClient.from("tool_calls").insert({
              message_id: userMsgId,
              tool_name: toolName,
              arguments: toolArgs,
              result: toolResult,
              status: toolStatus,
              duration_ms: toolDuration,
            });

            // Emit tool_call event to client
            await sendEvent("tool_call", {
              tool_name: toolName,
              arguments: toolArgs,
              result: toolResult,
            });

            llmMessages.push({
              role: "tool",
              tool_call_id: tc.id,
              content: JSON.stringify(toolResult),
            });
          }
        } else {
          // Final text response reached
          assistantText = msg?.content ?? "";
          break;
        }
      }

      // Stream assistant text tokens (chunked for realistic calm editorial feel)
      if (assistantText) {
        const words = assistantText.split(/(\s+)/);
        for (const token of words) {
          if (token) {
            await sendEvent("token", { token });
          }
        }
      }

      // Save assistant message to messages table
      await adminClient.from("messages").insert({
        conversation_id: conversationId,
        role: "assistant",
        content: assistantText,
      });

      // Background preference extraction via EXTRACTION_MODEL
      try {
        const extractionPrompt = `You are a luxury real estate preference extraction engine.
Analyze the following user message: "${userText}"

Extract any preferences expressed by the user. Only propose updates from these whitelisted fields:
- 'listing_type' (value: "sale" or "rent")
- 'currency_code' (value: "EUR", "AED", "USD")
- 'budget_min' (number)
- 'budget_max' (number)
- 'min_bedrooms' (number)
- 'min_bathrooms' (number)
- 'min_area_sqm' (number)
- 'max_area_sqm' (number)
- 'style' (object: {"code": "haussmannian"|"contemporary"|"modernist"|"art-deco"|"mediterranean"|"minimalist"|"brutalist"|"traditional", "score": -2 to 2 not 0})
- 'amenity' (object: {"code": "pool"|"spa"|"gym"|"hammam"|"terrace"|"garden"|"balcony"|"roof-terrace"|"home-automation"|"climate-control"|"sound-system"|"ev-charging"|"concierge"|"doorman"|"cctv"|"gated"|"garage"|"parking"|"valet"|"car-lift"|"sea-view"|"skyline-view"|"garden-view"|"city-view"|"elevator"|"fireplace"|"wine-cellar"|"staff-quarters", "requirement": "must"|"nice"})
- 'neighborhood' (object: {"slug": "le-marais"|"saint-germain"|"paris-7e"|"montmartre"|"palm-jumeirah"|"downtown-dubai"|"jumeirah-bay"|"emirates-hills"|"saadiyat"|"al-reem"|"khalifa-city"|"yas-island", "priority": 1|2|3})
- 'property_type' (object: {"code": "apartment"|"penthouse"|"villa"|"townhouse"|"loft"|"mansion"})

Output MUST be a valid JSON array of objects:
[
  {
    "field_path": string,
    "proposed_value": any,
    "confidence": number (between 0.0 and 1.0),
    "reason": string
  }
]
If no preferences were expressed, return [].`;

        const extStart = Date.now();
        const extCompletion = await chatWithFallback({
          messages: [
            { role: "system", content: "You extract structured preferences in JSON." },
            { role: "user", content: extractionPrompt },
          ],
          response_format: { type: "json_object" },
          temperature: 0.1,
          max_tokens: 500,
        }, MODELS.extraction);

        const extRaw = extCompletion.data?.choices?.[0]?.message?.content ?? "[]";
        let parsedUpdates: any[] = [];
        try {
          const parsed = JSON.parse(extRaw);
          parsedUpdates = Array.isArray(parsed) ? parsed : (parsed.updates ?? []);
        } catch {
          parsedUpdates = [];
        }

        const extUsage = extCompletion.data?.usage;
        const extCost = estimateCost(
          extCompletion.model,
          extUsage?.prompt_tokens ?? 0,
          extUsage?.completion_tokens ?? 0
        );

        await adminClient.from("llm_calls").insert({
          message_id: userMsgId,
          feature: "extraction",
          model_id: extCompletion.model,
          prompt_tokens: extUsage?.prompt_tokens ?? 0,
          completion_tokens: extUsage?.completion_tokens ?? 0,
          cost_usd: extCost,
          latency_ms: Date.now() - extStart,
          status: "success",
        });

        const emittedUpdates = [];
        for (const u of parsedUpdates) {
          const confidence = Number(u.confidence ?? 0);
          if (confidence < 0.5) continue;

          const needsConfirm = ["budget_min", "budget_max", "listing_type"].includes(u.field_path);
          const status = confidence >= 0.85 && !needsConfirm ? "applied" : "pending";

          const { data: updateRow } = await adminClient
            .from("preference_updates")
            .insert({
              client_id: clientId,
              source_message_id: userMsgId,
              origin: "chat",
              field_path: u.field_path,
              proposed_value: u.proposed_value,
              confidence,
              reason: u.reason ?? "Identified by AI advisor",
              status,
              resolved_at: status === "applied" ? new Date().toISOString() : null,
            })
            .select("id, field_path, proposed_value, confidence, reason, status")
            .single();

          if (updateRow) {
            if (status === "applied") {
              await applyPreference(adminClient, clientId, u.field_path, u.proposed_value);
            }
            emittedUpdates.push(updateRow);
          }
        }

        if (emittedUpdates.length > 0) {
          await sendEvent("preference_updates", emittedUpdates);
        }
      } catch (extErr) {
        console.error("Preference extraction error:", extErr);
      }

      await sendEvent("done", "[DONE]");
    } catch (err: any) {
      console.error("Chat respond loop error:", err);
      await sendEvent("error", { message: err.message ?? "Advisor processing error" });
    } finally {
      await writer.close();
    }
  })();

  return new Response(responseStream.readable, {
    status: 200,
    headers: sseHeaders(),
  });
});
