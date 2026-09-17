import assert from "node:assert/strict";
import test from "node:test";
import {
  aiResultSchema,
  estimateLineReviewDecisionSchema,
  PROHIBITED_AUTOMATIONS,
  supplementComparisonSchema,
} from "../dist/index.js";

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

test("estimate verification accepts only explicit human review decisions", () => {
  assert.equal(estimateLineReviewDecisionSchema.parse("corrected"), "corrected");
  assert.throws(() => estimateLineReviewDecisionSchema.parse("auto_approved"));
});

test("clear coat exclusions cannot become supplement candidates", () => {
  assert.throws(() => supplementComparisonSchema.parse({
    comparisonStatus: "automatic_operation_excluded",
    matchMethod: "none",
    matchedEstimateLineId: null,
    confidence: 0.99,
    sourceQuality: "mixed",
    evidenceIds: ["00000000-0000-0000-0000-000000000001"],
    reason: "Clear coat is automatically included.",
    limitations: [],
    humanReviewRequired: true,
    canCreateSupplementCandidate: true,
  }));
});
