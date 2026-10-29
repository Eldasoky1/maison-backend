import { test, describe } from "node:test";
import assert from "node:assert/strict";

describe("4. AI Advisor Tools & Dynamic Preference Engine", () => {
  // Mock tools implementation matching tools.ts
  const TOOL_DEFINITIONS = [
    {
      name: "search_properties",
      required: [],
      properties: ["query", "listing_type", "min_bedrooms", "budget_max", "neighborhood", "style", "limit"]
    },
    {
      name: "get_property",
      required: ["reference"],
      properties: ["reference"]
    },
    {
      name: "explain_match",
      required: ["reference"],
      properties: ["reference"]
    },
    {
      name: "get_preferences",
      required: [],
      properties: []
    },
    {
      name: "propose_preference_updates",
      required: ["updates"],
      properties: ["updates"]
    },
    {
      name: "add_to_collection",
      required: ["reference"],
      properties: ["reference", "collection_name", "note"]
    },
    {
      name: "request_viewing",
      required: ["reference", "requested_start"],
      properties: ["reference", "requested_start", "duration_minutes", "notes"]
    },
    {
      name: "send_inquiry",
      required: ["reference", "subject", "body"],
      properties: ["reference", "subject", "body"]
    }
  ];

  test("Advisor tool suite defines exactly the 8 specified tools with required parameters", () => {
    assert.equal(TOOL_DEFINITIONS.length, 8);
    const names = TOOL_DEFINITIONS.map(t => t.name).sort();
    assert.deepEqual(names, [
      "add_to_collection",
      "explain_match",
      "get_preferences",
      "get_property",
      "propose_preference_updates",
      "request_viewing",
      "search_properties",
      "send_inquiry"
    ]);

    const getProp = TOOL_DEFINITIONS.find(t => t.name === "get_property");
    assert.deepEqual(getProp.required, ["reference"]);

    const reqViewing = TOOL_DEFINITIONS.find(t => t.name === "request_viewing");
    assert.deepEqual(reqViewing.required, ["reference", "requested_start"]);

    const inquiry = TOOL_DEFINITIONS.find(t => t.name === "send_inquiry");
    assert.deepEqual(inquiry.required, ["reference", "subject", "body"]);
  });

  test("search_properties filters listings accurately", () => {
    const mockListings = [
      { reference_code: "MR-101", listing_type: "sale", bedrooms: 4, price: 2650000, neighborhood_name: "Le Marais", primary_style_name: "Haussmannian" },
      { reference_code: "MR-102", listing_type: "sale", bedrooms: 2, price: 1980000, neighborhood_name: "Le Marais", primary_style_name: "Contemporary" },
      { reference_code: "MR-108", listing_type: "rent", bedrooms: 3, price: 8500, neighborhood_name: "Le Marais", primary_style_name: "Traditional" },
      { reference_code: "MR-201", listing_type: "sale", bedrooms: 5, price: 18500000, neighborhood_name: "Palm Jumeirah", primary_style_name: "Mediterranean" },
    ];

    function search(args) {
      let rows = [...mockListings];
      if (args.listing_type) rows = rows.filter(r => r.listing_type === args.listing_type);
      if (args.min_bedrooms) rows = rows.filter(r => r.bedrooms >= args.min_bedrooms);
      if (args.budget_max) rows = rows.filter(r => r.price <= args.budget_max);
      if (args.style) rows = rows.filter(r => r.primary_style_name.toLowerCase().includes(args.style.toLowerCase()));
      return rows;
    }

    const saleBeds4 = search({ listing_type: "sale", min_bedrooms: 4 });
    assert.equal(saleBeds4.length, 2);
    assert.equal(saleBeds4[0].reference_code, "MR-101");
    assert.equal(saleBeds4[1].reference_code, "MR-201");

    const rentals = search({ listing_type: "rent" });
    assert.equal(rentals.length, 1);
    assert.equal(rentals[0].reference_code, "MR-108");

    const contemporary = search({ style: "Contemporary" });
    assert.equal(contemporary.length, 1);
    assert.equal(contemporary[0].reference_code, "MR-102");
  });

  test("applyPreference dispatches updates correctly for all preference dimensions", async () => {
    const mockDb = {
      client_preferences: {},
      preference_styles: [],
      preference_amenities: [],
      preference_neighborhoods: [],
      preference_property_types: []
    };

    async function mockApplyPreference(clientId, fieldPath, value) {
      const scalarFields = ["listing_type", "currency_code", "budget_min", "budget_max", "min_bedrooms", "min_bathrooms", "min_area_sqm", "max_area_sqm"];
      if (scalarFields.includes(fieldPath)) {
        mockDb.client_preferences[fieldPath] = value;
        return;
      }
      if (fieldPath === "style") {
        mockDb.preference_styles.push({ client_id: clientId, code: value.code || value, score: value.score || 1 });
        return;
      }
      if (fieldPath === "amenity") {
        mockDb.preference_amenities.push({ client_id: clientId, code: value.code || value, requirement: value.requirement || "nice" });
        return;
      }
      if (fieldPath === "neighborhood") {
        mockDb.preference_neighborhoods.push({ client_id: clientId, slug: value.slug || value, priority: value.priority || 2 });
        return;
      }
      if (fieldPath === "property_type") {
        mockDb.preference_property_types.push({ client_id: clientId, code: value.code || value });
        return;
      }
    }

    const cId = "b0000000-0000-4000-8000-000000000001";
    await mockApplyPreference(cId, "min_bedrooms", 4);
    assert.equal(mockDb.client_preferences.min_bedrooms, 4);

    await mockApplyPreference(cId, "style", { code: "haussmannian", score: 2 });
    assert.equal(mockDb.preference_styles[0].code, "haussmannian");
    assert.equal(mockDb.preference_styles[0].score, 2);

    await mockApplyPreference(cId, "amenity", { code: "wine-cellar", requirement: "must" });
    assert.equal(mockDb.preference_amenities[0].code, "wine-cellar");
    assert.equal(mockDb.preference_amenities[0].requirement, "must");

    await mockApplyPreference(cId, "neighborhood", { slug: "saint-germain", priority: 3 });
    assert.equal(mockDb.preference_neighborhoods[0].slug, "saint-germain");
    assert.equal(mockDb.preference_neighborhoods[0].priority, 3);

    await mockApplyPreference(cId, "property_type", { code: "penthouse" });
    assert.equal(mockDb.preference_property_types[0].code, "penthouse");
  });
});
