import assert from "node:assert/strict";
import test from "node:test";
import { aiResultSchema, PROHIBITED_AUTOMATIONS } from "../dist/index.js";

test("material AI results always require human review", () => {
  assert.throws(() => aiResultSchema.parse({
    findingType: "possible_component_damage",
    confidence: 0.81,
    sourceQuality: "camera_only",
    humanReviewRequired: false,
    evidenceIds: [],
    reason: "Possible deformation",
    limitations: ["Partially obscured"],
  }));
});

test("high-impact automation denylist includes supplement submission", () => {
  assert.ok(PROHIBITED_AUTOMATIONS.includes("submit_supplement"));
});
