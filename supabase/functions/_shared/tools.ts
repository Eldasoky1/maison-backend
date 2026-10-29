import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export type ToolCtx = { supabase: SupabaseClient; clientId: string; messageId: string };

const s = (type: string, description?: string, extra: Record<string, unknown> = {}) =>
  ({ type, ...(description ? { description } : {}), ...extra });

const tool = (name: string, description: string, properties: Record<string, unknown>, required: string[] = []) =>
  ({ type: "function" as const, function: { name, description, parameters: { type: "object", properties, required } } });

export const TOOL_DEFINITIONS = [
  tool("search_properties", "Search live listings. Use for any recommendation. Never invent a listing.", {
    query: s("string", "Free text, e.g. 'garden' or 'left bank'"),
    listing_type: s("string", undefined, { enum: ["sale", "rent"] }),
    min_bedrooms: s("integer"), budget_max: s("number"),
    neighborhood: s("string", "Neighborhood slug or name"),
    style: s("string", "Architectural style code"),
    limit: s("integer", "1-20"),
  }),
  tool("get_property", "Full detail for one listing by reference code.", {
    reference: s("string", "e.g. MR-101"),
  }, ["reference"]),
  tool("explain_match", "The stored match components and SQL-written reasons for a listing.", {
    reference: s("string"),
  }, ["reference"]),
  tool("get_preferences", "The client's stored taste profile. Read before proposing changes.", {}),
  tool("propose_preference_updates", "Propose preference changes. Confidence < 0.5 is discarded by the server.", {
    updates: s("array", "Array of updates", {
      items: {
        type: "object",
        properties: {
          field_path: s("string", undefined, { enum: ["listing_type", "currency_code", "budget_min", "budget_max", "min_bedrooms", "min_bathrooms", "min_area_sqm", "max_area_sqm", "style", "amenity", "neighborhood", "property_type"] }),
          proposed_value: s("string", "JSON-encoded value, e.g. \"4\" or \"{\\\"code\\\":\\\"haussmannian\\\"}\""),
          confidence: s("number"),
          reason: s("string"),
        },
        required: ["field_path", "proposed_value", "confidence"],
      },
    }),
  }, ["updates"]),
  tool("add_to_collection", "Save a listing to a collection, creating a default one if needed.", {
    reference: s("string"), collection_name: s("string"),
  }, ["reference"]),
  tool("request_viewing", "Request a viewing. Only call after the client confirms a date and time.", {
    reference: s("string"), requested_start: s("string", "ISO 8601 with timezone"),
    duration_minutes: s("integer"), notes: s("string"),
  }, ["reference", "requested_start"]),
  tool("send_inquiry", "Send a written inquiry to the listing's agent.", {
    reference: s("string"), subject: s("string"), body: s("string"),
  }, ["reference", "subject", "body"]),
];

