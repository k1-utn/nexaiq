import { z } from "zod";

export const humanDecisionSchema = z.enum([
  "pending_review",
  "confirmed",
  "dismissed",
  "needs_review",
  "escalated",
]);

export const loginCredentialsSchema = z.object({
  email: z.email().trim().toLowerCase(),
  password: z.string().min(1).max(1024),
});

export const aiResultSchema = z.object({
  findingType: z.string().min(1),
  confidence: z.number().min(0).max(1),
  sourceQuality: z.enum(["source_document", "camera_only", "mixed", "unknown"]),
  humanReviewRequired: z.literal(true),
  evidenceIds: z.array(z.string().uuid()),
  reason: z.string().min(1),
  limitations: z.array(z.string()),
});

export type AiResult = z.infer<typeof aiResultSchema>;
export type HumanDecision = z.infer<typeof humanDecisionSchema>;

export const estimateLineReviewDecisionSchema = z.enum([
  "confirmed",
  "corrected",
  "excluded",
  "needs_review",
]);

export type EstimateLineReviewDecision = z.infer<
  typeof estimateLineReviewDecisionSchema
>;

export const PRODUCT_LANGUAGE = {
  candidate: "Potential finding",
  supplement: "Possible supplement candidate",
  review: "Estimator review required",
  critical: "Critical review required",
  source: "Source verification required",
  evidence: "Evidence not documented",
  signoff: "Qualified-person sign-off required",
} as const;

export const PROHIBITED_AUTOMATIONS = [
  "approve_structural_repair",
  "approve_weld_quality",
  "approve_calibration",
  "submit_supplement",
  "modify_estimate",
  "release_vehicle",
  "sign_final_qc",
] as const;
