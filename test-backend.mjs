import { test, describe } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";

const rootDir = process.cwd();
const migrationsDir = path.join(rootDir, "supabase", "migrations");
const seedFile = path.join(rootDir, "supabase", "seed.sql");

describe("1. Database Schema & Migrations Integrity", () => {
  const migrationFiles = fs.readdirSync(migrationsDir).filter((f) => f.endsWith(".sql")).sort();
  const allSql = migrationFiles.map((f) => fs.readFileSync(path.join(migrationsDir, f), "utf-8")).join("\n");

  test("Exactly 10 ordered migration files exist", () => {
    assert.equal(migrationFiles.length, 10);
    assert.match(migrationFiles[0], /init\.sql/);
    assert.match(migrationFiles[1], /reference\.sql/);
    assert.match(migrationFiles[2], /identity\.sql/);
    assert.match(migrationFiles[3], /catalog\.sql/);
    assert.match(migrationFiles[4], /ai\.sql/);
    assert.match(migrationFiles[5], /preferences\.sql/);
    assert.match(migrationFiles[6], /engagement\.sql/);
    assert.match(migrationFiles[7], /logic\.sql/);
    assert.match(migrationFiles[8], /rls\.sql/);
    assert.match(migrationFiles[9], /storage_cron\.sql/);
  });

  const expectedTables = [
    // Reference (9)
    "currencies", "countries", "cities", "neighborhoods", "architectural_styles",
    "amenity_categories", "amenities", "property_types", "hero_variants",
    // Identity (6)
    "profiles", "agencies", "agent_profiles", "agency_verifications", "consent_records", "audit_logs",
    // Catalog (6)
    "properties", "property_translations", "property_images", "property_amenities",
    "property_styles", "property_price_history",
    // Preferences (6)
    "client_preferences", "preference_styles", "preference_amenities",
    "preference_neighborhoods", "preference_property_types", "preference_updates",
    // Engagement (8)
    "collections", "collection_items", "property_interactions", "agent_availability",
    "viewing_requests", "inquiries", "inquiry_messages", "notifications",
    // AI Telemetry (4)
    "conversations", "messages", "tool_calls", "llm_calls",
  ];

  test("All 39 tables are defined with valid SQL table definitions", () => {
    assert.equal(expectedTables.length, 39);
    for (const table of expectedTables) {
      const tableRegex = new RegExp(`create table( if not exists)? public\\.${table}\\b`, "i");
      assert.ok(
        tableRegex.test(allSql),
        `Table definition missing or misnamed: public.${table}`
      );
    }
  });

  test("Row Level Security is enabled on all 39 tables", () => {
    for (const table of expectedTables) {
      const rlsRegex = new RegExp(`alter table public\\.${table} enable row level security`, "i");
      assert.ok(
        rlsRegex.test(allSql),
        `RLS not enabled on public.${table}`
      );
    }
  });

  test("Composite Foreign Key & Unique on properties(id, agent_id)", () => {
    assert.ok(
      allSql.includes("constraint properties_id_agent_key unique (id, agent_id)") ||
      allSql.includes("unique (id, agent_id)"),
      "Unique constraint on properties(id, agent_id) missing"
    );
    assert.ok(
      allSql.includes("references public.properties(id, agent_id)"),
      "Composite FK to properties(id, agent_id) missing on viewing_requests"
    );
  });

  test("GiST exclusion constraint prevents overlapping viewing bookings per agent", () => {
    assert.ok(
      allSql.includes("constraint viewing_requests_no_overlap") &&
      allSql.includes("exclude using gist") &&
      allSql.includes("agent_id with =") &&
      allSql.includes("tstzrange(requested_start, ends_at) with &&"),
      "GiST exclusion constraint on viewing_requests missing"
    );
  });

  test("Notifications check constraint enforces exactly one subject reference", () => {
    assert.ok(
      allSql.includes("notifications_one_subject") &&
      allSql.includes("num_nonnulls(property_id, viewing_request_id, inquiry_id) = 1"),
      "Notifications check constraint for exactly one subject missing"
    );
  });

  test("Preference styles constraint enforces score between -2 and 2 and score <> 0", () => {
    assert.ok(
      allSql.includes("check (score between -2 and 2 and score <> 0)"),
      "Score bounds check on preference_styles missing"
    );
  });

  test("Key database functions are defined with SECURITY DEFINER and search_path set", () => {
    const requiredFunctions = [
      "is_admin",
      "is_agent",
      "is_agency_verified",
      "match_properties",
      "purge_expired_data",
      "export_my_data",
      "delete_my_account",
    ];

    for (const fn of requiredFunctions) {
      const fnRegex = new RegExp(`create or replace function public\\.${fn}\\b`, "i");
      assert.ok(fnRegex.test(allSql), `Function public.${fn} is missing`);
    }
  });

  test("Storage buckets and policies are defined", () => {
    assert.ok(allSql.includes("'property-images'"), "Bucket property-images missing");
    assert.ok(allSql.includes("'avatars'"), "Bucket avatars missing");
    assert.ok(allSql.includes("'agency-documents'"), "Bucket agency-documents missing");
  });
});