export async function runTool(ctx: ToolCtx, name: string, args: Record<string, any>) {
  const { supabase, clientId } = ctx;
  const ref = String(args.reference ?? "").toUpperCase();

  if (name === "search_properties") {
    const { data, error } = await supabase.rpc("match_properties", {
      p_client_id: clientId, p_limit: 40, p_offset: 0, p_sort: "relevance",
    });
    if (error) return { ok: false, error: error.message };
    let rows = (data ?? []) as any[];
    if (args.listing_type) rows = rows.filter((r) => r.listing_type === args.listing_type);
    if (args.min_bedrooms) rows = rows.filter((r) => r.bedrooms >= args.min_bedrooms);
    if (args.budget_max) rows = rows.filter((r) => r.price <= args.budget_max);
    if (args.neighborhood) rows = rows.filter((r) =>
      `${r.neighborhood_slug} ${r.neighborhood_name}`.toLowerCase().includes(String(args.neighborhood).toLowerCase()));
    if (args.style) rows = rows.filter((r) => (r.primary_style_name ?? "").toLowerCase().includes(String(args.style).toLowerCase()));
    if (args.query) {
      const q = String(args.query).toLowerCase();
      rows = rows.filter((r) => `${r.title} ${r.description} ${r.neighborhood_name} ${r.primary_style_name}`.toLowerCase().includes(q));
    }
    return { ok: true, data: rows.slice(0, Math.min(Number(args.limit) || 8, 20)).map((r) => ({
      reference: r.reference_code, title: r.title, price: r.price, currency: r.currency_code,
      listing_type: r.listing_type, bedrooms: r.bedrooms, area_sqm: r.area_sqm,
      neighborhood: r.neighborhood_name, style: r.primary_style_name,
      match_score: r.match_score, reasons: (r.reasons ?? []).slice(0, 2),
    })) };
  }

  if (name === "get_property" || name === "explain_match") {
    const { data: card } = await supabase.from("listing_cards").select("*").eq("reference_code", ref).maybeSingle();
    if (!card) return { ok: false, error: `No live listing ${ref}` };
    const [{ data: amenities }, { data: styles }, { data: images }] = await Promise.all([
      supabase.from("property_amenities").select("amenities(name)").eq("property_id", card.id),
      supabase.from("property_styles").select("is_primary, confidence, architectural_styles(name)").eq("property_id", card.id),
      supabase.from("property_images").select("storage_path, media_kind, alt_text").eq("property_id", card.id).order("sort_order"),
    ]);
    return { ok: true, data: { ...card, amenities: (amenities ?? []).map((a: any) => a.amenities?.name), styles: styles ?? [], images: images ?? [] } };
  }

  if (name === "get_preferences") {
    const [{ data: prefs }, { data: styles }, { data: amenities }, { data: hoods }, { data: types }, { data: pending }] = await Promise.all([
      supabase.from("client_preferences").select("*").eq("client_id", clientId).maybeSingle(),
      supabase.from("preference_styles").select("score, architectural_styles(code,name)").eq("client_id", clientId),
      supabase.from("preference_amenities").select("requirement, amenities(code,name)").eq("client_id", clientId),
      supabase.from("preference_neighborhoods").select("priority, neighborhoods(name,slug)").eq("client_id", clientId),
      supabase.from("preference_property_types").select("property_types(code,name)").eq("client_id", clientId),
      supabase.from("preference_updates").select("*").eq("client_id", clientId).eq("status", "pending"),
    ]);
    return { ok: true, data: { preferences: prefs, styles, amenities, neighborhoods: hoods, property_types: types, pending_updates: pending } };
  }

  if (name === "propose_preference_updates") {
    const updates = Array.isArray(args.updates) ? args.updates : [];
    const results = [];
    for (const u of updates.slice(0, 8)) {
      const confidence = Number(u.confidence ?? 0);
      if (confidence < 0.5) { results.push({ field_path: u.field_path, status: "discarded" }); continue; }
      const needsConfirm = ["budget_min", "budget_max", "listing_type"].includes(u.field_path);
      const status = confidence >= 0.85 && !needsConfirm ? "applied" : "pending";
      let value: unknown = u.proposed_value;
      try { value = JSON.parse(String(u.proposed_value)); } catch { /* keep raw */ }
      const { data, error } = await supabase.from("preference_updates").insert({
        client_id: clientId, source_message_id: ctx.messageId, origin: "chat",
        field_path: u.field_path, proposed_value: value, confidence,
        reason: u.reason ?? null, status, resolved_at: status === "applied" ? new Date().toISOString() : null,
      }).select("id, field_path, status").single();
      if (error) { results.push({ field_path: u.field_path, error: error.message }); continue; }
      if (status === "applied") await applyPreference(supabase, clientId, u.field_path, value);
      results.push(data);
    }
    return { ok: true, data: results };
  }

  const { data: property } = await supabase
    .from("properties").select("id, agent_id, reference_code").eq("reference_code", ref).maybeSingle();
  if (!property) return { ok: false, error: `No listing ${ref}` };

  if (name === "add_to_collection") {
    let { data: collection } = await supabase.from("collections")
      .select("id, name").eq("client_id", clientId).eq("is_default", true).maybeSingle();
    if (!collection) {
      const created = await supabase.from("collections")
        .insert({ client_id: clientId, name: args.collection_name ?? "Saved homes", is_default: true })
        .select("id, name").single();
      if (created.error) return { ok: false, error: created.error.message };
      collection = created.data;
    }
    const { error } = await supabase.from("collection_items")
      .upsert({ collection_id: collection.id, property_id: property.id, note: args.note ?? null });
    return error ? { ok: false, error: error.message } : { ok: true, data: { collection: collection.name, reference: ref } };
  }

  if (name === "request_viewing") {
    const { data, error } = await supabase.from("viewing_requests").insert({
      client_id: clientId, property_id: property.id, agent_id: property.agent_id,
      requested_start: args.requested_start, duration_minutes: Number(args.duration_minutes) || 45,
      notes: args.notes ?? null, status: "requested",
    }).select("id, requested_start, status").single();
    if (error) return { ok: false, error: error.code === "23P01" ? "That slot is already booked. Offer another time." : error.message };
    return { ok: true, data };
  }

  if (name === "send_inquiry") {
    const { data: inquiry, error } = await supabase.from("inquiries")
      .insert({ client_id: clientId, property_id: property.id, subject: args.subject }).select("id").single();
    if (error) return { ok: false, error: error.message };
    const { error: messageError } = await supabase.from("inquiry_messages")
      .insert({ inquiry_id: inquiry.id, sender_id: clientId, body: args.body });
    return messageError ? { ok: false, error: messageError.message } : { ok: true, data: { inquiry_id: inquiry.id } };
  }

  return { ok: false, error: `Unknown tool ${name}` };
}

