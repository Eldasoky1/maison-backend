import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, preflight, json } from "../_shared/http.ts";
import { MODELS, OPENROUTER_URL, estimateCost } from "../_shared/openrouter.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return preflight();
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const adminClient = createClient(supabaseUrl, supabaseServiceKey);

  let body: { property_id?: string; image_ids?: string[] } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const propertyId = body.property_id;
  if (!propertyId) {
    return json({ error: "property_id is required" }, 400);
  }

  // Fetch property and images
  const [{ data: prop }, { data: images }, { data: styles }, { data: amenities }] = await Promise.all([
    adminClient.from("properties").select("id, reference_code").eq("id", propertyId).single(),
    adminClient
      .from("property_images")
      .select("id, storage_path, media_kind, is_cover, alt_text")
      .eq("property_id", propertyId)
      .order("sort_order"),
    adminClient.from("architectural_styles").select("id, code, name"),
    adminClient.from("amenities").select("id, code, name"),
  ]);

  if (!prop) {
    return json({ error: "Property not found" }, 404);
  }

  if (!images || images.length === 0) {
    return json({ success: true, message: "No images to tag for this property", updated: 0 });
  }

  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  const availableStyles = (styles ?? []).map((s) => s.code);
  const styleCodeToId = new Map((styles ?? []).map((s) => [s.code, s.id]));

  let updatedImagesCount = 0;
  const taggedStyles: Array<{ code: string; confidence: number; is_primary: boolean }> = [];

  for (const img of images.slice(0, 4)) {
    // Construct public or signed URL if in Supabase storage
    let imageUrl = img.storage_path;
    if (!imageUrl.startsWith("http")) {
      const { data: publicUrlData } = adminClient.storage
        .from("property-images")
        .getPublicUrl(img.storage_path);
      imageUrl = publicUrlData?.publicUrl ?? img.storage_path;
    }

    if (apiKey) {
      const started = Date.now();
      try {
        const prompt = `Analyze this luxury real estate architectural image.
Known styles: ${availableStyles.join(", ")}.
Return a JSON object:
{
  "alt_text": "An elegant, calm description in 1-2 sentences for visually impaired users.",
  "primary_style": "one of the known style codes above",
  "confidence": 0.85,
  "detected_amenities": ["amenity_codes_from_image"]
}`;

        const res = await fetch(`${OPENROUTER_URL}/chat/completions`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
            "HTTP-Referer": "https://maison.local",
            "X-Title": "Maison",
          },
          body: JSON.stringify({
            model: MODELS.vision,
            messages: [
              {
                role: "user",
                content: [
                  { type: "text", text: prompt },
                  { type: "image_url", image_url: { url: imageUrl } },
                ],
              },
            ],
            response_format: { type: "json_object" },
            max_tokens: 400,
          }),
        });

        const resData = await res.json();
        const latency = Date.now() - started;
        const usage = resData?.usage;
        const pTokens = usage?.prompt_tokens ?? 0;
        const cTokens = usage?.completion_tokens ?? 0;

        await adminClient.from("llm_calls").insert({
          feature: "vision_tagging",
          model_id: MODELS.vision,
          prompt_tokens: pTokens,
          completion_tokens: cTokens,
          cost_usd: estimateCost(MODELS.vision, pTokens, cTokens),
          latency_ms: latency,
          status: res.ok ? "success" : "error",
        });

        if (res.ok) {
          const content = resData?.choices?.[0]?.message?.content ?? "{}";
          let parsed: any = {};
          try {
            parsed = JSON.parse(content);
          } catch {
            parsed = {};
          }

          if (parsed.alt_text && !img.alt_text) {
            await adminClient
              .from("property_images")
              .update({ alt_text: parsed.alt_text })
              .eq("id", img.id);
            updatedImagesCount++;
          }

          if (parsed.primary_style && styleCodeToId.has(parsed.primary_style)) {
            const styleId = styleCodeToId.get(parsed.primary_style)!;
            const conf = Math.max(0, Math.min(1, Number(parsed.confidence) || 0.8));

            await adminClient
              .from("property_styles")
              .upsert(
                {
                  property_id: propertyId,
                  style_id: styleId,
                  source: "vision_ai",
                  confidence: conf,
                  is_primary: false,
                },
                { onConflict: "property_id,style_id" }
              );

            taggedStyles.push({
              code: parsed.primary_style,
              confidence: conf,
              is_primary: false,
            });
          }
        }
      } catch (visErr) {
        console.error("Vision API call failed:", visErr);
      }
    } else {
      // Offline fallback: set generic descriptive alt text if empty
      if (!img.alt_text) {
        await adminClient
          .from("property_images")
          .update({ alt_text: `Architectural interior of ${prop.reference_code}` })
          .eq("id", img.id);
        updatedImagesCount++;
      }
    }
  }

  return json({
    success: true,
    property_id: propertyId,
    updated_images: updatedImagesCount,
    tagged_styles: taggedStyles,
  });
});