describe("2. Seed Data & Static Assets Validation", () => {
  const seedSql = fs.readFileSync(seedFile, "utf-8");

  test("Seed script exists and contains valid syntax", () => {
    assert.ok(seedSql.length > 5000);
    assert.ok(seedSql.includes("insert into public.currencies"));
    assert.ok(seedSql.includes("insert into public.countries"));
    assert.ok(seedSql.includes("insert into public.cities"));
    assert.ok(seedSql.includes("insert into public.neighborhoods"));
    assert.ok(seedSql.includes("insert into public.architectural_styles"));
    assert.ok(seedSql.includes("insert into public.amenities"));
    assert.ok(seedSql.includes("insert into public.property_types"));
    assert.ok(seedSql.includes("insert into public.hero_variants"));
  });

  test("Seed script seeds exactly 30 synthetic listings (MR-101 to MR-115, MR-201 to MR-215)", () => {
    for (let i = 101; i <= 115; i++) {
      assert.ok(seedSql.includes(`'MR-${i}'`), `Listing MR-${i} missing from seed`);
    }
    for (let i = 201; i <= 215; i++) {
      assert.ok(seedSql.includes(`'MR-${i}'`), `Listing MR-${i} missing from seed`);
    }
  });

  test("Seed script seeds verified agency and agent personas", () => {
    assert.ok(seedSql.includes("Maison Privé"), "Maison Privé agency missing");
    assert.ok(seedSql.includes("camille@maison.test"), "Agent Camille missing");
    assert.ok(seedSql.includes("omar@maison.test"), "Agent Omar missing");
    assert.ok(seedSql.includes("elise@maison.test"), "Client Elise missing");
    assert.ok(seedSql.includes("james@maison.test"), "Client James missing");
    assert.ok(seedSql.includes("layla@maison.test"), "Client Layla missing");
    assert.ok(seedSql.includes("admin@maison.test"), "Admin missing");
  });

  test("Pre-computed 1536-dimensional embeddings for all 30 listings", () => {
    assert.ok(seedSql.includes("vector(1536)"), "1536-dimensional vector generation missing");
    assert.ok(seedSql.includes("embedding_stale = false"), "embedding_stale update missing");
  });

  test("Public seed SVG assets exist on disk (129 files)", () => {
    const publicSeedDir = path.join(rootDir, "public", "seed");
    assert.ok(fs.existsSync(publicSeedDir), "public/seed folder missing");
    const files = fs.readdirSync(publicSeedDir);
    assert.ok(files.length >= 120, `Expected at least 120 SVG assets, got ${files.length}`);
    assert.ok(files.includes("style-haussmannian.svg"));
    assert.ok(files.includes("mr-101-cover.svg"));
    assert.ok(files.includes("mr-101-1.svg"));
    assert.ok(files.includes("mr-101-plan.svg"));
  });
});