export async function applyPreference(
  supabase: SupabaseClient,
  clientId: string,
  fieldPath: string,
  value: any
) {
  const scalarFields = [
    "listing_type",
    "currency_code",
    "budget_min",
    "budget_max",
    "min_bedrooms",
    "min_bathrooms",
    "min_area_sqm",
    "max_area_sqm",
  ];

  if (scalarFields.includes(fieldPath)) {
    const updateObj: Record<string, any> = {};
    updateObj[fieldPath] = value;
    await supabase.from("client_preferences").update(updateObj).eq("client_id", clientId);
    return;
  }

  if (fieldPath === "style") {
    let code = typeof value === "object" && value?.code ? value.code : String(value);
    let score = typeof value === "object" && value?.score ? Number(value.score) : 1;
    if (score === 0) score = 1;
    const { data: style } = await supabase
      .from("architectural_styles")
      .select("id")
      .eq("code", code)
      .maybeSingle();
    if (style?.id) {
      await supabase
        .from("preference_styles")
        .upsert({ client_id: clientId, style_id: style.id, score });
    }
    return;
  }

  if (fieldPath === "amenity") {
    let code = typeof value === "object" && value?.code ? value.code : String(value);
    let requirement = (typeof value === "object" && value?.requirement === "must") ? "must" : "nice";
    const { data: amenity } = await supabase
      .from("amenities")
      .select("id")
      .eq("code", code)
      .maybeSingle();
    if (amenity?.id) {
      await supabase
        .from("preference_amenities")
        .upsert({ client_id: clientId, amenity_id: amenity.id, requirement });
    }
    return;
  }

  if (fieldPath === "neighborhood") {
    let slug = typeof value === "object" && value?.slug ? value.slug : String(value);
    let priority = typeof value === "object" && value?.priority ? Number(value.priority) : 2;
    const { data: hood } = await supabase
      .from("neighborhoods")
      .select("id")
      .eq("slug", slug)
      .maybeSingle();
    if (hood?.id) {
      await supabase
        .from("preference_neighborhoods")
        .upsert({ client_id: clientId, neighborhood_id: hood.id, priority });
    }
    return;
  }

  if (fieldPath === "property_type") {
    let code = typeof value === "object" && value?.code ? value.code : String(value);
    const { data: pt } = await supabase
      .from("property_types")
      .select("id")
      .eq("code", code)
      .maybeSingle();
    if (pt?.id) {
      await supabase
        .from("preference_property_types")
        .upsert({ client_id: clientId, property_type_id: pt.id });
    }
    return;
  }
}