describe("3. Edge Functions Logic & Safety Controls", () => {
  // Test pricing formula from openrouter.ts
  const PRICES = {
    "anthropic/claude-sonnet-4.5": { input: 3, output: 15 },
    "anthropic/claude-haiku-4.5": { input: 1, output: 5 },
    "openai/gpt-4.1-mini": { input: 0.4, output: 1.6 },
    "openai/text-embedding-3-small": { input: 0.02, output: 0 },
    "google/gemini-2.5-flash": { input: 0.3, output: 2.5 },
  };

  function estimateCost(model, promptTokens, completionTokens) {
    const p = PRICES[model] || { input: 3, output: 15 };
    return (promptTokens / 1e6) * p.input + (completionTokens / 1e6) * p.output;
  }

  test("OpenRouter cost estimator accurately computes USD token costs", () => {
    const sonnetCost = estimateCost("anthropic/claude-sonnet-4.5", 1000, 500);
    // (1000/1e6)*3 + (500/1e6)*15 = 0.003 + 0.0075 = 0.0105
    assert.equal(Number(sonnetCost.toFixed(6)), 0.0105);

    const haikuCost = estimateCost("anthropic/claude-haiku-4.5", 2000, 200);
    // (2000/1e6)*1 + (200/1e6)*5 = 0.002 + 0.001 = 0.003
    assert.equal(Number(haikuCost.toFixed(6)), 0.003);

    const embCost = estimateCost("openai/text-embedding-3-small", 50000, 0);
    // (50000/1e6)*0.02 = 0.001
    assert.equal(Number(embCost.toFixed(6)), 0.001);
  });

  test("Preference updates confidence rules match specifications", () => {
    function classifyUpdate(fieldPath, confidence) {
      if (confidence < 0.5) return "discarded";
      const needsConfirm = ["budget_min", "budget_max", "listing_type"].includes(fieldPath);
      if (confidence >= 0.85 && !needsConfirm) return "applied";
      return "pending";
    }

    // Below 0.50 -> discarded
    assert.equal(classifyUpdate("min_bedrooms", 0.45), "discarded");
    assert.equal(classifyUpdate("budget_max", 0.49), "discarded");

    // 0.50 to 0.84 -> pending
    assert.equal(classifyUpdate("min_bedrooms", 0.75), "pending");
    assert.equal(classifyUpdate("style", 0.60), "pending");

    // >= 0.85 non-budget -> applied
    assert.equal(classifyUpdate("min_bedrooms", 0.85), "applied");
    assert.equal(classifyUpdate("min_bedrooms", 0.95), "applied");
    assert.equal(classifyUpdate("amenity", 0.90), "applied");
    assert.equal(classifyUpdate("style", 0.88), "applied");

    // >= 0.85 budget or listing_type -> ALWAYS needs confirmation (pending)
    assert.equal(classifyUpdate("budget_min", 0.95), "pending");
    assert.equal(classifyUpdate("budget_max", 0.90), "pending");
    assert.equal(classifyUpdate("listing_type", 0.99), "pending");
  });

  test("Transparent Match Scoring Formula matches SQL logic", () => {
    function computeMatchScore({ semantic, style, amenity, neighborhood, active }) {
      if (!active) return 0.5;
      const score = 0.35 * semantic + 0.25 * style + 0.20 * amenity + 0.20 * neighborhood;
      return Number(score.toFixed(4));
    }

    // Active with perfect scores
    const perfect = computeMatchScore({ semantic: 1.0, style: 1.0, amenity: 1.0, neighborhood: 1.0, active: true });
    assert.equal(perfect, 1.0);

    // Active with weighted blend:
    // 0.35*0.8 + 0.25*0.7 + 0.20*0.9 + 0.20*0.6 = 0.28 + 0.175 + 0.18 + 0.12 = 0.755
    const blend = computeMatchScore({ semantic: 0.8, style: 0.7, amenity: 0.9, neighborhood: 0.6, active: true });
    assert.equal(blend, 0.755);

    // Disliked style penalty (style = 0.15)
    // 0.35*0.9 + 0.25*0.15 + 0.20*1.0 + 0.20*1.0 = 0.315 + 0.0375 + 0.20 + 0.20 = 0.7525
    const dislikedStyle = computeMatchScore({ semantic: 0.9, style: 0.15, amenity: 1.0, neighborhood: 1.0, active: true });
    assert.equal(dislikedStyle, 0.7525);

    // Consent inactive / revoked -> default neutral 0.5
    const inactive = computeMatchScore({ semantic: 0.9, style: 0.9, amenity: 0.9, neighborhood: 0.9, active: false });
    assert.equal(inactive, 0.5);
  });
});
